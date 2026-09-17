#!/usr/bin/env bash
# tests/integration/configure-namespaces.test.sh — Kubernetes/Configuration/configure-namespaces.sh.
# AUCUN CLUSTER RÉEL : un faux kubectl en tête de PATH, aux codes du vrai. Il lit
# le manifeste reçu sur stdin et refuse tout kind autre que Namespace.
_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_dir/lib/common.sh" ] && [ "$_dir" != "/" ]; do _dir="$(dirname "$_dir")"; done
source "$_dir/lib/common.sh"
source "$SCRIPTS_ROOT/tests/lib/assert.sh"

CIBLE="$SCRIPTS_ROOT/Kubernetes/Configuration/configure-namespaces.sh"
# Garde avant tout trap et toute écriture : hors conteneur, un vrai kubectl ou un
# vrai cluster fausserait les appels.
if [ ! -e /.dockerenv ]; then
    saute_indisponible "configure-namespaces.sh" "hors conteneur : un vrai kubectl ou un vrai cluster fausserait les appels"
    bilan "TASK-067 / configure-namespaces.sh"
fi
BAC="$(mktemp -d)"; export BAC
trap 'rm -rf "$BAC"' EXIT
faux() { cat > "$BAC/$1"; chmod +x "$BAC/$1"; }
: > "$BAC/kubectl-tous"; : > "$BAC/kubectl-appels"; : > "$BAC/sorties"
faux kubectl <<'SH'
#!/bin/sh
printf 'kubectl %s\n' "$*" >> "$BAC/kubectl-appels"
printf 'kubectl %s\n' "$*" >> "${KUBECTL_JOURNAL:-$BAC/kubectl-tous}"
case " $* " in *" create "*|*" delete "*|*" patch "*|*" replace "*|*" edit "*|*" prune "*)
    printf 'verbe proscrit : %s\n' "$*" >&2; exit 3 ;; esac
[ -z "${KUBECTL_ERREUR:-}" ] || { printf '%s\n' "$KUBECTL_ERREUR" >&2; exit "${KUBECTL_CODE:-1}"; }
non() { printf 'manifeste : %s\n' "$1" >&2; exit 2; }
case "$1 $2" in
    "get namespaces")
        [ "${3:-} ${4:-}" = "-o name" ] || non 'get namespaces sans -o name'
        for n in ${EXISTANTS:-}; do printf 'namespace/%s\n' "$n"; done
        # Ce que le cluster garde : un apply réussi laisse une trace, que la
        # lecture suivante rend comme un existant. C'est ce qui rend deux
        # exécutions enchaînées comparables.
        for f in "$BAC"/cree-*; do [ -e "$f" ] || continue; printf 'namespace/%s\n' "${f##*/cree-}"; done ;;
    "apply -f")
        m="$BAC/recu"; cat > "$m"
        grep -qxE 'apiVersion: v1' "$m" || non 'apiVersion v1 attendue'
        grep -qxE 'kind: Namespace' "$m" || non 'kind Namespace attendu'
        n="$(sed -n 's/^  name: \(.*\)$/\1/p' "$m")"
        [ -n "$n" ] || non 'metadata.name absent'
        case " ${REFUSES:-} " in *" $n "*) printf 'Error from server (Forbidden): namespaces "%s" is forbidden\n' "$n" >&2; exit 1 ;; esac
        : > "$BAC/cree-$n"
        printf 'namespace/%s created\n' "$n" ;;
    *) printf 'kubectl inattendu : %s\n' "$*" >&2; exit 1 ;;
esac
SH
CHEMIN="$BAC:$PATH"
BASE=(DELAI_TEST=5 LOG_DIR="$BAC/logs"); EXTRA=(); LISTE="web,data,monitoring"; CODE=0
lancer() { sortie="$(env PATH="$CHEMIN" SRV_K8S_NAMESPACES="$LISTE" "${BASE[@]}" "${EXTRA[@]}" timeout 60 bash "$CIBLE" "$@" </dev/null 2>&1)" && CODE=0 || CODE=$?
           printf '%s\n' "$sortie" >> "$BAC/sorties"; }
