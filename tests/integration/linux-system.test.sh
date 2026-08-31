#!/usr/bin/env bash
# tests/integration/linux-system.test.sh — les six scripts de Linux/System, exécutés.
#
# Critères de TASK-004, éprouvés par l'exécution réelle et non par la lecture :
#
#   1. --help affiché, code 0                        groupe « préflight »
#   2. refus sans privilège pour les scripts modifiants  groupe « préflight »
#   3. --dry-run ne modifie aucun fichier            groupe « dry-run »
#   4. deux exécutions de suite laissent le système identique  groupe « idempotence »
#   5. system-info.sh tourne sans privilège, code 0  groupe « system-info »
#   6. option inconnue refusée avec le code 2        groupe « préflight »
#
# L'énoncé s'arrête à ces six critères. Ce fichier en éprouve un septième, de
# son propre chef, parce qu'il a de la valeur et que le groupe « préflight » le
# rendait accessible sans frais :
#
#   +. OS non supporté refusé (require_os)           groupe « préflight »
#
# CE FICHIER MODIFIE LE SYSTÈME. Il n'écrit rien tant qu'il n'a pas reconnu un
# système jetable (conteneur Docker, ou MGNET_TEST_JETABLE=1) : ailleurs, les
# groupes modifiants se déclarent NON EXÉCUTÉS plutôt que de réécrire
# /etc/hosts d'une machine de travail.
#
#   tests/env/run-in-container.sh -- tests/run.sh integration
#
# ---------------------------------------------------------------------------
# Comment l'idempotence est prouvée ici, et pourquoi la preuve tient
# ---------------------------------------------------------------------------
#
#   empreinte P0 -> exécution 1 -> empreinte A -> exécution 2 -> empreinte B
#
# « A == B » ne suffit pas. Sur un système déjà conforme, les deux exécutions ne
# font rien, les trois empreintes sont égales et le test passe sans rien
# prouver. C'est exactement ce que la règle « un conteneur neuf par cas » vise à
# empêcher. Chaque cas exige donc AUSSI « P0 != A » : le premier passage doit
# avoir réellement modifié quelque chose. Une preuve d'idempotence à vide
# devient alors un échec, et non un succès silencieux.
#
# Ce fichier tourne à l'intérieur d'un unique conteneur — c'est là que
# « tests/run.sh integration » est invoqué, et docker n'y est pas disponible
# pour en créer d'autres. Trois dispositions remplacent le conteneur neuf par
# cas, et sont vérifiées et non supposées :
#
#   - les groupes non modifiants passent en premier (préflight, system-info,
#     dry-run) ; le groupe « idempotence » est le dernier ;
#   - l'empreinte relevée juste avant le groupe « idempotence » est comparée à
#     « info-avant », relevée à l'ouverture du groupe « system-info ». Si elle a
#     bougé, le groupe entier est déclaré NON EXÉCUTÉ : on ne prouve pas une
#     idempotence depuis un état inconnu. Le groupe « préflight », antérieur à
#     « info-avant », échappe à cette garde — voir la note posée au-dessus du
#     contrôle lui-même ;
#   - les trois cas d'idempotence portent sur des fichiers DISJOINTS —
#     /etc/localtime et /etc/timezone, /etc/hosts, /etc/logrotate.d/<règle> —
#     aucun ne prépare le terrain d'un autre.
#
# ---------------------------------------------------------------------------
# Recouvrement assumé avec tests/acceptance/TASK-011-*
# ---------------------------------------------------------------------------
#
# TASK-011 éprouve déjà, dans onze conteneurs neufs, le préflight, les
# --dry-run et l'idempotence de cinq de ces six scripts. Ses assertions sont
# formulées autour des corrections d'analyse statique qu'elle portait (SC1087,
# export ASSUME_YES) et disparaîtront avec elle. Le niveau « integration » est
# le domicile durable de ces preuves : le recouvrement est ici assumé, borné à
# UN conteneur au lieu de onze, et signalé dans tests/README.md.
#
# Ce que ce fichier apporte que TASK-011 n'a pas :
#   - system-info.sh, qu'elle ne couvre que par « --help » ;
#   - l'exigence « P0 != A », qui interdit une idempotence prouvée à vide ;
#   - une empreinte de TOUT /etc, et non d'une liste de fichiers choisis
#     d'avance : un fichier inattendu est vu ;
#   - le cas « /etc/hosts déjà conforme par un alias », chemin de
#     hosts_deja_conforme() qu'aucun cas existant n'emprunte.

set -Eeuo pipefail

