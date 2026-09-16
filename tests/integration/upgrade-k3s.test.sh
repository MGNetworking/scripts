#!/usr/bin/env bash
# tests/integration/upgrade-k3s.test.sh — Linux/K3s/upgrade-k3s.sh.
# TASK-053. AUCUNE MISE À NIVEAU RÉELLE : un faux curl dépose un faux
# installateur, qui change la version qu'annonce le faux k3s. Le diagnostic
# d'avant et d'après est le vrai verify-k3s.sh, qui lit ces faux.
_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_dir/lib/common.sh" ] && [ "$_dir" != "/" ]; do _dir="$(dirname "$_dir")"; done
source "$_dir/lib/common.sh"
source "$SCRIPTS_ROOT/tests/lib/assert.sh"

CIBLE="$SCRIPTS_ROOT/Linux/K3s/upgrade-k3s.sh"
JOURNAL="/var/log/mgnetworking/upgrade-k3s.log"
if [ ! -e /.dockerenv ]; then
    saute_indisponible "upgrade-k3s.sh" "hors conteneur : le diagnostic porterait sur un vrai cluster"
    bilan "TASK-053 / upgrade-k3s.sh"
fi
BAC="$(mktemp -d)"
export BAC
trap 'rm -rf "$BAC"' EXIT

faux() { cat > "$BAC/$1"; chmod +x "$BAC/$1"; }
# Faux k3s : la version annoncée est celle du fichier version, que l'installateur
# réécrit ; muet, il simule un cluster qui ne répond plus — son binaire, lui,
# répond toujours : c'est l'API qui se tait, pas le binaire.
faux k3s <<'EOF'
#!/bin/sh
case "$*" in
  --version) echo "k3s version $(cat "$BAC/version") (aaaaaaa)" ;;
  *kubectl*)
    [ ! -f "$BAC/muet" ] || exit 1
    case "$*" in
      *"get nodes"*)      echo "nœud-1   Ready   control-plane,master   5d   $(cat "$BAC/version")" ;;
      *"get pods"*)       echo "kube-system   coredns-aaa   1/1   Running   0   5d" ;;
      *"get namespaces"*) echo "kube-system" ;;
      *) exit 1 ;;
    esac ;;
  *) exit 1 ;;
esac
EOF
# Faux curl : sert l'installateur demandé. Celui-ci dit d'où il a été exécuté et
# ce que l'environnement lui a transmis, puis pose la version d'après.
faux curl <<'EOF'
#!/bin/sh
echo "curl $*" >> "$BAC/curl-appels"
[ "${CURL_ECHEC:-0}" = 0 ] || exit 7
cible=""; while [ $# -gt 0 ]; do if [ "$1" = "-o" ]; then shift; cible="$1"; fi; shift; done
cat > "$cible" <<'INSTALLATEUR'
printf '%s\n' "$0" > "$BAC/installateur-appele"
printf '%s\n' "${INSTALL_K3S_VERSION:-aucune}" > "$BAC/installateur-version"
printf '%s\n' "${INSTALL_K3S_CHANNEL:-aucun}" > "$BAC/installateur-canal"
printf '%s\n' "$(cat "$BAC/version")" > "$BAC/version-avant"
[ "${INSTALLATEUR_CODE:-0}" = 0 ] || exit "${INSTALLATEUR_CODE}"
[ "${INSTALLATEUR_MUET:-0}" = 0 ] || : > "$BAC/muet"
printf '%s\n' "${K3S_VERSION_APRES:-v1.31.1+k3s1}" > "$BAC/version"
INSTALLATEUR
EOF
faux systemctl <<'EOF'
#!/bin/sh
case "$*" in
  "is-active k3s") echo active ;;
  "list-unit-files k3s.service") echo "k3s.service enabled" ;;
esac
exit 0
EOF

neuf() {
    printf 'v1.30.5+k3s1\n' > "$BAC/version"
    rm -f "$BAC/muet" "$BAC/installateur-appele" "$BAC/installateur-version" \
          "$BAC/installateur-canal" "$BAC/version-avant" "$JOURNAL"
    : > "$BAC/curl-appels"; }
lancer() { sortie="$(TMPDIR="$BAC" PATH="$BAC:$PATH" bash "$CIBLE" "$@" 2>&1)" && CODE=0 || CODE=$?; }
sur() { TMPDIR="$BAC" PATH="$BAC:$PATH" "$@"; }
actuelle() { cat "$BAC/version"; }

titre "Codes d'usage"
sortie="$(bash "$CIBLE" --help 2>&1)" && code=0 || code=$?
assert_code 0 "$code" "--help rend 0"
assert_contient "$sortie" "vX.Y.Z+k3sN" "--help donne la forme de la version attendue"
assert_contient "$sortie" "2  option"   "--help documente les codes de retour"
bash "$CIBLE" --option-inexistante >/dev/null 2>&1 && code=0 || code=$?
assert_code 2 "$code" "une option inconnue rend 2"
bash "$CIBLE" --version >/dev/null 2>&1 && code=0 || code=$?
assert_code 2 "$code" "--version sans valeur rend 2"

