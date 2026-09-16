#!/usr/bin/env bash
set -Eeuo pipefail

# Met K3s à niveau par l'installateur officiel get.k3s.io. La version cible est
# explicite et obligatoire : ce script ne vise jamais la dernière stable par
# défaut (décision 47). Ni config.yaml ni les charges de travail ne sont touchés.

_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_dir/lib/common.sh" ] && [ "$_dir" != "/" ]; do _dir="$(dirname "$_dir")"; done
source "$_dir/lib/common.sh"

# Décision 45 : un parent qui exporte ASSUME_YES ne confirme pas à ma place.
export ASSUME_YES="false"
# Un canal hérité détournerait l'installateur de la version annoncée au résumé.
unset INSTALL_K3S_CHANNEL K3S_URL K3S_TOKEN

DRY_RUN="false"
OUI="false"
CIBLE=""
URL_INSTALLATEUR="https://get.k3s.io"

usage() {
    cat <<'EOF'
upgrade-k3s.sh — met K3s à niveau vers une version explicite.

Usage : upgrade-k3s.sh --version vX.Y.Z+k3sN [--dry-run] [-y|--yes] [--help]

  --version <v>  version cible, obligatoire — ou SRV_K3S_VERSION dans
                 config/server.env ; jamais la dernière stable par défaut
  --dry-run      versions et commande prévue, sans téléchargement
  -y, --yes      ne pose aucune question (obligatoire hors terminal)

La cible est validée (vX.Y.Z+k3sN) puis comparée à la version en place : une
cible inférieure, ou qui saute plus d'une version mineure — écart que
Kubernetes ne supporte pas — est refusée. Le cluster doit être sain avant :
Linux/K3s/verify-k3s.sh est exécuté, et son échec interrompt tout.

L'installateur part dans un fichier temporaire, exécuté puis retiré — jamais
« curl | sh » — et en HTTPS seulement. verify-k3s.sh repasse après.

Codes de retour :
  0  mise à niveau faite, déjà à jour, ou simulée
  1  cible absente ou invalide, K3s absent, cible en recul ou trop lointaine,
     cluster malsain, privilège manquant, téléchargement, installateur, diagnostic
  2  option inconnue
EOF
}

while [ "${1:-}" != "" ]; do
    case "$1" in
        --version) [ "${2:-}" != "" ] || die "Option --version sans valeur." 2
                   CIBLE="$2"; shift 2 ;;
        --dry-run) DRY_RUN="true"; shift ;;
        -y|--yes)  export ASSUME_YES="true"; OUI="true"; shift ;;
        --help|-h) usage; exit 0 ;;
        *) die "Option inconnue : $1" 2 ;;
    esac
done
CIBLE="${CIBLE:-${SRV_K3S_VERSION:-}}"

if [ -z "$CIBLE" ]; then
    die "Version cible absente : --version vX.Y.Z+k3sN, ou SRV_K3S_VERSION dans config/server.env. Ce script ne vise jamais la dernière stable par défaut. Rien n'a été modifié." 1
fi
if [[ ! "$CIBLE" =~ ^v[0-9]+\.[0-9]+\.[0-9]+\+k3s[0-9]+$ ]]; then
    die "Version cible invalide : « $CIBLE » (forme attendue : vX.Y.Z+k3sN). Rien n'a été modifié." 1
fi

[ "$DRY_RUN" = "true" ] || require_root
require_cmd curl

K3S_BIN=""
if command -v k3s >/dev/null 2>&1; then K3S_BIN="$(command -v k3s)"; fi
if [ -z "$K3S_BIN" ]; then
    die "K3s n'est pas installé sur cette machine : il n'y a rien à mettre à niveau. L'installation relève de Linux/K3s/install-k3s.sh." 1
fi

version_lue() { "$K3S_BIN" --version 2>/dev/null | awk '/^k3s version/ {print $3}' || true; }

# vX.Y.Z+k3sN -> MAJEUR, MINEUR, PATCH et REVISION, la révision K3s comprise :
# v1.30.5+k3s1 est postérieure à v1.30.5+k3s0, et le recul se refuse aussi.
decouper() {
    local v="${1#v}" reste="${1#v*.}"
    MAJEUR="${v%%.*}"; MINEUR="${reste%%.*}"; PATCH="${reste#*.}"; PATCH="${PATCH%%+*}"
    REVISION="${1##*+k3s}"
}
# Rang comparable des trois nombres qui suivent la majeure, déjà réputée égale.
rang() { printf '%s' $(( MINEUR * 10000 + PATCH * 100 + REVISION )); }

