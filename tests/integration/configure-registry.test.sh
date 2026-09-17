#!/usr/bin/env bash
# tests/integration/configure-registry.test.sh — Kubernetes/Configuration/configure-registry.sh.
#
# AUCUN CLUSTER RÉEL : un faux kubectl en tête de PATH, aux codes et messages du
# vrai. Il consigne ses arguments, relève « ps -eo args » pendant l'appel, garde
# le manifeste reçu sur l'entrée standard et le décode : c'est ce qui prouve à la
# fois que le jeton part bien — dans le Secret — et qu'il ne part jamais par
# ailleurs. L'état du cluster tient dans un fichier par namespace, si bien que
# deux exécutions enchaînées se lisent l'une l'autre.
#
# config/registry.env vit dans config/, zone du dépôt : le bac à sable recopie
# lib/common.sh et le script, et s'enracine de lui-même — SCRIPTS_ROOT se résout
# depuis l'emplacement de common.sh. L'identité des copies est prouvée avant
# usage. Les valeurs sentinelles ne passent ni par l'environnement ni par un
# argument : un fichier du bac les porte, que le faux kubectl lit.
_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_dir/lib/common.sh" ] && [ "$_dir" != "/" ]; do _dir="$(dirname "$_dir")"; done
source "$_dir/lib/common.sh"
source "$SCRIPTS_ROOT/tests/lib/assert.sh"

# SUITE_SOUS_TEST : la suite se relance elle-même contre une copie jetable du
# script (§ Mutations) ; c'est le seul cas où la cible n'est pas celle du dépôt.
CIBLE="${SUITE_SOUS_TEST:-$SCRIPTS_ROOT/Kubernetes/Configuration/configure-registry.sh}"
if [ ! -e /.dockerenv ]; then
    saute_indisponible "configure-registry.sh" "hors conteneur : un vrai kubectl ou un vrai cluster fausserait les appels"
    bilan "TASK-071 / configure-registry.sh"
fi
BAC="$(mktemp -d)"; export BAC
trap 'rm -rf "$BAC"' EXIT
mkdir -p "$BAC/src/lib" "$BAC/src/config" "$BAC/src/Kubernetes/Configuration" \
         "$BAC/bin" "$BAC/bin-nu" "$BAC/etat" "$BAC/recu" "$BAC/tmp" "$BAC/logs"
cp "$SCRIPTS_ROOT/lib/common.sh" "$BAC/src/lib/common.sh"
cp "$CIBLE" "$BAC/src/Kubernetes/Configuration/configure-registry.sh"
SRC="$BAC/src/Kubernetes/Configuration/configure-registry.sh"
CONF="$BAC/src/config/registry.env"
NOM="registry-credentials"; export NOM   # lu par le faux kubectl
SERVEUR="registry.exemple.test:5000"; IDENT="identifiant-sentinelle-9f3a"; JETON="jeton-sentinelle-7c1b"
printf '%s\n%s\n' "$IDENT" "$JETON" > "$BAC/sentinelles"
: > "$BAC/attendu"
faux() { cat > "$BAC/bin/$1"; chmod +x "$BAC/bin/$1"; }
for outil in bash sh timeout id mkdir basename dirname date uname cat tee sed head rm mktemp grep tr stat base64 sha256sum ps script awk sort cut find; do
    for d in "$BAC/bin" "$BAC/bin-nu"; do ln -sf "$(command -v "$outil")" "$d/$outil"; done
done

faux kubectl <<'SH'
#!/bin/sh
SID="$(sed -n 1p "$BAC/sentinelles")"; SJET="$(sed -n 2p "$BAC/sentinelles")"
printf 'kubectl %s\n' "$*" >> "$BAC/kubectl-appels"
printf 'kubectl %s\n' "$*" >> "$BAC/kubectl-tous"
ps -eo args >> "$BAC/ps" 2>/dev/null
for interdit in "$SID" "$SJET"; do
    case "$*" in *"$interdit"*) printf '%s\n' "$*" >> "$BAC/fuite"; exit 99 ;; esac
