#!/usr/bin/env bash
# configure-swap.sh — affiche et configure le fichier d'échange (swap).
#
# Sans taille, le script se contente d'afficher l'état courant : c'est un
# diagnostic sans risque.
#
# Avec une taille, il crée ou redimensionne un fichier d'échange et l'inscrit
# dans /etc/fstab. Aucun swap existant n'est remplacé sans confirmation.

set -Eeuo pipefail

_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_dir/lib/common.sh" ] && [ "$_dir" != "/" ]; do _dir="$(dirname "$_dir")"; done
source "$_dir/lib/common.sh"

DRY_RUN="false"
TAILLE_DEMANDEE=""
FICHIER_SWAP="/swapfile"

# -------------------------------------------------------------------
# Aide
# -------------------------------------------------------------------
show_help() {
    cat <<'AIDE'
Usage : configure-swap.sh [taille] [options]

Sans taille : affiche l'état du swap et s'arrête. Aucune modification.

Avec une taille : crée ou redimensionne le fichier d'échange, l'active et
l'inscrit dans /etc/fstab pour qu'il survive au redémarrage.

Tailles acceptées : 2G, 512M, ou un nombre seul interprété en mégaoctets.

Le fichier vaut par défaut /swapfile. Un swap déjà actif n'est jamais remplacé
sans confirmation, et jamais désactivé si la mémoire libre ne suffit pas à
absorber ce qu'il contient.

Exemples :
  configure-swap.sh                       # état actuel
  configure-swap.sh 2G
  configure-swap.sh 2G --dry-run
  configure-swap.sh                       # ou SRV_SWAP_SIZE dans server.env

Options :
      --file <chemin>   Fichier d'échange à utiliser (défaut : /swapfile)
      --dry-run         Afficher les opérations sans les exécuter.
  -y, --yes             Ne pas demander de confirmation.
  -h, --help            Afficher cette aide

Attention : les partitions de swap ne sont pas gérées par ce script, qui ne
traite que les fichiers d'échange.
AIDE
}

while [ "${1:-}" != "" ]; do
    case "$1" in
        --file)     shift; FICHIER_SWAP="${1:?--file attend un chemin}"; shift ;;
        --dry-run)  DRY_RUN="true"; shift ;;
        -y|--yes)   ASSUME_YES="true"; shift ;;
        -h|--help)  show_help; exit 0 ;;
        -*)         die "Option inconnue : $1" 2 ;;
        *)
            if [ -n "$TAILLE_DEMANDEE" ]; then
                die "Une seule taille attendue (reçu « $TAILLE_DEMANDEE » puis « $1 »)." 2
            fi
            TAILLE_DEMANDEE="$1"
            shift
            ;;
    esac
done

# Ligne de commande d'abord, config/server.env à défaut.
ORIGINE_TAILLE="argument"
if [ -z "$TAILLE_DEMANDEE" ]; then
    TAILLE_DEMANDEE="${SRV_SWAP_SIZE:-}"
    ORIGINE_TAILLE="config/server.env"
fi

# -------------------------------------------------------------------
# Présentation de l'état courant
# -------------------------------------------------------------------
afficher_etat() {
    printf '\nSwap actif\n' >&2
    printf -- '------------------------------------------------------------\n' >&2

    if [ -r /proc/swaps ] && [ "$(wc -l < /proc/swaps)" -gt 1 ]; then
        awk 'NR > 1 { printf "  %-30s %-10s %10s Ko  %10s Ko\n", $1, $2, $3, $4 }' /proc/swaps >&2
        printf '  %-30s %-10s %13s %13s\n' "(fichier)" "(type)" "taille" "utilisé" >&2
    else
        printf '  aucun\n' >&2
    fi

    printf '\nMémoire\n' >&2
    printf -- '------------------------------------------------------------\n' >&2
    if command -v free >/dev/null 2>&1; then
        free -h | awk '
            /^Mem:/  { printf "  %-12s %8s total  %8s utilisés\n", "RAM", $2, $3 }
            /^Swap:/ { printf "  %-12s %8s total  %8s utilisés\n", "Swap", $2, $3 }
        ' >&2
    fi

    printf '\nEntrées de swap dans /etc/fstab\n' >&2
    printf -- '------------------------------------------------------------\n' >&2
    if grep -qE '[[:space:]]swap[[:space:]]' /etc/fstab 2>/dev/null; then
        grep -E '[[:space:]]swap[[:space:]]' /etc/fstab | sed 's/^/  /' >&2
    else
        printf '  aucune\n' >&2
    fi
    printf '\n' >&2
}

