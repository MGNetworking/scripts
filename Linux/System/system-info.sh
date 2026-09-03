#!/usr/bin/env bash
# system-info.sh — état du système, en lecture seule.
#
# N'écrit rien, ne modifie rien, ne nécessite aucun privilège.
# Usage : ./system-info.sh [--help]

set -Eeuo pipefail

_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_dir/lib/common.sh" ] && [ "$_dir" != "/" ]; do _dir="$(dirname "$_dir")"; done
source "$_dir/lib/common.sh"

# -------------------------------------------------------------------
# Aide
# -------------------------------------------------------------------
show_help() {
    cat <<'AIDE'
Usage : system-info.sh [options]

Affiche l'état du système : distribution, noyau, architecture, processeur,
mémoire, stockage, réseau, identité et heure.

Script en lecture seule : aucune modification, aucun privilège requis.

Options :
  -h, --help    Afficher cette aide
AIDE
}

while [ "${1:-}" != "" ]; do
    case "$1" in
        -h|--help) show_help; exit 0 ;;
        *)         die "Option inconnue : $1" 2 ;;
    esac
done

# -------------------------------------------------------------------
# Présentation
# -------------------------------------------------------------------

# Titre de section
titre() {
    printf '\n%s\n' "$1"
    printf '%s\n' "------------------------------------------------------------"
}

