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
# TASK-016 y ajoute le verrouillage de quatre corrections de codes de retour et
# de messages, groupe « 1 bis » :
#
#   a. --file sans valeur : code 2, message préfixé [ERROR], UNE ligne
#   b. valeur d'argument invalide : code 2 sur les trois scripts concernés
#   c. le trap ERR ne double plus le diagnostic de configure-swap.sh
#   d. un argument obligatoire manquant ne déverse plus l'aide sur stderr
#
# et la non-régression qui les borne, groupe « 1 ter » : sans privilège mais
# avec des arguments valides, un script rend toujours 1 — un privilège
# insuffisant est un échec d'exécution, pas une erreur d'usage (ADR-0003,
# décision 10). Avec une option inconnue ou une valeur invalide, il rend 2 :
# les arguments sont vérifiés avant les privilèges.
#
# TASK-017 y ajoute le verrouillage de la validation de --file, section 5 du
# groupe « 1 bis » et groupe « 3 bis » :
#
#   e. une valeur commençant par un tiret est refusée en 2, sans que dirname
#      la voie ni que le trap ERR double le diagnostic
#   f. un chemin relatif est refusé en 2, et rien ne naît dans le répertoire
#      courant — le cas grave, éprouvé avec SRV_SWAP_SIZE imposé
#   g. --dry-run et -y placés APRÈS un --file valide restent actifs : c'est
#      l'assertion qui manquait, et la seule qui prouve que --file ne consomme
#      plus l'option suivante
#
# TASK-019 y ajoute le verrouillage du contrôle de la NATURE de la cible,
# section 6 du groupe « 1 bis », deux cas nominaux au groupe « 3 » et le groupe
# « 3 ter » :
#
#   h. un fichier ordinaire existant est refusé en 2 et reste INTACT — contenu
#      et inode relevés avant et après ; c'est le cas qui motive la tâche, le
#      « rm -f » du script le supprimait sur un simple oui
#   i. un répertoire et « / » sont refusés en 2, sans message brut de rm ni
#      ligne de trap, avec un décompte MESURÉ des lignes [ERROR]
#   j. les deux cibles nominales continuent de passer : le chemin inexistant
#      (« créer »), et le fichier d'échange inactif reconnu à sa signature
#      SWAPSPACE2 (« remplacer ») — seule preuve directe de cette lecture
#   k. le chemin par défaut /swapfile est contrôlé lui aussi, et le contrôle
#      reste APRÈS require_root : sans privilège, le script rend toujours 1
#
# Le second tour de TASK-019 — valider_fichier_swap prend un paramètre de moment,
# « avant-root » ou « apres-root » — ajoute les cas f et g de cette section 6 :
#
#   l. les cinq refus valent AUSSI sans privilège, en 2 et en quatre lignes :
#      les arguments se jugent avant les privilèges, et l'aiguillage sur le
#      moment n'a différé aucun d'eux
#   m. le SEUL verdict différé est celui d'une cible illisible : sans privilège
#      elle rend 1 et non 2 — la régression que le relecteur avait mesurée —
#      et en root le refus ordinaire tranche, en 2
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