_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_dir/lib/common.sh" ] && [ "$_dir" != "/" ]; do _dir="$(dirname "$_dir")"; done
source "$_dir/lib/common.sh"
# shellcheck source=/dev/null
source "$SCRIPTS_ROOT/tests/lib/assert.sh"

SYS="$SCRIPTS_ROOT/Linux/System"

INFO_SH="$SYS/system-info.sh"
HOSTNAME_SH="$SYS/configure-hostname.sh"
LOGGING_SH="$SYS/configure-logging.sh"
SWAP_SH="$SYS/configure-swap.sh"
TIMEZONE_SH="$SYS/configure-timezone.sh"
UPDATE_SH="$SYS/update-system.sh"

# Les six scripts du répertoire. system-info.sh est le seul qui ne modifie
# rien : il figure dans le premier lot, pas dans le second.
SIX_SCRIPTS="$INFO_SH $HOSTNAME_SH $LOGGING_SH $SWAP_SH $TIMEZONE_SH $UPDATE_SH"
CINQ_MODIFIANTS="$HOSTNAME_SH $LOGGING_SH $SWAP_SH $TIMEZONE_SH $UPDATE_SH"

FUSEAU_CIBLE="Europe/Paris"

REP_TMP="$(mktemp -d)"
F_OUT="$REP_TMP/stdout"
F_ERR="$REP_TMP/stderr"
CODE=0

trap 'rm -rf "$REP_TMP"' EXIT

# ===================================================================
# Outillage
# ===================================================================

# lancer <commande...> — exécute dans un SOUS-SHELL et capture le code.
#
# Le sous-shell est indispensable : les scripts posent « set -Eeuo pipefail » et
# lib/common.sh un « trap ERR ». Un script qui meurt en 2 tuerait le harnais si
# on ne l'isolait pas. L'entrée standard est fermée : confirm() lit alors une
# réponse vide et refuse, ce qui rend les chemins « sans -y » observables.
lancer() {
    CODE=0
    ( "$@" ) >"$F_OUT" 2>"$F_ERR" </dev/null || CODE=$?
}

sortie()  { cat "$F_OUT"; }
erreur()  { cat "$F_ERR"; }

# empreinte <fichier> — état des fichiers que ces scripts peuvent toucher.
#
# TOUT /etc est relevé, contenu compris, et non une liste de fichiers arrêtée
# d'avance : c'est ce qui permet de voir une écriture qu'on n'attendait pas.
# 119 fichiers dans l'image de test, quelques dizaines de millisecondes.
#
# LOG_DIR est délibérément hors de l'empreinte : lib/common.sh y écrit un
# journal au seul chargement, avant même que le script n'ait lu ses arguments.
# L'y inclure rendrait toute empreinte différente de la précédente et aucun
# --dry-run ne pourrait jamais être déclaré inoffensif. Les écritures hors
# journaux sont surveillées séparément, par ecritures_depuis().
empreinte() {
    local destination="$1"
    local code=0

    {
        # « -exec … + » groupe les arguments : un seul cksum pour tout /etc.
        find /etc -type f -exec cksum {} + 2>/dev/null | sort
        find /etc -type l -printf 'lien %p -> %l\n' 2>/dev/null | sort
        printf 'hostname %s\n' "$(hostname)"
        printf 'swaps %s\n' "$(cksum < /proc/swaps)"
        if [ -e /swapfile ]; then
            printf 'swapfile %s octets\n' "$(stat -c %s /swapfile)"
        else
            printf 'swapfile absent\n'
        fi
    } > "$destination" || code=$?

    # find rend 1 dès qu'un fichier disparaît entre le parcours et le cksum. Le
    # code est relevé plutôt qu'ignoré : un relevé incomplet fausserait les
    # comparaisons qui suivent, et doit se voir à l'écran.
    if [ "$code" -ne 0 ]; then
        warn "Relevé d'empreinte incomplet (code $code) : $destination"
    fi
}

