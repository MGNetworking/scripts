#!/usr/bin/env bash
# tests/integration/configure-cron.test.sh — Linux/System/configure-cron.sh, exécuté.
#
# Les dix critères d'acceptation de TASK-009, éprouvés par l'exécution réelle et
# non par la lecture du code :
#
#    1. le fichier porte SHELL, PATH et une entrée par tâche      groupe « contenu »
#    2. l'entrée porte « root » après l'horaire, pas de sudo      groupe « contenu »
#    3. le script planifié est invoqué avec --yes                 groupe « contenu »
#    4. stdout vers /dev/null, stderr CONSERVÉE                   groupe « contenu »
#    5. --dry-run affiche le fichier sans rien modifier           groupe « dry-run »
#    6. une seconde exécution ne modifie rien — par empreinte     groupe « idempotence »
#    7. refus sans privilège root                                 groupe « préflight »
#    8. horaire configurable par server.env puis par --horaire    groupe « précédence »
#    9. le chemin de déploiement est détecté, non écrit en dur    groupe « précédence »
#   10. --help documente le tout                                  groupe « préflight »
#
# Cinq exigences s'y ajoutent, parce qu'elles sont la raison d'être du script et
# qu'aucune ne se voit à l'oeil nu :
#
#   +. le nom déposé ne comporte PAS de point — cron ignorerait le fichier en
#      silence, sans le moindre message ;
#   +. le fichier est root:root 0644 et non exécutable — cron rejette les deux
#      autres cas, là encore sans rien dire ;
#   +. la commande passe par « /bin/bash <chemin> » et non par le chemin seul.
#      Les fichiers du dépôt sont enregistrés dans Git en 100644 : sur un
#      serveur issu d'un « git clone », un appel direct rendrait 126 à chaque
#      passage, sans rien écrire que cron puisse expédier. L'interpréteur est
#      donc éprouvé comme un champ à part entière de la ligne ;
#   +. la garde de dépendance porte sur le DÉMON et non sur /etc/cron.d, lequel
#      vient d'e2fsprogs et existe même sans cron. Son contrat est
#      dissymétrique : --dry-run avertit et produit l'aperçu (code 0), une
#      exécution réelle s'arrête sur « Prérequis manquant. » (code 1) ;
#   +. la ligne ne comporte PAS « 2>&1 ». C'est la contrainte la plus fragile de
#      tout le dispositif : elle ne casse rien quand on l'enfreint, elle rend
#      seulement muets les échecs de la tâche planifiée. Tant que le point en
#      suspens n° 2 n'est pas traité, la sortie d'erreur transmise par cron est
#      la SEULE alerte disponible. Une retouche bien intentionnée du fichier
#      déposé la supprimerait sans que rien ne s'en aperçoive : d'où une
#      assertion dédiée, portant sur l'absence d'un motif.
#
# CE FICHIER MODIFIE LE SYSTÈME. Il dépose /etc/cron.d/mgnetworking, installe le
# paquet « cron », pose un instant un faux /usr/sbin/cron et déplace un instant
# /etc/cron.d. Chacun est retiré et son retrait vérifié. Il n'écrit rien tant qu'il
# n'a pas reconnu un système jetable (conteneur Docker, ou MGNET_TEST_JETABLE=1) :
# ailleurs, les groupes modifiants se déclarent NON EXÉCUTÉS.
#
#   tests/env/run-in-container.sh -- tests/run.sh integration
#
# ---------------------------------------------------------------------------
# Comment l'idempotence est prouvée ici
# ---------------------------------------------------------------------------
#
#   empreinte P0 -> exécution 1 -> empreinte A -> exécution 2 -> empreinte B
#
# Le protocole est celui de linux-system.test.sh, garde comprise. « A == B » ne
# suffit pas : sur un système où le fichier serait déjà conforme, les deux
# exécutions ne feraient rien, les trois empreintes seraient égales et le test
# passerait sans rien prouver. Chaque cas exige donc AUSSI « P0 != A ».
#
# Ce fichier partage son conteneur avec linux-system.test.sh — docker n'est pas
# disponible à l'intérieur pour en créer d'autres. Trois dispositions le
# rendent sûr, et elles sont vérifiées et non supposées :
#
#   - les groupes non modifiants passent en premier (préflight, horaires
#     refusés, dry-run, précédence) ; le groupe « idempotence » vient après ;
#   - l'empreinte relevée à l'ouverture du groupe « dry-run » est comparée à
#     celle relevée juste avant le groupe « idempotence », déduction faite des
#     mutations volontaires et annoncées (installation du paquet cron). Le
#     fichier /etc/cron.d/mgnetworking est en outre vérifié ABSENT avant P0 :
#     sans cela le premier passage n'aurait rien à écrire et « P0 != A »
#     tomberait pour la mauvaise raison ;
#   - le fichier visé, /etc/cron.d/mgnetworking, n'est touché par aucun autre
#     fichier de cas du niveau. Il est restauré ou supprimé en fin de parcours,
#     et son absence est vérifiée.
#
# ---------------------------------------------------------------------------
# Ce que le conteneur ne permet pas, et qui est déclaré NON EXÉCUTÉ
# ---------------------------------------------------------------------------
#
#   - cron exécutant réellement la tâche à l'heure dite : le profil « debian »
#     n'a pas d'init, le démon n'est pas lancé ;
#   - le bit d'exécution réel de update-system.sh : le montage du dépôt par
#     Docker Desktop expose TOUS les fichiers en 0777. « test -x » y répond
#     toujours oui, quel que soit le mode réellement enregistré. La branche
#     d'avertissement est donc éprouvée sur une copie hors montage (groupe
#     « précédence »), la seule endroit où le mode est observable.

set -Eeuo pipefail

_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_dir/lib/common.sh" ] && [ "$_dir" != "/" ]; do _dir="$(dirname "$_dir")"; done
source "$_dir/lib/common.sh"
# shellcheck source=/dev/null
source "$SCRIPTS_ROOT/tests/lib/assert.sh"

CRON_SH="$SCRIPTS_ROOT/Linux/System/configure-cron.sh"
PLANIFIE="$SCRIPTS_ROOT/Linux/System/update-system.sh"

REPERTOIRE_CRON="/etc/cron.d"
FICHIER_CRON="$REPERTOIRE_CRON/mgnetworking"
HORAIRE_DEFAUT="0 4 * * 1"

REP_TMP="$(mktemp -d)"
F_OUT="$REP_TMP/stdout"
F_ERR="$REP_TMP/stderr"
CODE=0

BAC="/tmp/mgnet-test-bac-cron"
LOG_DIR_NOBODY="/tmp/mgnet-test-cron-nobody"

# Renseignées par les cas qui déplacent quelque chose, relues par le filet de
# sécurité posé sur EXIT. Un test interrompu ne doit pas laisser le système
# amputé de /etc/cron.d ni privé du fichier de l'administrateur.
CRON_D_DEPLACE=""
SAUVEGARDE_FICHIER=""

# Renseignée par le cas qui a besoin d'un démon cron sans vouloir installer le
# paquet. Un faux exécutable laissé derrière ferait croire à cron installé aux
# groupes suivants — d'où sa présence dans le filet.
FAUX_DEMON=""

