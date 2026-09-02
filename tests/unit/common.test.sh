#!/usr/bin/env bash
# tests/unit/common.test.sh — tests unitaires de lib/common.sh
# (TASK-003, complété par TASK-015).
#
# lib/common.sh est le point de défaillance unique du dépôt : chaque script le
# charge. Ce fichier couvre les onze critères de TASK-003 — load_config,
# require_cmd, require_root, require_os, detect_os, les quatre fonctions de
# journalisation, die, confirm, le double chargement et run_logged — puis les
# trois corrections du socle tranchées par TASK-015 (§6, §11 et §12).
#
# ---------------------------------------------------------------------------
# Trois difficultés, trois partis pris
# ---------------------------------------------------------------------------
#
# 1. LES FONCTIONS QUI SORTENT. die, require_root, require_cmd, require_os et
#    load_config appellent « exit ». Les éprouver depuis le shell du harnais le
#    tuerait. Chaque cas est donc écrit dans un fichier jetable, exécuté par un
#    processus bash NEUF, dont on capture le code, stdout, stderr et le journal.
#
#    Le code est recueilli par « || CODE=$? » : cette forme n'arme pas le trap
#    ERR posé par common.sh, la commande n'étant pas la dernière d'une liste ||.
#    Le « set -Eeuo pipefail » du harnais reste en place de bout en bout — le
#    retirer pour faire passer un cas vaudrait échec de la tâche (AGENTS.md §12).
#
#    Un sous-shell « ( source … ) » ne suffirait pas : il hérite de la variable
#    _COMMON_SH_CHARGE du harnais, et la garde anti-double-chargement de
#    common.sh ferait de son « source » une opération nulle. Un processus
#    distinct, lui, part vierge.
#
# 2. LE BAC À SABLE. SCRIPTS_ROOT est résolu depuis l'emplacement de
#    lib/common.sh. Une COPIE de ce fichier dans un répertoire temporaire s'y
#    enracine donc d'elle-même, ce qui permet :
#
#      - de créer des config/*.env jetables sans jamais écrire dans config/,
#        qui est en zone interdite (AGENTS.md §5) ;
#      - de neutraliser un éventuel config/server.env de la machine, que
#        common.sh charge de lui-même et qui pourrait redéfinir LOG_DIR.
#
#    L'identité de la copie avec l'original est prouvée par cmp (§0) : sans
#    cela, ce fichier prouverait le comportement d'un code qui n'est pas celui
#    du dépôt. C'est le procédé déjà employé par TASK-012.
#
# 3. LES JOURNAUX. common.sh crée LOG_DIR et calcule LOG_FILE dès le « source »,
#    avant tout parsing. LOG_DIR est donc exporté vers un répertoire temporaire,
#    supprimé en fin d'exécution. Le journal est remis à zéro avant chaque cas :
#    les assertions portent alors sur les seules lignes du cas courant.
#
# ---------------------------------------------------------------------------
# Trois divergences relevées ici, tranchées et corrigées par TASK-015
# ---------------------------------------------------------------------------
#
# Ce fichier épinglait le comportement d'AVANT. ADR-0003 — décisions 7, 8 et 9 —
# a tranché, TASK-015 a corrigé le socle, et les assertions ont été RETOURNÉES
# dans le même commit. Elles décrivent désormais le contrat effectif :
#
#   décision 7 — load_config encadre son « source » par set -a / set +a. Une
#                affectation nue d'un .env atteint donc les processus fils (§6).
#                set +a est rétabli MÊME SI le source échoue, sans quoi tout ce
#                que le script déclare ensuite serait exporté à son insu (§6) ;
#   décision 8 — un journal devenu inécrivable en cours d'exécution n'interrompt
#                plus le script : un seul avertissement sur stderr, puis
#                l'exécution se poursuit sans journal (§11) ;
#   décision 9 — le message du trap ERR nomme le fichier RÉELLEMENT fautif,
#                common.sh compris, et non plus systématiquement le script
#                appelant (§12).
#
# Les sections 6, 9, 11 et 12 sont écrites pour rougir si l'une de ces trois
# corrections était défaite : les mutations correspondantes ont été jouées, une
# à une, et chacune fait tomber au moins une assertion. La seule exception est
# consignée à l'endroit du cas concerné (§11, « le drapeau _JOURNAL_AVERTI »).

set -Eeuo pipefail

_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_dir/lib/common.sh" ] && [ "$_dir" != "/" ]; do _dir="$(dirname "$_dir")"; done
source "$_dir/lib/common.sh"

# shellcheck source=/dev/null
source "$SCRIPTS_ROOT/tests/lib/assert.sh"

ETIQUETTE="lib/common.sh"

# Utilisateur non privilégié employé pour éprouver require_root.
UTILISATEUR_NON_ROOT="nobody"

# -------------------------------------------------------------------
# Bac à sable
# -------------------------------------------------------------------
REP_TMP="$(mktemp -d)"
trap 'rm -rf "$REP_TMP"' EXIT

DEPOT="$REP_TMP/depot"
REP_LOGS="$REP_TMP/journaux"
JOURNAL_ATTENDU="$REP_LOGS/extrait.log"
F_EXTRAIT="$REP_TMP/extrait.sh"
F_OUT="$REP_TMP/stdout"
F_ERR="$REP_TMP/stderr"
F_ENTREE="$REP_TMP/entree"

# Répertoire de journaux transmis aux extraits. Il vaut REP_LOGS pour tous les
# cas sauf le §10, qui le détourne volontairement vers un chemin NON créable
# afin d'éprouver common.sh lorsque la journalisation est impossible. Une
# variable plutôt qu'un paramètre supplémentaire : le détournement reste ainsi
# visible à l'endroit du cas qui le pratique, et remis à sa valeur d'origine là.
REP_LOGS_CAS="$REP_LOGS"

mkdir -p "$DEPOT/lib" "$DEPOT/config" "$REP_LOGS"
cp "$SCRIPTS_ROOT/lib/common.sh" "$DEPOT/lib/common.sh"

# Le bac doit rester traversable et lisible après dégradation de privilèges
# (§4), et le répertoire de journaux inscriptible par l'utilisateur dégradé.
chmod 0755 "$REP_TMP" "$DEPOT" "$DEPOT/lib" "$DEPOT/config"
chmod 0644 "$DEPOT/lib/common.sh"
chmod 0777 "$REP_LOGS"

# Préambule commun à tous les extraits. Le chemin du bac et celui des journaux
# arrivent en paramètres positionnels plutôt que par l'environnement : ils
# survivent ainsi à n'importe quel lanceur de dégradation de privilèges.
PREAMBULE="$(cat <<'PRE'
#!/usr/bin/env bash
# Extrait jetable, écrit et supprimé par tests/unit/common.test.sh.
set -Eeuo pipefail

DEPOT_TEST="$1"; shift
export LOG_DIR="$1"; shift

# shellcheck source=/dev/null
source "$DEPOT_TEST/lib/common.sh"
PRE
)"

# Résultats du dernier appel à « executer ».
CODE=0
SORTIE=""
ERREUR=""
JOURNAL=""

