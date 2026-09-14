#!/usr/bin/env bash
# tests/integration/install-docker.test.sh — Docker/Installation/install-docker.sh.
#
# TASK-029. AUCUNE INSTALLATION RÉELLE : les chemins modifiants sont éprouvés
# par de faux apt-get, curl, systemctl, dpkg-query et docker en tête de PATH.
# Le --dry-run, lui, s'exécute tel quel — il n'écrit rien par contrat.

# shellcheck disable=SC2016
# Les corps des faux binaires sont écrits entre apostrophes : leurs $ appartiennent
# au faux programme, qui s'exécute plus tard, et non à ce fichier.

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
assert_egal "0" "$(grep -c 'bookworm\|jammy\|noble' "$CIBLE" || true)" \
    "aucun nom de code de distribution n'apparaît dans le source du script"

titre "Système non supporté — refus avant toute action"

sortie="$(OS_ID=fedora OS_VERSION=41 OS_ARCH=x86_64 bash "$CIBLE" --dry-run 2>&1)" && code=0 || code=$?
assert_code 1 "$code" "une distribution hors cibles est refusée en 1"
assert_contient "$sortie" "fedora" "le refus nomme ce qui a été détecté"

sortie="$(OS_ID=debian OS_VERSION=12 OS_ARCH=riscv64 bash "$CIBLE" --dry-run 2>&1)" && code=0 || code=$?
assert_code 1 "$code" "une architecture hors cibles est refusée en 1"
assert_contient "$sortie" "riscv64" "le refus nomme l'architecture détectée"

faux uname 'case "$1" in -m) echo x86_64 ;; -r) echo 3.2.0-4-amd64 ;; *) echo Linux ;; esac'
sortie="$(PATH="$BAC:$PATH" bash "$CIBLE" --dry-run 2>&1)" && code=0 || code=$?
assert_code 1 "$code" "un noyau antérieur à 3.10 est refusé en 1 (contraste : le vrai noyau passe le --dry-run plus haut)"
assert_contient "$sortie" "3.2.0" "le refus nomme le noyau détecté"
rm -f "$BAC/uname"

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

titre "Chemins modifiants — faux apt-get, curl, systemctl, dpkg-query et docker"

# Ces cas écrivent réellement la clé et le dépôt : seulement sur un système
# jetable, et seulement s'ils n'y sont pas déjà.
LISTE=/etc/apt/sources.list.d/docker.list
CLE=/etc/apt/keyrings/docker.asc
if [ ! -e /.dockerenv ] || [ -e "$LISTE" ] || [ -e "$CLE" ]; then
    saute_indisponible "chemins modifiants" "système non jetable, ou dépôt Docker déjà présent"
    bilan "TASK-029 / install-docker.sh"
fi
trap 'rm -rf "$BAC"; rm -f "$LISTE" "$CLE"' EXIT
export APT_LOG="$BAC/apt.log" APT_N="$BAC/apt.n" SYSTEMCTL_LOG="$BAC/systemctl.log"

faux dpkg-query 'case "$*" in *docker.io*) echo "install ok installed" ;; *) exit 1 ;; esac'
faux apt-get 'echo "${DEBIAN_FRONTEND:-} $*" >> "$APT_LOG"
if [ "$1" = update ]; then
    n=$(( $(cat "$APT_N" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$APT_N"
    [ "$n" != "${APT_UPDATE_ECHEC_AU:-0}" ] || exit 100
fi
exit 0'
faux curl 'while [ $# -gt 0 ]; do [ "$1" = -o ] && echo "CLE-FACTICE" > "$2"; shift; done
[ "${CURL_ECHEC:-0}" = 0 ]'
faux systemctl 'echo "$*" >> "$SYSTEMCTL_LOG"'
faux docker 'case "$*" in "--version") echo "Docker version 28.5.2, build aaa" ;;
"compose version --short") echo 2.39.1 ;; "buildx version") echo "github.com/docker/buildx v0.17.1" ;; *) exit 0 ;; esac'

sortie="$(PATH="$BAC:$PATH" bash "$CIBLE" --yes 2>&1)" && code=0 || code=$?
assert_code 0 "$code" "installation complète avec conflit : rend 0"
assert_contient "$(cat "$APT_LOG")" "noninteractive remove -y docker.io" "le conflit est retiré, en mode non interactif"
assert_contient "$(cat "$APT_LOG")" "install -y docker-ce docker-ce-cli containerd.io" "les paquets officiels sont installés"
assert_contient "$(cat "$SYSTEMCTL_LOG")" "enable docker" "le service est activé"
assert_contient "$(cat "$SYSTEMCTL_LOG")" "start docker"  "le service est démarré"
assert_contient "$(cat "$LISTE" 2>/dev/null)" "signed-by=$CLE" "le dépôt référence la clé par signed-by"
assert_egal "CLE-FACTICE" "$(cat "$CLE" 2>/dev/null)" "la clé est en place"
assert_contient "$sortie" "0.17.1" "la vérification finale lit la version de Buildx"

rm -f "$LISTE" "$CLE" "$APT_N"
sortie="$(APT_UPDATE_ECHEC_AU=2 PATH="$BAC:$PATH" bash "$CIBLE" --yes 2>&1)" && code=0 || code=$?
assert_code 1 "$code" "apt-get update en échec après ajout du dépôt : rend 1"
assert_absent "$(ls /etc/apt/sources.list.d/)" "docker.list" "le dépôt inutilisable est retiré"
assert_absent "$(ls /etc/apt/keyrings/ 2>/dev/null)" "docker.asc" "la clé qu'il venait de poser est retirée"
assert_contient "$sortie" "dépôt retiré" "le message dit ce qui a été défait"

rm -f "$APT_N"
sortie="$(CURL_ECHEC=1 PATH="$BAC:$PATH" bash "$CIBLE" --yes 2>&1)" && code=0 || code=$?
assert_code 1 "$code" "clé irrécupérable : rend 1"
assert_absent "$(ls /etc/apt/keyrings/ 2>/dev/null)" "docker.asc" "aucune clé tronquée n'est mise en place"
assert_absent "$(ls /etc/apt/sources.list.d/)" "docker.list" "aucun dépôt n'est écrit sans clé"

bilan "TASK-029 / install-docker.sh"
