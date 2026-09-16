#!/usr/bin/env bash
# tests/integration/install-k3s.test.sh — Linux/K3s/install-k3s.sh.
#
# TASK-051. AUCUNE INSTALLATION RÉELLE : un faux curl dépose un faux installateur,
# qui crée lui-même le faux k3s — comme l'installateur officiel pose le binaire.
# Le diagnostic final est le vrai verify-k3s.sh, qui lit ces faux.
_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_dir/lib/common.sh" ] && [ "$_dir" != "/" ]; do _dir="$(dirname "$_dir")"; done
source "$_dir/lib/common.sh"
source "$SCRIPTS_ROOT/tests/lib/assert.sh"

CIBLE="$SCRIPTS_ROOT/Linux/K3s/install-k3s.sh"
JOURNAL="/var/log/mgnetworking/install-k3s.log"
# Ce fichier écrit puis efface /var/lib/rancher/k3s : hors d'un conteneur
# jetable, il détruirait un vrai cluster. Même garde que install-docker.test.sh.
if [ ! -e /.dockerenv ]; then
    saute_indisponible "install-k3s.sh" "hors conteneur : /var/lib/rancher/k3s ne serait pas jetable"
    bilan "TASK-051 / install-k3s.sh"
fi
BAC="$(mktemp -d)"
export BAC
trap 'rm -rf "$BAC" /var/lib/rancher/k3s' EXIT

faux() { cat > "$BAC/$1"; chmod +x "$BAC/$1"; }
# Faux k3s, en modèle : c'est l'installateur qui le met en place.
faux k3s.modele <<'EOF'
#!/bin/sh
[ "${K3S_MUET:-0}" = 0 ] || exit 1
case "$*" in
  --version) echo "k3s version v1.30.5+k3s1 (aaaaaaa)" ;;
  *"kubectl get nodes"*) echo "nœud-1   Ready   control-plane,master   5d" ;;
  *"kubectl get pods"*) echo "kube-system   coredns-aaa   1/1   Running   0   5d" ;;
  *) exit 1 ;;
esac
EOF
# Faux curl : il sert l'installateur qu'on lui demande de télécharger. Celui-ci
# dit d'où il a été exécuté et ce que l'environnement lui a transmis, puis pose
# le faux k3s.
faux curl <<'EOF'
#!/bin/sh
echo "curl $*" >> "$BAC/curl-appels"
case " $* " in *" --head "*) [ "${CURL_SONDE_ECHEC:-0}" = 0 ] || exit 6; exit 0 ;; esac
[ "${CURL_TELECHARGEMENT_ECHEC:-0}" = 0 ] || exit 7
cible=""; while [ $# -gt 0 ]; do if [ "$1" = "-o" ]; then shift; cible="$1"; fi; shift; done
cat > "$cible" <<'INSTALLATEUR'
printf '%s\n' "$0" > "$BAC/installateur-appele"
printf '%s\n' "${INSTALL_K3S_VERSION:-aucune}" > "$BAC/installateur-version"
printf '%s\n' "${INSTALL_K3S_CHANNEL:-aucun}" > "$BAC/installateur-canal"
printf '%s\n' "${K3S_URL:-aucune}" > "$BAC/installateur-url"
cp "$BAC/k3s.modele" "$BAC/k3s"; chmod +x "$BAC/k3s"
exit "${INSTALLATEUR_CODE:-0}"
INSTALLATEUR
EOF
faux ss <<'EOF'
#!/bin/sh
[ "${SS_ECHEC:-0}" = 0 ] || exit 1
[ ! -f "$BAC/ecoutes" ] || cat "$BAC/ecoutes"
EOF
# Faux systemctl fidèle au vrai : is-active ne rend 0 que si le service est
# actif, is-enabled 1 tant qu'il n'est pas activé, enable obéit au scénario.
faux systemctl <<'EOF'
#!/bin/sh
echo "systemctl $*" >> "$BAC/systemctl.log"
case "$*" in
  "is-active k3s")  if [ "${SERVICE_K3S:-active}" = active ]; then echo active; exit 0; fi
                    echo "${SERVICE_K3S}"; exit 3 ;;
  "is-enabled k3s") [ "${SERVICE_ACTIVE_BOOT:-1}" = 1 ] && { echo enabled; exit 0; }
                    echo disabled; exit 1 ;;
  "enable k3s")     [ "${ACTIVATION_ECHEC:-0}" = 0 ] || exit 1 ;;
  "list-unit-files k3s.service") echo "k3s.service enabled" ;;