done
case " $* " in *" --request-timeout="*) ;; *) printf 'appel sans --request-timeout : %s\n' "$*" >&2; exit 9 ;; esac
[ -z "${KUBECTL_ERREUR:-}" ] || { printf '%s\n' "$KUBECTL_ERREUR" >&2; exit "${KUBECTL_CODE:-1}"; }
non() { printf 'refusé : %s\n' "$1" >&2; exit 2; }
case "$1 $2" in
"get namespaces")
    [ "${3:-} ${4:-}" = "-o name" ] || non 'get namespaces sans -o name'
    for n in ${CLUSTER_NS:-web data monitoring}; do printf 'namespace/%s\n' "$n"; done ;;
"get secret")
    case " $* " in *" jsonpath="*) ;; *) non 'get secret sans jsonpath' ;; esac
    ns=""; prec=""
    for a in "$@"; do [ "$prec" = "-n" ] && ns="$a"; prec="$a"; done
    [ -n "$ns" ] || non "namespace absent de l'appel"
    if [ -f "$BAC/etat/$ns" ]; then cat "$BAC/etat/$ns"
    else printf 'Error from server (NotFound): secrets "%s" not found\n' "$NOM" >&2; exit 1; fi ;;
"apply -f")
    [ "${3:-}" = "-" ] || non 'apply sans entrée standard'
    m="$BAC/recu/manifeste"; cat > "$m"
    grep -qx 'apiVersion: v1' "$m" || non 'apiVersion v1 attendue'
    grep -qx 'kind: Secret' "$m" || non 'kind Secret attendu'
    grep -qx 'type: kubernetes.io/dockerconfigjson' "$m" || non 'type dockerconfigjson attendu'
    ns="$(sed -n 's/^  namespace: //p' "$m")"
    emp="$(sed -n 's/^    mgnetworking\/empreinte: //p' "$m")"
    [ -n "$ns" ] && [ -n "$emp" ] || non 'namespace ou empreinte absents du manifeste'
    sed -n 's/^  \.dockerconfigjson: //p' "$m" > "$BAC/recu/base64"
    base64 -d < "$BAC/recu/base64" > "$BAC/recu/json" 2>/dev/null || non 'base64 illisible'
    j="$(cat "$BAC/recu/json")"
    if [ -f "$BAC/attendu" ]; then
        for champ in "\"username\":\"$SID\"" "\"password\":\"$SJET\"" "\"auth\":\"$(printf '%s:%s' "$SID" "$SJET" | base64 -w0)\""; do
            case "$j" in *"$champ"*) ;; *) non 'champ attendu absent du JSON décodé' ;; esac
        done
    fi
    case "$j" in '{"auths":{"'*'":{"username":"'*'","password":"'*'","auth":"'*'"}}}') ;;
        *) non 'JSON décodé de forme inattendue' ;; esac
    case " ${APPLY_REFUSES:-} " in *" $ns "*) printf 'Error from server (Forbidden): secrets "%s" is forbidden\n' "$NOM" >&2; exit 1 ;; esac
    if [ -f "$BAC/etat/$ns" ]; then printf 'secret/%s configured\n' "$NOM"
    else printf 'secret/%s created\n' "$NOM"; fi
    printf '%s' "$emp" > "$BAC/etat/$ns" ;;
*) printf 'kubectl inattendu : %s\n' "$*" >&2; exit 1 ;;
esac
SH
chmod +x "$BAC/bin/kubectl"

CHEMIN="$BAC/bin:$PATH"
BASE=(DELAI_TEST=5 LOG_DIR="$BAC/logs" TMPDIR="$BAC/tmp"); EXTRA=(); LISTE="web,data,monitoring"; CODE=0
config() {   # [serveur] [identifiant] [jeton] — arguments absents : les valeurs neutres
    printf 'REGISTRY_SERVEUR="%s"\nREGISTRY_IDENTIFIANT="%s"\nREGISTRY_JETON="%s"\n' \
        "${1-$SERVEUR}" "${2-$IDENT}" "${3-$JETON}" > "$CONF"
    chmod 600 "$CONF"
}
lancer() { sortie="$(env PATH="$CHEMIN" SRV_K8S_NAMESPACES="$LISTE" "${BASE[@]}" "${EXTRA[@]}" timeout 60 bash "$SRC" "$@" </dev/null 2>&1)" && CODE=0 || CODE=$?
           printf '%s\n' "$sortie" >> "$BAC/sorties"; }