ACTUELLE="$(version_lue)"
if [[ ! "$ACTUELLE" =~ ^v[0-9]+\.[0-9]+\.[0-9]+\+k3s[0-9]+$ ]]; then
    die "Version en place illisible : « ${ACTUELLE:-aucune} ». Rien n'a été modifié. Diagnostic : Linux/K3s/verify-k3s.sh." 1
fi
info "Version en place : $ACTUELLE"
info "Version cible   : $CIBLE"

if [ "$ACTUELLE" = "$CIBLE" ]; then
    success "K3s est déjà en $CIBLE : rien à faire, rien n'a été téléchargé."
    exit 0
fi

decouper "$ACTUELLE"; RANG_A="$(rang)"; A_MAJ="$MAJEUR"; A_MIN="$MINEUR"
decouper "$CIBLE";    RANG_C="$(rang)"; C_MAJ="$MAJEUR"; C_MIN="$MINEUR"
if [ "$C_MAJ" -ne "$A_MAJ" ]; then
    die "Changement de version majeure refusé : $ACTUELLE → $CIBLE. Rien n'a été modifié." 1
fi
if [ "$RANG_C" -lt "$RANG_A" ]; then
    die "Version cible inférieure à celle en place : $ACTUELLE → $CIBLE. Rien n'a été modifié." 1
fi
if [ "$C_MIN" -gt $((A_MIN + 1)) ]; then
    die "Version cible trop lointaine : $ACTUELLE → $CIBLE saute plus d'une version mineure, écart que Kubernetes ne supporte pas. Rien n'a été modifié." 1
fi

if ! bash "$SCRIPTS_ROOT/Linux/K3s/verify-k3s.sh"; then
    die "Le cluster n'est pas sain : la mise à niveau vers $CIBLE est refusée, et rien n'a été modifié." 1
fi

printf '\nChangements prévus\n'
printf '  Version actuelle       %s\n' "$ACTUELLE"
printf '  Version cible          %s\n' "$CIBLE"
printf '  Installateur           %s, en HTTPS\n' "$URL_INSTALLATEUR"
printf "  Service                k3s, redémarré par l'installateur, puis diagnostic verify-k3s.sh\n\n"

if [ "$DRY_RUN" = "true" ]; then
    info "[dry-run] Commande prévue : curl -fsSL $URL_INSTALLATEUR -o <temporaire> --proto '=https' --tlsv1.2, puis INSTALL_K3S_VERSION=$CIBLE sh <temporaire>"
    info "[dry-run] Aucun téléchargement, aucune écriture : K3s est toujours en $ACTUELLE."
    exit 0
fi

[ -t 0 ] || [ "$OUI" = "true" ] \
    || die "Mise à niveau à confirmer, et aucun terminal n'est disponible. Relancer avec --yes." 1
confirm "Mettre K3s à niveau de $ACTUELLE vers $CIBLE ?" || die "Mise à niveau abandonnée : rien n'a été modifié." 1

# Jamais « curl | sh » : un tube ne rend pas le code de curl à sh, et le script
# exécuté ne serait ni relisible ni rejouable. Décision 47 : HTTPS seul.
export INSTALL_K3S_VERSION="$CIBLE"
TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT
if ! curl -fsSL --max-time 120 --proto '=https' --tlsv1.2 -o "$TMP" "$URL_INSTALLATEUR" || [ ! -s "$TMP" ]; then
    die "Installateur irrécupérable depuis $URL_INSTALLATEUR : K3s est toujours en $ACTUELLE, rien n'a été modifié."
fi
if ! run_logged sh "$TMP"; then
    die "L'installateur K3s a échoué : l'état de la machine est incertain. Version en place : $(version_lue)."
fi

printf '\nVérification\n\n'
if ! bash "$SCRIPTS_ROOT/Linux/K3s/verify-k3s.sh"; then
    die "K3s ne répond pas après la mise à niveau. Version en place : $(version_lue). Retour arrière : Linux/K3s/install-k3s.sh avec SRV_K3S_VERSION=$ACTUELLE." 1
fi
success "K3s à niveau : $ACTUELLE → $CIBLE, et le cluster est sain."
info "Configuration du serveur : Linux/K3s/configure-k3s.sh."