titre "Version cible : obligatoire et validée strictement"
neuf
lancer --yes
assert_code 1 "$CODE" "sans version cible, le script refuse en 1"
assert_contient "$sortie" "--version" "le refus nomme l'option qui débloque la situation"
assert_contient "$sortie" "jamais la dernière stable" "le refus dit pourquoi il n'en choisit pas une"
assert_egal "" "$(cat "$BAC/curl-appels")" "et rien n'a été téléchargé"
for forme in "1.30.5+k3s1" "v1.30+k3s1" "v1.30.5" "v1.30.5+k3s" "v1.30.5+k3sX"; do
    neuf
    lancer --version "$forme" --yes
    assert_code 1 "$CODE" "la forme « $forme » est refusée en 1"
    assert_contient "$sortie" "invalide" "et le refus la dit invalide"
done
neuf
lancer --dry-run
assert_code 1 "$CODE" "sans --version ni SRV_K3S_VERSION, --dry-run refuse aussi"
sur env SRV_K3S_VERSION=v1.31.1+k3s1 bash "$CIBLE" --dry-run >/dev/null 2>&1 && code=0 || code=$?
assert_code 0 "$code" "SRV_K3S_VERSION tient lieu de --version — garde de contraste"

titre "K3s absent — renvoi vers install-k3s.sh"
neuf
mv "$BAC/k3s" "$BAC/k3s.hors"
lancer --version v1.31.1+k3s1 --yes
mv "$BAC/k3s.hors" "$BAC/k3s"
assert_code 1 "$CODE" "un K3s absent refuse en 1"
assert_contient "$sortie" "install-k3s.sh" "et le refus renvoie vers le script d'installation"
assert_egal "" "$(cat "$BAC/curl-appels")" "rien n'a été téléchargé"

titre "Privilège : root requis hors --dry-run"
neuf
faux id <<'EOF'
#!/bin/sh
[ "$*" = "-u" ] && { echo 1000; exit 0; }
exec /usr/bin/id "$@"
EOF
lancer --version v1.31.1+k3s1 --yes
rm -f "$BAC/id"
assert_code 1 "$CODE" "un utilisateur non privilégié est refusé en 1"
assert_contient "$sortie" "root" "le refus nomme le privilège manquant"

titre "Cible en recul, trop lointaine, ou de version majeure différente"
for cas in "v1.29.9+k3s1|inférieure" "v1.30.5+k3s0|inférieure" "v1.32.1+k3s1|mineure" "v2.30.5+k3s1|majeure"; do
    cible="${cas%%|*}"; attendu="${cas##*|}"
    neuf
    lancer --version "$cible" --yes
    assert_code 1 "$CODE" "la cible $cible est refusée en 1"
    assert_contient "$sortie" "$attendu" "et le refus dit « $attendu »"
    assert_egal "" "$(cat "$BAC/curl-appels")" "cible $cible : rien n'a été téléchargé"
    assert_egal "v1.30.5+k3s1" "$(actuelle)" "cible $cible : la version en place est intacte"
done
neuf
lancer --version v1.31.1+k3s1 --dry-run
assert_code 0 "$CODE" "une mineure de plus est acceptée — garde de contraste"

titre "Déjà à jour : constat, sans rien télécharger"
neuf
lancer --version v1.30.5+k3s1 --yes
assert_code 0 "$CODE" "une cible égale à la version en place rend 0"
assert_contient "$sortie" "déjà en v1.30.5+k3s1" "le script constate au lieu de mettre à niveau"
assert_egal "" "$(cat "$BAC/curl-appels")" "aucune requête réseau n'est partie"
assert_egal "v1.30.5+k3s1" "$(actuelle)" "et la version en place n'a pas bougé"

titre "Cluster malsain avant la mise à niveau"
neuf
: > "$BAC/muet"
lancer --version v1.31.1+k3s1 --yes
assert_code 1 "$CODE" "un cluster qui ne répond pas refuse en 1"
assert_contient "$sortie" "n'est pas sain" "le refus nomme l'état du cluster"
assert_egal "" "$(cat "$BAC/curl-appels")" "et rien n'a été téléchargé"
assert_egal "v1.30.5+k3s1" "$(actuelle)" "ni modifié"

titre "--dry-run : versions et commande prévue, sans téléchargement"
neuf
lancer --version v1.31.1+k3s1 --dry-run
assert_code 0 "$CODE" "--dry-run rend 0"
assert_contient "$sortie" "Version en place : v1.30.5+k3s1" "la version en place est affichée"
assert_contient "$sortie" "Version cible   : v1.31.1+k3s1" "la version cible est affichée"
assert_contient "$sortie" "curl -fsSL https://get.k3s.io" "la commande prévue est affichée, en HTTPS"
assert_contient "$sortie" "--proto '=https'" "et l'option HTTPS seul y figure (décision 47)"
assert_contient "$sortie" "Aucun téléchargement" "le script dit lui-même n'avoir rien téléchargé"
assert_egal "" "$(cat "$BAC/curl-appels")" "aucun appel à curl, en effet"
assert_egal "v1.30.5+k3s1" "$(actuelle)" "et aucune écriture"

