#!/usr/bin/env bash
# tests/integration/resource-usage.test.sh — Kubernetes/Maintenance/resource-usage.sh.
# Aucun cluster réel : un faux kubectl rend les sorties et les codes du vrai — y
# compris « Metrics API not available » et « ServiceUnavailable » — et note ses
# arguments.
_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_dir/lib/common.sh" ] && [ "$_dir" != "/" ]; do _dir="$(dirname "$_dir")"; done
source "$_dir/lib/common.sh"
source "$SCRIPTS_ROOT/tests/lib/assert.sh"
CIBLE="$SCRIPTS_ROOT/Kubernetes/Maintenance/resource-usage.sh"
if [ ! -e /.dockerenv ]; then
    saute_indisponible "resource-usage.sh" "hors conteneur : un vrai kubectl ou un vrai cluster fausserait le relevé"
    bilan "TASK-059 / resource-usage.sh"
fi
BAC="$(mktemp -d)"; export BAC
trap 'rm -rf "$BAC"' EXIT
present() { test -e "$1" && echo présente || echo absente; }
: > "$BAC/tous"
# Le faux kubectl tient les formats, les messages et les codes du vrai.
# « --no-headers » y retire la ligne d'intitulés comme sur le vrai ; KUBECTL_REFUS
# nomme le relevé que le serveur refuse ; « No resources found » sort sur stderr
# avec le code 0 ; un namespace inconnu rend le NotFound du vrai — celui que
# « top pods -n inconnu » ne rendrait pas.
cat > "$BAC/kubectl" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" | tee -a "$BAC/appels" >> "$BAC/tous"
coupe=0
case " $* " in *" --no-headers "*) coupe=1 ;; esac
[ "${KUBECTL_INJOIGNABLE:-0}" = 1 ] && { echo "The connection to the server 127.0.0.1:6443 was refused" >&2; exit 1; }
case " ${KUBECTL_REFUS:-} " in *" $1 $2 "*) echo "Error from server (Forbidden): $2 is forbidden" >&2; exit 1 ;; esac
if [ "$1" = top ]; then
    case "${KUBECTL_METRIQUES:-ok}" in
        ok) ;;
        indisponible) echo "Error from server (ServiceUnavailable): the server is currently unable to handle the request (get $2.metrics.k8s.io)" >&2; exit 1 ;;
        *) echo "error: Metrics API not available" >&2; exit 1 ;;
    esac
fi
[ "$1" = top ] && [ "$2" = pods ] && [ "${KUBECTL_PODS_KO:-0}" = 1 ] && { echo "error: unable to retrieve metrics for pods" >&2; exit 1; }
if [ "$1" = get ] && [ "$2" = namespace ]; then
    [ -e "$BAC/get-namespace-$3" ] || { echo "Error from server (NotFound): namespaces \"$3\" not found" >&2; exit 1; }
    printf '%s\n' "$3   Active   10d"
    exit 0
fi
fic="$BAC/$1-$2"
[ -e "$fic" ] || { echo "Error from server (NotFound): the server could not find the requested resource" >&2; exit 1; }
[ -s "$fic" ] || { echo "No resources found" >&2; exit 0; }
if [ "$coupe" = 1 ]; then tail -n +2 "$fic"; else cat "$fic"; fi
EOF
chmod +x "$BAC/kubectl"
# Ni K3s ni systemd n'ont leur place ici : leurs faux laissent une trace.
for outil in k3s systemctl; do printf '#!/bin/sh\ntouch "%s/%s-appele"\n' "$BAC" "$outil" > "$BAC/$outil" && chmod +x "$BAC/$outil"; done
CODE=0; sortie=""
# Chaque lancer repart d'un journal vierge : « appels » ne porte que sur le cas.
lancer() { : > "$BAC/appels"; sortie="$(PATH="$BAC:$PATH" bash "$CIBLE" "$@" 2>&1)" && CODE=0 || CODE=$?; }
# Plusieurs affectations d'un coup : un cas peut en demander deux.
avec() { local v; for v in "$@"; do export "${v?}"; done; lancer; for v in "$@"; do unset "${v%%=*}"; done; }
# Lignes de la sortie qui répondent au motif : c'est le tableau tel qu'il se lit.
lignes() { printf '%s\n' "$sortie" | grep -cE "$1"; }
REEL_TIMEOUT="$(command -v timeout)"