# ecritures_depuis <témoin> <destination> — fichiers modifiés depuis le témoin.
#
# La référence est un fichier et non une date : « find -newer » compare à la
# précision du système de fichiers, là où « -newermt @secondes » arrondit et
# ferait remonter tout ce que le conteneur a écrit dans la même seconde.
#
# /var/log est exclu — c'est le domicile des journaux, dont l'écriture n'est
# pas une modification du système au sens de --dry-run. Les caches apt et la
# base dpkg le sont aussi : update-system.sh rafraîchit l'index de paquets même
# en --dry-run, et son aide le dit.
ecritures_depuis() {
    local temoin="$1" destination="$2"
    local racine code=0
    local -a racines=()

    for racine in /etc /root /usr /opt /srv /var /boot; do
        if [ -d "$racine" ]; then
            racines+=("$racine")
        fi
    done

    find "${racines[@]}" -newer "$temoin" \
        -not -path '/var/log' \
        -not -path '/var/log/*' \
        -not -path '/var/cache/apt' \
        -not -path '/var/cache/apt/*' \
        -not -path '/var/lib/apt' \
        -not -path '/var/lib/apt/*' \
        -not -path '/var/lib/dpkg' \
        -not -path '/var/lib/dpkg/*' \
        2>/dev/null | sort > "$destination" || code=$?

    if [ "$code" -ne 0 ]; then
        warn "Relevé des écritures incomplet (code $code) : $destination"
    fi
}

# assert_empreinte_egale <avant> <après> <libellé>
assert_empreinte_egale() {
    local avant="$1" apres="$2" libelle="$3"
    if diff -u "$avant" "$apres" > "$REP_TMP/diff" 2>&1; then
        ok "$libelle"
    else
        ko "$libelle" "$(head -n 12 "$REP_TMP/diff" | tr '\n' '|')"
    fi
}

# assert_empreinte_differente <avant> <après> <libellé>
# Garde anti-preuve-à-vide : une idempotence mesurée sur un système que la
# première exécution n'a pas touché ne prouve rien.
assert_empreinte_differente() {
    local avant="$1" apres="$2" libelle="$3"
    if diff -q "$avant" "$apres" >/dev/null 2>&1; then
        ko "$libelle" "aucune modification relevée : la preuve d'idempotence serait vide"
    else
        ok "$libelle"
    fi
}

# assert_aucune_ecriture <témoin> <libellé>
assert_aucune_ecriture() {
    local temoin="$1" libelle="$2"
    ecritures_depuis "$temoin" "$REP_TMP/ecritures"
    if [ -s "$REP_TMP/ecritures" ]; then
        ko "$libelle" "$(tr '\n' ' ' < "$REP_TMP/ecritures")"
    else
        ok "$libelle"
    fi
}

# ===================================================================
# Reconnaissance de l'environnement
# ===================================================================
titre "0. Environnement"

EST_LINUX="false"
if [ "$(uname -s 2>/dev/null)" = "Linux" ]; then
    EST_LINUX="true"
fi

EST_DEBIAN="false"
if [ -r /etc/os-release ]; then
    identifiant="$(sed -n 's/^ID=//p' /etc/os-release | tr -d '"')"
    case "$identifiant" in
        debian|ubuntu) EST_DEBIAN="true" ;;
    esac
fi

EST_ROOT="false"
if [ "$(id -u)" -eq 0 ]; then
    EST_ROOT="true"
fi

# Un système jetable, et rien d'autre, autorise les groupes modifiants.
JETABLE="false"
if [ -f /.dockerenv ]; then
    JETABLE="true"
elif grep -qE '(docker|containerd|lxc)' /proc/1/cgroup 2>/dev/null; then
    JETABLE="true"
elif [ "${MGNET_TEST_JETABLE:-}" = "1" ]; then
    JETABLE="true"
fi

info "Linux : $EST_LINUX — Debian/Ubuntu : $EST_DEBIAN — root : $EST_ROOT — jetable : $JETABLE"

# Lanceur non privilégié. Trois candidats éprouvés dans l'ordre : le premier qui
# abaisse RÉELLEMENT l'UID est retenu. Sans lui, les cas de privilège sont
# déclarés NON EXÉCUTÉS — jamais réussis.
LANCEUR_SANS_ROOT=()
LOG_DIR_NOBODY="/tmp/mgnet-integration-nobody"

choisir_lanceur_sans_root() {
    local uid=""

    if [ "$EST_ROOT" = "false" ]; then
        LANCEUR_SANS_ROOT=(env)
        return 0
    fi

    if command -v setpriv >/dev/null 2>&1; then
        uid="$(setpriv --reuid=65534 --regid=65534 --clear-groups id -u 2>/dev/null)" || uid=""
        if [ "$uid" = "65534" ]; then
            LANCEUR_SANS_ROOT=(setpriv --reuid=65534 --regid=65534 --clear-groups)
            return 0
        fi
    fi

    if command -v runuser >/dev/null 2>&1; then
        uid="$(runuser -u nobody -- id -u 2>/dev/null)" || uid=""
        if [ "$uid" = "65534" ]; then
            LANCEUR_SANS_ROOT=(runuser -u nobody --)
            return 0
        fi
    fi

    return 1
}