# Réponse tapée sous un pseudo-terminal : le terrain de la décision 45.
lancer_pty() { rep="$1"; shift; sortie="$(printf '%s\n' "$rep" | env PATH="$CHEMIN" SRV_K8S_NAMESPACES="$LISTE" "${BASE[@]}" "${EXTRA[@]}" timeout 60 script -qec "bash $SRC $*" /dev/null 2>&1)" && CODE=0 || CODE=$?
               printf '%s\n' "$sortie" >> "$BAC/sorties"; }
sain() { : > "$BAC/kubectl-appels"; : > "$BAC/ps"; : > "$BAC/fuite"; rm -rf "$BAC/etat"; mkdir -p "$BAC/etat"; }
pose() { for a in "$@"; do printf '%s' "${a#*=}" > "$BAC/etat/${a%%=*}"; done; }
appels() { cat "$BAC/kubectl-appels"; }
# Le contenu attendu du Secret, construit comme le script le construit : c'est la
# spécification du manifeste, et l'empreinte qui doit se lire en annotation.
attendu() { printf '{"auths":{"%s":{"username":"%s","password":"%s","auth":"%s"}}}' \
    "$SERVEUR" "$IDENT" "$JETON" "$(printf '%s:%s' "$IDENT" "$JETON" | base64 -w0)"; }
empreinte() { printf '%s' "$(attendu)" | sha256sum | cut -d' ' -f1; }
config
AVANT_SRC="$(cd "$BAC/src" && find . -type f | sort)"

titre "Bac à sable — copies fidèles du script et de son socle"
if cmp -s "$CIBLE" "$SRC" && cmp -s "$SCRIPTS_ROOT/lib/common.sh" "$BAC/src/lib/common.sh"; then
    ok "le bac à sable porte des copies fidèles du script et de son socle"
else
    ko "le bac à sable porte des copies fidèles du script et de son socle" "les fichiers diffèrent"
fi

titre "Codes d'usage"
sortie="$(timeout 30 bash "$CIBLE" --help 2>&1)" && code=0 || code=$?
assert_code 0 "$code" "--help rend 0 sans cluster"
assert_contient "$sortie" "config/registry.env" "--help nomme le fichier de configuration"
assert_contient "$sortie" "REGISTRY_SERVEUR" "--help nomme les variables attendues"
assert_contient "$sortie" "imagePullSecrets" "--help dit comment un Pod s'en sert"
assert_contient "$sortie" "échappés" "--help dit ce que deviennent guillemets et antislashs"
assert_contient "$sortie" "Codes de retour" "--help documente les codes de retour"
timeout 30 bash "$CIBLE" --option-inexistante >/dev/null 2>&1 && code=0 || code=$?
assert_code 2 "$code" "une option inconnue rend 2"

titre "Droits du fichier de configuration — refusé en 1, avant tout chargement"
rm -f "$CONF"; sain; lancer --yes
assert_code 1 "$CODE" "un config/registry.env absent rend 1"
assert_contient "$sortie" "config/registry.env" "le refus nomme le fichier attendu"
assert_contient "$sortie" "registry.env.example" "et son modèle"
assert_egal "" "$(appels)" "aucun appel kubectl n'a eu lieu"
for d in 644 640 400 660; do
    config; chmod "$d" "$CONF"; sain; lancer --yes
    assert_code 1 "$CODE" "un fichier en 0$d rend 1"
done
assert_contient "$sortie" "droits 660" "le refus nomme les droits trouvés"
assert_contient "$sortie" "600 attendus" "et ceux qui sont attendus"
assert_absent "$sortie" "$JETON" "le jeton du fichier refusé n'est pas affiché"
assert_egal "" "$(appels)" "aucun appel kubectl n'a eu lieu"
config
if [ "$(id -u)" = 0 ]; then
    chown 1000 "$CONF"; sain; lancer --yes
    assert_code 1 "$CODE" "un fichier d'un autre propriétaire rend 1"
    assert_contient "$sortie" "propriétaire" "le refus nomme le propriétaire"
    config
else
    saute_par_nature "fichier d'un autre propriétaire" "hors root, aucun autre propriétaire n'est atteignable"