# Le décrivant d'un nœud, au format réel : Capacity: et Allocatable: complets —
# les grandeurs que le script ne doit pas confondre avec cpu et memory y sont —
# puis System Info: et le tableau « Allocated resources: », sans deux-points.
noeud() {   # <nom> <cpu> <mémoire> <cpu allouable> <mémoire allouable>
    printf '%s\n' \
        "Name:               $1" \
        "Roles:              control-plane" \
        "Labels:             kubernetes.io/hostname=$1" \
        "                    node-role.kubernetes.io/control-plane=" \
        "Annotations:        node.alpha.kubernetes.io/ttl: 0" \
        "                    volumes.kubernetes.io/controller-managed-attach-detach: true" \
        "Capacity:" \
        "  cpu:                $2" \
        "  ephemeral-storage:  101901099Ki" \
        "  hugepages-1Gi:      0" \
        "  hugepages-2Mi:      0" \
        "  memory:             $3" \
        "  pods:               110" \
        "Allocatable:" \
        "  cpu:                $4" \
        "  ephemeral-storage:  93890275093" \
        "  hugepages-1Gi:      0" \
        "  hugepages-2Mi:      0" \
        "  memory:             $5" \
        "  pods:               110" \
        "System Info:" \
        "  Container Runtime Version:  containerd://1.7.20-k3s1" \
        "  Kubelet Version:            v1.31.4+k3s1" \
        "Allocated resources:" \
        "  (Total limits may be over 100 percent, i.e., overcommitted.)" \
        "  Resource           Requests      Limits" \
        "  --------           --------      ------" \
        "  cpu                350m (9%)     100m (2%)" \
        "  memory             200Mi (2%)    500Mi (6%)" \
        "  ephemeral-storage  0 (0%)        0 (0%)" \
        "  hugepages-1Gi      0 (0%)        0 (0%)" \
        "Events:              <none>"
}

# Formes réelles : « kubectl top » rend un tableau à en-tête, « describe nodes »
# deux nœuds décrits, « get namespace » le namespace demandé.
metriques() {
    printf '%s\n' "NAME     CPU(cores)   CPU%   MEMORY(bytes)   MEMORY%" \
                  "node-1   120m         3%     1500Mi          18%" > "$BAC/top-nodes"
    printf '%s\n' "NAMESPACE    NAME          CPU(cores)   MEMORY(bytes)" \
                  "kube-system  coredns-abc   4m           18Mi" \
                  "default      web-1         12m          64Mi" > "$BAC/top-pods"
    printf '%s\n' "node-1   Ready   control-plane   10d   v1.31.4" > "$BAC/get-nodes"
    printf '%s\n' "kube-system   Active   10d" > "$BAC/get-namespace-kube-system"
    { noeud node-1 4 8123456Ki 3800m 7600000Ki
      noeud node-2 8 16234567Ki 7800m 15000000Ki; } > "$BAC/describe-nodes"
}

titre "Codes d'usage"
sortie="$(bash "$CIBLE" --help 2>&1)" && code=0 || code=$?
assert_code 0 "$code" "--help rend 0"
assert_contient "$sortie" "Codes de retour" "--help documente les codes de retour"
assert_contient "$sortie" "kubectl top nodes" "--help documente le mode avec métriques"
assert_contient "$sortie" "capacité et l'allocatable" "--help documente le mode sans métriques"
bash "$CIBLE" --option-inexistante >/dev/null 2>&1 && code=0 || code=$?
assert_code 2 "$code" "une option inconnue rend 2"
sortie="$(bash "$CIBLE" --namespace 2>&1)" && code=0 || code=$?
assert_code 2 "$code" "--namespace sans valeur rend 2"
assert_contient "$sortie" "[ERROR]" "et le manque de valeur est signalé en [ERROR]"
# Une valeur en tiret serait transmise à kubectl : le refus précède tout appel.
lancer --namespace -A
assert_egal "2 0" "$CODE $(wc -l < "$BAC/appels")" "--namespace -A rend 2, sans tenter le moindre appel"

