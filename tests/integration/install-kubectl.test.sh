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
chmod 755 "$BAC"   # les cas sans root font traverser le bac par « nobody »
present() { test -e "$1" && echo présente || echo absente; }
REEL_TIMEOUT="$(command -v timeout)"
# Le faux kubectl tient les formats et les codes du vrai : le client répond sans serveur.
cat > "$BAC/kubectl" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" | tee -a "$BAC/appels" >> "$BAC/tous"
case "$*" in *--client*) exec cat "$BAC/version-client" ;; esac
case "${KUBECTL_MODE:-ok}" in
    injoignable) case "$*" in *version*) cat "$BAC/version-client" ;; esac
                 echo "The connection to the server 127.0.0.1:6443 was refused - did you specify the right host or port?" >&2; exit 1 ;;
    interdit)    echo 'Error from server (Forbidden): nodes is forbidden: User "u" cannot list resource "nodes" in API group "" at the cluster scope' >&2; exit 1 ;;
    message)     cat "$BAC/erreur-kubectl" >&2; exit 1 ;;
esac
case "$*" in
    *"get nodes"*) exec cat "$BAC/nodes" ;;
    *version*)     exec cat "$BAC/version-serveur" ;;
esac
exit 1
EOF
chmod +x "$BAC/kubectl"; : > "$BAC/tous"; : > "$BAC/appels"; chmod 666 "$BAC/tous" "$BAC/appels"
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
# Un compte non root, pour ce que root ne peut pas éprouver : un fichier en 0000.
NON_ROOT=""
if command -v setpriv >/dev/null 2>&1 && setpriv --reuid=nobody --regid=nogroup --clear-groups true 2>/dev/null; then NON_ROOT="oui"; fi
mkdir -p "$BAC/logs"; chmod 777 "$BAC/logs"
lancer_nobody() {
    setpriv --reuid=nobody --regid=nogroup --clear-groups \
        env HOME="$FOYER" KUBECONFIG="$KC" PATH="$CHEMIN" LOG_DIR="$BAC/logs" \
        bash "$CIBLE" > "$BAC/nobody-sortie" 2>&1
    CODE=$?; sortie="$(cat "$BAC/nobody-sortie")"; codes="$codes $CODE"
}

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
assert_contient "$sortie" "install -d -m 0700 ~/.kube" "le message affiche la copie à faire, création du dossier comprise"
# Le $(id -u) attendu est du texte littéral : il appartient à la commande recopiée.
# shellcheck disable=SC2016
assert_contient "$sortie" '-o "$(id -u)" -g "$(id -g)"' "le fichier copié appartient au compte, pas à root"
assert_contient "$sortie" "-m 0600 /etc/rancher/k3s/k3s.yaml ~/.kube/config" "et il est posé en 0600 depuis k3s.yaml"
assert_contient "$sortie" "127.0.0.1" "k3s.yaml vise le nœud : l'adresse est signalée comme locale"
assert_absent  "$sortie" "[SUCCESS]" "et rien n'est déclaré vérifié"
assert_egal "absente" "$(present "$BAC/home2")" "rien n'est créé dans le HOME : le script n'installe rien"

titre "KUBECONFIG qui ne mène à rien"
KC="$BAC/absent.yaml"; lancer
assert_code 1 "$CODE" "un KUBECONFIG absent rend 1"
assert_contient "$sortie" "chemin absent : $BAC/absent.yaml" "la cause est nommée, le chemin cité"
# Plusieurs chemins : la valeur entière est citée, jamais le seul dernier.
KC="$BAC/absent1.yaml:$BAC/absent2.yaml"; lancer
assert_code 1 "$CODE" "deux chemins absents rendent 1"
assert_contient "$sortie" "chemin absent : $KC" "les deux chemins sont cités, pas le dernier"
KC="$BAC/absent1.yaml:"; lancer
assert_code 1 "$CODE" "une entrée vide dans KUBECONFIG ne change pas la cause"
assert_contient "$sortie" "chemin absent : $KC" "l'entrée vide est citée telle quelle, sans chemin fantôme"
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