# executer <corps> [fichier d'entrée] [lanceur...]
#
# Écrit le corps à la suite du préambule, l'exécute dans un processus bash neuf
# et recueille code de retour, stdout, stderr et journal. Le lanceur facultatif
# préfixe la commande : il sert à dégrader les privilèges (§4).
executer() {
    local corps="$1"
    local entree="${2:-/dev/null}"
    if [ "$#" -gt 2 ]; then
        shift 2
    else
        set --
    fi

    {
        printf '%s\n' "$PREAMBULE"
        printf '%s\n' "$corps"
    } > "$F_EXTRAIT"
    chmod 0644 "$F_EXTRAIT"

    rm -f "$JOURNAL_ATTENDU"

    CODE=0
    "$@" bash "$F_EXTRAIT" "$DEPOT" "$REP_LOGS_CAS" \
        <"$entree" >"$F_OUT" 2>"$F_ERR" || CODE=$?

    SORTIE="$(cat "$F_OUT")"
    ERREUR="$(cat "$F_ERR")"
    JOURNAL=""
    if [ -f "$JOURNAL_ATTENDU" ]; then
        JOURNAL="$(cat "$JOURNAL_ATTENDU")"
    fi
}

# compter <texte> <motif> — nombre de lignes contenant le motif, LITTÉRALEMENT.
#
# Ni « grep -c » ni « grep | wc » : grep sort en 1 quand il ne trouve rien, ce
# qui armerait le trap ERR du harnais pour un décompte légitimement nul — et un
# « || true » pour l'éteindre reviendrait à neutraliser une assertion. awk rend
# toujours 0, et « index » y cherche une sous-chaîne littérale, comme
# « contient » le fait pour les assertions.
compter() {
    local texte="$1" motif="$2"
    printf '%s\n' "$texte" | awk -v m="$motif" 'index($0, m) { n++ } END { print n + 0 }'
}

# -------------------------------------------------------------------
# Ce que cet environnement permet
# -------------------------------------------------------------------
# Une distribution identifiable, pour §5.
OS_ID_REEL=""
OS_VERSION_REEL=""
if [ -r /etc/os-release ]; then
    OS_ID_REEL="$( . /etc/os-release; printf '%s\n' "${ID:-}" )"
    OS_VERSION_REEL="$( . /etc/os-release; printf '%s\n' "${VERSION_ID:-}" )"
fi

# Un moyen de tomber sous un utilisateur non privilégié, pour §4.
#
# Trois candidats, tous utilisables comme simple préfixe de commande. Ils sont
# ÉPROUVÉS et non supposés : la présence de l'exécutable ne garantit ni les
# capacités nécessaires, ni le succès de l'appel.
MODE_NON_ROOT="indisponible"
RAISON_NON_ROOT=""
LANCEUR_NON_ROOT=()

essayer_lanceur() {
    local uid_obtenu
    uid_obtenu="$("$@" id -u 2>/dev/null)" || return 1
    [ -n "$uid_obtenu" ] || return 1
    [ "$uid_obtenu" != "0" ] || return 1
    return 0
}

detecter_non_root() {
    local uid gid essai
    local candidat=()

    if [ "$(id -u)" != "0" ]; then
        MODE_NON_ROOT="direct"
        return 0
    fi

    if ! id "$UTILISATEUR_NON_ROOT" >/dev/null 2>&1; then
        RAISON_NON_ROOT="l'utilisateur « $UTILISATEUR_NON_ROOT » n'existe pas sur ce système"
        return 0
    fi
    uid="$(id -u "$UTILISATEUR_NON_ROOT")"
    gid="$(id -g "$UTILISATEUR_NON_ROOT")"

    for essai in setpriv runuser chroot; do
        command -v "$essai" >/dev/null 2>&1 || continue
        case "$essai" in
            setpriv) candidat=(setpriv --reuid="$uid" --regid="$gid" --clear-groups) ;;
            runuser) candidat=(runuser -u "$UTILISATEUR_NON_ROOT" --) ;;
            chroot)  candidat=(chroot --userspec="$uid:$gid" /) ;;
        esac
        if essayer_lanceur "${candidat[@]}"; then
            LANCEUR_NON_ROOT=("${candidat[@]}")
            MODE_NON_ROOT="degrade"
            info "Dégradation de privilèges par « $essai » vers $UTILISATEUR_NON_ROOT."
            return 0
        fi
    done

    RAISON_NON_ROOT="aucun de setpriv, runuser ou chroot --userspec n'a pu abaisser les privilèges"
    return 0
}

detecter_non_root

# ===================================================================
# 0. Le bac à sable est fidèle
# ===================================================================
titre "0. Bac à sable"

if cmp -s "$SCRIPTS_ROOT/lib/common.sh" "$DEPOT/lib/common.sh"; then
    ok "la copie éprouvée est identique à lib/common.sh"
else
    ko "la copie éprouvée diffère de lib/common.sh" \
       "les cas suivants ne porteraient pas sur le socle du dépôt"
fi

executer "$(cat <<'FIN'
printf 'SCRIPTS_ROOT=%s\n' "$SCRIPTS_ROOT"
printf 'LOG_DIR=%s\n'      "$LOG_DIR"
printf 'LOG_FILE=%s\n'     "$LOG_FILE"
FIN
)"

assert_code 0 "$CODE" "common.sh se charge dans un processus neuf"
assert_contient "$SORTIE" "SCRIPTS_ROOT=$DEPOT" \
    "SCRIPTS_ROOT est résolu depuis l'emplacement de lib/common.sh"
assert_contient "$SORTIE" "LOG_DIR=$REP_LOGS" \
    "LOG_DIR est bien redirigé vers le répertoire temporaire"
assert_contient "$SORTIE" "LOG_FILE=$JOURNAL_ATTENDU" \
    "LOG_FILE est déduit de LOG_DIR et du nom du script"

# ===================================================================
# 1. info, warn, error, success — stderr et fichier de log
# ===================================================================
titre "1. Journalisation"

executer "$(cat <<'FIN'
info    "marqueur-info"
warn    "marqueur-warn"
error   "marqueur-error"
success "marqueur-success"
printf 'TERMINE\n'
FIN
)"

assert_code 0 "$CODE" "les quatre fonctions de journalisation n'interrompent pas le script"

assert_contient "$ERREUR" "[INFO] marqueur-info"       "info écrit sur stderr avec le préfixe [INFO]"
assert_contient "$ERREUR" "[WARN] marqueur-warn"       "warn écrit sur stderr avec le préfixe [WARN]"
assert_contient "$ERREUR" "[ERROR] marqueur-error"     "error écrit sur stderr avec le préfixe [ERROR]"
assert_contient "$ERREUR" "[SUCCESS] marqueur-success" "success écrit sur stderr avec le préfixe [SUCCESS]"

assert_contient "$JOURNAL" "[INFO] marqueur-info"       "info écrit dans le fichier de log"
assert_contient "$JOURNAL" "[WARN] marqueur-warn"       "warn écrit dans le fichier de log"
assert_contient "$JOURNAL" "[ERROR] marqueur-error"     "error écrit dans le fichier de log"
assert_contient "$JOURNAL" "[SUCCESS] marqueur-success" "success écrit dans le fichier de log"

# stdout appartient aux données que le script produit : aucun message de
# journalisation ne doit y atterrir, sous peine de fausser tout appelant qui
# lirait cette sortie.
assert_contient "$SORTIE" "TERMINE"  "stdout reste utilisable par le script"
assert_absent   "$SORTIE" "marqueur-" "aucun message de journalisation n'atterrit sur stdout"

# La sortie n'étant pas un terminal, les séquences de couleur sont désactivées.
# Le motif est le caractère d'échappement lui-même, produit par printf : la
# chaîne littérale « \033 » n'apparaîtrait jamais dans la sortie et ce contrôle
# passerait toujours, quoi qu'il arrive.
assert_absent "$ERREUR" "$(printf '\033')" "aucune séquence de couleur hors terminal"

