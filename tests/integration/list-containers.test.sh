#!/usr/bin/env bash
# tests/integration/list-containers.test.sh — Docker/Diagnostics/list-containers.sh.
#
# TASK-033. Le conteneur de test n'a pas de démon Docker et n'en aura pas : les
# trois causes d'échec du script sont éprouvées par un faux « docker » placé en
# tête de PATH, et l'inventaire lui-même par des réponses tabulées fabriquées.
#
# Le faux « docker » ENREGISTRE SES ARGUMENTS. C'est ce qui prouve la lecture
# seule autrement qu'en relisant le script : la trace ne doit porter que des
# sous-commandes « ps », et un seul appel par exécution.
#
# PATH est préfixé à chaque appel, jamais supposé acquis : lib/common.sh charge
# config/server.env APRÈS la résolution de sa racine, et ce fichier peut
# redéfinir PATH. Sur une machine qui en porte un, le faux docker serait ignoré
# en silence et le vrai démon interrogé.
#
# Les cas « sans faux docker » ci-dessous — aide, docker absent, option
# inconnue — ne valent que parce que la commande docker est réellement absente
# du conteneur : c'est la même dépendance qu'assume check-docker.test.sh.

_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_dir/lib/common.sh" ] && [ "$_dir" != "/" ]; do _dir="$(dirname "$_dir")"; done
source "$_dir/lib/common.sh"
source "$SCRIPTS_ROOT/tests/lib/assert.sh"

CIBLE="$SCRIPTS_ROOT/Docker/Diagnostics/list-containers.sh"
BAC="$(mktemp -d)"
TRACE="$BAC/appels"
trap 'rm -rf "$BAC"' EXIT

# -------------------------------------------------------------------
# Faux docker
# -------------------------------------------------------------------
# Il trace ses arguments, puis rend ce que l'environnement lui demande :
# STUB_SORTIE sur la sortie standard, STUB_ERREUR sur la sortie d'erreur,
# STUB_CODE en code de retour.
cat > "$BAC/docker" <<'STUB'
#!/bin/sh
printf '%s\n' "$*" >> "$TRACE"
if [ -n "${STUB_SORTIE:-}" ]; then printf '%s\n' "$STUB_SORTIE"; fi
if [ -n "${STUB_ERREUR:-}" ]; then printf '%s\n' "$STUB_ERREUR" >&2; fi
exit "${STUB_CODE:-0}"
STUB
chmod +x "$BAC/docker"

# Lance le script sous le faux docker. $1 : sortie standard, $2 : sortie
# d'erreur, $3 : code de retour, le reste : arguments du script. Renseigne
# SORTIE et CODE, que les assertions lisent — les passer par stdout les
# perdrait dans un sous-shell.
SORTIE=""
CODE=0
lancer() {
    local attendu_sortie="$1" attendu_erreur="$2" code_stub="$3"
    shift 3
    SORTIE="$(STUB_SORTIE="$attendu_sortie" STUB_ERREUR="$attendu_erreur" \
        STUB_CODE="$code_stub" TRACE="$TRACE" PATH="$BAC:$PATH" \
        bash "$CIBLE" "$@" 2>&1)" && CODE=0 || CODE=$?
}

# -------------------------------------------------------------------
# Réponses fabriquées
# -------------------------------------------------------------------
# Trois conteneurs actifs, aux longueurs délibérément inégales : un nom de 39
# caractères, une liste de ports à rallonge, trois réseaux. « batch » n'a AUCUN
# port publié — le champ vide est le piège du découpage sur tabulations : deux
# tabulations voisines n'y comptent que pour un seul séparateur si l'on s'y
# prend mal, et tout ce qui suit se décale.
API=$'api\tregistre.exemple.net/equipe/api:2.14.0\tUp 3 hours\t0.0.0.0:8080->80/tcp, 0.0.0.0:8443->443/tcp, :::8080->80/tcp\tfrontend,backend,supervision\t9f8e7d6c5b4a'
BATCH=$'batch\texemple/batch:0.9\tUp 12 minutes\t\tlot-interne\ta1b2c3d4e5f6'
COLLECTE=$'collecteur-de-metriques-du-site-principal\texemple/collecteur:1.0\tRestarting (1) 5 seconds ago\t127.0.0.1:9100->9100/tcp\tsupervision\t112233445566'
ARCHIVE=$'archive\texemple/archive:3.1\tExited (0) 2 days ago\t\tlot-interne\tdeadbeef0000'

ACTIFS="$API
$BATCH
$COLLECTE"
TOUS="$ACTIFS
$ARCHIVE"

# -------------------------------------------------------------------
# Outils d'analyse du tableau
# -------------------------------------------------------------------
# La ligne du tableau qui porte un motif — vide si aucune.
ligne_de() {
    local ligne
    while IFS= read -r ligne; do
        if contient "$ligne" "$2"; then
            printf '%s\n' "$ligne"
            return 0
        fi
    done <<< "$1"
    return 1
}

