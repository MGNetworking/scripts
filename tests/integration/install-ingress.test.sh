#!/usr/bin/env bash
# tests/integration/install-ingress.test.sh — Kubernetes/Installation/install-ingress.sh.
# RIEN N'EST INSTALLÉ : faux kubectl et faux ss en tête de PATH, aux sorties, codes
# et messages du vrai. Ni cluster, ni réseau, ni écoute réelle.
_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_dir/lib/common.sh" ] && [ "$_dir" != "/" ]; do _dir="$(dirname "$_dir")"; done
source "$_dir/lib/common.sh"
source "$SCRIPTS_ROOT/tests/lib/assert.sh"

CIBLE="$SCRIPTS_ROOT/Kubernetes/Installation/install-ingress.sh"
IMAGE="rancher/mirrored-library-traefik:3.1.5"
# Les trois expressions de lecture attendues, écrites une fois : le faux kubectl
# ne rend la donnée que pour celles-là, et les assertions les retrouvent au journal.
export JP_CLASSES='jsonpath={range .items[*]}{.metadata.name}{" "}{.metadata.annotations.ingressclass\.kubernetes\.io/is-default-class}{"\n"}{end}'
export CC_DEPLOIEMENT='custom-columns=IMAGE:.spec.template.spec.containers[0].image,PRETES:.status.readyReplicas,DESIREES:.spec.replicas'
export JP_SERVICES='jsonpath={range .items[*]}{.metadata.namespace}{" "}{.metadata.name}{" "}{.spec.type}{" "}{.spec.ports[*].port}{"\n"}{end}'
if [ ! -e /.dockerenv ]; then
    saute_indisponible "install-ingress.sh" "hors conteneur : un vrai kubectl ou un vrai ss fausserait les appels"
    bilan "TASK-064 / install-ingress.sh"
fi
BAC="$(mktemp -d)"; export BAC
chmod 755 "$BAC"   # le cas sans root y lit ses faux sous l'identité nobody
trap 'rm -rf "$BAC"' EXIT
faux() { cat > "$BAC/$1"; chmod +x "$BAC/$1"; }
: > "$BAC/kubectl-tous"

# Faux kubectl : la sortie des colonnes demandées — jsonpath et custom-columns —
# telle que le vrai la rend, et ses messages d'erreur, codes compris. La donnée
# n'est rendue que pour l'expression -o attendue : sans cette garde, un script qui
# demanderait n'importe quoi serait servi pareil, et les deux modes de lecture ne
# seraient prouvés par rien.
faux kubectl <<'EOF'
#!/bin/sh
printf 'kubectl %s\n' "$*" >> "$BAC/kubectl-appels"; printf 'kubectl %s\n' "$*" >> "$BAC/kubectl-tous"
[ -z "${KUBECTL_ERREUR:-}" ] || { printf '%s\n' "$KUBECTL_ERREUR" >&2; exit "${KUBECTL_CODE:-1}"; }
o=""; precedent=""
for a in "$@"; do [ "$precedent" = "-o" ] && o="$a"; precedent="$a"; done
rendre() {   # <fichier> <expression attendue> <message NotFound>
    [ "$o" = "$2" ] || { printf 'kubectl inattendu : -o « %s »\n' "$o" >&2; exit 1; }
    [ -f "$BAC/$1" ] || { printf 'Error from server (NotFound): %s\n' "$3" >&2; exit 1; }
    cat "$BAC/$1"; }
case "$1 $2" in
    "get ingressclasses") rendre ingressclasses "$JP_CLASSES" "the server could not find the requested resource" ;;
    "get deployment") rendre deploiement "$CC_DEPLOIEMENT" 'deployments.apps "traefik" not found' ;;
    "get services") rendre services "$JP_SERVICES" "the server could not find the requested resource" ;;
    *) printf 'kubectl inattendu : %s\n' "$*" >&2; exit 1 ;;
esac
EOF

# Faux ss : la sortie du vrai. La colonne des processus n'apparaît qu'avec -p,
# que le script ne demande qu'à root : le faux obéit au même signal.
faux ss <<'EOF'
#!/bin/sh
printf 'ss %s\n' "$*" >> "$BAC/ss-appels"
[ -z "${SS_ERREUR:-}" ] || { printf '%s\n' "$SS_ERREUR" >&2; exit "${SS_CODE:-1}"; }
printf 'State Recv-Q Send-Q Local Address:Port Peer Address:PortProcess\n'
case "$*" in
    *p*) cat "$BAC/ecoute-avec" 2>/dev/null ;;
    *)   cat "$BAC/ecoute-sans" 2>/dev/null ;;