SANS_ROOT_DISPONIBLE="false"
if choisir_lanceur_sans_root; then
    SANS_ROOT_DISPONIBLE="true"
    info "Lanceur non privilégié : ${LANCEUR_SANS_ROOT[*]}"
fi

# sans_root <commande...> — la commande, exécutée sans privilège.
# LOG_DIR part dans /tmp : sans cela lib/common.sh tenterait d'écrire son
# journal dans le dépôt monté, qui n'appartient pas à « nobody ».
sans_root() {
    lancer env "LOG_DIR=$LOG_DIR_NOBODY" "${LANCEUR_SANS_ROOT[@]}" "$@"
}

# Rien à faire hors Linux : ces scripts n'y démarrent même pas.
if [ "$EST_LINUX" != "true" ]; then
    saute "l'ensemble des cas de Linux/System" "cet hôte n'est pas un Linux — ces scripts ne s'y exécutent pas"
    bilan "TASK-004 / Linux/System"
    exit 0
fi

# logrotate conditionne configure-logging.sh. Il est absent de l'image de test :
# la tentative d'installation a lieu ICI, avant toute empreinte, pour que la
# mutation de la base dpkg ne vienne pas polluer une comparaison.
LOGROTATE_DISPONIBLE="false"
if command -v logrotate >/dev/null 2>&1; then
    LOGROTATE_DISPONIBLE="true"
elif [ "$EST_ROOT" = "true" ] && [ "$JETABLE" = "true" ]; then
    info "logrotate absent : tentative d'installation…"
    if apt-get update -qq >/dev/null 2>&1 && apt-get install -y -qq logrotate >/dev/null 2>&1; then
        LOGROTATE_DISPONIBLE="true"
        info "logrotate installé."
    fi
fi

REGLE_LOGROTATE="/etc/logrotate.d/$(basename "$LOG_DIR")"

# ===================================================================
# 1. Préflight — aide, option inconnue, privilèges, OS
# ===================================================================
titre "1. Préflight des six scripts"

for script in $SIX_SCRIPTS; do
    nom="$(basename "$script")"

    lancer bash "$script" --help
    assert_code 0 "$CODE" "$nom --help sort en 0"
    assert_contient "$(sortie)" "Usage :" "$nom --help écrit son usage sur stdout"

    lancer bash "$script" -h
    assert_code 0 "$CODE" "$nom -h sort en 0"

    lancer bash "$script" --option-qui-n-existe-pas
    assert_code 2 "$CODE" "$nom refuse une option inconnue"
    assert_contient "$(erreur)" "Option inconnue" "$nom nomme l'option inconnue"
done

# --- Refus sans privilège ---------------------------------------------------
# require_root sort en 1 : dans ce dépôt, le code 2 est réservé à l'erreur
# d'usage. system-info.sh est absent de cette liste — son cas est l'inverse,
# et il est traité au groupe suivant.
if [ "$SANS_ROOT_DISPONIBLE" != "true" ]; then
    for script in $CINQ_MODIFIANTS; do
        saute "$(basename "$script") refuse de s'exécuter sans privilège" \
            "aucun lanceur ne parvient à abaisser l'UID sur cet hôte"
    done
else
    sans_root bash "$HOSTNAME_SH" essai-mgnet
    assert_code 1 "$CODE" "configure-hostname.sh refuse de s'exécuter sans privilège"
    assert_contient "$(erreur)" "doit être exécuté en root" "configure-hostname.sh dit pourquoi il refuse"

    sans_root bash "$TIMEZONE_SH" "$FUSEAU_CIBLE"
    assert_code 1 "$CODE" "configure-timezone.sh refuse de s'exécuter sans privilège"

    sans_root bash "$LOGGING_SH"
    assert_code 1 "$CODE" "configure-logging.sh refuse de s'exécuter sans privilège"

    sans_root bash "$SWAP_SH" 512M
    assert_code 1 "$CODE" "configure-swap.sh refuse de s'exécuter sans privilège"

    sans_root bash "$UPDATE_SH"
    assert_code 1 "$CODE" "update-system.sh refuse de s'exécuter sans privilège"

    # L'erreur d'usage prime sur le manque de privilège : sinon un appel mal
    # formé serait masqué par un message de permission.
    sans_root bash "$UPDATE_SH" --option-qui-n-existe-pas
    assert_code 2 "$CODE" "update-system.sh : l'option inconnue prime sur le manque de privilège"
