#!/usr/bin/env bash
set -Eeuo pipefail

# Ramène le cluster à une seule StorageClass par défaut : la cible. Seule
# l'annotation par défaut est touchée ; aucune classe n'est créée ni supprimée.
_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_dir/lib/common.sh" ] && [ "$_dir" != "/" ]; do _dir="$(dirname "$_dir")"; done
source "$_dir/lib/common.sh"

DELAI=10        # --request-timeout de chaque appel kubectl, en secondes
MARGE=2         # « timeout » qui l'entoure : le laisser écrire son message
CLE="storageclass.kubernetes.io/is-default-class"
# Le point de la clé est échappé : sans lui, kubectl le lit comme un chemin d'objet.
JP='{range .items[*]}{.metadata.name}{" "}{.metadata.annotations.storageclass\.kubernetes\.io/is-default-class}{"\n"}{end}'
DRY_RUN="false"; OUI="false"
# Décision 45 : un parent qui exporte ASSUME_YES ne confirme pas à ma place.
export ASSUME_YES="false"
# Surcharge de test, lue avant tout trap et toute écriture de fichier.
if [ -e /.dockerenv ] && [ -n "${DELAI_TEST:-}" ]; then DELAI="$DELAI_TEST"; fi

usage() {
    cat <<'EOF'
configure-storage.sh — ramène le cluster à une seule StorageClass par défaut.

Usage : configure-storage.sh [--dry-run] [-y|--yes] [--help]

  --dry-run    affiche les annotations qui changeraient, sans rien annoter
  -y, --yes    ne pose aucune question (obligatoire hors terminal)

La classe cible est SRV_K8S_STORAGE_CLASS (config/server.env), local-path à
défaut. Elle doit exister dans le cluster : le script n'en crée aucune. Les
autres classes marquées par défaut voient leur annotation ramenée à « false » —
elle n'est jamais supprimée, seule sa valeur change, et rien n'est créé,
supprimé ni réappliqué. La cible est marquée AVANT que les autres soient
démarquées : le cluster ne passe jamais par zéro classe par défaut.

K3s réapplique ses manifestes intégrés au démarrage, dont local-path et sa
marque par défaut : ce que ce script retire peut revenir au redémarrage de K3s.
Il n'y remédie pas ; sa vérification finale signale l'écart si l'état a dérivé.
kubectl résout seul son kubeconfig (KUBECONFIG, sinon ~/.kube/config).

Codes de retour :
  0  la cible est la seule classe par défaut, ou l'était déjà ; ou --dry-run
  1  kubectl absent, apiserver injoignable, droits insuffisants, kubeconfig
     invalide, délai dépassé, cible absente du cluster, confirmation refusée,
     annotation ou relecture en échec
  2  option inconnue, ou nom de classe mal formé
EOF
}

while [ "${1:-}" != "" ]; do
    case "$1" in
        --dry-run) DRY_RUN="true"; shift ;;
        -y|--yes)  export ASSUME_YES="true"; OUI="true"; shift ;;
        --help|-h) usage; exit 0 ;;
        *) die "Option inconnue : $1" 2 ;;
    esac
done

# RFC 1123, jugé avant tout appel : sinon kubectl lirait le nom comme une option.
CIBLE="${SRV_K8S_STORAGE_CLASS:-local-path}"
case "$CIBLE" in
    ""|*[!a-z0-9.-]*) die "Nom de StorageClass mal formé : « $CIBLE » — minuscules, chiffres, « - » et « . » attendus." 2 ;;
    [!a-z0-9]*|*[!a-z0-9]|*..*|*--*|*.-*|*-.*) die "Nom de StorageClass mal formé : « $CIBLE » — un label RFC 1123 commence et finit par un caractère alphanumérique, sans séparateur doublé." 2 ;;
esac
[ "${#CIBLE}" -le 253 ] || die "Nom de StorageClass trop long : « $CIBLE » — 253 caractères au plus." 2

command -v kubectl >/dev/null 2>&1 || die "kubectl est introuvable dans le PATH : voir Kubernetes/Installation/install-kubectl.sh (TASK-062)."
require_cmd timeout
TEMPORAIRE="$(mktemp -d)" || die "Répertoire temporaire indisponible."
trap 'rm -rf "$TEMPORAIRE"' EXIT

# REP — stdout — et ERREUR — stderr, tenu à part : un avertissement mêlé à une
# lecture serait pris pour une donnée.
REP=""; ERREUR=""; CODE=0
appel() {   # <verbe kubectl...>
    CODE=0
    REP="$(timeout "$((DELAI + MARGE))" kubectl "$@" --request-timeout="${DELAI}s" 2>"$TEMPORAIRE/erreur")" || CODE=$?
    ERREUR="$(cat "$TEMPORAIRE/erreur")"
}

