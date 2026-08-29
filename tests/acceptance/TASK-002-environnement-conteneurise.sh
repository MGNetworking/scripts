#!/usr/bin/env bash
# tests/acceptance/TASK-002-environnement-conteneurise.sh — critères de TASK-002.
#
# Prouve, par exécution réelle, ce que tests/env/run-in-container.sh annonce :
# préflight, aide, --dry-run inoffensif, état de départ identique d'une
# exécution à l'autre, fidélité du code de retour, destruction du conteneur.
#
# Les cas qui attendent un échec sont isolés dans un sous-shell : le lanceur
# charge lib/common.sh, qui pose un trap ERR, et tourne sous set -Eeuo pipefail.
#
# Le démon Docker arrêté n'est PAS simulé en arrêtant Docker Desktop — deux
# substituts fidèles sont utilisés : un PATH sans docker (client absent) et un
# DOCKER_HOST pointant sur un port fermé (démon injoignable).
#
# Ce fichier sort en 3 si un critère n'a pas pu être vérifié : « pas pu
# vérifier » ne vaut jamais « vérifié ».

set -Eeuo pipefail

_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_dir/lib/common.sh" ] && [ "$_dir" != "/" ]; do _dir="$(dirname "$_dir")"; done
source "$_dir/lib/common.sh"

LANCEUR="$SCRIPTS_ROOT/tests/env/run-in-container.sh"
PREFIXE="mgnet-test-"
PROFIL="debian"
IMAGE="${PREFIXE}${PROFIL}:latest"

# Profil jetable, créé puis supprimé par ce fichier : il sert à éprouver le
# --dry-run sur une image absente et l'échec de construction (code 4), sans
# jamais toucher au profil réel.
PROFIL_TEMP="tmp-echec-construction"
DOCKERFILE_TEMP="$SCRIPTS_ROOT/tests/env/Dockerfile.$PROFIL_TEMP"
IMAGE_TEMP="${PREFIXE}${PROFIL_TEMP}:latest"

# Fichier écrit dans le dépôt monté, pour prouver le montage en écriture.
# logs/ est ignoré par Git : le dépôt reste propre même si un cas échoue.
TEMOIN_ECRITURE="$SCRIPTS_ROOT/logs/.mgnet-test-ecriture"

REP_TMP="$(mktemp -d)"
FIC_OUT="$REP_TMP/stdout"
FIC_ERR="$REP_TMP/stderr"
CODE=0

reussites=0
echecs=0
non_executes=0

# -------------------------------------------------------------------
# Nettoyage
# -------------------------------------------------------------------
# Appelé explicitement en fin de fichier ET par le trap : un cas interrompu ne
# doit laisser ni fichier temporaire, ni Dockerfile jetable, ni conteneur.
nettoyer() {
    rm -rf "$REP_TMP"
    rm -f "$DOCKERFILE_TEMP" "$TEMOIN_ECRITURE"

    command -v docker >/dev/null 2>&1 || return 0

    local restants nom
    restants="$(docker ps -a --filter "name=$PREFIXE" --format '{{.Names}}' 2>/dev/null || true)"
    if [ -n "$restants" ]; then
        warn "Conteneurs préfixés $PREFIXE encore présents — suppression : $restants"
        while IFS= read -r nom; do
            [ -n "$nom" ] || continue
            docker rm -f "$nom" >/dev/null 2>&1 || true
        done <<<"$restants"
    fi

    if docker image inspect "$IMAGE_TEMP" >/dev/null 2>&1; then
        docker rmi -f "$IMAGE_TEMP" >/dev/null 2>&1 || true
    fi
}
trap nettoyer EXIT

# -------------------------------------------------------------------
# Assertions — Bash pur, aucun framework
# -------------------------------------------------------------------
titre() { info "--- $* ---"; }

ok() {
    success "$1"
    reussites=$((reussites + 1))
}

ko() {
    error "ÉCHEC : $1"
    if [ -s "$FIC_ERR" ]; then
        printf '        dernières lignes de la sortie :\n' >&2
        tail -n 4 "$FIC_ERR" | sed 's/^/        /' >&2
    fi
    echecs=$((echecs + 1))
}

saute() {
    warn "NON EXÉCUTÉ : $1 — $2"
    non_executes=$((non_executes + 1))
}

# Exécute le lanceur (ou toute commande) en capturant flux et code de retour,
# sans jamais déclencher le trap ERR de ce fichier.
lancer() {
    CODE=0
    ( "$@" ) >"$FIC_OUT" 2>"$FIC_ERR" || CODE=$?
}

