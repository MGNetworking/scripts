#!/usr/bin/env bash
# tests/integration/configure-k3s.test.sh — Linux/K3s/configure-k3s.sh. TASK-052.
# AUCUNE ÉCRITURE DANS /etc : K3S_CONFIG_DIR place config.yaml dans un bac à sable.
# Faux k3s et faux systemctl en tête de PATH ; le diagnostic final est le vrai
# verify-k3s.sh, qui lit ces faux.
_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_dir/lib/common.sh" ] && [ "$_dir" != "/" ]; do _dir="$(dirname "$_dir")"; done
source "$_dir/lib/common.sh"
source "$SCRIPTS_ROOT/tests/lib/assert.sh"

CIBLE="$SCRIPTS_ROOT/Linux/K3s/configure-k3s.sh"
# Les faux ne sont seuls maîtres de leur nom que dans un conteneur jetable.
if [ ! -e /.dockerenv ]; then
    saute_indisponible "configure-k3s.sh" "hors conteneur : les faux k3s et systemctl n'y seraient pas les seuls"
    bilan "TASK-052 / configure-k3s.sh"
fi
BAC="$(mktemp -d)"; export BAC
trap 'rm -rf "$BAC"' EXIT
BAC_ETC="$BAC/etc/k3s"; FICHIER="$BAC_ETC/config.yaml"; JOURNAL="$BAC/systemctl.log"
LANCER_ENV=(env "PATH=$BAC:$PATH" "K3S_CONFIG_DIR=$BAC_ETC")

faux() { cat > "$BAC/$1"; chmod +x "$BAC/$1"; }
faux k3s <<'EOF'
#!/bin/sh
[ "${K3S_MUET:-0}" = 0 ] || exit 1
case "$*" in
  --version) echo "k3s version v1.30.5+k3s1 (aaaaaaa)" ;;
  *"kubectl get nodes"*) echo "nœud-1   Ready   control-plane,master   5d" ;;
  *"kubectl get pods"*) echo "kube-system   coredns-aaa   1/1   Running   0   5d" ;;
  *) exit 1 ;;
esac
EOF
# Faux systemctl fidèle au vrai : is-active rend 3 quand le service n'est pas actif.
faux systemctl <<'EOF'
#!/bin/sh
echo "systemctl $*" >> "$BAC/systemctl.log"
case "$*" in
  "restart k3s")   [ "${REDEMARRAGE_ECHEC:-0}" = 0 ] || exit 1 ;;
  "is-active k3s") [ "${SERVICE_K3S:-active}" = active ] && { echo active; exit 0; }
                   echo "${SERVICE_K3S}"; exit 3 ;;
esac
exit 0
EOF

ATTENDU='# Généré par Linux/K3s/configure-k3s.sh — toute modification manuelle sera écrasée.
write-kubeconfig-mode: "0600"
tls-san:
  - "k3s.exemple.fr"
  - "10.0.0.5"'
ANCIEN='write-kubeconfig-mode: "0644"
tls-san:
  - "ancien.exemple.fr"'

