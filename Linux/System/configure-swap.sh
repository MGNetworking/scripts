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
Son répertoire d'accueil doit exister : le script ne crée aucun répertoire, et
refuse également en 2 un chemin dont le dossier parent est absent.

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
# Traversabilité des ancêtres d'un chemin
# -------------------------------------------------------------------
# Répond 0 si tous les ancêtres EXISTANTS du chemin donné sont traversables par
# l'appelant, 1 dès que l'un d'eux ne l'est pas.
#
# « [ -d /a/b ] » est faux dans deux cas qui n'ont rien à voir : « b » n'existe
# pas, ou « a » existe et n'est pas traversable par celui qui regarde. Le premier
# est une valeur d'argument fautive, qui se reproche en 2 sans attendre le
# moindre privilège ; le second est un manque de droits, qui ne se reproche pas à
# la ligne de commande. Cette fonction sépare les deux, et c'est tout ce que
# valider_fichier_swap a besoin de savoir de plus pour trancher avant
# require_root.
#
# Le parcours descend depuis la racine : chaque composant n'est examiné qu'une
# fois établi que tous ceux qui le précèdent sont traversables — « [ -d ] » et
# « [ -x ] » y disent donc la vérité. Le découpage se fait par expansion de
# paramètre : aucune substitution de commande, aucune commande externe, et pas
# de « for … in $chemin » qui exposerait les composants au globbing.
ancetres_traversables() {
    local reste="${1#/}"
    local parcouru=""
    local element

    while [ -n "$reste" ]; do
        element="${reste%%/*}"
        if [ "$element" = "$reste" ]; then
            reste=""
        else
            reste="${reste#*/}"
        fi
        # Composant vide : deux barres obliques consécutives, sans effet.
        [ -n "$element" ] || continue

        parcouru="$parcouru/$element"

        # Le composant n'est pas un répertoire — absent, ou fichier ordinaire :
        # rien n'existe au-dessous, et cette conclusion-là s'établit sans
        # privilège. Le verdict d'absence est donc fiable, on le laisse rendre.
        [ -d "$parcouru" ] || return 0
        # Il existe, mais on ne peut pas y entrer : plus rien n'est établissable
        # au-dessous, et surtout pas une absence.
        [ -x "$parcouru" ] || return 1
    done

    return 0
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
# l'intérieur : le contrôle de forme est un « case » de Bash pur, ceux de nature
# et de répertoire d'accueil n'emploient que des tests de fichier, des expansions
# de paramètre et deux appels de fonction placés en condition — est_fichier_swap
# et ancetres_traversables. La seule substitution de la chaîne est la lecture
# d'en-tête d'est_fichier_swap, qui ne meurt jamais et dont l'échec est éteint par
# « || true ». Tout cela s'exécute avant que dirname ou df ne voient la valeur.
#
# Le second paramètre dit QUAND l'appel a lieu :
#
#   avant-root  à l'analyse des arguments, sans privilège garanti
#   apres-root  au préflight, une fois require_root passé
#
# Tous les contrôles qui n'exigent aucun privilège — la forme, le lien
# symbolique, la nature non régulière, le fichier lisible mais non reconnu, le
# répertoire d'accueil absent — valent aux deux moments : les arguments se
# vérifient avant les privilèges, et une cible fautive doit être reprochée en
# code 2 même sans « sudo ».
#
# DEUX verdicts seulement sont différés à apres-root, et pour la même raison :
# ce n'est pas la cible qui est en cause, mais ce que l'appelant a le droit de
# voir.
#
#   la cible existe et n'est pas lisible     — un fichier d'échange est en 600
#   un ancêtre du chemin n'est pas traversable — « [ -d ] » ne prouve alors rien
#
# Les juger avant require_root rendrait 2 à un appelant sans privilège dont la
# ligne de commande est juste, là où le manque de privilège doit rendre 1.
# Aucun autre refus n'a de raison d'attendre : l'absence d'un répertoire, elle,
# se constate sans le moindre droit.
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

    # Le répertoire d'accueil doit exister. « --file /pas/de/dossier/swapfile »
    # franchit tout ce qui précède — une cible absente est le cas nominal d'une
    # création — mais rien ne peut naître dans un répertoire qui n'existe pas :
    # le script mourait plus loin sur l'échec muet de df. C'est une valeur
    # d'argument fautive, elle se reproche donc en 2, comme les autres refus de
    # --file, et dès l'analyse des arguments : un répertoire absent se constate
    # sans aucun privilège.
    #
    # Le répertoire parent est obtenu par expansion de paramètre plutôt que par
    # « $(dirname …) » : cette fonction ne contient aucune substitution de
    # commande autour d'un « die », et ce contrôle ne va pas l'y introduire. Le
    # chemin est absolu — le « case » ci-dessus l'a garanti — donc « ${chemin%/*} »
    # vaut le répertoire parent, ou la chaîne vide pour un fichier à la racine.
    local repertoire="${chemin%/*}"
    [ -n "$repertoire" ] || repertoire="/"

    if [ ! -d "$repertoire" ]; then
        # Seule ambiguïté : un ancêtre non traversable rend « [ -d ] » faux sans
        # que le répertoire soit absent. Ce cas-là est différé à apres-root,
        # comme l'est celui d'une cible illisible ; tous les autres tranchent
        # ici, avec ou sans « sudo ».
        if [ "$moment" = "avant-root" ] && ! ancetres_traversables "$repertoire"; then
            FICHIER_SWAP="$chemin"
            return 0
        fi
        error "Répertoire introuvable : « $repertoire »."
        error "Le fichier d'échange « $chemin » ne peut pas y être créé."
        die "Créer ce répertoire, ou choisir un autre chemin pour --file." 2
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
#
# Les deux lectures qu'elle fait sont elles-mêmes placées en CONTEXTE DE
# CONDITION : sous la forme nue, un « sed » ou un « tr » en échec — un binaire
# homonyme en tête de PATH suffit — fait échouer l'affectation, et le trap ERR
# parle deux fois sans nommer la cause. C'est le même motif, un cran plus bas
# (TASK-018).
#
# Ces échecs-là ne sont pas des fautes de l'appelant : la taille qu'il a écrite
# n'a pas pu être analysée, ce qui est un échec d'exécution — code 1 — quand une
# taille réellement invalide vaut 2.
TAILLE_MO=""
en_megaoctets() {
    local valeur="$1"
    local nombre unite

    if ! nombre="$(printf '%s' "$valeur" | sed 's/[^0-9]//g')"; then
        error "Lecture du nombre impossible dans « $valeur » : « sed » a échoué."
        die "Vérifier « sed » dans le PATH, puis relancer."
    fi

    if ! unite="$(printf '%s' "$valeur" | sed 's/[0-9]//g' | tr '[:lower:]' '[:upper:]')"; then
        error "Lecture de l'unité impossible dans « $valeur » : « sed » ou « tr » a échoué."
        die "Vérifier « sed » et « tr » dans le PATH, puis relancer."
    fi

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
# quelques lectures : la fonction est sans effet de bord, et les seuls verdicts
# qu'elle peut rendre ici sans les avoir rendus là-haut sont ceux d'une cible que
# l'appelant n'avait pas les droits de lire et d'un répertoire d'accueil qu'il
# n'avait pas les droits d'atteindre.
#
# Après require_root, et non avant : l'appelant sans privilège doit s'entendre
# reprocher le privilège manquant — code 1 — plutôt qu'une cible dont le script
# n'a de toute façon pas les droits de lecture. C'est aussi ici qu'aboutissent les
# deux jugements différés par le premier appel : les droits sont acquis, la nature
# de la cible et l'existence de son répertoire d'accueil peuvent être établies.
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

# -------------------------------------------------------------------
# Répertoire d'accueil et système de fichiers
# -------------------------------------------------------------------
# Les affectations de cette section sont toutes placées en CONTEXTE DE CONDITION,
# et c'est délibéré. Une substitution de commande s'exécute dans un sous-shell qui
# hérite du « trap ERR » de lib/common.sh : quand son contenu échoue, le trap
# parle une première fois dans le sous-shell, puis une seconde dans le shell
# principal pour l'affectation en échec. L'appelant reçoit deux fois la même
# ligne, et pas un mot sur la cause :
#
#   $ configure-swap.sh 512M --file --dry-run     # avant TASK-017
#   dirname: unrecognized option '--dry-run'
#   [ERROR] Échec (code 1) à la ligne 195 de configure-swap.sh.
#   [ERROR] Échec (code 1) à la ligne 195 de configure-swap.sh.
#
# En condition, ni errexit ni le trap n'ont prise — pas davantage à l'intérieur
# du sous-shell, qui hérite de ce contexte. L'échec n'est plus rendu que par le
# diagnostic écrit ici, une seule fois et avec sa cause.
#
# dirname y compris, depuis TASK-018. Il était resté en forme nue au motif qu'il
# NE POUVAIT PAS échouer ici : « -- » ferme les options, valider_fichier_swap
# refuse déjà toute valeur ne commençant pas par « / » (TASK-017), et l'absence de
# dirname serait exclue par le fait même que ce script s'exécute — les trois
# lignes de résolution en tête de fichier l'appellent.
#
# Cet argument couvre l'ABSENCE de la commande, jamais son ÉCHEC. C'est mot pour
# mot celui qui protégeait « NOM_ACTUEL="$(hostname)" » derrière un require_cmd
# dans configure-hostname.sh, et qu'un binaire homonyme en tête de PATH a
# démenti. Il ne couvre d'ailleurs pas non plus l'absence de façon sûre : les
# lignes de résolution s'exécutent AVANT que lib/common.sh ne charge
# config/server.env, lequel peut redéfinir PATH. Le dirname résolu ici n'est pas
# nécessairement celui qui a résolu l'en-tête.
#
# L'EXISTENCE du répertoire ainsi obtenu n'est pas contrôlée ici :
# valider_fichier_swap s'en charge, à l'analyse des arguments — un répertoire
# absent est une valeur fautive, et se constate sans privilège.
if ! repertoire_swap="$(dirname -- "$FICHIER_SWAP")"; then
    error "Répertoire d'accueil de $FICHIER_SWAP indéterminable : « dirname » a échoué."
    die "Vérifier « dirname » dans le PATH, puis relancer."
fi

# btrfs et ZFS imposent des précautions particulières (nodatacow, absence de
# compression, volume dédié). Mieux vaut refuser que produire un swap instable.
#
# Le répertoire existe, mais df peut encore échouer — système de fichiers
# démonté sous les pieds du script, erreur d'entrée-sortie. Sous pipefail,
# l'échec de df emporte le pipeline entier : la condition le recueille.
if ! type_fs="$(df -P -T "$repertoire_swap" 2>/dev/null | awk 'NR == 2 { print $2 }')"; then
    error "Système de fichiers de $repertoire_swap indéterminable : df a échoué."
    die "Vérifier que ce répertoire est monté et accessible."
fi

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

# La fonction renseigne TAILLE_ACTUELLE_MO plutôt que d'écrire sur stdout : elle
# n'est ainsi jamais appelée dans une substitution de commande. Sous l'ancienne
# forme — la fonction rendant sa valeur sur stdout autour d'un « $(stat …) »,
# l'appelante l'affectant par substitution — un « stat » en échec (fichier
# disparu entre le test et la lecture, stat absent du PATH) produisait ceci,
# MESURÉ par mutation dans le conteneur de test — les numéros sont ceux du
# fichier muté :
#
#   [ERROR] Échec (code 1) à la ligne 490 de configure-swap.sh.
#   configure-swap.sh: line 490: / 1024 / 1024 : syntax error: operand expected
#   [ERROR] Échec (code 1) à la ligne 496 de configure-swap.sh.
#
# Soit DEUX lignes du trap, à des lignes DIFFÉRENTES — celle de la lecture, puis
# celle de l'affectation — encadrant un message brut de bash, la substitution
# vidée laissant une arithmétique incomplète. Aucune des trois ne dit ce qui
# s'est passé. Le décompte des lignes [ERROR] ne sépare donc pas les deux formes :
# ce qui les sépare, c'est le diagnostic métier présent et le « Échec (code »
# absent. C'est le motif d'en_megaoctets, plus haut, et de valider_horaire dans
# configure-cron.sh.
#
# La lecture elle-même est en condition, où ni errexit ni le trap n'ont prise :
# le seul diagnostic rendu est celui écrit ici.
TAILLE_ACTUELLE_MO=0
lire_taille_actuelle() {
    local octets

    if [ ! -f "$FICHIER_SWAP" ]; then
        TAILLE_ACTUELLE_MO=0
        return 0
    fi

    if ! octets="$(stat -c %s "$FICHIER_SWAP" 2>/dev/null)"; then
        error "Taille de $FICHIER_SWAP illisible."
        die "Vérifier que ce fichier est toujours en place, puis relancer."
    fi

    TAILLE_ACTUELLE_MO=$(( octets / 1024 / 1024 ))
}

lire_taille_actuelle

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
#
# Même contexte de condition que pour df -T plus haut, et pour la même raison :
# l'échec du pipeline ne doit être annoncé qu'une fois, par un diagnostic qui
# nomme la cause. Le « 2>/dev/null » remplace le message brut de df par celui-ci.
if ! espace_libre_mo="$(df -P -BM "$repertoire_swap" 2>/dev/null \
        | awk 'NR == 2 { gsub(/M/, "", $4); print $4 }')"; then
    error "Espace libre indéterminable sur $repertoire_swap : df a échoué."
    die "Vérifier que ce répertoire est monté et accessible."
fi
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
    #
    # Deux lectures en condition, pour la raison dite plus haut : sous la forme
    # « var="$(awk …)" », un /proc devenu illisible produisait deux lignes de
    # trap identiques et rien d'autre. La mesure conditionne ici une décision de
    # sûreté — faute de pouvoir la prendre, le script s'arrête plutôt que de
    # supposer une valeur.
    if ! swap_utilise_ko="$(awk -v cible="$FICHIER_SWAP" \
            'NR > 1 && $1 == cible { print $4 }' /proc/swaps 2>/dev/null)"; then
        error "Lecture de /proc/swaps impossible : la place occupée reste inconnue."
        die "Désactiver le swap sans cette mesure ferait tuer des processus."
    fi
    if ! ram_libre_ko="$(awk '/^MemAvailable:/ { print $2 }' /proc/meminfo 2>/dev/null)"; then
        error "Lecture de /proc/meminfo impossible : la mémoire disponible reste inconnue."
        die "Désactiver le swap sans cette mesure ferait tuer des processus."
    fi

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
    # Deux exécutions dans la même seconde produiraient le même nom : la seconde
    # sauvegarde écraserait la première. Un suffixe numérique est ajouté tant que
    # le nom est pris — même forme que configure-hostname.sh.
    #
    # L'horodatage est lu UNE FOIS, en contexte de condition. Sous la forme nue,
    # la substitution est noyée dans une chaîne, mais l'affectation échoue tout
    # autant si « date » échoue — un binaire homonyme en tête de PATH suffit — et
    # le trap ERR parle alors deux fois sans nommer la cause (TASK-018). Lu une
    # seule fois, il sert aussi de base aux noms suffixés : la boucle ne rappelle
    # plus « date » et ne peut donc plus mélanger deux horodatages.
    #
    # L'échec est fatal : /etc/fstab ne se modifie pas sans sauvegarde. Le swap
    # reste actif pour cette session — seule sa persistance manque, et la ligne à
    # ajouter est donnée pour qu'elle puisse l'être à la main.
    if ! horodatage="$(date '+%Y%m%d-%H%M%S')"; then
        error "Horodatage impossible à produire : « date » a échoué."
        error "/etc/fstab n'a pas été modifié, faute de pouvoir le sauvegarder."
        error "Le swap est actif pour cette session, mais pas au redémarrage."
        error "Ligne à ajouter : $LIGNE_FSTAB"
        die "Vérifier « date » dans le PATH, puis relancer."
    fi

    sauvegarde="/etc/fstab.bak-$horodatage"
    suffixe=1
    while [ -e "$sauvegarde" ]; do
        sauvegarde="/etc/fstab.bak-$horodatage-$suffixe"
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
