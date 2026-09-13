#!/usr/bin/env bash
# tests/integration/install-docker.test.sh — Docker/Installation/install-docker.sh.
#
# TASK-029. AUCUNE INSTALLATION RÉELLE : les chemins modifiants sont éprouvés
# par de faux apt-get, curl, systemctl, dpkg-query et docker en tête de PATH.
# Le --dry-run, lui, s'exécute tel quel — il n'écrit rien par contrat.

_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_dir/lib/common.sh" ] && [ "$_dir" != "/" ]; do _dir="$(dirname "$_dir")"; done
source "$_dir/lib/common.sh"
source "$SCRIPTS_ROOT/tests/lib/assert.sh"

CIBLE="$SCRIPTS_ROOT/Docker/Installation/install-docker.sh"
BAC="$(mktemp -d)"
trap 'rm -rf "$BAC"' EXIT

faux() { printf '#!/bin/sh\n%s\n' "$2" > "$BAC/$1"; chmod +x "$BAC/$1"; }

titre "Codes d'usage"

bash "$CIBLE" --help >/dev/null 2>&1 && code=0 || code=$?
assert_code 0 "$code" "--help rend 0"

sortie="$(bash "$CIBLE" --help 2>&1)"
assert_contient "$sortie" "Debian 12"  "--help nomme les systèmes supportés"
assert_contient "$sortie" "keyrings"   "--help dit ce qui est écrit sur la machine"
assert_contient "$sortie" "2  option"  "--help documente les codes de retour"

bash "$CIBLE" --option-inexistante >/dev/null 2>&1 && code=0 || code=$?
assert_code 2 "$code" "une option inconnue rend 2"

titre "--dry-run : le résumé sans la moindre écriture"

avant="$(find /etc/apt /var/lib/dpkg -maxdepth 2 -newer "$CIBLE" 2>/dev/null | sort)"
sortie="$(bash "$CIBLE" --dry-run 2>&1)" && code=0 || code=$?
apres="$(find /etc/apt /var/lib/dpkg -maxdepth 2 -newer "$CIBLE" 2>/dev/null | sort)"

assert_code 0 "$code" "--dry-run rend 0 sur une machine sans Docker"
assert_egal "$avant" "$apres" "--dry-run n'a touché ni /etc/apt ni la base dpkg"
assert_absent "$(ls /etc/apt/sources.list.d/ 2>/dev/null)" "docker.list" "aucun dépôt n'a été déposé"
assert_contient "$sortie" "docker-ce docker-ce-cli" "le résumé nomme les paquets"
assert_contient "$sortie" "download.docker.com"     "le résumé nomme le dépôt"
assert_contient "$sortie" "dry-run"                 "le mode est annoncé"

titre "Le nom de code vient de la machine, il n'est pas écrit en dur"

attendu="$( . /etc/os-release && echo "$VERSION_CODENAME" )"
assert_contient "$sortie" "$attendu" "le dépôt annoncé porte le nom de code lu dans /etc/os-release"
assert_absent "$(grep -c 'bookworm\|jammy\|noble' "$CIBLE" || true)" "1" \
    "aucun nom de code de distribution n'apparaît dans le source du script"

titre "Système non supporté — refus avant toute action"

faux os-release ''
printf 'ID=fedora\nVERSION_ID=41\nVERSION_CODENAME=heisenbug\n' > "$BAC/os-release"
sortie="$(OS_ID=fedora OS_VERSION=41 OS_ARCH=x86_64 bash "$CIBLE" --dry-run 2>&1)" && code=0 || code=$?
assert_code 1 "$code" "une distribution hors cibles est refusée en 1"
assert_contient "$sortie" "fedora" "le refus nomme ce qui a été détecté"

sortie="$(OS_ID=debian OS_VERSION=12 OS_ARCH=riscv64 bash "$CIBLE" --dry-run 2>&1)" && code=0 || code=$?
assert_code 1 "$code" "une architecture hors cibles est refusée en 1"
assert_contient "$sortie" "riscv64" "le refus nomme l'architecture détectée"

titre "Installation déjà en place — constat, et rien d'autre"

faux docker 'case "$*" in "--version") echo "Docker version 28.5.2, build aaa" ;; *) exit 0 ;; esac'
faux dpkg-query 'case "$*" in *docker-ce*) echo "install ok installed" ;; *) exit 1 ;; esac'
sortie="$(PATH="$BAC:$PATH" bash "$CIBLE" 2>&1)" && code=0 || code=$?
assert_code 0 "$code" "une installation en place rend 0"
assert_contient "$sortie" "déjà installé" "le script constate au lieu de réinstaller"
assert_contient "$sortie" "28.5.2"        "la version en place est affichée"
assert_absent   "$sortie" "Changements prévus" "aucun changement n'est même envisagé"

titre "Garde de contraste — sans le faux dpkg-query, le script ne s'arrête pas là"

faux dpkg-query 'exit 1'
sortie="$(PATH="$BAC:$PATH" bash "$CIBLE" --dry-run 2>&1)" && code=0 || code=$?
assert_code 0 "$code" "sans docker-ce installé, le script poursuit jusqu'au résumé"
assert_contient "$sortie" "Changements prévus" "et il affiche bien les changements prévus"

titre "Hors terminal et sans --yes : le script refuse avant de poser sa question"

# Sans [ -t 0 ], « confirm » lirait un stdin fermé : errexit tuerait le script
# et le trap ERR écrirait une ligne qui ne désigne rien (motif de TASK-018).
faux apt-get 'exit 0'
faux curl 'exit 0'
faux systemctl 'exit 0'
sortie="$(PATH="$BAC:$PATH" bash "$CIBLE" </dev/null 2>&1)" && code=0 || code=$?
assert_code 1 "$code" "sans terminal et sans --yes, le script rend 1"
assert_contient "$sortie" "--yes" "le message nomme l'option qui débloque la situation"
assert_absent   "$sortie" "Échec (code" "aucune ligne du trap ERR : le refus est délibéré, pas un plantage"

saute_par_nature "l'installation réelle et le retrait des paquets conflictuels" \
    "poser docker-ce dans le conteneur de test supposerait un réseau vers download.docker.com et un dpkg réel ; AGENTS.md §8 l'exclut. Les chemins qui y mènent sont éprouvés jusqu'à la confirmation, et le --dry-run couvre le résumé des changements"

bilan "TASK-029 / install-docker.sh"
