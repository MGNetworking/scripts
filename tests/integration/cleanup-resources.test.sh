#!/usr/bin/env bash
# tests/integration/cleanup-resources.test.sh — Kubernetes/Maintenance/cleanup-resources.sh.
# Aucun cluster réel : un faux kubectl tient les codes du vrai — « get » d'un objet absent
# sort en 1 avec « NotFound » — note chaque appel ; « delete » retire le fichier qui le figure.
_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_dir/lib/common.sh" ] && [ "$_dir" != "/" ]; do _dir="$(dirname "$_dir")"; done
source "$_dir/lib/common.sh"
source "$SCRIPTS_ROOT/tests/lib/assert.sh"
CIBLE="$SCRIPTS_ROOT/Kubernetes/Maintenance/cleanup-resources.sh"
# La garde passe avant tout trap et toute écriture : ce script-là est destructeur.
if [ ! -e /.dockerenv ]; then
    saute_indisponible "cleanup-resources.sh" "hors conteneur : l'environnement n'est pas le bac à sable jetable attendu"
    bilan "TASK-061 / cleanup-resources.sh"
fi
BAC="$(mktemp -d)"; export BAC
trap 'rm -rf "$BAC"' EXIT
# Un kubeconfig vide : le script n'en lit aucun, et le faux kubectl non plus.
: > "$BAC/kubeconfig"; export KUBECONFIG="$BAC/kubeconfig"
mkdir -p "$BAC/objets"
cat > "$BAC/kubectl" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$BAC/appels"
[ "${KUBECTL_INJOIGNABLE:-0}" = 1 ] && { echo "The connection to the server 127.0.0.1:6443 was refused" >&2; exit 1; }
fic="$BAC/objets/$5-$2-$3"
case "$1" in
    get) [ -f "$fic" ] && { printf '%s/%s\n' "$2" "$3"; exit 0; }; echo "Error from server (NotFound): $2 \"$3\" not found" >&2; exit 1 ;;
    delete) [ -f "$fic" ] || { echo "Error from server (NotFound): $2 \"$3\" not found" >&2; exit 1; }
         [ "${KUBECTL_DELETE_MUET:-0}" = 1 ] || rm -f "$fic"
         printf '%s/%s deleted\n' "$2" "$3"; exit 0 ;;
    *) exit 0 ;;
esac
EOF
chmod +x "$BAC/kubectl"
existe() { : > "$BAC/objets/$1-$2-$3"; }
present() { test -f "$BAC/objets/$1-$2-$3" && echo présente || echo absente; }
lancer() { : > "$BAC/appels"; CODE=0; sortie="$(PATH="$BAC:$PATH" bash "$CIBLE" "$@" </dev/null 2>&1)" || CODE=$?; }

titre "Codes d'usage"
sortie="$(bash "$CIBLE" --help 2>&1)" && code=0 || code=$?
assert_code 0 "$code" "--help rend 0"
assert_contient "$sortie" "Codes de retour" "--help documente les codes de retour"
assert_contient "$sortie" "kube-system" "--help nomme les namespaces protégés"
lancer --option-inexistante; assert_code 2 "$CODE" "une option inconnue rend 2"
lancer; assert_code 2 "$CODE" "sans cible, le script rend 2"; assert_contient "$sortie" "Aucune cible" "et il dit ce qui manque"
lancer deployment/nginx; assert_code 2 "$CODE" "une cible sans « -n » rend 2"
lancer -n default; assert_code 2 "$CODE" "« -n » sans cible rend 2"
lancer -n default nginx; assert_code 2 "$CODE" "une cible sans « / » rend 2"
lancer -n default a/b/c; assert_code 2 "$CODE" "une cible à deux « / » rend 2"
lancer -n default -l/x; assert_code 2 "$CODE" "une cible en « - » rend 2 : aucun sélecteur possible"

titre "Refus avant toute suppression — namespace protégé, type hors périmètre"
existe default deployment nginx
for protege in kube-system kube-public kube-node-lease; do
    lancer -n "$protege" deployment/nginx -y
    assert_code 1 "$CODE" "un objet de $protege est refusé"
    assert_contient "$sortie" "Namespace protégé" "et le refus est nommé"
done
lancer -n default secret/mot-de-passe -y
assert_code 1 "$CODE" "un Secret est refusé"
assert_contient "$sortie" "hors périmètre" "comme type hors périmètre"
lancer -n default persistentvolume/pv-1 -y
assert_code 1 "$CODE" "un PersistentVolume est refusé"
assert_egal "" "$(cat "$BAC/appels")" "aucun appel kubectl n'a été tenté"
assert_egal "présente" "$(present default deployment nginx)" "et rien n'a été supprimé"

titre "Cible inexistante — le refus précède toute suppression"
lancer -n default deployment/nginx -n default deployment/absent -y
assert_code 1 "$CODE" "une cible inexistante rend 1"
assert_contient "$sortie" "inexistante" "le refus la nomme pour ce qu'elle est"
assert_contient "$sortie" "deployment/absent" "et nomme la cible fautive"
assert_egal "présente" "$(present default deployment nginx)" "l'autre cible, valide, est intacte"
assert_absent "$(cat "$BAC/appels")" "delete" "aucun delete n'a été appelé"