# lancer_depuis <répertoire> <commande...> — « lancer », depuis un répertoire
# de travail donné.
#
# Le « cd » a lieu DANS le sous-shell : le répertoire courant du harnais n'est
# jamais déplacé, et un cas qui échoue ne laisse pas les suivants ailleurs.
# Utile au seul cas où le répertoire courant est l'objet même de la preuve — un
# chemin relatif donné à --file y ferait naître le fichier d'échange.
lancer_depuis() {
    local repertoire="$1"; shift
    CODE=0
    ( cd "$repertoire" && "$@" ) >"$F_OUT" 2>"$F_ERR" </dev/null || CODE=$?
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

# empreinte_fichier <chemin> — l'état d'UN fichier, contenu compris.
#
# L'empreinte de tout /etc, plus haut, sert à prouver qu'un script n'a rien
# touché. Celle-ci sert l'inverse : montrer qu'un fichier NOMMÉMENT confié à un
# script qui s'apprêtait à le supprimer est ressorti intact. Elle relève le
# contenu (cksum), la taille, l'inode et la date de modification : un fichier
# supprimé puis recréé à l'identique — ce que ferait « rm -f » suivi d'une
# création — changerait d'inode même si le contenu revenait par miracle.
#
# « cksum < fichier » plutôt que « cksum fichier » : la sortie ne porte alors
# pas le nom du fichier, et l'empreinte reste comparable telle quelle.
#
# ABSENT est une valeur d'empreinte à part entière : comparer deux relevés dont
# le premier vaut ABSENT est une preuve vide, et les cas qui l'emploient posent
# une garde explicite avant de comparer.
empreinte_fichier() {
    local chemin="$1"
    if [ -e "$chemin" ]; then
        printf '%s | %s' "$(cksum < "$chemin")" "$(stat -c '%s %i %Y' "$chemin")"
    else
        printf 'ABSENT'
    fi
}

# --- Mesure du VOLUME de stderr --------------------------------------------
# Ce que ces deux fonctions permettent d'exiger n'est pas dans le contenu d'un
# message mais dans sa QUANTITÉ : « une seule ligne », « une seule ligne
# [ERROR] ». C'est la seule forme d'assertion qui empêche une aide entière ou un
# second diagnostic de revenir sur stderr — une assertion de contenu reste verte
# pendant qu'on ajoute des lignes autour d'elle.
#
# Le « || [ -n "$ligne" ] » compte la dernière ligne même si le fichier ne se
# termine pas par un saut de ligne : sans lui, un diagnostic sans « \n » final
# serait décompté à zéro et l'assertion passerait pour de mauvaises raisons.

# nb_lignes_erreur — nombre de lignes de stderr du dernier « lancer ».
nb_lignes_erreur() {
    local ligne n=0
    while IFS= read -r ligne || [ -n "$ligne" ]; do
        n=$(( n + 1 ))
    done < "$F_ERR"
    printf '%s' "$n"
}

# nb_lignes_contenant <motif> — lignes de stderr portant ce motif LITTÉRAL.
# « contient » vient de tests/lib/assert.sh : les crochets de [ERROR] y sont
# littéraux, là où un grep les prendrait pour une classe de caractères.
nb_lignes_contenant() {
    local motif="$1"
    local ligne n=0
    while IFS= read -r ligne || [ -n "$ligne" ]; do
        if contient "$ligne" "$motif"; then
            n=$(( n + 1 ))
        fi
    done < "$F_ERR"
    printf '%s' "$n"
}

# assert_au_plus <maximum> <obtenu> <libellé>
# Une borne, et non une égalité : elle laisse la place à une reformulation du
# diagnostic sans laisser passer les vingt-huit lignes d'une aide.
assert_au_plus() {
    local maximum="$1" obtenu="$2" libelle="$3"
    if [ "$obtenu" -le "$maximum" ] 2>/dev/null; then
        ok "$libelle — $obtenu ligne(s), $maximum au maximum"
    else
        ko "$libelle" "au plus $maximum ligne(s) attendue(s), obtenu $obtenu"
    fi
}

# valeur_imposee_par_config <variable> — la variable est-elle déjà fournie ?
#
# Les cas « argument obligatoire manquant » n'ont de sens que si config/server.env
# ne fournit pas la valeur : le script la prendrait alors et ne diagnostiquerait
# rien. lib/common.sh charge ce fichier avec « set -a » depuis TASK-015, donc la
# variable est exportée jusqu'ici ; le contrôle du fichier double la vérification
# pour le cas où elle serait vide mais définie.
SERVER_ENV="$SCRIPTS_ROOT/config/server.env"
valeur_imposee_par_config() {
    local variable="$1"
    if [ -n "${!variable:-}" ]; then
        return 0
    fi
    if [ -f "$SERVER_ENV" ] \
        && grep -qE "^[[:space:]]*(export[[:space:]]+)?$variable=." "$SERVER_ENV"; then
        return 0
    fi
    return 1
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

# ===================================================================
# 1 bis. Erreurs d'usage — les quatre corrections de TASK-016
# ===================================================================
# Ces cas sont placés dans le groupe « préflight » parce qu'ils n'écrivent RIEN :
# chacun meurt pendant l'analyse des arguments ou la validation, avant
# require_root et avant la moindre modification. Le groupe reste non modifiant,
# et la garde d'état du groupe « idempotence » n'en est pas troublée.
#
# La convention verrouillée ici est celle de docs/architecture-technique.md §6 :
#
#   2  erreur d'usage      option inconnue, argument manquant, VALEUR INVALIDE
#   1  échec d'exécution   privilège insuffisant, dépendance absente
#
# Les quatre défauts que TASK-016 a corrigés étaient tous des écarts à cette
# règle, et aucune assertion ne les voyait — c'est ce trou que ce sous-groupe
# ferme.
titre "1 bis. Erreurs d'usage — codes, préfixes et volume de stderr"

# --- 1. Un argument d'option manquant : code 2, préfixé, en UNE ligne -------
# « --file » était lu par « FICHIER_SWAP="${1:?--file attend un chemin}" ». Cette
# expansion écrit un message brut de bash — sans préfixe [ERROR], précédé du nom
# du script et d'un numéro de ligne — et fait sortir le shell en 1. Les trois
# assertions ferment trois aspects distincts du défaut : le code, la forme du
# message, et son volume.
lancer bash "$SWAP_SH" --file
assert_code 2 "$CODE" "configure-swap.sh --file sans valeur : erreur d'usage"
assert_contient "$(erreur)" "[ERROR] --file attend un chemin." \
    "configure-swap.sh --file sans valeur : message préfixé [ERROR]"
assert_egal "1" "$(nb_lignes_erreur)" \
    "configure-swap.sh --file sans valeur : une seule ligne sur stderr"
# Le décompte ci-dessus ne suffit PAS à voir revenir « ${1:?…} » : le message
# brut de bash tient lui aussi sur une ligne. Cette assertion-ci nomme sa forme
# — « configure-swap.sh: line 62: 1: --file attend un chemin » — et c'est elle,
# avec les deux précédentes, qui ferme le défaut.
assert_absent "$(erreur)" "configure-swap.sh: line" \
    "configure-swap.sh --file sans valeur : aucun message brut de bash sur stderr"

# --- 2. Une valeur d'argument invalide rend 2 sur les trois scripts ---------
# configure-swap.sh appelait déjà « die … 2 » ; configure-timezone.sh et
# configure-hostname.sh appelaient « die » sans code, donc 1. Le même appel mal
# formé rendait ainsi deux codes différents selon le script visé.
#
# Les chemins de validation éprouvés ici sont ceux propres à chaque script, et
# non un seul cas répété : fuseau inexistant, répertoire technique de zoneinfo,
# tentative de remontée d'arborescence, caractère interdit dans un nom d'hôte.
lancer bash "$TIMEZONE_SH" Zone/Inexistante
assert_code 2 "$CODE" "configure-timezone.sh refuse un fuseau inexistant"
assert_contient "$(erreur)" "[ERROR] Fuseau inconnu : « Zone/Inexistante »." \
    "configure-timezone.sh nomme le fuseau refusé"

lancer bash "$TIMEZONE_SH" posix/UTC
assert_code 2 "$CODE" "configure-timezone.sh refuse un répertoire technique de zoneinfo"
assert_contient "$(erreur)" "[ERROR] « posix/UTC » est un répertoire technique de zoneinfo, pas un fuseau." \
    "configure-timezone.sh explique pourquoi posix/ est refusé"

lancer bash "$TIMEZONE_SH" ../etc/passwd
assert_code 2 "$CODE" "configure-timezone.sh refuse un fuseau contenant « .. »"
assert_contient "$(erreur)" "[ERROR] Fuseau invalide : « ../etc/passwd »." \
    "configure-timezone.sh nomme le fuseau invalide"

lancer bash "$HOSTNAME_SH" mon_serveur
assert_code 2 "$CODE" "configure-hostname.sh refuse un caractère interdit dans le nom"
assert_contient "$(erreur)" "[ERROR] Segment invalide : « mon_serveur » — lettres, chiffres et tirets uniquement." \
    "configure-hostname.sh dit quels caractères il accepte"

# « -mauvais- » n'atteint JAMAIS valider_nom : son tiret initial le fait basculer
# sur « Option inconnue » dès l'analyse des arguments. Le code est le même — 2 —
# mais pour une autre raison. L'assertion de message le dit explicitement, faute
# de quoi ce cas passerait pour une preuve de la validation du nom, qu'il
# n'exerce pas. C'est la nuance relevée par le relecteur de TASK-016.
lancer bash "$HOSTNAME_SH" -mauvais-
assert_code 2 "$CODE" "configure-hostname.sh refuse « -mauvais- »"
assert_contient "$(erreur)" "[ERROR] Option inconnue : -mauvais-" \
    "configure-hostname.sh traite « -mauvais- » en option inconnue, et non en nom invalide"

# Les trois autres branches de valider_nom. Sans elles, une seule des cinq
# sorties de la fonction serait épinglée, et un « die » sans code rétabli sur
# les quatre autres passerait sans être vu.
lancer bash "$HOSTNAME_SH" "mon..serveur"
assert_code 2 "$CODE" "configure-hostname.sh refuse un segment vide"
assert_contient "$(erreur)" "[ERROR] Nom invalide : segment vide" \
    "configure-hostname.sh nomme le segment vide"

lancer bash "$HOSTNAME_SH" "serveur.-x"
assert_code 2 "$CODE" "configure-hostname.sh refuse un segment commençant par un tiret"
assert_contient "$(erreur)" "commence ou finit par un tiret" \
    "configure-hostname.sh explique le refus du tiret"

# 254 caractères : un de trop pour le nom entier, mais chaque segment reste sous
# la limite de 63, faute de quoi c'est l'autre branche qui répondrait.
nom_trop_long="$(printf 'a%.0s' $(seq 1 60)).$(printf 'b%.0s' $(seq 1 60)).$(printf 'c%.0s' $(seq 1 60)).$(printf 'd%.0s' $(seq 1 60)).eeeeeeeeee"
assert_egal "254" "${#nom_trop_long}" "le nom d'essai fait bien 254 caractères"
lancer bash "$HOSTNAME_SH" "$nom_trop_long"
assert_code 2 "$CODE" "configure-hostname.sh refuse un nom de plus de 253 caractères"
assert_contient "$(erreur)" "[ERROR] Nom trop long : 254 caractères (253 au maximum)." \
    "configure-hostname.sh nomme la longueur refusée"

lancer bash "$HOSTNAME_SH" "$(printf 'z%.0s' $(seq 1 64))"
assert_code 2 "$CODE" "configure-hostname.sh refuse un segment de plus de 63 caractères"
assert_contient "$(erreur)" "(63 caractères au maximum)" \
    "configure-hostname.sh nomme la limite de segment"

lancer bash "$SWAP_SH" abc
assert_code 2 "$CODE" "configure-swap.sh refuse une taille non numérique"

lancer bash "$SWAP_SH" 12X
assert_code 2 "$CODE" "configure-swap.sh refuse une unité inconnue"

# Ce « die » est hors de en_megaoctets — il n'a jamais souffert du doublon de
# trap — mais il relève de la même convention et rendait déjà 2. L'y épingler
# évite qu'il en sorte par la suite.
lancer bash "$SWAP_SH" 32
assert_code 2 "$CODE" "configure-swap.sh refuse une taille inférieure au minimum"
assert_contient "$(erreur)" "[ERROR] Taille trop faible : 32 Mo (64 Mo au minimum)." \
    "configure-swap.sh nomme le minimum"

# --- 3. Le trap ERR ne double plus le diagnostic ----------------------------
# en_megaoctets rendait sa valeur par « printf » sur stdout : elle s'exécutait
# donc dans une substitution de commande. Son « die » ne quittait que ce
# sous-shell ; le code remonté au shell principal faisait échouer l'affectation,
# et le trap ERR de lib/common.sh ajoutait une seconde ligne :
#
#   [ERROR] Taille invalide : « abc » (exemples : 2G, 512M, 2048).
#   [ERROR] Échec (code 2) à la ligne 143 de configure-swap.sh.
#
# La fonction renseigne désormais une variable globale et s'appelle hors
# substitution. UNE ASSERTION D'ABSENCE EST FACILE À ÉCRIRE CREUSE : sur un
# stderr vide, mal capturé ou pris sur le mauvais flux, elle serait verte sans
# rien prouver. Trois gardes l'encadrent donc — le code, la présence effective du
# diagnostic métier, et le DÉCOMPTE des lignes [ERROR], qui reste juste même si
# le libellé du trap change un jour dans lib/common.sh.
lancer bash "$SWAP_SH" abc
assert_code 2 "$CODE" "configure-swap.sh abc : erreur d'usage"
assert_contient "$(erreur)" "[ERROR] Taille invalide : « abc » (exemples : 2G, 512M, 2048)." \
    "configure-swap.sh abc : le diagnostic métier est bien là — la garde de l'assertion d'absence"
assert_absent "$(erreur)" "Échec (code" \
    "configure-swap.sh abc : le trap ERR n'ajoute aucune ligne au diagnostic"
assert_egal "1" "$(nb_lignes_contenant '[ERROR]')" \
    "configure-swap.sh abc : stderr ne porte qu'une seule ligne [ERROR]"

# L'autre « die » de en_megaoctets, sur la branche des unités. Il empruntait le
# même sous-shell et souffrait du même doublon.
lancer bash "$SWAP_SH" 12X
assert_contient "$(erreur)" "[ERROR] Unité inconnue dans « 12X » (attendu G ou M)." \
    "configure-swap.sh 12X : le diagnostic métier est bien là"
assert_absent "$(erreur)" "Échec (code" \
    "configure-swap.sh 12X : le trap ERR n'ajoute aucune ligne au diagnostic"
assert_egal "1" "$(nb_lignes_contenant '[ERROR]')" \
    "configure-swap.sh 12X : stderr ne porte qu'une seule ligne [ERROR]"

# --- 4. Un argument obligatoire manquant : un diagnostic, pas l'aide --------
# configure-hostname.sh appelait « show_help >&2 » : vingt-huit lignes d'aide sur
# stderr, dans lesquelles les deux lignes de diagnostic se perdaient.
#
# C'est LE DÉCOMPTE qui verrouille ce point. Les assertions de contenu
# resteraient toutes vertes si l'aide revenait autour d'elles ; seule une borne
# sur le nombre de lignes s'y oppose. Les assertions d'absence de « Usage : » et
# de « Options : » la doublent en nommant ce qui n'a rien à faire là.
if valeur_imposee_par_config SRV_HOSTNAME; then
    saute "configure-hostname.sh sans nom : diagnostic court plutôt que l'aide entière" \
        "SRV_HOSTNAME est fourni par l'environnement ou config/server.env — le script ne diagnostiquerait rien"
else
    lancer bash "$HOSTNAME_SH"
    assert_code 2 "$CODE" "configure-hostname.sh sans nom : erreur d'usage"
    assert_contient "$(erreur)" "[ERROR] Nom d'hôte manquant." \
        "configure-hostname.sh sans nom : dit ce qui manque"
    assert_contient "$(erreur)" "configure-hostname.sh --help" \
        "configure-hostname.sh sans nom : renvoie vers l'aide au lieu de la déverser"
    assert_au_plus 5 "$(nb_lignes_erreur)" \
        "configure-hostname.sh sans nom : stderr reste court"
    assert_absent "$(sortie)" "Usage :" \
        "configure-hostname.sh sans nom : l'aide n'est pas non plus écrite sur stdout"
    assert_absent "$(erreur)" "Usage :" \
        "configure-hostname.sh sans nom : l'aide n'est pas déversée sur stderr"
    assert_absent "$(erreur)" "Options :" \
        "configure-hostname.sh sans nom : la liste des options n'est pas déversée sur stderr"
fi

# Le script voisin, sur le même critère. Il n'a jamais porté le défaut : cette
# assertion l'empêche de le contracter.
if valeur_imposee_par_config SRV_TIMEZONE; then
    saute "configure-timezone.sh sans fuseau : diagnostic court plutôt que l'aide entière" \
        "SRV_TIMEZONE est fourni par l'environnement ou config/server.env — le script ne diagnostiquerait rien"
else
    lancer bash "$TIMEZONE_SH"
    assert_code 2 "$CODE" "configure-timezone.sh sans fuseau : erreur d'usage"
    assert_contient "$(erreur)" "[ERROR] Fuseau horaire manquant." \
        "configure-timezone.sh sans fuseau : dit ce qui manque"
    assert_au_plus 5 "$(nb_lignes_erreur)" \
        "configure-timezone.sh sans fuseau : stderr reste court"
    assert_absent "$(erreur)" "Usage :" \
        "configure-timezone.sh sans fuseau : l'aide n'est pas déversée sur stderr"
fi

# --- 5. La valeur de --file est contrôlée — TASK-017 ------------------------
# « --file » acceptait n'importe quelle chaîne non vide. Le contrôle posé par
# TASK-016 — « [ -n "${1:-}" ] » — ne rejetait que la valeur VIDE : son objet
# était le code de retour, pas la nature de la valeur. Deux dangers restaient
# ouverts, et deux refus distincts les ferment.
#
# Les deux cas meurent pendant l'analyse des arguments, avant require_root et
# avant la moindre écriture : ils ont leur place dans ce groupe non modifiant.

# a. Une valeur commençant par un tiret — l'option avalée.
#
#   $ configure-swap.sh 512M --file --dry-run
#   [INFO] Fichier d'échange : --dry-run
#   dirname: unrecognized option '--dry-run'
#   [ERROR] Échec (code 1) à la ligne 195 de configure-swap.sh.
#
# Rien n'était écrit, mais PAR ACCIDENT : dirname refusait une chaîne commençant
# par deux tirets et « set -Eeuo pipefail » tuait le script avant l'allocation.
# Le garde-fou disparaissait avec n'importe quelle autre valeur — d'où le cas b.
#
# Les deux assertions d'absence épinglent les deux lignes exactes de cette trace
# — « dirname: » et « Échec (code » — et le DÉCOMPTE des lignes [ERROR] voit
# revenir celle du trap même si son libellé change un jour dans lib/common.sh.
# Ce refus en produit QUATRE : trois « error » puis le « die ».
lancer bash "$SWAP_SH" 512M --file --dry-run
assert_code 2 "$CODE" "configure-swap.sh --file --dry-run : erreur d'usage"
assert_contient "$(erreur)" "[ERROR] Valeur refusée pour --file : « --dry-run »." \
    "configure-swap.sh --file --dry-run : nomme la valeur refusée"
assert_absent "$(erreur)" "dirname:" \
    "configure-swap.sh --file --dry-run : dirname ne voit jamais la valeur"
assert_absent "$(erreur)" "Échec (code" \
    "configure-swap.sh --file --dry-run : le trap ERR n'ajoute aucune ligne au diagnostic"
assert_absent "$(erreur)" "Fichier d'échange : --dry-run" \
    "configure-swap.sh --file --dry-run : l'option n'est jamais retenue comme chemin"
assert_egal "4" "$(nb_lignes_contenant '[ERROR]')" \
    "configure-swap.sh --file --dry-run : stderr porte les quatre lignes du refus, pas une de plus"

# b. Un chemin relatif — le fichier d'échange égaré, le cas grave.
#
# L'ordre inversé « configure-swap.sh --file 2G » prend « 2G » pour un chemin.
# SRV_SWAP_SIZE est imposé DANS L'ENVIRONNEMENT DE L'APPEL, et ce n'est pas un
# détail : sans lui le script s'arrêterait faute de taille, sur le seul
# diagnostic d'état, et le cas ne prouverait rien du chemin. Avec lui, plus rien
# n'arrêtait le script avant la création du fichier.
#
# Le répertoire courant est un répertoire VIDE et jetable — c'est là que le
# fichier serait né — et son contenu est relevé avant et après.
# contenu_repertoire <répertoire> <destination> — ce que le répertoire porte.
# « find » plutôt que « ls » : un nom de fichier exotique y survit (SC2012), et
# la ligne d'en-tête garantit qu'un relevé vide reste un relevé, et non un
# fichier vide qu'une redirection ratée produirait tout aussi bien.
contenu_repertoire() {
    local repertoire="$1" destination="$2"
    {
        printf 'contenu de %s\n' "$repertoire"
        find "$repertoire" -mindepth 1 -printf '%y %s %P\n' 2>/dev/null | sort
    } > "$destination"
}

REP_COURANT_VIDE="$REP_TMP/cwd-vide"
mkdir -p "$REP_COURANT_VIDE"
contenu_repertoire "$REP_COURANT_VIDE" "$REP_TMP/cwd-avant"

lancer_depuis "$REP_COURANT_VIDE" env SRV_SWAP_SIZE=512M bash "$SWAP_SH" --file 2G
assert_code 2 "$CODE" "configure-swap.sh --file 2G : erreur d'usage"
assert_contient "$(erreur)" "[ERROR] Chemin relatif refusé pour --file : « 2G »." \
    "configure-swap.sh --file 2G : nomme le chemin relatif refusé"
assert_absent "$(erreur)" "Échec (code" \
    "configure-swap.sh --file 2G : le trap ERR n'ajoute aucune ligne au diagnostic"
assert_egal "3" "$(nb_lignes_contenant '[ERROR]')" \
    "configure-swap.sh --file 2G : stderr porte les trois lignes du refus, pas une de plus"
# Le refus a lieu AVANT tout : ni résumé des opérations, ni création. C'est
# cette paire d'absences qui rougit si la contrainte de chemin absolu tombe —
# le relevé de répertoire ci-dessous, lui, resterait vert, le script effaçant
# de lui-même le fichier qu'il vient de créer quand swapon échoue.
assert_absent "$(erreur)" "Opérations prévues" \
    "configure-swap.sh --file 2G : aucune opération n'est même envisagée"
assert_absent "$(erreur)" "Création de" \
    "configure-swap.sh --file 2G : aucun fichier d'échange n'est créé"

contenu_repertoire "$REP_COURANT_VIDE" "$REP_TMP/cwd-apres"
assert_empreinte_egale "$REP_TMP/cwd-avant" "$REP_TMP/cwd-apres" \
    "configure-swap.sh --file 2G ne dépose rien dans le répertoire courant"

# c. Le refus tient à l'ABSENCE de chemin absolu, et non à la ressemblance de
# « 2G » avec une taille : un chemin relatif ordinaire est refusé de la même
# façon. Sans ce cas, une correction qui se contenterait de rejeter les tailles
# passerait le cas b.
lancer bash "$SWAP_SH" 512M --file essai/swapfile
assert_code 2 "$CODE" "configure-swap.sh --file essai/swapfile : erreur d'usage"
assert_contient "$(erreur)" "[ERROR] Chemin relatif refusé pour --file : « essai/swapfile »." \
    "configure-swap.sh --file essai/swapfile : nomme le chemin relatif refusé"

# d. Non-régression : « --file » sans valeur rend toujours 2, avec le message
# exact que la section 1 de ce groupe épingle. Le durcissement de TASK-017 a
# laissé ce contrôle intact — les assertions de la section 1 sont la preuve, et
# celle-ci n'a donc pas à être dupliquée ici.

# --- 6. La NATURE de la cible de --file est contrôlée — TASK-019 ------------
# TASK-017 a fermé la question de la FORME du chemin : absolu, sans tiret
# initial. Celle de sa NATURE restait entière, et c'est elle qui portait le
# risque réel. « configure-swap.sh 64M --file /etc/passwd » passait la
# validation de TASK-017, annonçait « créer /etc/passwd », demandait
# confirmation — et le « rm -f » de la création SUPPRIMAIT le fichier sur un
# simple oui. Un répertoire, lui, faisait mourir le script sur le message brut
# « rm: cannot remove … : Is a directory », doublé de la ligne du trap ERR.
#
# Ces cas meurent tous à l'analyse des arguments, avant require_root et avant
# afficher_etat : leur stderr ne porte donc QUE les lignes du refus, ce qui rend
# un décompte exact possible — et c'est cette forme d'assertion, pas celle de
# contenu, qui verrait revenir une ligne de trap ou un message de rm. Le
# rédacteur des tests de TASK-017 avait posé un tel décompte de tête sans jamais
# l'observer ; ici il est MESURÉ, refus par refus, et les chiffres viennent de
# l'exécution.
#
# Le groupe reste non modifiant : les cibles jetables sont créées dans REP_TMP,
# hors de l'empreinte de /etc comme du champ d'ecritures_depuis.
#
# LE PLACEMENT DE « -y » N'EST PAS LIBRE, et c'est une précaution contre le test
# lui-même. Un cas qui arme ASSUME_YES ouvre au script la voie de l'exécution
# réelle : si le contrôle que ce cas éprouve venait à tomber, le script créerait
# et activerait un fichier d'échange et compléterait /etc/fstab — sur la machine
# où le test tourne. « -y » n'est donc armé que dans les cas GARDÉS PAR JETABLE.
# Ailleurs, « lancer » ferme l'entrée standard : confirm() y lit une réponse
# vide et refuse, et rien ne peut être écrit même si le refus n'a pas lieu.

# refus_de_cible <libellé> <ligne attendue> — le tronc commun des refus.
#
# Les cinq assertions d'absence seraient creuses sur un stderr vide ou mal
# capturé : elles sont donc encadrées par la ligne de diagnostic exigée juste
# avant et par les deux décomptes qui les suivent. Le flux doit contenir
# exactement ce qu'on y attend, et rien d'autre.
#
# Les DEUX formes de confirmation sont épinglées, parce que confirm() en a deux :
# « Confirmation automatique : … » quand ASSUME_YES est armée, et l'invite
# « Appliquer ces opérations ? [o/N] » sinon. Un cas qui n'arme pas « -y » ne
# prouverait rien de la première ; il prouve la seconde, et c'est la même
# frontière — le refus tombe avant que la question ne soit seulement posée.
refus_de_cible() {
    local libelle="$1" ligne="$2"

    assert_code 2 "$CODE" "$libelle : erreur d'usage"
    assert_contient "$(erreur)" "$ligne" \
        "$libelle : nomme la cible et ce qu'elle est"
    assert_absent "$(erreur)" "rm: cannot remove" \
        "$libelle : le rm -f n'est jamais atteint"
    assert_absent "$(erreur)" "Échec (code" \
        "$libelle : le trap ERR n'ajoute aucune ligne au diagnostic"
    assert_absent "$(erreur)" "Confirmation automatique" \
        "$libelle : aucune confirmation automatique n'est prononcée"
    assert_absent "$(erreur)" "Appliquer ces opérations ?" \
        "$libelle : le refus tombe avant que la question ne soit posée"
    assert_absent "$(erreur)" "Opérations prévues" \
        "$libelle : aucune opération n'est même envisagée"
    assert_egal "4" "$(nb_lignes_contenant '[ERROR]')" \
        "$libelle : stderr porte les quatre lignes du refus, pas une de plus"
    assert_egal "4" "$(nb_lignes_erreur)" \
        "$libelle : stderr ne porte rien d'autre que ces quatre lignes"
}

# a. Un fichier ordinaire existant — le cas qui motive la tâche, joué sur une
#    cible JETABLE pour qu'il puisse tourner partout, y compris hors conteneur.
#
#    Sans « -y », délibérément : voir la note ci-dessus. Ce que ce cas prouve de
#    la confirmation est l'absence de l'INVITE ; le cas b, gardé, prouve celle de
#    la confirmation automatique.
FICHIER_ORDINAIRE="$REP_TMP/fichier-ordinaire"
printf 'contenu qui ne doit pas disparaître\n' > "$FICHIER_ORDINAIRE"
ORDINAIRE_AVANT="$(empreinte_fichier "$FICHIER_ORDINAIRE")"
assert_absent "$ORDINAIRE_AVANT" "ABSENT" \
    "garde : la cible ordinaire existe bien avant l'appel"

lancer bash "$SWAP_SH" 64M --file "$FICHIER_ORDINAIRE"
refus_de_cible "configure-swap.sh --file <fichier ordinaire>" \
    "[ERROR] Cible refusée pour --file : « $FICHIER_ORDINAIRE » existe et n'est pas un fichier d'échange."
assert_egal "$ORDINAIRE_AVANT" "$(empreinte_fichier "$FICHIER_ORDINAIRE")" \
    "configure-swap.sh --file <fichier ordinaire> : le fichier est intact, au contenu et à l'inode"

# b. /etc/passwd — la cible exacte de l'énoncé de TASK-019, « -y » compris.
#
#    Ce cas CONFIE /etc/passwd à un script qu'on soupçonne précisément de le
#    supprimer : tant que le contrôle tient, il ne se passe rien ; le jour où il
#    tombe, le système perd son fichier de comptes. Il ne s'exécute donc que sur
#    un système jetable, et se déclare NON EXÉCUTÉ ailleurs — le cas a, lui,
#    tourne partout et couvre la même branche du script.
#
#    L'ordre des options est celui de l'énoncé, « --file » puis « -y ». Le refus
#    tombe alors avant même que « -y » ne soit lu, et l'absence de « Confirmation
#    automatique » est ici doublement acquise. Le cas où elle MORD — ASSUME_YES
#    réellement armée quand le refus tombe — est celui du groupe 3 ter, où
#    « -y » n'est suivi d'aucun --file.
if [ "$JETABLE" != "true" ]; then
    saute "configure-swap.sh 64M --file /etc/passwd -y" \
        "ce cas confie /etc/passwd à un script soupçonné de le supprimer — réservé à un système jetable ; le cas a couvre la même branche sur une cible jetable"
else
    PASSWD_AVANT="$(empreinte_fichier /etc/passwd)"
    assert_absent "$PASSWD_AVANT" "ABSENT" \
        "garde : /etc/passwd existe bien avant l'appel"

    lancer bash "$SWAP_SH" 64M --file /etc/passwd -y
    refus_de_cible "configure-swap.sh 64M --file /etc/passwd -y" \
        "[ERROR] Cible refusée pour --file : « /etc/passwd » existe et n'est pas un fichier d'échange."
    assert_contient "$(erreur)" "[ERROR] Le script supprime sa cible avant de la recréer : ce fichier serait détruit." \
        "configure-swap.sh --file /etc/passwd : dit ce qui aurait été détruit"
    assert_absent "$(erreur)" "créer      /etc/passwd" \
        "configure-swap.sh --file /etc/passwd : la suppression n'est plus annoncée comme une création"
    assert_egal "$PASSWD_AVANT" "$(empreinte_fichier /etc/passwd)" \
        "configure-swap.sh 64M --file /etc/passwd -y : /etc/passwd est intact, au contenu et à l'inode"
fi

# c. Un répertoire — le cas mineur, celui du message brut de rm.
REP_CIBLE="$REP_TMP/rep-cible"
mkdir -p "$REP_CIBLE"
lancer bash "$SWAP_SH" 64M --file "$REP_CIBLE"
refus_de_cible "configure-swap.sh 64M --file <répertoire>" \
    "[ERROR] Cible refusée pour --file : « $REP_CIBLE » est un répertoire."
if [ -d "$REP_CIBLE" ]; then
    ok "configure-swap.sh --file <répertoire> : le répertoire est toujours là"
else
    ko "configure-swap.sh --file <répertoire> : le répertoire est toujours là" "$REP_CIBLE a disparu"
fi

# d. La racine — même nature, mais aucune erreur de frappe n'est plus proche du
#    désastre.
lancer bash "$SWAP_SH" 64M --file /
refus_de_cible "configure-swap.sh 64M --file /" \
    "[ERROR] Cible refusée pour --file : « / » est un répertoire."

# e. Un lien symbolique — refusé pour une autre raison, et le diagnostic la
#    nomme : le fichier d'échange remplacerait le lien, sa cible resterait en
#    place, et l'espace annoncé ne serait pas celui qui est occupé.
LIEN_CIBLE="$REP_TMP/lien-vers-fichier"
ln -sf "$FICHIER_ORDINAIRE" "$LIEN_CIBLE"
lancer bash "$SWAP_SH" 64M --file "$LIEN_CIBLE"
refus_de_cible "configure-swap.sh 64M --file <lien symbolique>" \
    "[ERROR] Lien symbolique refusé pour --file : « $LIEN_CIBLE »."
assert_egal "$ORDINAIRE_AVANT" "$(empreinte_fichier "$FICHIER_ORDINAIRE")" \
    "configure-swap.sh --file <lien symbolique> : la cible du lien est intacte"

# f. Les cinq refus valent AUSSI sans privilège — le second tour de TASK-019.
#
# La correction a donné un second paramètre à valider_fichier_swap, « avant-root »
# ou « apres-root », et diffère UN verdict selon le moment. Le risque d'un tel
# aiguillage est qu'il en diffère d'autres au passage : un refus qui ne tomberait
# plus qu'en root laisserait l'appelant sans « sudo » recevoir 1 — privilège
# manquant — pour une ligne de commande fautive, alors que la convention du dépôt
# réserve le 2 à l'usage et veut que les arguments soient jugés AVANT les
# privilèges.
#
# Les cinq mêmes refus sont donc rejoués sans privilège. Leurs cibles vivent dans
# un répertoire traversable par tous, et ce n'est pas un détail : sous REP_TMP,
# créé en mode 700, « nobody » ne pourrait même pas les voir, tous les chemins
# passeraient pour inexistants, et les cinq cas seraient verts sans rien prouver.
# Les gardes du cas g mesurent cette visibilité au lieu de la supposer.
REP_CIBLES="/tmp/mgnet-integration-cibles"
rm -rf "$REP_CIBLES"
mkdir -p "$REP_CIBLES/rep-visible"
chmod 755 "$REP_CIBLES" "$REP_CIBLES/rep-visible"
CIBLE_ORDINAIRE="$REP_CIBLES/ordinaire"
CIBLE_LIEN="$REP_CIBLES/lien"
CIBLE_600="$REP_CIBLES/illisible-600"
printf 'contenu qui ne doit pas disparaître\n' > "$CIBLE_ORDINAIRE"
chmod 644 "$CIBLE_ORDINAIRE"
ln -sf "$CIBLE_ORDINAIRE" "$CIBLE_LIEN"
printf 'ce fichier n%s est pas un fichier d%s échange\n' "'" "'" > "$CIBLE_600"
chmod 600 "$CIBLE_600"

if [ "$SANS_ROOT_DISPONIBLE" != "true" ]; then
    saute "les cinq refus de cible rejoués sans privilège" \
        "aucun lanceur ne parvient à abaisser l'UID sur cet hôte"
else
    sans_root bash "$SWAP_SH" 64M --file "$CIBLE_ORDINAIRE"
    refus_de_cible "configure-swap.sh --file <fichier ordinaire> sans privilège" \
        "[ERROR] Cible refusée pour --file : « $CIBLE_ORDINAIRE » existe et n'est pas un fichier d'échange."

    sans_root bash "$SWAP_SH" 64M --file "$REP_CIBLES/rep-visible"
    refus_de_cible "configure-swap.sh --file <répertoire> sans privilège" \
        "[ERROR] Cible refusée pour --file : « $REP_CIBLES/rep-visible » est un répertoire."

    sans_root bash "$SWAP_SH" 64M --file /
    refus_de_cible "configure-swap.sh --file / sans privilège" \
        "[ERROR] Cible refusée pour --file : « / » est un répertoire."

    sans_root bash "$SWAP_SH" 64M --file "$CIBLE_LIEN"
    refus_de_cible "configure-swap.sh --file <lien symbolique> sans privilège" \
        "[ERROR] Lien symbolique refusé pour --file : « $CIBLE_LIEN »."

    # /etc/passwd est en 644 : « nobody » le voit et le lit, le refus tombe donc
    # au même endroit qu'en root. Le cas est sans danger même si le contrôle
    # régressait — require_root arrêterait le script bien avant le « rm -f » — et
    # n'a donc pas besoin de la garde JETABLE du cas b.
    sans_root bash "$SWAP_SH" 64M --file /etc/passwd
    refus_de_cible "configure-swap.sh --file /etc/passwd sans privilège" \
        "[ERROR] Cible refusée pour --file : « /etc/passwd » existe et n'est pas un fichier d'échange."
fi

# g. Le SEUL verdict différé : la cible qui existe et n'est pas lisible.
#
# C'est la régression qu'a mesurée le relecteur. Une cible en mode 600 que
# l'appelant ne peut pas lire n'est pas une cible fautive : c'est un regard sans
# les droits. La juger à l'analyse des arguments rendait 2 à un appelant dont la
# ligne de commande était juste et à qui il ne manquait qu'un « sudo ». Le
# verdict est donc différé — require_root reproche le privilège, code 1 — et le
# second appel, « apres-root », tranche une fois les droits acquis.
#
# Les deux gardes ne sont pas décoratives. Si « nobody » ne VOYAIT pas la cible,
# le chemin passerait pour inexistant, le script irait jusqu'à require_root et
# rendrait 1 : la bonne réponse pour la mauvaise raison, et le cas resterait vert
# sous n'importe quelle mutation. Visible ET illisible pour l'appelant se mesure
# donc, et ne se suppose pas.
if [ "$EST_ROOT" != "true" ] || [ "$SANS_ROOT_DISPONIBLE" != "true" ]; then
    saute "le verdict différé sur une cible illisible" \
        "exige root pour poser une cible en 600 que le lanceur non privilégié ne puisse pas lire"
else
    # « stat » puis « cat », et non « bash -c "[ -e … ]" » : les deux mesurent la
    # même chose sans faire voyager d'expression à travers un « -c », forme que
    # l'analyse statique signale à raison (SC2016) comme une expansion qui n'aura
    # pas lieu là où on la lit. stat réussit si le chemin est VU — il ne demande
    # que le droit de traverser le répertoire ; cat échoue s'il n'est pas LISIBLE.
    lancer "${LANCEUR_SANS_ROOT[@]}" stat "$CIBLE_600"
    assert_code 0 "$CODE" \
        "garde : sans privilège, la cible en 600 est bien VUE — le chemin ne passe pas pour inexistant"
    lancer "${LANCEUR_SANS_ROOT[@]}" cat "$CIBLE_600"
    assert_code_non_nul "$CODE" \
        "garde : sans privilège, la cible en 600 n'est pas LISIBLE — le verdict a bien de quoi être différé"

    # Le cas de la régression : sans privilège, c'est 1 et non 2.
    sans_root bash "$SWAP_SH" 64M --file "$CIBLE_600"
    assert_code 1 "$CODE" \
        "configure-swap.sh --file <cible 600 illisible> sans privilège : le privilège manquant prime, code 1"
    assert_contient "$(erreur)" "[ERROR] Ce script doit être exécuté en root (ou via sudo)." \
        "configure-swap.sh --file <cible 600> sans privilège : c'est bien le privilège qui est reproché"
    assert_absent "$(erreur)" "Cible refusée pour --file" \
        "configure-swap.sh --file <cible 600> sans privilège : la cible n'est pas jugée sans les droits de la lire"
    assert_absent "$(erreur)" "Échec (code" \
        "configure-swap.sh --file <cible 600> sans privilège : le trap ERR n'ajoute aucune ligne"
    assert_egal "1" "$(nb_lignes_contenant '[ERROR]')" \
        "configure-swap.sh --file <cible 600> sans privilège : une seule ligne [ERROR], celle du privilège"

    # La même cible, EN ROOT. Le verdict différé aboutit alors — et il aboutit
    # sur le refus ORDINAIRE, ce qui est MESURÉ et non déduit : root lit un
    # fichier en 600, « [ ! -r ] » y est faux, et c'est la branche « existe et
    # n'est pas un fichier d'échange » qui tranche. Le refus tombe bien, en 2 :
    # la correction n'a ouvert aucun passage à une cible que le script
    # détruirait.
    lancer bash "$SWAP_SH" 64M --file "$CIBLE_600"
    refus_de_cible "configure-swap.sh --file <cible 600 illisible> en root" \
        "[ERROR] Cible refusée pour --file : « $CIBLE_600 » existe et n'est pas un fichier d'échange."
    assert_absent "$(empreinte_fichier "$CIBLE_600")" "ABSENT" \
        "configure-swap.sh --file <cible 600> en root : la cible est toujours là"

    # Ce que ce fichier NE prouve PAS, et pourquoi il ne le prouvera pas ici.
    #
    # La branche « apres-root » du cas illisible — celle qui dit « Vérifier les
    # droits de lecture sur ce chemin, ou en choisir un autre. » — exige un
    # fichier régulier que ROOT ne puisse pas lire. Quatre montages ont été
    # essayés dans ce conteneur, et les quatre ont échoué : mode 600, root passe
    # outre ; « setpriv --bounding-set=-dac_override,-dac_read_search » ;
    # « capsh --drop=cap_dac_override,cap_dac_read_search » ; « capsh --caps= ».
    # Dans les quatre cas « id -u » rend 0 et « [ -r ] » rend 0 — root conserve
    # le contournement DAC.
    #
    # Le message reste donc SANS PREUVE ici. Il n'est pas pour autant du code
    # mort dans l'absolu : NFS en root_squash, ou un refus MAC (SELinux,
    # AppArmor), rendent la branche atteignable sur un vrai serveur. Aucun de ces
    # montages n'est à portée du profil « debian ».
    saute_par_nature "le refus d'une cible illisible EN ROOT, et sa ligne « Vérifier les droits de lecture sur ce chemin »" \
        "root contourne les permissions DAC dans ce conteneur — quatre montages mesurés (mode 600, setpriv --bounding-set, capsh --drop, capsh --caps=), tous rendus lisibles"
fi

titre "1 ter. Privilèges et OS"

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
    # formé serait masqué par un message de permission. Les CINQ scripts sont
    # éprouvés, et non le seul update-system.sh : la garantie porte sur l'ORDRE
    # « arguments puis privilèges », qui se vérifie script par script.
    for script in $CINQ_MODIFIANTS; do
        nom="$(basename "$script")"
        sans_root bash "$script" --option-qui-n-existe-pas
        assert_code 2 "$CODE" "$nom sans privilège : l'option inconnue prime, code 2"
    done

    # Même ordre pour une VALEUR invalide : la validation précède require_root.
    # Ces trois cas sont le pendant exact des trois précédents — mêmes scripts,
    # mêmes arguments, mais valides — et c'est leur mise en regard qui prouve la
    # frontière d'ADR-0003 décision 10 : 1 quand la commande est juste et que
    # seul le privilège manque, 2 dès que la commande elle-même est fautive.
    sans_root bash "$HOSTNAME_SH" mon_serveur
    assert_code 2 "$CODE" "configure-hostname.sh sans privilège : le nom invalide prime, code 2"

    sans_root bash "$TIMEZONE_SH" Zone/Inexistante
    assert_code 2 "$CODE" "configure-timezone.sh sans privilège : le fuseau inconnu prime, code 2"

    sans_root bash "$SWAP_SH" abc
    assert_code 2 "$CODE" "configure-swap.sh sans privilège : la taille invalide prime, code 2"
    assert_absent "$(erreur)" "Échec (code" \
        "configure-swap.sh abc sans privilège : le trap ERR n'ajoute aucune ligne"

    rm -rf "$LOG_DIR_NOBODY"
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

    # La conversion des unités est le SEUL endroit où le passage d'un « printf »
    # sur stdout à une variable globale — la correction du doublon de trap —
    # pouvait abîmer une valeur sans que rien d'autre ne s'en aperçoive : une
    # variable mal renseignée resterait vide, et « $(( nombre * 1024 )) » ne
    # produirait plus 2048. Le cas 512M ci-dessus n'emprunte pas cette branche,
    # l'unité M étant recopiée telle quelle.
    dry_run_inoffensif "configure-swap.sh 2G --dry-run" \
        bash "$SWAP_SH" 2G --dry-run
    assert_contient "$(erreur)" "Taille demandée : 2048 Mo (argument : 2G)" \
        "configure-swap.sh convertit 2G en 2048 Mo"
    assert_contient "$(erreur)" "créer      /swapfile (2048 Mo)" \
        "configure-swap.sh annonce la création à 2048 Mo, valeur portée jusqu'au résumé"

    # --- Garde de non-régression : une option derrière --file — TASK-017 ---
    # CE CAS NE DÉMONTRE PAS LE CORRECTIF, et il faut le savoir pour ne pas s'y
    # fier à tort. Mesuré par le relecteur sur le configure-swap.sh de master :
    # « 2G --file /swapfile --dry-run » y donnait DÉJÀ « Mode --dry-run » et le
    # code 0. L'ancien code ne consommait qu'un seul jeton ; le défaut
    # n'apparaissait que lorsque l'option ÉTAIT elle-même la valeur — c'est le
    # cas 5a qui le prouve, pas celui-ci.
    #
    # Ce que ce cas apporte : la garantie qu'en fermant le défaut, on n'a pas
    # cassé le chemin nominal. Une validation trop gourmande qui consommerait le
    # jeton suivant le ferait rougir. Aucune autre assertion de ce fichier ne
    # place une option derrière une valeur de --file.
    dry_run_inoffensif "configure-swap.sh 2G --file /swapfile --dry-run" \
        bash "$SWAP_SH" 2G --file /swapfile --dry-run
    assert_contient "$(erreur)" "[INFO] Mode --dry-run : aucune modification effectuée." \
        "configure-swap.sh 2G --file /swapfile --dry-run : --dry-run reste actif après --file"
    assert_contient "$(erreur)" "[INFO] Fichier d'échange : /swapfile" \
        "configure-swap.sh 2G --file /swapfile --dry-run : le chemin donné est bien retenu"

    # Un chemin absolu AUTRE que le défaut : sans lui, les deux assertions
    # précédentes passeraient encore si --file était purement et simplement
    # ignoré, /swapfile étant la valeur par défaut de FICHIER_SWAP.
    if [ -e /var/swapfile-essai ]; then
        ko "garde : /var/swapfile-essai n'existe pas avant l'appel" \
            "le cas ne prouverait plus que le chemin INEXISTANT reste accepté"
    else
        ok "garde : /var/swapfile-essai n'existe pas avant l'appel"
    fi
    dry_run_inoffensif "configure-swap.sh 512M --file /var/swapfile-essai --dry-run" \
        bash "$SWAP_SH" 512M --file /var/swapfile-essai --dry-run
    assert_contient "$(erreur)" "créer      /var/swapfile-essai (512 Mo)" \
        "configure-swap.sh --file <chemin absolu> vise bien le fichier demandé"

    # --- Les DEUX cas nominaux de TASK-019, et ce qu'ils coûtent s'ils cassent -
    # Le contrôle de nature ajouté par TASK-019 refuse tout ce qu'il ne
    # reconnaît pas. Deux cibles doivent continuer de passer, et ce sont les
    # seules qui aient un usage : le chemin qui ne désigne rien — création — et
    # le fichier d'échange existant — redimensionnement. Un contrôle trop
    # sévère rendrait le script inutilisable sans qu'aucun refus ne paraisse
    # fautif ; c'est la régression la plus chère de cette tâche.
    #
    # Le premier cas est celui qui précède : /var/swapfile-essai n'existe pas —
    # la garde ci-dessus le vérifie plutôt que de le supposer — et le résumé
    # annonce toujours « créer ». L'assertion d'absence ci-dessous en fixe le
    # sens du côté de TASK-019 : aucun refus de cible sur ce chemin.
    assert_absent "$(erreur)" "Cible refusée pour --file" \
        "configure-swap.sh --file <chemin absolu inexistant> : la création reste acceptée"

    # Le second cas est le seul de tout le dépôt à éprouver la SIGNATURE. Un
    # fichier d'échange se reconnaît de deux façons, et le groupe swap-fstab de
    # tests/acceptance/interne/TASK-011-cas-conteneur.sh n'emprunte que la
    # première : il pose un fichier creux au chemin qu'expose /proc/swaps, sans
    # aucune signature. La lecture des dix octets « SWAPSPACE2 » écrits par
    # mkswap n'a donc ici que cette seule preuve directe — d'où le fichier
    # réellement produit par mkswap, et non imité.
    #
    # La signature est relevée AVANT l'appel, à l'offset que le script emploie :
    # sans cette garde, un mkswap muet ou une page de taille inattendue ferait
    # rougir le cas sans qu'on sache pourquoi, et la preuve se lirait comme un
    # défaut du script.
    SWAP_MKSWAP="$REP_TMP/swapfile-mkswap"
    dd if=/dev/zero of="$SWAP_MKSWAP" bs=1M count=64 status=none
    chmod 600 "$SWAP_MKSWAP"
    if mkswap "$SWAP_MKSWAP" >/dev/null 2>&1; then
        SIGNATURE_LUE="$(dd if="$SWAP_MKSWAP" bs=1 skip=4086 count=10 2>/dev/null | tr -d '\000')"
        assert_egal "SWAPSPACE2" "$SIGNATURE_LUE" \
            "garde : mkswap a écrit SWAPSPACE2 aux dix derniers octets de la première page"

        dry_run_inoffensif "configure-swap.sh 64M --file <fichier mkswap> --dry-run" \
            bash "$SWAP_SH" 64M --file "$SWAP_MKSWAP" --dry-run
        assert_contient "$(erreur)" "remplacer  $SWAP_MKSWAP (64 Mo -> 64 Mo)" \
            "configure-swap.sh reconnaît un fichier d'échange inactif par sa signature et le redimensionne"
        assert_absent "$(erreur)" "Cible refusée pour --file" \
            "configure-swap.sh --file <fichier mkswap> : aucun refus de cible"
        assert_absent "$(erreur)" "Échec (code" \
            "configure-swap.sh --file <fichier mkswap> : aucune ligne de trap"
        # Ce fichier est en mode 600, comme tout fichier d'échange, et il
        # traverse la validation DEUX fois depuis le second tour de TASK-019 :
        # une fois « avant-root » à la lecture de --file, une fois « apres-root »
        # au préflight. C'est le chemin nominal que l'aiguillage sur le moment
        # pouvait casser — un « n'est pas lisible » prononcé à l'un des deux
        # passages refuserait un fichier d'échange parfaitement valide.
        assert_absent "$(erreur)" "n'est pas lisible" \
            "configure-swap.sh --file <fichier mkswap en 600> : les deux passages de validation le laissent passer"
    else
        saute_indisponible "reconnaissance d'un fichier d'échange par sa signature" \
            "mkswap n'a pas pu préparer $SWAP_MKSWAP — la seule preuve directe de la lecture de SWAPSPACE2 est perdue"
    fi

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
# 3 bis. -y reste actif après --file — TASK-017
# ===================================================================
# « -y » ne s'observe pas comme « --dry-run ». confirm() n'est appelé qu'APRÈS
# la sortie du mode d'essai à blanc : le prouver exige une exécution RÉELLE, et
# c'est la seule de ce fichier.
#
# Elle est bornée par construction : le fichier d'échange visé est placé dans le
# répertoire jetable du test, jamais /swapfile. swapon est refusé au conteneur
# non privilégié — le script le diagnostique, supprime lui-même son fichier
# incomplet et sort en 1. Ce qui est éprouvé ici n'est donc pas l'activation du
# swap, qui reste NON EXÉCUTÉE au groupe 5, mais la seule ligne « Confirmation
# automatique », que « -y » seul produit.
#
# Les deux moitiés sont mises en regard — sans « -y » puis avec — parce que la
# seconde seule ne dirait pas d'où vient la différence. L'entrée standard est
# fermée par « lancer » : confirm() y lit une réponse vide et refuse.
#
# Une empreinte encadre le groupe. Elle prouve que cette exécution réelle n'a
# rien laissé hors du répertoire jetable, et protège du même geste la garde
# d'état du groupe 4, qui suit.
#
# PORTÉE EXACTE, pour ne pas s'y fier à tort : comme le cas « --dry-run » de la
# section 3, ce groupe est une garde de NON-RÉGRESSION, pas la démonstration du
# correctif. Le relecteur a mesuré que « -y » derrière une valeur de --file
# fonctionnait déjà sur master : l'ancien code ne consommait qu'un seul jeton, et
# le défaut n'apparaissait que lorsque l'option ÉTAIT la valeur. Ce qui prouve le
# correctif, c'est le cas 5a. Ce groupe garantit qu'on ne l'a pas payé en cassant
# le chemin nominal.
titre "3 bis. -y reste actif après --file"

if [ "$EST_ROOT" != "true" ]; then
    saute "-y reste actif après --file <chemin absolu>" \
        "require_root arrête le script avant confirm() — l'exécution réelle exige root"
elif [ "$JETABLE" != "true" ]; then
    saute "-y reste actif après --file <chemin absolu>" \
        "ce cas exécute réellement configure-swap.sh — réservé à un système jetable"
else
    FICHIER_ESSAI="$REP_TMP/swapfile-essai"
    empreinte "$REP_TMP/y-avant"

    # La moitié témoin : sans « -y », le script demande et renonce.
    lancer bash "$SWAP_SH" 64M --file "$FICHIER_ESSAI"
    assert_code 0 "$CODE" "configure-swap.sh 64M --file <absolu> sans -y : renonce proprement"
    assert_contient "$(erreur)" "[INFO] Abandon à la demande de l'utilisateur." \
        "configure-swap.sh sans -y : demande confirmation et renonce"
    assert_absent "$(erreur)" "Confirmation automatique" \
        "configure-swap.sh sans -y : aucune confirmation automatique"
    if [ -e "$FICHIER_ESSAI" ]; then
        ko "configure-swap.sh sans -y ne crée aucun fichier d'échange" "$FICHIER_ESSAI existe"
    else
        ok "configure-swap.sh sans -y ne crée aucun fichier d'échange"
    fi

    # La même commande, « -y » placé APRÈS la valeur de --file. C'est la seule
    # différence entre les deux appels.
    lancer bash "$SWAP_SH" 64M --file "$FICHIER_ESSAI" -y
    assert_contient "$(erreur)" "[INFO] Confirmation automatique : Appliquer ces opérations ?" \
        "configure-swap.sh 64M --file <absolu> -y : -y reste actif après --file"
    assert_absent "$(erreur)" "Abandon à la demande de l'utilisateur" \
        "configure-swap.sh avec -y : plus aucune demande de confirmation"
    assert_contient "$(erreur)" "[INFO] Fichier d'échange : $FICHIER_ESSAI" \
        "configure-swap.sh avec -y : le chemin donné est bien retenu"

    # La suite appartient au contrat de cet environnement, et non au correctif :
    # swapon y est refusé. Si ce code passait un jour à 0, le swap aurait été
    # RÉELLEMENT activé et le saut du groupe 5 aurait cessé d'être vrai — mieux
    # vaut alors une assertion rouge qu'un silence.
    assert_code 1 "$CODE" "configure-swap.sh avec -y : swapon refusé au conteneur, échec d'exécution"
    assert_contient "$(erreur)" "[ERROR] L'activation du swap a échoué." \
        "configure-swap.sh avec -y : l'échec de swapon est diagnostiqué"
    if [ -e "$FICHIER_ESSAI" ]; then
        ko "configure-swap.sh supprime le fichier d'échange incomplet" "$FICHIER_ESSAI subsiste"
    else
        ok "configure-swap.sh supprime le fichier d'échange incomplet"
    fi

    empreinte "$REP_TMP/y-apres"
    assert_empreinte_egale "$REP_TMP/y-avant" "$REP_TMP/y-apres" \
        "l'exécution réelle du groupe 3 bis ne laisse rien hors du répertoire jetable"
fi

# ===================================================================
# 3 ter. Le chemin par DÉFAUT est contrôlé lui aussi — TASK-019
# ===================================================================
# valider_fichier_swap ne voit que la valeur de --file, à l'analyse des
# arguments : le chemin par défaut /swapfile ne lui était jamais soumis, et
# c'est pourtant la même cible et le même « rm -f ». TASK-019 a donc ajouté un
# SECOND appel, après require_root.
#
# Les deux moitiés de cette phrase sont éprouvées ici, et elles se tiennent :
# le second appel doit exister — cas a — et il doit être placé APRÈS
# require_root — cas b. Un correctif qui remonterait l'appel avant require_root
# passerait le cas a et ferait rougir le cas b ; un correctif qui retirerait
# l'appel ferait l'inverse.
#
# CE GROUPE ÉCRIT /swapfile — un répertoire, puis un fichier ordinaire — et le
# retire aussitôt. Il exige donc root et un système jetable, et l'empreinte qui
# l'encadre vérifie la restitution plutôt que de la supposer : la garde d'état
# du groupe 4, qui suit, compare l'empreinte à celle du groupe 2 et
# déclarerait tout le groupe NON EXÉCUTÉ si /swapfile subsistait.
titre "3 ter. Le chemin par défaut /swapfile"

if [ "$EST_ROOT" != "true" ]; then
    saute "le contrôle du chemin par défaut /swapfile" \
        "le second appel a lieu après require_root — l'atteindre exige root"
elif [ "$JETABLE" != "true" ]; then
    saute "le contrôle du chemin par défaut /swapfile" \
        "ce groupe crée puis retire /swapfile — réservé à un système jetable"
elif [ -e /swapfile ]; then
    saute "le contrôle du chemin par défaut /swapfile" \
        "/swapfile existe déjà sur ce système — le remplacer sortirait du cadre de ce fichier"
else
    empreinte "$REP_TMP/defaut-avant"

    # a. /swapfile est un répertoire, et aucun --file n'est donné. Sans le
    #    second appel, le script irait jusqu'au « rm -f », qui refuserait — il
    #    n'est pas récursif — et mourrait sur le message brut de rm, doublé de
    #    la ligne du trap. « -y » est armé pour que ce chemin soit réellement
    #    ouvert : sans lui, le script s'arrêterait sur la confirmation refusée
    #    et le défaut resterait invisible.
    mkdir -p /swapfile
    lancer bash "$SWAP_SH" 2G -y
    rmdir /swapfile

    assert_code 2 "$CODE" "configure-swap.sh 2G, /swapfile étant un répertoire : erreur d'usage"
    assert_contient "$(erreur)" "[ERROR] Cible refusée pour --file : « /swapfile » est un répertoire." \
        "configure-swap.sh 2G : le chemin par défaut est contrôlé comme l'est une valeur de --file"
    assert_absent "$(erreur)" "rm: cannot remove" \
        "configure-swap.sh 2G : le rm -f n'est jamais atteint"
    assert_absent "$(erreur)" "Échec (code" \
        "configure-swap.sh 2G : le trap ERR n'ajoute aucune ligne au diagnostic"
    assert_absent "$(erreur)" "Confirmation automatique" \
        "configure-swap.sh 2G : le refus précède toute confirmation"
    assert_absent "$(erreur)" "Opérations prévues" \
        "configure-swap.sh 2G : aucune opération n'est même envisagée"
    # Le DÉCOMPTE, et non les seules absences. Il ne peut pas porter ici sur
    # tout stderr : le refus a lieu après afficher_etat, qui précède
    # require_root, et le flux porte donc aussi l'état du swap. Compter les
    # lignes [ERROR] voit revenir celle du trap même si son libellé change un
    # jour dans lib/common.sh, là où l'assertion d'absence ci-dessus est liée à
    # son texte.
    assert_egal "4" "$(nb_lignes_contenant '[ERROR]')" \
        "configure-swap.sh 2G : stderr porte les quatre lignes du refus, pas une de plus"

    # b. Le second appel est bien APRÈS require_root. /swapfile est cette fois
    #    un fichier ordinaire que le script ne reconnaîtrait pas — et qui, en
    #    mode 600 appartenant à root, n'est même pas lisible par « nobody ».
    #    Placé avant require_root, le contrôle rendrait 2 ; placé après, c'est
    #    le privilège manquant qui est reproché, code 1. Sans cette cible
    #    refusable, les deux placements donneraient le même résultat et le cas
    #    ne prouverait rien : /swapfile absent est accepté par la validation.
    if [ "$SANS_ROOT_DISPONIBLE" != "true" ]; then
        saute "configure-swap.sh 512M sans privilège rend 1 alors que /swapfile est une cible refusable" \
            "aucun lanceur ne parvient à abaisser l'UID sur cet hôte"
    else
        printf 'ceci n%s est pas un fichier d%s échange\n' "'" "'" > /swapfile
        chmod 600 /swapfile
        sans_root bash "$SWAP_SH" 512M
        rm -f /swapfile
        rm -rf "$LOG_DIR_NOBODY"

        assert_code 1 "$CODE" \
            "configure-swap.sh 512M sans privilège : le privilège manquant prime, code 1"
        assert_contient "$(erreur)" "[ERROR] Ce script doit être exécuté en root (ou via sudo)." \
            "configure-swap.sh 512M sans privilège : c'est bien le privilège qui est reproché"
        assert_absent "$(erreur)" "Cible refusée pour --file" \
            "configure-swap.sh 512M sans privilège : la cible n'est pas jugée avant le privilège"
        assert_absent "$(erreur)" "Échec (code" \
            "configure-swap.sh 512M sans privilège : le trap ERR n'ajoute aucune ligne"
    fi

    empreinte "$REP_TMP/defaut-apres"
    assert_empreinte_egale "$REP_TMP/defaut-avant" "$REP_TMP/defaut-apres" \
        "le groupe 3 ter laisse /swapfile dans l'état où il l'a trouvé"
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

# Les cibles du groupe 1 bis §6 f et g vivent hors de REP_TMP — elles doivent
# être traversables par un utilisateur non privilégié, ce qu'un « mktemp -d » en
# mode 700 interdit. Elles sont donc retirées ici, et leur retrait vérifié : un
# répertoire en 755 laissé dans /tmp est un résidu, fût-il jetable.
if [ -n "${REP_CIBLES:-}" ]; then
    rm -rf "$REP_CIBLES"
    if [ -e "$REP_CIBLES" ]; then
        ko "le répertoire des cibles de refus est supprimé" "$REP_CIBLES subsiste"
    else
        ok "le répertoire des cibles de refus est supprimé"
    fi
else
    saute "le retrait du répertoire des cibles de refus" \
        "le groupe 1 bis §6 n'a pas été atteint sur cet hôte"
fi

bilan "TASK-004 / Linux/System"