esac
EOF

sain() {   # cluster sain : Traefik prêt, aucun occupant des ports 80 et 443
    printf 'traefik true\n' > "$BAC/ingressclasses"; printf '%s 1 1\n' "$IMAGE" > "$BAC/deploiement"
    : > "$BAC/services"; : > "$BAC/ecoute-avec"; : > "$BAC/ecoute-sans"
    : > "$BAC/kubectl-appels"; : > "$BAC/ss-appels"
    chmod 666 "$BAC/kubectl-appels" "$BAC/ss-appels"; }
CHEMIN="$BAC:$PATH"
EXTRA=(); codes=""; CODE=0
lancer() { sortie="$(env PATH="$CHEMIN" "${EXTRA[@]}" timeout 60 bash "$CIBLE" </dev/null 2>&1)" && CODE=0 || CODE=$?; codes="$codes $CODE"; }
# Sans root, sous l'identité nobody : ss -p ne nommerait pas le processus.
lancer_nr() { sortie="$(env PATH="$CHEMIN" "${EXTRA[@]}" timeout 60 setpriv --reuid=65534 --regid=65534 --clear-groups bash "$CIBLE" </dev/null 2>&1)" && CODE=0 || CODE=$?; codes="$codes $CODE"; }

titre "Codes d'usage"
sortie="$(timeout 30 bash "$CIBLE" --help 2>&1)" && code=0 || code=$?
assert_code 0 "$code" "--help rend 0"
assert_contient "$sortie" "kube-system" "--help nomme le namespace où K3s pose Traefik"
assert_contient "$sortie" "2  option" "--help documente les codes de retour"
timeout 30 bash "$CIBLE" --option-inexistante >/dev/null 2>&1 && code=0 || code=$?
assert_code 2 "$code" "une option inconnue rend 2"

titre "kubectl ou ss absent"
for b in sans-kubectl sans-ss; do
    mkdir -p "$BAC/$b"
    for c in bash sh timeout id mkdir basename dirname date uname cat tee sed head rm mktemp; do
        ln -sf "$(command -v "$c")" "$BAC/$b/$c"; done; done
ln -sf "$BAC/ss" "$BAC/sans-kubectl/ss"; ln -sf "$BAC/kubectl" "$BAC/sans-ss/kubectl"
sortie="$(PATH="$BAC/sans-kubectl" timeout 60 bash "$CIBLE" </dev/null 2>&1)" && code=0 || code=$?
assert_code 1 "$code" "sans kubectl, le script rend 1"
assert_contient "$sortie" "kubectl est introuvable" "le message nomme kubectl"
assert_contient "$sortie" "install-kubectl.sh" "et renvoie vers le script qui le pose (TASK-062)"
sortie="$(PATH="$BAC/sans-ss" timeout 60 bash "$CIBLE" </dev/null 2>&1)" && code=0 || code=$?
assert_code 1 "$code" "sans ss, le script rend 1"
assert_contient "$sortie" "ss est introuvable" "le message nomme ss"
assert_contient "$sortie" "iproute2" "et le paquet qui le fournit"