titre "kubectl introuvable"
sortie="$(PATH="/usr/bin:/bin" bash "$CIBLE" 2>&1)" && CODE=0 || CODE=$?
assert_code 1 "$CODE" "sans kubectl, le script rend 1"
assert_contient "$sortie" "[ERROR]" "l'absence est signalée en [ERROR]"
assert_contient "$sortie" "kubectl" "et le message nomme kubectl"
assert_contient "$sortie" "Commande(s) requise(s) introuvable(s) : kubectl" "c'est le message de require_cmd, pas un autre"
assert_absent  "$sortie" "command not found" "aucun message brut du shell ne filtre"

titre "API metrics disponible — la garde de contraste"
metriques
lancer
appels="$(cat "$BAC/appels")"
assert_code 0 "$CODE" "avec métriques, le relevé rend 0"
assert_contient "$sortie" "[SUCCESS]" "et il le dit en [SUCCESS]"
assert_contient "$sortie" "node-1   120m" "le CPU et la mémoire du nœud sont affichés tels quels"
assert_contient "$sortie" "web-1         12m" "ceux des pods aussi"
# Les intitulés viennent de kubectl : le script ne demande pas --no-headers, que
# le faux respecte comme le vrai.
assert_contient "$sortie" "NAME     CPU(cores)" "l'intitulé du tableau des nœuds figure"
assert_contient "$sortie" "NAMESPACE    NAME" "comme celui du tableau des pods"
assert_absent  "$appels" "--no-headers" "et --no-headers n'est demandé nulle part"
assert_contient "$appels" "top nodes --request-timeout=5s" "« kubectl top nodes » est demandé, borné"
assert_contient "$appels" "top pods -A --request-timeout=5s" "puis « kubectl top pods » sur tous les namespaces"
assert_contient "$(head -1 "$BAC/appels")" "get nodes" "la sonde de l'apiserver ouvre le relevé, avant « top »"
assert_absent  "$appels" "describe" "aucun repli n'est tenté quand les métriques répondent"
assert_absent  "$sortie" "[WARN]" "sans aucun avertissement"

titre "Namespace désigné, puis pods sans métrique à rendre"
lancer --namespace kube-system
assert_code 0 "$CODE" "--namespace rend 0"
assert_contient "$sortie" "pods (namespace kube-system)" "la rubrique annonce la portée demandée"
assert_contient "$(cat "$BAC/appels")" "get namespace kube-system --request-timeout=5s" "l'existence du namespace est vérifiée, appel borné"
assert_contient "$(cat "$BAC/appels")" "top pods -n kube-system --request-timeout=5s" "les pods sont demandés pour ce seul namespace"
assert_absent  "$(cat "$BAC/appels")" " -A " "et -A n'est pas employé"
: > "$BAC/top-pods"
lancer
assert_code 0 "$CODE" "aucun pod à relever : le script rend 0, ce n'est pas une panne"
assert_contient "$sortie" "[INFO] Aucun pod" "il le dit en [INFO]"
assert_absent  "$sortie" "No resources found" "la sortie d'erreur de kubectl n'entre pas dans la liste"
assert_contient "$sortie" "[SUCCESS]" "le relevé reste complet"
# L'absence de pods se lit à l'annonce et au tableau des nœuds qui demeure, non à
# une sortie vide : un script devenu muet ne passerait pas pour autant.
assert_contient "$sortie" "node-1   120m" "le tableau des nœuds, lui, est toujours là"

titre "Namespace inconnu — la vérification qui manquait"
metriques
lancer --namespace absent
assert_code 1 "$CODE" "un namespace inconnu rend 1, pas un relevé vide"
assert_contient "$sortie" "Namespace inconnu : absent" "il est nommé pour ce qu'il est"
assert_contient "$sortie" 'namespaces "absent" not found' "le message de l'apiserver est montré tel quel"
assert_absent  "$(cat "$BAC/appels")" "top pods" "aucun relevé de pods n'est tenté"
assert_absent  "$(cat "$BAC/appels")" "top nodes" "aucun relevé de métriques non plus : le refus précède"
assert_absent  "$sortie" "[SUCCESS]" "et rien n'est déclaré terminé"

