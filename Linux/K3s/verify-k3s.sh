#!/usr/bin/env bash
set -Eeuo pipefail

# Diagnostique un K3s mono-nœud, en lecture seule : aucune commande de ce script
# ne modifie l'état de la machine. L'absence de K3s est le cas nominal, pas une
# erreur — elle se constate et vaut 1. Sert de vérification finale à
# install-k3s.sh et upgrade-k3s.sh, qui lisent le code de retour.

_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_dir/lib/common.sh" ] && [ "$_dir" != "/" ]; do _dir="$(dirname "$_dir")"; done
source "$_dir/lib/common.sh"

DELAI=5

usage() {
    cat <<'EOF'
verify-k3s.sh — diagnostic d'un K3s mono-nœud, en lecture seule.

Usage : verify-k3s.sh [--help]

Rubriques, dans cet ordre : service k3s (systemctl is-active), version du
binaire, nœuds, pods de tous les namespaces, namespaces, événements Warning.
Toute commande passe par « k3s kubectl », jamais par un kubectl supposé
installé, et chaque appel est borné par --request-timeout : un apiserver muet
ne fige pas le diagnostic.

Un nœud qui n'est pas Ready, un pod qui n'est ni Running ni Succeeded, ou un
service k3s qui n'est pas actif sont nommés dans un [WARN]. Les événements
Warning s'affichent sans peser sur le verdict : un cluster sain en compte
d'anciens.

Codes de retour :
  0  K3s installé, cluster sain
  1  K3s absent, API muette, service inactif, nœud non Ready ou pod anormal
  2  option inconnue — seul cas de 2

Root est requis : /etc/rancher/k3s/k3s.yaml n'est lisible que par lui.
EOF
}

while [ "${1:-}" != "" ]; do
    case "$1" in
        --help|-h) usage; exit 0 ;;
        *) die "Option inconnue : $1" 2 ;;
    esac
done

require_root

info "Diagnostic du cluster K3s."

# Le binaire peut manquer alors que l'unité est là — PATH restreint, lien
# absent — : les deux sont donc cherchés séparément.
K3S_BIN=""
if command -v k3s >/dev/null 2>&1; then K3S_BIN="$(command -v k3s)"; fi

SYSTEMD="oui"; SERVICE="inactive"; UNITES=""
if ! command -v systemctl >/dev/null 2>&1; then
    SYSTEMD="non"
else
    # is-active rend 3 dès que le service n'est pas « active » : garder sa seule
    # sortie, et ne la remplacer que si elle est vide — sinon « inactive »
    # s'ajouterait à « failed » sur une seconde ligne.
    SERVICE="$(timeout "$DELAI" systemctl is-active k3s 2>/dev/null)" || true
    [ -n "$SERVICE" ] || SERVICE="inactive"
    UNITES="$(timeout "$DELAI" systemctl list-unit-files k3s.service 2>/dev/null || true)"
fi
UNITE="non"
case "$UNITES" in *k3s.service*) UNITE="oui" ;; esac

# Interroge k3s en bornant l'appel. Renseigne REP au lieu de l'afficher : une
# substitution de commande perdrait la variable dans un sous-shell.
REP=""
lire() {
    REP=""
    [ -n "$K3S_BIN" ] || return 1
    REP="$(timeout "$DELAI" "$K3S_BIN" "$@" 2>/dev/null || true)"
    [ -n "$REP" ]
}

kubectl_lire() { lire kubectl "$@" --request-timeout="${DELAI}s"; }

# Affiche ce que la commande a rendu, ou « non disponible ».
rubrique() {
    local titre="$1"; shift
    printf '\n%s\n' "$titre"
    if "$@" && [ -n "$REP" ]; then printf '%s\n' "$REP" | sed 's/^/  /'; else printf '  non disponible\n'; fi
}

printf '\nService k3s\n'
if [ "$SYSTEMD" = "non" ]; then printf '  non disponible — systemd absent\n'; else printf '  %s\n' "$SERVICE"; fi

rubrique "Version" lire --version
rubrique "Nœuds" kubectl_lire get nodes --no-headers

ANOMALIES=""
API="non"
if [ -n "$REP" ]; then
    API="oui"
    while read -r nom etat _; do
        [ -n "$nom" ] || continue
        case "$etat" in Ready) ;; *) ANOMALIES="$ANOMALIES nœud $nom ($etat);" ;; esac
    done <<<"$REP"
fi

rubrique "Pods (tous les namespaces)" kubectl_lire get pods -A --no-headers
if [ -n "$REP" ]; then
    # Un pod de Job achevé porte la phase Succeeded, que kubectl affiche
    # « Completed » : le compter comme anormal ferait échouer tout cluster
    # qui exécute des tâches planifiées.
    while read -r espace nom _ etat _; do
        [ -n "$nom" ] || continue
        case "$etat" in Running|Succeeded|Completed) ;; *) ANOMALIES="$ANOMALIES pod $espace/$nom ($etat);" ;; esac
    done <<<"$REP"
fi

rubrique "Namespaces" kubectl_lire get namespaces --no-headers
# L'API qui répond sans rendre d'événement Warning n'est pas une API muette :
# les deux cas se distinguent par l'état relevé sur les nœuds.
printf '\nÉvénements Warning\n'
if kubectl_lire get events -A --field-selector type=Warning; then
    printf '%s\n' "$REP" | sed 's/^/  /'
elif [ "$API" = "oui" ]; then
    printf '  aucun événement Warning\n'
else
    printf '  non disponible\n'
fi

printf '\nVerdict\n'
if [ -z "$K3S_BIN" ] && [ "$UNITE" = "non" ]; then
    error "K3s n'est pas installé sur cette machine : ni binaire « k3s », ni unité k3s.service."
    error "L'installation relève de Linux/K3s/install-k3s.sh."
    exit 1
fi
if [ "$API" != "oui" ]; then
    error "L'API du cluster ne répond pas : « k3s kubectl get nodes » n'a rien rendu."
    exit 1
fi
if [ "$SYSTEMD" = "oui" ] && [ "$SERVICE" != "active" ]; then
    ANOMALIES="$ANOMALIES service k3s $SERVICE;"
fi
if [ -n "$ANOMALIES" ]; then
    warn "Cluster NON sain :$ANOMALIES"
    exit 1
fi
if [ "$SYSTEMD" = "non" ]; then
    warn "systemd absent : l'état du service k3s n'a pas pu être vérifié."
fi
success "K3s est installé et le cluster est sain."
