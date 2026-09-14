#!/usr/bin/env bash
# tests/integration/list-containers.test.sh — Docker/Diagnostics/list-containers.sh.
# TASK-033. Le conteneur de test n'a pas de démon Docker : les trois causes
# d'échec sont éprouvées par un faux « docker » en tête de PATH, l'inventaire par
# des réponses tabulées fabriquées, et la lecture seule par la trace des appels.

_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_dir/lib/common.sh" ] && [ "$_dir" != "/" ]; do _dir="$(dirname "$_dir")"; done
source "$_dir/lib/common.sh"
source "$SCRIPTS_ROOT/tests/lib/assert.sh"

BASH_BIN="$(command -v bash)"
CIBLE="$SCRIPTS_ROOT/Docker/Diagnostics/list-containers.sh"
BAC="$(mktemp -d)"
TRACE="$BAC/appels"
trap 'rm -rf "$BAC"' EXIT

# -------------------------------------------------------------------
# Faux docker
# -------------------------------------------------------------------
# Il trace ses arguments, puis rend STUB_SORTIE, STUB_ERREUR et STUB_CODE.
# STUB_DELAI le fait patienter, pour éprouver la borne de temps du script.
cat > "$BAC/docker" <<'STUB'
#!/bin/sh
printf '%s\n' "$*" >> "$TRACE"
[ "${STUB_DELAI:-0}" -gt 0 ] && sleep "$STUB_DELAI"
[ -n "${STUB_SORTIE:-}" ] && printf '%s\n' "$STUB_SORTIE"
[ -n "${STUB_ERREUR:-}" ] && printf '%s\n' "$STUB_ERREUR" >&2
exit "${STUB_CODE:-0}"
STUB
chmod +x "$BAC/docker"

# PATH maîtrisé, SANS docker : la preuve « commande absente » ne dépend donc pas
# de ce que l'image porte, et vaudrait sur une machine qui installerait Docker.
# Le script a besoin de ces quelques binaires ; ceux que l'image n'a pas manquent
# simplement à l'appel, qui échoue alors pour une autre raison, visible.
SANS_DOCKER="$BAC/sans-docker"
mkdir -p "$SANS_DOCKER"
for b in dirname basename mkdir id date sleep timeout; do
    chemin="$(command -v "$b" 2>/dev/null || true)"
    [ -n "$chemin" ] && ln -s "$chemin" "$SANS_DOCKER/$b"
done
CHEMIN="$BAC:$PATH"

# Lance le script. $1 sortie, $2 erreur, $3 code et $4 délai du faux docker, le
# reste : arguments du script. Renseigne SORTIE et CODE — les passer par stdout
# les perdrait dans un sous-shell.
SORTIE=""
CODE=0
lancer() {
    local o="$1" e="$2" c="$3" d="$4"
    shift 4
    SORTIE="$(STUB_SORTIE="$o" STUB_ERREUR="$e" STUB_CODE="$c" STUB_DELAI="$d" \
        TRACE="$TRACE" PATH="$CHEMIN" "$BASH_BIN" "$CIBLE" "$@" 2>&1)" && CODE=0 || CODE=$?
}

# -------------------------------------------------------------------
# Réponses fabriquées
# -------------------------------------------------------------------
# Trois actifs et un arrêté. Les longueurs sont délibérément inégales : nom de 39
# caractères, ports à rallonge, trois réseaux. « batch » n'a AUCUN port publié —
# deux tabulations voisines, le piège du découpage. Les identifiants sont longs :
# l'affichage doit n'en garder que douze caractères.
API=$'api\tregistre.exemple.net/equipe/api:2.14.0\tUp 3 hours\t0.0.0.0:8080->80/tcp, 0.0.0.0:8443->443/tcp, :::8080->80/tcp\tfrontend,backend,supervision\t9f8e7d6c5b4afedcba987654'
BATCH=$'batch\texemple/batch:0.9\tUp 12 minutes\t\tlot-interne\ta1b2c3d4e5f6a1b2c3d4e5f6'
COLLECTE=$'collecteur-de-metriques-du-site-principal\texemple/collecteur:1.0\tRestarting (1) 5 seconds ago\t127.0.0.1:9100->9100/tcp\tsupervision\t112233445566112233445566'
ARRETE=$'archive\texemple/archive:3.1\tExited (0) 2 days ago\t\tlot-interne\tdeadbeef0000deadbeef0000'