titre "Hors terminal et sans --yes, le script refuse avant de poser sa question"
neuf
sortie="$(TMPDIR="$BAC" PATH="$BAC:$PATH" bash "$CIBLE" --version v1.31.1+k3s1 </dev/null 2>&1)" && CODE=0 || CODE=$?
assert_code 1 "$CODE" "sans terminal et sans --yes, le script rend 1"
assert_contient "$sortie" "--yes" "le message nomme l'option qui débloque la situation"
assert_absent  "$sortie" "Échec (code" "aucune ligne du trap ERR : le refus est délibéré"
neuf
sortie="$(TMPDIR="$BAC" PATH="$BAC:$PATH" ASSUME_YES=true bash "$CIBLE" --version v1.31.1+k3s1 </dev/null 2>&1)" && CODE=0 || CODE=$?
assert_code 1 "$CODE" "un ASSUME_YES hérité, sans --yes, rend 1 (décision 45)"
assert_egal "v1.30.5+k3s1" "$(actuelle)" "et rien n'a été mis à niveau"

titre "Mise à niveau complète — faux curl, installateur, k3s et systemctl"
neuf
sur env INSTALL_K3S_CHANNEL=old K3S_URL=https://ailleurs:6443 bash "$CIBLE" --version v1.31.1+k3s1 --yes >/dev/null 2>&1 && code=0 || code=$?
assert_code 0 "$code" "mise à niveau complète : rend 0"
assert_contient "$(cat "$BAC/installateur-appele" 2>/dev/null)" "$BAC/tmp." "l'installateur a été exécuté depuis un fichier temporaire"
assert_egal "absente" "$(test -e "$(cat "$BAC/installateur-appele")" && echo présente || echo absente)" "et ce temporaire est retiré en sortant"
assert_egal "v1.31.1+k3s1" "$(cat "$BAC/installateur-version" 2>/dev/null)" "la version cible est transmise à l'installateur"
assert_egal "aucun" "$(cat "$BAC/installateur-canal" 2>/dev/null)" "un INSTALL_K3S_CHANNEL hérité est ignoré (décision 47)"
assert_contient "$(cat "$BAC/curl-appels")" "--proto =https" "le téléchargement impose HTTPS seul (décision 47)"
assert_contient "$(cat "$BAC/curl-appels")" "https://get.k3s.io" "et vise l'installateur officiel en HTTPS"
assert_egal "v1.31.1+k3s1" "$(actuelle)" "la version en place a bien changé"
assert_contient "$(cat "$JOURNAL" 2>/dev/null)" "Exécution : sh" "le journal a capté le passage de l'installateur"
assert_egal "0" "$(grep -c 'node-token' "$CIBLE" || true)" "le script ne nomme jamais le fichier du jeton"

titre "Avertissement : cluster muet après la mise à niveau"
neuf
sur env INSTALLATEUR_MUET=1 bash "$CIBLE" --version v1.31.1+k3s1 --yes >"$BAC/sortie" 2>&1 && code=0 || code=$?
assert_code 1 "$code" "un cluster qui ne répond plus après coup rend 1"
assert_contient "$(cat "$BAC/sortie")" "Version en place : v1.31.1+k3s1" "le message affiche la version réellement en place"
assert_contient "$(cat "$BAC/sortie")" "Retour arrière" "et indique par où revenir en arrière"

titre "Téléchargement et installateur en échec"
neuf
sur env CURL_ECHEC=1 bash "$CIBLE" --version v1.31.1+k3s1 --yes >"$BAC/sortie" 2>&1 && code=0 || code=$?
assert_code 1 "$code" "un téléchargement en échec rend 1"
assert_contient "$(cat "$BAC/sortie")" "irrécupérable" "le message dit ce qui a manqué"
assert_egal "absente" "$(test -e "$BAC/installateur-appele" && echo présente || echo absente)" "aucun installateur n'a été exécuté"
assert_egal "v1.30.5+k3s1" "$(actuelle)" "et la version en place est intacte"
neuf
sur env INSTALLATEUR_CODE=7 bash "$CIBLE" --version v1.31.1+k3s1 --yes >"$BAC/sortie" 2>&1 && code=0 || code=$?
assert_code 1 "$code" "un installateur qui échoue rend 1"
assert_contient "$(cat "$BAC/sortie")" "installateur K3s a échoué" "le message nomme l'installateur"
assert_egal "v1.30.5+k3s1" "$(actuelle)" "et la version en place n'a pas changé"

bilan "TASK-053 / upgrade-k3s.sh"