assert_code() {
    local attendu="$1" libelle="$2"
    if [ "$CODE" -eq "$attendu" ]; then
        ok "$libelle — code $CODE"
    else
        ko "$libelle — code attendu $attendu, obtenu $CODE"
    fi
}

assert_contient() {
    local fichier="$1" motif="$2" libelle="$3"
    if grep -qF -- "$motif" "$fichier"; then
        ok "$libelle"
    else
        ko "$libelle — motif absent : $motif"
    fi
}

assert_absent() {
    local fichier="$1" motif="$2" libelle="$3"
    if grep -qF -- "$motif" "$fichier"; then
        ko "$libelle — motif présent alors qu'il ne devrait pas : $motif"
    else
        ok "$libelle"
    fi
}

aucun_conteneur_residuel() {
    local libelle="$1" restants
    restants="$(docker ps -a --filter "name=$PREFIXE" --format '{{.Names}}' 2>/dev/null || true)"
    if [ -z "$restants" ]; then
        ok "$libelle"
    else
        ko "$libelle — conteneurs survivants : $(printf '%s' "$restants" | tr '\n' ' ')"
    fi
}

# -------------------------------------------------------------------
# Disponibilité de l'environnement
# -------------------------------------------------------------------
[ -f "$LANCEUR" ] || die "Lanceur introuvable : $LANCEUR" 1

DOCKER_UTILISABLE="false"
if command -v docker >/dev/null 2>&1; then
    version_serveur="$(docker info --format '{{.ServerVersion}}' 2>/dev/null || true)"
    if [ -n "$version_serveur" ]; then
        DOCKER_UTILISABLE="true"
        info "Démon Docker disponible — version serveur $version_serveur"
    fi
fi
if [ "$DOCKER_UTILISABLE" = "false" ]; then
    warn "Le démon Docker ne répond pas depuis cette machine."
    warn "Tous les cas comportementaux seront déclarés NON EXÉCUTÉS."
fi

# PATH privé de docker : sert à éprouver le cas « client absent » sans toucher
# à l'installation. Vide si docker n'est pas dans le PATH.
PATH_SANS_DOCKER=""
if command -v docker >/dev/null 2>&1; then
    dossier_docker="$(dirname "$(command -v docker)")"
    while IFS= read -r element; do
        [ -n "$element" ] || continue
        if [ "$element" = "$dossier_docker" ]; then
            continue
        fi
        if [ -z "$PATH_SANS_DOCKER" ]; then
            PATH_SANS_DOCKER="$element"
        else
            PATH_SANS_DOCKER="$PATH_SANS_DOCKER:$element"
        fi
    done <<<"$(printf '%s' "$PATH" | tr ':' '\n')"
fi

# ===================================================================
# 1. Préflight et usage — aucun accès à Docker requis
# ===================================================================
titre "1. Préflight et erreurs d'usage"

lancer bash "$LANCEUR" --help
assert_code 0 "--help sort en 0"
assert_contient "$FIC_OUT" "Usage : tests/env/run-in-container.sh" "--help affiche l'usage sur stdout"

lancer bash "$LANCEUR"
assert_code 2 "aucun argument"
assert_contient "$FIC_ERR" "Aucune commande à exécuter" "aucun argument : message explicite"

lancer bash "$LANCEUR" --
assert_code 2 "« -- » suivi de rien"

lancer bash "$LANCEUR" --option-inexistante -- true
assert_code 2 "option inconnue"
assert_contient "$FIC_ERR" "Option inconnue" "option inconnue : message explicite"

lancer bash "$LANCEUR" --profil
assert_code 2 "--profil sans valeur"

lancer bash "$LANCEUR" --profil profil-qui-n-existe-pas -- true
assert_code 2 "profil inexistant"
assert_contient "$FIC_ERR" "Profil inconnu" "profil inexistant : message explicite"
assert_contient "$FIC_ERR" "Profils disponibles : debian" "profil inexistant : liste les profils réels"

# Une erreur d'usage doit être détectée AVANT toute action Docker : sans docker
# dans le PATH, le code doit rester 2 et non 3.
if [ -n "$PATH_SANS_DOCKER" ]; then
    lancer env PATH="$PATH_SANS_DOCKER" bash "$LANCEUR" --profil profil-qui-n-existe-pas -- true
    assert_code 2 "profil inexistant sans docker : l'usage prime sur l'environnement"