titre "Kubeconfig invalide — trois formes, une seule cause"
cluster_sain
for forme in 'error: You must be logged in to the server (Unauthorized)' \
             'Unable to connect to the server: tls: failed to verify certificate: x509: certificate signed by unknown authority' \
             "error: error loading config file \"$KUBECONF\": yaml: line 3: could not find expected ':'"; do
    printf '%s\n' "$forme" > "$BAC/erreur-kubectl"
    export KUBECTL_MODE=message; lancer; unset KUBECTL_MODE
    assert_code 1 "$CODE" "un kubeconfig invalide rend 1 — ${forme:0:22}"
    assert_contient "$sortie" "Kubeconfig invalide ou périmé" "la cause est nommée — ${forme:0:22}"
    assert_absent  "$sortie" "injoignable" "et non prise pour un apiserver injoignable"
    assert_absent  "$sortie" "n'a pas répondu" "ni pour un apiserver muet"
    assert_absent  "$sortie" "[SUCCESS]" "sans [SUCCESS] : rien n'est vérifié"
done

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
# Un suffixe de distribution ou de préversion se retire avant le calcul : vX.Y.Z reste.
cluster_sain; server_version 1.31 v1.31.0-rc.1; lancer
assert_code 0 "$CODE" "un suffixe « -rc.1 » ne fait pas échouer le script"
assert_contient "$sortie" "serveur v1.31.0-rc.1" "la version du serveur est affichée telle quelle"
assert_absent  "$sortie" "non vérifié" "et l'écart est calculé, non déclaré invérifiable"
cluster_sain; server_version 1.31 1.31; lancer
assert_code 0 "$CODE" "une forme hors « vX.Y.Z » ne change pas le code"
assert_contient "$sortie" "non vérifié" "elle est signalée en [WARN]"
assert_absent  "$sortie" "plus d'une version mineure" "sans écart inventé à partir d'une forme douteuse"
assert_contient "$sortie" "[SUCCESS]" "et le cluster reste déclaré joignable"

titre "Architecture hors amd64 et arm64"
cluster_sain
printf '#!/bin/sh\necho riscv64\n' > "$BAC/uname"; chmod +x "$BAC/uname"
lancer
rm -f "$BAC/uname"
assert_code 0 "$CODE" "une architecture inconnue ne change pas le code"
assert_contient "$sortie" "riscv64" "l'architecture relevée est affichée telle quelle"
assert_contient "$sortie" "[WARN]" "et signalée en [WARN]"

titre "Kubeconfig illisible pour un compte non root"
if [ -z "$NON_ROOT" ]; then
    saute_indisponible "kubeconfig en 0000 lu par un compte non root" "setpriv ou le compte nobody manque, et root lit tout"
else
    printf '%s\n' "JETON-A-NE-PAS-AFFICHER" > "$BAC/secret.yaml"; chmod 000 "$BAC/secret.yaml"
    KC="$BAC/secret.yaml"; lancer_nobody
    assert_code 1 "$CODE" "un kubeconfig en 0000 rend 1 pour un compte non root"
    assert_contient "$sortie" "chemin illisible" "la cause est l'illisibilité, pas l'absence"
    assert_absent  "$sortie" "[SUCCESS]" "sans [SUCCESS] : rien n'est vérifié"
    chmod 644 "$BAC/secret.yaml"; KC="$KUBECONF"
fi

titre "Sans root — un cas sain lu par un compte non root"
if [ -z "$NON_ROOT" ]; then
    saute_indisponible "cas sain exécuté sans root" "setpriv ou le compte nobody manque"
else
    cluster_sain; FOYER="$BAC/home"; KC="$KUBECONF"; lancer_nobody
    assert_code 0 "$CODE" "sans root, un cas sain rend 0"
    assert_contient "$sortie" "[SUCCESS]" "et le dit en [SUCCESS]"
    assert_contient "$sortie" "nœud-1" "l'accès est prouvé hors de tout privilège"
    assert_absent  "$sortie" "exécuté en root" "aucun require_root : le message du socle ne paraît pas"
fi

titre "Lecture seule, appels bornés, sans root"
assert_egal "0" "$(grep -vcE '^(version|get nodes)' "$BAC/tous" || true)" "aucun appel ne sort des trois formes attendues"
for verbe in delete apply patch exec cordon drain scale rollout edit create; do
    assert_absent "$(cat "$BAC/tous")" "$verbe" "aucun appel « $verbe » : rien n'est modifié"
done
assert_absent "$(cat "$BAC/tous")" "config" "aucun « kubectl config » sur l'ensemble des exécutions : le kubeconfig n'est jamais ouvert"
assert_egal "absente absente" "$(present "$BAC/k3s-appele") $(present "$BAC/systemctl-appele")" "ni k3s ni systemctl ne sont appelés"
cas2="non"; case "$codes" in *" 2"*) cas2="oui" ;; esac
assert_egal "non" "$cas2" "aucun chemin éprouvé ne rend 2 : le 2 reste réservé à l'usage"

bilan "TASK-062 / install-kubectl.sh"