TOUS="$API
$BATCH
$COLLECTE
$ARRETE"

# Rang, compté en caractères, auquel commence une valeur dans une ligne : deux
# lignes sont alignées sur une colonne quand ce rang y est le même.
rang_de() {
    local ligne="${1%%"$2"*}"
    printf '%s' "${#ligne}"
}

# -------------------------------------------------------------------
# Aide et erreurs d'usage
# -------------------------------------------------------------------
titre "Aide — lisible alors que docker n'est pas installé"

CHEMIN="$SANS_DOCKER"
lancer "" "" 0 --help
assert_code 0 "$CODE" "--help rend 0 sans consulter le moindre démon"
assert_contient "$SORTIE" "--all" "l'aide documente les options"
assert_contient "$SORTIE" "IDENTIFIANT" "l'aide dit ce que contient chaque colonne"
assert_contient "$SORTIE" "Codes de retour" "l'aide documente les codes de retour"

titre "Docker absent — PATH maîtrisé qui ne porte pas docker"

lancer "" "" 0
assert_code 1 "$CODE" "l'absence de la commande rend 1, jamais 2"
assert_contient "$SORTIE" "introuvable" "le message nomme la dépendance manquante"
assert_absent "$SORTIE" "ne répond pas" "l'absence du client n'est pas confondue avec un démon muet"
assert_absent "$SORTIE" "groupe docker" "ni avec un refus d'accès à la socket"

# Garde de contraste : le même appel, avec un faux docker qui répond, rend 0 et
# produit l'inventaire. Sans elle, ce cas serait vert sans rien prouver.
CHEMIN="$BAC:$PATH"
lancer "$TOUS" "" 0
assert_code 0 "$CODE" "contraste : le même appel, docker présent, rend 0"

titre "Une option inconnue — faute d'usage, et rien d'autre"

lancer "" "" 0 --inconnue
assert_code 2 "$CODE" "une option inconnue rend 2, et aucun préflight n'a eu lieu"
assert_contient "$SORTIE" "[ERROR] Option inconnue" "le message porte [ERROR] et nomme l'option fautive"
assert_absent "$SORTIE" "Usage" "l'aide n'est pas déversée"
assert_egal "1" "$(printf '%s\n' "$SORTIE" | wc -l | tr -d ' ')" \
    "le refus tient sur une seule ligne"

# -------------------------------------------------------------------
# Les trois autres causes d'échec du client
# -------------------------------------------------------------------
titre "Le démon ne répond pas"

lancer "" "Cannot connect to the Docker daemon at unix:///var/run/docker.sock. Is the docker daemon running?" 1
assert_code 1 "$CODE" "un démon muet rend 1"
assert_contient "$SORTIE" "ne répond pas" "le message nomme le démon"
assert_absent "$SORTIE" "groupe docker" "et ne renvoie pas au groupe docker, qui n'y changerait rien"
assert_absent "$SORTIE" "Cannot connect" "le message brut du client ne filtre pas à l'écran"

titre "La socket existe, l'utilisateur n'y a pas droit"

lancer "" 'permission denied while trying to connect to the Docker daemon socket at unix:///var/run/docker.sock: connect: permission denied' 1
assert_code 1 "$CODE" "un refus d'accès rend 1, comme les deux autres causes"
assert_contient "$SORTIE" "groupe docker" "le message nomme l'appartenance au groupe docker"
assert_contient "$SORTIE" "usermod" "et donne la commande qui répare"
assert_absent "$SORTIE" "ne répond pas" "il ne se fond pas dans le message du démon muet"
assert_absent "$SORTIE" "permission denied" "le message brut du client ne filtre pas"

titre "Délai borné — un démon figé ne suspend pas l'inventaire"

debut=$SECONDS
lancer "" "" 0 60
ecoule=$(( SECONDS - debut ))
assert_code 1 "$CODE" "un démon qui ne répond plus rend 1"
assert_contient "$SORTIE" "ne répond pas" "et cette cause-là est nommée"
if [ "$ecoule" -lt 30 ]; then
    ok "la main est rendue en ${ecoule}s, très en deçà des 60s d'un appel non borné"
else
    ko "la main est rendue en ${ecoule}s : la borne de temps n'a pas joué"
fi

# -------------------------------------------------------------------
# Inventaire
# -------------------------------------------------------------------
titre "Inventaire — les conteneurs en cours d'exécution, et eux seuls"