else
    saute "usage avant Docker" "docker n'est pas dans le PATH, la simulation n'a pas de sens"
fi

# ===================================================================
# 2. Environnement indisponible — jamais un faux succès
# ===================================================================
titre "2. Docker indisponible"

if [ -n "$PATH_SANS_DOCKER" ]; then
    lancer env PATH="$PATH_SANS_DOCKER" bash "$LANCEUR" -- true
    assert_code 3 "client docker absent"
    assert_contient "$FIC_ERR" "docker est introuvable" "client absent : message explicite"
    assert_absent "$FIC_ERR" "[SUCCESS]" "client absent : aucun faux succès"
else
    saute "client docker absent" "docker n'est pas dans le PATH, impossible de l'en retirer"
fi

# DOCKER_HOST sur un port fermé : le client est là, le démon ne répond pas.
# C'est le substitut fidèle de « Docker Desktop arrêté », sans l'arrêter.
if [ "$DOCKER_UTILISABLE" = "true" ]; then
    lancer env DOCKER_HOST="tcp://127.0.0.1:1" bash "$LANCEUR" -- true
    assert_code 3 "démon injoignable"
    assert_contient "$FIC_ERR" "Le démon Docker ne répond pas" "démon injoignable : message explicite"
    assert_absent "$FIC_ERR" "[SUCCESS]" "démon injoignable : aucun faux succès"
    aucun_conteneur_residuel "démon injoignable : aucun conteneur créé"
else
    saute "démon injoignable" "le démon ne répond déjà pas, la comparaison ne prouverait rien"
fi

# ===================================================================
# 3. --dry-run — ni construction, ni exécution
# ===================================================================
titre "3. --dry-run"

if [ "$DOCKER_UTILISABLE" = "true" ]; then
    # Profil jetable : son image n'existe pas, --dry-run doit donc annoncer la
    # construction sans la faire. Le Dockerfile échouerait s'il était construit,
    # ce qui rend la preuve incontestable.
    printf 'FROM debian:12\nRUN echo "construction volontairement en echec" && exit 1\n' \
        > "$DOCKERFILE_TEMP"

    lancer bash "$LANCEUR" --profil "$PROFIL_TEMP" --dry-run -- bash -c 'echo NE_DOIT_PAS_APPARAITRE'
    assert_code 0 "--dry-run sur image absente"
    assert_contient "$FIC_ERR" "[dry-run] docker build" "--dry-run annonce la construction"
    assert_contient "$FIC_ERR" "[dry-run] docker run" "--dry-run annonce l'exécution"
    assert_absent "$FIC_OUT" "NE_DOIT_PAS_APPARAITRE" "--dry-run n'exécute pas la commande"

    if docker image inspect "$IMAGE_TEMP" >/dev/null 2>&1; then
        ko "--dry-run n'a rien construit — image $IMAGE_TEMP créée"
    else
        ok "--dry-run n'a rien construit — aucune image $IMAGE_TEMP"
    fi
    aucun_conteneur_residuel "--dry-run n'a créé aucun conteneur"

    lancer bash "$LANCEUR" --profil "$PROFIL_TEMP" --reconstruire --dry-run -- true
    assert_code 0 "--reconstruire --dry-run"
    assert_contient "$FIC_ERR" "docker build --pull --no-cache" "--reconstruire ajoute --pull --no-cache"
else
    saute "--dry-run" "le démon Docker ne répond pas"
fi

# ===================================================================
# 4. Échec de construction — code 4, rien n'est exécuté
# ===================================================================
titre "4. Échec de construction"

if [ "$DOCKER_UTILISABLE" = "true" ]; then
    lancer bash "$LANCEUR" --profil "$PROFIL_TEMP" -- bash -c 'echo NE_DOIT_PAS_APPARAITRE'
    assert_code 4 "construction en échec"
    assert_contient "$FIC_ERR" "Échec de la construction" "construction en échec : message explicite"
    assert_absent "$FIC_OUT" "NE_DOIT_PAS_APPARAITRE" "construction en échec : commande non exécutée"
    aucun_conteneur_residuel "construction en échec : aucun conteneur"
    rm -f "$DOCKERFILE_TEMP"
else
    saute "échec de construction" "le démon Docker ne répond pas"
fi

# ===================================================================
# 5. Nominal — l'image, le montage, les flux
# ===================================================================
titre "5. Exécution nominale"

