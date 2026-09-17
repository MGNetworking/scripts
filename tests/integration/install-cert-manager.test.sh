#!/usr/bin/env bash
# tests/integration/install-cert-manager.test.sh — Kubernetes/Installation/install-cert-manager.sh.
# AUCUNE INSTALLATION RÉELLE : un faux helm et un faux kubectl en tête de PATH,
# aux codes et messages réels, traçant leurs arguments. Ni cluster, ni réseau.
_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_dir/lib/common.sh" ] && [ "$_dir" != "/" ]; do _dir="$(dirname "$_dir")"; done
source "$_dir/lib/common.sh"
source "$SCRIPTS_ROOT/tests/lib/assert.sh"

CIBLE="$SCRIPTS_ROOT/Kubernetes/Installation/install-cert-manager.sh"
if [ ! -e /.dockerenv ]; then
    saute_indisponible "install-cert-manager.sh" "hors conteneur : un vrai helm ou un vrai cluster fausserait les appels"
    bilan "TASK-065 / install-cert-manager.sh"
fi
BAC="$(mktemp -d)"; export BAC
trap 'rm -rf "$BAC"' EXIT
export SRV_CERT_MANAGER_VERSION="v1.21.2"
faux() { cat > "$BAC/$1"; chmod +x "$BAC/$1"; }
: > "$BAC/kubectl-tous"; : > "$BAC/helm-tous"

# Faux helm : « list » ne rend que ce qui est posé, « upgrade » pose la release
# et les CRD du chart — ce que fait le vrai, crds.enabled=true. Le tableau et le
# JSON sont rendus comme le vrai helm ; les variables HELM_* héritées sont
# journalisées pour prouver qu'elles arrivent vides.
faux helm <<'EOF'
#!/bin/sh
printf 'helm %s\n' "$*" >> "$BAC/helm-appels"
printf 'helm %s\n' "$*" >> "$BAC/helm-tous"
printf 'HELM_NAMESPACE=[%s] HELM_KUBECONTEXT=[%s]\n' "${HELM_NAMESPACE:-}" "${HELM_KUBECONTEXT:-}" >> "$BAC/helm-vars"
tous="$*"; cmd="$1"; shift
tout=non; json=non; ns=default; filtre=''
while [ $# -gt 0 ]; do
    case "$1" in
        -a|--all) tout=oui ;;
        -o|--output) shift; [ "${1:-}" = json ] && json=oui ;;
        --namespace|-n) shift; ns="${1:-}" ;;
        -f|--filter) shift; filtre="${1:-}" ;;
    esac
    shift
done
case "$cmd" in
upgrade)
    [ -z "${HELM_DORT:-}" ] || sleep "$HELM_DORT"
    v=""; prec=""
    for a in $tous; do [ "$prec" = "--version" ] && v="$a"; prec="$a"; done
    v="${HELM_POSE:-$v}"
    printf '%s' "$v" > "$BAC/release-version"
    printf 'deployed' > "$BAC/release-status"
    printf '%s' "$ns" > "$BAC/release-namespace"
    for c in certificates issuers clusterissuers; do
        [ "$c" = "${HELM_CRD_MANQUANTE:-}" ] || : > "$BAC/crd-$c.cert-manager.io"
    done
    exit 0 ;;
list)
    [ -z "${HELM_LISTE_ERREUR:-}" ] || { echo "$HELM_LISTE_ERREUR" >&2; exit "${HELM_LISTE_CODE:-1}"; }
    st=''; ver=''; rns=''
    if [ -f "$BAC/release-version" ]; then
        ver="$(cat "$BAC/release-version")"; st="$(cat "$BAC/release-status")"; rns="$(cat "$BAC/release-namespace")"
    fi
    # Sans « -a », helm ne rend que deployed et failed : une release
    # pending-install reste invisible. « -f » ne retient que le nom demandé, et
    # le namespace demandé doit être celui de la release.
    vu=non
    if [ -n "$ver" ] && [ "$filtre" = '^cert-manager$' ] && [ "$ns" = "$rns" ]; then
        case "$st" in
            deployed|failed) vu=oui ;;
            *) if [ "$tout" = oui ]; then vu=oui; fi ;;
        esac
    fi
    if [ "$vu" = non ]; then
        if [ "$json" = oui ]; then printf '[]\n'; else printf 'NAME \tNAMESPACE \tREVISION \tUPDATED \tSTATUS \tCHART \tAPP VERSION\n'; fi
        exit 0
    fi
    if [ "$json" = oui ]; then
        printf '[{"name":"cert-manager","namespace":"%s","revision":"1","updated":"2026-09-17 10:00:00.00000000 +0000 UTC","status":"%s","chart":"cert-manager-%s","app_version":"%s"}]\n' "$rns" "$st" "$ver" "$ver"
    else
        printf 'cert-manager \t%s \t1 \t2026-09-17 10:00:00 +0000 UTC \t%s \tcert-manager-%s \t%s\n' "$rns" "$st" "$ver" "$ver"
    fi
    exit 0 ;;
