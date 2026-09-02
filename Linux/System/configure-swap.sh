#!/usr/bin/env bash
# configure-swap.sh — affiche et configure le fichier d'échange (swap).
#
# Sans taille, le script se contente d'afficher l'état courant : c'est un
# diagnostic sans risque.
#
# Avec une taille, il crée ou redimensionne un fichier d'échange et l'inscrit
# dans /etc/fstab. Aucun swap existant n'est remplacé sans confirmation, et la
# cible visée doit être un fichier d'échange ou n'être rien du tout : le script
# supprime ce qu'il recrée, il ne le fera pas d'un fichier qu'il ne reconnaît pas.

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

Le chemin donné à --file doit être ABSOLU, et ne peut donc pas commencer par un
tiret. Un chemin relatif ferait naître le fichier d'échange dans le répertoire
courant, quel qu'il soit ; une valeur commençant par un tiret est une option du
script, pas un chemin. Les deux sont refusés avec le code 2.

Ce chemin doit en outre ne rien désigner — le fichier est alors créé — ou
désigner un fichier d'échange existant, qui est alors redimensionné. Le script
supprime sa cible avant de la recréer : toute autre cible (répertoire, fichier
ordinaire, périphérique) est refusée avec le code 2, avant toute confirmation.

Exemples :
  configure-swap.sh                       # état actuel
  configure-swap.sh 2G
  configure-swap.sh 2G --dry-run
  configure-swap.sh                       # ou SRV_SWAP_SIZE dans server.env

Options :
      --file <chemin>   Fichier d'échange à utiliser, en chemin absolu
                        (défaut : /swapfile)
      --dry-run         Afficher les opérations sans les exécuter.
  -y, --yes             Ne pas demander de confirmation.
  -h, --help            Afficher cette aide

Attention : les partitions de swap ne sont pas gérées par ce script, qui ne
traite que les fichiers d'échange.
AIDE
}

# -------------------------------------------------------------------
# Reconnaissance d'un fichier d'échange
# -------------------------------------------------------------------
# Répond 0 si le chemin donné est un fichier d'échange, actif ou non. Deux
# preuves, dans cet ordre :
#
#   1. /proc/swaps liste les swaps ACTIFS. Il est lisible par tous, aucun
#      privilège n'est requis, et c'est déjà la source de swap_actif() ;
#   2. un fichier d'échange INACTIF se reconnaît à sa signature : mkswap écrit
#      « SWAPSPACE2 » sur les dix derniers octets de la première page du fichier
#      (union swap_header, linux/swap.h). C'est cette même signature que lit la
#      commande « file » pour annoncer « Linux swap file » — on la lit
#      directement plutôt que d'ajouter « file » aux dépendances du script.
#
# Le fichier ne porte pas la taille de page qui a servi à l'écrire, et celle-ci
# dépend de l'architecture : 4 Kio sur x86-64, jusqu'à 64 Kio ailleurs. Les
# emplacements possibles sont donc essayés l'un après l'autre. Lire l'octet
# exact plutôt que chercher la chaîne dans tout l'en-tête évite de prendre pour
# un swap un fichier qui contiendrait ces dix caractères par hasard.
#
# La fonction ne dit rien et ne meurt jamais : elle répond, l'appelante décide.
# Ses commandes sont toutes placées en condition ou neutralisées par « || true »,
# de sorte qu'aucun échec n'atteigne le trap ERR de lib/common.sh.
est_fichier_swap() {
    local chemin="$1"
    local taille_page signature

    if [ -r /proc/swaps ] && awk -v cible="$chemin" \
            'NR > 1 && $1 == cible { trouve = 1 } END { exit !trouve }' /proc/swaps; then
        return 0
    fi

    # Un fichier d'échange est en mode 600 : hors root, la signature est hors
    # d'atteinte. L'appelante distingue ce cas, qui n'est pas un refus de même
    # nature qu'un fichier lu et non reconnu — elle diffère son jugement tant
    # qu'elle n'a pas les droits de lire.
    if [ ! -r "$chemin" ]; then
        return 1
    fi

    for taille_page in 4096 8192 16384 32768 65536; do
        # « tr » écarte les octets nuls : sans lui, bash avertirait « ignored
        # null byte in input » à chaque fichier ordinaire examiné.
        signature="$(dd if="$chemin" bs=1 skip=$(( taille_page - 10 )) count=10 \
            2>/dev/null | tr -d '\000' || true)"
        if [ "$signature" = "SWAPSPACE2" ]; then
            return 0
        fi
    done

    return 1
}