afficher_etat

# Sans taille demandée, le script s'arrête ici : diagnostic seul.
if [ -z "$TAILLE_DEMANDEE" ]; then
    info "Aucune taille demandée : état affiché, rien de modifié."
    info "Pour configurer : configure-swap.sh 2G — ou SRV_SWAP_SIZE dans config/server.env."
    exit 0
fi

# -------------------------------------------------------------------
# Conversion de la taille en mégaoctets
# -------------------------------------------------------------------
en_megaoctets() {
    local valeur="$1"
    local nombre unite

    nombre="$(printf '%s' "$valeur" | sed 's/[^0-9]//g')"
    unite="$(printf '%s' "$valeur" | sed 's/[0-9]//g' | tr '[:lower:]' '[:upper:]')"

    if [ -z "$nombre" ] || [ "$nombre" -le 0 ] 2>/dev/null; then
        die "Taille invalide : « $valeur » (exemples : 2G, 512M, 2048)." 2
    fi

    case "$unite" in
        G|GB|GO)   printf '%s' "$(( nombre * 1024 ))" ;;
        M|MB|MO|"") printf '%s' "$nombre" ;;
        *)         die "Unité inconnue dans « $valeur » (attendu G ou M)." 2 ;;
    esac
}

TAILLE_MO="$(en_megaoctets "$TAILLE_DEMANDEE")"

if [ "$TAILLE_MO" -lt 64 ]; then
    die "Taille trop faible : ${TAILLE_MO} Mo (64 Mo au minimum)." 2
fi

# -------------------------------------------------------------------
# Préflight
# -------------------------------------------------------------------
require_root
require_cmd mkswap swapon swapoff

info "Taille demandée : ${TAILLE_MO} Mo ($ORIGINE_TAILLE : $TAILLE_DEMANDEE)"
info "Fichier d'échange : $FICHIER_SWAP"

# Un conteneur partage le noyau de son hôte et n'a pas la main sur le swap :
# swapon y échoue avec un message peu explicite. Les VPS en KVM ne sont pas
# concernés, contrairement à ceux vendus en OpenVZ ou LXC.
if command -v systemd-detect-virt >/dev/null 2>&1; then
    virtualisation="$(systemd-detect-virt --container 2>/dev/null || true)"
    case "$virtualisation" in
        none|"")
            ;;
        *)
            warn "Environnement détecté : « $virtualisation »."
            warn "Un conteneur partage le noyau de son hôte : l'activation du swap"
            warn "peut y être refusée. WSL l'autorise, OpenVZ et LXC généralement non."
            ;;
    esac
fi

# Une partition de swap relève du partitionnement, hors du champ de ce script.
if [ -r /proc/swaps ] && awk 'NR > 1 && $2 == "partition" { trouve = 1 } END { exit !trouve }' /proc/swaps; then
    warn "Une partition de swap est active. Ce script ne gère que les fichiers."
    warn "Le fichier créé s'ajoutera à la partition existante."
fi

# btrfs et ZFS imposent des précautions particulières (nodatacow, absence de
# compression, volume dédié). Mieux vaut refuser que produire un swap instable.
repertoire_swap="$(dirname "$FICHIER_SWAP")"
type_fs="$(df -P -T "$repertoire_swap" 2>/dev/null | awk 'NR == 2 { print $2 }')"
case "$type_fs" in
    btrfs|zfs)
        error "Système de fichiers « $type_fs » sur $repertoire_swap."
        error "Un fichier d'échange y demande une préparation spécifique que ce"
        error "script ne prend pas en charge (nodatacow, absence de compression)."
        die "Créer le swap manuellement, ou choisir --file sur un autre volume."
        ;;