esac
exit 1
EOF

# Faux kubectl : les messages et codes du vrai, y compris NotFound sur une CRD
# absente et le dépassement de « rollout status ».
faux kubectl <<'EOF'
#!/bin/sh
printf 'kubectl %s\n' "$*" >> "$BAC/kubectl-appels"
printf 'kubectl %s\n' "$*" >> "$BAC/kubectl-tous"
[ -z "${KUBECTL_ERREUR:-}" ] || { echo "$KUBECTL_ERREUR" >&2; exit "${KUBECTL_CODE:-1}"; }
case "$1" in
    version) echo "Client Version: v1.31.0"; echo "Server Version: v1.31.0" ;;
    get)
        [ -f "$BAC/crd-$3" ] || { echo "Error from server (NotFound): customresourcedefinitions.apiextensions.k8s.io \"$3\" not found" >&2; exit 1; }
        echo "NAME                                        CREATED AT" ;;
    rollout)
        [ -f "$BAC/pret-${3#deployment/}" ] || { echo "error: timed out waiting for the condition" >&2; exit 1; }
        echo "deployment \"${3#deployment/}\" successfully rolled out" ;;
    *) exit 1 ;;
esac
EOF

CHEMIN="$BAC:$PATH"
neuf() {   # machine d'essai à zéro : pas de release, pas de CRD, déploiements prêts
    rm -f "$BAC"/release-* "$BAC"/crd-*
    for d in cert-manager cert-manager-cainjector cert-manager-webhook; do : > "$BAC/pret-$d"; done
    : > "$BAC/helm-appels"; : > "$BAC/kubectl-appels"; : > "$BAC/helm-vars"; }
poser() { printf '%s' "$1" > "$BAC/release-version"; printf '%s' "${2:-deployed}" > "$BAC/release-status";
          printf '%s' "${3:-cert-manager}" > "$BAC/release-namespace"; }
crds() { for c in certificates issuers clusterissuers; do : > "$BAC/crd-$c.cert-manager.io"; done; }
helm_appels() { cat "$BAC/helm-appels"; }
kubectl_appels() { cat "$BAC/kubectl-appels"; }
EXTRA=(); codes=""; code=0
lancer() { sortie="$(env PATH="$CHEMIN" "${EXTRA[@]}" timeout 60 bash "$CIBLE" "$@" </dev/null 2>&1)" && CODE=0 || CODE=$?; codes="$codes $CODE"; }
# Réponse tapée sous un pseudo-terminal : le terrain de la décision 45.
lancer_pty() { rep="$1"; shift; sortie="$(printf '%s\n' "$rep" | env PATH="$CHEMIN" "${EXTRA[@]}" timeout 60 script -qec "bash $CIBLE $*" /dev/null 2>&1)" && CODE=0 || CODE=$?; codes="$codes $CODE"; }

titre "Codes d'usage"
sortie="$(timeout 30 bash "$CIBLE" --help 2>&1)" && code=0 || code=$?
assert_code 0 "$code" "--help rend 0"
assert_contient "$sortie" "oci://quay.io/jetstack/charts/cert-manager" "--help nomme le chart OCI officiel"
assert_contient "$sortie" "crds.enabled=true" "--help dit que les CRD viennent du chart"
assert_contient "$sortie" "2  option" "--help documente les codes de retour"
timeout 30 bash "$CIBLE" --option-inexistante >/dev/null 2>&1 && code=0 || code=$?
assert_code 2 "$code" "une option inconnue rend 2"