fi
# L'ordre compte : le contrôle des droits passe avant la recherche de kubectl.
rm -f "$CONF"; PATH_SAIN="$CHEMIN"; CHEMIN="$BAC/bin-nu"; lancer --yes; CHEMIN="$PATH_SAIN"
assert_code 1 "$CODE" "sans kubectl, un fichier absent est refusé d'abord"
assert_contient "$sortie" "config/registry.env" "le refus nomme le fichier"
assert_absent "$sortie" "kubectl est introuvable" "le contrôle des droits précède la recherche de kubectl"
config

titre "Identifiants absents ou mal formés — refusés en 2, avant tout appel"
config ""; sain; lancer --yes
assert_code 2 "$CODE" "un REGISTRY_SERVEUR vide rend 2"
assert_contient "$sortie" "REGISTRY_SERVEUR" "le refus nomme la variable"
config "$SERVEUR" ""; sain; lancer --yes
assert_code 2 "$CODE" "un REGISTRY_IDENTIFIANT vide rend 2"
assert_contient "$sortie" "REGISTRY_IDENTIFIANT" "le refus nomme la variable"
config "$SERVEUR" "$IDENT" ""; sain; lancer --yes
assert_code 2 "$CODE" "un REGISTRY_JETON vide rend 2"
assert_contient "$sortie" "REGISTRY_JETON" "le refus nomme la variable"
assert_egal "" "$(appels)" "aucun appel kubectl n'a eu lieu"
for m in "https://registry.exemple.test" "registry.exemple.test/v2" "registry exemple.test"; do
    config "$m"; sain; lancer --yes
    assert_code 2 "$CODE" "l'adresse « $m » est refusée en 2"
done
assert_contient "$sortie" "mal formé" "le refus dit ce qui est mal formé"
assert_absent "$sortie" "registry exemple.test" "et ne recopie pas l'adresse refusée"
PIEGE_ID="$(printf 'ident\tifiant')"; PIEGE_JET="$(printf 'je\nton')"
config "$SERVEUR" "$PIEGE_ID"; sain; lancer --yes
assert_code 2 "$CODE" "une tabulation dans l'identifiant rend 2"
assert_contient "$sortie" "REGISTRY_IDENTIFIANT" "le refus nomme la variable"
assert_absent "$sortie" "$PIEGE_ID" "et n'affiche pas la valeur refusée"
config "$SERVEUR" "$IDENT" "$PIEGE_JET"; sain; lancer --yes
assert_code 2 "$CODE" "un retour à la ligne dans le jeton rend 2"
assert_contient "$sortie" "REGISTRY_JETON" "le refus nomme la variable"
assert_egal "" "$(appels)" "aucun appel kubectl n'a eu lieu"
config

titre "Guillemets et barres obliques inverses — échappés, le JSON reste valide"
PIEGE_ID='compte"a\b'; PIEGE_JET='jeton"c\d'
printf 'REGISTRY_SERVEUR="%s"\nREGISTRY_IDENTIFIANT="compte\\"a\\\\b"\nREGISTRY_JETON="jeton\\"c\\\\d"\n' "$SERVEUR" > "$CONF"
chmod 600 "$CONF"; rm -f "$BAC/attendu"; sain; LISTE="web"; EXTRA=(CLUSTER_NS="web"); lancer --yes; EXTRA=()
assert_code 0 "$CODE" "une valeur à guillemet et antislash est échappée, non refusée"
assert_contient "$(cat "$BAC/recu/json")" '"username":"compte\"a\\b"' "le JSON décodé porte la valeur échappée"
assert_contient "$(cat "$BAC/recu/json")" "\"auth\":\"$(printf '%s:%s' "$PIEGE_ID" "$PIEGE_JET" | base64 -w0)\"" "et l'empreinte auth les valeurs brutes"
: > "$BAC/attendu"; config; LISTE="web,data,monitoring"

titre "Liste des namespaces — refusée en 2, avant tout appel kubectl"
sain
for m in "" ",web" "web," "web,,data" "web data" "Web" "-web" "web-" "a.b"; do
    LISTE="$m"; lancer --yes
    assert_code 2 "$CODE" "la liste « $m » est refusée en 2"
