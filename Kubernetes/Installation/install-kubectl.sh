#!/usr/bin/env bash
set -Eeuo pipefail

# Vérifie kubectl, en lecture seule : rien n'est installé, rien n'est écrit hors
# journal, aucun kubeconfig ouvert ni affiché. K3s pose kubectl et son k3s.yaml
# en 0600 ; ce script constate, et explique la copie à faire si elle manque.

_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_dir/lib/common.sh" ] && [ "$_dir" != "/" ]; do _dir="$(dirname "$_dir")"; done
source "$_dir/lib/common.sh"

DELAI=5   # --request-timeout de chaque appel, en secondes
MARGE=2   # « timeout » entoure l'appel et laisse kubectl écrire son message
usage() {
    cat <<'EOF'
install-kubectl.sh — vérifie kubectl et l'accès au cluster, en lecture seule.

Usage : install-kubectl.sh [--help]

Rien n'est installé : K3s pose kubectl et /etc/rancher/k3s/k3s.yaml. Sont
constatés dans l'ordre : présence de kubectl, architecture de la machine,
version du client, kubeconfig, accès au cluster, version du serveur.

Le kubeconfig est celui que kubectl résout seul — KUBECONFIG, sinon
~/.kube/config. Le script vérifie qu'il est lisible, ne l'ouvre jamais, et
affiche la copie à faire depuis /etc/rancher/k3s/k3s.yaml s'il manque. Root
n'est pas requis ; chaque appel est borné par --request-timeout (5 s).

Codes de retour :
  0  kubectl présent et cluster joignable — avertissements compris
  1  kubectl absent, kubeconfig absent ou illisible, apiserver injoignable,
     droits insuffisants ou délai dépassé
  2  option inconnue — seul cas de 2
EOF
}

while [ "${1:-}" != "" ]; do
    case "$1" in
        --help|-h) usage; exit 0 ;;
        *) die "Option inconnue : $1" 2 ;;
    esac
done

# require_cmd n'est pas employé pour kubectl : son message ne dit pas où K3s le
# pose, et c'est justement ce qu'un kubectl absent doit apprendre.
if ! command -v kubectl >/dev/null 2>&1; then
    error "kubectl est introuvable dans le PATH."
    error "K3s le pose lui-même : voir Linux/K3s/install-k3s.sh."
    exit 1
fi
require_cmd timeout

TEMPORAIRE="$(mktemp -d)" || die "Répertoire temporaire indisponible."
trap 'rm -rf "$TEMPORAIRE"' EXIT

REP=""; ERREUR=""; CODE=0
lire() {
    CODE=0
    REP="$(timeout "$((DELAI + MARGE))" kubectl "$@" --request-timeout="${DELAI}s" 2>"$TEMPORAIRE/erreur")" || CODE=$?
    ERREUR="$(cat "$TEMPORAIRE/erreur")"
    return "$CODE"
}

# Traduit l'échec d'un appel, la sortie d'erreur de kubectl comprise — montrée
# seulement là. Le 124 vient de « timeout », pas de kubectl : le dire
# « injoignable » accuserait le cluster à tort.
echec() {
    local appel="$1"
    [ -z "$ERREUR" ] || printf '%s\n' "$ERREUR" | sed 's/^/  /' >&2
    case "$CODE:$ERREUR" in
        124:*)       die "L'appel $appel a été interrompu : délai dépassé (${DELAI} s)." ;;
        *Forbidden*) die "Droits insuffisants : $appel a été refusé par le cluster." ;;
        *"was refused"*|*"Unable to connect"*|*"no route to host"*)
                     die "L'apiserver est injoignable : $appel a échoué." ;;
    esac
    # Posé hors de l'expansion : une apostrophe dans ${2:-…} vaut SC1011.
    die "${2:-L'apiserver n'a pas répondu : $appel a échoué.}"
}

# Rend le gitVersion du bloc demandé — clientVersion ou serverVersion —, vide s'il est absent.
version_de() {
    printf '%s\n' "$2" | awk -F'"' -v bloc="$1" '
        index($0, "\"" bloc "\"") { dedans = 1; next }
        dedans && /gitVersion/ { print $4; exit }'
}