titre "Version cible obligatoire"
sortie="$(env -u SRV_CERT_MANAGER_VERSION PATH="$CHEMIN" timeout 60 bash "$CIBLE" --yes </dev/null 2>&1)" && code=0 || code=$?
assert_code 1 "$code" "sans --version ni SRV_CERT_MANAGER_VERSION, le script rend 1"
assert_contient "$sortie" "obligatoire" "le message dit que la version est obligatoire"
assert_contient "$sortie" "SRV_CERT_MANAGER_VERSION" "et nomme la variable qui peut la porter"
neuf; lancer --dry-run --version 1.21.2
assert_code 1 "$CODE" "une version sans « v » est refusée en 1"
assert_contient "$sortie" "invalide" "le message dit la version invalide"
neuf; lancer --dry-run --version v1.21
assert_code 1 "$CODE" "une version à deux champs est refusée en 1"
neuf; lancer --dry-run --version v1.21.2.3
assert_code 1 "$CODE" "une version à quatre champs est refusée en 1"

titre "helm ou kubectl absent"
mkdir -p "$BAC/sans-helm" "$BAC/sans-kubectl"
for c in bash sh timeout id mkdir basename dirname date uname cat tee sed head rm; do
    ln -sf "$(command -v "$c")" "$BAC/sans-helm/$c"
    ln -sf "$(command -v "$c")" "$BAC/sans-kubectl/$c"
done
ln -sf "$BAC/kubectl" "$BAC/sans-helm/kubectl"
ln -sf "$BAC/helm" "$BAC/sans-kubectl/helm"
sortie="$(PATH="$BAC/sans-helm" timeout 60 bash "$CIBLE" --yes </dev/null 2>&1)" && code=0 || code=$?
assert_code 1 "$code" "sans helm, le script rend 1"
assert_contient "$sortie" "helm est introuvable" "le message nomme helm"
assert_contient "$sortie" "install-helm.sh" "et renvoie vers le script qui l'installe (TASK-063)"
sortie="$(PATH="$BAC/sans-kubectl" timeout 60 bash "$CIBLE" --yes </dev/null 2>&1)" && code=0 || code=$?
assert_code 1 "$code" "sans kubectl, le script rend 1"
assert_contient "$sortie" "kubectl est introuvable" "le message nomme kubectl"
assert_contient "$sortie" "install-kubectl.sh" "et renvoie vers TASK-062"

titre "Cluster injoignable, kubeconfig invalide, droits insuffisants"
neuf; EXTRA=(KUBECTL_ERREUR='The connection to the server 127.0.0.1:6443 was refused - did you specify the right host or port?'); lancer --yes; EXTRA=()
assert_code 1 "$CODE" "un apiserver injoignable rend 1"
assert_contient "$sortie" "injoignable" "le message nomme l'apiserver"
assert_contient "$sortie" "install-kubectl.sh" "et renvoie vers TASK-062"
assert_egal "" "$(helm_appels)" "aucun appel helm tant que le cluster ne répond pas"
neuf; EXTRA=(KUBECTL_ERREUR='error: error loading config file "/root/.kube/config": no such file or directory'); lancer --yes; EXTRA=()
assert_code 1 "$CODE" "un kubeconfig invalide rend 1"
assert_contient "$sortie" "Kubeconfig invalide" "message distinct de l'apiserver injoignable"
assert_absent "$sortie" "injoignable" "sans confondre les deux causes"
neuf; EXTRA=(KUBECTL_ERREUR='Error from server (Forbidden): namespaces is forbidden'); lancer --yes; EXTRA=()
assert_code 1 "$CODE" "un refus de droits rend 1"
assert_contient "$sortie" "Droits insuffisants" "troisième message, distinct des deux autres"

titre "« helm list » en échec"
neuf; EXTRA=(HELM_LISTE_ERREUR='Error from server (Forbidden): releases is forbidden'); lancer --yes; EXTRA=()
assert_code 1 "$CODE" "un « helm list » refusé rend 1"
assert_contient "$sortie" "Droits insuffisants" "le message nomme le refus de droits, comme pour kubectl"
assert_contient "$sortie" "helm list" "et l'appel fautif"
assert_absent "$(helm_appels)" "upgrade" "aucun helm upgrade n'est tenté"
assert_absent "$sortie" "[SUCCESS]" "aucun [SUCCESS] ne masque l'échec"

