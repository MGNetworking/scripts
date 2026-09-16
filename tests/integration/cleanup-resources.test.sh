#!/usr/bin/env bash
# tests/integration/cleanup-resources.test.sh — Kubernetes/Maintenance/cleanup-resources.sh.
# Aucun cluster réel : un faux kubectl tient les codes du vrai — « get » d'un objet
# absent sort en 1 avec « NotFound » — et ANALYSE tous ses arguments. Une option
# qu'il ne connaît pas, un verbe manquant, un argv mal ordonné laissent « FAUX » au
# journal d'appels, que les tests relisent.
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
# Un kubeconfig vide, celui du test : le script ne doit jamais en changer.
: > "$BAC/kubeconfig"; export KUBECONFIG="$BAC/kubeconfig"
mkdir -p "$BAC/objets"
# Bac et journaux ouverts : le cas « sans root » fait tourner le script en nobody.
chmod 777 "$BAC" "$BAC/objets"
for f in appels cumul kubeconfigs appels-docker appels-k3s; do : > "$BAC/$f"; chmod 666 "$BAC/$f"; done
cat > "$BAC/kubectl" <<'EOF'
#!/bin/sh
# Faux kubectl : journalise son argv et le kubeconfig vu, puis analyse TOUS ses
# arguments. Ce qu'il ne connaît pas laisse « FAUX » au journal et sort en 2.
printf '%s\n' "$*" >> "$BAC/appels"
printf '%s\n' "${KUBECONFIG:-}" >> "$BAC/kubeconfigs"
verbe=""; ns=""; type=""; nom=""
interdit() { echo "Error from server (Forbidden): $type \"$nom\" is forbidden: User \"u\" cannot delete resource \"$type\" in API group \"apps\" in the namespace \"$ns\"" >&2; exit 1; }
while [ $# -gt 0 ]; do
    case "$1" in
        get|delete) verbe="$1"; shift ;;
        -n) [ $# -ge 2 ] || { echo "FAUX : -n sans valeur" >> "$BAC/appels"; exit 2; }; ns="$2"; shift 2 ;;
        --request-timeout=*) shift ;;
        --wait=false) shift ;;
        -*) echo "FAUX : option inconnue $1" >> "$BAC/appels"; exit 2 ;;
        *) if [ -z "$type" ]; then type="$1"; elif [ -z "$nom" ]; then nom="$1"
           else echo "FAUX : argument en trop $1" >> "$BAC/appels"; exit 2; fi; shift ;;
    esac
done
if [ -z "$verbe" ] || [ -z "$ns" ] || [ -z "$type" ] || [ -z "$nom" ]; then
    echo "FAUX : argv incomplet ou mal ordonné" >> "$BAC/appels"; exit 2
fi
[ "${KUBECTL_INJOIGNABLE:-0}" = 1 ] && { echo "The connection to the server 127.0.0.1:6443 was refused - did you specify the right host or port?" >&2; exit 1; }
[ "${KUBECTL_FORBIDDEN:-0}" = 1 ] && interdit
[ "${KUBECTL_TYPE_INCONNU:-0}" = 1 ] && { echo "error: the server doesn't have a resource type \"$type\"" >&2; exit 1; }
[ "$verbe" = delete ] && [ "${KUBECTL_ECHEC:-}" = "$type/$nom" ] && interdit
[ "${KUBECTL_LENT:-0}" = 1 ] && sleep 20
fic="$BAC/objets/$ns-$type-$nom"
case "$verbe" in
    get) [ -f "$fic" ] || { echo "Error from server (NotFound): $type \"$nom\" not found" >&2; exit 1; }
         printf '%s/%s\n' "$type" "$nom"; exit 0 ;;
    delete) [ -f "$fic" ] || { echo "Error from server (NotFound): $type \"$nom\" not found" >&2; exit 1; }
            [ "${KUBECTL_DELETE_MUET:-0}" = 1 ] || rm -f "$fic"
            printf '%s/%s deleted\n' "$type" "$nom"; exit 0 ;;