neuf() { rm -rf "$BAC_ETC"; : > "$JOURNAL"; }
pose() { if [ -e "$1" ]; then echo "présente"; else echo "absente"; fi; }
lancer() { sortie="$("${LANCER_ENV[@]}" bash "$CIBLE" "$@" 2>&1)" && CODE=0 || CODE=$?; }
ancien_en_place() { mkdir -p "$BAC_ETC"; rm -f "$BAC_ETC"/*.bak; printf '%s\n' "$ANCIEN" > "$FICHIER"; : > "$JOURNAL"; }

titre "Codes d'usage"
sortie="$(bash "$CIBLE" --help 2>&1)" && code=0 || code=$?
assert_code 0 "$code" "--help rend 0"
assert_contient "$sortie" "write-kubeconfig-mode" "--help nomme la clé écrite"
assert_contient "$sortie" "2  option" "--help documente les codes de retour"
bash "$CIBLE" --option-inexistante >/dev/null 2>&1 && code=0 || code=$?
assert_code 2 "$code" "une option inconnue rend 2"

titre "Privilège et présence de K3s"
neuf
faux id <<'EOF'
#!/bin/sh
[ "$*" = "-u" ] && { echo 1000; exit 0; }
exec /usr/bin/id "$@"
EOF
# LOG_DIR est fixé : sans lui, le socle écrirait dans le dépôt, faute de racine.
sortie="$("${LANCER_ENV[@]}" LOG_DIR="$BAC/logs" bash "$CIBLE" --yes 2>&1)" && code=0 || code=$?
rm -f "$BAC/id"
assert_code 1 "$code" "un utilisateur non privilégié est refusé en 1"
assert_contient "$sortie" "root" "le refus nomme le privilège manquant"
assert_egal "absente" "$(pose "$FICHIER")" "rien n'a été écrit"
mv "$BAC/k3s" "$BAC/k3s.range"
lancer --yes
mv "$BAC/k3s.range" "$BAC/k3s"
assert_code 1 "$CODE" "K3s absent est refusé en 1"
assert_contient "$sortie" "K3s n'est pas installé" "le refus nomme ce qui manque"
assert_contient "$sortie" "install-k3s.sh" "et dit où se fait l'installation"

titre "Contenu écrit : les deux clés de la décision 47, et rien d'autre"
neuf
sortie="$("${LANCER_ENV[@]}" SRV_K3S_TLS_SAN="k3s.exemple.fr,10.0.0.5" bash "$CIBLE" --yes 2>&1)" && code=0 || code=$?
assert_code 0 "$code" "un fichier absent est créé : rend 0"
assert_egal "$ATTENDU" "$(cat "$FICHIER" 2>/dev/null)" "le fichier porte exactement le contenu attendu"
assert_contient "$(cat "$JOURNAL")" "restart k3s" "K3s est redémarré"
assert_contient "$sortie" "cluster est sain" "et le diagnostic verify-k3s.sh rend 0"

titre "Fichier identique : rien n'est réécrit ni redémarré"
: > "$JOURNAL"
sortie="$("${LANCER_ENV[@]}" SRV_K3S_TLS_SAN="k3s.exemple.fr,10.0.0.5" bash "$CIBLE" --yes 2>&1)" && code=0 || code=$?
assert_code 0 "$code" "une seconde exécution rend 0"
assert_contient "$sortie" "déjà conforme" "le script constate au lieu de réécrire"
assert_egal "" "$(cat "$JOURNAL")" "aucun redémarrage n'a été demandé"

titre "SRV_K3S_TLS_SAN absente ou vide : la clé tls-san est omise"
neuf
lancer --yes
assert_code 0 "$CODE" "sans SRV_K3S_TLS_SAN, le script écrit quand même"
assert_absent "$(cat "$FICHIER")" "tls-san" "la clé tls-san est omise"
assert_contient "$(cat "$FICHIER")" 'write-kubeconfig-mode: "0600"' "write-kubeconfig-mode reste écrit"
neuf
sortie="$("${LANCER_ENV[@]}" SRV_K3S_TLS_SAN="" bash "$CIBLE" --yes 2>&1)" && code=0 || code=$?
assert_code 0 "$code" "une SRV_K3S_TLS_SAN vide n'est pas une erreur"
assert_absent "$(cat "$FICHIER")" "tls-san" "et la clé tls-san est omise là aussi"

titre "Fichier différent : différence affichée, sauvegarde, remplacement"
ancien_en_place
sortie="$("${LANCER_ENV[@]}" SRV_K3S_TLS_SAN="k3s.exemple.fr,10.0.0.5" bash "$CIBLE" --dry-run 2>&1)" && code=0 || code=$?
assert_code 0 "$code" "--dry-run rend 0"
assert_contient "$sortie" '-write-kubeconfig-mode: "0644"' "la différence montre l'ancienne valeur"
assert_contient "$sortie" '+write-kubeconfig-mode: "0600"' "et la nouvelle"
assert_egal "$ANCIEN" "$(cat "$FICHIER")" "le fichier n'a pas été touché"
assert_egal "" "$(cat "$JOURNAL")" "ni K3s redémarré"
sortie="$("${LANCER_ENV[@]}" SRV_K3S_TLS_SAN="k3s.exemple.fr,10.0.0.5" bash "$CIBLE" --yes 2>&1)" && code=0 || code=$?
assert_code 0 "$code" "le remplacement rend 0"
assert_contient "$sortie" '-write-kubeconfig-mode: "0644"' "la différence est affichée avant confirmation, hors dry-run aussi"
assert_contient "$sortie" "Original sauvegardé" "l'original est sauvegardé avant remplacement"
assert_egal "$ANCIEN" "$(cat "$BAC_ETC"/*.bak 2>/dev/null)" "la sauvegarde contient l'ancien fichier"
assert_egal "$ATTENDU" "$(cat "$FICHIER")" "et le fichier porte le nouveau contenu"

titre "Confirmation : --yes seul, ASSUME_YES hérité ignoré (décision 45)"
neuf
sortie="$("${LANCER_ENV[@]}" bash "$CIBLE" </dev/null 2>&1)" && code=0 || code=$?
assert_code 1 "$code" "sans terminal et sans --yes, le script rend 1"
assert_contient "$sortie" "--yes" "le message nomme l'option qui débloque la situation"
assert_egal "absente" "$(pose "$FICHIER")" "rien n'a été écrit"
sortie="$("${LANCER_ENV[@]}" ASSUME_YES=true bash "$CIBLE" </dev/null 2>&1)" && code=0 || code=$?
assert_code 1 "$code" "un ASSUME_YES hérité, sans --yes, rend 1"
assert_egal "absente" "$(pose "$FICHIER")" "et rien n'est écrit pour autant"

titre "Valeur mal formée dans config/ : refus en 2, sans rien écrire"
for valeur in "k3s.exemple.fr,10.0.0.5/32" "k3s.exemple.fr,,10.0.0.5" "k3s.exemple.fr,10.0.0.5 10.0.0.6"; do
    neuf
    sortie="$("${LANCER_ENV[@]}" SRV_K3S_TLS_SAN="$valeur" bash "$CIBLE" --yes 2>&1)" && code=0 || code=$?
    assert_code 2 "$code" "« $valeur » est refusée en 2"
    assert_contient "$sortie" "SRV_K3S_TLS_SAN mal formée" "le refus nomme la variable fautive"
    assert_egal "absente" "$(pose "$FICHIER")" "et rien n'a été écrit"
done

titre "Écriture suivie d'un échec : l'original est restauré, K3s relancé"
ancien_en_place
sortie="$("${LANCER_ENV[@]}" SRV_K3S_TLS_SAN="k3s.exemple.fr" REDEMARRAGE_ECHEC=1 bash "$CIBLE" --yes 2>&1)" && code=0 || code=$?
assert_code 1 "$code" "un redémarrage en échec rend 1"
assert_contient "$sortie" "restaurée" "le message dit que l'original est revenu"
assert_egal "$ANCIEN" "$(cat "$FICHIER")" "l'ancien fichier est en place"
ancien_en_place
sortie="$("${LANCER_ENV[@]}" SRV_K3S_TLS_SAN="k3s.exemple.fr" K3S_MUET=1 bash "$CIBLE" --yes 2>&1)" && code=0 || code=$?
assert_code 1 "$code" "un cluster qui ne répond pas rend 1"
assert_contient "$sortie" "L'API du cluster ne répond pas" "l'échec rapporté est celui de verify-k3s.sh"
assert_contient "$sortie" "l'original a été restauré" "et le script nomme la restauration"
assert_egal "$ANCIEN" "$(cat "$FICHIER")" "l'ancien fichier est en place"
assert_egal "2" "$(grep -c 'restart k3s' "$JOURNAL" || true)" "K3s a été relancé une seconde fois, avec l'ancien fichier"

bilan "TASK-052 / configure-k3s.sh"
