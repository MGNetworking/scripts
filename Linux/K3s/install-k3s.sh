#!/usr/bin/env bash
set -Eeuo pipefail

# Installe K3s mono-nœud (décision 23) par l'installateur officiel get.k3s.io.
# N'écrit aucune configuration — c'est configure-k3s.sh — et ne lit ni n'affiche
# le jeton du nœud, qui vit sous /var/lib/rancher/k3s.

_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_dir/lib/common.sh" ] && [ "$_dir" != "/" ]; do _dir="$(dirname "$_dir")"; done
source "$_dir/lib/common.sh"

# Décision 45 : un parent qui exporte ASSUME_YES ne confirme pas à ma place.
export ASSUME_YES="false"

DRY_RUN="false"
OUI="false"
URL_INSTALLATEUR="https://get.k3s.io"
# 6443 : API du serveur. 80 et 443 : Traefik, conservé par la décision 23 — déjà
# pris par le reverse proxy Docker sur le premier serveur (backlog §1).
PORTS_REQUIS="6443 80 443"
# Planchers repris de la documentation K3s, non mesurés dans ce dépôt.
MIN_DISQUE_MO=5120
MIN_MEMOIRE_MO=512

usage() {
    cat <<'EOF'
install-k3s.sh — installe K3s mono-nœud depuis l'installateur officiel.

Usage : install-k3s.sh [--dry-run] [-y|--yes] [--help]

  --dry-run   affiche le préflight et la commande prévue, sans rien télécharger
  -y, --yes   ne pose aucune question (obligatoire hors terminal)

Systèmes supportés : Debian 12 et 13, Ubuntu 22.04 et 24.04 LTS, sur amd64 ou
arm64 (décision 14). Toute autre distribution ou architecture est refusée.

Ce que le script modifie : K3s, par https://get.k3s.io en HTTPS seulement.
L'installateur part dans un fichier temporaire, exécuté puis retiré — jamais
« curl | sh ». Le service k3s est activé, puis Linux/K3s/verify-k3s.sh dit si le
cluster répond. Version : le canal stable, ou celle qu'épingle SRV_K3S_VERSION
dans config/server.env.

Codes de retour :
  0  K3s est installé et le diagnostic passe, ou l'était déjà
  1  système non supporté, ressources insuffisantes, get.k3s.io injoignable,
     port requis occupé, privilège manquant, installateur ou diagnostic en échec
  2  option inconnue
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

[ "$DRY_RUN" = "true" ] || { require_root; enable_full_logging; }

require_os debian ubuntu
case "$OS_ID $OS_VERSION" in
    "debian 12"|"debian 13"|"ubuntu 22.04"|"ubuntu 24.04") ;;
    *) die "Version non supportée : $OS_ID $OS_VERSION (attendu : Debian 12/13, Ubuntu 22.04/24.04)" ;;
esac
case "$OS_ARCH" in
    x86_64)  ARCH="amd64" ;;
    aarch64) ARCH="arm64" ;;
    *) die "Architecture non supportée : $OS_ARCH (attendu : x86_64 ou aarch64)" ;;
esac
require_cmd systemctl curl
if command -v k3s >/dev/null 2>&1; then
    success "K3s est déjà installé : $(k3s --version 2>/dev/null | head -n1 || echo 'version illisible')"
    info "Ce script ne réinstalle rien. Configurer relève de Linux/K3s/configure-k3s.sh."
    exit 0
fi
DISQUE_MO="$(df -Pm /var/lib 2>/dev/null | awk 'NR==2 {print $4}')"
if [ -z "${DISQUE_MO:-}" ]; then
    warn "Espace libre sous /var/lib illisible : le contrôle du disque n'a pas été fait."
elif [ "$DISQUE_MO" -lt "$MIN_DISQUE_MO" ]; then
    die "Espace insuffisant sous /var/lib : ${DISQUE_MO} Mo libres, ${MIN_DISQUE_MO} Mo requis. Rien n'a été installé."
fi