# ===================================================================
# 2. die — code fourni, 1 par défaut
# ===================================================================
titre "2. die"

executer 'die "message-die-defaut"'
assert_code 1 "$CODE" "die sort en 1 par défaut"
assert_contient "$ERREUR"  "[ERROR] message-die-defaut" "die écrit son message avec le préfixe [ERROR]"
assert_contient "$JOURNAL" "[ERROR] message-die-defaut" "die consigne son message dans le journal"

executer "$(cat <<'FIN'
die "message-die-code" 7
printf 'JAMAIS_ATTEINT\n'
FIN
)"
assert_code 7 "$CODE" "die sort avec le code fourni"
assert_absent "$SORTIE" "JAMAIS_ATTEINT" "die interrompt le script immédiatement"

executer 'die "message-die-usage" 2'
assert_code 2 "$CODE" "die transmet le code 2, réservé aux erreurs d'usage"

# ===================================================================
# 3. require_cmd
# ===================================================================
titre "3. require_cmd"

executer "$(cat <<'FIN'
require_cmd bash cat
printf 'PRESENTES\n'
FIN
)"
assert_code 0 "$CODE" "require_cmd réussit sur des commandes présentes"
assert_contient "$SORTIE" "PRESENTES" "require_cmd laisse le script se poursuivre"

executer "$(cat <<'FIN'
require_cmd bash commande-absente-xyz autre-absente-abc
printf 'JAMAIS_ATTEINT\n'
FIN
)"
assert_code 1 "$CODE" "require_cmd échoue lorsqu'une commande manque"
# Le message ne doit citer QUE les manquantes, dans l'ordre où elles ont été
# demandées : « bash » est présent et n'a rien à y faire.
assert_contient "$ERREUR" \
    "Commande(s) requise(s) introuvable(s) : commande-absente-xyz autre-absente-abc" \
    "require_cmd liste les commandes manquantes, et elles seules"
assert_absent "$SORTIE" "JAMAIS_ATTEINT" "require_cmd interrompt le script"

# ===================================================================
# 4. require_root
# ===================================================================
titre "4. require_root"

CORPS_REQUIRE_ROOT="$(cat <<'FIN'
require_root
printf 'PRIVILEGES_OK\n'
FIN
)"

case "$MODE_NON_ROOT" in
    direct)
        executer "$CORPS_REQUIRE_ROOT"
        ;;
    degrade)
        executer "$CORPS_REQUIRE_ROOT" /dev/null "${LANCEUR_NON_ROOT[@]}"
        ;;
    *)
        # Aucun moyen d'abaisser les privilèges : rien n'est exécuté, et les
        # cas correspondants sont déclarés NON EXÉCUTÉS ci-dessous.
        ;;
esac

if [ "$MODE_NON_ROOT" = "indisponible" ]; then
    saute "require_root sous un utilisateur non privilégié" "$RAISON_NON_ROOT"
    saute "le message d'erreur de require_root" "$RAISON_NON_ROOT"
    saute "l'interruption du script par require_root" "$RAISON_NON_ROOT"
else
    # Le critère dit « un code non nul » sans en fixer la valeur : l'assertion
    # est écrite comme le critère, et non plus stricte que lui.
    assert_code_non_nul "$CODE" "require_root échoue sous un utilisateur non privilégié"
    assert_contient "$ERREUR" "Ce script doit être exécuté en root" \
        "require_root explique pourquoi il refuse"
    assert_absent "$SORTIE" "PRIVILEGES_OK" "require_root interrompt le script avant la suite"
fi

if [ "$(id -u)" = "0" ]; then
    executer "$CORPS_REQUIRE_ROOT"
    assert_code 0 "$CODE" "require_root réussit en root"
    assert_contient "$SORTIE" "PRIVILEGES_OK" "require_root laisse le script se poursuivre en root"
else
    saute "require_root en root" "le harnais ne tourne pas sous root"
    saute "la poursuite du script après require_root en root" "le harnais ne tourne pas sous root"
fi

# ===================================================================
# 5. detect_os et require_os
# ===================================================================
titre "5. detect_os et require_os"

if [ -z "$OS_ID_REEL" ]; then
    saute "detect_os renseigne OS_ID, OS_VERSION et OS_ARCH" "/etc/os-release illisible sur ce système"
    saute "detect_os exporte OS_ID vers les processus fils" "/etc/os-release illisible sur ce système"
    saute "require_os accepte la distribution attendue"      "/etc/os-release illisible sur ce système"
    saute "require_os accepte l'une des distributions listées" "/etc/os-release illisible sur ce système"
    saute "require_os refuse une distribution non listée"    "/etc/os-release illisible sur ce système"
else
    export OS_ATTENDU="$OS_ID_REEL"

    executer "$(cat <<'FIN'
detect_os
printf 'OS_ID=%s\n'      "$OS_ID"
printf 'OS_VERSION=%s\n' "$OS_VERSION"
printf 'OS_ARCH=%s\n'    "$OS_ARCH"
bash -c 'printf "FILS_OS_ID=%s\n" "${OS_ID:-absente}"'
FIN
)"
    assert_code 0 "$CODE" "detect_os réussit là où /etc/os-release est lisible"
    assert_contient "$SORTIE" "OS_ID=$OS_ID_REEL"    "detect_os renseigne OS_ID depuis /etc/os-release"
    assert_contient "$SORTIE" "OS_ARCH=$(uname -m)"  "detect_os renseigne OS_ARCH depuis uname -m"

    valeur_version="$(printf '%s\n' "$SORTIE" | sed -n 's/^OS_VERSION=//p')"
    assert_non_vide "$valeur_version" "detect_os renseigne OS_VERSION"

    if [ -n "$OS_VERSION_REEL" ]; then
        assert_egal "$OS_VERSION_REEL" "$valeur_version" \
            "OS_VERSION reprend le VERSION_ID de /etc/os-release"
    else
        # VERSION_ID est facultatif dans /etc/os-release : common.sh retombe
        # alors sur « inconnue » plutôt que de laisser la variable vide.
        assert_egal "inconnue" "$valeur_version" \
            "OS_VERSION vaut « inconnue » à défaut de VERSION_ID"
    fi

    assert_contient "$SORTIE" "FILS_OS_ID=$OS_ID_REEL" \
        "detect_os exporte OS_ID vers les processus fils"

    executer "$(cat <<'FIN'
require_os "$OS_ATTENDU"
printf 'ACCEPTE\n'
FIN
)"
    assert_code 0 "$CODE" "require_os accepte la distribution courante"
    assert_contient "$SORTIE" "ACCEPTE" "require_os laisse le script se poursuivre"
    # OS_ID n'était pas renseignée : require_os a donc appelé detect_os lui-même.
    assert_absent "$ERREUR" "distribution non identifiable" \
        "require_os appelle detect_os quand OS_ID n'est pas encore renseignée"

    executer "$(cat <<'FIN'
require_os distribution-imaginaire "$OS_ATTENDU" autre-imaginaire
printf 'ACCEPTE\n'
FIN
)"
    assert_code 0 "$CODE" "require_os accepte l'une quelconque des distributions listées"

    executer "$(cat <<'FIN'
require_os distribution-imaginaire autre-imaginaire
printf 'JAMAIS_ATTEINT\n'
FIN
)"
    assert_code 1 "$CODE" "require_os refuse une distribution non listée"
    assert_contient "$ERREUR" "Distribution non supportée : $OS_ID_REEL" \
        "require_os nomme la distribution rencontrée et celles qu'il attendait"
    assert_absent "$SORTIE" "JAMAIS_ATTEINT" "require_os interrompt le script"