esac
exit 0
EOF
# Faux docker et faux k3s, en tête de PATH : leurs journaux prouvent leur silence.
cat > "$BAC/docker" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$BAC/appels-docker"
EOF
cat > "$BAC/k3s" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$BAC/appels-k3s"
EOF
chmod +x "$BAC/kubectl" "$BAC/docker" "$BAC/k3s"
existe() { : > "$BAC/objets/$1-$2-$3"; }
present() { test -f "$BAC/objets/$1-$2-$3" && echo présente || echo absente; }
lancer() { : > "$BAC/appels"; CODE=0; sortie="$(PATH="$BAC:$PATH" bash "$CIBLE" "$@" </dev/null 2>&1)" || CODE=$?; cat "$BAC/appels" >> "$BAC/cumul"; }
lancer_nobody() { : > "$BAC/appels"; CODE=0; sortie="$(PATH="$BAC:$PATH" setpriv --reuid=65534 --regid=65534 --clear-groups bash "$CIBLE" "$@" </dev/null 2>&1)" || CODE=$?; cat "$BAC/appels" >> "$BAC/cumul"; }
# Refus d'usage : code 2, et le journal d'appels est remis à zéro juste avant.
refus() { local l="$1"; shift; lancer "$@" -y; assert_code 2 "$CODE" "$l — rend 2"; assert_egal "" "$(cat "$BAC/appels")" "$l — sans appeler kubectl"; }
# Refus motivé : code attendu, motif dit, et aucun appel kubectl.
refus_motif() { local c="$1" m="$2" l="$3"; shift 3; lancer "$@" -y; assert_code "$c" "$CODE" "$l — rend $c"; assert_contient "$sortie" "$m" "$l — « $m » est dit"; assert_egal "" "$(cat "$BAC/appels")" "$l — sans appeler kubectl"; }

titre "Codes d'usage"
sortie="$(bash "$CIBLE" --help 2>&1)" && code=0 || code=$?
assert_code 0 "$code" "--help rend 0"
assert_contient "$sortie" "Codes de retour" "--help documente les codes de retour"
assert_contient "$sortie" "kube-system" "--help nomme les namespaces protégés"
assert_contient "$sortie" "Types acceptés" "--help donne la liste blanche des types"
lancer --option-inexistante; assert_code 2 "$CODE" "une option inconnue rend 2"
lancer; assert_code 2 "$CODE" "sans cible, le script rend 2"; assert_contient "$sortie" "Aucune cible" "et il dit ce qui manque"
refus "une cible sans « -n »" deployment/nginx
refus "« -n » sans cible" -n default
refus "une cible sans « / »" -n default nginx
refus "une cible à deux « / »" -n default a/b/c
refus "une cible en « - »" -n default -l/x

titre "Périmètre — liste blanche de types, et refus avant tout appel kubectl"
for cible in "pod,secret/x" "all/x" "Secret/x" "secrets.v1/x" "deployments.apps/x" "ns/production" \
             "ns/kube-system" "no/n1" "crds/x" "pvc/x" "secret/x" "pv/x" "clusterrole/x" "pod/-x" \
             "pod/X" "pod/x.."; do
    refus "type « $cible »" -n default "$cible"
done
refus "« --all » glissé en option" -n default pod/x --all
refus "namespace en majuscules" -n Default pod/x

titre "Nom court — c'est la forme canonique qui part à kubectl"
existe default deployments nginx
existe default configmaps x
lancer -n default deploy/nginx -n default cm/x -y
assert_code 0 "$CODE" "deploy/nginx et cm/x sont acceptés"
APPELS="$(cat "$BAC/appels")"
assert_contient "$APPELS" "delete deployments nginx" "« deploy » part sous « deployments »"
assert_contient "$APPELS" "delete configmaps x" "« cm » part sous « configmaps »"
assert_absent "$APPELS" "deploy " "aucune abréviation n'est transmise telle quelle"

titre "Refus avant toute suppression — namespace protégé, type hors liste"
existe default deployments nginx
for protege in kube-system kube-public kube-node-lease; do
    refus_motif 1 "Namespace protégé" "un objet de $protege est refusé" -n "$protege" deployment/nginx
done
refus_motif 2 "hors périmètre" "un Secret est refusé comme type hors liste" -n default secret/mot-de-passe
refus_motif 2 "hors périmètre" "un PersistentVolume aussi" -n default persistentvolume/pv-1
assert_egal "présente" "$(present default deployments nginx)" "et rien n'a été supprimé"

titre "Cible inexistante — le refus précède toute suppression"
lancer -n default deployment/nginx -n default deployment/absent -y
assert_code 1 "$CODE" "une cible inexistante rend 1"
assert_contient "$sortie" "inexistante" "le refus la nomme pour ce qu'elle est"
assert_contient "$sortie" "deployments/absent" "et nomme la cible fautive"
assert_egal "présente" "$(present default deployments nginx)" "l'autre cible, valide, est intacte"
assert_absent "$(cat "$BAC/appels")" "delete" "aucun delete n'a été appelé"
assert_egal "1" "$(grep -c '^get deployments nginx' "$BAC/appels" || true)" "la cible valide avait bien été relue"