filet_de_securite() {
    local code="$?"
    if [ -n "$CRON_D_DEPLACE" ] && [ -d "$CRON_D_DEPLACE" ] && [ ! -d "$REPERTOIRE_CRON" ]; then
        mv "$CRON_D_DEPLACE" "$REPERTOIRE_CRON"
    fi
    if [ -n "$SAUVEGARDE_FICHIER" ] && [ -f "$SAUVEGARDE_FICHIER" ] && [ -d "$REPERTOIRE_CRON" ]; then
        cp "$SAUVEGARDE_FICHIER" "$FICHIER_CRON"
    fi
    if [ -n "$FAUX_DEMON" ] && [ -f "$FAUX_DEMON" ]; then
        rm -f "$FAUX_DEMON"
    fi
    rm -rf "$REP_TMP" "$BAC" "$LOG_DIR_NOBODY"
    return "$code"
}
trap filet_de_securite EXIT

# ===================================================================
# Outillage
# ===================================================================

# lancer <commande...> — exécute dans un SOUS-SHELL et capture le code.
#
# Le sous-shell est indispensable : le script pose « set -Eeuo pipefail » et
# lib/common.sh un « trap ERR ». Un « die … 2 » tuerait le harnais s'il n'était
# pas isolé. L'entrée standard est fermée : confirm() lit alors une réponse vide
# et refuse, ce qui rend observable le chemin « sans -y ».
lancer() {
    CODE=0
    ( "$@" ) >"$F_OUT" 2>"$F_ERR" </dev/null || CODE=$?
}

# lancer_entree <réponse> <commande...> — idem, avec une réponse au clavier.
# C'est le seul moyen d'atteindre la branche « l'opérateur confirme ».
lancer_entree() {
    local reponse="$1"; shift
    CODE=0
    ( "$@" ) >"$F_OUT" 2>"$F_ERR" <<< "$reponse" || CODE=$?
}

sortie() { cat "$F_OUT"; }
erreur() { cat "$F_ERR"; }

# empreinte <destination> — état de tout ce que ce script peut toucher.
#
# TOUT /etc est relevé, contenu compris, et non une liste arrêtée d'avance :
# c'est ce qui permet de voir une écriture qu'on n'attendait pas — un fichier
# temporaire oublié dans /etc/cron.d, par exemple. Le répertoire des crontabs
# utilisateur y est joint : c'est l'autre endroit qu'une planification pourrait
# atteindre.
#
# LOG_DIR est hors de l'empreinte : lib/common.sh y écrit dès le « source »,
# avant même que le script n'ait lu ses arguments. L'y inclure rendrait toute
# empreinte différente de la précédente et aucun --dry-run ne pourrait jamais
# être déclaré inoffensif. Les écritures hors journaux sont surveillées à part,
# par ecritures_depuis().
empreinte() {
    local destination="$1"
    local code=0

    {
        find /etc -type f -exec cksum {} + 2>/dev/null | sort
        find /etc -type l -printf 'lien %p -> %l\n' 2>/dev/null | sort
        find /etc -type d -printf 'rep %p\n' 2>/dev/null | sort
        if [ -d /var/spool/cron ]; then
            find /var/spool/cron -type f -exec cksum {} + 2>/dev/null | sort
        else
            printf 'spool cron absent\n'
        fi
    } > "$destination" || code=$?

    # find rend 1 dès qu'un fichier disparaît entre le parcours et le cksum. Un
    # relevé incomplet fausserait les comparaisons : il doit se voir.
    if [ "$code" -ne 0 ]; then
        warn "Relevé d'empreinte incomplet (code $code) : $destination"
    fi
}

# ecritures_depuis <témoin> <destination> — fichiers modifiés depuis le témoin.
#
# La référence est un fichier et non une date : « find -newer » compare à la
# précision du système de fichiers, là où « -newermt @secondes » arrondirait et
# ferait remonter tout ce que le conteneur a écrit dans la même seconde.
#
# /var/log est exclu — c'est le domicile des journaux, dont l'écriture n'est pas
# une modification du système au sens de --dry-run.
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

# assert_fichier_absent <chemin> <libellé>
assert_fichier_absent() {
    local chemin="$1" libelle="$2"
    if [ -e "$chemin" ]; then
        ko "$libelle" "$chemin existe"
    else
        ok "$libelle"
    fi
}

# lignes_de_tache <fichier> — les lignes utiles du fichier de cron.
#
# Tout ce qui n'est ni vide, ni un commentaire, ni une affectation de variable
# d'environnement. Écrit sans grep pour ne pas dépendre du code de retour d'un
# tube sous « pipefail » : une absence de correspondance est ici une donnée, pas
# une erreur.
lignes_de_tache() {
    local fichier="$1"
    local ligne
    while IFS= read -r ligne; do
        case "$ligne" in
            ''|'#'*)      continue ;;
            [A-Z]*=*)     continue ;;
        esac
        printf '%s\n' "$ligne"
    done < "$fichier"
}

# demon_cron_present — vrai si le script trouverait un démon cron.
#
# La recherche reproduit exactement celle de chemin_demon_cron() : le PATH
# d'abord, puis /usr/sbin, qui n'y figure pas toujours. Ne PAS se contenter de
# « command -v cron » : le test conclurait à l'absence là où le script conclut
# à la présence, et la branche mesurée ne serait pas celle qu'on croit.
#
# La dépendance se mesure sur le démon, jamais sur /etc/cron.d : ce répertoire
# vient d'e2fsprogs et existe sur une machine où cron n'est pas installé.
demon_cron_present() {
    local candidat
    for candidat in cron crond; do
        command -v "$candidat" >/dev/null 2>&1 && return 0
    done
    for candidat in /usr/sbin/cron /usr/sbin/crond; do
        [ -x "$candidat" ] && return 0
    done
    return 1
}

# ===================================================================
# 0. Reconnaissance de l'environnement
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

# Lanceur non privilégié. Deux candidats éprouvés dans l'ordre : le premier qui
# abaisse RÉELLEMENT l'UID est retenu. Sans lui, les cas de privilège sont
# déclarés NON EXÉCUTÉS — jamais réussis.
LANCEUR_SANS_ROOT=()

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

# LOG_DIR part dans /tmp : sans cela lib/common.sh tenterait d'écrire son
# journal dans le dépôt monté, qui n'appartient pas à « nobody ».
sans_root() {
    lancer env "LOG_DIR=$LOG_DIR_NOBODY" "${LANCEUR_SANS_ROOT[@]}" "$@"
}

if [ "$EST_LINUX" != "true" ]; then
    saute "l'ensemble des cas de configure-cron.sh" \
        "cet hôte n'est pas un Linux — ce script n'y démarre pas"
    bilan "TASK-009 / configure-cron.sh"
    exit 0
fi

if [ ! -f "$CRON_SH" ]; then
    saute "l'ensemble des cas de configure-cron.sh" "$CRON_SH est introuvable"
    bilan "TASK-009 / configure-cron.sh"
    exit 0
fi

# Les groupes modifiants exigent les trois conditions à la fois. La raison est
# calculée une fois, réutilisée à chaque « saute » : un NON EXÉCUTÉ sans motif
# ne renseigne personne.
MODIFIANT="oui"
if [ "$EST_ROOT" != "true" ]; then
    MODIFIANT="require_root arrête le script avant toute écriture"
elif [ "$JETABLE" != "true" ]; then
    MODIFIANT="cet hôte n'est pas un système jetable — /etc/cron.d ne sera pas touché"