titre "API metrics absente — repli sur la capacité des nœuds"
metriques
avec KUBECTL_METRIQUES=0
assert_code 0 "$CODE" "sans API metrics, le relevé rend 0 : ce n'est pas une panne"
assert_contient "$sortie" "[WARN] API metrics absente" "l'absence est dite en [WARN], la cause nommée"
assert_contient "$(cat "$BAC/appels")" "describe nodes --request-timeout=30s" "« describe nodes » porte son propre délai, plus long"
assert_contient "$sortie" "8123456Ki" "la capacité mémoire du nœud est affichée"
assert_contient "$sortie" "3800m" "l'allocatable CPU aussi, distinct de la capacité"
assert_absent  "$sortie" "Allocatable:" "le décrivant n'est pas rendu tel quel"
assert_absent  "$(cat "$BAC/appels")" "top pods" "aucun relevé de pods n'est tenté sans métriques"
assert_contient "$sortie" "[SUCCESS]" "le relevé reste déclaré terminé"
# Deux nœuds décrits : chacun sa ligne, sa capacité et son allocatable — et rien
# d'autre dans les colonnes CPU et mémoire.
assert_egal "2" "$(lignes '^  node-[12] ')" "chaque nœud a sa ligne"
assert_egal "1" "$(lignes '^  node-1 +4 +3800m +8123456Ki +7600000Ki$')" "node-1 : sa capacité et son allocatable"
assert_egal "1" "$(lignes '^  node-2 +8 +7800m +16234567Ki +15000000Ki$')" "node-2 : les siennes, distinctes"
assert_absent "$sortie" "ephemeral-storage" "l'ephemeral-storage ne se glisse pas dans les colonnes"
assert_absent "$sortie" "101901099Ki" "ni sa valeur"
assert_absent "$sortie" "hugepages" "ni les hugepages"
assert_absent "$sortie" "350m" "ni les demandes d'« Allocated resources »"
assert_absent "$sortie" "200Mi" "ni leur mémoire"
assert_absent "$sortie" "0 (0%)" "ni le reste de ce tableau"

titre "API metrics installée mais en panne — la même règle que l'absence"
metriques
avec KUBECTL_METRIQUES=indisponible
assert_code 0 "$CODE" "une API metrics en panne ne fait pas échouer le relevé"
assert_contient "$sortie" "[WARN] API metrics indisponible" "la cause est nommée : indisponible, et non absente"
assert_contient "$sortie" "8123456Ki" "la capacité et l'allocatable prennent le relais"
assert_contient "$(cat "$BAC/appels")" "describe nodes" "« describe nodes » est appelé à sa place"
assert_absent  "$sortie" "[ERROR]" "sans erreur : l'apiserver, lui, a répondu"
assert_contient "$sortie" "[SUCCESS]" "et le relevé est déclaré terminé"

titre "« top nodes » sans tableau : la rubrique n'a rien rendu"
metriques
: > "$BAC/top-nodes"
lancer
assert_code 1 "$CODE" "une liste de nœuds vide rend 1 : le relevé est amputé"
assert_contient "$sortie" "Aucune métrique de nœud" "la rubrique vide est nommée"
assert_absent  "$sortie" "[SUCCESS]" "et jamais [SUCCESS] (A78)"

titre "Une rubrique illisible interdit le [SUCCESS] (A78)"
metriques
avec KUBECTL_PODS_KO=1
assert_code 1 "$CODE" "des métriques de pods illisibles rendent 1"
assert_contient "$sortie" "Relevé impossible : CPU et mémoire des pods" "la rubrique est nommée"
assert_absent  "$sortie" "[SUCCESS]" "et jamais [SUCCESS] : un relevé amputé n'est pas terminé"
rm -f "$BAC/describe-nodes"
avec KUBECTL_METRIQUES=0
assert_code 1 "$CODE" "un repli illisible rend 1"
assert_contient "$sortie" "ne connaît pas la ressource" "la cause rendue par kubectl est distinguée"
assert_absent  "$sortie" "[SUCCESS]" "sans [SUCCESS] : rien n'a pu être relevé"
metriques
avec KUBECTL_METRIQUES=0
assert_code 0 "$CODE" "contraste : la description revenue, le repli rend 0"