done
LISTE="web,data,monitoring"
assert_contient "$sortie" "SRV_K8S_NAMESPACES" "le refus nomme la variable de liste"
assert_egal "" "$(appels)" "aucun appel kubectl n'a eu lieu"
sain; EXTRA=(CLUSTER_NS="web data"); lancer --yes; EXTRA=()
assert_code 1 "$CODE" "un namespace de la liste absent du cluster rend 1"
assert_contient "$sortie" "monitoring" "le refus le nomme"
assert_contient "$sortie" "configure-namespaces.sh" "et renvoie vers TASK-067"
assert_absent "$(appels)" "apply" "rien n'est appliqué, pas même les namespaces présents"

titre "kubectl absent"
mkdir -p "$BAC/sans-kubectl"
for c in bash sh timeout id mkdir basename dirname date uname cat tee sed head rm mktemp grep tr stat; do ln -sf "$(command -v "$c")" "$BAC/sans-kubectl/$c"; done
sortie="$(env PATH="$BAC/sans-kubectl" SRV_K8S_NAMESPACES="$LISTE" LOG_DIR="$BAC/logs" TMPDIR="$BAC/tmp" timeout 60 bash "$SRC" --yes </dev/null 2>&1)" && code=0 || code=$?
assert_code 1 "$code" "sans kubectl, le script rend 1"
assert_contient "$sortie" "kubectl est introuvable" "le message nomme kubectl"
assert_contient "$sortie" "install-kubectl.sh" "et renvoie vers TASK-062"

titre "Préflight — apiserver, kubeconfig et droits, causes distinctes"
sain; EXTRA=(KUBECTL_ERREUR='The connection to the server 127.0.0.1:6443 was refused - did you specify the right host or port?'); lancer --yes; EXTRA=()
assert_code 1 "$CODE" "un apiserver injoignable rend 1"
assert_contient "$sortie" "injoignable" "le message nomme l'apiserver"
assert_contient "$sortie" "install-kubectl.sh" "et renvoie vers TASK-062"
sain; EXTRA=(KUBECTL_ERREUR='error: error loading config file "/root/.kube/config": no such file or directory'); lancer --yes; EXTRA=()
assert_code 1 "$CODE" "un kubeconfig invalide rend 1"
assert_contient "$sortie" "Kubeconfig invalide" "message distinct de l'apiserver injoignable"
assert_absent "$sortie" "injoignable" "sans confondre les deux causes"
sain; EXTRA=(KUBECTL_ERREUR='Error from server (Forbidden): secrets is forbidden: User "x" cannot list resource "secrets"'); lancer --yes; EXTRA=()
assert_code 1 "$CODE" "un refus de droits rend 1"
assert_contient "$sortie" "Droits insuffisants" "troisième message, distinct des deux autres"
assert_absent "$(appels)" "apply" "aucune écriture n'est tentée"

titre "--dry-run — rien n'est appliqué, rien du contenu n'est montré"
sain; lancer --dry-run
assert_code 0 "$CODE" "--dry-run rend 0 avec trois Secrets à créer"
assert_contient "$sortie" "à créer (3)" "les Secrets à créer sont comptés"
assert_contient "$sortie" "web data monitoring" "et nommés"
assert_absent "$sortie" "$JETON" "le jeton n'est pas montré"
assert_absent "$sortie" ".dockerconfigjson" "ni le contenu du manifeste"
assert_absent "$(appels)" "apply" "--dry-run n'appelle jamais apply"
LISTE="web"; sain; pose "web=empreinte-perimee"; lancer --dry-run
assert_code 0 "$CODE" "--dry-run rend 0 avec un Secret périmé"
assert_contient "$sortie" "à mettre à jour (1) : web" "le Secret périmé est annoncé comme tel"
assert_absent "$(appels)" "apply" "et rien n'est appliqué"
LISTE="web,data,monitoring"

titre "Création dans chaque namespace"
sain; lancer --yes
assert_code 0 "$CODE" "trois namespaces sans Secret : création, en 0"
assert_contient "$sortie" "[SUCCESS]" "le verdict est déclaré"
assert_contient "$sortie" "secret/registry-credentials created" "ce que kubectl a créé est affiché"
assert_egal "3" "$(grep -c -- 'apply -f -' <<<"$(appels)")" "un apply par namespace, trois ici"
assert_egal "3" "$(find "$BAC/etat" -type f | wc -l | tr -d ' ')" "les trois namespaces portent le Secret"
assert_egal "$(empreinte)" "$(cat "$BAC/etat/monitoring")" "l'empreinte du JSON est posée en annotation"
assert_egal "monitoring" "$(sed -n 's/^  namespace: //p' "$BAC/recu/manifeste")" "le manifeste reçu nomme bien monitoring"

