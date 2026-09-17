#!/usr/bin/env bash
# tests/integration/configure-tls.test.sh — Kubernetes/Configuration/configure-tls.sh.
# AUCUN CLUSTER RÉEL : un faux kubectl en tête de PATH, aux codes et messages du
# vrai. Il lit le manifeste reçu sur stdin, le juge document par document et par
# clé parente, et refuse tout kind Certificate, CertificateRequest ou Secret.
_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_dir/lib/common.sh" ] && [ "$_dir" != "/" ]; do _dir="$(dirname "$_dir")"; done
source "$_dir/lib/common.sh"
source "$SCRIPTS_ROOT/tests/lib/assert.sh"

CIBLE="$SCRIPTS_ROOT/Kubernetes/Configuration/configure-tls.sh"
if [ ! -e /.dockerenv ]; then
    saute_indisponible "configure-tls.sh" "hors conteneur : un vrai kubectl ou un vrai cluster fausserait les appels"
    bilan "TASK-070 / configure-tls.sh"
fi
BAC="$(mktemp -d)"; export BAC
trap 'rm -rf "$BAC"' EXIT
faux() { cat > "$BAC/$1"; chmod +x "$BAC/$1"; }
: > "$BAC/kubectl-tous"; : > "$BAC/kubectl-appels"; : > "$BAC/sorties"
MAIL="acme@exemple.fr"

faux kubectl <<'SH'
#!/bin/sh
printf 'kubectl %s\n' "$*" >> "$BAC/kubectl-appels"
printf 'kubectl %s\n' "$*" >> "$BAC/kubectl-tous"
case " $* " in *" create "*|*" delete "*|*" patch "*|*" replace "*|*" edit "*|*" prune "*)
    printf 'verbe proscrit : %s\n' "$*" >&2; exit 3 ;; esac