fi

# --- Refus d'un OS non supporté --------------------------------------------
# update-system.sh est le seul des six à appeler require_os. /etc/os-release
# est un fichier ordinaire de l'image : le remplacer le temps d'un appel est le
# seul moyen d'éprouver ce refus sans une seconde image. Il est remis en place
# immédiatement, et l'empreinte du groupe suivant le vérifie.
if [ "$EST_ROOT" = "true" ] && [ "$JETABLE" = "true" ]; then
    cp /etc/os-release "$REP_TMP/os-release.origine"
    printf 'ID=fedora\nVERSION_ID="41"\nPRETTY_NAME="Fedora (simulée par le test)"\n' > /etc/os-release
    lancer bash "$UPDATE_SH" --dry-run
    cat "$REP_TMP/os-release.origine" > /etc/os-release

    assert_code 1 "$CODE" "update-system.sh refuse un OS non supporté"
    assert_contient "$(erreur)" "Distribution non supportée" "update-system.sh nomme la distribution refusée"

    if cmp -s /etc/os-release "$REP_TMP/os-release.origine"; then
        ok "/etc/os-release a été remis dans son état d'origine"
    else
        ko "/etc/os-release a été remis dans son état d'origine" "le fichier diffère de la sauvegarde"
    fi
else
    saute "refus d'un OS non supporté par update-system.sh" \
        "exige root sur un système jetable — /etc/os-release doit être remplacé le temps d'un appel"
fi

# ===================================================================
# 2. system-info.sh — lecture seule, sans privilège
# ===================================================================
# Le seul des six qu'aucun test d'exécution ne couvrait jusqu'ici au-delà de
# « --help ». C'est aussi le seul qui ne doit exiger aucun privilège.
titre "2. system-info.sh"

SECTIONS="Système Processeur Mémoire Stockage Réseau Identité"

empreinte "$REP_TMP/info-avant"
touch "$REP_TMP/temoin-info"

lancer bash "$INFO_SH"
assert_code 0 "$CODE" "system-info.sh sort en 0"

texte="$(sortie)"
for section in $SECTIONS; do
    assert_contient "$texte" "$section" "system-info.sh affiche la section « $section »"
done
assert_contient "$texte" "Distribution" "system-info.sh affiche la distribution"

empreinte "$REP_TMP/info-apres"
assert_empreinte_egale "$REP_TMP/info-avant" "$REP_TMP/info-apres" \
    "system-info.sh ne modifie aucun fichier"
assert_aucune_ecriture "$REP_TMP/temoin-info" \
    "system-info.sh n'écrit rien hors du répertoire de journaux"

# Critère 5 : sans privilège, et en 0.
if [ "$SANS_ROOT_DISPONIBLE" != "true" ]; then
    saute "system-info.sh s'exécute sans privilège" \
        "aucun lanceur ne parvient à abaisser l'UID sur cet hôte"
else
    sans_root bash "$INFO_SH"
    assert_code 0 "$CODE" "system-info.sh s'exécute sans privilège et sort en 0"
    assert_contient "$(sortie)" "Distribution" "system-info.sh non privilégié produit son rapport"
    rm -rf "$LOG_DIR_NOBODY"
fi

# Critère 4 pour ce script : deux exécutions de suite, système identique.
empreinte "$REP_TMP/info-idem-a"
lancer bash "$INFO_SH"
assert_code 0 "$CODE" "system-info.sh seconde exécution sort en 0"
empreinte "$REP_TMP/info-idem-b"
assert_empreinte_egale "$REP_TMP/info-idem-a" "$REP_TMP/info-idem-b" \
    "system-info.sh exécuté deux fois laisse le système identique"

# ===================================================================
# 3. --dry-run — critère 3
# ===================================================================
# Une empreinte avant, une après, et la liste des fichiers écrits entre les
# deux. L'empreinte seule ne verrait pas un fichier créé hors de /etc ; la
# liste seule ne verrait pas une réécriture à l'identique de la même taille.
# Les deux ensemble ne laissent pas de trou.
titre "3. --dry-run des quatre scripts modifiant des fichiers"

dry_run_inoffensif() {
    local libelle="$1"; shift

    empreinte "$REP_TMP/dry-avant"
    touch "$REP_TMP/temoin-dry"
    lancer "$@"

    assert_code 0 "$CODE" "$libelle sort en 0"
    empreinte "$REP_TMP/dry-apres"
    assert_empreinte_egale "$REP_TMP/dry-avant" "$REP_TMP/dry-apres" \
        "$libelle ne modifie aucun fichier"
    assert_aucune_ecriture "$REP_TMP/temoin-dry" \
        "$libelle n'écrit rien hors du répertoire de journaux"
}