titre "--dry-run — la liste, et rien d'autre"
lancer -n default deployment/nginx --dry-run
assert_code 0 "$CODE" "--dry-run rend 0"
assert_contient "$sortie" "namespace default" "il affiche le namespace"
assert_contient "$sortie" "deployments/nginx" "et le type sous sa forme canonique, avec le nom"
assert_egal "" "$(cat "$BAC/appels")" "sans appeler kubectl, delete compris"
assert_egal "présente" "$(present default deployments nginx)" "et sans rien supprimer"

titre "Confirmation — --yes seul, ASSUME_YES hérité ignoré (décision 45)"
lancer -n default deployment/nginx
assert_code 1 "$CODE" "sans terminal et sans --yes, le script rend 1"
assert_contient "$sortie" "--yes" "le message nomme l'option qui débloque la situation"
assert_absent "$sortie" "Échec (code" "aucune ligne du trap ERR : le refus est délibéré"
export ASSUME_YES=true
lancer -n default deployment/nginx
unset ASSUME_YES
assert_code 1 "$CODE" "un ASSUME_YES hérité, sans --yes, rend 1"
assert_egal "présente" "$(present default deployments nginx)" "et rien n'est supprimé"
if command -v script >/dev/null 2>&1; then
    # Avec un terminal, c'est confirm qui décide : ce cas seul prouve que
    # l'ASSUME_YES du parent est réellement remis à false (décision 45).
    CODE=0; sortie="$(printf 'n\n' | PATH="$BAC:$PATH" ASSUME_YES=true \
        script -qec "bash $CIBLE -n default deployment/nginx" /dev/null 2>&1)" || CODE=$?
    assert_code 1 "$CODE" "un ASSUME_YES hérité, avec un terminal, rend 1"
    assert_absent "$sortie" "Confirmation automatique" "l'ASSUME_YES du parent est ignoré"
    assert_contient "$sortie" "abandonné" "la question est posée et « n » l'écarte"
    assert_egal "présente" "$(present default deployments nginx)" "et rien n'est supprimé"
else
    saute_indisponible "ASSUME_YES hérité avec un terminal" "script (util-linux) absent"
fi

titre "Suppression — chaque cible relue absente, et chaque appel borné"
existe default configmaps reglages
lancer -n default deployment/nginx -n default configmap/reglages -y
assert_code 0 "$CODE" "deux cibles nommées sont supprimées"
assert_contient "$sortie" "[SUCCESS]" "le script le dit en [SUCCESS]"
assert_egal "absente" "$(present default deployments nginx)" "la première a disparu"
assert_egal "absente" "$(present default configmaps reglages)" "la seconde aussi"
APPELS="$(cat "$BAC/appels")"
assert_contient "$APPELS" "get deployments nginx -n default" "chaque cible est relue avant d'être supprimée"
assert_contient "$APPELS" "delete configmaps reglages -n default" "et supprimée par son nom, dans son namespace"
assert_egal "get" "$(head -n 1 "$BAC/appels" | cut -d' ' -f1)" "la relecture précède le premier delete"
assert_egal "get" "$(tail -n 1 "$BAC/appels" | cut -d' ' -f1)" "et la relecture finale juge seule de la disparition"
assert_contient "$APPELS" "--wait=false" "delete ne bloque pas sur un finalizer"
assert_absent "$APPELS" "--force" "aucun delete forcé"; assert_absent "$APPELS" "--grace-period" "aucune grâce écourtée"
assert_absent "$APPELS" "-l " "aucune suppression par sélecteur"; assert_absent "$APPELS" "--all" "ni par --all"
assert_egal "0" "$(grep -cvE -- '--request-timeout=[0-9]+s' "$BAC/cumul" || true)" "aucun appel sans --request-timeout, cumul de tous les lancements"
assert_non_vide "$(grep -cE '^delete ' "$BAC/cumul" || true)" "le cumul porte bien des delete"
assert_non_vide "$(grep -cE '^get ' "$BAC/cumul" || true)" "et des relectures"

titre "Cible encore présente après delete — le nettoyage est dit inachevé"
existe default deployments nginx
export KUBECTL_DELETE_MUET=1
lancer -n default deployment/nginx -y
unset KUBECTL_DELETE_MUET
assert_code 1 "$CODE" "une cible encore présente rend 1"
assert_contient "$sortie" "encore présent" "le script nomme ce qui reste"
assert_contient "$sortie" "deployments/nginx" "et le nomme précisément"
assert_absent "$sortie" "[SUCCESS]" "jamais [SUCCESS] : le nettoyage est inachevé"