ARCH="$(uname -m)"
case "$ARCH" in x86_64|amd64) ARCH_K8S="amd64" ;; aarch64|arm64) ARCH_K8S="arm64" ;; *) ARCH_K8S="" ;; esac
printf '\nArchitecture\n  %s%s\n' "$ARCH" "${ARCH_K8S:+ ($ARCH_K8S)}"
[ -n "$ARCH_K8S" ] || warn "Architecture $ARCH : les binaires Kubernetes ne sont publiés que pour amd64 et arm64."
printf '\nVersion du client\n'
lire version --client -o json
[ "$CODE" = 0 ] || echec "« kubectl version --client »"
V_CLIENT="$(version_de clientVersion "$REP")"
[ -n "$V_CLIENT" ] || die "La version du client est absente de la sortie de kubectl."
printf '  %s\n' "$V_CLIENT"
# KUBECONFIG peut porter plusieurs chemins séparés par « : » : le premier lisible suffit.
DERNIER=""
kubeconfig_lisible() {
    local chemin; local -a chemins; IFS=':' read -r -a chemins <<<"$1"
    for chemin in "${chemins[@]}"; do DERNIER="$chemin"; [ -f "$chemin" ] && [ -r "$chemin" ] && return 0; done
    return 1
}
printf '\nKubeconfig\n'
if [ -n "${KUBECONFIG:-}" ]; then
    kubeconfig_lisible "$KUBECONFIG" || {
        # Un chemin illisible et un chemin absent n'ont pas la même cause.
        [ -e "$DERNIER" ] && die "KUBECONFIG désigne un chemin illisible : $DERNIER"
        die "KUBECONFIG désigne un chemin absent : $DERNIER"
    }
    printf '  %s (KUBECONFIG)\n' "$DERNIER"
else
    KC="${HOME:-}/.kube/config"
    if [ ! -f "$KC" ] || [ ! -r "$KC" ]; then
        info "Aucun kubeconfig : ni KUBECONFIG défini, ni $KC. Copiez celui de K3s :"
        info "  install -d -m 0700 ~/.kube && sudo install -m 0600 /etc/rancher/k3s/k3s.yaml ~/.kube/config"
        die "Sans kubeconfig, kubectl ne peut pas joindre le cluster."
    fi
    printf '  %s\n' "$KC"
fi

printf '\nAccès au cluster\n'
lire get nodes --no-headers
[ "$CODE" = 0 ] || echec "« kubectl get nodes »"
# Un code 0 sans nœud n'est pas un accès prouvé : une rubrique vide interdit le [SUCCESS] (A78).
[ -n "$REP" ] || die "Le cluster ne rend aucun nœud : l'accès n'est pas prouvé."
printf '%s\n' "$REP" | sed 's/^/  /'

printf '\nVersions client et serveur\n'
lire version -o json
[ "$CODE" = 0 ] || echec "« kubectl version »"
V_SERVEUR="$(version_de serverVersion "$REP")"
[ -n "$V_SERVEUR" ] || die "La version du serveur est absente de la sortie de kubectl."
printf '  client %s, serveur %s\n' "$V_CLIENT" "$V_SERVEUR"

mineure() {   # v1.31.4+k3s1 -> 1.31 ; échoue si la forme n'est pas reconnue
    local v="${1#v}"; v="${v%%+*}"
    case "$v" in [0-9]*.[0-9]*) printf '%s' "${v%.*}" ;; *) return 1 ;; esac
}
# Écart admis entre client et serveur : une version mineure (décision 48). Le majeur
# entre dans le calcul ; l'écart n'est qu'un avertissement, jamais un échec.
if MC="$(mineure "$V_CLIENT")" && MS="$(mineure "$V_SERVEUR")"; then
    ECART=$(( (${MS%%.*} - ${MC%%.*}) * 100 + ${MS#*.} - ${MC#*.} ))
    [ "$ECART" -ge 0 ] || ECART=$(( -ECART ))
    [ "$ECART" -le 1 ] || warn "Écart de versions : client $V_CLIENT, serveur $V_SERVEUR — plus d'une version mineure."
else
    warn "Écart de versions non vérifié : « $V_CLIENT » ou « $V_SERVEUR » n'a pas la forme v<majeur>.<mineure>."
fi

success "kubectl $V_CLIENT est présent et le cluster répond — serveur $V_SERVEUR."