if [ "$EST_ROOT" != "true" ]; then
    saute "les quatre --dry-run" "require_root arrête ces scripts avant leur mode --dry-run"
elif [ "$EST_DEBIAN" != "true" ]; then
    saute "les quatre --dry-run" "l'hôte n'est ni Debian ni Ubuntu"
else
    # Le nom demandé diffère du nom courant : sans cela le script sortirait sur
    # « Rien à faire » et le --dry-run ne serait pas atteint.
    dry_run_inoffensif "configure-hostname.sh --dry-run" \
        bash "$HOSTNAME_SH" essai-integration --dry-run
    assert_contient "$(erreur)" "aucune modification effectuée" \
        "configure-hostname.sh --dry-run annonce qu'il n'a rien modifié"

    dry_run_inoffensif "configure-timezone.sh --dry-run" \
        bash "$TIMEZONE_SH" "$FUSEAU_CIBLE" --dry-run
    assert_contient "$(erreur)" "aucune modification effectuée" \
        "configure-timezone.sh --dry-run annonce qu'il n'a rien modifié"

    dry_run_inoffensif "configure-swap.sh --dry-run" \
        bash "$SWAP_SH" 512M --dry-run
    assert_contient "$(erreur)" "aucune modification effectuée" \
        "configure-swap.sh --dry-run annonce qu'il n'a rien modifié"

    # Sans taille, configure-swap.sh n'est qu'un diagnostic : il ne doit pas
    # davantage écrire.
    dry_run_inoffensif "configure-swap.sh sans taille" bash "$SWAP_SH"

    if [ "$LOGROTATE_DISPONIBLE" != "true" ]; then
        saute "configure-logging.sh --dry-run" "logrotate absent de l'image et non installable"
    else
        dry_run_inoffensif "configure-logging.sh --dry-run" \
            bash "$LOGGING_SH" --dry-run
        assert_contient "$(erreur)" "[dry-run] Créerait $REGLE_LOGROTATE" \
            "configure-logging.sh --dry-run annonce la règle sans la déposer"
        if [ -f "$REGLE_LOGROTATE" ]; then
            ko "configure-logging.sh --dry-run ne dépose pas la règle" "$REGLE_LOGROTATE créé"
        else
            ok "configure-logging.sh --dry-run ne dépose pas la règle"
        fi
    fi
fi

# ===================================================================
# 4. Idempotence — critère 4
# ===================================================================
titre "4. Idempotence — deux exécutions de suite"

# idempotent <libellé> <motif-attendu-au-second-passage> -- <commande...>
#
# Le protocole complet, garde anti-preuve-à-vide comprise.
idempotent() {
    local libelle="$1" motif="$2"; shift 2
    if [ "${1:-}" = "--" ]; then
        shift
    fi

    empreinte "$REP_TMP/idem-p0"

    lancer "$@"
    assert_code 0 "$CODE" "$libelle : première exécution sort en 0"
    empreinte "$REP_TMP/idem-a"
    assert_empreinte_differente "$REP_TMP/idem-p0" "$REP_TMP/idem-a" \
        "$libelle : la première exécution modifie réellement le système"

    lancer "$@"
    assert_code 0 "$CODE" "$libelle : seconde exécution sort en 0"
    assert_contient "$(erreur)" "$motif" "$libelle : la seconde exécution annonce n'avoir rien à faire"
    empreinte "$REP_TMP/idem-b"
    assert_empreinte_egale "$REP_TMP/idem-a" "$REP_TMP/idem-b" \
        "$libelle : la seconde exécution laisse le système identique"
}

GROUPE_IDEMPOTENCE="oui"
if [ "$EST_ROOT" != "true" ]; then
    GROUPE_IDEMPOTENCE="require_root arrête ces scripts avant toute modification"
elif [ "$JETABLE" != "true" ]; then
    GROUPE_IDEMPOTENCE="cet hôte n'est pas un système jetable — /etc/hosts et /etc/localtime ne seront pas réécrits"
elif [ "$EST_DEBIAN" != "true" ]; then
    GROUPE_IDEMPOTENCE="l'hôte n'est ni Debian ni Ubuntu"
fi