# Sous le minimum, K3s démarre encore : c'est un avertissement, jamais un refus.
MEMOIRE_MO="$(awk '/^MemTotal:/ {print int($2/1024)}' /proc/meminfo 2>/dev/null || true)"
if [ -n "${MEMOIRE_MO:-}" ] && [ "$MEMOIRE_MO" -lt "$MIN_MEMOIRE_MO" ]; then
    warn "Mémoire totale de ${MEMOIRE_MO} Mo, sous les ${MIN_MEMOIRE_MO} Mo conseillés par K3s : le serveur démarrera, les charges souffriront."
fi
info "Système : $OS_ID $OS_VERSION ($ARCH), ${DISQUE_MO:-?} Mo libres sous /var/lib, ${MEMOIRE_MO:-?} Mo de mémoire."

# HEAD suffit à prouver que l'hôte répond en HTTPS ; le script n'est téléchargé
# qu'une fois, plus bas. Décision 47 : HTTPS seul, sans empreinte épinglée.
if ! timeout 15 curl -fsS --head -o /dev/null "$URL_INSTALLATEUR"; then
    die "$URL_INSTALLATEUR injoignable en HTTPS : rien n'a été téléchargé ni installé."
fi
# ss -H -ltn : une ligne par écoute, sans en-tête, 4e colonne = adresse locale.
OCCUPES=""
if command -v ss >/dev/null 2>&1; then
    OCCUPES="$(ss -H -ltn 2>/dev/null | awk '{print $4}' | sed 's/.*://' | sort -u || true)"
else
    warn "ss absent : les ports $PORTS_REQUIS n'ont pas été vérifiés."
fi
CONFLITS=""
for port in $PORTS_REQUIS; do
    case " $OCCUPES " in *" $port "*) CONFLITS="$CONFLITS $port" ;; esac
done
if [ -n "$CONFLITS" ]; then
    die "Port(s) déjà en écoute :${CONFLITS} — K3s a besoin de 6443, et de 80 et 443 pour Traefik. Rien n'a été installé."
fi

VERSION="stable (canal par défaut de l'installateur)"
if [ -n "${SRV_K3S_VERSION:-}" ]; then
    VERSION="$SRV_K3S_VERSION (épinglée)"
    export INSTALL_K3S_VERSION="$SRV_K3S_VERSION"
fi
printf '\nChangements prévus\n'
printf '  Installateur           %s, en HTTPS\n' "$URL_INSTALLATEUR"
printf '  Version                %s\n' "$VERSION"
printf '  Service                k3s, activé, puis diagnostic verify-k3s.sh\n\n'

if [ "$DRY_RUN" = "true" ]; then
    info "[dry-run] Commande prévue : curl -fsSL $URL_INSTALLATEUR -o <temporaire>, puis ${SRV_K3S_VERSION:+INSTALL_K3S_VERSION=$SRV_K3S_VERSION }sh <temporaire>"
    info "[dry-run] Aucun téléchargement, aucune écriture : rien n'a été installé."
    exit 0
fi

[ -t 0 ] || [ "$OUI" = "true" ] \
    || die "Installation à confirmer, et aucun terminal n'est disponible. Relancer avec --yes."
confirm "Installer K3s ($VERSION) sur cette machine ?" || die "Installation abandonnée."

# Jamais « curl | sh » : un tube ne rend pas le code de curl à sh, et le script
# exécuté ne serait ni relisible ni rejouable.
TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT
if ! curl -fsSL --max-time 120 -o "$TMP" "$URL_INSTALLATEUR" || [ ! -s "$TMP" ]; then
    die "Installateur irrécupérable depuis $URL_INSTALLATEUR : rien n'a été installé."
fi
if ! run_logged sh "$TMP"; then
    die "L'installateur K3s a échoué : l'état de la machine est incertain. Relancer ce script, qui ne réinstalle pas un K3s présent."
fi
run_logged systemctl enable k3s

# La version et l'état du service sont ceux que verify-k3s.sh relève ensuite.
printf '\nVérification : %s\n\n' "$(k3s --version 2>/dev/null | head -n1 || echo 'version non disponible')"
if ! bash "$SCRIPTS_ROOT/Linux/K3s/verify-k3s.sh"; then
    die "K3s est installé, mais le diagnostic ci-dessus ne passe pas."
fi
success "K3s installé et cluster sain."
info "Configuration du serveur : Linux/K3s/configure-k3s.sh."