titre "Cluster injoignable, kubeconfig invalide, droits insuffisants"
sain; EXTRA=(KUBECTL_ERREUR='The connection to the server 127.0.0.1:6443 was refused - did you specify the right host or port?'); lancer; EXTRA=()
assert_code 1 "$CODE" "un apiserver injoignable rend 1"
assert_contient "$sortie" "injoignable" "le message nomme l'apiserver"
assert_contient "$sortie" "install-kubectl.sh" "et renvoie vers TASK-062"
assert_absent "$sortie" "[SUCCESS]" "aucun [SUCCESS] ne masque l'échec"
assert_egal "" "$(cat "$BAC/ss-appels")" "ss n'est pas interrogé tant que le cluster ne répond pas"
sain; EXTRA=(KUBECTL_ERREUR='error: error loading config file "/root/.kube/config": yaml: line 3: mapping values are not allowed in this context'); lancer; EXTRA=()
assert_code 1 "$CODE" "un kubeconfig mal formé rend 1"
assert_contient "$sortie" "Kubeconfig invalide" "message distinct de l'apiserver injoignable"
sain; EXTRA=(KUBECTL_ERREUR='error: You must be logged in to the server (Unauthorized)'); lancer; EXTRA=()
assert_code 1 "$CODE" "un jeton refusé rend 1"
assert_contient "$sortie" "Kubeconfig invalide ou périmé" "même cause qu'un kubeconfig mal formé"
sain; EXTRA=(KUBECTL_ERREUR='Error from server (Forbidden): ingressclasses.networking.k8s.io is forbidden'); lancer; EXTRA=()
assert_code 1 "$CODE" "un refus de droits rend 1"
assert_contient "$sortie" "Droits insuffisants" "troisième message, distinct des deux autres"

titre "Ressource inconnue de l'API — le cluster répond, mais ne la connaît pas"
sain; rm -f "$BAC/ingressclasses"; lancer
assert_code 1 "$CODE" "une ressource absente de l'API rend 1"
assert_contient "$sortie" "Ressource inconnue de l'API" "elle est nommée pour ce qu'elle est"
assert_absent "$sortie" "injoignable" "et non prise pour un apiserver muet"
assert_absent "$sortie" "[SUCCESS]" "aucun [SUCCESS] ne masque l'échec"
sain; EXTRA=("KUBECTL_ERREUR=error: the server doesn't have a resource type \"ingressclasses\""); lancer; EXTRA=()
assert_contient "$sortie" "Ressource inconnue de l'API" "la seconde forme du même aveu est traitée pareil"

titre "IngressClass traefik"
sain; : > "$BAC/ingressclasses"; lancer
assert_code 1 "$CODE" "aucune IngressClass rend 1"
assert_contient "$sortie" "IngressClass traefik absente" "le message nomme ce qui manque"
assert_contient "$sortie" "Rien n'a été installé" "et dit que rien n'a été installé"
assert_absent "$sortie" "[SUCCESS]" "aucun [SUCCESS] ne masque l'absence"
sain; printf 'nginx false\n' > "$BAC/ingressclasses"; lancer
assert_code 1 "$CODE" "une IngressClass nginx seule rend 1, sans rien installer"
assert_contient "$sortie" "IngressClass traefik absente" "le message nomme la classe absente"
sain; printf 'traefik false\nnginx true\n' > "$BAC/ingressclasses"; lancer
assert_code 0 "$CODE" "une autre classe par défaut ne change pas le code"
assert_contient "$sortie" "IngressClass par défaut : nginx" "la classe par défaut du cluster est affichée"
assert_contient "$sortie" "[WARN] Autre(s) IngressClass présente(s) : nginx" "et l'autre IngressClass est signalée, nommée"
assert_contient "$sortie" "[SUCCESS]" "Traefik reste déclaré prêt"
sain; printf 'traefik true\nnginx true\n' > "$BAC/ingressclasses"; lancer
assert_code 0 "$CODE" "deux classes marquées par défaut ne changent pas le code"
assert_contient "$sortie" "IngressClass par défaut : traefik nginx" "toutes les classes marquées sont listées, non la dernière seule"

titre "Déploiement traefik"
sain; rm -f "$BAC/deploiement"; lancer
assert_code 1 "$CODE" "un déploiement absent rend 1"
assert_contient "$sortie" "Déploiement traefik absent du namespace kube-system" "le message le nomme avec son namespace"
assert_absent "$sortie" "[SUCCESS]" "aucun [SUCCESS] ne masque l'absence"
sain; printf '%s <none> 1\n' "$IMAGE" > "$BAC/deploiement"; lancer
assert_code 1 "$CODE" "sans réplique prête, le script rend 1"
assert_contient "$sortie" "non disponible dans kube-system : 0/1" "le message donne les répliques prêtes sur désirées"
assert_contient "$sortie" "Rien n'a été modifié" "et dit que rien n'a été modifié"
sain; printf '%s 1 3\n' "$IMAGE" > "$BAC/deploiement"; lancer
assert_code 1 "$CODE" "deux répliques prêtes sur trois rendent 1"