titre "Diagnostics — chaque échec dit pour ce qu'il est"
export KUBECTL_INJOIGNABLE=1
lancer -n default deployment/nginx -y
unset KUBECTL_INJOIGNABLE
assert_code 1 "$CODE" "un apiserver injoignable rend 1"
assert_contient "$sortie" "[ERROR]" "l'échec est signalé en [ERROR]"
assert_contient "$sortie" "Apiserver injoignable" "il est nommé pour ce qu'il est"
assert_contient "$sortie" "was refused" "la raison rendue par kubectl est montrée"
assert_egal "présente" "$(present default deployments nginx)" "et rien n'est supprimé"
export KUBECTL_FORBIDDEN=1
lancer -n default deployment/nginx -y
unset KUBECTL_FORBIDDEN
assert_code 1 "$CODE" "un refus de l'apiserver rend 1"
assert_contient "$sortie" "Droits insuffisants" "le refus est nommé pour ce qu'il est"
assert_contient "$sortie" "is forbidden" "et le message de kubectl est montré"
export KUBECTL_TYPE_INCONNU=1
lancer -n default deployment/nginx -y
unset KUBECTL_TYPE_INCONNU
assert_code 1 "$CODE" "un type absent de l'apiserver rend 1"
assert_contient "$sortie" "Type inconnu" "il n'est pas pris pour un apiserver muet"
assert_contient "$sortie" "doesn't have a resource type" "et le message de kubectl est montré"
assert_absent "$sortie" "injoignable" "l'apiserver n'est pas accusé à tort"
export DELAI_TEST=1 KUBECTL_LENT=1
lancer -n default deployment/nginx -y
unset DELAI_TEST KUBECTL_LENT
assert_code 1 "$CODE" "un appel qui dépasse le délai rend 1"
assert_contient "$sortie" "Délai dépassé" "le dépassement est nommé"
assert_absent "$sortie" "apiserver" "et n'est pas imputé à l'apiserver"
sortie="$(PATH="/usr/bin:/bin" bash "$CIBLE" -n default deployment/nginx -y 2>&1)" && code=0 || code=$?
assert_code 1 "$code" "sans kubectl, le script rend 1"
assert_contient "$sortie" "Commande(s) requise(s) introuvable(s) : kubectl" "c'est le message de require_cmd"

titre "Échec partiel — les cibles suivantes restent tentées, et le bilan dit tout"
existe default deployments a
existe default deployments b
existe default deployments c
export KUBECTL_ECHEC=deployments/b
lancer -n default deployments/a -n default deployments/b -n default deployments/c -y
unset KUBECTL_ECHEC
assert_code 1 "$CODE" "l'échec de la 2e de 3 cibles rend 1"
assert_egal "absente" "$(present default deployments c)" "la 3e cible a tout de même été supprimée"
assert_contient "$sortie" "Supprimées : default deployments/a default deployments/c" "le bilan nomme les cibles supprimées"
assert_contient "$sortie" "default deployments/b — Droits insuffisants" "et celles en échec, avec leur raison"
assert_absent "$sortie" "Non tentées" "aucune cible n'est restée non tentée"
assert_absent "$sortie" "[SUCCESS]" "jamais [SUCCESS] sur un nettoyage partiel"

titre "Ce que le script ne fait pas — preuves de comportement"
assert_egal "" "$(cat "$BAC/appels-docker")" "aucun appel à docker"
assert_egal "" "$(cat "$BAC/appels-k3s")" "aucun appel à k3s, donc aucun « k3s kubectl »"
assert_absent "$(cat "$BAC/cumul")" "--kubeconfig" "kubectl est appelé sans --kubeconfig"
assert_absent "$(cat "$BAC/cumul")" "k3s" "ni le moindre chemin k3s"
assert_egal "$BAC/kubeconfig" "$(sort -u "$BAC/kubeconfigs")" "KUBECONFIG reste celui du test, à chaque appel"
assert_absent "$(cat "$BAC/cumul")" "FAUX" "le faux kubectl n'a jamais eu à refuser un argv"
assert_absent "$(cat "$BAC/cumul")" "get all" "« get all » n'est pas employé"
if command -v setpriv >/dev/null 2>&1; then
    existe default configmaps sansroot
    lancer_nobody -n default configmap/sansroot -y
    assert_code 0 "$CODE" "sans root, le cas nominal aboutit"
    assert_contient "$sortie" "[SUCCESS]" "et se dit terminé"
    assert_egal "absente" "$(present default configmaps sansroot)" "l'objet est bien supprimé"
else
    saute_indisponible "exécution sans root" "setpriv (util-linux) absent"
fi

bilan "TASK-061 / cleanup-resources.sh"