titre "Idempotence — deux exécutions enchaînées (regles.md §10)"
sain; LISTE="web,data"; lancer --yes
assert_code 0 "$CODE" "la 1re exécution crée les deux Secrets et rend 0"
assert_egal "2" "$(grep -c -- 'apply -f -' <<<"$(appels)")" "un apply par namespace absent"
# Le journal des appels est vidé, l'état du cluster NON : c'est la seconde
# exécution qui éprouve l'idempotence, sur ce que la première a laissé.
: > "$BAC/kubectl-appels"; lancer --yes
assert_code 0 "$CODE" "la 2e exécution rend 0 sans rien réappliquer"
assert_contient "$sortie" "déjà à jour" "ce que la 1re a posé est relu comme tel"
assert_contient "$sortie" "aucun changement" "et l'absence de changement est annoncée"
assert_egal "0" "$(grep -c -- 'apply -f -' <<<"$(appels)")" "aucun apply à la seconde exécution"
assert_contient "$(appels)" "get secret" "l'état est relu à chaque exécution"
LISTE="web,data,monitoring"
sain; pose "web=$(empreinte)" "data=empreinte-perimee"; LISTE="web,data"; lancer --yes
assert_code 0 "$CODE" "un Secret à jour et un Secret périmé rendent 0"
assert_contient "$sortie" "0 créé(s), 1 mis à jour" "le bilan compte séparément créations et mises à jour"
assert_egal "1" "$(grep -c -- 'apply -f -' <<<"$(appels)")" "seul le Secret périmé est appliqué"
assert_egal "data" "$(sed -n 's/^  namespace: //p' "$BAC/recu/manifeste")" "et c'est celui du namespace périmé"
assert_egal "$(empreinte)" "$(cat "$BAC/etat/data")" "l'empreinte périmée a été remplacée"
LISTE="web,data,monitoring"

titre "Échec partiel — bilan de ce qui a été appliqué et de ce qui reste (A78)"
sain; EXTRA=(APPLY_REFUSES=data); lancer --yes; EXTRA=()
assert_code 1 "$CODE" "un Secret refusé par le cluster rend 1"
assert_absent "$sortie" "[SUCCESS]" "aucun [SUCCESS] ne masque l'échec partiel"
assert_contient "$sortie" "1 appliqué(s), 1 échoué (data), 1 non tenté(s)" "le bilan compte appliqué, échoué et non tenté"
assert_contient "$sortie" "(Forbidden)" "et la cause rendue par le cluster est citée"
assert_absent "$sortie" "Error from server" "sous forme résumée, jamais le message brut de kubectl"
assert_egal "2" "$(grep -c -- 'apply -f -' <<<"$(appels)")" "la boucle s'arrête au premier échec : monitoring n'est pas tenté"

titre "Délai dépassé — « timeout » enveloppe chaque appel"
REEL_TIMEOUT="$(command -v timeout)"
# Le lien symbolique est retiré AVANT d'écrire : « cat > » suivrait le lien et
# écraserait le vrai timeout, dont le faux se sert comme repli.
rm -f "$BAC/bin/timeout"
faux timeout <<EOF
#!/bin/sh
case "\${TIMEOUT_SUR:-}:\$*" in
    "get:7 kubectl get "*)     printf '%s\n' "\$*" >> "$BAC/timeout-appels"; exit 124 ;;
    "apply:7 kubectl apply "*) printf '%s\n' "\$*" >> "$BAC/timeout-appels"; exit 124 ;;
    *) exec $REEL_TIMEOUT "\$@" ;;