titre "--dry-run : version et commande, sans rien exécuter"
neuf; lancer --dry-run
assert_code 0 "$CODE" "--dry-run rend 0"
assert_contient "$sortie" "Changements prévus" "le résumé des changements est affiché"
assert_contient "$sortie" "v1.21.2" "la version voulue est affichée"
assert_contient "$sortie" "helm upgrade --install cert-manager oci://quay.io/jetstack/charts/cert-manager --version v1.21.2 --namespace cert-manager --create-namespace --set crds.enabled=true" "la commande helm prévue est affichée en entier"
assert_egal "" "$(helm_appels)" "aucun appel helm : ni install, ni upgrade"
assert_egal "" "$(kubectl_appels)" "aucun appel kubectl : le préflight reste local"
neuf; EXTRA=(SRV_CERT_MANAGER_VERSION=v1.20.0); lancer --dry-run --version v1.21.2; EXTRA=()
assert_contient "$sortie" "--version v1.21.2" "--version prime sur SRV_CERT_MANAGER_VERSION"
assert_absent "$sortie" "v1.20.0" "la version de l'environnement n'est pas retenue"

titre "Première installation — release et CRD absentes"
neuf; lancer --yes
assert_code 0 "$CODE" "l'installation rend 0"
assert_contient "$sortie" "v1.21.2 (première installation)" "le résumé annonce la première installation"
assert_contient "$(helm_appels)" "upgrade --install cert-manager oci://quay.io/jetstack/charts/cert-manager --version v1.21.2 --namespace cert-manager --create-namespace --set crds.enabled=true" "helm upgrade --install porte le chart OCI, la version épinglée, le namespace créé et les CRD"
assert_absent "$(helm_appels)" "helm install" "le script n'emploie jamais « helm install » seul"
assert_contient "$(kubectl_appels)" "rollout status deployment/cert-manager " "le déploiement cert-manager est attendu"
assert_contient "$(kubectl_appels)" "rollout status deployment/cert-manager-cainjector " "celui de cainjector aussi"
assert_contient "$(kubectl_appels)" "rollout status deployment/cert-manager-webhook " "celui du webhook aussi"
assert_contient "$(kubectl_appels)" "get crd certificates.cert-manager.io" "la CRD certificates est relue"
assert_contient "$(kubectl_appels)" "get crd issuers.cert-manager.io" "la CRD issuers est relue"
assert_contient "$(kubectl_appels)" "get crd clusterissuers.cert-manager.io" "la CRD clusterissuers est relue"
assert_contient "$sortie" "[SUCCESS]" "et l'installation est déclarée réussie"

titre "Release déjà à la version voulue"
neuf; poser v1.21.2; lancer --yes
assert_code 0 "$CODE" "une release à la version voulue rend 0"
assert_contient "$sortie" "déjà à la version voulue" "le script constate au lieu de refaire"
assert_contient "$sortie" "v1.21.2" "et affiche la version en place"
assert_contient "$(helm_appels)" "helm list -a -o json --namespace cert-manager -f ^cert-manager" "seule « helm list » a servi, avec -a et -o json"
assert_absent "$(helm_appels)" "upgrade" "aucun helm upgrade n'est tenté"
assert_egal "kubectl version --request-timeout=5s" "$(kubectl_appels)" "et aucun déploiement n'est attendu"

titre "Release plus ancienne — mise à jour confirmée"
neuf; poser v1.20.0; lancer --yes
assert_code 0 "$CODE" "une release plus ancienne est mise à jour, en 0"
assert_contient "$sortie" "v1.20.0 → v1.21.2" "le résumé montre installée → voulue"
assert_contient "$sortie" "Mettre à jour cert-manager" "et la confirmation parle de mise à jour"
assert_contient "$sortie" "notes de version" "et rappelle de lire les notes de version"
assert_contient "$(helm_appels)" "--version v1.21.2" "la mise à jour vise la version voulue"
assert_contient "$(helm_appels)" "--set crds.enabled=true" "avec les CRD du chart"
assert_contient "$sortie" "[SUCCESS]" "et se termine en succès"

