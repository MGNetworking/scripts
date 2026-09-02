#!/usr/bin/env bash
# configure-timezone.sh — définit le fuseau horaire du serveur.
#
# Le fuseau est validé avant application : un nom inexistant ramènerait la
# machine à UTC sans avertissement.
#
# Idempotent : relançable sans effet de bord.

set -Eeuo pipefail

_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_dir/lib/common.sh" ] && [ "$_dir" != "/" ]; do _dir="$(dirname "$_dir")"; done
source "$_dir/lib/common.sh"

DRY_RUN="false"
NOUVEAU_FUSEAU=""

REPERTOIRE_FUSEAUX="/usr/share/zoneinfo"

# -------------------------------------------------------------------
# Aide
# -------------------------------------------------------------------
show_help() {
    cat <<'AIDE'
Usage : configure-timezone.sh [fuseau] [options]

Définit le fuseau horaire du serveur.

Le fuseau est pris dans cet ordre :
  1. l'argument de la ligne de commande ;
  2. SRV_TIMEZONE dans config/server.env.

Son existence est vérifiée avant toute modification.

Exemples :
  configure-timezone.sh                      # SRV_TIMEZONE
  configure-timezone.sh Europe/Paris
  configure-timezone.sh UTC --dry-run

Options :
      --list      Lister les fuseaux disponibles et quitter.
      --dry-run   Afficher le changement sans l'appliquer.
  -y, --yes       Ne pas demander de confirmation.
  -h, --help      Afficher cette aide

Attention : les tâches planifiées suivent le fuseau du système. Un cron réglé
sur 4 h s'exécutera à 4 h dans le nouveau fuseau, donc à une autre heure réelle
qu'auparavant.
AIDE
}

# -------------------------------------------------------------------
# Liste des fuseaux
# -------------------------------------------------------------------
# timedatectl fait autorité lorsqu'il répond ; il échoue en conteneur ou en
# chroot, faute de bus. Le repli parcourt zoneinfo en écartant ses répertoires
# techniques (posix/, right/) et ses tables (zone.tab, iso3166.tab…).
lister_fuseaux() {
    if command -v timedatectl >/dev/null 2>&1; then
        local liste
        if liste="$(timedatectl list-timezones 2>/dev/null)" && [ -n "$liste" ]; then
            printf '%s\n' "$liste"
            return 0
        fi
    fi

    find "$REPERTOIRE_FUSEAUX" -type f 2>/dev/null \
        | grep -v '/posix/\|/right/' \
        | grep -v '\.tab$\|\.list$\|/leapseconds$\|/tzdata\.zi$' \
        | sed "s|^$REPERTOIRE_FUSEAUX/||" \
        | sort
}

# -------------------------------------------------------------------
# Analyse des arguments
# -------------------------------------------------------------------
while [ "${1:-}" != "" ]; do
    case "$1" in
        --list)     lister_fuseaux; exit 0 ;;
        --dry-run)  DRY_RUN="true"; shift ;;
        # ASSUME_YES est lue par confirm(), dans lib/common.sh.
        -y|--yes)   export ASSUME_YES="true"; shift ;;
        -h|--help)  show_help; exit 0 ;;
        -*)         die "Option inconnue : $1" 2 ;;
        *)
            if [ -n "$NOUVEAU_FUSEAU" ]; then
                die "Un seul fuseau attendu (reçu « $NOUVEAU_FUSEAU » puis « $1 »)." 2
            fi
            NOUVEAU_FUSEAU="$1"
            shift
            ;;
    esac
done

# Ligne de commande d'abord, config/server.env à défaut.
ORIGINE_FUSEAU="argument"
if [ -z "$NOUVEAU_FUSEAU" ]; then
    NOUVEAU_FUSEAU="${SRV_TIMEZONE:-}"
    ORIGINE_FUSEAU="config/server.env"
fi

if [ -z "$NOUVEAU_FUSEAU" ]; then
    error "Fuseau horaire manquant."
    error "Le passer en argument, ou définir SRV_TIMEZONE dans config/server.env."
    error "Lister les fuseaux disponibles : configure-timezone.sh --list"
    exit 2
fi