esac

# -------------------------------------------------------------------
# État du fichier visé
# -------------------------------------------------------------------
swap_actif() {
    [ -r /proc/swaps ] && awk -v cible="$FICHIER_SWAP" 'NR > 1 && $1 == cible { trouve = 1 } END { exit !trouve }' /proc/swaps
}

taille_actuelle_mo() {
    if [ -f "$FICHIER_SWAP" ]; then
        printf '%s' "$(( $(stat -c %s "$FICHIER_SWAP") / 1024 / 1024 ))"
    else
        printf '0'
    fi
}

TAILLE_ACTUELLE_MO="$(taille_actuelle_mo)"

if swap_actif && [ "$TAILLE_ACTUELLE_MO" -eq "$TAILLE_MO" ]; then
    if grep -qE "^[[:space:]]*$FICHIER_SWAP[[:space:]]" /etc/fstab 2>/dev/null; then
        success "Rien à faire : $FICHIER_SWAP est actif à ${TAILLE_MO} Mo et inscrit dans /etc/fstab."
        exit 0
    fi
    info "$FICHIER_SWAP est actif à la bonne taille mais absent de /etc/fstab."
fi

# -------------------------------------------------------------------
# Espace disque
# -------------------------------------------------------------------
# L'espace déjà occupé par le fichier existant sera libéré : il ne compte pas
# dans le besoin net.
espace_libre_mo="$(df -P -BM "$repertoire_swap" | awk 'NR == 2 { gsub(/M/, "", $4); print $4 }')"
besoin_mo=$(( TAILLE_MO - TAILLE_ACTUELLE_MO ))

if [ "$besoin_mo" -gt 0 ] && [ "$espace_libre_mo" -lt "$besoin_mo" ]; then
    error "Espace insuffisant sur $repertoire_swap : ${espace_libre_mo} Mo libres, ${besoin_mo} Mo nécessaires."
    die "Aucune modification effectuée."
fi

# -------------------------------------------------------------------
# Résumé des changements
# -------------------------------------------------------------------
info "Opérations prévues :"
if swap_actif; then
    printf '    désactiver %s (%s Mo)\n' "$FICHIER_SWAP" "$TAILLE_ACTUELLE_MO" >&2
fi
if [ -f "$FICHIER_SWAP" ]; then
    printf '    remplacer  %s (%s Mo -> %s Mo)\n' "$FICHIER_SWAP" "$TAILLE_ACTUELLE_MO" "$TAILLE_MO" >&2
else
    printf '    créer      %s (%s Mo)\n' "$FICHIER_SWAP" "$TAILLE_MO" >&2
fi
printf '    activer    %s\n' "$FICHIER_SWAP" >&2
printf '    inscrire   %s dans /etc/fstab\n' "$FICHIER_SWAP" >&2

if [ "$DRY_RUN" = "true" ]; then
    info "Mode --dry-run : aucune modification effectuée."
    exit 0
fi

if ! confirm "Appliquer ces opérations ?"; then
    info "Abandon à la demande de l'utilisateur."
    exit 0
fi

# -------------------------------------------------------------------
# Désactivation du swap existant
# -------------------------------------------------------------------
if swap_actif; then
    # swapoff recopie en mémoire tout ce que contient le swap. Sans marge, le
    # noyau tuerait des processus pour trouver de la place.
    swap_utilise_ko="$(awk -v cible="$FICHIER_SWAP" 'NR > 1 && $1 == cible { print $4 }' /proc/swaps)"
    ram_libre_ko="$(awk '/^MemAvailable:/ { print $2 }' /proc/meminfo)"

    if [ "${swap_utilise_ko:-0}" -gt "${ram_libre_ko:-0}" ]; then
        error "Le swap contient $(( swap_utilise_ko / 1024 )) Mo, la mémoire disponible est de $(( ram_libre_ko / 1024 )) Mo."
        error "Le désactiver forcerait le noyau à tuer des processus."
        die "Libérer de la mémoire, puis relancer."
    fi

    info "Désactivation de $FICHIER_SWAP…"
    run_logged swapoff "$FICHIER_SWAP"