elif [ "$EST_DEBIAN" != "true" ]; then
    MODIFIANT="l'hôte n'est ni Debian ni Ubuntu — require_os refuse le script"
fi

# L'horaire par défaut n'est celui qui sera déposé que si aucun config/server.env
# de la machine n'impose SRV_CRON_UPDATE_SYSTEM. Ce fichier n'est pas versionné :
# il peut exister sur la machine de développement, dont le dépôt est monté dans
# le conteneur. Les seules assertions concernées sont celles qui citent
# l'horaire attendu — elles sont déclarées NON EXÉCUTÉES plutôt que d'échouer
# pour une raison qui ne regarde pas le script.
SERVER_ENV="$SCRIPTS_ROOT/config/server.env"
HORAIRE_MAITRISE="oui"
if [ -f "$SERVER_ENV" ] && grep -qE '^[[:space:]]*(export[[:space:]]+)?SRV_CRON_UPDATE_SYSTEM=' "$SERVER_ENV"; then
    HORAIRE_MAITRISE="config/server.env de cette machine impose SRV_CRON_UPDATE_SYSTEM — l'horaire déposé n'est pas la valeur par défaut"
    warn "$HORAIRE_MAITRISE"
fi

# Le fichier de l'administrateur, s'il y en a un, est mis de côté et remis en
# place au nettoyage. Ce fichier de cas ne détruit pas une planification en
# service, fût-ce sur un système déclaré jetable.
if [ "$MODIFIANT" = "oui" ] && [ -f "$FICHIER_CRON" ]; then
    SAUVEGARDE_FICHIER="$REP_TMP/mgnetworking.origine"
    cp "$FICHIER_CRON" "$SAUVEGARDE_FICHIER"
    rm -f "$FICHIER_CRON"
    info "Un $FICHIER_CRON préexistant a été mis de côté ; il sera remis en fin de parcours."
fi

# ===================================================================
# 1. Préflight — aide, options, privilèges, OS
# ===================================================================
# Aucun cas de ce groupe n'écrit quoi que ce soit : ils s'exécutent quel que
# soit l'environnement, root ou non.
titre "1. Préflight"

lancer bash "$CRON_SH" --help
assert_code 0 "$CODE" "--help sort en 0"
aide="$(sortie)"
assert_contient "$aide" "Usage :" "--help écrit son usage sur stdout"
assert_contient "$aide" "--horaire" "--help documente --horaire"
assert_contient "$aide" "--dry-run" "--help documente --dry-run"
assert_contient "$aide" "SRV_CRON_UPDATE_SYSTEM" "--help nomme la variable de configuration"
assert_contient "$aide" "$FICHIER_CRON" "--help nomme le fichier déposé"
assert_contient "$aide" "--yes" "--help explique l'appel avec --yes"
assert_contient "$aide" "sortie d'erreur est CONSERVÉE" "--help dit que la sortie d'erreur est conservée"
assert_contient "$aide" "/bin/bash <chemin>" \
    "--help annonce que le script planifié est invoqué par bash"
assert_contient "$aide" "démon cron est signalée sans arrêter le script" \
    "--help dit que seul --dry-run tolère l'absence du démon cron"

lancer bash "$CRON_SH" -h
assert_code 0 "$CODE" "-h sort en 0"

lancer bash "$CRON_SH" --option-qui-n-existe-pas
assert_code 2 "$CODE" "une option inconnue est refusée"
assert_contient "$(erreur)" "Option inconnue" "l'option inconnue est nommée"

lancer bash "$CRON_SH" --horaire
assert_code 2 "$CODE" "--horaire sans valeur est refusé"
assert_contient "$(erreur)" "cinq champs" "--horaire sans valeur rappelle le format attendu"

if [ "$SANS_ROOT_DISPONIBLE" != "true" ]; then
    saute "le refus de s'exécuter sans privilège" \
        "aucun lanceur ne parvient à abaisser l'UID sur cet hôte"
    saute "le refus de --dry-run sans privilège" \
        "aucun lanceur ne parvient à abaisser l'UID sur cet hôte"
    saute "la primauté de l'erreur d'usage sur le manque de privilège" \
        "aucun lanceur ne parvient à abaisser l'UID sur cet hôte"
else
    # require_root sort en 1 : dans ce dépôt le code 2 est réservé à l'erreur
    # d'usage.
    sans_root bash "$CRON_SH"
    assert_code 1 "$CODE" "le script refuse de s'exécuter sans privilège"
    assert_contient "$(erreur)" "doit être exécuté en root" "le script dit pourquoi il refuse"

    # --dry-run n'ouvre pas une porte dérobée : il reste derrière require_root.
    sans_root bash "$CRON_SH" --dry-run
    assert_code 1 "$CODE" "--dry-run refuse lui aussi de s'exécuter sans privilège"

    # L'erreur d'usage prime : sinon un appel mal formé serait masqué par un
    # message de permission, et l'opérateur corrigerait la mauvaise chose.
    sans_root bash "$CRON_SH" --option-qui-n-existe-pas
    assert_code 2 "$CODE" "l'option inconnue prime sur le manque de privilège"

    sans_root bash "$CRON_SH" --horaire "@weekly"
    assert_code 2 "$CODE" "l'horaire invalide prime sur le manque de privilège"

    rm -rf "$LOG_DIR_NOBODY"
fi

# --- Refus d'un OS non supporté --------------------------------------------
# /etc/os-release est un fichier ordinaire de l'image : le remplacer le temps
# d'un appel est le seul moyen d'éprouver ce refus sans une seconde image. Il
# est remis en place immédiatement, et l'assertion suivante le vérifie.
if [ "$MODIFIANT" != "oui" ]; then
    saute "le refus d'un OS non supporté" "$MODIFIANT"
else
    cp /etc/os-release "$REP_TMP/os-release.origine"
    printf 'ID=fedora\nVERSION_ID="41"\nPRETTY_NAME="Fedora (simulée par le test)"\n' > /etc/os-release
    lancer bash "$CRON_SH" --dry-run
    cat "$REP_TMP/os-release.origine" > /etc/os-release

    assert_code 1 "$CODE" "le script refuse un OS non supporté"
    assert_contient "$(erreur)" "Distribution non supportée" "le script nomme la distribution refusée"
    assert_fichier_absent "$FICHIER_CRON" "aucun fichier n'est déposé sur un OS non supporté"

    if cmp -s /etc/os-release "$REP_TMP/os-release.origine"; then
        ok "/etc/os-release a été remis dans son état d'origine"
    else
        ko "/etc/os-release a été remis dans son état d'origine" "le fichier diffère de la sauvegarde"
    fi
fi

# ===================================================================
# 2. Horaires refusés
# ===================================================================
# Cinq formes fautives, dont une tentative d'injection. Le contrat est double :
# code 2, et AUCUN fichier déposé. Un refus qui laisserait derrière lui un
# fichier à demi écrit serait pire qu'une acceptation.
titre "2. Horaires refusés"

if [ "$MODIFIANT" != "oui" ]; then
    saute "le refus des horaires mal formés" "$MODIFIANT"