esac
EOF
sain; : > "$BAC/timeout-appels"; EXTRA=(TIMEOUT_SUR=get); lancer --yes; EXTRA=()
assert_code 1 "$CODE" "un appel kubectl qui expire rend 1"
assert_contient "$sortie" "délai dépassé" "le délai est nommé pour ce qu'il est"
assert_contient "$sortie" "kubectl get namespaces" "et l'appel qui a expiré est nommé"
assert_egal "7 kubectl get namespaces -o name --request-timeout=5s" "$(head -1 "$BAC/timeout-appels")" "le délai externe vaut 7 (5 + 2), et l'appel reste borné à 5 s"
sain; : > "$BAC/timeout-appels"; LISTE="web,data"; EXTRA=(CLUSTER_NS="web data" TIMEOUT_SUR=apply); lancer --yes; EXTRA=()
assert_code 1 "$CODE" "un apply qui expire rend 1"
assert_contient "$sortie" "délai dépassé" "le délai est nommé sur l'apply aussi"
assert_contient "$sortie" "« web »" "et le namespace dont l'apply a expiré est nommé"
assert_contient "$sortie" "0 appliqué(s), 1 échoué (web), 1 non tenté(s)" "le bilan compte appliqué, échoué et non tenté"
assert_absent "$sortie" "[SUCCESS]" "aucun [SUCCESS] ne masque l'échec partiel"
rm -f "$BAC/bin/timeout"; ln -sf "$REEL_TIMEOUT" "$BAC/bin/timeout"; LISTE="web,data,monitoring"

titre "Confirmation — décision 45"
sain; LISTE="web"; EXTRA=(CLUSTER_NS="web"); lancer
assert_code 1 "$CODE" "hors terminal et sans --yes, un changement rend 1"
assert_contient "$sortie" "--yes" "le message nomme l'option qui débloque"
assert_absent "$(appels)" "apply" "et rien n'est appliqué"
sain; EXTRA=(CLUSTER_NS="web" ASSUME_YES=true); lancer; EXTRA=()
assert_code 1 "$CODE" "un ASSUME_YES hérité ne confirme pas à la place du --yes"
assert_absent "$(appels)" "apply" "et rien n'est appliqué"
EXTRA=(CLUSTER_NS="web"); sain; lancer_pty n
assert_code 1 "$CODE" "une réponse « n » sous terminal abandonne en 1"
assert_contient "$sortie" "Configuration abandonnée" "le refus est celui de confirm"
assert_absent "$(appels)" "apply" "et rien n'est appliqué"
sain; lancer_pty o
assert_code 0 "$CODE" "une réponse « o » sous terminal applique, en 0"
assert_contient "$sortie" "[SUCCESS]" "et le verdict est déclaré"
EXTRA=(); LISTE="web,data,monitoring"

titre "Aucun fichier temporaire ne survit à l'exécution"
sain; LISTE="web,data"; EXTRA=(CLUSTER_NS="web data"); lancer --yes; EXTRA=(); LISTE="web,data,monitoring"
assert_code 0 "$CODE" "l'exécution rend 0"
assert_egal "" "$(find "$BAC/tmp" -mindepth 1 2>/dev/null | head -5)" "le répertoire temporaire est rendu vide"
assert_egal "$AVANT_SRC" "$(cd "$BAC/src" && find . -type f | sort)" "aucun fichier n'est laissé dans l'arborescence du script"

titre "Le jeton circule dans le Secret, et nulle part ailleurs"
sain; lancer --yes
assert_code 0 "$CODE" "l'exécution complète rend 0"
assert_contient "$(cat "$BAC/recu/json")" "$JETON" "le Secret reçu porte le jeton : la preuve n'est pas vide"
assert_contient "$(cat "$BAC/recu/json")" "$IDENT" "et l'identifiant"
assert_absent "$(cat "$BAC/sorties")" "$JETON" "le jeton n'est dans aucune sortie de la suite"
assert_absent "$(cat "$BAC/sorties")" "$IDENT" "l'identifiant non plus"
journal="$(cat "$BAC/logs/configure-registry.log" 2>/dev/null)"
assert_non_vide "$journal" "le script tient un journal"
assert_absent "$journal" "$JETON" "le jeton n'y est pas journalisé"
assert_absent "$journal" "$IDENT" "l'identifiant non plus"
assert_absent "$(appels)" "$JETON" "le jeton n'est dans les arguments d'aucun appel kubectl"
assert_egal "" "$(cat "$BAC/fuite")" "le faux kubectl n'a vu aucune sentinelle en argument"
assert_non_vide "$(cat "$BAC/ps")" "la table des processus a bien été relevée pendant les appels"
assert_absent "$(cat "$BAC/ps")" "$JETON" "le jeton n'est dans la ligne de commande d'aucun processus"
assert_absent "$(cat "$BAC/ps")" "$IDENT" "l'identifiant non plus"