titre "Traefik prêt"
sain; lancer
assert_code 0 "$CODE" "un cluster sain rend 0"
assert_contient "$sortie" "IngressClass traefik : présente" "l'IngressClass est constatée"
assert_contient "$sortie" "IngressClass par défaut : traefik" "la classe par défaut est affichée"
assert_contient "$sortie" "Image     $IMAGE" "la version de l'image Traefik est affichée"
assert_contient "$(cat "$BAC/kubectl-appels")" "get services -A" "les Services sont relus"
# Les trois lectures sont prouvées par l'expression exacte qu'elles demandent :
# le faux ne rend la donnée que pour celle-là.
assert_contient "$(cat "$BAC/kubectl-appels")" "-o $JP_CLASSES" "l'IngressClass est lue par son jsonpath, clé d'annotation échappée comprise"
assert_contient "$(cat "$BAC/kubectl-appels")" "-o $CC_DEPLOIEMENT" "le déploiement est lu par ses colonnes nommées : image, .status.readyReplicas, .spec.replicas"
assert_contient "$(cat "$BAC/kubectl-appels")" "-o $JP_SERVICES" "les Services sont lus par leur jsonpath, .spec.ports[*].port compris"
assert_contient "$sortie" "Aucune écoute visible par ss" "et le script dit ce que ss ne voit pas"
assert_contient "$sortie" "ce silence ne prouve pas que les ports sont libres" "sans conclure d'un silence que 80 et 443 sont libres (servicelb)"
assert_contient "$sortie" "[SUCCESS]" "et le verdict est déclaré"

titre "Conflits sur les ports 80 et 443"
sain; printf 'default autre LoadBalancer 80 443\n' > "$BAC/services"; lancer
assert_code 0 "$CODE" "un Service LoadBalancer étranger ne change pas le code"
assert_contient "$sortie" "[WARN] Service LoadBalancer default/autre : port(s) 80 443" "le [WARN] nomme le port et l'occupant"
sain; printf 'kube-system traefik LoadBalancer 80 443\n' > "$BAC/services"; lancer
assert_code 0 "$CODE" "le Service de Traefik lui-même ne change pas le code"
assert_contient "$sortie" "Service kube-system/traefik sur les ports 80 443 : c'est Traefik lui-même" "il est reconnu comme l'occupant attendu"
assert_absent "$sortie" "déjà publiés par Traefik" "et n'est pas signalé comme conflit"
sain; printf 'default autre LoadBalancer 8080\n' > "$BAC/services"; lancer
assert_absent "$sortie" "[WARN]" "un Service LoadBalancer hors 80 et 443 n'est pas un conflit"
sain; printf 'LISTEN 0 128 0.0.0.0:80 0.0.0.0:* users:(("nginx",pid=1234,fd=6))\n' > "$BAC/ecoute-avec"; lancer
assert_code 0 "$CODE" "une écoute sur 80 ne change pas le code"
assert_contient "$sortie" "[WARN] Port 80 déjà en écoute sur la machine : nginx." "le [WARN] nomme le port et l'occupant"
assert_contient "$(cat "$BAC/ss-appels")" "ss -ltnp" "root demande les processus par ss -p"
sain; printf 'LISTEN 0 128 0.0.0.0:443 0.0.0.0:*\n' > "$BAC/ecoute-sans"; lancer_nr
assert_code 0 "$CODE" "une écoute sur 443, lue sans root, ne change pas le code"
assert_contient "$sortie" "[WARN] Port 443 déjà en écoute sur la machine : processus non nommé" "sans root, le port est nommé seul"
# « sain » a vidé le journal : il ne porte que l'appel de ce cas sans root.
assert_egal "1" "$(grep -cx 'ss -ltn' "$BAC/ss-appels" || true)" "et ss est appelé sans -p : la ligne exacte"
assert_egal "0" "$(grep -c -- '-ltnp' "$BAC/ss-appels" || true)" "jamais -ltnp, dont -ltn n'est qu'un préfixe"

titre "Écoute illisible"
sain; EXTRA=(SS_ERREUR='ss: cannot open netlink socket: Permission denied'); lancer; EXTRA=()
assert_code 1 "$CODE" "un « ss » en échec rend 1"
assert_contient "$sortie" "l'écoute des ports 80 et 443 n'a pas pu être vérifiée" "le message dit ce qui n'a pas été vérifié"
assert_absent "$sortie" "[SUCCESS]" "aucun [SUCCESS] ne masque le relevé manquant"

