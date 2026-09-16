#!/usr/bin/env bash
# tests/integration/install-kubectl.test.sh — Kubernetes/Installation/install-kubectl.sh.
# Aucun cluster réel : un faux kubectl rend les sorties, messages et codes du vrai.
_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_dir/lib/common.sh" ] && [ "$_dir" != "/" ]; do _dir="$(dirname "$_dir")"; done
source "$_dir/lib/common.sh"
source "$SCRIPTS_ROOT/tests/lib/assert.sh"

CIBLE="$SCRIPTS_ROOT/Kubernetes/Installation/install-kubectl.sh"
if [ ! -e /.dockerenv ]; then
    saute_indisponible "install-kubectl.sh" "hors conteneur : un vrai kubectl ou un vrai cluster fausserait la vérification"
    bilan "TASK-062 / install-kubectl.sh"
fi
BAC="$(mktemp -d)"; export BAC
trap 'rm -rf "$BAC"' EXIT
present() { test -e "$1" && echo présente || echo absente; }
REEL_TIMEOUT="$(command -v timeout)"
# Le faux kubectl tient les formats et les codes du vrai : le client répond sans serveur.
cat > "$BAC/kubectl" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" | tee -a "$BAC/appels" >> "$BAC/tous"
case "$*" in *--client*) exec cat "$BAC/version-client" ;; esac
case "${KUBECTL_MODE:-ok}" in
    injoignable) echo "The connection to the server 127.0.0.1:6443 was refused - did you specify the right host or port?" >&2; exit 1 ;;
    interdit)    echo 'Error from server (Forbidden): nodes is forbidden: User "u" cannot list resource "nodes"' >&2; exit 1 ;;
esac
case "$*" in
    *"get nodes"*) exec cat "$BAC/nodes" ;;
    *version*)     exec cat "$BAC/version-serveur" ;;
esac
exit 1
EOF
chmod +x "$BAC/kubectl"; : > "$BAC/tous"
# Ni K3s ni systemd n'ont leur place ici : leurs faux laissent une trace.
for outil in k3s systemctl; do printf '#!/bin/sh\ntouch "%s/%s-appele"\n' "$BAC" "$outil" > "$BAC/$outil"; chmod +x "$BAC/$outil"; done
# Le JSON de kubectl, aux vraies formes : clientVersion seule pour --client, les deux pour le serveur.
bloc() {   # <majeur.mineur> <gitVersion>
    printf '    "major": "%s",\n    "minor": "%s",\n    "gitVersion": "%s",\n    "platform": "linux/amd64"\n' \
        "${1%%.*}" "${1#*.}" "$2"
}
client_version() { { echo '{'; echo '  "clientVersion": {'; bloc "$@"; echo '  },'; echo '  "kustomizeVersion": "v0.5.4"'; echo '}'; } > "$BAC/version-client"; }
server_version() { { echo '{'; echo '  "clientVersion": {'; bloc 1.31 v1.31.4; echo '  },'; echo '  "kustomizeVersion": "v0.5.4",'; echo '  "serverVersion": {'; bloc "$@"; echo '  }'; echo '}'; } > "$BAC/version-serveur"; }
cluster_sain() {
    client_version 1.31 v1.31.4; server_version 1.30 v1.30.5
    printf '%s\n' "nœud-1   Ready   control-plane   10d   v1.30.5+k3s1" > "$BAC/nodes"; : > "$BAC/appels"
}

# Le kubeconfig du bac est lisible et porte un marqueur qui ne doit jamais ressortir.
KUBECONF="$BAC/home/.kube/config"; KC="$KUBECONF"; FOYER="$BAC/home"
CHEMIN="$BAC:$PATH"
mkdir -p "$BAC/home/.kube"
printf '%s\n' "JETON-A-NE-PAS-AFFICHER" > "$KUBECONF"
CODE=0; codes=""; sortie=""
lancer() { sortie="$(HOME="$FOYER" KUBECONFIG="$KC" PATH="$CHEMIN" bash "$CIBLE" 2>&1)" && CODE=0 || CODE=$?; codes="$codes $CODE"; }

titre "Codes d'usage"
sortie="$(bash "$CIBLE" --help 2>&1)" && code=0 || code=$?
assert_code 0 "$code" "--help rend 0"
assert_contient "$sortie" "Codes de retour" "--help documente les codes de retour"
bash "$CIBLE" --option-inexistante >/dev/null 2>&1 && code=0 || code=$?
assert_code 2 "$code" "une option inconnue rend 2"