[ -z "${KUBECTL_ERREUR:-}" ] || { printf '%s\n' "$KUBECTL_ERREUR" >&2; exit "${KUBECTL_CODE:-1}"; }
non() { printf 'manifeste : %s\n' "$1" >&2; exit 2; }
notfound() { printf 'Error from server (NotFound): %s not found\n' "$1" >&2; exit 1; }
# Enfants directs d'une clé, son « - » de liste compris, et eux seuls.
sous() { awk -v p="$2" 'BEGIN{d=-1} {match($0,/^ */); i=RLENGTH}
        d>=0 { if (i>d) {print; next}; d=-1 }
        $0 ~ ("^ *(- )?" p ":$") {d=i}' "$1"; }
exemplaire() {   # <fichier> : un document, jugé clé parente par clé parente
    f="$1"
    grep -qxE 'apiVersion: cert-manager.io/v1' "$f" || non 'apiVersion cert-manager.io/v1'
    grep -qxE 'kind: ClusterIssuer' "$f" || non 'kind ClusterIssuer'
    grep -qxE '    app.kubernetes.io/managed-by: mgnetworking' "$f" || non 'label managed-by'
    grep -qE '^  namespace:' "$f" && non 'un ClusterIssuer est une ressource de cluster, sans namespace'
    n="$(sed -n 's/^  name: \(letsencrypt-[a-z]*\)$/\1/p' "$f")"
    case "$n" in
        letsencrypt-staging)    srv="https://acme-staging-v02.api.letsencrypt.org/directory" ;;
        letsencrypt-production) srv="https://acme-v02.api.letsencrypt.org/directory" ;;
        *) non 'nom attendu : letsencrypt-staging ou letsencrypt-production' ;;
    esac
    sous "$f" acme > "$BAC/acme-$n"
    grep -qxE "    email: \"$ACME_EMAIL\"" "$BAC/acme-$n" || non "email ACME attendu, entre guillemets, sous acme de $n"
    grep -qxE "    server: $srv" "$BAC/acme-$n" || non "serveur $srv attendu sous acme de $n"
    sous "$BAC/acme-$n" privateKeySecretRef > "$BAC/cle-$n"
    grep -qxE "      name: $n-account-key" "$BAC/cle-$n" || non "privateKeySecretRef $n-account-key attendu"
    sous "$BAC/acme-$n" solvers > "$BAC/solv-$n"
    sous "$BAC/solv-$n" http01 > "$BAC/http01-$n"
    sous "$BAC/http01-$n" ingress > "$BAC/ing-$n"
    grep -qxE '            ingressClassName: traefik' "$BAC/ing-$n" || non "solveur HTTP-01 ingressClassName traefik attendu dans $n"
}
manifeste() {   # <nom> : lit stdin, exige deux documents, juge chacun
    m="$BAC/manifeste-$1"; cat > "$m"
    grep -qxE 'kind: (Certificate|CertificateRequest|Secret)$' "$m" && non 'kind Certificate, CertificateRequest ou Secret proscrit'
    rm -f "$BAC"/doc[0-9]
    awk -v b="$BAC" '/^---$/{n++; next} {print > (b "/doc" n+0)}
        END {if (n != 1) {print "manifeste : deux documents attendus" > "/dev/stderr"; exit 1}}' "$m" || exit 1
    exemplaire "$BAC/doc0"; exemplaire "$BAC/doc1"
}
case "$1 $2" in
    "get crd")  [ -f "$BAC/crd" ] || notfound 'customresourcedefinitions.apiextensions.k8s.io "clusterissuers.cert-manager.io"'
                printf 'NAME CREATED AT\nclusterissuers.cert-manager.io 2026-09-17T00:00:00Z\n' ;;
    "diff -f")  manifeste diff
                [ -z "${DIFF_ERREUR:-}" ] || { printf '%s\n' "$DIFF_ERREUR" >&2; exit "${DIFF_CODE:-1}"; }
                [ "${DIFF_CODE:-1}" = "0" ] && exit 0
                printf '%s\n' "${DIFF_TEXTE:-+    server: https://acme-v02.api.letsencrypt.org/directory}"; exit "${DIFF_CODE:-1}" ;;
    "apply -f") manifeste apply
                [ -z "${APPLY_ERREUR:-}" ] || { printf '%s\n' "$APPLY_ERREUR" >&2; exit "${APPLY_CODE:-1}"; }
                : > "$BAC/pose"
                printf 'clusterissuer.cert-manager.io/letsencrypt-staging created\nclusterissuer.cert-manager.io/letsencrypt-production created\n' ;;
    "get clusterissuers")
                [ -f "$BAC/pose" ] || exit 0
                [ "${3:-} ${4:-}" = "-l app.kubernetes.io/managed-by=mgnetworking" ] || {
                    printf 'clusterissuer.cert-manager.io/letsencrypt-staging\nclusterissuer.cert-manager.io/letsencrypt-production\nclusterissuer.cert-manager.io/etranger\n'; exit 0; }
                printf 'clusterissuer.cert-manager.io/letsencrypt-staging\n'
                [ -z "${POSE_UN_SEUL:-}" ] && printf 'clusterissuer.cert-manager.io/letsencrypt-production\n'
                exit 0 ;;
    "wait --for=condition=Ready")
                [ -z "${WAIT_ERREUR:-}" ] || { printf '%s\n' "$WAIT_ERREUR" >&2; exit "${WAIT_CODE:-1}"; }
                printf 'clusterissuer.cert-manager.io/%s condition met\n' "${3#clusterissuer/}" ;;
    *) printf 'kubectl inattendu : %s\n' "$*" >&2; exit 1 ;;
esac
SH

CHEMIN="$BAC:$PATH"
BASE=(DELAI_TEST=5 ATTENTE_TEST=20); EXTRA=(); CODE=0
lancer() { sortie="$(env PATH="$CHEMIN" SRV_K8S_ACME_EMAIL="$MAIL" ACME_EMAIL="$MAIL" "${BASE[@]}" "${EXTRA[@]}" timeout 60 bash "$CIBLE" "$@" </dev/null 2>&1)" && CODE=0 || CODE=$?
           printf '%s\n' "$sortie" >> "$BAC/sorties"; }
# Réponse tapée sous un pseudo-terminal : le terrain de la décision 45.
lancer_pty() { rep="$1"; shift; sortie="$(printf '%s\n' "$rep" | env PATH="$CHEMIN" SRV_K8S_ACME_EMAIL="$MAIL" ACME_EMAIL="$MAIL" "${BASE[@]}" "${EXTRA[@]}" timeout 60 script -qec "bash $CIBLE $*" /dev/null 2>&1)" && CODE=0 || CODE=$?; }
sain() { : > "$BAC/crd"; rm -f "$BAC/pose"; : > "$BAC/kubectl-appels"; }
appels() { cat "$BAC/kubectl-appels"; }