# Ce contrôle compare l'état courant à « info-avant », relevée à l'ouverture du
# groupe « system-info » — et non à l'état du tout début du fichier. Ce qu'il
# prouve exactement : ni « system-info » ni « dry-run » n'ont modifié le système.
# Une dérive causée par le groupe « préflight », qui les précède, lui
# échapperait.
#
# Le trou est résiduel et couvert autrement : la seule écriture du préflight est
# le remplacement temporaire de /etc/os-release pour éprouver require_os, et sa
# restauration porte sa propre assertion (« /etc/os-release a été remis dans son
# état d'origine »). Aucun autre cas du préflight n'écrit quoi que ce soit.
if [ "$GROUPE_IDEMPOTENCE" = "oui" ]; then
    empreinte "$REP_TMP/etat-avant-idempotence"
    if diff -u "$REP_TMP/info-avant" "$REP_TMP/etat-avant-idempotence" > "$REP_TMP/derive" 2>&1; then
        ok "l'état de départ du groupe « idempotence » est intact — les groupes précédents n'ont rien modifié"
    else
        GROUPE_IDEMPOTENCE="le système a dérivé pendant les groupes précédents — $(head -n 8 "$REP_TMP/derive" | tr '\n' '|')"
    fi
fi

if [ "$GROUPE_IDEMPOTENCE" != "oui" ]; then
    saute "configure-timezone.sh exécuté deux fois de suite" "$GROUPE_IDEMPOTENCE"
    saute "configure-hostname.sh exécuté deux fois de suite" "$GROUPE_IDEMPOTENCE"
    saute "configure-logging.sh exécuté deux fois de suite" "$GROUPE_IDEMPOTENCE"
    saute "configure-swap.sh exécuté deux fois de suite" "$GROUPE_IDEMPOTENCE"
    saute "update-system.sh exécuté deux fois de suite" "$GROUPE_IDEMPOTENCE"
else
    # --- configure-timezone.sh : /etc/localtime et /etc/timezone ------------
    if [ ! -f "/usr/share/zoneinfo/$FUSEAU_CIBLE" ]; then
        saute "configure-timezone.sh exécuté deux fois de suite" \
            "/usr/share/zoneinfo/$FUSEAU_CIBLE absent de cet hôte"
    else
        idempotent "configure-timezone.sh $FUSEAU_CIBLE" "Rien à faire" \
            -- bash "$TIMEZONE_SH" "$FUSEAU_CIBLE" -y
        lien="$(readlink -f /etc/localtime)"
        assert_egal "/usr/share/zoneinfo/$FUSEAU_CIBLE" "$lien" \
            "/etc/localtime pointe bien sur $FUSEAU_CIBLE après les deux passages"
    fi

    # --- configure-logging.sh : /etc/logrotate.d/<règle> --------------------
    if [ "$LOGROTATE_DISPONIBLE" != "true" ]; then
        saute "configure-logging.sh exécuté deux fois de suite" \
            "logrotate absent de l'image et non installable"
    else
        idempotent "configure-logging.sh" "déjà en place et à jour" \
            -- bash "$LOGGING_SH"
    fi

    # --- configure-hostname.sh : /etc/hosts ---------------------------------
    # Le nom demandé est celui de la machine : le changement porte alors sur le
    # seul /etc/hosts. Renommer réellement exige CAP_SYS_ADMIN — déclaré NON
    # EXÉCUTÉ plus bas.
    nom_courant="$(hostname)"
    idempotent "configure-hostname.sh $nom_courant" "Rien à faire" \
        -- bash "$HOSTNAME_SH" "$nom_courant" -y

    lignes="$(grep -cE '^[[:space:]]*127\.0\.1\.1[[:space:]]' /etc/hosts)" || lignes="0"
    assert_egal "1" "$lignes" "/etc/hosts porte exactement une ligne 127.0.1.1 après deux passages"

    sauvegardes="$(find /etc -maxdepth 1 -name 'hosts.bak-*' | wc -l | tr -d ' ')"
    assert_egal "1" "$sauvegardes" \
        "une seule sauvegarde de /etc/hosts a été créée — le second passage n'en refait pas"

    # Chemin de hosts_deja_conforme() qu'aucun autre cas n'emprunte : le nom
    # demandé n'est pas le nom principal de la ligne, mais l'un de ses alias.
    # Le script doit conclure « rien à faire » et surtout ne pas réécrire la
    # ligne sur son modèle, ce qui ferait perdre les alias en place.
    printf '127.0.0.1\tlocalhost\n127.0.1.1\tautre-nom\t%s\n' "$nom_courant" > /etc/hosts
    empreinte "$REP_TMP/alias-avant"
    lancer bash "$HOSTNAME_SH" "$nom_courant" -y
    assert_code 0 "$CODE" "configure-hostname.sh sort en 0 quand le nom n'est qu'un alias de la ligne"
    assert_contient "$(erreur)" "Rien à faire" \
        "configure-hostname.sh reconnaît le nom en position d'alias"
    empreinte "$REP_TMP/alias-apres"
    assert_empreinte_egale "$REP_TMP/alias-avant" "$REP_TMP/alias-apres" \
        "configure-hostname.sh ne réécrit pas une ligne dont le nom est déjà un alias"

    # --- configure-swap.sh : --dry-run seulement ----------------------------
    # L'activation exige CAP_SYS_ADMIN, refusé au conteneur : seul le chemin
    # sans écriture est éprouvé ici, deux fois de suite.
    empreinte "$REP_TMP/swap-a"
    lancer bash "$SWAP_SH" 512M --dry-run
    assert_code 0 "$CODE" "configure-swap.sh --dry-run première exécution sort en 0"
    lancer bash "$SWAP_SH" 512M --dry-run
    assert_code 0 "$CODE" "configure-swap.sh --dry-run seconde exécution sort en 0"
    empreinte "$REP_TMP/swap-b"
    assert_empreinte_egale "$REP_TMP/swap-a" "$REP_TMP/swap-b" \
        "configure-swap.sh --dry-run exécuté deux fois laisse le système identique"

    # --- update-system.sh : --dry-run seulement -----------------------------
    # « apt-get upgrade » réel est hors du périmètre de TASK-004 : l'image n'a
    # aucun paquet obsolète et une mise à jour dans un conteneur de test
    # n'apporterait aucune information. Le chemin sans écriture, lui, se
    # vérifie : l'index de paquets est rafraîchi, /etc ne bouge pas.
    paquets_avant="$(dpkg-query -W -f='${Package} ${Version}\n' | sort | cksum)"
    empreinte "$REP_TMP/update-a"
    lancer bash "$UPDATE_SH" --dry-run
    assert_code 0 "$CODE" "update-system.sh --dry-run première exécution sort en 0"
    lancer bash "$UPDATE_SH" --dry-run
    assert_code 0 "$CODE" "update-system.sh --dry-run seconde exécution sort en 0"
    empreinte "$REP_TMP/update-b"
    assert_empreinte_egale "$REP_TMP/update-a" "$REP_TMP/update-b" \
        "update-system.sh --dry-run exécuté deux fois laisse /etc identique"
    paquets_apres="$(dpkg-query -W -f='${Package} ${Version}\n' | sort | cksum)"
    assert_egal "$paquets_avant" "$paquets_apres" \
        "update-system.sh --dry-run n'installe aucun paquet"