fi

# -------------------------------------------------------------------
# Création du fichier
# -------------------------------------------------------------------
rm -f "$FICHIER_SWAP"

# À partir d'ici le fichier existe mais n'est pas encore utilisable. Si mkswap
# ou swapon échoue — cas courant en conteneur, où le noyau appartient à l'hôte —
# il ne doit pas rester des centaines de mégaoctets orphelins sur le disque.
nettoyer_fichier_incomplet() {
    if [ -f "$FICHIER_SWAP" ] && ! swap_actif; then
        rm -f "$FICHIER_SWAP"
        warn "Échec de la configuration : $FICHIER_SWAP a été supprimé."
    fi
}
trap nettoyer_fichier_incomplet EXIT

info "Création de $FICHIER_SWAP (${TAILLE_MO} Mo)…"
# fallocate est instantané mais tous les systèmes de fichiers ne le gèrent pas ;
# dd fonctionne partout, au prix d'une écriture réelle.
if command -v fallocate >/dev/null 2>&1 && fallocate -l "${TAILLE_MO}M" "$FICHIER_SWAP" 2>/dev/null; then
    info "Fichier alloué via fallocate."
else
    info "fallocate indisponible sur ce système de fichiers, écriture via dd…"
    run_logged dd if=/dev/zero of="$FICHIER_SWAP" bs=1M count="$TAILLE_MO" status=none
fi

# Un fichier d'échange lisible par tous exposerait le contenu de la mémoire.
chmod 600 "$FICHIER_SWAP"
chown root:root "$FICHIER_SWAP"

run_logged mkswap "$FICHIER_SWAP"

if ! run_logged swapon "$FICHIER_SWAP"; then
    error "L'activation du swap a échoué."
    error "Sur un conteneur (OpenVZ, LXC, WSL), le noyau appartient à l'hôte et"
    error "n'autorise pas le swap. Vérifier avec : systemd-detect-virt"
    die "Aucune entrée n'a été ajoutée à /etc/fstab."
fi

# Le swap est actif : le fichier n'est plus à nettoyer en cas de sortie.
trap - EXIT
success "Swap actif : $FICHIER_SWAP (${TAILLE_MO} Mo)"

# -------------------------------------------------------------------
# Persistance dans /etc/fstab
# -------------------------------------------------------------------
LIGNE_FSTAB="$FICHIER_SWAP	none	swap	sw	0	0"

if grep -qE "^[[:space:]]*$FICHIER_SWAP[[:space:]]" /etc/fstab 2>/dev/null; then
    info "/etc/fstab contient déjà une entrée pour $FICHIER_SWAP."
else
    sauvegarde="/etc/fstab.bak-$(date '+%Y%m%d-%H%M%S')"
    suffixe=1
    while [ -e "$sauvegarde" ]; do
        sauvegarde="/etc/fstab.bak-$(date '+%Y%m%d-%H%M%S')-$suffixe"
        suffixe=$(( suffixe + 1 ))
    done
    cp -p /etc/fstab "$sauvegarde"
    info "Sauvegarde : $sauvegarde"

    printf '%s\n' "$LIGNE_FSTAB" >> /etc/fstab
    success "/etc/fstab complété : le swap sera actif au redémarrage."
fi

# -------------------------------------------------------------------
# Vérification
# -------------------------------------------------------------------
if ! swap_actif; then
    die "$FICHIER_SWAP n'apparaît pas dans /proc/swaps après activation."
fi

afficher_etat
success "Swap configuré : $FICHIER_SWAP (${TAILLE_MO} Mo)"