titre "Apiserver injoignable, puis droit refusé sur la sonde"
avec KUBECTL_INJOIGNABLE=1
assert_code 1 "$CODE" "un apiserver injoignable rend 1"
assert_contient "$sortie" "[ERROR]" "l'échec est signalé en [ERROR]"
assert_contient "$sortie" "apiserver" "il nomme l'apiserver"
assert_contient "$sortie" "was refused" "la raison rendue par kubectl est montrée"
assert_egal "1" "$(wc -l < "$BAC/appels")" "un seul appel est tenté : la sonde arrête le relevé"
avec KUBECTL_REFUS="get nodes"
assert_code 1 "$CODE" "un « get nodes » refusé rend 1"
assert_contient "$sortie" "Droits insuffisants" "le refus est nommé pour ce qu'il est"
assert_absent  "$sortie" "apiserver ne répond pas" "un refus de droits n'est pas un apiserver muet"

titre "Refus de droits sur les relevés de métriques et de repli"
metriques
avec KUBECTL_REFUS="top nodes"
assert_code 1 "$CODE" "un « top nodes » refusé rend 1"
assert_contient "$sortie" "Droits insuffisants" "le refus est nommé"
assert_absent  "$sortie" "[SUCCESS]" "et jamais [SUCCESS]"
assert_absent  "$(cat "$BAC/appels")" "describe" "un refus n'est pas une API absente : aucun repli"
avec KUBECTL_REFUS="describe nodes" KUBECTL_METRIQUES=0
assert_code 1 "$CODE" "un « describe nodes » refusé rend 1"
assert_contient "$sortie" "Droits insuffisants" "le refus est nommé là aussi"
assert_absent  "$sortie" "[SUCCESS]" "sans [SUCCESS] : la capacité n'a pas été relevée"

titre "Délai dépassé — « timeout » enveloppe l'appel et le dit"
metriques
: > "$BAC/timeout-appels"
# Un faux « timeout » : il n'intercepte que « describe nodes » et rend 124 comme
# le vrai au bout du délai — l'attente réelle serait de 32 secondes.
cat > "$BAC/timeout" <<EOF
#!/bin/sh
case "\$*" in
    *" describe nodes "*)
        printf '%s\n' "\$*" >> "$BAC/timeout-appels"
        exit 124 ;;
    *) exec $REEL_TIMEOUT "\$@" ;;
esac
EOF
chmod +x "$BAC/timeout"
avec KUBECTL_METRIQUES=0
rm -f "$BAC/timeout"
assert_code 1 "$CODE" "un « describe nodes » qui expire rend 1"
assert_contient "$sortie" "[ERROR]" "l'échec est signalé en [ERROR]"
assert_contient "$sortie" "délai dépassé" "le délai est nommé pour ce qu'il est"
assert_absent  "$sortie" "injoignable" "et non pris pour un apiserver injoignable"
assert_contient "$(cat "$BAC/timeout-appels")" "32 kubectl describe nodes --request-timeout=30s" "« timeout » reçoit le délai propre à « describe nodes », majoré de 2 s"

titre "kubectl seul, appels bornés, lecture seule"
assert_egal "0" "$(grep -vcE -- '--request-timeout=[0-9]+s' "$BAC/tous" || true)" "chaque appel kubectl de la suite porte --request-timeout"
assert_contient "$(cat "$BAC/tous")" "get namespace kube-system --request-timeout=5s" "dont la vérification du namespace"
assert_contient "$(cat "$BAC/tous")" "describe nodes --request-timeout=30s" "et « describe nodes », avec son délai propre"
assert_egal "0" "$(grep -vcE '^(get nodes|get namespace|top nodes|top pods|describe nodes) ' "$BAC/tous" || true)" "aucun appel ne sort des relevés attendus"
for verbe in delete apply patch exec cordon drain scale rollout edit create; do
    assert_absent "$(cat "$BAC/tous")" "$verbe" "aucun appel « $verbe » : rien n'est modifié sur le cluster"
done
assert_absent "$(cat "$CIBLE")" "k3s.yaml" "aucune référence à /etc/rancher/k3s/k3s.yaml : kubectl résout son kubeconfig"
assert_absent "$(cat "$CIBLE")" "require_root" "aucun require_root : le script s'exécute sans root"
assert_egal "absente absente" "$(present "$BAC/k3s-appele") $(present "$BAC/systemctl-appele")" "ni k3s ni systemctl ne sont appelés"

bilan "TASK-059 / resource-usage.sh"