titre "Codes d'usage"
sortie="$(timeout 30 bash "$CIBLE" --help 2>&1)" && code=0 || code=$?
assert_code 0 "$code" "--help rend 0"
assert_contient "$sortie" "SRV_K8S_ACME_EMAIL" "--help nomme la variable d'adresse"
assert_contient "$sortie" "2  option" "--help documente les codes de retour"
timeout 30 bash "$CIBLE" --option-inexistante >/dev/null 2>&1 && code=0 || code=$?
assert_code 2 "$code" "une option inconnue rend 2"

titre "Adresse ACME absente ou mal formée — jugée avant tout appel kubectl"
sain
for m in "" "acme" "acme@exemple" "acme@exemple.fr x"; do
    MAIL="$m"; lancer --yes
    assert_code 2 "$CODE" "l'adresse « $m » est refusée en 2"
done
MAIL="acme@exemple.fr"
assert_contient "$sortie" "SRV_K8S_ACME_EMAIL" "le refus nomme la variable à renseigner"
assert_egal "" "$(appels)" "aucun appel kubectl n'a eu lieu"

titre "kubectl absent"
mkdir -p "$BAC/sans-kubectl"
for c in bash sh timeout id mkdir basename dirname date uname cat tee sed head rm mktemp grep tr; do
    ln -sf "$(command -v "$c")" "$BAC/sans-kubectl/$c"; done
sortie="$(env PATH="$BAC/sans-kubectl" SRV_K8S_ACME_EMAIL="$MAIL" timeout 60 bash "$CIBLE" --yes </dev/null 2>&1)" && code=0 || code=$?
assert_code 1 "$code" "sans kubectl, le script rend 1"
assert_contient "$sortie" "kubectl est introuvable" "le message nomme kubectl"
assert_contient "$sortie" "install-kubectl.sh" "et renvoie vers TASK-062"

titre "Préflight : apiserver, kubeconfig, droits, webhook cert-manager"
sain; EXTRA=(KUBECTL_ERREUR='The connection to the server 127.0.0.1:6443 was refused - did you specify the right host or port?'); lancer --yes; EXTRA=()
assert_code 1 "$CODE" "un apiserver injoignable rend 1"; assert_contient "$sortie" "injoignable" "le message nomme l'apiserver"
assert_contient "$sortie" "install-kubectl.sh" "et renvoie vers TASK-062"
sain; EXTRA=(KUBECTL_ERREUR='error: error loading config file "/root/.kube/config": no such file or directory'); lancer --yes; EXTRA=()
assert_code 1 "$CODE" "un kubeconfig invalide rend 1"; assert_contient "$sortie" "Kubeconfig invalide" "message distinct de l'apiserver injoignable"
assert_absent "$sortie" "injoignable" "sans confondre les deux causes"
sain; EXTRA=(KUBECTL_ERREUR='Error from server (Forbidden): clusterissuers.cert-manager.io is forbidden'); lancer --yes; EXTRA=()
assert_code 1 "$CODE" "un refus de droits rend 1"; assert_contient "$sortie" "Droits insuffisants" "troisième message, distinct des deux autres"
# Message réel d'un webhook injoignable : il contient « connection refused », et
# ne doit pourtant pas être pris pour un apiserver muet.
WEBHOOK='Error from server (InternalError): error when creating "STDIN": Internal error occurred: failed calling webhook "webhook.cert-manager.io": failed to call webhook: Post "https://cert-manager-webhook.cert-manager.svc:443/validate?timeout=30s": dial tcp 10.43.0.1:443: connect: connection refused'
sain; EXTRA=(DIFF_CODE=2 DIFF_ERREUR="$WEBHOOK"); lancer --yes; EXTRA=()
assert_code 1 "$CODE" "un webhook cert-manager non prêt rend 1"
assert_contient "$sortie" "webhook.cert-manager.io" "le message nomme le webhook"
assert_absent "$sortie" "injoignable" "et l'apiserver n'est pas mis en cause à tort"
assert_absent "$(appels)" "apply" "rien n'est appliqué"

