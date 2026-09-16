#!/usr/bin/env bash
set -Eeuo pipefail

# Installe Helm 4 (plan §5) par le script officiel get-helm-4, qui vérifie
# lui-même la sha256 de l'archive. Ni plugin, ni dépôt de charts : et un Helm
# déjà présent est constaté, jamais mis à niveau.

_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_dir/lib/common.sh" ] && [ "$_dir" != "/" ]; do _dir="$(dirname "$_dir")"; done
source "$_dir/lib/common.sh"

# Décision 45 : un parent qui exporte ASSUME_YES ne confirme pas à ma place.
export ASSUME_YES="false"
# Ces variables héritées détourneraient get-helm-4 de l'installation annoncée
# au résumé. La vérification sha256, elle, est reposée explicitement : jamais
# désactivée.
unset VERIFY_CHECKSUM USE_SUDO HELM_INSTALL_DIR BINARY_NAME DESIRED_VERSION DEBUG
export VERIFY_CHECKSUM="true"

DRY_RUN="false"
OUI="false"
URL_INSTALLATEUR="https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-4"

usage() {
    cat <<'EOF'
install-helm.sh — installe Helm 4 par le script officiel get-helm-4.

Usage : install-helm.sh [--dry-run] [-y|--yes] [--help]

  --dry-run   préflight local et commande prévue, sans réseau ni écriture
  -y, --yes   ne pose aucune question (obligatoire hors terminal)

Systèmes supportés : Debian 12 et 13, Ubuntu 22.04 et 24.04 LTS, sur amd64 ou
arm64 (décision 14). Toute autre distribution ou architecture est refusée.

get-helm-4 part dans un fichier temporaire, exécuté puis retiré — jamais
« curl | sh » — et en HTTPS seulement. Il vérifie la sha256 de l'archive et
élève par sudo vers /usr/local/bin : ce script n'exige donc pas root. Version :
la dernière publiée, ou celle qu'épingle SRV_HELM_VERSION dans config/server.env.

Codes de retour :
  0  Helm est installé et sa version relue, ou l'était déjà
  1  système non supporté, curl ou openssl absent, get-helm-4 irrécupérable ou
     en échec, version installée absente ou différente de celle épinglée
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

[ "$DRY_RUN" = "true" ] || enable_full_logging

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
require_cmd curl openssl

if command -v helm >/dev/null 2>&1; then
    success "Helm est déjà installé : $(helm version --short 2>/dev/null || echo 'version illisible')"
    info "Ce script ne met rien à niveau. Un dépôt de charts s'ajoute par « helm repo add »."
    exit 0
fi

# « v4.0.0+g3fc9f4b » et « 4.0.0 » désignent la même version : ni « v », ni
# métadonnée de construction, la comparaison porte sur le numéro seul.
normaliser() { local v="${1%%+*}"; printf '%s' "${v#v}"; }

if [ -n "${SRV_HELM_VERSION:-}" ]; then
    VERSION="$SRV_HELM_VERSION (épinglée)"
else
    VERSION="dernière publiée"
fi
printf '\nChangements prévus\n'
printf '  Installateur           %s, en HTTPS\n' "$URL_INSTALLATEUR"
printf '  Version                %s\n' "$VERSION"
printf '  Destination            /usr/local/bin/helm, par le sudo de get-helm-4\n\n'

if [ "$DRY_RUN" = "true" ]; then
    info "[dry-run] Commande prévue : curl -fsSL $URL_INSTALLATEUR -o <temporaire> --proto '=https' --tlsv1.2, puis sh <temporaire>${SRV_HELM_VERSION:+ --version $SRV_HELM_VERSION}"
    info "[dry-run] Préflight local seul : aucune requête réseau, aucune écriture. Rien n'a été installé."
    exit 0
fi

[ -t 0 ] || [ "$OUI" = "true" ] \
    || die "Installation à confirmer, et aucun terminal n'est disponible. Relancer avec --yes."
confirm "Installer Helm ($VERSION) sur cette machine ?" || die "Installation abandonnée."

# Jamais « curl | sh » : un tube ne rend pas le code de curl à sh, et le script
# exécuté ne serait ni relisible ni rejouable.
TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT
if ! curl -fsSL --max-time 120 --proto '=https' --tlsv1.2 -o "$TMP" "$URL_INSTALLATEUR" || [ ! -s "$TMP" ]; then
    die "Téléchargement de get-helm-4 en échec depuis $URL_INSTALLATEUR : rien n'a été installé."
fi

ECHEC=""
if [ -n "${SRV_HELM_VERSION:-}" ]; then
    run_logged sh "$TMP" --version "$SRV_HELM_VERSION" || ECHEC="oui"
else
    run_logged sh "$TMP" || ECHEC="oui"
fi
[ -z "$ECHEC" ] || die "get-helm-4 a échoué : l'état de la machine est incertain. Relancer ce script, qui ne réinstalle pas un Helm présent."

INSTALLEE="$(helm version --short 2>/dev/null || true)"
[ -n "$INSTALLEE" ] || die "Helm a été installé, mais « helm version --short » ne rend rien : la version n'est pas prouvée."
if [ -n "${SRV_HELM_VERSION:-}" ] \
   && [ "$(normaliser "$INSTALLEE")" != "$(normaliser "$SRV_HELM_VERSION")" ]; then
    die "Version relue $INSTALLEE, différente de celle épinglée ($SRV_HELM_VERSION)."
fi
success "Helm $INSTALLEE est installé."