# -------------------------------------------------------------------
# Validation
# -------------------------------------------------------------------
# Un fuseau refusé est une valeur d'argument invalide : code 2, comme l'option
# inconnue et l'argument manquant (voir docs/architecture-technique.md §6).
valider_fuseau() {
    local fuseau="$1"

    case "$fuseau" in
        posix/*|right/*)
            die "« $fuseau » est un répertoire technique de zoneinfo, pas un fuseau." 2 ;;
        *.tab|*.list|/*|*..*)
            die "Fuseau invalide : « $fuseau »." 2 ;;
    esac

    if [ ! -f "$REPERTOIRE_FUSEAUX/$fuseau" ]; then
        error "Fuseau inconnu : « $fuseau »."
        error "Lister les fuseaux disponibles : configure-timezone.sh --list"
        die "Aucune modification effectuée." 2
    fi
}

valider_fuseau "$NOUVEAU_FUSEAU"

# -------------------------------------------------------------------
# Préflight
# -------------------------------------------------------------------
require_root

# -------------------------------------------------------------------
# État actuel
# -------------------------------------------------------------------
fuseau_actuel() {
    if command -v timedatectl >/dev/null 2>&1; then
        local valeur
        if valeur="$(timedatectl show -p Timezone --value 2>/dev/null)" && [ -n "$valeur" ]; then
            printf '%s' "$valeur"
            return 0
        fi
    fi
    if [ -r /etc/timezone ]; then
        tr -d '[:space:]' < /etc/timezone
        return 0
    fi
    if [ -L /etc/localtime ]; then
        # /etc/localtime pointe sur /usr/share/zoneinfo/<fuseau>
        readlink -f /etc/localtime | sed "s|^$REPERTOIRE_FUSEAUX/||"
        return 0
    fi
    printf 'inconnu'
}

FUSEAU_ACTUEL="$(fuseau_actuel)"

info "Fuseau actuel  : $FUSEAU_ACTUEL  ($(date '+%Y-%m-%d %H:%M:%S %Z'))"
info "Fuseau demandé : $NOUVEAU_FUSEAU ($ORIGINE_FUSEAU)"

if [ "$FUSEAU_ACTUEL" = "$NOUVEAU_FUSEAU" ]; then
    success "Rien à faire : le fuseau est déjà « $NOUVEAU_FUSEAU »."
    exit 0
fi

# Heure qu'il sera dans le fuseau demandé, pour rendre le changement tangible.
info "Heure dans « $NOUVEAU_FUSEAU » : $(TZ="$NOUVEAU_FUSEAU" date '+%Y-%m-%d %H:%M:%S %Z')"

if [ "$DRY_RUN" = "true" ]; then
    info "Mode --dry-run : aucune modification effectuée."
    exit 0
fi

if ! confirm "Passer de « $FUSEAU_ACTUEL » à « $NOUVEAU_FUSEAU » ?"; then
    info "Abandon à la demande de l'utilisateur."
    exit 0
fi

# -------------------------------------------------------------------
# Application
# -------------------------------------------------------------------
if command -v timedatectl >/dev/null 2>&1 && timedatectl set-timezone "$NOUVEAU_FUSEAU" 2>/dev/null; then
    info "Fuseau défini via timedatectl."
else
    # Repli pour les systèmes sans systemd, ou lorsque timedatectl échoue faute
    # de bus. C'est exactement ce que timedatectl fait lui-même.
    ln -sf "$REPERTOIRE_FUSEAUX/$NOUVEAU_FUSEAU" /etc/localtime
    info "Fuseau défini via /etc/localtime."
fi

# timedatectl ne maintient que /etc/localtime. /etc/timezone, propre à Debian et
# lu par certains outils (dpkg-reconfigure tzdata notamment), resterait sur
# l'ancienne valeur — d'où cette mise en cohérence explicite.
if [ -f /etc/timezone ]; then
    ancien_fichier="$(tr -d '[:space:]' < /etc/timezone)"
    if [ "$ancien_fichier" != "$NOUVEAU_FUSEAU" ]; then
        printf '%s\n' "$NOUVEAU_FUSEAU" > /etc/timezone
        info "/etc/timezone mis en cohérence (était « $ancien_fichier »)."
    fi
fi

# -------------------------------------------------------------------
# Vérification
# -------------------------------------------------------------------
FUSEAU_VERIFIE="$(fuseau_actuel)"
if [ "$FUSEAU_VERIFIE" != "$NOUVEAU_FUSEAU" ]; then
    die "Le fuseau est « $FUSEAU_VERIFIE » et non « $NOUVEAU_FUSEAU »."
fi

# Les trois sources doivent concorder : c'est leur divergence qui produit des
# comportements incohérents d'un outil à l'autre.
#
# La comparaison porte sur le contenu et non sur le nom du lien : de nombreux
# fuseaux sont des alias les uns des autres — « UTC » pointe sur « Etc/UTC »,
# « US/Eastern » sur « America/New_York » — et comparer les noms signalerait une
# incohérence là où il n'y en a aucune.
if [ -e /etc/localtime ] && ! cmp -s /etc/localtime "$REPERTOIRE_FUSEAUX/$NOUVEAU_FUSEAU"; then
    die "/etc/localtime ne correspond pas à « $NOUVEAU_FUSEAU »."
fi

if [ -f /etc/timezone ]; then
    fichier_timezone="$(tr -d '[:space:]' < /etc/timezone)"
    if [ "$fichier_timezone" != "$NOUVEAU_FUSEAU" ]; then
        die "/etc/timezone contient « $fichier_timezone » et non « $NOUVEAU_FUSEAU »."
    fi
fi

info "Heure locale : $(date '+%Y-%m-%d %H:%M:%S %Z')"
warn "Les tâches planifiées suivent ce fuseau : vérifier les horaires de cron."
success "Fuseau horaire configuré : $NOUVEAU_FUSEAU"