fi

# ===================================================================
# 6. load_config
# ===================================================================
titre "6. load_config"

# Affectations nues, conformes à config/README.md : « uniquement des
# affectations, jamais de commandes ».
cat > "$DEPOT/config/unitaire.env" <<'FIN'
# Configuration jetable écrite par tests/unit/common.test.sh.
VALEUR_UNITAIRE="valeur-attendue"
VALEUR_AVEC_ESPACES="deux mots"
FIN

# Variante employant « export », pour situer précisément la frontière.
cat > "$DEPOT/config/unitaire-export.env" <<'FIN'
# Configuration jetable écrite par tests/unit/common.test.sh.
export VALEUR_EXPORTEE="valeur-exportee"
FIN

# Fichier dont le « source » ÉCHOUE : un guillemet jamais refermé. L'erreur est
# de syntaxe, donc constatée à l'analyse — le fichier n'est pas exécuté du tout
# et « . » rend un code non nul de façon déterministe. Une commande en échec au
# milieu du fichier ne conviendrait pas : le source rendrait le code de sa
# DERNIÈRE commande, souvent 0.
cat > "$DEPOT/config/bancale.env" <<'FIN'
# Configuration jetable écrite par tests/unit/common.test.sh.
VALEUR_AVANT="avant"
VALEUR_BANCALE="guillemet jamais refermé
FIN

# Fichier dont le source RÉUSSIT malgré une commande en échec au milieu. C'est
# la contrepartie du « || code=$? » de load_config, mesurée et assumée : le
# contexte de condition suspend errexit PENDANT l'exécution du fichier, le
# source va jusqu'au bout et rend le code de sa dernière commande — ici une
# affectation, donc 0. La garde « Configuration illisible » ne se déclenche
# jamais sur ce cas.
cat > "$DEPOT/config/tolerante.env" <<'FIN'
# Configuration jetable écrite par tests/unit/common.test.sh.
VALEUR_TOLERANTE_AVANT="avant"
commande-absente-dans-un-env-xyz
VALEUR_TOLERANTE_APRES="apres"
FIN

chmod 0644 "$DEPOT/config/unitaire.env" "$DEPOT/config/unitaire-export.env" \
    "$DEPOT/config/bancale.env" "$DEPOT/config/tolerante.env"

executer "$(cat <<'FIN'
load_config unitaire
printf 'VALEUR_UNITAIRE=%s\n'      "${VALEUR_UNITAIRE:-absente}"
printf 'VALEUR_AVEC_ESPACES=%s\n'  "${VALEUR_AVEC_ESPACES:-absente}"
bash -c 'printf "FILS_NUE=%s\n" "${VALEUR_UNITAIRE:-absente}"'
FIN
)"

assert_code 0 "$CODE" "load_config charge un fichier existant"
assert_contient "$SORTIE" "VALEUR_UNITAIRE=valeur-attendue" \
    "les variables du fichier sont disponibles dans le shell appelant"
assert_contient "$SORTIE" "VALEUR_AVEC_ESPACES=deux mots" \
    "une valeur contenant des espaces est chargée telle quelle"
assert_contient "$ERREUR" "[INFO] Configuration chargée : config/unitaire.env" \
    "load_config annonce le fichier chargé"
assert_contient "$JOURNAL" "Configuration chargée : config/unitaire.env" \
    "load_config consigne le chargement dans le journal"

# ASSERTION RETOURNÉE (TASK-015, ADR-0003 décision 7). Elle affirmait
# « FILS_NUE=absente » : c'était le comportement d'avant le set -a. Le contrat
# dit maintenant l'inverse, et c'est ce que ce cas prouve. Une mutation qui
# retirerait le « set -a » de load_config fait rougir ici, et ici seulement.
assert_contient "$SORTIE" "FILS_NUE=valeur-attendue" \
    "une affectation nue d'un .env est propagée aux processus fils"

executer "$(cat <<'FIN'
load_config unitaire-export
printf 'VALEUR_EXPORTEE=%s\n' "${VALEUR_EXPORTEE:-absente}"
bash -c 'printf "FILS_EXPORT=%s\n" "${VALEUR_EXPORTEE:-absente}"'
FIN
)"
assert_code 0 "$CODE" "load_config charge un fichier employant export"
assert_contient "$SORTIE" "VALEUR_EXPORTEE=valeur-exportee" \
    "une variable exportée par le fichier est disponible dans le shell appelant"
assert_contient "$SORTIE" "FILS_EXPORT=valeur-exportee" \
    "load_config propage aux processus fils ce que le fichier exporte lui-même"

# --- Portée du set -a : elle s'arrête à load_config ------------------------
#
# L'exportation vaut pour la CONFIGURATION, pas pour tout ce que le script
# déclare ensuite. Sans le « set +a », chaque variable de travail du script
# partirait dans l'environnement de la moindre commande externe appelée après.
executer "$(cat <<'FIN'
load_config unitaire
etat="non"
case "$-" in *a*) etat="oui" ;; esac
printf 'ALLEXPORT_APRES=%s\n' "$etat"
DECLAREE_APRES="valeur-declaree-apres"
bash -c 'printf "FILS_DECLAREE_APRES=%s\n" "${DECLAREE_APRES:-absente}"'
FIN
)"
assert_code 0 "$CODE" "le script se poursuit après load_config"
assert_contient "$SORTIE" "ALLEXPORT_APRES=non" \
    "load_config éteint allexport en sortant — « a » n'est plus dans \$-"
assert_contient "$SORTIE" "FILS_DECLAREE_APRES=absente" \
    "une variable déclarée après load_config n'est pas exportée à son insu"

# L'appelant qui avait lui-même armé allexport le retrouve armé : load_config
# rétablit l'état ANTÉRIEUR, il ne force pas « off ».
executer "$(cat <<'FIN'
set -a
load_config unitaire
etat="non"
case "$-" in *a*) etat="oui" ;; esac
set +a
printf 'ALLEXPORT_PREALABLE=%s\n' "$etat"
FIN
)"
assert_code 0 "$CODE" "load_config s'exécute sous un allexport déjà armé"
assert_contient "$SORTIE" "ALLEXPORT_PREALABLE=oui" \
    "load_config rétablit l'état antérieur de allexport plutôt que de le forcer à « off »"

# --- Le cas silencieux : le source échoue ----------------------------------
#
# C'est le piège que la décision 7 nomme explicitement. Si « set +a » n'était
# pas atteint quand le source échoue, allexport resterait armé pour tout le
# reste de l'exécution — sans le moindre signe visible.
#
# load_config appelle « die » sur cet échec : l'état de allexport ne peut donc
# s'observer que depuis un piège EXIT, exécuté dans le MÊME shell juste avant la
# sortie. Un sous-shell ne conviendrait pas, son « $- » n'étant pas celui du
# script.
executer "$(cat <<'FIN'
etat_final() {
    local etat="non"
    case "$-" in *a*) etat="oui" ;; esac
    printf 'ALLEXPORT_APRES_ECHEC=%s\n' "$etat"
    MARQUEUR_APRES_ECHEC="declaree-dans-le-piege"
    bash -c 'printf "FILS_APRES_ECHEC=%s\n" "${MARQUEUR_APRES_ECHEC:-absente}"'
}
trap etat_final EXIT
load_config bancale
printf 'JAMAIS_ATTEINT\n'
FIN
)"
assert_code 1 "$CODE" "load_config sur un fichier illisible arrête le script"
assert_contient "$ERREUR" "Configuration illisible : config/bancale.env" \
    "load_config nomme le fichier dont le chargement a échoué"
