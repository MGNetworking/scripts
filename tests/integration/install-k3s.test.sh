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
# dit d'où il a été exécuté, quelle version il a reçue, et pose le faux k3s.
faux curl <<'EOF'
#!/bin/sh
echo "curl $*" >> "$BAC/curl-appels"
case " $* " in *" --head "*) [ "${CURL_SONDE_ECHEC:-0}" = 0 ] || exit 6; exit 0 ;; esac
[ "${CURL_TELECHARGEMENT_ECHEC:-0}" = 0 ] || exit 7
cible=""; while [ $# -gt 0 ]; do if [ "$1" = "-o" ]; then shift; cible="$1"; fi; shift; done
cat > "$cible" <<'INSTALLATEUR'
printf '%s\n' "$0" > "$BAC/installateur-appele"
printf '%s\n' "${INSTALL_K3S_VERSION:-aucune}" > "$BAC/installateur-version"
cp "$BAC/k3s.modele" "$BAC/k3s"; chmod +x "$BAC/k3s"
exit "${INSTALLATEUR_CODE:-0}"
INSTALLATEUR
EOF
faux ss <<'EOF'
#!/bin/sh
[ ! -f "$BAC/ecoutes" ] || cat "$BAC/ecoutes"
EOF
faux systemctl <<'EOF'
#!/bin/sh
echo "systemctl $*" >> "$BAC/systemctl.log"
case "$*" in
  "is-active k3s") echo "${SERVICE_K3S:-active}" ;;
  "list-unit-files k3s.service") echo "k3s.service enabled" ;;
esac
EOF

# Remet la machine d'essai à zéro : aucun k3s posé, aucune trace, aucun journal.
neuf() {
    rm -f "$BAC/k3s" "$BAC/ecoutes" "$BAC/installateur-appele" "$BAC/installateur-version" "$JOURNAL"
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
assert_contient "$sortie" "[WARN]" "la mémoire de 256 Mo n'émet qu'un avertissement"
rm -f "$BAC/df" "$BAC/awk"

titre "get.k3s.io injoignable, port requis déjà en écoute"
neuf
sortie="$(TMPDIR="$BAC" PATH="$BAC:$PATH" CURL_SONDE_ECHEC=1 bash "$CIBLE" --yes 2>&1)" && code=0 || code=$?
assert_code 1 "$code" "un get.k3s.io injoignable refuse en 1"
assert_contient "$sortie" "get.k3s.io" "le refus nomme l'hôte injoignable"
assert_egal "absente" "$(pose "$BAC/installateur-appele")" "rien n'a été installé"
printf 'LISTEN 0 4096 0.0.0.0:443 0.0.0.0:*\n' > "$BAC/ecoutes"
sortie="$(TMPDIR="$BAC" PATH="$BAC:$PATH" bash "$CIBLE" --yes 2>&1)" && code=0 || code=$?
assert_code 1 "$code" "un port requis déjà en écoute refuse en 1"
assert_contient "$sortie" "Port(s) déjà en écoute : 443" "le refus nomme le port occupé"

titre "--dry-run : le préflight et la commande, sans rien télécharger"
neuf
lancer --dry-run
assert_code 0 "$CODE" "--dry-run rend 0"
assert_contient "$sortie" "Changements prévus" "le résumé des changements est affiché"
assert_contient "$sortie" "stable (canal" "sans SRV_K3S_VERSION, le canal stable est annoncé"
assert_contient "$sortie" "curl -fsSL https://get.k3s.io" "la commande prévue est affichée, en HTTPS"
assert_absent "$(cat "$BAC/curl-appels")" "--max-time" "et rien n'a été téléchargé"
assert_egal "absente" "$(pose "$BAC/k3s")" "aucun k3s n'a été posé"

titre "Hors terminal et sans --yes, le script refuse avant de poser sa question"
neuf
sortie="$(TMPDIR="$BAC" PATH="$BAC:$PATH" bash "$CIBLE" </dev/null 2>&1)" && code=0 || code=$?
assert_code 1 "$code" "sans terminal et sans --yes, le script rend 1"
assert_contient "$sortie" "--yes" "le message nomme l'option qui débloque la situation"
assert_absent "$sortie" "Échec (code" "aucune ligne du trap ERR : le refus est délibéré"

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

titre "K3s déjà installé — constat, et rien d'autre"
lancer --yes
assert_code 0 "$CODE" "une installation en place rend 0"
assert_contient "$sortie" "déjà installé" "le script constate au lieu de réinstaller"
assert_contient "$sortie" "v1.30.5+k3s1" "la version en place est affichée"
assert_absent  "$sortie" "Changements prévus" "aucun changement n'est même envisagé"

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
assert_contient "$sortie" "diagnostic" "le message renvoie au diagnostic"

bilan "TASK-051 / install-k3s.sh"