titre "kubectl introuvable — le message renvoie vers K3s"
sortie="$(PATH="/usr/bin:/bin" bash "$CIBLE" 2>&1)" && CODE=0 || CODE=$?; codes="$codes $CODE"
assert_code 1 "$CODE" "sans kubectl, le script rend 1"
assert_contient "$sortie" "kubectl est introuvable" "l'absence est signalée en [ERROR]"
assert_contient "$sortie" "Linux/K3s/install-k3s.sh" "et le message dit où K3s le pose"
assert_absent  "$sortie" "command not found" "aucun message brut du shell ne filtre"

titre "timeout introuvable"
mkdir -p "$BAC/sans-timeout"
for c in bash sh id mkdir basename dirname date uname; do ln -s "$(command -v "$c")" "$BAC/sans-timeout/$c"; done
cp "$BAC/kubectl" "$BAC/sans-timeout/kubectl"
CHEMIN="$BAC/sans-timeout"; lancer; CHEMIN="$BAC:$PATH"
assert_code 1 "$CODE" "sans timeout, le script rend 1"
assert_contient "$sortie" "Commande(s) requise(s) introuvable(s) : timeout" "c'est le message de require_cmd, pas un autre"

titre "Cluster joignable — la garde de contraste"
cluster_sain
lancer
assert_code 0 "$CODE" "kubectl présent et cluster joignable : le script rend 0"
assert_contient "$sortie" "[SUCCESS]" "et le dit en [SUCCESS]"
assert_contient "$sortie" "$(uname -m)" "l'architecture de la machine est affichée"
assert_contient "$sortie" "client v1.31.4, serveur v1.30.5" "les versions client et serveur sont affichées"
assert_contient "$sortie" "$KUBECONF" "le kubeconfig résolu est nommé"
assert_contient "$sortie" "nœud-1" "l'accès est prouvé par la liste des nœuds"
assert_absent  "$sortie" "JETON-A-NE-PAS-AFFICHER" "aucun contenu de kubeconfig ne ressort"
assert_egal "version --client -o json --request-timeout=5s" "$(head -1 "$BAC/appels")" "la version du client ouvre la vérification, sans le serveur"
assert_contient "$(cat "$BAC/appels")" "get nodes --no-headers --request-timeout=5s" "l'accès est éprouvé par « get nodes », borné"
assert_contient "$(cat "$BAC/appels")" "version -o json --request-timeout=5s" "puis la version du serveur"
assert_egal "0" "$(grep -vc -- '--request-timeout=5s' "$BAC/appels" || true)" "chaque appel kubectl porte --request-timeout"
assert_absent "$(cat "$BAC/appels")" "config" "aucun « kubectl config » : le kubeconfig n'est jamais ouvert"

titre "KUBECONFIG vide et ~/.kube/config absent — la copie à faire"
KC=""; FOYER="$BAC/home2"; lancer; KC="$KUBECONF"; FOYER="$BAC/home"
assert_code 1 "$CODE" "sans kubeconfig, le script rend 1"
assert_contient "$sortie" "0600 /etc/rancher/k3s/k3s.yaml ~/.kube/config" "le message affiche la copie à faire, en 0600"
assert_absent  "$sortie" "[SUCCESS]" "et rien n'est déclaré vérifié"
assert_egal "absente" "$(present "$BAC/home2")" "rien n'est créé dans le HOME : le script n'installe rien"

titre "KUBECONFIG qui ne mène à rien"
KC="$BAC/absent.yaml"; lancer
assert_code 1 "$CODE" "un KUBECONFIG absent rend 1"
assert_contient "$sortie" "chemin absent : $BAC/absent.yaml" "la cause est nommée, le chemin cité"
mkdir -p "$BAC/dossier"; KC="$BAC/dossier"; lancer
assert_code 1 "$CODE" "un KUBECONFIG illisible rend 1"
assert_contient "$sortie" "chemin illisible" "la cause est distinguée de l'absence"
assert_absent  "$sortie" "chemin absent" "un dossier n'est pas un chemin absent"
assert_absent  "$sortie" "[SUCCESS]" "sans [SUCCESS] : rien n'est vérifié"
KC="$KUBECONF"