# Rang, compté en caractères, auquel commence une valeur dans une ligne. Deux
# lignes sont alignées sur une colonne si ce rang y est le même.
rang_de() {
    local ligne="$1"
    ligne="${ligne%%"$2"*}"
    printf '%s' "${#ligne}"
}

# -------------------------------------------------------------------
# Aide et erreurs d'usage
# -------------------------------------------------------------------
titre "Aide — lisible alors que docker n'est pas installé"

SORTIE="$(bash "$CIBLE" --help 2>&1)" && code=0 || code=$?
assert_code 0 "$code" "--help rend 0 sans consulter le moindre démon"
assert_contient "$SORTIE" "--all" "l'aide documente les options"
assert_contient "$SORTIE" "IDENTIFIANT" "l'aide dit ce que contient chaque colonne"
assert_contient "$SORTIE" "Codes de retour" "l'aide documente les codes de retour"

titre "Docker absent — le client n'est pas installé"

SORTIE="$(bash "$CIBLE" 2>&1)" && code=0 || code=$?
assert_code 1 "$code" "l'absence de la commande rend 1, jamais 2"
assert_contient "$SORTIE" "introuvable" "le message nomme la dépendance manquante"
assert_contient "$SORTIE" "docker" "et la nomme précisément"
assert_absent "$SORTIE" "ne répond pas" "l'absence du client n'est pas confondue avec un démon muet"
assert_absent "$SORTIE" "groupe docker" "ni avec un refus d'accès à la socket"

titre "Une option inconnue — faute d'usage, et rien d'autre"

SORTIE="$(bash "$CIBLE" --inconnue 2>&1)" && code=0 || code=$?
assert_code 2 "$code" "une option inconnue rend 2, et aucun préflight n'a eu lieu"
assert_contient "$SORTIE" "[ERROR]" "le message porte le préfixe [ERROR]"
assert_contient "$SORTIE" "Option inconnue" "et nomme l'option fautive"
assert_absent "$SORTIE" "Usage" "l'aide n'est pas déversée"
assert_egal "1" "$(printf '%s\n' "$SORTIE" | wc -l | tr -d ' ')" \
    "le refus tient sur une seule ligne"

# -------------------------------------------------------------------
# Les deux causes d'échec du démon
# -------------------------------------------------------------------
titre "Le démon ne répond pas"

lancer "" "Cannot connect to the Docker daemon at unix:///var/run/docker.sock. Is the docker daemon running?" 1
assert_code 1 "$CODE" "un démon muet rend 1"
assert_contient "$SORTIE" "ne répond pas" "le message nomme le démon"
assert_absent "$SORTIE" "groupe docker" "et ne renvoie pas au groupe docker, qui n'y changerait rien"
assert_absent "$SORTIE" "Cannot connect" "le message brut du client ne filtre pas à l'écran"
assert_absent "$SORTIE" "Aucun conteneur" "aucun inventaire n'est affiché"

titre "La socket existe, l'utilisateur n'y a pas droit"

lancer "" 'permission denied while trying to connect to the Docker daemon socket at unix:///var/run/docker.sock: Get "http://%2Fvar%2Frun%2Fdocker.sock/v1.24/containers/json": dial unix /var/run/docker.sock: connect: permission denied' 1
assert_code 1 "$CODE" "un refus d'accès rend 1, comme les deux autres causes"
assert_contient "$SORTIE" "groupe docker" "le message nomme l'appartenance au groupe docker"
assert_contient "$SORTIE" "usermod" "et donne la commande qui répare"
assert_absent "$SORTIE" "ne répond pas" "il ne se fond pas dans le message du démon muet"
assert_absent "$SORTIE" "permission denied" "le message brut du client ne filtre pas"

# -------------------------------------------------------------------
# Inventaire
# -------------------------------------------------------------------
titre "Inventaire — les conteneurs en cours d'exécution"

lancer "$ACTIFS" "" 0
assert_code 0 "$CODE" "l'inventaire rend 0"
assert_contient "$SORTIE" "NOM" "l'en-tête nomme les colonnes"
assert_contient "$SORTIE" "IDENTIFIANT" "y compris l'identifiant"
assert_contient "$SORTIE" "RESEAUX" "et les réseaux"
assert_contient "$SORTIE" "collecteur-de-metriques-du-site-principal" "le nom est affiché en entier"
assert_contient "$SORTIE" "registre.exemple.net/equipe/api:2.14.0" "l'image est affichée en entier"
assert_contient "$SORTIE" "Up 3 hours" "l'état annoncé par Docker est repris tel quel"
assert_contient "$SORTIE" "9f8e7d6c5b4a" "l'identifiant court est affiché"
assert_contient "$SORTIE" "frontend,backend,supervision" "les trois réseaux sont affichés en entier"
assert_absent "$SORTIE" "archive" "un conteneur arrêté n'apparaît pas sans --all"
assert_absent "$SORTIE" "Exited" "ni son état"
assert_absent "$SORTIE" "Conteneurs arrêtés" "ni la section qui les porte"