# -------------------------------------------------------------------
# Validation de la valeur de --file
# -------------------------------------------------------------------
# Deux contrôles : la FORME du chemin, puis ce qu'il DÉSIGNE.
#
# La forme, d'abord — deux refus, pour deux dangers distincts :
#
#   1. une valeur commençant par un tiret est une option du script, avalée comme
#      chemin. « configure-swap.sh 512M --file --dry-run » donnait un fichier
#      d'échange nommé « --dry-run » et un essai à blanc silencieusement perdu ;
#   2. un chemin relatif ferait naître le fichier d'échange dans le répertoire
#      courant. « configure-swap.sh --file 2G » — l'ordre inversé — prend « 2G »
#      pour un chemin, et la taille vient alors de SRV_SWAP_SIZE : plus rien
#      n'arrête le script. Un fichier d'échange n'a de sens qu'à un emplacement
#      choisi ; il n'existe aucun usage légitime d'un chemin relatif ici.
#
# La nature ensuite, détaillée dans le corps de la fonction : un chemin peut être
# absolu et parfaitement formé, et désigner /etc/passwd.
#
# La fonction renseigne FICHIER_SWAP plutôt que d'écrire sur stdout, et n'est
# jamais appelée dans une substitution de commande : son « die » quitterait
# sinon le seul sous-shell, et le code remonté déclencherait le trap ERR de
# lib/common.sh — le refus se verrait doublé d'un « Échec (code 2) à la
# ligne … » sans intérêt. C'est le motif de valider_horaire, dans
# configure-cron.sh.
#
# Aucun « die » ne se trouve non plus dans une substitution de commande à
# l'intérieur : le contrôle de forme est un « case » de Bash pur, celui de nature
# n'emploie que des tests de fichier et un appel en condition. La seule
# substitution de la chaîne est la lecture d'en-tête d'est_fichier_swap, qui ne
# meurt jamais et dont l'échec est éteint par « || true ». Tout cela s'exécute
# avant que dirname ou df ne voient la valeur.
#
# Le second paramètre dit QUAND l'appel a lieu, et cela change un seul refus :
#
#   avant-root  à l'analyse des arguments, sans privilège garanti
#   apres-root  au préflight, une fois require_root passé
#
# Tous les contrôles qui n'exigent aucun privilège — la forme, le lien
# symbolique, la nature non régulière, le fichier lisible mais non reconnu —
# valent aux deux moments : les arguments se vérifient avant les privilèges, et
# une cible fautive doit être reprochée en code 2 même sans « sudo ». Seul le cas
# « existe et n'est pas lisible » est différé : là, ce n'est pas la cible qui est
# en cause mais les droits de celui qui regarde. Le juger avant require_root
# rendait 2 à un appelant sans privilège dont la ligne de commande était juste,
# là où le manque de privilège doit rendre 1.
valider_fichier_swap() {
    local chemin="$1"
    local moment="$2"

    case "$chemin" in
        -*)
            error "Valeur refusée pour --file : « $chemin »."
            error "Une valeur commençant par un tiret est une option, pas un chemin :"
            error "elle serait consommée par --file, et l'option perdue en silence."
            die "Écrire le chemin après --file — par exemple : --file /swapfile --dry-run" 2
            ;;
        /*)
            ;;
        *)
            error "Chemin relatif refusé pour --file : « $chemin »."
            error "Le fichier d'échange naîtrait dans le répertoire courant, quel qu'il soit."
            die "Donner un chemin absolu — par exemple : --file /swapfile" 2
            ;;
    esac

    # La forme est bonne ; reste ce que le chemin DÉSIGNE. Le script supprime sa
    # cible avant de la recréer (« rm -f », plus bas) : trois natures, trois
    # traitements.
    #
    #   absente                    -> création, cas nominal, rien à dire
    #   fichier d'échange existant -> redimensionnement, cas nominal
    #   autre chose                -> refus, avant toute confirmation
    #
    # Le refus vaut mieux que la confirmation : « configure-swap.sh 64M --file
    # /etc/passwd » annonçait « créer /etc/passwd » et le fichier disparaissait
    # sur un simple oui. Rien n'est perdu pour l'appelant, qui n'a qu'à choisir
    # un autre chemin — ou effacer lui-même ce qu'il veut effacer.
    #
    # Contrairement au « case » ci-dessus, ce contrôle interroge le disque. Il le
    # fait sans aucune substitution de commande autour d'un « die » : les tests
    # de fichier sont ceux de Bash, et est_fichier_swap est appelée en condition,
    # où ni errexit ni le trap ERR n'ont prise. Le refus reste donc une seule
    # série de lignes, sans « Échec (code 2) à la ligne … » derrière.
    local nature
    if [ -L "$chemin" ]; then
        error "Lien symbolique refusé pour --file : « $chemin »."
        error "Le fichier d'échange remplacerait le lien ; sa cible, elle, resterait"
        error "en place — l'espace annoncé ne serait pas celui qui est occupé."
        die "Donner le chemin réel du fichier d'échange." 2
    fi

    if [ -e "$chemin" ]; then
        if [ ! -f "$chemin" ]; then
            nature="un objet spécial"
            if   [ -d "$chemin" ]; then nature="un répertoire"
            elif [ -b "$chemin" ]; then nature="un périphérique bloc"
            elif [ -c "$chemin" ]; then nature="un périphérique caractère"
            elif [ -p "$chemin" ]; then nature="un tube nommé"
            elif [ -S "$chemin" ]; then nature="une socket"
            fi
            error "Cible refusée pour --file : « $chemin » est $nature."
            error "Ce script ne gère que les fichiers d'échange ; une partition de swap"
            error "relève du partitionnement, hors de son champ."
            die "Donner le chemin d'un fichier d'échange, existant ou à créer." 2
        fi

        if ! est_fichier_swap "$chemin"; then
            if [ ! -r "$chemin" ]; then
                # Illisible ne veut pas dire fautif : un fichier d'échange est en
                # mode 600, et c'est l'appelant sans privilège qui ne peut pas le
                # lire. À l'analyse des arguments, le jugement est donc DIFFÉRÉ —
                # require_root reprochera le privilège manquant, code 1, et le
                # second appel tranchera la nature avec les droits pour le faire.
                if [ "$moment" = "avant-root" ]; then
                    FICHIER_SWAP="$chemin"
                    return 0
                fi
                # Root et illisible : la cause n'est plus le privilège. Le refus
                # tient — le script supprime sa cible, il ne le fera pas d'un
                # objet dont il n'a rien pu établir.
                error "Cible refusée pour --file : « $chemin » n'est pas lisible."
                error "Sa nature ne peut pas être établie, et le script supprime sa cible"
                error "avant de recréer le fichier d'échange."
                die "Vérifier les droits de lecture sur ce chemin, ou en choisir un autre." 2
            fi
            error "Cible refusée pour --file : « $chemin » existe et n'est pas un fichier d'échange."
            error "/proc/swaps ne le liste pas et aucune signature de swap n'y figure."
            error "Le script supprime sa cible avant de la recréer : ce fichier serait détruit."
            die "Choisir un autre chemin, ou supprimer soi-même ce fichier s'il est sans valeur." 2
        fi
    fi

    FICHIER_SWAP="$chemin"
}

while [ "${1:-}" != "" ]; do
    case "$1" in
        # Le contrôle est explicite plutôt qu'en « ${1:?…} » : cette expansion
        # produit un message brut, sans le préfixe [ERROR], et sort en 1 alors
        # qu'un argument manquant est une erreur d'usage — code 2.
        --file)
            shift
            [ -n "${1:-}" ] || die "--file attend un chemin." 2
            valider_fichier_swap "$1" avant-root
            shift
            ;;
        --dry-run)  DRY_RUN="true"; shift ;;
        # ASSUME_YES est lue par confirm(), dans lib/common.sh.
        -y|--yes)   export ASSUME_YES="true"; shift ;;
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
# La fonction renseigne TAILLE_MO plutôt que d'écrire sur stdout : appelée dans
# une substitution de commande, son « die » ne quitterait que le sous-shell, et
# le code d'erreur remonté au shell principal déclencherait le trap ERR de
# lib/common.sh — le diagnostic métier se verrait alors doublé d'un « Échec
# (code 2) à la ligne … » sans intérêt pour l'appelant.
TAILLE_MO=""
en_megaoctets() {
    local valeur="$1"
    local nombre unite

    nombre="$(printf '%s' "$valeur" | sed 's/[^0-9]//g')"
    unite="$(printf '%s' "$valeur" | sed 's/[0-9]//g' | tr '[:lower:]' '[:upper:]')"

    if [ -z "$nombre" ] || [ "$nombre" -le 0 ] 2>/dev/null; then
        die "Taille invalide : « $valeur » (exemples : 2G, 512M, 2048)." 2
    fi

    case "$unite" in
        G|GB|GO)    TAILLE_MO="$(( nombre * 1024 ))" ;;
        M|MB|MO|"") TAILLE_MO="$nombre" ;;
        *)          die "Unité inconnue dans « $valeur » (attendu G ou M)." 2 ;;
    esac
}

en_megaoctets "$TAILLE_DEMANDEE"

if [ "$TAILLE_MO" -lt 64 ]; then
    die "Taille trop faible : ${TAILLE_MO} Mo (64 Mo au minimum)." 2
fi

# -------------------------------------------------------------------
# Préflight
# -------------------------------------------------------------------
require_root
require_cmd mkswap swapon swapoff

# Le chemin par DÉFAUT n'est jamais passé par valider_fichier_swap, qui ne
# contrôle que la valeur de --file, à l'analyse des arguments. C'est pourtant la
# même cible et le même « rm -f » : elle est donc contrôlée ici, une fois root
# obtenu — un fichier d'échange est en mode 600, lui seul peut en lire la
# signature. Rejouer le contrôle sur une valeur déjà validée ne coûte que
# quelques lectures : la fonction est sans effet de bord, et le seul verdict
# qu'elle peut rendre ici sans l'avoir rendu là-haut est celui d'une cible que
# l'appelant n'avait pas les droits de lire.
#
# Après require_root, et non avant : l'appelant sans privilège doit s'entendre
# reprocher le privilège manquant — code 1 — plutôt qu'une cible dont le script
# n'a de toute façon pas les droits de lecture. C'est aussi ici qu'aboutit le
# jugement différé par le premier appel, quand la valeur de --file désignait un
# fichier illisible : les droits sont acquis, la nature peut être établie.
valider_fichier_swap "$FICHIER_SWAP" apres-root

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
    if grep -qE "^[[:space:]]*${FICHIER_SWAP}[[:space:]]" /etc/fstab 2>/dev/null; then
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

if grep -qE "^[[:space:]]*${FICHIER_SWAP}[[:space:]]" /etc/fstab 2>/dev/null; then
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