titre "Version voulue inférieure à l'installée"
neuf; poser v1.22.0; lancer --yes
assert_code 1 "$CODE" "une version voulue inférieure rend 1"
assert_contient "$sortie" "inférieure à celle installée" "le message dit laquelle est inférieure"
assert_contient "$sortie" "rien n'a été modifié" "et que rien n'a été modifié"
assert_absent "$(helm_appels)" "upgrade" "aucun retour en arrière n'est tenté"
assert_absent "$sortie" "[SUCCESS]" "et rien n'est annoncé comme réussi"

titre "Comparaison numérique des versions"
neuf; poser v1.9.0; lancer --yes --version v1.10.0
assert_code 0 "$CODE" "v1.9.0 → v1.10.0 est une mise à jour, en 0"
assert_contient "$(helm_appels)" "--version v1.10.0" "la mise à jour vise v1.10.0"
assert_contient "$sortie" "v1.9.0 → v1.10.0" "le résumé montre installée → voulue"
neuf; poser v1.10.0; lancer --yes --version v1.9.0
assert_code 1 "$CODE" "v1.10.0 → v1.9.0 est refusé en 1, la comparaison n'étant pas lexicale"
assert_contient "$sortie" "inférieure à celle installée" "le refus nomme la version inférieure"
assert_absent "$(helm_appels)" "upgrade" "aucun retour en arrière n'est tenté"

titre "Release en échec ou opération en cours"
neuf; poser v1.21.2 failed; lancer --yes
assert_code 1 "$CODE" "une release en échec rend 1, même à la version voulue"
assert_contient "$sortie" "installation précédente en échec, à examiner" "le message dit ce que la release a de particulier"
assert_contient "$sortie" "helm history cert-manager -n cert-manager" "et renvoie vers helm history"
assert_absent "$(helm_appels)" "upgrade" "aucun helm upgrade n'est tenté par-dessus"
assert_absent "$sortie" "[SUCCESS]" "et rien n'est annoncé comme réussi"
neuf; poser v1.21.2 pending-install; crds; lancer --yes
assert_code 1 "$CODE" "une release « pending-install » rend 1, même avec les CRD présentes"
assert_contient "$sortie" "opération helm en cours ou interrompue" "le message nomme l'opération helm inachevée"
assert_absent "$sortie" "sans release Helm" "sans la confondre avec des CRD orphelines"
assert_absent "$(helm_appels)" "upgrade" "aucun helm upgrade n'est tenté"

titre "Dépassement du délai de helm"
neuf; EXTRA=(TIMEOUT_HELM=1 HELM_DORT=3); lancer --yes; EXTRA=()
assert_code 1 "$CODE" "un helm upgrade qui dépasse son délai rend 1"
assert_contient "$sortie" "124" "le message nomme le dépassement"
assert_contient "$sortie" "à moitié posée" "et prévient de l'état incertain de la release"
assert_absent "$sortie" "[SUCCESS]" "aucun [SUCCESS] ne masque le dépassement"

titre "Variables HELM_* héritées"
neuf; EXTRA=(HELM_NAMESPACE=kube-system HELM_KUBECONTEXT=autre); lancer --yes; EXTRA=()
assert_code 0 "$CODE" "l'installation aboutit malgré les variables héritées"
assert_contient "$(helm_appels)" "upgrade --install" "et helm est bien appelé"
heritees="$(grep -vcE '^HELM_NAMESPACE=\[\] HELM_KUBECONTEXT=\[\]$' "$BAC/helm-vars" || true)"
assert_egal "0" "$heritees" "HELM_NAMESPACE et HELM_KUBECONTEXT hérités arrivent vides à helm"

titre "CRD cert-manager.io sans release Helm"
neuf; crds; lancer --yes
assert_code 1 "$CODE" "des CRD sans release Helm rendent 1"
assert_contient "$sortie" "sans release Helm" "le message dit ce qui a été trouvé"
assert_contient "$sortie" "rien n'a été modifié" "et que rien n'a été modifié"
assert_absent "$(helm_appels)" "upgrade" "aucune adoption ni écrasement n'est tenté"