assert_absent "$SORTIE" "JAMAIS_ATTEINT" "load_config n'exécute pas la suite du script"
assert_contient "$SORTIE" "ALLEXPORT_APRES_ECHEC=non" \
    "set +a est rétabli même lorsque le source du fichier échoue"
assert_contient "$SORTIE" "FILS_APRES_ECHEC=absente" \
    "aucune variable n'est exportée à son insu après un source en échec"

# --- L'autre face du « || code=$? » : la sévérité qu'il abandonne -----------
#
# Le contexte de condition qui garantit le « set +a » suspend AUSSI errexit
# pendant l'exécution du fichier sourcé. Une commande en échec au milieu d'un
# .env n'interrompt donc plus rien : le source va jusqu'au bout, rend le code de
# sa dernière commande — une affectation, donc 0 — et load_config annonce un
# chargement réussi. Le socle de « master » tuait le script sur le champ, en 127.
#
# C'est une contrepartie ASSUMÉE, inscrite dans docs/architecture-technique.md
# et en commentaire de load_config. Le risque reste théorique : config/README.md
# prescrit des fichiers faits d'affectations, jamais de commandes.
#
# Ce cas est le seul filet sous cette contrepartie. Qui « rétablirait » un jour
# la sévérité en retirant le « || code=$? » casserait du même geste la garantie
# du set +a rétabli quoi qu'il arrive — et sans ce cas, rien ne rougirait.
executer "$(cat <<'FIN'
load_config tolerante
printf 'AVANT=%s\n' "${VALEUR_TOLERANTE_AVANT:-absente}"
printf 'APRES=%s\n' "${VALEUR_TOLERANTE_APRES:-absente}"
etat="non"
case "$-" in *a*) etat="oui" ;; esac
printf 'ALLEXPORT=%s\n' "$etat"
bash -c 'printf "FILS_TOLERANTE=%s\n" "${VALEUR_TOLERANTE_APRES:-absente}"'
printf 'TERMINE\n'
FIN
)"
assert_code 0 "$CODE" \
    "une commande en échec au milieu d'un .env n'interrompt pas le script"
assert_contient "$ERREUR" "commande-absente-dans-un-env-xyz" \
    "la commande du .env a bien été tentée, et a bien échoué"
assert_contient "$SORTIE" "AVANT=avant" \
    "l'affectation qui précède la commande en échec est prise en compte"
assert_contient "$SORTIE" "APRES=apres" \
    "celle qui la SUIT l'est aussi : le source est allé jusqu'au bout"
assert_contient "$ERREUR" "[INFO] Configuration chargée : config/tolerante.env" \
    "load_config annonce un chargement réussi malgré la commande en échec"
assert_absent "$ERREUR" "Configuration illisible" \
    "la garde « Configuration illisible » ne se déclenche pas sur une commande en échec"
assert_contient "$SORTIE" "TERMINE" "le script se poursuit après le chargement"
assert_contient "$SORTIE" "ALLEXPORT=non" \
    "set +a est rétabli sur ce chemin aussi"
assert_contient "$SORTIE" "FILS_TOLERANTE=apres" \
    "l'exportation reste effective malgré la commande en échec"

executer "$(cat <<'FIN'
load_config configuration-inexistante-xyz
printf 'JAMAIS_ATTEINT\n'
FIN
)"
assert_code_non_nul "$CODE" "load_config sur un fichier absent arrête le script"
assert_contient "$ERREUR" "Configuration introuvable : config/configuration-inexistante-xyz.env" \
    "load_config nomme le fichier manquant et son modèle"
assert_absent "$SORTIE" "JAMAIS_ATTEINT" "load_config n'exécute pas la suite du script"

# ===================================================================
# 7. confirm
# ===================================================================
titre "7. confirm"

CORPS_CONFIRM="$(cat <<'FIN'
code=0
confirm "Question de contrôle ?" || code=$?
printf 'CODE=%s\n' "$code"
FIN
)"

# L'entrée standard est /dev/null : si confirm posait la question, « read »
# rencontrerait une fin de fichier et rendrait un code non nul. CODE=0 prouve
# donc l'absence d'interaction, et pas seulement le code de retour.
export ASSUME_YES="true"
executer "$CORPS_CONFIRM"
unset ASSUME_YES

assert_code 0 "$CODE" "confirm ne fait pas échouer le script quand ASSUME_YES vaut true"
assert_contient "$SORTIE" "CODE=0" "confirm retourne 0 lorsque ASSUME_YES vaut true"
assert_contient "$ERREUR" "Confirmation automatique" "confirm annonce la confirmation automatique"
assert_absent   "$ERREUR" "[o/N]" "confirm ne pose aucune question lorsque ASSUME_YES vaut true"

printf 'o\n' > "$F_ENTREE"
executer "$CORPS_CONFIRM" "$F_ENTREE"
assert_contient "$SORTIE" "CODE=0"  "confirm accepte une réponse « o »"
assert_contient "$ERREUR" "[o/N]"   "confirm pose la question quand ASSUME_YES ne vaut pas true"

printf 'n\n' > "$F_ENTREE"
executer "$CORPS_CONFIRM" "$F_ENTREE"
assert_contient "$SORTIE" "CODE=1" "confirm retourne 1 sur une réponse « n »"

printf '\n' > "$F_ENTREE"
executer "$CORPS_CONFIRM" "$F_ENTREE"
assert_contient "$SORTIE" "CODE=1" "confirm retourne 1 sur une réponse vide — le défaut est le refus"

# ===================================================================
# 8. Double chargement de common.sh
# ===================================================================
titre "8. Double chargement"

executer "$(cat <<'FIN'
avant_root="$SCRIPTS_ROOT"
avant_log_dir="$LOG_DIR"
avant_log_file="$LOG_FILE"
avant_garde="$_COMMON_SH_CHARGE"

avant_lignes=0
if [ -f "$LOG_FILE" ]; then
    avant_lignes="$(wc -l < "$LOG_FILE")"
fi

code_second=0
# shellcheck source=/dev/null
source "$DEPOT_TEST/lib/common.sh" || code_second=$?

apres_lignes=0
if [ -f "$LOG_FILE" ]; then
    apres_lignes="$(wc -l < "$LOG_FILE")"
fi

identique() {
    if [ "$1" = "$2" ]; then printf 'oui\n'; else printf 'non\n'; fi
}

printf 'CODE_SECOND=%s\n'    "$code_second"
printf 'GARDE_AVANT=%s\n'    "$avant_garde"
printf 'GARDE_APRES=%s\n'    "$_COMMON_SH_CHARGE"
printf 'ROOT=%s\n'           "$(identique "$avant_root" "$SCRIPTS_ROOT")"
printf 'LOG_DIR_STABLE=%s\n' "$(identique "$avant_log_dir" "$LOG_DIR")"
printf 'LOG_FILE_STABLE=%s\n' "$(identique "$avant_log_file" "$LOG_FILE")"
printf 'LIGNES=%s/%s\n'      "$avant_lignes" "$apres_lignes"
printf 'TYPE_INFO=%s\n'      "$(type -t info)"