# Une relance porte SUITE_SOUS_TEST : elle juge le script qu'on lui donne, elle
# ne rejoue donc pas cette section — sans quoi elle se relancerait sans fin.
if [ -z "${SUITE_SOUS_TEST:-}" ]; then
    titre "Mutations — la suite entière doit échouer contre chacune"
    # Ce qui est prouvé ici n'est pas qu'un mutant se comporte mal, mais que la
    # SUITE le voie : chacun est jugé par une relance complète de ce fichier
    # contre lui. Les relances sont indépendantes — chacune son bac — et
    # tournent de front ; le verdict n'est lu qu'après.
    JUGES=(); PIDS=()
    # Chaque mutant est posé dans sa propre arborescence, socle compris : la
    # relance éprouve aussi « --help », qui doit résoudre lib/common.sh.
    mutant() {   # <nom> — lit le script sur l'entrée standard, rend son chemin
        local d="$BAC/mut/$1"
        mkdir -p "$d/Kubernetes/Configuration" "$d/lib"
        cp "$SCRIPTS_ROOT/lib/common.sh" "$d/lib/common.sh"
        cat > "$d/Kubernetes/Configuration/configure-registry.sh"
        printf '%s' "$d/Kubernetes/Configuration/configure-registry.sh"
    }
    relancer() { JUGES+=("$1")
        SUITE_SOUS_TEST="$2" timeout 600 bash "${BASH_SOURCE[0]}" >"$BAC/juge-$1.log" 2>&1 &
        PIDS+=("$!"); }
    # Les programmes sed qui portent un « $ » littéral sont entre guillemets
    # doubles, échappé : entre guillemets simples shellcheck les signalerait
    # (SC2016), et ce sont bien des « $ » de sed, non des expansions du shell.
    relancer "témoin" "$(mutant temoin < "$CIBLE")"
    relancer "jeton en argument" \
        "$(sed -e "s#< <(manifeste \"\$n\")#--docker-password=\"\$JETON\" < <(manifeste \"\$n\")#" "$CIBLE" | mutant jeton)"
    relancer "contrôle des droits retiré" \
        "$(sed -e "s#^\[ \"\$DROITS\" = 600 \].*#:#" "$CIBLE" | mutant droits)"
    relancer "comparaison d'empreinte retirée" \
        "$(sed -e "s#\[ \"\$REP\" = \"\$EMPREINTE\" \]#false#" "$CIBLE" | mutant empreinte)"
    for i in "${!JUGES[@]}"; do
        wait "${PIDS[$i]}" && code=0 || code=$?
        if [ "${JUGES[$i]}" = "témoin" ]; then
            assert_code 0 "$code" "copie intacte : la relance passe — les échecs des mutants ne viennent pas d'elle"
        else
            assert_code_non_nul "$code" "la suite échoue contre le mutant « ${JUGES[$i]} »"
            assert_contient "$(cat "$BAC/juge-${JUGES[$i]}.log")" "ÉCHEC" "et c'est une vérification qui l'a vu, pas un plantage"
        fi
    done
fi

titre "Ce que le script ne fait jamais"
assert_egal "0" "$(grep -c require_root "$CIBLE" || true)" "aucun require_root"
assert_egal "0" "$(grep -vE '^[[:space:]]*#' "$CIBLE" | grep -c 'k3s.yaml' || true)" "aucune référence à k3s.yaml hors commentaire"
assert_egal "0" "$(grep -c run_logged "$CIBLE" || true)" "run_logged n'est jamais employé ici"
assert_egal "0" "$(grep -c -- '--docker-password\|--docker-server\|--docker-username' "$CIBLE" || true)" "aucune option kubectl porteuse d'identifiant"
assert_egal "0" "$(grep -vc -- '--request-timeout=' "$BAC/kubectl-tous" || true)" "chaque appel kubectl de toute la suite porte --request-timeout"
assert_egal "0" "$(grep -vcE '^kubectl (get|apply) ' "$BAC/kubectl-tous" || true)" "aucun appel kubectl ne sort de get ou apply"
assert_egal "0" "$(grep -cE -- ' delete|--prune| create | patch | replace | edit |scale' "$BAC/kubectl-tous" || true)" "aucune suppression ni écriture hors apply"

bilan "TASK-071 / configure-registry.sh"