titre "Confirmation et décision 45"
neuf; lancer
assert_code 1 "$CODE" "hors terminal et sans --yes, le script rend 1"
assert_contient "$sortie" "--yes" "le message nomme l'option qui débloque la situation"
assert_absent "$sortie" "Échec (code" "aucune ligne du trap ERR : le refus est délibéré"
assert_absent "$(helm_appels)" "upgrade" "et rien n'est lancé"
neuf; EXTRA=(ASSUME_YES=true); lancer; EXTRA=()
assert_code 1 "$CODE" "un ASSUME_YES hérité, sans --yes, rend 1"
assert_absent "$(helm_appels)" "upgrade" "et rien n'est lancé"
neuf; lancer_pty n
assert_code 1 "$CODE" "une réponse « n » sous terminal abandonne en 1"
assert_contient "$sortie" "Installation abandonnée" "le refus est celui de confirm"
assert_absent "$(helm_appels)" "upgrade" "et rien n'est lancé"
neuf; EXTRA=(ASSUME_YES=true); lancer_pty n; EXTRA=()
assert_code 1 "$CODE" "sous terminal, un ASSUME_YES hérité ne confirme pas à la place du --yes"
assert_contient "$sortie" "Installation abandonnée" "c'est la réponse « n » qui décide"
neuf; lancer_pty o
assert_code 0 "$CODE" "une réponse « o » sous terminal installe, en 0"
assert_contient "$sortie" "[SUCCESS]" "et l'installation est déclarée réussie"

titre "Déploiement non prêt"
neuf; rm -f "$BAC/pret-cert-manager-webhook"; lancer --yes
assert_code 1 "$CODE" "un déploiement non prêt rend 1"
assert_contient "$sortie" "cert-manager-webhook" "le message nomme le déploiement non prêt"
assert_contient "$sortie" "délai de 180 s dépassé" "et nomme le dépassement du délai"
assert_contient "$sortie" "Rien n'a été désinstallé" "sans rien désinstaller"
assert_absent "$(helm_appels)" "uninstall" "aucun helm uninstall n'est tenté"
assert_absent "$sortie" "[SUCCESS]" "aucun [SUCCESS] ne masque l'échec partiel"

titre "Version relue et CRD après installation"
neuf; EXTRA=(HELM_POSE=v1.21.3); lancer --yes; EXTRA=()
assert_code 1 "$CODE" "une version relue différente de la voulue rend 1"
assert_contient "$sortie" "v1.21.3" "le message nomme la version relue"
assert_contient "$sortie" "différente de la voulue" "et dit pourquoi elle ne convient pas"
assert_absent "$sortie" "[SUCCESS]" "aucun [SUCCESS] ne masque l'écart de version"
neuf; EXTRA=(HELM_CRD_MANQUANTE=issuers); lancer --yes; EXTRA=()
assert_code 1 "$CODE" "une CRD manquante après installation rend 1"
assert_contient "$sortie" "CRD manquante(s) après installation : issuers.cert-manager.io" "le message nomme la CRD manquante"
assert_absent "$sortie" "[SUCCESS]" "aucun [SUCCESS] ne masque la CRD manquante"

titre "Ce que le script ne fait jamais"
assert_egal "0" "$(grep -c require_root "$CIBLE" || true)" "aucun require_root"
assert_egal "0" "$(grep -vE '^[[:space:]]*#' "$CIBLE" | grep -c 'k3s\.yaml' || true)" "aucune référence à k3s.yaml hors commentaire"
sans_delai="$(grep -v '^kubectl rollout status ' "$BAC/kubectl-tous" | grep -vc -- '--request-timeout=5s' || true)"
assert_egal "0" "$sans_delai" "chaque appel kubectl hors « rollout status » porte --request-timeout"
avec_delai="$(grep -c -- '^kubectl rollout status .*--request-timeout' "$BAC/kubectl-tous" || true)"
assert_egal "0" "$avec_delai" "« rollout status » ne le porte pas : il bornerait l'attente de 180 s à 5 s"
hors_forme="$(grep -vcE '^kubectl (version|get crd|rollout status) ' "$BAC/kubectl-tous" || true)"
assert_egal "0" "$hors_forme" "aucun appel kubectl ne sort de « version », « get crd » et « rollout status »"
assert_egal "0" "$(grep -cE 'uninstall|rollback|delete' "$BAC/helm-tous" || true)" "aucun helm uninstall, rollback ni delete de toute la suite"

cas2="non"; case "$codes" in *" 2"*) cas2="oui" ;; esac
assert_egal "non" "$cas2" "aucun chemin éprouvé ne rend 2 : le 2 reste réservé à l'usage"

bilan "TASK-065 / install-cert-manager.sh"