else
    horaire_refuse() {
        local horaire="$1" motif="$2" libelle="$3"

        lancer bash "$CRON_SH" --horaire "$horaire" -y
        assert_code 2 "$CODE" "$libelle"
        assert_contient "$(erreur)" "$motif" "$libelle : le motif du refus est nommé"
        assert_contient "$(erreur)" "Aucune modification effectuée" \
            "$libelle : le script annonce n'avoir rien modifié"
        assert_fichier_absent "$FICHIER_CRON" "$libelle : aucun fichier n'est déposé"
    }

    horaire_refuse "@weekly" "Raccourci non accepté" \
        "« @weekly » est refusé"
    horaire_refuse "0 4 * *" "4 champ(s) au lieu de 5" \
        "un horaire à quatre champs est refusé"
    horaire_refuse "0 4 * * 1 2" "6 champ(s) au lieu de 5" \
        "un horaire à six champs est refusé"

    # Injection : « ; rm » terminerait la commande de cron et en lancerait une
    # seconde. Le refus doit porter sur la FORME du champ, avant toute écriture.
    horaire_refuse "0 4 * * lundi;rm" "Champ d'horaire invalide" \
        "une tentative d'injection par « ; » est refusée"

    # Le pourcent est proscrit partout dans une crontab : cron le remplace par
    # un retour à la ligne et coupe la commande en deux.
    horaire_refuse "0 4 * * 1%rm" "Champ d'horaire invalide" \
        "un champ contenant « % » est refusé"

    lancer bash "$CRON_SH" --horaire "   " -y
    assert_code 2 "$CODE" "un horaire vide de tout champ est refusé"
    assert_fichier_absent "$FICHIER_CRON" "un horaire vide ne dépose aucun fichier"
fi

# ===================================================================
# 3. --dry-run — critère 5
# ===================================================================
# Une empreinte avant, une après, et la liste des fichiers écrits entre les
# deux. L'empreinte seule ne verrait pas un fichier créé hors de /etc ; la liste
# seule ne verrait pas une réécriture à l'identique de la même taille. Les deux
# ensemble ne laissent pas de trou.
titre "3. --dry-run"

# La ligne attendue invoque « /bin/bash <chemin> » et non le chemin seul. Ce
# n'est pas un détail de forme : les fichiers du dépôt sont enregistrés dans Git
# en 100644, et un appel direct rendrait 126 à chaque passage sur un serveur
# issu d'un « git clone ». L'interpréteur est donc un champ à part entière de la
# ligne, éprouvé comme tel au groupe 6.
INTERPRETEUR_ATTENDU="/bin/bash"
LIGNE_ATTENDUE="$HORAIRE_DEFAUT root $INTERPRETEUR_ATTENDU $PLANIFIE --yes >/dev/null"

if [ "$MODIFIANT" != "oui" ]; then
    saute "--dry-run n'écrit rien" "$MODIFIANT"
    saute "--dry-run affiche le fichier complet" "$MODIFIANT"
    saute "--dry-run sans démon cron" "$MODIFIANT"
    saute "le refus d'écrire sans démon cron" "$MODIFIANT"
    saute "le refus d'écrire quand /etc/cron.d est absent" "$MODIFIANT"
else
    empreinte "$REP_TMP/dry-avant"
    touch "$REP_TMP/temoin-dry"

    lancer bash "$CRON_SH" --dry-run
    assert_code 0 "$CODE" "--dry-run sort en 0"

    apercu="$(erreur)"
    assert_contient "$apercu" "[dry-run] Créerait $FICHIER_CRON" \
        "--dry-run annonce le fichier qu'il créerait"
    assert_contient "$apercu" "SHELL=/bin/bash" "--dry-run affiche la ligne SHELL"
    assert_contient "$apercu" "PATH=/usr/local/sbin" "--dry-run affiche la ligne PATH"
    if [ "$HORAIRE_MAITRISE" = "oui" ]; then
        assert_contient "$apercu" "$LIGNE_ATTENDUE" "--dry-run affiche la ligne de tâche complète"
    else
        saute "--dry-run affiche la ligne de tâche complète" "$HORAIRE_MAITRISE"
        assert_contient "$apercu" "root $INTERPRETEUR_ATTENDU $PLANIFIE --yes >/dev/null" \
            "--dry-run affiche la ligne de tâche, horaire mis à part"
    fi
    assert_contient "$apercu" "aucune modification effectuée" \
        "--dry-run annonce qu'il n'a rien modifié"

    empreinte "$REP_TMP/dry-apres"
    assert_empreinte_egale "$REP_TMP/dry-avant" "$REP_TMP/dry-apres" \
        "--dry-run ne modifie aucun fichier"
    assert_aucune_ecriture "$REP_TMP/temoin-dry" \
        "--dry-run n'écrit rien hors du répertoire de journaux"
    assert_fichier_absent "$FICHIER_CRON" "--dry-run ne dépose pas $FICHIER_CRON"

    # --- Démon cron absent : --dry-run tolère, l'exécution réelle refuse ----
    # Le paquet cron n'est pas encore installé à ce stade, et c'est voulu : la
    # garde de dépendance porte sur le DÉMON, et cette branche-là n'est
    # atteignable qu'ici. Le contrat est dissymétrique et les deux moitiés se
    # mesurent séparément :
    #   --dry-run  → trois avertissements, aperçu produit, code 0 ;
    #   sans lui   → « Prérequis manquant. », code 1, rien de déposé. Déposer
    #                un fichier que rien ne lira donnerait une planification
    #                imaginaire.
    if demon_cron_present; then
        saute "--dry-run sans démon cron" \
            "un démon cron est déjà présent sur cet hôte — la branche n'est pas atteignable"
        saute "le refus d'écrire sans démon cron" \
            "un démon cron est déjà présent sur cet hôte — la branche n'est pas atteignable"
    else
        assert_contient "$apercu" "Aucun démon cron trouvé" \
            "--dry-run signale l'absence de démon cron sans s'arrêter"
        assert_contient "$apercu" "apt-get install cron" \
            "--dry-run donne la commande qui installe le démon manquant"
        assert_contient "$apercu" "l'aperçu est produit malgré tout, rien ne sera écrit" \
            "--dry-run annonce qu'il produit l'aperçu malgré l'absence du démon"
        ok "--dry-run reste utilisable alors que le paquet cron n'est pas installé"

        lancer bash "$CRON_SH" -y
        assert_code 1 "$CODE" "l'exécution réelle refuse d'écrire sans démon cron"
        assert_contient "$(erreur)" "Aucun démon cron trouvé" \
            "l'exécution réelle nomme la dépendance manquante"
        assert_contient "$(erreur)" "Prérequis manquant" \
            "l'exécution réelle annonce le prérequis manquant"
        assert_fichier_absent "$FICHIER_CRON" \
            "aucun fichier n'est déposé quand le démon cron manque"
    fi

    # --- /etc/cron.d absent, démon présent : installation incomplète --------
    # Le contrôle du répertoire vient APRÈS celui du démon. Sans démon en place,
    # c'est la garde de dépendance qui parlerait et ce cas mesurerait autre
    # chose que ce qu'annonce son libellé. Un faux /usr/sbin/cron exécutable
    # suffit à chemin_demon_cron() : il n'a pas à démarrer, seulement à exister.
    # Il est retiré juste après, et son absence est vérifiée — le laisser ferait
    # croire au groupe 5 que le paquet cron est installé.
    if ! demon_cron_present; then
        FAUX_DEMON="/usr/sbin/cron"
        printf '#!/bin/sh\n# faux démon posé par le test — voir configure-cron.test.sh\nexit 0\n' \
            > "$FAUX_DEMON"
        chmod 0755 "$FAUX_DEMON"
    fi

    if ! demon_cron_present; then
        saute "le refus d'écrire quand /etc/cron.d est absent" \
            "aucun démon cron n'a pu être mis en place : la garde de dépendance parlerait avant celle du répertoire"
    else
        # Le répertoire est déplacé le temps de deux appels, puis remis. La
        # restauration porte sa propre assertion : sans elle, un échec ici
        # laisserait le système amputé sans que rien ne le dise.
        CRON_D_DEPLACE="$REP_TMP/cron.d.deplace"
        mv "$REPERTOIRE_CRON" "$CRON_D_DEPLACE"

        lancer bash "$CRON_SH" --dry-run
        assert_code 0 "$CODE" "--dry-run sort en 0 même si /etc/cron.d est absent"
        assert_contient "$(erreur)" "[dry-run] Créerait $FICHIER_CRON" \
            "--dry-run produit son aperçu même si /etc/cron.d est absent"

        lancer bash "$CRON_SH" -y
        assert_code 1 "$CODE" "l'exécution réelle refuse d'écrire si /etc/cron.d est absent"
        assert_contient "$(erreur)" "installation de cron incomplète" \
            "l'exécution réelle nomme le répertoire manquant"

        mv "$CRON_D_DEPLACE" "$REPERTOIRE_CRON"
        CRON_D_DEPLACE=""
        if [ -d "$REPERTOIRE_CRON" ]; then
            ok "$REPERTOIRE_CRON a été remis en place"
        else
            ko "$REPERTOIRE_CRON a été remis en place" "le répertoire est toujours absent"
        fi
    fi

    if [ -n "$FAUX_DEMON" ]; then
        chemin_faux_demon="$FAUX_DEMON"
        rm -f "$FAUX_DEMON"
        FAUX_DEMON=""
        assert_fichier_absent "$chemin_faux_demon" \
            "le faux démon cron posé par le test est retiré"
    fi