if [ "$DOCKER_UTILISABLE" = "true" ]; then
    # Commande de validation inscrite dans TASK-002.
    lancer bash "$LANCEUR" -- bash -c 'cat /etc/os-release'
    assert_code 0 "cat /etc/os-release dans le conteneur"
    assert_contient "$FIC_OUT" "ID=debian" "l'image est une Debian"
    assert_contient "$FIC_OUT" 'VERSION_ID="12"' "l'image est une Debian 12"
    # stdout doit porter la seule sortie du conteneur : les messages du lanceur
    # partent sur stderr, sinon un « cat » lu par un tiers serait pollué.
    assert_absent "$FIC_OUT" "[INFO]" "stdout n'est pas pollué par les messages du lanceur"
    assert_contient "$FIC_ERR" "Conteneur  : $PREFIXE" "le conteneur porte le préfixe $PREFIXE"

    if docker image inspect "$IMAGE" >/dev/null 2>&1; then
        ok "l'image construite est nommée $IMAGE"
    else
        ko "l'image construite est nommée $IMAGE — introuvable"
    fi

    # Contenu de l'image : chacun de ces outils a sa justification dans le
    # Dockerfile. Un seul conteneur, une assertion par outil.
    # Les guillemets simples sont voulus : « $o », « $LANG » et « $PWD » doivent
    # être développés DANS le conteneur, pas ici. D'où SC2016 désactivé.
    # shellcheck disable=SC2016
    lancer bash "$LANCEUR" -- bash -c 'for o in ip free uptime shellcheck apt-get; do if command -v "$o" >/dev/null 2>&1; then echo "present:$o"; else echo "absent:$o"; fi; done; echo "LANG=$LANG"; echo "PWD=$PWD"'
    assert_code 0 "inventaire de l'image"
    assert_contient "$FIC_OUT" "present:ip" "iproute2 présent (ip)"
    assert_contient "$FIC_OUT" "present:free" "procps présent (free)"
    assert_contient "$FIC_OUT" "present:uptime" "procps présent (uptime)"
    assert_contient "$FIC_OUT" "present:shellcheck" "shellcheck présent"
    assert_contient "$FIC_OUT" "present:apt-get" "apt-get présent"
    assert_contient "$FIC_OUT" "LANG=C.UTF-8" "locale C.UTF-8"
    assert_contient "$FIC_OUT" "PWD=/depot" "répertoire de travail /depot"

    # Montage en lecture-écriture : le conteneur écrit, l'hôte relit.
    rm -f "$TEMOIN_ECRITURE"
    lancer bash "$LANCEUR" -- bash -c 'echo ecrit-par-le-conteneur > /depot/logs/.mgnet-test-ecriture'
    assert_code 0 "écriture dans le dépôt monté"
    if [ -f "$TEMOIN_ECRITURE" ] && [ "$(cat "$TEMOIN_ECRITURE")" = "ecrit-par-le-conteneur" ]; then
        ok "le dépôt est monté en lecture-écriture — l'hôte relit ce que le conteneur a écrit"
    else
        ko "le dépôt est monté en lecture-écriture — témoin absent ou altéré"
    fi
    rm -f "$TEMOIN_ECRITURE"

    # Bit exécutable des fichiers montés : un script du dépôt doit pouvoir être
    # invoqué directement, sans « bash » devant.
    if [ -f "$SCRIPTS_ROOT/Linux/System/system-info.sh" ]; then
        lancer bash "$LANCEUR" -- Linux/System/system-info.sh
        assert_code 0 "Linux/System/system-info.sh s'exécute directement (bit exécutable du montage)"
        assert_contient "$FIC_OUT" "Nom d'hôte" "system-info.sh produit son rapport sur stdout"
    else
        saute "bit exécutable du montage" "Linux/System/system-info.sh est absent du dépôt"
    fi
else
    saute "exécution nominale" "le démon Docker ne répond pas"
fi

# ===================================================================
# 6. Fidélité du code de retour
# ===================================================================
titre "6. Fidélité du code de retour"

if [ "$DOCKER_UTILISABLE" = "true" ]; then
    for attendu in 0 1 7 42; do
        lancer bash "$LANCEUR" -- bash -c "exit $attendu"
        assert_code "$attendu" "exit $attendu transmis tel quel"
    done

    lancer bash "$LANCEUR" -- false
    assert_code 1 "« false » transmis en 1"

    # Codes 3 et 4 : le lanceur les utilise pour ses propres échecs, mais la
    # transmission fidèle prime. La documentation assume l'ambiguïté ; on
    # vérifie qu'elle se résout bien en faveur de la commande.
    lancer bash "$LANCEUR" -- bash -c 'exit 3'
    assert_code 3 "exit 3 de la commande transmis malgré la collision avec le code d'environnement"
    assert_contient "$FIC_ERR" "code de retour 3" "collision de code : message levant l'ambiguïté"