esac
exit 0
EOF

# Remet la machine d'essai à zéro : aucun k3s posé, aucune trace, aucun journal.
neuf() {
    rm -f "$BAC/k3s" "$BAC/ecoutes" "$BAC/installateur-appele" "$BAC/installateur-version" \
          "$BAC/installateur-canal" "$BAC/installateur-url" "$JOURNAL"
    : > "$BAC/curl-appels"; : > "$BAC/systemctl.log"; }
pose() { if [ -e "$1" ]; then echo "présente"; else echo "absente"; fi; }
lancer() { sortie="$(TMPDIR="$BAC" PATH="$BAC:$PATH" bash "$CIBLE" "$@" 2>&1)" && CODE=0 || CODE=$?; }

titre "Codes d'usage"
sortie="$(bash "$CIBLE" --help 2>&1)" && code=0 || code=$?
assert_code 0 "$code" "--help rend 0"
assert_contient "$sortie" "Debian 12"  "--help nomme les systèmes supportés"
assert_contient "$sortie" "2  option"  "--help documente les codes de retour"
bash "$CIBLE" --option-inexistante >/dev/null 2>&1 && code=0 || code=$?
assert_code 2 "$code" "une option inconnue rend 2"

titre "Cibles hors décision 14"
sortie="$(OS_ID=fedora OS_VERSION=41 OS_ARCH=x86_64 bash "$CIBLE" --dry-run 2>&1)" && code=0 || code=$?
assert_code 1 "$code" "une distribution hors cibles est refusée en 1"
assert_contient "$sortie" "fedora" "le refus nomme ce qui a été détecté"
sortie="$(OS_ID=debian OS_VERSION=12 OS_ARCH=riscv64 bash "$CIBLE" --dry-run 2>&1)" && code=0 || code=$?
assert_code 1 "$code" "une architecture hors cibles est refusée en 1"
assert_contient "$sortie" "riscv64" "le refus nomme l'architecture détectée"

titre "Ressources : le disque bloque, la mémoire avertit"
faux df <<'EOF'
#!/bin/sh
printf 'Filesystem 1M-blocks Used Available Use%% Mounted on\n/dev/sda1 100000 99000 %s 99%% /var/lib\n' "${DISQUE_LIBRE_MO:-50000}"
EOF
faux awk <<'EOF'
#!/bin/sh
case "$*" in *MemTotal*) echo "${MEMOIRE_MO:-8192}"; exit 0 ;; esac
exec /usr/bin/awk "$@"
EOF
neuf
sortie="$(TMPDIR="$BAC" PATH="$BAC:$PATH" DISQUE_LIBRE_MO=100 bash "$CIBLE" --yes 2>&1)" && code=0 || code=$?
assert_code 1 "$code" "un espace libre sous /var/lib insuffisant bloque en 1"
assert_contient "$sortie" "Espace insuffisant" "le refus dit ce qui manque"
assert_egal "absente" "$(pose "$BAC/installateur-appele")" "rien n'a été installé"
sortie="$(TMPDIR="$BAC" PATH="$BAC:$PATH" DISQUE_LIBRE_MO=50000 MEMOIRE_MO=256 bash "$CIBLE" --dry-run 2>&1)" && code=0 || code=$?
assert_code 0 "$code" "disque suffisant et 256 Mo de mémoire : le script passe — contraste"
assert_contient "$sortie" "Mémoire totale de 256 Mo" "l'avertissement est celui de la mémoire, et d'elle seule"
assert_contient "$sortie" "Changements prévus" "l'installation n'est pas interrompue pour autant"
rm -f "$BAC/df" "$BAC/awk"

titre "Privilège : root requis hors --dry-run"
faux id <<'EOF'
#!/bin/sh
[ "$*" = "-u" ] && { echo 1000; exit 0; }
exec /usr/bin/id "$@"
EOF
sortie="$(TMPDIR="$BAC" PATH="$BAC:$PATH" LOG_DIR="$BAC/logs" bash "$CIBLE" --yes 2>&1)" && code=0 || code=$?
rm -f "$BAC/id"
assert_code 1 "$code" "un utilisateur non privilégié est refusé en 1"
assert_contient "$sortie" "root" "le refus nomme le privilège manquant"