fi

# ===================================================================
# 5. Hors de portée de cet environnement
# ===================================================================
# Ces lignes ne sont pas des cas manqués : ce sont des cas dont on sait qu'ils
# ne peuvent pas être joués ici. Les taire ferait croire à une couverture
# complète. Ils attendent le profil « container-systemd ».
titre "5. Hors de portée de cet environnement"

saute "configure-timezone.sh appliquant le fuseau par timedatectl" \
    "le profil debian n'a pas systemd — seul le repli /etc/localtime a été éprouvé"
saute "configure-hostname.sh changeant réellement le nom de la machine" \
    "hostnamectl absent et « hostname <nom> » exige CAP_SYS_ADMIN, refusé au conteneur"
saute "configure-swap.sh créant, activant et inscrivant un fichier d'échange" \
    "swapon exige CAP_SYS_ADMIN, refusé au conteneur non privilégié"
saute "update-system.sh appliquant réellement apt-get upgrade" \
    "exclu par TASK-004 : l'image n'a aucun paquet obsolète, la mise à jour n'apprendrait rien"
saute "configure-logging.sh sur un système sans le groupe « adm »" \
    "l'image Debian le fournit toujours — la branche GROUPE_LOGS=root reste sans preuve"

# ===================================================================
# Nettoyage
# ===================================================================
# Le répertoire jetable est supprimé, et son absence vérifiée : le trap EXIT
# n'est qu'un filet, il ne rend compte de rien.
titre "6. Nettoyage"

diff_final="$REP_TMP"
rm -rf "$REP_TMP"
rm -rf "$LOG_DIR_NOBODY"

if [ -e "$diff_final" ]; then
    ko "le répertoire de travail jetable est supprimé" "$diff_final subsiste"
else
    ok "le répertoire de travail jetable est supprimé"
fi

bilan "TASK-004 / Linux/System"