fi

# ===================================================================
# 4. Précédence de l'horaire, et chemin de déploiement — critères 8 et 9
# ===================================================================
# Deux preuves en une : le bac à sable est un dépôt COMPLET recopié hors du
# montage, avec son propre config/server.env. Il permet à la fois d'éprouver le
# chargement du fichier de configuration — sans jamais écrire dans le config/ du
# dépôt monté, qui est celui de la machine de développement — et de vérifier que
# le chemin inscrit dans la ligne de cron suit le dépôt au lieu d'être écrit en
# dur.
titre "4. Précédence de l'horaire et chemin de déploiement"

if [ "$MODIFIANT" != "oui" ]; then
    saute "la précédence de l'horaire" "$MODIFIANT"
    saute "la détection du chemin de déploiement" "$MODIFIANT"
    saute "l'avertissement sur un script planifié non exécutable" "$MODIFIANT"
else
    # --- Par l'environnement, puis par la ligne de commande -----------------
    # SRV_CRON_UPDATE_SYSTEM est ici passée par l'environnement : c'est la même
    # variable que celle de config/server.env, et cette forme évite d'écrire
    # dans le config/ du dépôt monté, qui est celui de la machine de
    # développement. Le chargement depuis le FICHIER est éprouvé plus bas, dans
    # le bac à sable.
    if [ "$HORAIRE_MAITRISE" != "oui" ]; then
        saute "SRV_CRON_UPDATE_SYSTEM fixe l'horaire de la ligne déposée" "$HORAIRE_MAITRISE"
    else
        lancer env SRV_CRON_UPDATE_SYSTEM="15 3 * * 6" bash "$CRON_SH" --dry-run
        assert_code 0 "$CODE" "un horaire venu de la configuration est accepté"
        assert_contient "$(erreur)" "15 3 * * 6 root $INTERPRETEUR_ATTENDU $PLANIFIE --yes >/dev/null" \
            "SRV_CRON_UPDATE_SYSTEM fixe l'horaire de la ligne déposée"
        assert_contient "$(erreur)" "(config/server.env)" \
            "le script annonce l'origine « config/server.env » de l'horaire"
    fi

    lancer env SRV_CRON_UPDATE_SYSTEM="15 3 * * 6" bash "$CRON_SH" --horaire "45 2 * * 3" --dry-run
    assert_code 0 "$CODE" "--horaire par-dessus la configuration est accepté"
    assert_contient "$(erreur)" "45 2 * * 3 root $INTERPRETEUR_ATTENDU $PLANIFIE --yes >/dev/null" \
        "--horaire prime sur SRV_CRON_UPDATE_SYSTEM"
    assert_absent "$(erreur)" "15 3 * * 6" \
        "l'horaire de la configuration ne subsiste nulle part dans le fichier"
    assert_contient "$(erreur)" "(argument)" \
        "le script annonce que l'horaire vient de la ligne de commande"

    # --- Bac à sable : un dépôt ailleurs, avec son config/server.env --------
    rm -rf "$BAC"
    mkdir -p "$BAC/lib" "$BAC/config" "$BAC/Linux/System"
    cp "$SCRIPTS_ROOT/lib/common.sh" "$BAC/lib/common.sh"
    cp "$CRON_SH" "$BAC/Linux/System/configure-cron.sh"
    cp "$PLANIFIE" "$BAC/Linux/System/update-system.sh"
    printf 'SRV_CRON_UPDATE_SYSTEM="7 2 * * 5"\n' > "$BAC/config/server.env"

    # Le bit d'exécution est délibérément retiré. Le montage du dépôt expose
    # tout en 0777 : cette copie est le seul endroit où le mode est réellement
    # observable, et donc où la branche d'avertissement est atteignable.
    chmod 0644 "$BAC/Linux/System/update-system.sh"

    if cmp -s "$SCRIPTS_ROOT/lib/common.sh" "$BAC/lib/common.sh"; then
        ok "le bac à sable porte une copie fidèle de lib/common.sh"
    else
        ko "le bac à sable porte une copie fidèle de lib/common.sh" "les deux fichiers diffèrent"
    fi

    lancer bash "$BAC/Linux/System/configure-cron.sh" --dry-run
    assert_code 0 "$CODE" "le script lancé depuis un autre dépôt sort en 0"
    apercu_bac="$(erreur)"
    assert_contient "$apercu_bac" "7 2 * * 5 root $INTERPRETEUR_ATTENDU $BAC/Linux/System/update-system.sh --yes >/dev/null" \
        "config/server.env fixe l'horaire et le chemin suit le dépôt réel"
    assert_absent "$apercu_bac" "$SCRIPTS_ROOT/Linux/System/update-system.sh" \
        "aucun chemin du dépôt d'origine ne subsiste dans la ligne produite"
    assert_absent "$apercu_bac" "/opt/mgnetworking" \
        "le chemin d'exemple du README n'est pas écrit en dur"

    # Le bit d'exécution manquant : avertissement, pas arrêt. Le choix du
    # rédacteur est mesuré ici, non commenté.
    assert_contient "$apercu_bac" "n'est pas exécutable" \
        "le script avertit quand le script planifié n'est pas exécutable"
    assert_contient "$apercu_bac" "chmod +x" \
        "le script donne le correctif de l'avertissement"

    chmod 0755 "$BAC/Linux/System/update-system.sh"
    lancer bash "$BAC/Linux/System/configure-cron.sh" --dry-run
    assert_code 0 "$CODE" "le script sort en 0 une fois le bit d'exécution posé"
    assert_absent "$(erreur)" "n'est pas exécutable" \
        "l'avertissement disparaît une fois le bit d'exécution posé"

    # Script planifié introuvable : celui-là est bien un arrêt.
    rm -f "$BAC/Linux/System/update-system.sh"
    lancer bash "$BAC/Linux/System/configure-cron.sh" --dry-run
    assert_code 1 "$CODE" "le script s'arrête si le script à planifier est introuvable"
    assert_contient "$(erreur)" "Script à planifier introuvable" \
        "le script nomme le script à planifier introuvable"

    rm -rf "$BAC"
    assert_fichier_absent "$BAC" "le bac à sable est supprimé"
