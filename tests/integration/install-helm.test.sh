#!/usr/bin/env bash
# tests/integration/install-helm.test.sh — Kubernetes/Installation/install-helm.sh.
# AUCUNE INSTALLATION RÉELLE : un faux curl dépose un faux get-helm-4, qui pose
# lui-même le faux helm — comme l'installateur officiel pose le binaire.
_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_dir/lib/common.sh" ] && [ "$_dir" != "/" ]; do _dir="$(dirname "$_dir")"; done
source "$_dir/lib/common.sh"
source "$SCRIPTS_ROOT/tests/lib/assert.sh"

CIBLE="$SCRIPTS_ROOT/Kubernetes/Installation/install-helm.sh"
# get-helm-4 écrit dans /usr/local/bin : hors d'un conteneur jetable, il poserait
# un vrai Helm sur la machine. Même garde que install-k3s.test.sh.
if [ ! -e /.dockerenv ]; then
    saute_indisponible "install-helm.sh" "hors conteneur : /usr/local/bin/helm ne serait pas jetable"
    bilan "TASK-063 / install-helm.sh"
fi
BAC="$(mktemp -d)"; export BAC
trap 'rm -rf "$BAC"' EXIT

faux() { cat > "$BAC/$1"; chmod +x "$BAC/$1"; }
# Faux helm, en modèle : c'est l'installateur qui le met en place.
faux helm.modele <<'EOF'
#!/bin/sh
echo "$*" >> "$BAC/helm-appels"
[ -z "${HELM_MUET:-}" ] || exit 1
case "$*" in version*) echo "${HELM_AFFICHEE:-v4.0.0+g3fc9f4b}"; exit 0 ;; esac
exit 1
EOF
# Faux curl : il dépose l'installateur, qui dit d'où il a été exécuté et ce que
# l'environnement lui a transmis, puis pose le faux helm. Aucun octet du réseau.
# L'installateur officiel est du bash : celui-ci porte un bashisme et sa trace
# BASH_VERSION, pour que « sh <temporaire> » se voie au lieu de passer.
faux curl <<'EOF'
#!/bin/sh
echo "curl $*" >> "$BAC/curl-appels"
[ -z "${CURL_ECHEC:-}" ] || exit 7
cible=""; while [ $# -gt 0 ]; do if [ "$1" = "-o" ]; then shift; cible="$1"; fi; shift; done
cat > "$cible" <<'INSTALLATEUR'
[[ -n "$BASH_VERSION" ]] || exit 3
printf '%s\n' "$BASH_VERSION" > "$BAC/installateur-bash"
printf '%s\n' "$0" > "$BAC/installateur-appele"
printf '%s\n' "$*" > "$BAC/installateur-args"
printf '%s\n' "${VERIFY_CHECKSUM:-aucune}" "${USE_SUDO:-aucune}" "${HELM_INSTALL_DIR:-aucune}" \
    "${BINARY_NAME:-aucune}" "${DESIRED_VERSION:-aucune}" "${DEBUG:-aucune}" > "$BAC/installateur-env"
cp "$BAC/helm.modele" "$BAC/helm"; chmod +x "$BAC/helm"
exit "${INSTALLATEUR_CODE:-0}"
INSTALLATEUR
EOF
# Faux sudo en tête de PATH, journal CUMULATIF — « neuf » ne l'efface pas : vide
# après tous les cas d'installation, il prouve qu'install-helm.sh n'appelle
# jamais sudo lui-même, l'élévation restant celle de get-helm-4. Faux openssl,
# pour que require_cmd trouve l'outil.
printf '#!/bin/sh\ntouch "%s/sudo-appele"\nexit 0\n' "$BAC" > "$BAC/sudo"; chmod +x "$BAC/sudo"
printf '#!/bin/sh\nexit 0\n' > "$BAC/openssl"; chmod +x "$BAC/openssl"

CHEMIN="$BAC:$PATH"
neuf() {   # machine d'essai à zéro : aucun helm posé, appels remis à zéro
    rm -f "$BAC/helm" "$BAC/installateur-appele" "$BAC/installateur-args" \
          "$BAC/installateur-env" "$BAC/installateur-bash"
    : > "$BAC/curl-appels"; : > "$BAC/helm-appels"; }
pose() { if [ -e "$1" ]; then echo "présente"; else echo "absente"; fi; }
EXTRA=(); codes=""
lancer() {
    sortie="$(env TMPDIR="$BAC" PATH="$CHEMIN" "${EXTRA[@]}" timeout 30 bash "$CIBLE" "$@" </dev/null 2>&1)" \
        && CODE=0 || CODE=$?
    codes="$codes $CODE"; }
# Réponse tapée sous un pseudo-terminal, sans --yes — le terrain de la décision
# 45. EXTRA comme pour « lancer », pour y éprouver un environnement hérité.
lancer_pty() {
    sortie="$(printf '%s\n' "$1" | env TMPDIR="$BAC" PATH="$CHEMIN" "${EXTRA[@]}" \
        timeout 30 script -qec "bash $CIBLE" /dev/null 2>&1)" && CODE=0 || CODE=$?
    codes="$codes $CODE"; }

titre "Codes d'usage"
sortie="$(timeout 30 bash "$CIBLE" --help 2>&1)" && code=0 || code=$?
assert_code 0 "$code" "--help rend 0"
assert_contient "$sortie" "Debian 12" "--help nomme les systèmes supportés"
assert_contient "$sortie" "mot de passe" "--help dit que le sudo de get-helm-4 réclame un terminal"
assert_contient "$sortie" "2  option" "--help documente les codes de retour"
timeout 30 bash "$CIBLE" --option-inexistante >/dev/null 2>&1 && code=0 || code=$?
assert_code 2 "$code" "une option inconnue rend 2"

titre "Cibles hors décision 14"
EXTRA=(OS_ID=fedora OS_VERSION=41 OS_ARCH=x86_64); lancer --dry-run; EXTRA=()
assert_code 1 "$CODE" "une distribution hors cibles est refusée en 1"
assert_contient "$sortie" "fedora" "le refus nomme ce qui a été détecté"
EXTRA=(OS_ID=debian OS_VERSION=12 OS_ARCH=riscv64); lancer --dry-run; EXTRA=()
assert_code 1 "$CODE" "une architecture hors cibles est refusée en 1"
assert_contient "$sortie" "riscv64" "le refus nomme l'architecture détectée"
assert_egal "" "$(cat "$BAC/curl-appels")" "aucun refus n'a rien téléchargé"

titre "curl et openssl requis"
# Ni curl ni openssl ici : le harnais seul, pour que require_cmd les réclame.
mkdir -p "$BAC/sans-outils"
for c in bash sh timeout id mkdir basename dirname date uname cat tee; do
    ln -sf "$(command -v "$c")" "$BAC/sans-outils/$c"
done
sortie="$(TMPDIR="$BAC" PATH="$BAC/sans-outils" timeout 30 bash "$CIBLE" --yes </dev/null 2>&1)" && code=0 || code=$?
assert_code 1 "$code" "sans curl ni openssl, le script rend 1"
assert_contient "$sortie" "Commande(s) requise(s) introuvable(s) : curl openssl" \
    "c'est le message de require_cmd, et il nomme les deux outils"

titre "Helm déjà présent — constat, et rien d'autre"
neuf; cp "$BAC/helm.modele" "$BAC/helm"
lancer --yes
assert_code 0 "$CODE" "une installation en place rend 0"
assert_contient "$sortie" "déjà installé" "le script constate au lieu de réinstaller"
assert_contient "$sortie" "v4.0.0+g3fc9f4b" "la version en place est affichée"
assert_absent  "$sortie" "Changements prévus" "aucun changement n'est même envisagé"
assert_egal "" "$(cat "$BAC/curl-appels")" "et rien n'est téléchargé"

titre "--dry-run : le préflight et la commande, sans rien télécharger"
neuf
lancer --dry-run
assert_code 0 "$CODE" "--dry-run rend 0"
assert_contient "$sortie" "Changements prévus" "le résumé des changements est affiché"
assert_contient "$sortie" "dernière publiée" "sans SRV_HELM_VERSION, la dernière publiée est annoncée"
assert_contient "$sortie" "curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-4" \
    "la commande prévue est affichée, en HTTPS"
assert_egal "" "$(cat "$BAC/curl-appels")" "aucun appel à curl : le préflight reste local"
neuf; EXTRA=(SRV_HELM_VERSION=v4.1.0); lancer --dry-run; EXTRA=()
assert_code 0 "$CODE" "--dry-run avec version épinglée rend 0"
assert_contient "$sortie" "v4.1.0 (épinglée)" "le résumé affiche la version épinglée"
assert_contient "$sortie" "bash <temporaire> --version v4.1.0" "et l'épingle est passée à l'installateur, annoncé sous bash"

titre "Hors terminal et sans --yes, le script refuse avant de télécharger"
neuf
lancer
assert_code 1 "$CODE" "sans terminal et sans --yes, le script rend 1"
assert_contient "$sortie" "--yes" "le message nomme l'option qui débloque la situation"
assert_absent  "$sortie" "Échec (code" "aucune ligne du trap ERR : le refus est délibéré"
assert_egal "" "$(cat "$BAC/curl-appels")" "rien n'est téléchargé"
# Décision 45 : un ASSUME_YES venu du parent ne vaut pas --yes.
neuf; EXTRA=(ASSUME_YES=true); lancer; EXTRA=()
assert_code 1 "$CODE" "un ASSUME_YES hérité, sans --yes, rend 1"
assert_egal "absente" "$(pose "$BAC/helm")" "et rien n'est installé"
# Décision 45 sous terminal, cette fois : la question EST posée, donc seule la
# remise à false d'ASSUME_YES fait décider la réponse.
neuf; EXTRA=(ASSUME_YES=true); lancer_pty n; EXTRA=()
assert_code 1 "$CODE" "sous terminal, un ASSUME_YES hérité ne confirme pas à la place du --yes"
assert_contient "$sortie" "Installation abandonnée" "c'est la réponse « n » qui décide"
assert_egal "" "$(cat "$BAC/curl-appels")" "et rien n'est téléchargé"
# Sous pseudo-terminal, la question est posée et la réponse est lue.
neuf; lancer_pty n
assert_code 1 "$CODE" "une réponse « n » sous terminal abandonne en 1"
assert_contient "$sortie" "Installation abandonnée" "le refus est celui de confirm"
assert_egal "" "$(cat "$BAC/curl-appels")" "et rien n'est téléchargé"
neuf; lancer_pty o
assert_code 0 "$CODE" "une réponse « o » sous terminal installe, en 0"
assert_contient "$sortie" "[SUCCESS]" "et l'installation est déclarée réussie"

titre "Installation complète — faux curl, installateur et helm"
neuf
EXTRA=(VERIFY_CHECKSUM=false USE_SUDO=false HELM_INSTALL_DIR="$BAC/ailleurs" \
       BINARY_NAME=autre DESIRED_VERSION=v9.9.9 DEBUG=true)
lancer --yes
EXTRA=()
assert_code 0 "$CODE" "installation complète : rend 0"
chemin="$(cat "$BAC/installateur-appele" 2>/dev/null)"
assert_contient "$chemin" "$BAC/tmp." "l'installateur a été exécuté depuis un fichier temporaire"
assert_egal "absente" "$(pose "$chemin")" "et ce temporaire est retiré en sortant"
assert_contient "$(cat "$BAC/curl-appels")" "--proto =https" "le téléchargement impose HTTPS"
assert_contient "$(cat "$BAC/curl-appels")" "--tlsv1.2" "et TLS 1.2 au moins"
assert_contient "$(cat "$BAC/curl-appels")" "-o $BAC/tmp." "get-helm-4 part dans un temporaire, jamais dans un tube"
assert_egal "$(printf 'true\naucune\naucune\naucune\naucune\naucune')" "$(cat "$BAC/installateur-env")" \
    "VERIFY_CHECKSUM reposée à true ; USE_SUDO, HELM_INSTALL_DIR, BINARY_NAME, DESIRED_VERSION et DEBUG neutralisées"
assert_egal "version --short" "$(cat "$BAC/helm-appels")" \
    "seule « helm version --short » est appelée : ni dépôt de charts, ni plugin"
assert_non_vide "$(cat "$BAC/installateur-bash")" \
    "l'installateur tourne sous bash : BASH_VERSION y est renseignée"
assert_contient "$sortie" "Helm v4.0.0+g3fc9f4b est installé" "le succès nomme la version relue"

titre "Version relue après installation"
neuf; EXTRA=(SRV_HELM_VERSION=v4.1.0); lancer --yes; EXTRA=()
assert_code 1 "$CODE" "une version relue différente de l'épinglée rend 1"
assert_contient "$sortie" "v4.0.0+g3fc9f4b" "le message nomme la version relue"
assert_contient "$sortie" "différente de celle épinglée" "et dit pourquoi elle ne convient pas"
neuf; EXTRA=(SRV_HELM_VERSION=v4.1.0 HELM_AFFICHEE=v4.1.0+gabcdef); lancer --yes; EXTRA=()
assert_code 0 "$CODE" "la même version, à la métadonnée de construction près, rend 0"
assert_contient "$(cat "$BAC/installateur-args")" "--version v4.1.0" "l'épingle est transmise à l'installateur"
neuf; EXTRA=(HELM_MUET=1); lancer --yes; EXTRA=()
assert_code 1 "$CODE" "une version relue illisible rend 1"
assert_contient "$sortie" "n'est pas prouvée" "le message dit ce qui n'est pas prouvé"

titre "Téléchargement et installateur en échec"
neuf; EXTRA=(CURL_ECHEC=1); lancer --yes; EXTRA=()
assert_code 1 "$CODE" "un téléchargement en échec rend 1"
assert_contient "$sortie" "Téléchargement de get-helm-4 en échec" "le message nomme l'étape"
assert_egal "absente" "$(pose "$BAC/installateur-appele")" "aucun installateur n'a été exécuté"
neuf; EXTRA=(INSTALLATEUR_CODE=7); lancer --yes; EXTRA=()
assert_code 1 "$CODE" "un installateur qui échoue rend 1"
assert_contient "$sortie" "get-helm-4 a échoué" "le message nomme l'installateur"

titre "Ce que le script ne fait jamais"
assert_egal "0" "$(grep -c require_root "$CIBLE" || true)" "aucun require_root : l'élévation est celle de get-helm-4"
# Faux sudo en tête de PATH, journal cumulatif que « neuf » n'efface pas : vide
# après tous les cas d'installation, il prouve qu'install-helm.sh n'appelle
# jamais sudo lui-même — l'élévation reste celle de get-helm-4.
assert_egal "absente" "$(pose "$BAC/sudo-appele")" "install-helm.sh n'appelle jamais sudo lui-même"
cas2="non"; case "$codes" in *" 2"*) cas2="oui" ;; esac
assert_egal "non" "$cas2" "aucun chemin éprouvé ne rend 2 : le 2 reste réservé à l'usage"

bilan "TASK-063 / install-helm.sh"
