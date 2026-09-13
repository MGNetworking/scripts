#!/usr/bin/env bash
# tests/integration/check-docker.test.sh — Docker/Diagnostics/check-docker.sh.
#
# TASK-031. Le conteneur de test n'a pas de démon Docker et n'en aura pas : les
# trois issues du script sont éprouvées par un faux « docker » en tête de PATH.
#
# Chaque cas à faux « docker » porte sa GARDE DE CONTRASTE : « docker » est
# absent par défaut ici, donc un cas « Docker absent » serait vert sans rien
# prouver. La garde vérifie que le même appel, avec un faux binaire qui répond,
# donne un verdict différent.

_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_dir/lib/common.sh" ] && [ "$_dir" != "/" ]; do _dir="$(dirname "$_dir")"; done
source "$_dir/lib/common.sh"
source "$SCRIPTS_ROOT/tests/lib/assert.sh"

CIBLE="$SCRIPTS_ROOT/Docker/Diagnostics/check-docker.sh"
BAC="$(mktemp -d)"
trap 'rm -rf "$BAC"' EXIT

# Installe un faux « docker » dans $BAC. $1 : le corps du case, sans le case.
stub() { printf '#!/bin/sh\ncase "$*" in\n%s\nesac\n' "$1" > "$BAC/docker"; chmod +x "$BAC/docker"; }

STUB_SAIN='"--version") echo "Docker version 28.5.2, build aaaaaaa" ;;
  "info --format"*) echo "28.5.2|overlay2|/var/lib/docker" ;;
  "compose version --short") echo "2.39.1" ;;
  "buildx version") echo "github.com/docker/buildx v0.17.1" ;;
  *) exit 1 ;;'

titre "Docker absent — le cas d'usage principal"

sortie="$(bash "$CIBLE" 2>&1)" && code=0 || code=$?
assert_code 1 "$code" "un environnement sans docker n'est pas exploitable"
assert_contient "$sortie" "Client Docker"   "la rubrique client est affichée malgré tout"
assert_contient "$sortie" "Socket du démon" "la rubrique socket est affichée malgré tout"
assert_contient "$sortie" "Démon Docker"    "la rubrique démon est affichée malgré tout"
assert_contient "$sortie" "non disponible"  "les informations manquantes sont nommées, pas tues"
assert_absent   "$sortie" "command not found" "aucun message brut du shell ne filtre"
assert_absent   "$sortie" "No such file"      "aucun message brut du shell ne filtre"

titre "Environnement sain — la garde de contraste de tous les cas suivants"

stub "$STUB_SAIN"
sortie="$(PATH="$BAC:$PATH" bash "$CIBLE" 2>&1)" && code=0 || code=$?
assert_code 0 "$code" "client présent et démon qui répond : exploitable"
assert_contient "$sortie" "28.5.2"     "la version du moteur est extraite de docker info"
assert_contient "$sortie" "overlay2"   "le pilote de stockage est extrait de docker info"
assert_contient "$sortie" "/var/lib/docker" "le répertoire de données est extrait de docker info"
assert_contient "$sortie" "2.39.1"     "la version du plugin Compose est rapportée"
assert_contient "$sortie" "v0.17.1"    "la version de Buildx est rapportée"

titre "Client présent, démon injoignable"

stub '"--version") echo "Docker version 28.5.2, build aaaaaaa" ;;
  *) echo "Cannot connect to the Docker daemon at unix:///var/run/docker.sock." >&2; exit 1 ;;'
sortie="$(PATH="$BAC:$PATH" bash "$CIBLE" 2>&1)" && code=0 || code=$?
assert_code 1 "$code" "un démon muet rend l'environnement non exploitable"
assert_contient "$sortie" "le démon ne répond pas" "le verdict nomme le démon"
assert_absent   "$sortie" "le client « docker » est absent" "et surtout pas le client, qui est là"
assert_absent   "$sortie" "Cannot connect"  "le message brut de docker ne filtre pas à l'écran"

titre "docker info : stderr ne corrompt pas la ligne de gabarit"

stub '"--version") echo "Docker version 28.5.2, build aaaaaaa" ;;
  "info --format"*) echo "WARNING: bridge-nf-call-iptables is disabled" >&2; echo "28.5.2|overlay2|/var/lib/docker" ;;
  *) exit 1 ;;'
sortie="$(PATH="$BAC:$PATH" bash "$CIBLE" 2>&1)" && code=0 || code=$?
assert_code 0 "$code" "un avertissement sur stderr ne fait pas conclure à un démon mort"
assert_contient "$sortie" "overlay2" "le pilote reste correctement extrait"
assert_absent   "$sortie" "bridge-nf-call" "l'avertissement de docker ne filtre pas à l'écran"

titre "Délai borné — un démon qui ne répond plus ne fige pas le diagnostic"

stub '"--version") echo "Docker version 28.5.2, build aaaaaaa" ;;
  *) sleep 60 ;;'
debut=$SECONDS
sortie="$(PATH="$BAC:$PATH" bash "$CIBLE" 2>&1)" && code=0 || code=$?
ecoule=$(( SECONDS - debut ))
assert_code 1 "$code" "un démon qui ne répond plus rend l'environnement non exploitable"
if [ "$ecoule" -lt 30 ]; then
    ok "la main est rendue en ${ecoule}s, très en deçà des 60s qu'un appel non borné aurait coûtées"
else
    ko "la main est rendue en ${ecoule}s : la borne de temps n'a pas joué"
fi

titre "Codes d'usage"

bash "$CIBLE" --help >/dev/null 2>&1 && code=0 || code=$?
assert_code 0 "$code" "--help rend 0"

bash "$CIBLE" --option-qui-nexiste-pas >/dev/null 2>&1 && code=0 || code=$?
assert_code 2 "$code" "une option inconnue rend 2"

# Le 2 doit être le SEUL cas de 2 : les trois autres chemins d'échec rendent 1,
# ce que les groupes précédents ont déjà affirmé — Docker absent, démon muet et
# délai dépassé sont tous sortis en 1.
ok "le 2 est réservé à l'erreur d'usage : les trois chemins d'échec ci-dessus rendent 1"

titre "Lecture seule"

stub "$STUB_SAIN"
avant="$(find /etc /var/lib -maxdepth 2 -newer "$CIBLE" 2>/dev/null | sort)"
PATH="$BAC:$PATH" bash "$CIBLE" >/dev/null 2>&1 || true
apres="$(find /etc /var/lib -maxdepth 2 -newer "$CIBLE" 2>/dev/null | sort)"
assert_egal "$avant" "$apres" "aucun fichier de /etc ni de /var/lib n'a été touché"

saute_par_nature "le socket présent mais interdit" \
    "le distinguer d'un socket absent demanderait de fabriquer un vrai socket unix appartenant à un autre utilisateur, donc un démon ou CAP_CHOWN. La branche « absent » est éprouvée par tous les cas ci-dessus, le conteneur n'ayant pas de /var/run/docker.sock"

bilan "TASK-031 / check-docker.sh"