# « trap -p » est exécuté directement, sans substitution de commande : selon la
# façon dont bash propage les traps à un sous-shell, « $(trap -p ERR) » pourrait
# ne rien rendre et ce contrôle passerait pour de mauvaises raisons.
printf 'TRAP_ERR: '
trap -p ERR

printf 'TERMINE\n'
FIN
)"

assert_code 0 "$CODE" "un second chargement de common.sh ne provoque aucune erreur"
assert_contient "$SORTIE" "CODE_SECOND=0"        "le second « source » retourne 0"
assert_contient "$SORTIE" "GARDE_AVANT=1"        "la garde _COMMON_SH_CHARGE est posée au premier chargement"
assert_contient "$SORTIE" "GARDE_APRES=1"        "la garde reste inchangée après le second chargement"
assert_contient "$SORTIE" "ROOT=oui"             "SCRIPTS_ROOT n'est pas recalculé"
assert_contient "$SORTIE" "LOG_DIR_STABLE=oui"   "LOG_DIR n'est pas recalculé"
assert_contient "$SORTIE" "LOG_FILE_STABLE=oui"  "LOG_FILE n'est pas recalculé"
assert_contient "$SORTIE" "LIGNES=0/0"           "le second chargement n'écrit rien dans le journal"
assert_contient "$SORTIE" "TYPE_INFO=function"   "les fonctions restent définies après le second chargement"
assert_contient "$SORTIE" "TRAP_ERR: trap -- '_on_error" \
    "le trap ERR de common.sh est toujours celui installé au premier chargement"
assert_contient "$SORTIE" "TERMINE"              "le script se poursuit normalement"

# Preuve directe du court-circuit : SCRIPTS_ROOT est volontairement falsifiée
# avant le second « source ». Si la garde ne jouait pas, common.sh la
# recalculerait et la valeur falsifiée disparaîtrait.
executer "$(cat <<'FIN'
SCRIPTS_ROOT="/marqueur-court-circuit"
# shellcheck source=/dev/null
source "$DEPOT_TEST/lib/common.sh"
printf 'SCRIPTS_ROOT=%s\n' "$SCRIPTS_ROOT"
FIN
)"
assert_code 0 "$CODE" "le court-circuit du second chargement n'interrompt pas le script"
assert_contient "$SORTIE" "SCRIPTS_ROOT=/marqueur-court-circuit" \
    "la garde _COMMON_SH_CHARGE court-circuite réellement le second chargement"

# Portée de la garde, et fondation de tout ce fichier. _COMMON_SH_CHARGE est une
# variable de shell, non exportée : un SOUS-SHELL en hérite — son « source »
# devient une opération nulle — tandis qu'un PROCESSUS bash neuf ne la reçoit
# pas et recharge réellement common.sh.
#
# C'est ce qui rend « ( source … ) » inapte à éprouver le socle, et ce qui rend
# valide le procédé retenu ici. Si la garde était exportée, chacun des cas de ce
# fichier n'exécuterait rien et passerait pour de bonnes raisons apparentes.
executer "$(cat <<'FIN'
garde_fils="$( bash -c 'printf "%s" "${_COMMON_SH_CHARGE:-absente}"' )"
printf 'GARDE_DANS_UN_FILS=%s\n' "$garde_fils"

racine_sous_shell="$(
    SCRIPTS_ROOT="/marqueur-sous-shell"
    # shellcheck source=/dev/null
    source "$DEPOT_TEST/lib/common.sh"
    printf '%s' "$SCRIPTS_ROOT"
)"
printf 'RACINE_SOUS_SHELL=%s\n' "$racine_sous_shell"
FIN
)"
assert_code 0 "$CODE" "la portée de la garde s'observe sans erreur"
assert_contient "$SORTIE" "GARDE_DANS_UN_FILS=absente" \
    "_COMMON_SH_CHARGE n'est pas exportée : un processus neuf recharge bien common.sh"
assert_contient "$SORTIE" "RACINE_SOUS_SHELL=/marqueur-sous-shell" \
    "un sous-shell hérite de la garde : son « source » y est une opération nulle"

# ===================================================================
# 9. run_logged
# ===================================================================
titre "9. run_logged"

executer "$(cat <<'FIN'
code=0
run_logged bash -c 'printf "sortie-enveloppee\n"; exit 42' || code=$?
printf 'CODE=%s\n' "$code"
FIN
)"

assert_code 0 "$CODE" "le script survit à run_logged sur une commande en échec"
assert_contient "$SORTIE"  "CODE=42"            "run_logged retourne le code de la commande enveloppée"
assert_contient "$JOURNAL" "sortie-enveloppee"  "run_logged consigne la sortie de la commande dans le journal"
assert_contient "$JOURNAL" "Exécution : bash -c" "run_logged annonce dans le journal la commande exécutée"
assert_contient "$ERREUR"  "sortie-enveloppee"  "run_logged renvoie la sortie de la commande sur stderr"
assert_absent   "$SORTIE"  "sortie-enveloppee"  "run_logged laisse stdout aux données du script"

executer "$(cat <<'FIN'
code=0
run_logged true || code=$?
printf 'CODE=%s\n' "$code"
FIN
)"
assert_contient "$SORTIE" "CODE=0" "run_logged retourne 0 sur une commande qui réussit"

# --- Les deux cas discriminants -------------------------------------------
#
# Ce sont les seuls à prouver que run_logged rend PIPESTATUS[0] et non le code
# du tube : partout ailleurs tee réussit, et les deux valeurs coïncident. Il
# faut donc un tee qui ÉCHOUE pendant que la branche à tee reste empruntée.
#
# La façon de faire a dû changer avec TASK-015, et c'est le point le plus
# fragile de ce fichier. Ces deux cas pointaient auparavant LOG_FILE vers un
# répertoire inexistant. Depuis la décision 8, le « info » d'ouverture de
# run_logged constate le journal mort, avertit et VIDE LOG_FILE : le test qui
# suit bascule sur la branche sans tee, tee n'est plus atteint, et les deux
# assertions resteraient vertes sans plus rien prouver. Une régression de
# couverture silencieuse — le onzième critère de TASK-003 aurait disparu sans
# qu'aucun voyant ne s'allume.
#
# Le journal reste donc parfaitement écrivable, et c'est TEE SEUL qui échoue :
# un faux tee, placé en tête de PATH, relaie fidèlement son entrée puis sort en
# 1. Les deux gardes qui suivent chaque cas — journal non vide, aucun
# avertissement de journal mort — vérifient que la branche à tee a bien été
# empruntée. Sans elles, ce cas pourrait redevenir creux sans se voir.
mkdir -p "$DEPOT/bin"
cat > "$DEPOT/bin/tee" <<'FIN'
#!/usr/bin/env bash
# Faux tee, écrit par tests/unit/common.test.sh. Relaie l'entrée sur sa sortie
# standard comme le ferait le vrai — run_logged la redirige vers stderr — puis
# échoue, sans rien écrire dans le fichier qu'on lui demande.
cat
exit 1
FIN
chmod 0755 "$DEPOT/bin" "$DEPOT/bin/tee"

executer "$(cat <<'FIN'
PATH="$DEPOT_TEST/bin:$PATH"
printf 'TEE=%s\n' "$(command -v tee)"
FIN
)"
assert_contient "$SORTIE" "TEE=$DEPOT/bin/tee" \
    "le faux tee est bien celui que le PATH du cas résout"