titre "CRD ClusterIssuer absente ou non servie"
sain; rm -f "$BAC/crd"; lancer --yes
assert_code 1 "$CODE" "une CRD ClusterIssuer absente rend 1"
assert_contient "$sortie" "CRD clusterissuers.cert-manager.io absente" "le message la nomme"
assert_absent "$sortie" "[SUCCESS]" "aucun [SUCCESS] ne masque l'absence"; assert_absent "$(appels)" "apply" "et rien n'est appliqué"
CRD_ERR='error: resource mapping not found for name: "letsencrypt-staging" from "STDIN": no matches for kind "ClusterIssuer" in version "cert-manager.io/v1"
ensure CRDs are installed first'
sain; EXTRA=(DIFF_CODE=2 DIFF_ERREUR="$CRD_ERR"); lancer --yes; EXTRA=()
assert_code 1 "$CODE" "un diff en erreur (code 2) rend 1"
assert_contient "$sortie" "CRD cert-manager.io/v1 absente ou non servie" "le message nomme la CRD"
assert_absent "$sortie" "injoignable" "et l'apiserver n'est pas mis en cause à tort"
assert_absent "$(appels)" "apply" "aucun apply n'est tenté après un diff en erreur"

titre "Idempotence, --dry-run et confirmation"
sain; EXTRA=(DIFF_CODE=0); lancer --yes; EXTRA=()
assert_code 0 "$CODE" "sans différence, le script rend 0"; assert_contient "$sortie" "déjà à l'état voulu" "il constate au lieu de refaire"
assert_absent "$(appels)" "apply" "aucun apply n'est tenté"
sain; lancer --dry-run
assert_code 0 "$CODE" "--dry-run rend 0"; assert_contient "$sortie" "Différence avec le cluster" "la différence est affichée"
assert_contient "$sortie" "[dry-run]" "et le dry-run est annoncé"
assert_contient "$(appels)" "diff -f - " "le manifeste est lu sur stdin"; assert_absent "$(appels)" "apply" "--dry-run n'appelle jamais apply"
assert_absent "$(appels)" "wait" "ni wait"
sain; lancer
assert_code 1 "$CODE" "hors terminal et sans --yes, un changement à faire rend 1"
assert_contient "$sortie" "--yes" "le message nomme l'option qui débloque"; assert_absent "$(appels)" "apply" "et rien n'est appliqué"
sain; EXTRA=(ASSUME_YES=true); lancer; EXTRA=()
assert_code 1 "$CODE" "un ASSUME_YES hérité ne confirme pas à la place du --yes"; assert_absent "$(appels)" "apply" "et rien n'est appliqué"
sain; lancer_pty n
assert_code 1 "$CODE" "une réponse « n » sous terminal abandonne en 1"; assert_contient "$sortie" "Configuration abandonnée" "le refus est celui de confirm"

titre "Application, relecture et condition Ready"
sain; lancer_pty o
assert_code 0 "$CODE" "une réponse « o » sous terminal applique, en 0"; assert_contient "$sortie" "[SUCCESS]" "et le verdict est déclaré"
assert_contient "$(appels)" "apply -f - " "le manifeste est appliqué depuis stdin"
assert_contient "$(appels)" "get clusterissuers -l app.kubernetes.io/managed-by=mgnetworking -o name" "et relu par le label"
assert_contient "$(appels)" "wait --for=condition=Ready clusterissuer/letsencrypt-staging --timeout=20s" "chaque issuer est attendu Ready, délai borné"
assert_contient "$sortie" "clusterissuer.cert-manager.io/letsencrypt-staging created" "ce que kubectl a créé est affiché"
sain; EXTRA=(POSE_UN_SEUL=1); lancer --yes; EXTRA=()
assert_code 1 "$CODE" "un seul ClusterIssuer relu rend 1"; assert_contient "$sortie" "letsencrypt-production est absent" "le message nomme celui qui manque"
assert_absent "$sortie" "[SUCCESS]" "aucun [SUCCESS] ne masque la relecture incomplète"
sain; EXTRA=(WAIT_CODE=1 WAIT_ERREUR='error: timed out waiting for the condition on clusterissuers/letsencrypt-staging'); lancer --yes; EXTRA=()
assert_code 1 "$CODE" "un issuer qui n'atteint pas Ready rend 1"
assert_contient "$sortie" "timed out waiting for the condition on clusterissuers/letsencrypt-staging" "le message de kubectl est affiché"
assert_contient "$sortie" "letsencrypt-staging" "et l'issuer fautif est nommé"
assert_absent "$sortie" "[SUCCESS]" "aucun [SUCCESS] ne masque l'attente déçue"

titre "Délai dépassé — « timeout » enveloppe chaque appel"
REEL_TIMEOUT="$(command -v timeout)"
faux timeout <<EOF
#!/bin/sh
case "\${TIMEOUT_SUR:-}:\$*" in
    "kubectl:7 kubectl "*) printf '%s\n' "\$*" >> "$BAC/timeout-appels"; exit 124 ;;
    *) exec $REEL_TIMEOUT "\$@" ;;