sain() { : > "$BAC/kubectl-appels"; rm -f "$BAC"/cree-*; }
appels() { cat "$BAC/kubectl-appels"; }

titre "Codes d'usage"
sortie="$(timeout 30 bash "$CIBLE" --help 2>&1)" && code=0 || code=$?
assert_code 0 "$code" "--help rend 0 sans cluster"
assert_contient "$sortie" "SRV_K8S_NAMESPACES" "--help nomme la variable de liste"
assert_contient "$sortie" "2  option" "--help documente les codes de retour"
timeout 30 bash "$CIBLE" --option-inexistante >/dev/null 2>&1 && code=0 || code=$?
assert_code 2 "$code" "une option inconnue rend 2"
titre "Liste absente ou mal formée — refusée en 2, avant tout appel kubectl"
sain
for m in "" ",web" "web," "web,,data" "web data" "Web" "-web" "web-" "a.b" "web,web" "default" "kube-system" "kube-x" $'web\nkube-x' $'web\n'; do
    LISTE="$m"; lancer --yes
    assert_code 2 "$CODE" "la liste « $m » est refusée en 2"
done
LISTE=$'web\nkube-x'; lancer --yes
assert_contient "$sortie" "SRV_K8S_NAMESPACES" "un retour à la ligne est refusé en nommant la variable"
LISTE="kube-system"; lancer --yes
assert_contient "$sortie" "réservé" "un namespace système est refusé pour ce motif"
LISTE="$(printf 'a%.0s' {1..64})"; lancer --yes
assert_code 2 "$CODE" "un nom de 64 caractères est refusé en 2 (63 au plus)"
assert_contient "$sortie" "63 caractères" "le refus nomme la longueur, et non un caractère interdit"
assert_contient "$sortie" "SRV_K8S_NAMESPACES" "le refus nomme la variable à renseigner"
assert_egal "" "$(appels)" "aucun appel kubectl n'a eu lieu"
LISTE="web,data,monitoring"
titre "kubectl absent"
mkdir -p "$BAC/sans-kubectl"
for c in bash sh timeout id mkdir basename dirname date uname cat tee sed head rm mktemp grep tr; do ln -sf "$(command -v "$c")" "$BAC/sans-kubectl/$c"; done
sortie="$(env PATH="$BAC/sans-kubectl" SRV_K8S_NAMESPACES="$LISTE" timeout 60 bash "$CIBLE" --yes </dev/null 2>&1)" && code=0 || code=$?
assert_code 1 "$code" "sans kubectl, le script rend 1"
assert_contient "$sortie" "kubectl est introuvable" "le message nomme kubectl"
assert_contient "$sortie" "install-kubectl.sh" "et renvoie vers TASK-062"
titre "Préflight : l'API répond et identifie l'appelant"
sain; EXTRA=(KUBECTL_ERREUR='The connection to the server 127.0.0.1:6443 was refused - did you specify the right host or port?'); lancer --yes; EXTRA=()
assert_code 1 "$CODE" "un apiserver injoignable rend 1"
assert_contient "$sortie" "injoignable" "le message nomme l'apiserver"
assert_contient "$sortie" "install-kubectl.sh" "et renvoie vers TASK-062"
sain; EXTRA=(KUBECTL_ERREUR='error: error loading config file "/root/.kube/config": no such file or directory'); lancer --yes; EXTRA=()
assert_code 1 "$CODE" "un kubeconfig invalide rend 1"
assert_contient "$sortie" "Kubeconfig invalide" "message distinct de l'apiserver injoignable"
assert_absent "$sortie" "injoignable" "sans confondre les deux causes"
sain; EXTRA=(KUBECTL_ERREUR='Error from server (Forbidden): namespaces is forbidden: User "x" cannot list resource "namespaces"'); lancer --yes; EXTRA=()
assert_code 1 "$CODE" "un refus de droits rend 1"
assert_contient "$sortie" "Droits insuffisants" "troisième message, distinct des deux autres"
assert_absent "$(appels)" "apply" "aucune écriture n'est tentée"
titre "Idempotence, --dry-run et confirmation"
sain; EXTRA=(EXISTANTS="web data monitoring"); lancer --yes; EXTRA=()
assert_code 0 "$CODE" "tous les namespaces présents : le script rend 0"
assert_contient "$sortie" "existent déjà" "il annonce l'état au lieu d'agir"
assert_contient "$sortie" "aucun changement" "et le dit en toutes lettres"
assert_absent "$(appels)" "apply" "aucun namespace n'est réappliqué"
titre "Idempotence démontrée par deux exécutions enchaînées (regles.md §10)"
sain; LISTE="web,data"; EXTRA=(EXISTANTS=""); lancer --yes; EXTRA=()
assert_code 0 "$CODE" "la 1re exécution crée les absents et rend 0"
assert_egal "2" "$(grep -c -- 'apply -f -' <<<"$(appels)")" "un apply par namespace absent"
# Le journal des appels est vidé, les traces de création NON : c'est la
# deuxième exécution qui éprouve l'idempotence, sur l'état laissé par la première.
: > "$BAC/kubectl-appels"
lancer --yes
assert_code 0 "$CODE" "la 2e exécution rend 0 sans rien recréer"
assert_contient "$sortie" "existent déjà" "ce que la 1re a créé est relu comme existant"
assert_contient "$sortie" "aucun changement" "et l'absence de changement est annoncée"
assert_egal "0" "$(grep -c -- 'apply -f -' <<<"$(appels)")" "aucun apply à la seconde exécution"
assert_contient "$(appels)" "get namespaces -o name" "l'existant est relu à chaque exécution"
sain; LISTE="web"; EXTRA=(EXISTANTS="web-prod"); lancer --yes; EXTRA=()
assert_code 0 "$CODE" "un existant au nom seulement voisin ne dispense pas de créer"
assert_egal "1" "$(grep -c -- 'apply -f -' <<<"$(appels)")" "« web » est appliqué malgré « web-prod »"
assert_contient "$sortie" "namespace/web created" "la correspondance des existants est exacte"
sain; LISTE="web,data"; EXTRA=(EXISTANTS="web"); lancer --dry-run; EXTRA=()
assert_code 0 "$CODE" "--dry-run rend 0"
assert_contient "$sortie" "Namespaces à créer" "les namespaces à créer sont annoncés"
assert_contient "$sortie" "  data" "et nommés"
assert_absent "$sortie" "  web" "un namespace déjà présent n'y figure pas"
assert_contient "$(appels)" "get namespaces -o name" "l'existant est relu"
assert_absent "$(appels)" "apply" "--dry-run n'appelle jamais apply"
sain; LISTE="web"; EXTRA=(EXISTANTS=""); lancer
assert_code 1 "$CODE" "hors terminal et sans --yes, le script rend 1"
assert_contient "$sortie" "Configuration abandonnée" "le refus vient de confirm"
assert_absent "$(appels)" "apply" "et rien n'est créé"
sain; EXTRA=(EXISTANTS="" ASSUME_YES=true); lancer; EXTRA=()
assert_code 0 "$CODE" "un ASSUME_YES hérité confirme (décision 45 : script non destructif)"
assert_contient "$(appels)" "apply" "et les namespaces sont créés sans --yes"
titre "Création"
sain; LISTE="web,data,monitoring"; EXTRA=(EXISTANTS="default kube-system"); lancer --yes; EXTRA=()
assert_code 0 "$CODE" "trois namespaces absents sont créés, en 0"
assert_contient "$sortie" "[SUCCESS]" "et le verdict est déclaré"
assert_contient "$sortie" "namespace/monitoring created" "ce que kubectl a créé est affiché"
assert_egal "3" "$(grep -c -- 'apply -f -' <<<"$(appels)")" "un appel par namespace absent, trois ici"
assert_egal "oui" "$([ -f "$BAC/cree-monitoring" ] && echo oui || echo non)" "le manifeste reçu nomme bien monitoring"
sain; LISTE="web,data,monitoring"; EXTRA=(EXISTANTS="web data"); lancer --yes; EXTRA=()
assert_code 0 "$CODE" "seul l'absent est créé"
assert_egal "1" "$(grep -c -- 'apply -f -' <<<"$(appels)")" "un seul appel, pour monitoring"
titre "Échec partiel — bilan et code non nul (A78)"
sain; EXTRA=(EXISTANTS="" REFUSES="data"); lancer --yes; EXTRA=()
assert_code 1 "$CODE" "un namespace refusé par le cluster rend 1"
assert_absent "$sortie" "[SUCCESS]" "aucun [SUCCESS] ne masque l'échec partiel"
assert_contient "$sortie" "1 créé(s), 1 échoué (data), 1 non tenté(s)" "le bilan compte créés, échoué et non tentés"
assert_contient "$sortie" "Forbidden" "et la cause rendue par le cluster est citée"
assert_egal "2" "$(grep -c -- 'apply -f -' <<<"$(appels)")" "la boucle s'arrête au premier échec : monitoring n'est pas tenté"
titre "Délai dépassé — « timeout » enveloppe chaque appel"
faux timeout <<EOF
#!/bin/sh
case "\${TIMEOUT_SUR:-}:\$*" in "get:7 kubectl get "*) printf '%s\n' "\$*" >> "$BAC/timeout-appels"; exit 124 ;; esac
exec $(command -v timeout) "\$@"
EOF
: > "$BAC/timeout-appels"; sain; EXTRA=(TIMEOUT_SUR=get); lancer --yes; EXTRA=()
assert_code 1 "$CODE" "un appel kubectl qui expire rend 1"
assert_contient "$sortie" "délai dépassé" "le délai est nommé pour ce qu'il est"
assert_contient "$sortie" "kubectl get namespaces -o name" "et l'appel qui a expiré est nommé"
assert_egal "7 kubectl get namespaces -o name --request-timeout=5s" "$(head -1 "$BAC/timeout-appels")" "le délai externe vaut 7 (5 + 2), et l'appel reste borné à 5 s"
rm -f "$BAC/timeout"
titre "Délai dépassé sur un apply — le namespace est nommé, avec le bilan"
faux timeout <<EOF
#!/bin/sh
case "\${TIMEOUT_SUR:-}:\$*" in "apply:7 kubectl apply "*)
    printf '%s\n' "\$*" >> "$BAC/timeout-apply"; exit 124 ;; esac