titre "get.k3s.io injoignable, ports requis déjà en écoute"
neuf
sortie="$(TMPDIR="$BAC" PATH="$BAC:$PATH" CURL_SONDE_ECHEC=1 bash "$CIBLE" --yes 2>&1)" && code=0 || code=$?
assert_code 1 "$code" "un get.k3s.io injoignable refuse en 1"
assert_contient "$sortie" "get.k3s.io" "le refus nomme l'hôte injoignable"
assert_egal "absente" "$(pose "$BAC/installateur-appele")" "rien n'a été installé"
for port in 6443 80 443; do
    printf 'LISTEN 0 4096 0.0.0.0:%s 0.0.0.0:*\n' "$port" > "$BAC/ecoutes"
    : > "$BAC/curl-appels"
    sortie="$(TMPDIR="$BAC" PATH="$BAC:$PATH" bash "$CIBLE" --yes 2>&1)" && code=0 || code=$?
    assert_code 1 "$code" "un port $port déjà en écoute refuse en 1"
    assert_contient "$sortie" "Port(s) déjà en écoute : $port" "le refus nomme le port $port"
    assert_egal "" "$(cat "$BAC/curl-appels")" "port $port occupé : aucune requête réseau n'est partie"
    assert_egal "absente" "$(pose "$BAC/installateur-appele")" "port $port occupé : rien n'a été installé"
done
neuf
sortie="$(TMPDIR="$BAC" PATH="$BAC:$PATH" SS_ECHEC=1 bash "$CIBLE" --yes 2>&1)" && code=0 || code=$?
assert_code 1 "$code" "un ss en échec refuse en 1"
assert_contient "$sortie" "ss n'a pas pu lister les ports" "le refus nomme l'outil et ce qui n'a pas été vérifié"
assert_egal "" "$(cat "$BAC/curl-appels")" "et rien n'a été téléchargé"

titre "--dry-run : le préflight et la commande, sans rien télécharger"
neuf
lancer --dry-run
assert_code 0 "$CODE" "--dry-run rend 0"
assert_contient "$sortie" "Changements prévus" "le résumé des changements est affiché"
assert_contient "$sortie" "stable (canal" "sans SRV_K3S_VERSION, le canal stable est annoncé"
assert_contient "$sortie" "curl -fsSL https://get.k3s.io" "la commande prévue est affichée, en HTTPS"
assert_egal "" "$(cat "$BAC/curl-appels")" "aucun appel à curl : le préflight reste local"
assert_egal "absente" "$(pose "$BAC/k3s")" "aucun k3s n'a été posé"

titre "Hors terminal et sans --yes, le script refuse avant de poser sa question"
neuf
sortie="$(TMPDIR="$BAC" PATH="$BAC:$PATH" bash "$CIBLE" </dev/null 2>&1)" && code=0 || code=$?
assert_code 1 "$code" "sans terminal et sans --yes, le script rend 1"
assert_contient "$sortie" "--yes" "le message nomme l'option qui débloque la situation"
assert_absent "$sortie" "Échec (code" "aucune ligne du trap ERR : le refus est délibéré"
# Décision 45 : ASSUME_YES venu du parent ne vaut pas --yes.
neuf
sortie="$(TMPDIR="$BAC" PATH="$BAC:$PATH" ASSUME_YES=true bash "$CIBLE" </dev/null 2>&1)" && code=0 || code=$?
assert_code 1 "$code" "un ASSUME_YES hérité, sans --yes, rend 1"
assert_egal "absente" "$(pose "$BAC/k3s")" "et rien n'est installé"

titre "Installation complète — faux curl, installateur, k3s et systemctl"
neuf
mkdir -p /var/lib/rancher/k3s/server
printf 'JETON-DE-NOEUD\n' > /var/lib/rancher/k3s/server/node-token
sortie="$(TMPDIR="$BAC" PATH="$BAC:$PATH" SRV_K3S_VERSION=v1.30.5+k3s1 bash "$CIBLE" --yes 2>&1)" && code=0 || code=$?
assert_code 0 "$code" "installation complète avec version épinglée : rend 0"
chemin="$(cat "$BAC/installateur-appele" 2>/dev/null)"
assert_contient "$chemin" "$BAC/tmp." "l'installateur a été exécuté depuis un fichier temporaire"
assert_egal "absente" "$(pose "$chemin")" "et ce temporaire est retiré en sortant"
assert_contient "$sortie" "v1.30.5+k3s1 (épinglée)" "le résumé affiche la version épinglée"
assert_egal "v1.30.5+k3s1" "$(cat "$BAC/installateur-version" 2>/dev/null)" "la version épinglée est transmise à l'installateur"
assert_contient "$(cat "$BAC/systemctl.log")" "enable k3s" "le service k3s est activé"
assert_contient "$sortie" "cluster est sain" "le diagnostic final verify-k3s.sh rend 0"
assert_absent  "$sortie" "JETON-DE-NOEUD" "le jeton du nœud n'apparaît pas dans la sortie"
assert_contient "$(cat "$JOURNAL" 2>/dev/null)" "Exécution : sh" "le journal a bien capté le passage de l'installateur"
assert_absent  "$(cat "$JOURNAL" 2>/dev/null)" "JETON-DE-NOEUD" "ni le jeton dans le journal"
assert_egal "0" "$(grep -c 'node-token' "$CIBLE" || true)" "le script ne nomme jamais le fichier du jeton"