titre "--dry-run — la liste, et rien d'autre"
lancer -n default deployment/nginx --dry-run
assert_code 0 "$CODE" "--dry-run rend 0"
assert_contient "$sortie" "namespace default" "il affiche le namespace"
assert_contient "$sortie" "deployment/nginx" "et le type avec le nom"
assert_egal "" "$(cat "$BAC/appels")" "sans appeler kubectl, delete compris"
assert_egal "présente" "$(present default deployment nginx)" "et sans rien supprimer"

titre "Confirmation — --yes seul, ASSUME_YES hérité ignoré (décision 45)"
lancer -n default deployment/nginx
assert_code 1 "$CODE" "sans terminal et sans --yes, le script rend 1"
assert_contient "$sortie" "--yes" "le message nomme l'option qui débloque la situation"
assert_absent "$sortie" "Échec (code" "aucune ligne du trap ERR : le refus est délibéré"
export ASSUME_YES=true
lancer -n default deployment/nginx
unset ASSUME_YES
assert_code 1 "$CODE" "un ASSUME_YES hérité, sans --yes, rend 1"
assert_egal "présente" "$(present default deployment nginx)" "et rien n'est supprimé"
if command -v script >/dev/null 2>&1; then
    # Avec un terminal, c'est confirm qui décide : ce cas seul prouve que
    # l'ASSUME_YES du parent est réellement remis à false (décision 45).
    CODE=0; sortie="$(printf 'n\n' | PATH="$BAC:$PATH" ASSUME_YES=true \
        script -qec "bash $CIBLE -n default deployment/nginx" /dev/null 2>&1)" || CODE=$?
    assert_code 1 "$CODE" "un ASSUME_YES hérité, avec un terminal, rend 1"
    assert_absent "$sortie" "Confirmation automatique" "l'ASSUME_YES du parent est ignoré"
    assert_contient "$sortie" "abandonné" "la question est posée et « n » l'écarte"
    assert_egal "présente" "$(present default deployment nginx)" "et rien n'est supprimé"
else
    saute_indisponible "ASSUME_YES hérité avec un terminal" "script (util-linux) absent"
fi

titre "Suppression — chaque cible relue absente"
existe default configmap reglages
lancer -n default deployment/nginx -n default configmap/reglages -y
assert_code 0 "$CODE" "deux cibles nommées sont supprimées"
assert_contient "$sortie" "[SUCCESS]" "le script le dit en [SUCCESS]"
assert_egal "absente" "$(present default deployment nginx)" "la première a disparu"
assert_egal "absente" "$(present default configmap reglages)" "la seconde aussi"
APPELS="$(cat "$BAC/appels")"
assert_contient "$APPELS" "get deployment nginx -n default" "chaque cible est relue avant d'être supprimée"
assert_contient "$APPELS" "delete configmap reglages -n default" "et supprimée par son nom, dans son namespace"
assert_egal "get" "$(head -n 1 "$BAC/appels" | cut -d' ' -f1)" "la relecture précède le premier delete"
assert_egal "0" "$(grep -vcE -- '--request-timeout=[0-9]+s' "$BAC/appels" || true)" "chaque appel est borné par --request-timeout"
assert_absent "$APPELS" "--force" "aucun delete forcé"; assert_absent "$APPELS" "--grace-period" "aucune grâce écourtée"
assert_absent "$APPELS" "-l " "aucune suppression par sélecteur"; assert_absent "$APPELS" "--all" "ni par --all"

titre "Cible encore présente après delete — le nettoyage est dit inachevé"
existe default deployment nginx
export KUBECTL_DELETE_MUET=1
lancer -n default deployment/nginx -y
unset KUBECTL_DELETE_MUET
assert_code 1 "$CODE" "une cible encore présente rend 1"
assert_contient "$sortie" "encore présent" "le script nomme ce qui reste"
assert_contient "$sortie" "deployment/nginx" "et le nomme précisément"
assert_absent "$sortie" "[SUCCESS]" "jamais [SUCCESS] : le nettoyage est inachevé"

titre "Apiserver injoignable, puis kubectl absent"
export KUBECTL_INJOIGNABLE=1
lancer -n default deployment/nginx -y
unset KUBECTL_INJOIGNABLE
assert_code 1 "$CODE" "un apiserver injoignable rend 1"
assert_contient "$sortie" "[ERROR]" "l'échec est signalé en [ERROR]"
assert_contient "$sortie" "apiserver" "il nomme l'apiserver"
assert_contient "$sortie" "was refused" "la raison rendue par kubectl est montrée"
assert_egal "présente" "$(present default deployment nginx)" "et rien n'est supprimé"
sortie="$(PATH="/usr/bin:/bin" bash "$CIBLE" -n default deployment/nginx -y 2>&1)" && code=0 || code=$?
assert_code 1 "$code" "sans kubectl, le script rend 1"
assert_contient "$sortie" "Commande(s) requise(s) introuvable(s) : kubectl" "c'est le message de require_cmd"

titre "Ce que le script ne fait pas"
SOURCE="$(cat "$CIBLE")"
assert_contient "$SOURCE" "--request-timeout" "chaque appel kubectl est borné"
assert_absent "$SOURCE" "require_root" "aucun require_root : le script s'exécute sans root"
assert_absent "$SOURCE" "k3s.yaml" "aucune référence à /etc/rancher/k3s/k3s.yaml"
assert_absent "$SOURCE" "k3s kubectl" "kubectl est appelé directement"; assert_absent "$SOURCE" "get all" "« get all » n'est pas employé"

bilan "TASK-061 / cleanup-resources.sh"