# 1. commande à 0, tee à 1 : « pipefail » donnerait 1 au tube, run_logged doit
#    rendre 0 ;
executer "$(cat <<'FIN'
PATH="$DEPOT_TEST/bin:$PATH"
code=0
run_logged true || code=$?
printf 'CODE=%s\n' "$code"
printf 'LOG_FILE_VIDE=%s\n' "$([ -z "$LOG_FILE" ] && printf oui || printf non)"
FIN
)"
assert_contient "$SORTIE" "CODE=0" \
    "run_logged rend le code de la commande, pas celui de tee"
assert_contient "$SORTIE" "LOG_FILE_VIDE=non" \
    "le journal est resté vivant : c'est bien la branche à tee qui a été empruntée"
assert_contient "$JOURNAL" "Exécution : true" \
    "run_logged a bien écrit dans le journal avant d'appeler tee"
assert_absent "$ERREUR" "Journal inaccessible" \
    "aucune bascule vers la branche sans tee n'a eu lieu"

# 2. commande à 42, tee à 1 : le seul code qui distingue PIPESTATUS[0] à la
#    fois du code du tube ET de celui de tee — les deux valant 1 ici.
# Le marqueur est ASSEMBLÉ À L'EXÉCUTION — « relayee-par-le-faux-%s » et « tee »
# sont deux arguments distincts. Sans cette précaution, le marqueur figurerait
# tel quel dans la ligne de commande, que run_logged annonce et journalise :
# le chercher dans le journal ne prouverait alors rien de ce que tee y a écrit.
executer "$(cat <<'FIN'
PATH="$DEPOT_TEST/bin:$PATH"
code=0
run_logged bash -c "printf 'relayee-par-le-faux-%s\n' tee; exit 42" || code=$?
printf 'CODE=%s\n' "$code"
FIN
)"
assert_contient "$SORTIE" "CODE=42" \
    "run_logged rend le code de la commande en échec alors que tee échoue aussi"
assert_contient "$ERREUR" "relayee-par-le-faux-tee" \
    "la sortie de la commande traverse tee jusqu'à stderr"
assert_absent "$ERREUR" "Journal inaccessible" \
    "un tee en échec ne fait pas passer le journal pour mort"

# Le journal, lui, ne reçoit rien de la commande : le faux tee n'y écrit pas.
# La ligne d'annonce, elle, y est — c'est info qui l'a écrite, pas tee.
assert_contient "$JOURNAL" "Exécution : bash -c" \
    "l'annonce de run_logged est consignée alors même que tee échoue"
assert_absent "$JOURNAL" "relayee-par-le-faux-tee" \
    "rien n'a été consigné par le tee en échec"

# Bascule automatique : LOG_FILE pointe vers un chemin mort AVANT l'appel. Le
# « info » d'ouverture le constate, vide LOG_FILE, et run_logged prend de
# lui-même la branche sans tee. C'est le comportement voulu par la décision 8 —
# et c'est aussi la raison pour laquelle les deux cas ci-dessus ne peuvent plus
# s'écrire ainsi.
executer "$(cat <<'FIN'
LOG_FILE="$LOG_DIR/repertoire-inexistant/journal.log"
code=0
run_logged bash -c 'printf "sortie-apres-bascule\n"; exit 42' || code=$?
printf 'CODE=%s\n' "$code"
printf 'LOG_FILE_VIDE=%s\n' "$([ -z "$LOG_FILE" ] && printf oui || printf non)"
FIN
)"
assert_code 0 "$CODE" "un journal mort n'interrompt pas run_logged"
assert_contient "$SORTIE" "LOG_FILE_VIDE=oui" \
    "run_logged bascule sur la branche sans tee quand le journal est mort"
assert_contient "$SORTIE" "CODE=42" \
    "run_logged rend le code de la commande après la bascule"
assert_contient "$ERREUR" "sortie-apres-bascule" \
    "la sortie de la commande parvient à stderr après la bascule"

# ===================================================================
# 10. Journalisation impossible — LOG_DIR non créable
# ===================================================================
# common.sh laisse LOG_FILE vide lorsque « mkdir -p "$LOG_DIR" » échoue. Cette
# branche gouverne _log ET la seconde moitié de run_logged, celle qui n'emploie
# pas tee : sans ce cas, la moitié de la fonction visée par le onzième critère
# ne serait jamais exécutée. Le chemin est rendu non créable par un FICHIER
# ordinaire placé là où il faudrait un répertoire — plus sûr qu'un chemin
# absolu interdit, qui dépendrait des privilèges de l'exécutant.
titre "10. Journalisation impossible"

OBSTACLE="$REP_TMP/obstacle"
: > "$OBSTACLE"

REP_LOGS_CAS="$OBSTACLE/journaux"
executer "$(cat <<'FIN'
printf 'LOG_FILE=[%s]\n' "$LOG_FILE"
info "marqueur-sans-journal"
code=0
run_logged bash -c 'printf "sortie-sans-tee\n"; exit 42' || code=$?
printf 'CODE=%s\n' "$code"
printf 'TERMINE\n'
FIN
)"
REP_LOGS_CAS="$REP_LOGS"

assert_code 0 "$CODE" "un LOG_DIR non créable n'empêche pas le script de tourner"
assert_contient "$SORTIE" "LOG_FILE=[]" \
    "LOG_FILE reste vide lorsque LOG_DIR ne peut pas être créé"
assert_contient "$ERREUR" "[INFO] marqueur-sans-journal" \
    "les fonctions de journalisation écrivent sur stderr même sans fichier de log"
assert_egal "" "$JOURNAL" "aucun journal n'est écrit hors du répertoire prévu"
assert_contient "$SORTIE" "CODE=42" \
    "run_logged rend le code de la commande dans sa branche sans tee"
assert_contient "$ERREUR" "sortie-sans-tee" \
    "run_logged renvoie la sortie sur stderr même sans fichier de log"
assert_absent "$SORTIE" "sortie-sans-tee" \
    "run_logged laisse stdout aux données du script même sans fichier de log"
assert_contient "$SORTIE" "TERMINE" "le script se poursuit après un run_logged sans journal"

if [ -f "$OBSTACLE" ]; then
    ok "l'obstacle est resté un fichier ordinaire — rien n'a été créé sous lui"
else
    ko "l'obstacle n'est plus un fichier ordinaire" \
       "common.sh aurait alors écrit là où mkdir avait échoué"
fi

# ===================================================================
# 11. Journal devenu inécrivable EN COURS D'EXÉCUTION
# ===================================================================
# À ne pas confondre avec le §10, qui traite d'un LOG_DIR impossible à créer AU
# CHARGEMENT — LOG_FILE y reste vide et rien n'est jamais tenté. Ici, le journal
# a été ouvert normalement puis disparaît : répertoire supprimé, disque plein,
# droits modifiés. Avant TASK-015, le premier « info » qui suivait tuait le
# script sous set -e. ADR-0003 décision 8 : un avertissement, UNE SEULE FOIS,
# puis on continue sans journal.
titre "11. Journal inécrivable en cours d'exécution"

JOURNAL_MORT_1="$REP_LOGS/repertoire-inexistant/journal.log"

executer "$(cat <<'FIN'
LOG_FILE="$LOG_DIR/repertoire-inexistant/journal.log"
i=0
while [ "$i" -lt 50 ]; do
    info "pulsation-$i"
    i=$((i + 1))
done
warn    "apres-warn"
error   "apres-error"
success "apres-success"
code=0
run_logged bash -c 'printf "sortie-journal-mort\n"; exit 7' || code=$?
printf 'CODE_RUN_LOGGED=%s\n' "$code"
printf 'LOG_FILE=[%s]\n' "$LOG_FILE"
printf 'TERMINE\n'
FIN
)"