titre "Apiserver injoignable"
cluster_sain; export KUBECTL_MODE=injoignable; lancer; unset KUBECTL_MODE
assert_code 1 "$CODE" "un apiserver injoignable rend 1"
assert_contient "$sortie" "apiserver est injoignable" "la cause est nommée pour ce qu'elle est"
assert_contient "$sortie" "was refused" "le message de kubectl est montré tel quel"
assert_absent  "$sortie" "[SUCCESS]" "et rien n'est déclaré vérifié (A78)"
assert_egal "2" "$(wc -l < "$BAC/appels")" "la version du serveur n'est pas demandée après l'échec"

titre "Droits insuffisants — un refus n'est pas une panne du cluster"
cluster_sain; export KUBECTL_MODE=interdit; lancer; unset KUBECTL_MODE
assert_code 1 "$CODE" "un « get nodes » refusé rend 1"
assert_contient "$sortie" "Droits insuffisants" "le refus est nommé pour ce qu'il est"
assert_absent  "$sortie" "injoignable" "et n'est pas pris pour un apiserver muet"
assert_absent  "$sortie" "[SUCCESS]" "sans [SUCCESS]"

titre "Délai dépassé — « timeout » enveloppe l'appel"
cluster_sain
# Un faux « timeout » : « get nodes » rend 124 comme le vrai, sans les 7 s d'attente.
cat > "$BAC/timeout" <<EOF
#!/bin/sh
case "\$*" in
    *" get nodes "*) printf '%s\n' "\$*" >> "$BAC/timeout-appels"; exit 124 ;;
    *) exec $REEL_TIMEOUT "\$@" ;;
esac
EOF
chmod +x "$BAC/timeout"; : > "$BAC/timeout-appels"
lancer
rm -f "$BAC/timeout"
assert_code 1 "$CODE" "un appel qui expire rend 1"
assert_contient "$sortie" "délai dépassé" "le délai est nommé pour ce qu'il est"
assert_absent  "$sortie" "injoignable" "et non pris pour un apiserver injoignable"
assert_contient "$(cat "$BAC/timeout-appels")" "7 kubectl get nodes --no-headers --request-timeout=5s" "« timeout » reçoit le délai majoré de 2 s"

titre "Écart de versions"
cluster_sain; server_version 1.28 v1.28.15; lancer
assert_code 0 "$CODE" "plus d'une version mineure d'écart ne change pas le code"
assert_contient "$sortie" "plus d'une version mineure" "l'écart est signalé en [WARN]"
assert_contient "$sortie" "[SUCCESS]" "le cluster reste déclaré joignable"
cluster_sain; lancer
assert_absent "$sortie" "plus d'une version mineure" "à une version mineure près, aucun avertissement"

titre "Architecture hors amd64 et arm64"
cluster_sain
printf '#!/bin/sh\necho riscv64\n' > "$BAC/uname"; chmod +x "$BAC/uname"
lancer
rm -f "$BAC/uname"
assert_code 0 "$CODE" "une architecture inconnue ne change pas le code"
assert_contient "$sortie" "riscv64" "l'architecture relevée est affichée telle quelle"
assert_contient "$sortie" "[WARN]" "et signalée en [WARN]"

titre "Lecture seule, appels bornés, sans root"
assert_egal "0" "$(grep -vcE '^(version|get nodes)' "$BAC/tous" || true)" "aucun appel ne sort des trois formes attendues"
for verbe in delete apply patch exec cordon drain scale rollout edit create; do
    assert_absent "$(cat "$BAC/tous")" "$verbe" "aucun appel « $verbe » : rien n'est modifié"
done
assert_absent "$(cat "$CIBLE")" "require_root" "aucun require_root : le script s'exécute sans root"
assert_absent "$(cat "$CIBLE")" "config view" "aucun « kubectl config view » : le kubeconfig n'est jamais ouvert"
assert_egal "absente absente" "$(present "$BAC/k3s-appele") $(present "$BAC/systemctl-appele")" "ni k3s ni systemctl ne sont appelés"
cas2="non"; case "$codes" in *" 2"*) cas2="oui" ;; esac
assert_egal "non" "$cas2" "aucun chemin éprouvé ne rend 2 : le 2 reste réservé à l'usage"

bilan "TASK-062 / install-kubectl.sh"