titre "Délai dépassé — « timeout » enveloppe chaque appel"
REEL_TIMEOUT="$(command -v timeout)"
# Faux « timeout » : 124 sans attente réelle, sur la seule cible nommée par
# TIMEOUT_SUR — sinon le premier appel kubectl expirerait aussi, et le cas ss ne
# serait jamais atteint. Le motif est ancré sur le délai, sans quoi le
# « timeout 60 bash » du harnais — dont le chemin « install-ingress.sh » contient
# « ss » — tomberait dans la même branche.
faux timeout <<EOF
#!/bin/sh
case "\${TIMEOUT_SUR:-}:\$*" in
    "kubectl:7 kubectl "*) printf '%s\n' "\$*" >> "$BAC/timeout-appels"; exit 124 ;;
    "ss:7 ss "*)           printf '%s\n' "\$*" >> "$BAC/timeout-appels"; exit 124 ;;
    *) exec $REEL_TIMEOUT "\$@" ;;
esac
EOF
: > "$BAC/timeout-appels"
sain; EXTRA=(TIMEOUT_SUR=kubectl); lancer; EXTRA=()
assert_code 1 "$CODE" "un appel kubectl qui expire rend 1"
assert_contient "$sortie" "délai dépassé" "le délai est nommé pour ce qu'il est"
assert_contient "$sortie" "« kubectl get ingressclasses » a été interrompu" "et l'appel qui a expiré est nommé"
assert_absent "$sortie" "[SUCCESS]" "aucun [SUCCESS] ne masque l'expiration"
assert_egal "7 kubectl get ingressclasses -o $JP_CLASSES --request-timeout=5s" "$(head -1 "$BAC/timeout-appels")" "le délai externe vaut 7 (5 + 2), et l'appel reste borné à 5 s"
: > "$BAC/timeout-appels"
sain; EXTRA=(TIMEOUT_SUR=ss); lancer; EXTRA=()
assert_code 1 "$CODE" "un relevé ss qui expire rend 1"
assert_contient "$sortie" "délai dépassé" "le délai est nommé là aussi"
assert_contient "$sortie" "« ss -ltn" "et c'est bien « ss » qui a expiré, non kubectl"
assert_absent "$sortie" "[SUCCESS]" "aucun [SUCCESS] ne masque l'expiration"
assert_egal "7 ss -ltnp" "$(head -1 "$BAC/timeout-appels")" "le délai externe vaut 7 (5 + 2) pour ss"
rm -f "$BAC/timeout"

titre "Ce que le script ne fait jamais"
assert_egal "0" "$(grep -c require_root "$CIBLE" || true)" "aucun require_root : lecture seule"
sans_delai="$(grep -vc -- '--request-timeout=5s' "$BAC/kubectl-tous" || true)"
assert_egal "0" "$sans_delai" "chaque appel kubectl de toute la suite porte --request-timeout"
hors_forme="$(grep -vcE '^kubectl (get ingressclasses|get deployment|get services) ' "$BAC/kubectl-tous" || true)"
assert_egal "0" "$hors_forme" "aucun appel kubectl ne sort de ces trois lectures"
assert_egal "0" "$(grep -cE 'apply|create|patch|delete|edit|annotate|label|scale' "$BAC/kubectl-tous" || true)" "aucune écriture dans le cluster"
assert_egal "0" "$(grep -c 'k3s.yaml' "$BAC/kubectl-tous" || true)" "aucune lecture du kubeconfig de K3s"
case "$codes" in *" 2"*) cas2="oui" ;; *) cas2="non" ;; esac
assert_egal "non" "$cas2" "aucun chemin éprouvé ne rend 2 : le 2 reste réservé à l'usage"
# Sonde du faux lui-même, après la relecture du journal : elle l'écrirait sinon.
PATH="$CHEMIN" kubectl get services -o 'jsonpath={.items}' >/dev/null 2>&1 && code=0 || code=$?
assert_code 1 "$code" "le faux kubectl refuse une expression -o qu'il n'attend pas : jsonpath et custom-columns sont donc bien prouvés"

bilan "TASK-064 / install-ingress.sh"
