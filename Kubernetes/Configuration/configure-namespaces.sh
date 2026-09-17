#!/usr/bin/env bash
set -Eeuo pipefail

# Crée les namespaces communs du cluster listés dans SRV_K8S_NAMESPACES, par
# kubectl apply. Rien n'est supprimé ni modifié : un namespace déjà présent est
# laissé tel quel, et n'est pas réappliqué.
_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_dir/lib/common.sh" ] && [ "$_dir" != "/" ]; do _dir="$(dirname "$_dir")"; done
source "$_dir/lib/common.sh"

DELAI=10        # --request-timeout de chaque appel kubectl, en secondes
MARGE=2         # « timeout » qui l'entoure : le laisser écrire son message
DRY_RUN="false"
# Surcharge de test, lue avant tout trap et toute écriture de fichier.
if [ -e /.dockerenv ] && [ -n "${DELAI_TEST:-}" ]; then DELAI="$DELAI_TEST"; fi

usage() {
    cat <<'EOF'
configure-namespaces.sh — crée les namespaces communs du cluster.

Usage : configure-namespaces.sh [--dry-run] [-y|--yes] [--help]

  --dry-run    affiche les namespaces à créer, sans rien appliquer
  -y, --yes    ne pose aucune question (obligatoire hors terminal)

La liste vient de SRV_K8S_NAMESPACES (config/server.env), noms séparés par des
virgules. Chaque nom est un label DNS-1123 : minuscules, chiffres et « - », 63
caractères au plus. Les namespaces que Kubernetes réserve — default,
kube-system, kube-public, kube-node-lease et tout préfixe kube- — sont refusés
dans la liste : ce script ne les crée ni ne les touche. Les namespaces déjà
présents ne sont ni modifiés ni réappliqués, et rien n'est jamais supprimé.
kubectl résout seul son kubeconfig (KUBECONFIG, sinon ~/.kube/config).

Codes de retour :
  0  tous les namespaces de la liste existent, ou viennent d'être créés ;
     ou --dry-run
  1  kubectl absent, apiserver injoignable, droits insuffisants, kubeconfig
     invalide, délai dépassé, confirmation refusée, création en échec
  2  option inconnue, ou SRV_K8S_NAMESPACES absente, vide ou mal formée
EOF
}

while [ "${1:-}" != "" ]; do
    case "$1" in
        --dry-run) DRY_RUN="true"; shift ;;
        -y|--yes)  export ASSUME_YES="true"; shift ;;
        --help|-h) usage; exit 0 ;;
        *) die "Option inconnue : $1" 2 ;;
    esac
done

# La liste est jugée entièrement avant tout appel : un nom douteux irait sinon
# jusqu'à kubectl, qui le lirait comme une option.
LISTE="${SRV_K8S_NAMESPACES:-}"
[ -n "$LISTE" ] || die "Liste des namespaces absente : renseigner SRV_K8S_NAMESPACES dans config/server.env (modèle : config/server.env.example). Rien n'a été tenté." 2
case "$LISTE" in
    ,*|*,|*,,*) die "Liste mal formée dans SRV_K8S_NAMESPACES : entrée vide (virgule en tête ou en trop). Rien n'a été tenté." 2 ;;
    *[[:space:]]*) die "Liste mal formée dans SRV_K8S_NAMESPACES : blanc ou retour à la ligne (read n'en lirait que la première). Rien n'a été tenté." 2 ;;
esac

IFS=',' read -r -a VOULUS <<< "$LISTE"
VUS=","
for n in "${VOULUS[@]}"; do
    case "$n" in
        default|kube-*) die "Namespace réservé par Kubernetes : « $n » — à retirer de SRV_K8S_NAMESPACES. Rien n'a été tenté." 2 ;;
        *[!a-z0-9-]*|[!a-z0-9]*|*[!a-z0-9]) die "Nom mal formé dans SRV_K8S_NAMESPACES : « $n » — minuscules, chiffres et « - » attendus, sans espace. Rien n'a été tenté." 2 ;;
    esac
    [ "${#n}" -le 63 ] || die "Nom trop long dans SRV_K8S_NAMESPACES : « $n » — 63 caractères au plus. Rien n'a été tenté." 2
    case "$VUS" in *",$n,"*) die "Doublon dans SRV_K8S_NAMESPACES : « $n ». Rien n'a été tenté." 2 ;; esac
    VUS="$VUS$n,"
done