esac
EOF
: > "$BAC/timeout-appels"
sain; EXTRA=(TIMEOUT_SUR=kubectl); lancer --yes; EXTRA=()
assert_code 1 "$CODE" "un appel kubectl qui expire rend 1"; assert_contient "$sortie" "délai dépassé" "le délai est nommé pour ce qu'il est"
assert_contient "$sortie" "« kubectl get crd clusterissuers.cert-manager.io »" "et l'appel qui a expiré est nommé"
assert_egal "7 kubectl get crd clusterissuers.cert-manager.io --request-timeout=5s" "$(head -1 "$BAC/timeout-appels")" "le délai externe vaut 7 (5 + 2), et l'appel reste borné à 5 s"
rm -f "$BAC/timeout"

titre "Mutations du manifeste — la suite doit les voir, sinon elle ne prouve rien"
mkdir -p "$BAC/mut/Kubernetes/Configuration"; ln -sfn "$SCRIPTS_ROOT/lib" "$BAC/mut/lib"
MUT="$BAC/mut/Kubernetes/Configuration/configure-tls.sh"
lancer_mut() { sortie="$(env PATH="$CHEMIN" SRV_K8S_ACME_EMAIL="$MAIL" ACME_EMAIL="$MAIL" "${BASE[@]}" "${EXTRA[@]}" timeout 60 bash "$MUT" "$@" </dev/null 2>&1)" && CODE=0 || CODE=$?; }
cp "$CIBLE" "$MUT"; lancer_mut --yes
assert_code 0 "$CODE" "copie intacte : le chemin nominal rend 0"; assert_absent "$sortie" "manifeste :" "le faux kubectl ne rejette pas un manifeste sain"
for m in serveur ingress email certificat suppression; do
    case "$m" in
        serveur)     sed 's#acme-staging-v02#acme-v02#' "$CIBLE" > "$MUT" ;;
        ingress)     sed 's#ingressClassName: traefik#ingressClassName: nginx#' "$CIBLE" > "$MUT" ;;
        email)       awk '!/^    email: /' "$CIBLE" > "$MUT" ;;
        certificat)  awk '{print} /^kind: ClusterIssuer$/{print "kind: Certificate"}' "$CIBLE" > "$MUT" ;;
        suppression) sed 's# apply -f -# delete -f -#' "$CIBLE" > "$MUT" ;;
    esac
    lancer_mut --yes
    assert_code 1 "$CODE" "manifeste « $m » muté : la suite le voit et rend 1"
done

titre "Ce que le script ne fait jamais"
assert_egal "0" "$(grep -c require_root "$CIBLE" || true)" "aucun require_root"
assert_egal "0" "$(grep -vE '^[[:space:]]*#' "$CIBLE" | grep -c 'k3s.yaml' || true)" "aucune référence à k3s.yaml hors commentaire"
assert_egal "0" "$(grep -vc -- '--request-timeout=' "$BAC/kubectl-tous" || true)" "chaque appel kubectl de toute la suite porte --request-timeout"
assert_egal "0" "$(grep -vcE '^kubectl (get crd|get clusterissuers|diff|apply|wait) ' "$BAC/kubectl-tous" || true)" "aucun appel kubectl ne sort de ces cinq verbes"
assert_egal "0" "$(grep -cE -- ' delete|--prune| create|patch|replace|edit|scale' "$BAC/kubectl-tous" || true)" "aucune suppression ni écriture hors apply"
assert_egal "0" "$(grep -c 'k3s.yaml' "$BAC/kubectl-tous" || true)" "aucune lecture du kubeconfig de K3s"
assert_egal "0" "$(grep -vE '^[[:space:]]*#' "$CIBLE" | grep -cE 'curl|wget|openssl|nslookup' || true)" "aucun outil réseau : rien n'est appelé chez Let's Encrypt"
assert_absent "$(cat "$BAC/sorties")" "PRIVATE KEY" "aucune clé privée dans ce que le script a affiché"
assert_absent "$(cat "$BAC/sorties")" "kind: Secret" "aucun Secret dans ce qu'il a affiché"
assert_absent "$(cat "${LOG_DIR:-/tmp}/configure-tls.log" 2>/dev/null)" "PRIVATE KEY" "aucune clé privée dans le journal"

bilan "TASK-070 / configure-tls.sh"