# Traduit l'échec du dernier appel : le 124 vient de « timeout », pas du cluster.
echec() {   # <appel> : n'est appelée que pour une lecture, et sort en 1
    [ -z "$ERREUR" ] || printf '%s\n' "$ERREUR" | sed 's/^/  /' >&2
    case "$CODE:$ERREUR" in
        124:*) die "L'appel $1 a été interrompu : délai dépassé (${DELAI} s)." ;;
        *Forbidden*) die "Droits insuffisants : $1 a été refusé par le cluster." ;;
        *Unauthorized*|*x509*|*"error loading config file"*) die "Kubeconfig invalide ou périmé : $1 a été refusé." ;;
        *NotFound*) die "Ressource absente du cluster : $1 a échoué." ;;
        *"connection refused"*|*"was refused"*|*"Unable to connect"*|*"no such host"*|*"i/o timeout"*) die "L'apiserver est injoignable : $1 a échoué. Vérifier l'accès par install-kubectl.sh (TASK-062)." ;;
        *) die "Échec de $1. La cause est dans le message ci-dessus : le cluster a répondu, et a refusé." ;;
    esac
}

# Un seul relevé sert au compte, à la présence de la cible et aux marques posées.
relever() {
    appel get storageclass -o "jsonpath=$JP"
    [ "$CODE" = 0 ] || echec "« kubectl get storageclass »"
    printf '%s\n' "$REP" | grep . > "$TEMPORAIRE/etat" || true
    TOTAL="$(grep -c . "$TEMPORAIRE/etat" || true)"
    awk '{print $1}' "$TEMPORAIRE/etat" > "$TEMPORAIRE/noms"
    awk '$2 == "true" {print $1}' "$TEMPORAIRE/etat" > "$TEMPORAIRE/defaut"
}

relever
AVANT="$TOTAL"
grep -qxF "$CIBLE" "$TEMPORAIRE/noms" || die "La classe cible « $CIBLE » est absente du cluster ($TOTAL classe(s) : $(tr '\n' ' ' < "$TEMPORAIRE/noms")). Rien n'a été modifié, et ce script n'en crée aucune : la renseigner dans SRV_K8S_STORAGE_CLASS, ou l'installer d'abord." 1

if [ "$(grep -c . "$TEMPORAIRE/defaut" || true)" = 1 ] && grep -qxF "$CIBLE" "$TEMPORAIRE/defaut"; then
    success "« $CIBLE » est déjà la seule StorageClass par défaut : aucun changement."
    exit 0
fi

# Plan d'annotations, cible en tête : jamais zéro classe par défaut, même si un démarquage échoue.
PLAN=()
grep -qxF "$CIBLE" "$TEMPORAIRE/defaut" || PLAN+=("$CIBLE=true")
mapfile -t DEMARQ < <(grep -vxF "$CIBLE" "$TEMPORAIRE/defaut")
for d in "${DEMARQ[@]}"; do PLAN+=("$d=false"); done
VOULEES="${#PLAN[@]}"
printf '\nAnnotations à changer (%s) :\n' "$VOULEES"
for a in "${PLAN[@]}"; do printf '  %s  %s=%s\n' "${a%%=*}" "$CLE" "${a##*=}"; done
[ "$VOULEES" -le 1 ] || info "« $CIBLE » est annotée en premier : le cluster ne passe jamais par zéro classe par défaut."

if [ "$DRY_RUN" = "true" ]; then
    info "[dry-run] kubectl annotate n'a pas été appelé : rien n'a été modifié."
    exit 0
fi
[ -t 0 ] || [ "$OUI" = "true" ] || die "Annotations à confirmer, et aucun terminal n'est disponible. Relancer avec --yes." 1
confirm "Appliquer ces $VOULEES annotation(s) ? « $CIBLE » restera la seule StorageClass par défaut." || die "Configuration abandonnée : rien n'a été modifié." 1

FAITES=0
for a in "${PLAN[@]}"; do
    n="${a%%=*}"; v="${a##*=}"
    appel annotate storageclass "$n" "$CLE=$v" --overwrite
    if [ "$CODE" != 0 ]; then
        printf '%s\n' "$ERREUR" | sed 's/^/  /' >&2
        [ "$CODE" != 124 ] || error "Annotation de « $n » interrompue : délai dépassé (${DELAI} s sur kubectl annotate)."
        error "Bilan : $FAITES annotation(s) appliquée(s), $((VOULEES - FAITES)) non appliquée(s). Restaient : ${PLAN[*]:FAITES}. « $CIBLE » n'est peut-être pas la seule classe par défaut."
        exit 1
    fi
    printf '%s\n' "$REP" | sed 's/^/  /'
    FAITES=$((FAITES + 1))
done

relever
[ "$TOTAL" = "$AVANT" ] || die "Relecture : $TOTAL StorageClass dans le cluster, $AVANT avant les annotations — le nombre a changé, or ce script n'en crée ni n'en supprime aucune." 1
if [ "$(grep -c . "$TEMPORAIRE/defaut" || true)" != 1 ] || ! grep -qxF "$CIBLE" "$TEMPORAIRE/defaut"; then
    die "Relecture : $(grep -c . "$TEMPORAIRE/defaut" || true) classe(s) par défaut ($(tr '\n' ' ' < "$TEMPORAIRE/defaut")) — « $CIBLE » seule était attendue. Si une classe a repris sa marque, K3s a pu réappliquer ses manifestes au redémarrage : relancer ce script." 1
fi
success "« $CIBLE » est la seule StorageClass par défaut ($FAITES annotation(s) changée(s), $TOTAL classe(s) au total). Aucune classe n'a été créée ni supprimée."