command -v kubectl >/dev/null 2>&1 || die "kubectl est introuvable dans le PATH : voir Kubernetes/Installation/install-kubectl.sh (TASK-062)."
require_cmd timeout
TEMPORAIRE="$(mktemp -d)" || die "Répertoire temporaire indisponible."
trap 'rm -rf "$TEMPORAIRE"' EXIT

# REP — stdout — et ERREUR — stderr, tenu à part : un avertissement mêlé à une
# lecture serait pris pour une donnée.
REP=""; ERREUR=""; CODE=0
appel() {   # <stdin> <verbe kubectl...>
    local entree="$1"; shift
    CODE=0
    REP="$(timeout "$((DELAI + MARGE))" kubectl "$@" --request-timeout="${DELAI}s" < "$entree" 2>"$TEMPORAIRE/erreur")" || CODE=$?
    ERREUR="$(cat "$TEMPORAIRE/erreur")"
}

# Traduit l'échec du dernier appel : le 124 vient de « timeout », pas du cluster.
echec() {   # <appel> : n'est appelée que pour une lecture, et sort en 1
    [ -z "$ERREUR" ] || printf '%s\n' "$ERREUR" | sed 's/^/  /' >&2
    case "$CODE:$ERREUR" in
        124:*) die "L'appel $1 a été interrompu : délai dépassé (${DELAI} s)." ;;
        *Forbidden*) die "Droits insuffisants : $1 a été refusé par le cluster." ;;
        *Unauthorized*|*x509*|*"error loading config file"*) die "Kubeconfig invalide ou périmé : $1 a été refusé." ;;
        *"connection refused"*|*"was refused"*|*"Unable to connect"*|*"no such host"*|*"i/o timeout"*) die "L'apiserver est injoignable : $1 a échoué. Vérifier l'accès par install-kubectl.sh (TASK-062)." ;;
        *) die "Échec de $1. La cause est dans le message ci-dessus : le cluster a répondu, et a refusé." ;;
    esac
}

# Préflight et relevé en un seul appel : il prouve que l'API répond, et donne
# les namespaces existants.
appel /dev/null get namespaces -o name
[ "$CODE" = 0 ] || echec "« kubectl get namespaces -o name »"
printf '%s\n' "$REP" | sed -n 's|^namespace/||p' > "$TEMPORAIRE/existants"

A_CREER=()
for n in "${VOULUS[@]}"; do
    grep -qxF "$n" "$TEMPORAIRE/existants" || A_CREER+=("$n")
done
if [ "${#A_CREER[@]}" -eq 0 ]; then
    success "Les ${#VOULUS[@]} namespace(s) de SRV_K8S_NAMESPACES existent déjà : aucun changement."
    exit 0
fi

if [ "$DRY_RUN" = "true" ]; then
    printf '\nNamespaces à créer : %s sur %s\n' "${#A_CREER[@]}" "${#VOULUS[@]}"
    printf '  %s\n' "${A_CREER[@]}"
    info "[dry-run] kubectl apply n'a pas été appelé : rien n'a été créé."
    exit 0
fi
confirm "Créer ${#A_CREER[@]} namespace(s) : ${A_CREER[*]} ?" || die "Configuration abandonnée : rien n'a été créé." 1

CREES=(); ECHEC=""
for n in "${A_CREER[@]}"; do
    cat > "$TEMPORAIRE/namespace.yaml" <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: $n
  labels:
    app.kubernetes.io/managed-by: mgnetworking
EOF
    appel "$TEMPORAIRE/namespace.yaml" apply -f -
    # Un refus arrête la boucle : les suivants ne sont pas tentés, et le bilan
    # ci-dessous le dit plutôt que de laisser croire à une liste complète.
    if [ "$CODE" != 0 ]; then
        [ -z "$ERREUR" ] || printf '%s\n' "$ERREUR" | sed 's/^/  /' >&2
        [ "$CODE" != 124 ] || error "Création de « $n » interrompue : délai dépassé (${DELAI} s sur kubectl apply)."
        ECHEC="$n"
        break
    fi
    CREES+=("$n")
    printf '%s\n' "$REP" | sed 's/^/  /'
done

if [ -n "$ECHEC" ]; then
    error "Namespaces : ${#CREES[@]} créé(s), 1 échoué ($ECHEC), $(( ${#A_CREER[@]} - ${#CREES[@]} - 1 )) non tenté(s). La liste n'est pas complète."
    exit 1
fi
success "Namespaces créés : ${CREES[*]}. Rien n'a été supprimé."