titre "Version et environnement transmis à l'installateur"
neuf
: > "$BAC/curl-appels"
sortie="$(TMPDIR="$BAC" PATH="$BAC:$PATH" INSTALL_K3S_VERSION=v9.9.9 K3S_URL=https://ailleurs:6443 bash "$CIBLE" --yes 2>&1)" && code=0 || code=$?
assert_code 0 "$code" "sans SRV_K3S_VERSION, l'installation suit le canal stable"
assert_egal "stable" "$(cat "$BAC/installateur-canal")" "l'installateur reçoit INSTALL_K3S_CHANNEL=stable"
assert_egal "aucune" "$(cat "$BAC/installateur-version")" "un INSTALL_K3S_VERSION hérité du parent est ignoré"
assert_egal "aucune" "$(cat "$BAC/installateur-url")" "et un K3S_URL hérité ne détourne pas l'installation"
assert_contient "$(cat "$BAC/curl-appels")" "--proto =https" "le téléchargement impose HTTPS (décision 47)"
assert_contient "$(cat "$BAC/curl-appels")" "https://get.k3s.io" "et vise l'installateur officiel en HTTPS"

titre "K3s déjà installé — constat, et rien d'autre"
lancer --yes
assert_code 0 "$CODE" "une installation en place rend 0"
assert_contient "$sortie" "déjà installé" "le script constate au lieu de réinstaller"
assert_contient "$sortie" "v1.30.5+k3s1" "la version en place est affichée"
assert_absent  "$sortie" "Changements prévus" "aucun changement n'est même envisagé"

titre "Activation et état du service après installation"
neuf
sortie="$(TMPDIR="$BAC" PATH="$BAC:$PATH" ACTIVATION_ECHEC=1 bash "$CIBLE" --yes 2>&1)" && code=0 || code=$?
assert_code 1 "$code" "une activation du service en échec rend 1"
assert_contient "$sortie" "Activation du service k3s en échec" "le message nomme l'activation, sans ligne ERR anonyme"
neuf
sortie="$(TMPDIR="$BAC" PATH="$BAC:$PATH" SERVICE_K3S=inactive bash "$CIBLE" --yes 2>&1)" && code=0 || code=$?
assert_code 1 "$code" "un service k3s inactif après installation rend 1"
assert_contient "$sortie" "n'est pas actif après l'installation" "le message nomme l'état relevé"

titre "Téléchargement, installateur et diagnostic en échec"
neuf
sortie="$(TMPDIR="$BAC" PATH="$BAC:$PATH" CURL_TELECHARGEMENT_ECHEC=1 bash "$CIBLE" --yes 2>&1)" && code=0 || code=$?
assert_code 1 "$code" "un téléchargement en échec rend 1"
assert_contient "$sortie" "irrécupérable" "le message dit ce qui a manqué"
assert_egal "absente" "$(pose "$BAC/installateur-appele")" "aucun installateur n'a été exécuté"
sortie="$(TMPDIR="$BAC" PATH="$BAC:$PATH" INSTALLATEUR_CODE=7 bash "$CIBLE" --yes 2>&1)" && code=0 || code=$?
assert_code 1 "$code" "un installateur qui échoue rend 1"
assert_contient "$sortie" "installateur K3s a échoué" "le message nomme l'installateur"
neuf
sortie="$(TMPDIR="$BAC" PATH="$BAC:$PATH" K3S_MUET=1 bash "$CIBLE" --yes 2>&1)" && code=0 || code=$?
assert_code 1 "$code" "un cluster qui ne répond pas rend 1"
assert_contient "$sortie" "L'API du cluster ne répond pas" "l'échec rapporté est celui du diagnostic verify-k3s.sh"
assert_contient "$sortie" "diagnostic ci-dessus ne passe pas" "et le script nomme la vérification qui a échoué"

bilan "TASK-051 / install-k3s.sh"