exec $(command -v timeout) "\$@"
EOF
sain; LISTE="web,data,monitoring"; EXTRA=(EXISTANTS="" TIMEOUT_SUR=apply); lancer --yes; EXTRA=()
assert_code 1 "$CODE" "un apply qui expire rend 1"
assert_contient "$sortie" "délai dépassé" "le délai est nommé pour ce qu'il est"
assert_contient "$sortie" "« web »" "et le namespace dont l'apply a expiré est nommé"
assert_contient "$sortie" "0 créé(s), 1 échoué (web), 2 non tenté(s)" "le bilan compte créés, échoué et non tentés"
assert_absent "$sortie" "[SUCCESS]" "aucun [SUCCESS] ne masque l'échec partiel"
rm -f "$BAC/timeout"
titre "Ce que le script ne fait jamais"
assert_egal "0" "$(grep -c require_root "$CIBLE" || true)" "aucun require_root"
assert_egal "0" "$(grep -vE '^[[:space:]]*#' "$CIBLE" | grep -c 'k3s.yaml' || true)" "aucune référence à k3s.yaml hors commentaire"
assert_egal "0" "$(grep -vc -- '--request-timeout=' "$BAC/kubectl-tous" || true)" "chaque appel kubectl de toute la suite porte --request-timeout"
assert_egal "0" "$(grep -vcE '^kubectl (get|apply) ' "$BAC/kubectl-tous" || true)" "aucun appel kubectl ne sort de get ou apply"
assert_egal "0" "$(grep -cE -- ' delete|--prune| create | patch | replace | edit |scale' "$BAC/kubectl-tous" || true)" "aucune suppression ni écriture hors apply"
assert_egal "0" "$(grep -c 'namespace/default\|namespace/kube-' "$BAC/kubectl-tous" || true)" "aucun namespace réservé n'a été visé"

bilan "TASK-067 / configure-namespaces.sh"