assert_code 0 "$CODE" "un journal devenu inécrivable n'interrompt pas le script"
assert_contient "$SORTIE" "TERMINE" "le script va jusqu'à sa dernière instruction"

# « Une seule fois » : cinquante info, puis warn, error, success et run_logged.
assert_egal "1" "$(compter "$ERREUR" "Journal inaccessible")" \
    "un seul avertissement de journal inaccessible pour 54 messages"
assert_egal "50" "$(compter "$ERREUR" "[INFO] pulsation-")" \
    "les cinquante messages sont tous affichés malgré le journal mort"
assert_contient "$ERREUR" "[WARN] apres-warn"       "warn continue de fonctionner après la mort du journal"
assert_contient "$ERREUR" "[ERROR] apres-error"     "error continue de fonctionner après la mort du journal"
assert_contient "$ERREUR" "[SUCCESS] apres-success" "success continue de fonctionner après la mort du journal"
assert_contient "$ERREUR" "$JOURNAL_MORT_1" "l'avertissement nomme le journal devenu inaccessible"

# AUCUN message brut de bash. C'est ce qui valide que la redirection porte sur
# le GROUPE et non sur le seul printf : appliquée au printf, elle serait établie
# après l'ouverture de LOG_FILE, et bash aurait déjà écrit son « … : No such
# file or directory » sur la stderr du script.
#
# Le décompte du chemin est l'assertion qui porte : le chemin n'a le droit
# d'apparaître qu'une fois, dans l'avertissement du socle. Elle tient quelle que
# soit la langue de bash, là où le libellé anglais ci-dessous ne dirait plus
# rien sous une autre locale — les deux sont gardées, la seconde pour ce
# qu'elle nomme.
assert_egal "1" "$(compter "$ERREUR" "$JOURNAL_MORT_1")" \
    "le chemin du journal mort n'apparaît qu'une fois : aucun message brut de bash"
assert_absent "$ERREUR" "No such file or directory" \
    "le message brut de bash est étouffé, remplacé par un avertissement lisible"

# Le socle vide LOG_FILE : c'est sa convention pour « pas de journal », déjà
# celle du §10. run_logged s'y conforme et prend la branche sans tee.
assert_contient "$SORTIE" "LOG_FILE=[]" "le socle neutralise le journal hors service"
assert_contient "$SORTIE" "CODE_RUN_LOGGED=7" "run_logged rend son code après la mort du journal"
assert_contient "$ERREUR" "sortie-journal-mort" "run_logged fonctionne encore sans journal"
assert_egal "" "$JOURNAL" "rien n'est écrit dans le journal d'origine"

if [ -e "$REP_LOGS/repertoire-inexistant" ]; then
    ko "le répertoire du journal mort a été créé" \
       "le socle ne doit rien créer là où l'écriture a échoué"
else
    ok "aucun répertoire n'est créé pour un journal hors service"
fi

# Le drapeau _JOURNAL_AVERTI, épinglé pour lui-même.
#
# Sur le chemin ordinaire, « une seule fois » tient DEUX FOIS : par le drapeau,
# et parce que LOG_FILE est vidé — _journaliser sort alors avant même de tenter
# quoi que ce soit. Retirer le drapeau ne se verrait donc pas ci-dessus. Le seul
# scénario qui le distingue est celui d'un script qui REARME LOG_FILE après
# coup, vers un chemin lui aussi mort. C'est ce cas, et lui seul, qui fait
# rougir la mutation « drapeau retiré ».
JOURNAL_MORT_2="$REP_LOGS/autre-repertoire-inexistant/journal.log"

executer "$(cat <<'FIN'
LOG_FILE="$LOG_DIR/repertoire-inexistant/journal.log"
info "premiere-mort"
LOG_FILE="$LOG_DIR/autre-repertoire-inexistant/journal.log"
info "seconde-mort"
printf 'TERMINE\n'
FIN
)"
assert_code 0 "$CODE" "un journal réarmé puis mort à nouveau n'interrompt pas le script"
assert_contient "$SORTIE" "TERMINE" "le script se poursuit après la seconde mort"
assert_egal "1" "$(compter "$ERREUR" "Journal inaccessible")" \
    "le drapeau _JOURNAL_AVERTI empêche un second avertissement, journal réarmé compris"
assert_absent "$ERREUR" "$JOURNAL_MORT_2" \
    "le second journal mort n'est pas annoncé — l'avertissement a déjà eu lieu"
assert_contient "$ERREUR" "[INFO] seconde-mort" \
    "les messages continuent d'être affichés après la seconde mort"

# ===================================================================
# 12. trap ERR — le message nomme le fichier RÉELLEMENT fautif
# ===================================================================
# Avant TASK-015, le trap employait « basename "$0" » : il nommait toujours le
# script appelant, y compris quand la faute venait du socle — « à la ligne 273
# de extrait.sh » alors que la ligne 273 est celle de common.sh. $LINENO et le
# nom du fichier désignaient deux unités différentes, et le diagnostic était
# trompeur. ADR-0003 décision 9 : « ${BASH_SOURCE[0]} », évalué DANS la chaîne
# du trap.
#
# Les deux sens sont éprouvés. Un seul ne suffirait pas : une correction qui se
# contenterait d'inverser le défaut — nommer toujours common.sh — passerait un
# test unilatéral.
titre "12. trap ERR — fichier fautif"

# Sens 1 : la faute vient de lib/common.sh. « read » y échoue sur une fin de
# fichier, à l'intérieur de confirm, l'entrée standard étant /dev/null. C'est un
# échec RÉEL du socle, pas une simulation.
executer "$(cat <<'FIN'
confirm "Question sans réponse possible ?"
printf 'JAMAIS_ATTEINT\n'
FIN
)"
assert_code_non_nul "$CODE" "un échec survenu dans common.sh interrompt le script"
assert_contient "$ERREUR" "de common.sh." \
    "le trap ERR nomme common.sh quand la faute vient du socle"
assert_absent "$ERREUR" "de extrait.sh." \
    "le trap ERR ne met pas la faute du socle sur le compte du script appelant"
assert_absent "$SORTIE" "JAMAIS_ATTEINT" "le script ne poursuit pas après l'échec"

# Le nom est réduit par basename : un chemin absolu dans le message trahirait
# une régression de forme. Contrôlé sur ce cas-ci, le seul dont le message
# désigne un fichier situé ailleurs que dans le répertoire de l'extrait.
assert_absent "$ERREUR" "de $DEPOT/lib/common.sh" \
    "le message porte le nom du fichier fautif, pas son chemin complet"

# Sens 2 : la faute vient du script appelant. Le message doit alors le nommer,
# lui, et non le socle.
executer "$(cat <<'FIN'
false
printf 'JAMAIS_ATTEINT\n'
FIN
)"
assert_code_non_nul "$CODE" "un échec survenu dans le script appelant l'interrompt"
assert_contient "$ERREUR" "de extrait.sh." \
    "le trap ERR nomme le script appelant quand la faute vient de lui"
assert_absent "$ERREUR" "de common.sh." \
    "le trap ERR n'impute pas au socle une faute du script appelant"
assert_contient "$ERREUR" "[ERROR] Échec (code 1) à la ligne " \
    "le message conserve son code et son numéro de ligne"
assert_absent "$SORTIE" "JAMAIS_ATTEINT" "le script ne poursuit pas après l'échec"

# ===================================================================
# Bilan
# ===================================================================
bilan "$ETIQUETTE"