fi

# ===================================================================
# 5. Idempotence — critère 6
# ===================================================================
titre "5. Idempotence — deux exécutions de suite"

# Le paquet cron est installé ICI, entre les groupes non modifiants et le
# groupe d'idempotence : sa mutation de /etc est ainsi antérieure à P0 et ne
# vient polluer aucune comparaison. Le groupe « dry-run » avait au contraire
# besoin de son absence.
CRON_INSTALLE="false"
if [ "$MODIFIANT" = "oui" ]; then
    if command -v cron >/dev/null 2>&1 || command -v crond >/dev/null 2>&1; then
        CRON_INSTALLE="true"
    else
        info "Paquet cron absent : tentative d'installation…"
        if apt-get update -qq >/dev/null 2>&1 && apt-get install -y -qq cron >/dev/null 2>&1; then
            CRON_INSTALLE="true"
            info "Paquet cron installé."
        else
            warn "L'installation du paquet cron a échoué."
        fi
    fi
fi

IDEMPOTENCE="$MODIFIANT"
if [ "$IDEMPOTENCE" = "oui" ] && [ "$CRON_INSTALLE" != "true" ]; then
    IDEMPOTENCE="le paquet cron n'a pas pu être installé — la planification n'a pas de destinataire"
fi

# La preuve « P0 != A » n'a de sens que si le fichier est absent au départ :
# sinon le premier passage n'aurait rien à écrire, et la garde tomberait pour
# une raison qui n'est pas celle qu'elle surveille.
if [ "$IDEMPOTENCE" = "oui" ] && [ -e "$FICHIER_CRON" ]; then
    IDEMPOTENCE="$FICHIER_CRON existe déjà au départ — une idempotence mesurée depuis cet état ne prouverait rien"
fi

if [ "$IDEMPOTENCE" != "oui" ]; then
    saute "les deux exécutions successives" "$IDEMPOTENCE"
    saute "la garde « la première exécution modifie réellement le système »" "$IDEMPOTENCE"
    saute "l'annonce « déjà en place et à jour » au second passage" "$IDEMPOTENCE"
else
    empreinte "$REP_TMP/idem-p0"

    lancer bash "$CRON_SH" -y
    assert_code 0 "$CODE" "première exécution : sort en 0"
    premiere="$(erreur)"
    assert_contient "$premiere" "Fichier écrit : $FICHIER_CRON" \
        "première exécution : le fichier est écrit"
    assert_contient "$premiere" "Planification installée" \
        "première exécution : la planification est annoncée installée"
    assert_contient "$premiere" "Démon cron" \
        "première exécution : le démon cron est localisé"

    empreinte "$REP_TMP/idem-a"
    assert_empreinte_differente "$REP_TMP/idem-p0" "$REP_TMP/idem-a" \
        "la première exécution modifie réellement le système"

    lancer bash "$CRON_SH" -y
    assert_code 0 "$CODE" "seconde exécution : sort en 0"
    seconde="$(erreur)"
    assert_contient "$seconde" "déjà en place et à jour" \
        "seconde exécution : le script annonce n'avoir rien à faire"
    assert_absent "$seconde" "Fichier écrit" \
        "seconde exécution : aucune réécriture n'est annoncée"

    empreinte "$REP_TMP/idem-b"
    assert_empreinte_egale "$REP_TMP/idem-a" "$REP_TMP/idem-b" \
        "la seconde exécution laisse le système identique"

    # Un horaire écrit avec des espaces multiples désigne la même chose : le
    # script le normalise, sans quoi deux formulations du même horaire
    # produiraient deux fichiers différents et l'idempotence serait perdue.
    if [ "$HORAIRE_MAITRISE" != "oui" ]; then
        saute "un horaire aux espaces multiples est reconnu comme identique" "$HORAIRE_MAITRISE"
        cp "$REP_TMP/idem-b" "$REP_TMP/idem-c"
    else
        lancer bash "$CRON_SH" --horaire "0   4  *  *  1" -y
        assert_code 0 "$CODE" "un horaire aux espaces multiples sort en 0"
        assert_contient "$(erreur)" "déjà en place et à jour" \
            "un horaire aux espaces multiples est reconnu comme identique"
        empreinte "$REP_TMP/idem-c"
        assert_empreinte_egale "$REP_TMP/idem-b" "$REP_TMP/idem-c" \
            "un horaire aux espaces multiples ne réécrit rien"
    fi

    # --dry-run sur un système déjà conforme : toujours 0, toujours rien.
    lancer bash "$CRON_SH" --dry-run
    assert_code 0 "$CODE" "--dry-run sur un système déjà conforme sort en 0"
    assert_contient "$(erreur)" "est déjà celui attendu" \
        "--dry-run reconnaît un fichier déjà conforme"
    empreinte "$REP_TMP/idem-d"
    assert_empreinte_egale "$REP_TMP/idem-c" "$REP_TMP/idem-d" \
        "--dry-run sur un système déjà conforme ne modifie rien"
fi

# ===================================================================
# 6. Le contenu déposé — critères 1 à 4
# ===================================================================
# Ce groupe lit le fichier réellement présent sur le disque. Il est le coeur du
# test : c'est ce fichier, et lui seul, que cron exécutera.
titre "6. Contenu du fichier déposé"

if [ ! -f "$FICHIER_CRON" ]; then
    saute "le contenu du fichier déposé" \
        "$FICHIER_CRON n'a pas été déposé — voir les groupes précédents"
    saute "l'absence de « 2>&1 » dans la ligne de tâche" \
        "$FICHIER_CRON n'a pas été déposé — voir les groupes précédents"