lancer "$TOUS" "" 0
assert_code 0 "$CODE" "l'inventaire rend 0"
assert_contient "$SORTIE" "NOM" "l'en-tête nomme les colonnes"
assert_contient "$SORTIE" "Conteneurs en cours d'exécution" "les actifs ont leur section"
# Le faux docker rend AUSSI un arrêté : c'est donc le filtre du script, et non
# celui du client, qui l'écarte.
assert_absent "$SORTIE" "archive" "un conteneur arrêté n'apparaît pas sans --all"
assert_absent "$SORTIE" "Exited" "ni son état"
assert_absent "$SORTIE" "Conteneurs arrêtés" "ni la section qui les porte"

assert_contient "$SORTIE" "collecteur-de-metriques-du-site-principal" "le nom est affiché en entier"
assert_contient "$SORTIE" "registre.exemple.net/equipe/api:2.14.0" "l'image est affichée en entier"
assert_contient "$SORTIE" "Up 3 hours" "l'état annoncé par Docker est repris tel quel"
assert_contient "$SORTIE" "frontend,backend,supervision" "les trois réseaux sont affichés en entier"
assert_contient "$SORTIE" "0.0.0.0:8080->80/tcp, 0.0.0.0:8443->443/tcp, :::8080->80/tcp" \
    "la liste de ports est complète"
assert_contient "$SORTIE" "9f8e7d6c5b4a" "l'identifiant est ramené à douze caractères"
assert_absent "$SORTIE" "9f8e7d6c5b4afedcba987654" "et l'identifiant complet n'est pas affiché"

# Alignement, mesuré au rang où commence une colonne. Le nom du premier fait 3
# caractères, celui du troisième 39 : sans dimensionnement, rien ne s'accorderait.
ligne_api="$(grep -F "registre.exemple.net/equipe/api:2.14.0" <<< "$SORTIE")"
ligne_batch="$(grep -F "exemple/batch:0.9" <<< "$SORTIE")"
ligne_collecte="$(grep -F "exemple/collecteur:1.0" <<< "$SORTIE")"

assert_egal "$(rang_de "$ligne_api" "0.0.0.0:8080->80/tcp")" \
            "$(rang_de "$ligne_collecte" "127.0.0.1:9100->9100/tcp")" \
            "la colonne des ports commence au même rang sur les deux lignes"
assert_egal "$(rang_de "$ligne_api" "frontend,backend,supervision")" \
            "$(rang_de "$ligne_batch" "lot-interne")" \
            "la colonne des réseaux commence au même rang, même sans port publié"
assert_egal "$(rang_de "$ligne_api" "9f8e7d6c5b4a")" \
            "$(rang_de "$ligne_batch" "a1b2c3d4e5f6")" \
            "l'identifiant du conteneur sans port publié est dans sa colonne"

titre "--all — les conteneurs arrêtés, dans leur propre section"

lancer "$TOUS" "" 0 --all
assert_code 0 "$CODE" "--all rend 0"
assert_contient "$SORTIE" "Conteneurs arrêtés" "les arrêtés ont leur section"
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
lancer "$TOUS" "" 0
assert_egal "ps" "$(awk '{print $1}' "$TRACE" | sort -u)" \
    "la seule sous-commande appelée est « ps » : ni rm, ni stop, ni prune"
assert_egal "1" "$(wc -l < "$TRACE" | tr -d ' ')" \
    "un seul appel à docker pour l'inventaire, comme l'exige la fiche"

: > "$TRACE"
lancer "$TOUS" "" 0 --all
assert_contient "$(cat "$TRACE")" "--all" "--all change le drapeau passé à « docker ps »"
assert_egal "1" "$(wc -l < "$TRACE" | tr -d ' ')" "et non le nombre d'appels"

titre "Le répertoire courant n'a pas d'importance"

SORTIE="$(cd /tmp && STUB_SORTIE="$TOUS" TRACE="$TRACE" PATH="$CHEMIN" \
    "$BASH_BIN" "$CIBLE" 2>&1)" && code=0 || code=$?
assert_code 0 "$code" "le script s'exécute depuis /tmp"
assert_contient "$SORTIE" "registre.exemple.net/equipe/api:2.14.0" "et produit le même inventaire"

bilan "TASK-033 / list-containers.sh"