# Aucune troncature : la liste de ports est reprise d'un bout à l'autre.
assert_contient "$SORTIE" "0.0.0.0:8080->80/tcp, 0.0.0.0:8443->443/tcp, :::8080->80/tcp" \
    "la liste de ports est complète"

# Alignement, mesuré sur le rang où commence une colonne. Le nom du premier
# conteneur fait 3 caractères, celui du troisième 39 : sans dimensionnement sur
# le contenu, ces deux lignes ne s'accorderaient sur rien.
ligne_api="$(ligne_de "$SORTIE" "registre.exemple.net/equipe/api:2.14.0")"
ligne_batch="$(ligne_de "$SORTIE" "exemple/batch:0.9")"
ligne_collecte="$(ligne_de "$SORTIE" "exemple/collecteur:1.0")"

assert_egal "$(rang_de "$ligne_api" "0.0.0.0:8080->80/tcp")" \
            "$(rang_de "$ligne_collecte" "127.0.0.1:9100->9100/tcp")" \
            "la colonne des ports commence au même rang sur les deux lignes"
assert_egal "$(rang_de "$ligne_api" "frontend,backend,supervision")" \
            "$(rang_de "$ligne_batch" "lot-interne")" \
            "la colonne des réseaux commence au même rang, même sans port publié"
assert_contient "$ligne_batch" "a1b2c3d4e5f6" \
    "le conteneur sans port publié garde son identifiant dans la bonne colonne"

titre "--all — les conteneurs arrêtés, dans leur propre section"

lancer "$TOUS" "" 0 --all
assert_code 0 "$CODE" "--all rend 0"
assert_contient "$SORTIE" "Conteneurs en cours d'exécution" "les actifs ont leur section"
assert_contient "$SORTIE" "Conteneurs arrêtés" "les arrêtés ont la leur"
assert_contient "$SORTIE" "Up 3 hours" "les actifs restent affichés"
assert_contient "$SORTIE" "Exited (0) 2 days ago" "l'état de l'arrêté est repris tel quel"

# La place de chacun, et non sa seule présence : ce qui suit l'en-tête des
# arrêtés ne doit porter que des arrêtés.
apres_arretes="${SORTIE#*"Conteneurs arrêtés"}"
assert_contient "$apres_arretes" "archive" "l'arrêté est rangé sous son propre en-tête"
assert_absent "$apres_arretes" "collecteur-de-metriques" "et les actifs n'y descendent pas"

titre "Cas vide — aucune panne, et le script le dit"

lancer "" "" 0
assert_code 0 "$CODE" "aucun conteneur rend 0"
assert_contient "$SORTIE" "Aucun conteneur à afficher" "le script le dit en clair"
assert_contient "$SORTIE" "--all" "et indique comment voir les conteneurs arrêtés"

lancer "" "" 0 --all
assert_code 0 "$CODE" "--all sans aucun conteneur rend 0 lui aussi"
assert_contient "$SORTIE" "Aucun conteneur à afficher" "avec le même aveu"

# -------------------------------------------------------------------
# Lecture seule
# -------------------------------------------------------------------
titre "Lecture seule — ce que la trace des appels prouve"

: > "$TRACE"
lancer "$ACTIFS" "" 0
assert_egal "ps" "$(awk '{print $1}' "$TRACE" | sort -u)" \
    "la seule sous-commande appelée est « ps » : ni rm, ni stop, ni prune"
assert_egal "1" "$(wc -l < "$TRACE" | tr -d ' ')" \
    "un seul appel à docker pour un inventaire, comme l'exige la fiche"

: > "$TRACE"
lancer "$TOUS" "" 0 --all
assert_contient "$(cat "$TRACE")" "--all" \
    "--all change le drapeau passé à « docker ps »"
assert_egal "1" "$(wc -l < "$TRACE" | tr -d ' ')" \
    "et non le nombre d'appels"

titre "Lecture seule — rien n'est écrit sur la machine"

avant="$(find /etc /var/lib -maxdepth 2 -newer "$CIBLE" 2>/dev/null | sort)"
lancer "$TOUS" "" 0 --all
apres="$(find /etc /var/lib -maxdepth 2 -newer "$CIBLE" 2>/dev/null | sort)"
assert_egal "$avant" "$apres" "aucun fichier de /etc ni de /var/lib n'a été touché"

titre "Le répertoire courant n'a pas d'importance"

SORTIE="$(cd /tmp && STUB_SORTIE="$ACTIFS" TRACE="$TRACE" PATH="$BAC:$PATH" \
    bash "$CIBLE" 2>&1)" && code=0 || code=$?
assert_code 0 "$code" "le script s'exécute depuis /tmp"
assert_contient "$SORTIE" "registre.exemple.net/equipe/api:2.14.0" \
    "et produit le même inventaire"

bilan "TASK-033 / list-containers.sh"