else
    contenu="$(cat "$FICHIER_CRON")"

    assert_contient "$contenu" "SHELL=/bin/bash" "le fichier porte SHELL=/bin/bash"
    assert_contient "$contenu" "PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin" \
        "le fichier porte la ligne PATH"

    lignes_de_tache "$FICHIER_CRON" > "$REP_TMP/taches"
    nb_taches="$(wc -l < "$REP_TMP/taches" | tr -d ' ')"
    assert_egal "1" "$nb_taches" "le fichier porte exactement une entrée de tâche"

    tache="$(cat "$REP_TMP/taches")"
    if [ "$HORAIRE_MAITRISE" = "oui" ]; then
        assert_egal "$LIGNE_ATTENDUE" "$tache" "l'entrée de tâche est exactement celle attendue"
    else
        saute "l'entrée de tâche est exactement celle attendue" "$HORAIRE_MAITRISE"
    fi

    # Décomposition champ par champ : l'égalité ci-dessus prouve tout d'un coup,
    # ces assertions-ci disent LEQUEL des contrats est rompu le jour où elle
    # tombe. Les cinq premiers champs sont ceux de l'horaire par défaut ; les
    # quatre suivants ne dépendent d'aucune configuration.
    #
    # L'interpréteur est un champ à part, entre l'utilisateur et le chemin :
    # la ligne appelle « /bin/bash <chemin> » et non le chemin seul. Le
    # dissocier du chemin permet de dire lequel des deux a changé le jour où
    # cette égalité tombe.
    read -r c1 c2 c3 c4 c5 utilisateur interpreteur commande reste <<< "$tache"
    if [ "$HORAIRE_MAITRISE" = "oui" ]; then
        assert_egal "0" "$c1" "champ 1 de l'horaire : minute"
        assert_egal "4" "$c2" "champ 2 de l'horaire : heure"
        assert_egal "*" "$c3" "champ 3 de l'horaire : jour du mois"
        assert_egal "*" "$c4" "champ 4 de l'horaire : mois"
        assert_egal "1" "$c5" "champ 5 de l'horaire : jour de la semaine"
    else
        saute "les cinq champs de l'horaire par défaut" "$HORAIRE_MAITRISE"
        assert_non_vide "$c5" "l'horaire compte bien cinq champs avant l'utilisateur"
    fi
    assert_egal "root" "$utilisateur" "l'utilisateur « root » suit les cinq champs de l'horaire"

    # Les fichiers du dépôt sont enregistrés dans Git en 100644. Sans cet
    # interpréteur, la tâche rendrait 126 à chaque passage sur un serveur issu
    # d'un « git clone » — en silence, puisque cron n'expédie que ce que le
    # travail écrit, et qu'un 126 n'écrit rien sur la sortie d'erreur du shell
    # de cron.
    assert_egal "$INTERPRETEUR_ATTENDU" "$interpreteur" \
        "le script est invoqué par bash et non par son chemin seul"
    assert_egal "$PLANIFIE" "$commande" "la commande est le chemin réel du script planifié"
    assert_egal "--yes >/dev/null" "$reste" "la commande porte --yes puis la redirection de stdout"

    # Critère 2 : le champ utilisateur remplace sudo. Un sudo dans une ligne de
    # /etc/cron.d serait au mieux inutile, au pire un contournement.
    # L'assertion porte sur la LIGNE DE TÂCHE et non sur tout le fichier : les
    # commentaires du fichier expliquent justement que cron n'utilise pas sudo,
    # et le mot y figure donc légitimement.
    assert_absent "$tache" "sudo" "la ligne de tâche n'appelle jamais sudo"

    # Critère 4, et la contrainte la plus fragile de tout le dispositif.
    # « 2>&1 » rendrait muets les échecs de la tâche planifiée : cron n'aurait
    # plus rien à transmettre, et le point en suspens n° 2 n'a pas encore
    # d'autre mécanisme d'alerte. Rien ne casserait — c'est bien le problème.
    assert_absent "$tache" "2>&1" \
        "la ligne de tâche ne redirige PAS la sortie d'erreur — seule alerte disponible"
    assert_absent "$contenu" "2>&1" \
        "aucune ligne du fichier ne redirige la sortie d'erreur"
    assert_absent "$tache" "2>/dev/null" \
        "la ligne de tâche ne jette pas non plus la sortie d'erreur autrement"

    # cron ignore une dernière ligne dépourvue de retour chariot : l'entrée de
    # tâche étant la dernière du fichier, l'oubli la rendrait inopérante.
    if [ -z "$(tail -c 1 "$FICHIER_CRON")" ]; then
        ok "le fichier se termine par un retour à la ligne"
    else
        ko "le fichier se termine par un retour à la ligne" "dernier octet non nul"
    fi

    # Le nom du fichier : un point le rendrait invisible pour cron, en silence.
    assert_egal "mgnetworking" "$(basename "$FICHIER_CRON")" \
        "le fichier déposé se nomme « mgnetworking », sans extension"
    restes="$(find "$REPERTOIRE_CRON" -maxdepth 1 -name 'mgnetworking*' | sort | tr '\n' ' ')"
    assert_egal "$FICHIER_CRON " "$restes" \
        "aucun fichier temporaire « mgnetworking.tmp.* » ne subsiste dans $REPERTOIRE_CRON"
fi

# ===================================================================
# 7. Permissions, et correction d'un état dérivé
# ===================================================================
# cron rejette un fichier de /etc/cron.d qui n'appartient pas à root ou qui
# porte le bit d'exécution — sans le dire. Le script doit poser les bonnes
# permissions, et les rétablir si elles ont dérivé, sans toucher au contenu.
titre "7. Permissions"

if [ ! -f "$FICHIER_CRON" ]; then
    saute "les permissions du fichier déposé" \
        "$FICHIER_CRON n'a pas été déposé — voir les groupes précédents"
    saute "la correction d'un état dérivé" \
        "$FICHIER_CRON n'a pas été déposé — voir les groupes précédents"
else
    assert_egal "root:root" "$(stat -c '%U:%G' "$FICHIER_CRON")" \
        "le fichier appartient à root:root"
    assert_egal "644" "$(stat -c '%a' "$FICHIER_CRON")" \
        "le fichier est en mode 0644"

    if [ -x "$FICHIER_CRON" ]; then
        ko "le fichier n'est pas exécutable" "cron rejetterait un fichier exécutable"
    else
        ok "le fichier n'est pas exécutable"
    fi

    # --- Dérive des permissions, contenu intact ----------------------------
    if [ "$MODIFIANT" != "oui" ]; then
        saute "la correction d'un état dérivé" "$MODIFIANT"
    else
        cksum_avant="$(cksum < "$FICHIER_CRON")"
        chmod 0755 "$FICHIER_CRON"
        chown nobody:nogroup "$FICHIER_CRON" 2>/dev/null || chown nobody "$FICHIER_CRON"

        lancer bash "$CRON_SH" -y
        assert_code 0 "$CODE" "l'exécution sur un état dérivé sort en 0"
        derive="$(erreur)"
        assert_contient "$derive" "est déjà celui attendu" \
            "le contenu est reconnu conforme malgré la dérive des permissions"
        assert_contient "$derive" "Propriétaire corrigé" "le propriétaire est corrigé"
        assert_contient "$derive" "Mode corrigé" "le mode est corrigé"
        assert_absent "$derive" "Fichier écrit" \
            "le contenu n'est pas réécrit pour corriger des permissions"

        assert_egal "root:root" "$(stat -c '%U:%G' "$FICHIER_CRON")" \
            "le propriétaire est revenu à root:root"
        assert_egal "644" "$(stat -c '%a' "$FICHIER_CRON")" \
            "le mode est revenu à 0644"
        assert_egal "$cksum_avant" "$(cksum < "$FICHIER_CRON")" \
            "le contenu du fichier est resté identique pendant la correction"

        # Le même état dérivé, en --dry-run : il annonce, il ne corrige pas.
        chmod 0755 "$FICHIER_CRON"
        lancer bash "$CRON_SH" --dry-run
        assert_code 0 "$CODE" "--dry-run sur un état dérivé sort en 0"
        assert_contient "$(erreur)" "[dry-run] Appliquerait le mode 0644" \
            "--dry-run annonce la correction de mode sans l'appliquer"
        assert_egal "755" "$(stat -c '%a' "$FICHIER_CRON")" \
            "--dry-run n'a pas corrigé le mode"

        lancer bash "$CRON_SH" -y
        assert_code 0 "$CODE" "l'exécution réelle qui suit sort en 0"
        assert_egal "644" "$(stat -c '%a' "$FICHIER_CRON")" \
            "le mode 0644 est rétabli après le --dry-run"
    fi