# Ligne « libellé : valeur ». Une valeur vide devient « non disponible ».
#
# Le remplissage est calculé sur le nombre de caractères et non d'octets :
# « %-22s » de printf compte les octets, ce qui décale les libellés accentués.
ligne() {
    local libelle="$1"
    local valeur="${2:-non disponible}"
    local remplissage=$(( 23 - ${#libelle} ))

    if [ "$remplissage" -lt 1 ]; then
        remplissage=1
    fi
    printf '  %s%*s%s\n' "$libelle" "$remplissage" "" "$valeur"
}

# Cellule de largeur fixe, comptée en caractères.
# Usage : cellule <texte> <largeur> <gauche|droite>
cellule() {
    local texte="$1" largeur="$2" cote="$3"
    local remplissage=$(( largeur - ${#texte} ))

    if [ "$remplissage" -lt 0 ]; then
        remplissage=0
    fi
    if [ "$cote" = "droite" ]; then
        printf '%*s%s' "$remplissage" "" "$texte"
    else
        printf '%s%*s' "$texte" "$remplissage" ""
    fi
}

# -------------------------------------------------------------------
# Collecte
# -------------------------------------------------------------------

section_systeme() {
    titre "Système"
    detect_os
    ligne "Distribution" "${PRETTY_NAME:-$OS_ID $OS_VERSION}"
    ligne "Identifiant" "$OS_ID"
    ligne "Version" "$OS_VERSION"
    ligne "Noyau" "$(uname -r)"
    ligne "Architecture" "$OS_ARCH"
}

section_processeur() {
    titre "Processeur"

    local modele="" coeurs=""

    if [ -r /proc/cpuinfo ]; then
        modele="$(grep -m1 -E '^(model name|Model)[[:space:]]*:' /proc/cpuinfo 2>/dev/null | cut -d: -f2- | sed 's/^[[:space:]]*//' || true)"
    fi

    # Affectation en CONTEXTE DE CONDITION. « command -v nproc » établit que la
    # commande existe, pas qu'elle réussit : un faux nproc en tête de PATH la met
    # en échec, et sous la forme nue « coeurs="$(nproc)" » le trap ERR de
    # lib/common.sh parle deux fois — une fois dans le sous-shell de la
    # substitution, une fois dans le shell principal pour l'affectation — sans
    # qu'aucune des deux lignes ne dise ce qui a flanché. En condition, ni
    # errexit ni le trap n'ont prise.
    #
    # L'échec n'est pas fatal : ce script ne fait que lire, et il dégrade déjà en
    # « non disponible » ailleurs. Une valeur vide suffit à ce que « ligne »
    # l'affiche ainsi ; l'avertissement, lui, nomme la cause.
    if command -v nproc >/dev/null 2>&1; then
        if ! coeurs="$(nproc)"; then
            warn "« nproc » a échoué : le nombre de cœurs logiques reste indéterminé."
            coeurs=""
        fi
    elif [ -r /proc/cpuinfo ]; then
        coeurs="$(grep -c '^processor' /proc/cpuinfo || true)"
    fi

    ligne "Modèle" "$modele"
    ligne "Cœurs logiques" "$coeurs"

    # Charge moyenne sur 1, 5 et 15 minutes
    if [ -r /proc/loadavg ]; then
        ligne "Charge (1/5/15 min)" "$(cut -d' ' -f1-3 /proc/loadavg)"
    fi
}

section_memoire() {
    titre "Mémoire"

    if command -v free >/dev/null 2>&1; then
        # Les colonnes de « free » varient selon les versions : on lit les
        # champs par position sur les lignes Mem: et Swap:.
        free -h | awk '
            /^Mem:/  { printf "  %-22s %s utilisés sur %s (%s disponibles)\n", "RAM", $3, $2, ($7 == "" ? $4 : $7) }
            /^Swap:/ { printf "  %-22s %s utilisés sur %s\n", "Swap", $3, $2 }
        '
    elif [ -r /proc/meminfo ]; then
        # Mêmes gardes que pour nproc, et pour la même raison : « [ -r ] » établit
        # que le fichier était lisible à l'instant du test, et rien du tout sur
        # awk — qu'un faux awk en tête de PATH suffit à mettre en échec. Chaque
        # lecture est donc en contexte de condition, et chacune dit ce qu'elle
        # n'a pas pu établir plutôt que de laisser deux lignes de trap le taire.
        local total="" dispo=""
        if ! total="$(awk '/^MemTotal:/  {printf "%.1f Go", $2/1024/1024}' /proc/meminfo)"; then
            warn "MemTotal illisible dans /proc/meminfo : « awk » a échoué."
            total=""
        fi
        if ! dispo="$(awk '/^MemAvailable:/ {printf "%.1f Go", $2/1024/1024}' /proc/meminfo)"; then
            warn "MemAvailable illisible dans /proc/meminfo : « awk » a échoué."
            dispo=""
        fi
        ligne "RAM totale" "$total"
        ligne "RAM disponible" "$dispo"
    else
        ligne "RAM" ""
    fi
}

section_stockage() {
    titre "Stockage"

    if ! command -v df >/dev/null 2>&1; then
        ligne "Systèmes de fichiers" ""
        return 0
    fi

    # Systèmes de fichiers réels uniquement : les pseudo-systèmes (tmpfs,
    # devtmpfs, overlay…) n'ont pas leur place dans un état de stockage, et les
    # images de paquets snap sont montées en lecture seule à 100 % d'occupation.
    printf '  %s%s%s%s%s\n' \
        "$(cellule "Monté sur" 24 gauche)" \
        "$(cellule "Taille" 10 droite)" \
        "$(cellule "Utilisé" 10 droite)" \
        "$(cellule "Libre" 10 droite)" \
        "$(cellule "Occup." 7 droite)"

    df -h -x tmpfs -x devtmpfs -x overlay -x squashfs 2>/dev/null \
        | awk 'NR > 1 && $6 !~ /^\/snap\// { printf "  %-24s%10s%10s%10s%7s\n", $6, $2, $3, $4, $5 }'
}

section_reseau() {
    titre "Réseau"

    ligne "Nom d'hôte" "$(hostname 2>/dev/null || cat /etc/hostname 2>/dev/null || true)"

    local adresses=""
    if command -v ip >/dev/null 2>&1; then
        adresses="$(ip -4 -o addr show scope global 2>/dev/null | awk '{print $2": "$4}' || true)"
    elif command -v hostname >/dev/null 2>&1; then
        adresses="$(hostname -I 2>/dev/null || true)"
    fi

    if [ -n "$adresses" ]; then
        printf '%s\n' "$adresses" | while IFS= read -r adresse; do
            ligne "Adresse IPv4" "$adresse"
        done
    else
        ligne "Adresse IPv4" ""
    fi

    if command -v ip >/dev/null 2>&1; then
        ligne "Passerelle" "$(ip route show default 2>/dev/null | awk '{print $3; exit}' || true)"
    fi
}

section_identite() {
    titre "Identité et heure"

    ligne "Utilisateur" "$(id -un) (uid $(id -u))"
    ligne "Répertoire du dépôt" "$SCRIPTS_ROOT"

    if command -v uptime >/dev/null 2>&1; then
        ligne "Uptime" "$(uptime -p 2>/dev/null || uptime 2>/dev/null | sed 's/^[[:space:]]*//' || true)"
    elif [ -r /proc/uptime ]; then
        ligne "Uptime" "$(awk '{printf "%d jours %d heures %d minutes", $1/86400, ($1%86400)/3600, ($1%3600)/60}' /proc/uptime)"
    fi

    ligne "Date et heure" "$(date '+%Y-%m-%d %H:%M:%S %Z')"

    if command -v timedatectl >/dev/null 2>&1; then
        ligne "Fuseau horaire" "$(timedatectl show -p Timezone --value 2>/dev/null || true)"
    elif [ -r /etc/timezone ]; then
        ligne "Fuseau horaire" "$(cat /etc/timezone)"
    fi
}

# -------------------------------------------------------------------
# Exécution
# -------------------------------------------------------------------
section_systeme
section_processeur
section_memoire
section_stockage
section_reseau
section_identite
printf '\n'