else
    saute "fidélité du code de retour" "le démon Docker ne répond pas"
fi

# ===================================================================
# 7. Aucun état ne survit — deux exécutions partent du même état
# ===================================================================
titre "7. État de départ identique"

if [ "$DOCKER_UTILISABLE" = "true" ]; then
    # Un marqueur écrit HORS du dépôt monté : s'il survit, le conteneur a été
    # réutilisé et aucun test d'idempotence ne vaudrait plus rien.
    lancer bash "$LANCEUR" -- bash -c 'echo marqueur > /var/tmp/mgnet-marqueur-etat; test -f /var/tmp/mgnet-marqueur-etat'
    assert_code 0 "première exécution : marqueur déposé dans /var/tmp"

    lancer bash "$LANCEUR" -- bash -c 'test ! -e /var/tmp/mgnet-marqueur-etat'
    assert_code 0 "seconde exécution : le marqueur de la première a disparu"

    # Empreinte du système de fichiers hors dépôt, avant et après.
    empreinte='ls -a / ; ls -aR /var/tmp /tmp /root /etc/apt'
    lancer bash "$LANCEUR" -- bash -c "$empreinte"
    assert_code 0 "empreinte 1 relevée"
    cp "$FIC_OUT" "$REP_TMP/empreinte1"

    lancer bash "$LANCEUR" -- bash -c "$empreinte"
    assert_code 0 "empreinte 2 relevée"
    cp "$FIC_OUT" "$REP_TMP/empreinte2"

    if diff -u "$REP_TMP/empreinte1" "$REP_TMP/empreinte2" > "$REP_TMP/diff-empreintes"; then
        ok "deux exécutions consécutives partent d'un état identique"
    else
        ko "deux exécutions consécutives partent d'un état identique — différences détectées"
        head -n 20 "$REP_TMP/diff-empreintes" >&2
    fi

    aucun_conteneur_residuel "aucun conteneur ne survit aux exécutions"
else
    saute "état de départ identique" "le démon Docker ne répond pas"
fi

# ===================================================================
# 8. Filet de sécurité à l'interruption
# ===================================================================
titre "8. Interruption en cours d'exécution"

if [ "$DOCKER_UTILISABLE" = "true" ]; then
    ( bash "$LANCEUR" -- sleep 45 ) >"$FIC_OUT" 2>"$FIC_ERR" &
    pid_lanceur=$!

    conteneur=""
    for _ in $(seq 1 60); do
        conteneur="$(docker ps --filter "name=$PREFIXE" --format '{{.Names}}' 2>/dev/null || true)"
        if [ -n "$conteneur" ]; then
            break
        fi
        sleep 1
    done

    if [ -z "$conteneur" ]; then
        kill -TERM "$pid_lanceur" 2>/dev/null || true
        wait "$pid_lanceur" 2>/dev/null || true
        saute "filet de sécurité à l'interruption" "le conteneur n'a pas démarré dans le délai imparti"
    else
        kill -TERM "$pid_lanceur" 2>/dev/null || true
        wait "$pid_lanceur" 2>/dev/null || true
        sleep 3
        aucun_conteneur_residuel "interruption : le conteneur est détruit malgré la sortie anormale"
        assert_contient "$FIC_ERR" "Conteneur résiduel" "interruption : la suppression est annoncée"
    fi
else
    saute "filet de sécurité à l'interruption" "le démon Docker ne répond pas"
fi

# ===================================================================
# Bilan
# ===================================================================
nettoyer

info "Bilan TASK-002 : $reussites vérification(s) réussie(s), $echecs échec(s), $non_executes NON EXÉCUTÉ(s)"

if [ "$echecs" -gt 0 ]; then
    die "TASK-002 : $echecs critère(s) en défaut." 1
fi

if [ "$non_executes" -gt 0 ]; then
    warn "TASK-002 : $non_executes vérification(s) NON EXÉCUTÉE(s) — les critères correspondants ne sont pas prouvés."
    exit 3
fi

success "TASK-002 : tous les critères vérifiés ($reussites vérifications)."