fi

# ===================================================================
# 8. Remplacement d'un fichier divergent, et doublons
# ===================================================================
# Le fichier appartient à l'administrateur dès qu'il l'a modifié : le script ne
# doit pas l'écraser sans le dire. Trois chemins : --dry-run, refus, accord.
titre "8. Remplacement d'un fichier divergent"

RAISON_REMPLACEMENT="$MODIFIANT"
if [ "$RAISON_REMPLACEMENT" = "oui" ] && [ ! -f "$FICHIER_CRON" ]; then
    RAISON_REMPLACEMENT="$FICHIER_CRON n'a pas été déposé — voir les groupes précédents"
fi

if [ "$RAISON_REMPLACEMENT" != "oui" ]; then
    saute "le remplacement d'un fichier divergent" "$RAISON_REMPLACEMENT"
    saute "le refus d'un remplacement" "$RAISON_REMPLACEMENT"
    saute "le signalement d'une planification en double" "$RAISON_REMPLACEMENT"
else
    reference="$REP_TMP/conforme"
    cp "$FICHIER_CRON" "$reference"

    # --- --dry-run : il montre la différence, il ne touche à rien -----------
    printf '# fichier modifié à la main par l administrateur\n' > "$FICHIER_CRON"
    lancer bash "$CRON_SH" --dry-run
    assert_code 0 "$CODE" "--dry-run sur un fichier divergent sort en 0"
    divergent="$(erreur)"
    assert_contient "$divergent" "diffère du contenu attendu" \
        "--dry-run signale la divergence"
    assert_contient "$divergent" "[dry-run] Remplacerait $FICHIER_CRON" \
        "--dry-run annonce le remplacement qu'il ferait"
    assert_egal "# fichier modifié à la main par l administrateur" "$(cat "$FICHIER_CRON")" \
        "--dry-run laisse intact le fichier de l'administrateur"

    # --- Refus : entrée standard fermée, confirm() lit une réponse vide -----
    lancer bash "$CRON_SH"
    assert_code 0 "$CODE" "un remplacement refusé sort en 0"
    assert_contient "$(erreur)" "le fichier en place est conservé" \
        "un remplacement refusé conserve le fichier en place"
    assert_egal "# fichier modifié à la main par l administrateur" "$(cat "$FICHIER_CRON")" \
        "le fichier de l'administrateur survit à un refus"

    # --- Accord : la réponse « o » est saisie -------------------------------
    lancer_entree "o" bash "$CRON_SH"
    assert_code 0 "$CODE" "un remplacement accepté sort en 0"
    assert_contient "$(erreur)" "Fichier écrit : $FICHIER_CRON" \
        "un remplacement accepté réécrit le fichier"
    if cmp -s "$reference" "$FICHIER_CRON"; then
        ok "le fichier remplacé est identique au fichier de référence"
    else
        ko "le fichier remplacé est identique au fichier de référence" "les deux fichiers diffèrent"
    fi

    # --- Doublon signalé ----------------------------------------------------
    # Deux planifications concurrentes se bloqueraient sur le verrou d'apt. Le
    # script avertit sans rien toucher : ce fichier-là ne lui appartient pas.
    doublon="$REPERTOIRE_CRON/mgnet-test-doublon"
    printf '0 5 * * 1 root %s --yes >/dev/null\n' "$PLANIFIE" > "$doublon"
    cksum_doublon="$(cksum < "$doublon")"

    lancer bash "$CRON_SH" -y
    assert_code 0 "$CODE" "l'exécution en présence d'un doublon sort en 0"
    assert_contient "$(erreur)" "déjà planifié ailleurs" \
        "une planification en double est signalée"
    assert_contient "$(erreur)" "$doublon" "le fichier en double est nommé"
    assert_egal "$cksum_doublon" "$(cksum < "$doublon")" \
        "le fichier en double n'est pas modifié — il appartient à l'administrateur"

    rm -f "$doublon"
    assert_fichier_absent "$doublon" "le fichier de doublon jetable est supprimé"
fi

# ===================================================================
# 9. Hors de portée de cet environnement
# ===================================================================
# Ces lignes ne sont pas des cas manqués : ce sont des cas dont on sait qu'ils
# ne peuvent pas être joués ici. Les taire ferait croire à une couverture
# complète.
titre "9. Hors de portée de cet environnement"

saute "cron exécutant réellement la tâche à l'heure dite" \
    "le profil debian n'a pas d'init — le démon n'est pas lancé, aucun passage n'a lieu"
saute "le bit d'exécution réel de update-system.sh dans le dépôt" \
    "le montage Docker Desktop expose tous les fichiers en 0777 : « test -x » y répond toujours oui, quel que soit le mode enregistré par git"
saute "le rechargement de la planification par cron après dépôt" \
    "exige un démon cron en service — profil « systemd », non écrit"
saute "le refus de cron devant un fichier au nom pointé ou exécutable" \
    "exige un démon cron en service : le script prévient ces deux cas, mais le rejet lui-même n'est observable que par cron"
saute "un chemin de dépôt contenant une espace ou un « % »" \
    "exige de recopier le dépôt sous un tel chemin — le montage /depot n'en comporte pas, et la garde est testée par lecture seule"

# ===================================================================
# 10. Nettoyage
# ===================================================================
# Le fichier déposé est retiré, celui de l'administrateur remis, et l'absence de
# chaque fichier jetable est vérifiée : le trap EXIT n'est qu'un filet, il ne
# rend compte de rien.
titre "10. Nettoyage"

if [ "$MODIFIANT" = "oui" ]; then
    rm -f "$FICHIER_CRON"
    if [ -n "$SAUVEGARDE_FICHIER" ] && [ -f "$SAUVEGARDE_FICHIER" ]; then
        cp "$SAUVEGARDE_FICHIER" "$FICHIER_CRON"
        chown root:root "$FICHIER_CRON"
        chmod 0644 "$FICHIER_CRON"
        SAUVEGARDE_FICHIER=""
        if [ -f "$FICHIER_CRON" ]; then
            ok "le $FICHIER_CRON préexistant a été remis en place"
        else
            ko "le $FICHIER_CRON préexistant a été remis en place" "le fichier est absent"
        fi
    else
        assert_fichier_absent "$FICHIER_CRON" "le fichier déposé par le test est supprimé"
    fi
else
    saute "le nettoyage du fichier déposé" "$MODIFIANT — rien n'a été déposé"
fi

rm -rf "$BAC" "$LOG_DIR_NOBODY"
assert_fichier_absent "$BAC" "le bac à sable est supprimé"
assert_fichier_absent "$LOG_DIR_NOBODY" "le répertoire de journaux non privilégié est supprimé"

rep_final="$REP_TMP"
rm -rf "$REP_TMP"
assert_fichier_absent "$rep_final" "le répertoire de travail jetable est supprimé"

bilan "TASK-009 / configure-cron.sh"
