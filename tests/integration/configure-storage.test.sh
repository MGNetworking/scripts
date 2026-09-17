#!/usr/bin/env bash
# tests/integration/configure-storage.test.sh — Kubernetes/Configuration/configure-storage.sh.
# AUCUN CLUSTER RÉEL : un faux kubectl en tête de PATH, aux codes et messages du
# vrai. Il mémorise les annotations dans un état de fichiers, si bien que deux
# exécutions enchaînées se lisent l'une après l'autre.
_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_dir/lib/common.sh" ] && [ "$_dir" != "/" ]; do _dir="$(dirname "$_dir")"; done
source "$_dir/lib/common.sh"
source "$SCRIPTS_ROOT/tests/lib/assert.sh"

# SUITE_SOUS_TEST : la suite se relance elle-même contre une copie jetable du
# script (§ Mutations) ; c'est le seul cas où la cible n'est pas celle du dépôt.
CIBLE="${SUITE_SOUS_TEST:-$SCRIPTS_ROOT/Kubernetes/Configuration/configure-storage.sh}"
if [ ! -e /.dockerenv ]; then
    saute_indisponible "configure-storage.sh" "hors conteneur : un vrai kubectl ou un vrai cluster fausserait les appels"
    bilan "TASK-068 / configure-storage.sh"
fi
BAC="$(mktemp -d)"; export BAC
trap 'rm -rf "$BAC"' EXIT
faux() { cat > "$BAC/$1"; chmod +x "$BAC/$1"; }
: > "$BAC/kubectl-tous"; : > "$BAC/kubectl-appels"; : > "$BAC/sorties"

faux kubectl <<'SH'
#!/bin/sh
printf 'kubectl %s\n' "$*" >> "$BAC/kubectl-appels"
printf 'kubectl %s\n' "$*" >> "${KUBECTL_JOURNAL:-$BAC/kubectl-tous}"
case " $* " in *" create "*|*" delete "*|*" patch "*|*" replace "*|*" edit "*|*" apply "*|*" prune "*)
    printf 'verbe proscrit : %s\n' "$*" >&2; exit 3 ;; esac
[ -z "${KUBECTL_ERREUR:-}" ] || { printf '%s\n' "$KUBECTL_ERREUR" >&2; exit "${KUBECTL_CODE:-1}"; }
K='storageclass.kubernetes.io/is-default-class'; KB='storageclass.beta.kubernetes.io/is-default-class'
case "$1" in
get)
    [ "${2:-}" = "storageclass" ] || { printf 'get inattendu : %s\n' "$*" >&2; exit 1; }
    case "$*" in *"jsonpath="*) ;; *) printf 'jsonpath attendu : %s\n' "$*" >&2; exit 1 ;; esac
    for f in "$BAC"/classes/*; do
        [ -e "$f" ] || continue
        n="${f##*/}"; read -r ga beta < "$f"
        # Dérive simulée : la classe nommée est relue à sa valeur d'avant
        # l'annotation, comme si K3s avait réappliqué ses manifestes.
        if [ "${KUBECTL_DERIVE:-}" = "$n" ] && [ -f "$BAC/avant-$n" ]; then read -r ga beta < "$BAC/avant-$n"; fi
        [ "$ga" = "absent" ] && ga=""; [ "$beta" = "absent" ] && beta=""
        printf '%s %s %s\n' "$n" "$ga" "$beta"
    done ;;
annotate)
    [ "${2:-}" = "storageclass" ] || exit 1
    n="$3"; a="$4"; cle="${a%%=*}"; v="${a##*=}"
    case "$a" in "$K=true"|"$K=false"|"$KB=true"|"$KB=false") ;;
        *) printf 'annotation inattendue : %s\n' "$a" >&2; exit 1 ;; esac
    case " ${REFUSES:-} " in *" $n "*) printf 'Error from server (Forbidden): storageclasses "%s" is forbidden\n' "$n" >&2; exit 1 ;; esac
    [ -z "${ANNOTATE_ERREUR:-}" ] || { printf '%s\n' "$ANNOTATE_ERREUR" >&2; exit 1; }
    [ -f "$BAC/classes/$n" ] || { printf 'Error from server (NotFound): storageclasses "%s" not found\n' "$n" >&2; exit 1; }
    read -r ga beta < "$BAC/classes/$n"
    [ -f "$BAC/avant-$n" ] || printf '%s %s\n' "$ga" "$beta" > "$BAC/avant-$n"
    if [ "$cle" = "$K" ]; then ga="$v"; else beta="$v"; fi
    printf '%s %s\n' "$ga" "$beta" > "$BAC/classes/$n"
    printf 'storageclass/%s annotated\n' "$n" ;;
*) printf 'kubectl inattendu : %s\n' "$*" >&2; exit 1 ;;
esac
SH

CHEMIN="$BAC:$PATH"
BASE=(DELAI_TEST=5 LOG_DIR="$BAC/logs"); EXTRA=(); CODE=0; CLASSE="local-path"
envs() { ENVS=("${BASE[@]}"); [ -z "$CLASSE" ] || ENVS+=("SRV_K8S_STORAGE_CLASS=$CLASSE"); }
lancer() { envs; sortie="$(env -u SRV_K8S_STORAGE_CLASS PATH="$CHEMIN" "${ENVS[@]}" "${EXTRA[@]}" timeout 60 bash "$CIBLE" "$@" </dev/null 2>&1)" && CODE=0 || CODE=$?
           printf '%s\n' "$sortie" >> "$BAC/sorties"; }
# Réponse tapée sous un pseudo-terminal : le terrain de la décision 45.
lancer_pty() { rep="$1"; shift; envs; sortie="$(printf '%s\n' "$rep" | env -u SRV_K8S_STORAGE_CLASS PATH="$CHEMIN" "${ENVS[@]}" "${EXTRA[@]}" timeout 60 script -qec "bash $CIBLE $*" /dev/null 2>&1)" && CODE=0 || CODE=$?; }
# L'état du cluster : un fichier par classe, « <clé GA> <clé bêta> ». « absent »
# vaut annotation non posée ; le préfixe « beta: » ne marque que la clé bêta.
etat() { rm -rf "$BAC/classes"; mkdir -p "$BAC/classes"
         for c in "$@"; do case "${c#*=}" in
             beta:*) printf 'absent %s\n' "${c#*beta:}" ;;
             *)      printf '%s absent\n' "${c#*=}" ;;
         esac > "$BAC/classes/${c%%=*}"
         done; }
sain() { : > "$BAC/kubectl-appels"; rm -f "$BAC"/avant-*; }
appels() { cat "$BAC/kubectl-appels"; }
annotes() { grep -- '^kubectl annotate' "$BAC/kubectl-appels" || true; }

titre "Codes d'usage"
sortie="$(timeout 30 bash "$CIBLE" --help 2>&1)" && code=0 || code=$?
assert_code 0 "$code" "--help rend 0 sans cluster"
assert_contient "$sortie" "SRV_K8S_STORAGE_CLASS" "--help nomme la variable de classe"
assert_contient "$sortie" "ramenée à « false »" "--help dit comment la marque est retirée"
timeout 30 bash "$CIBLE" --option-inexistante >/dev/null 2>&1 && code=0 || code=$?
assert_code 2 "$code" "une option inconnue rend 2"

titre "Nom de classe mal formé — refusé en 2, avant tout appel kubectl"
etat local-path=true; sain
for m in "Local-Path" "local path" "local_path" "-local" "local-" "local..path" "local.path." "local-.path"; do
    CLASSE="$m"; lancer --yes
    assert_code 2 "$CODE" "le nom « $m » est refusé en 2"
done
CLASSE="local-path"
assert_contient "$sortie" "mal formé" "le refus dit ce qui est mal formé"; assert_egal "" "$(appels)" "aucun appel kubectl n'a eu lieu"
etat a--b=true; sain; CLASSE="a--b"; lancer --yes
assert_code 0 "$CODE" "« a--b » est accepté : un sous-domaine RFC 1123 admet deux tirets consécutifs"
CLASSE="local-path"

titre "Variable absente — local-path est la cible par défaut"
etat local-path=true; sain; CLASSE=""; lancer --yes
assert_code 0 "$CODE" "sans SRV_K8S_STORAGE_CLASS, la cible est local-path"; assert_contient "$sortie" "déjà la seule" "et la classe trouvée est bien celle-là"
etat longhorn=true; sain; lancer --yes
assert_code 1 "$CODE" "un cluster sans local-path est refusé en 1"; assert_contient "$sortie" "« local-path »" "et le refus nomme la cible par défaut"
CLASSE="local-path"

titre "kubectl absent"
mkdir -p "$BAC/sans-kubectl"
for c in bash sh timeout id mkdir basename dirname date uname cat tee sed head rm mktemp grep tr awk tail; do ln -sf "$(command -v "$c")" "$BAC/sans-kubectl/$c"; done
sortie="$(env PATH="$BAC/sans-kubectl" timeout 60 bash "$CIBLE" --yes </dev/null 2>&1)" && code=0 || code=$?
assert_code 1 "$code" "sans kubectl, le script rend 1"; assert_contient "$sortie" "kubectl est introuvable" "le message nomme kubectl"
assert_contient "$sortie" "install-kubectl.sh" "et renvoie vers TASK-062"

titre "Préflight : apiserver, kubeconfig, droits"
etat local-path=true
sain; EXTRA=(KUBECTL_ERREUR='The connection to the server 127.0.0.1:6443 was refused - did you specify the right host or port?'); lancer --yes; EXTRA=()
assert_code 1 "$CODE" "un apiserver injoignable rend 1"; assert_contient "$sortie" "injoignable" "le message nomme l'apiserver"
assert_contient "$sortie" "install-kubectl.sh" "et renvoie vers TASK-062"
sain; EXTRA=(KUBECTL_ERREUR='error: error loading config file "/root/.kube/config": no such file or directory'); lancer --yes; EXTRA=()
assert_code 1 "$CODE" "un kubeconfig invalide rend 1"; assert_contient "$sortie" "Kubeconfig invalide" "message distinct de l'apiserver injoignable"
assert_absent "$sortie" "injoignable" "sans confondre les deux causes"
sain; EXTRA=(KUBECTL_ERREUR='Error from server (Forbidden): storageclasses.storage.k8s.io is forbidden'); lancer --yes; EXTRA=()
assert_code 1 "$CODE" "un refus de droits rend 1"; assert_contient "$sortie" "Droits insuffisants" "troisième message, distinct des deux autres"
assert_absent "$(appels)" "annotate" "aucune écriture n'est tentée"

titre "Cible absente du cluster"
etat longhorn=true ceph=true; sain; lancer --yes
assert_code 1 "$CODE" "une cible absente du cluster rend 1"; assert_contient "$sortie" "« local-path » est absente" "le refus la nomme"
assert_contient "$sortie" "SRV_K8S_STORAGE_CLASS" "et dit où la renseigner"; assert_absent "$(appels)" "annotate" "rien n'est modifié"
assert_absent "$sortie" "[SUCCESS]" "aucun [SUCCESS] ne masque le refus"

titre "Idempotence, confirmation et --dry-run"
etat local-path=true longhorn=false; sain; lancer --yes
assert_code 0 "$CODE" "la cible déjà seule par défaut rend 0"; assert_contient "$sortie" "déjà la seule" "le script constate au lieu d'agir"
assert_contient "$sortie" "aucun changement" "et le dit en toutes lettres"; assert_absent "$(appels)" "annotate" "aucune annotation n'est posée"
etat local-path=true longhorn=true; sain; lancer
assert_code 1 "$CODE" "hors terminal et sans --yes, un changement à faire rend 1"
assert_contient "$sortie" "--yes" "le message nomme l'option qui débloque"; assert_absent "$(appels)" "annotate" "et rien n'est annoté"
sain; EXTRA=(ASSUME_YES=true); lancer; EXTRA=()
assert_code 1 "$CODE" "un ASSUME_YES hérité ne confirme pas à la place du --yes (décision 45)"; assert_absent "$(appels)" "annotate" "et rien n'est annoté"
sain; lancer_pty n
assert_code 1 "$CODE" "une réponse « n » sous terminal abandonne en 1"; assert_contient "$sortie" "Configuration abandonnée" "le refus est celui de confirm"
assert_absent "$(appels)" "annotate" "rien n'est annoté"
sain; lancer_pty o
assert_code 0 "$CODE" "une réponse « o » sous terminal annote, en 0"; assert_contient "$sortie" "[SUCCESS]" "et le verdict est déclaré"
etat local-path=true longhorn=true; sain; lancer --dry-run
assert_code 0 "$CODE" "--dry-run rend 0"; assert_contient "$sortie" "Annotations à changer" "les annotations à changer sont annoncées"
assert_contient "$sortie" "storageclass.kubernetes.io/is-default-class=false" "la classe à démarquer est nommée, avec sa valeur"
assert_absent "$sortie" "storageclass.kubernetes.io/is-default-class=true" "la cible, déjà marquée, n'y figure pas"
assert_contient "$sortie" "[dry-run]" "et le dry-run est annoncé"; assert_absent "$(appels)" "annotate" "--dry-run n'appelle jamais annotate"
assert_egal "true absent" "$(cat "$BAC/classes/longhorn")" "l'état du cluster est resté intact"

titre "Ordre sûr — la cible est marquée AVANT que les autres soient démarquées"
etat local-path=absent longhorn=true; sain; lancer --yes
assert_code 0 "$CODE" "marquer la cible et démarquer l'autre rend 0"; assert_contient "$sortie" "[SUCCESS]" "et le verdict est déclaré"
assert_contient "$sortie" "est annotée en premier" "l'ordre est annoncé"; assert_egal "2" "$(grep -c . <<<"$(annotes)")" "deux annotations, une par classe"
assert_contient "$(annotes | head -1)" "storageclass local-path storageclass.kubernetes.io/is-default-class=true" "la cible est annotée la première : jamais zéro classe par défaut"
assert_contient "$(annotes | tail -1)" "storageclass longhorn storageclass.kubernetes.io/is-default-class=false" "l'autre est ramenée à false, sans suppression d'annotation"
assert_egal "true absent|false absent" "$(cat "$BAC/classes/local-path")|$(cat "$BAC/classes/longhorn")" "l'état final est celui voulu"
etat local-path=absent longhorn=false; sain; lancer --yes
assert_code 0 "$CODE" "aucune classe par défaut : la cible est marquée, en 0"; assert_contient "$(annotes | head -1)" "storageclass local-path storageclass.kubernetes.io/is-default-class=true" "et rien d'autre n'est annoté"

titre "Clé bêta — une classe que seule la clé bêta marque est démarquée"
etat local-path=absent longhorn=beta:true; sain; lancer --yes
assert_code 0 "$CODE" "démarquer la seule clé bêta d'une classe rend 0"; assert_contient "$sortie" "[SUCCESS]" "et le verdict est déclaré"
assert_egal "2" "$(grep -c . <<<"$(annotes)")" "deux annotations : la cible en GA, l'autre en bêta"
assert_contient "$(annotes | tail -1)" "storageclass longhorn storageclass.beta.kubernetes.io/is-default-class=false" "la clé bêta est ramenée à false, jamais supprimée"
assert_egal "true absent|absent false" "$(cat "$BAC/classes/local-path")|$(cat "$BAC/classes/longhorn")" "l'état final : la cible par la clé GA, la classe bêta démarquée"
etat local-path=absent longhorn=true; printf 'true true\n' > "$BAC/classes/longhorn"; sain; lancer --yes
assert_code 0 "$CODE" "une classe marquée par les deux clés rend 0"; assert_contient "$sortie" "[SUCCESS]" "et la relecture finale ne voit que la cible"
assert_egal "3" "$(grep -c . <<<"$(annotes)")" "chaque clé qui valait true est ramenée à false, en plus de la cible"
assert_egal "true absent|false false" "$(cat "$BAC/classes/local-path")|$(cat "$BAC/classes/longhorn")" "plus aucune clé par défaut hors la cible"

titre "Idempotence démontrée par deux exécutions enchaînées (regles.md §10)"
etat local-path=absent longhorn=true; sain; lancer --yes
assert_code 0 "$CODE" "la 1re exécution annote les deux classes et rend 0"
: > "$BAC/kubectl-appels"; lancer --yes
assert_code 0 "$CODE" "la 2e exécution rend 0 sans rien réannoter"; assert_contient "$sortie" "déjà la seule" "ce que la 1re a posé est relu comme tel"
assert_egal "0" "$(grep -c . <<<"$(annotes)")" "aucun annotate à la seconde exécution"; assert_contient "$(appels)" "get storageclass" "l'existant est relu à chaque exécution"

titre "Échec partiel — bilan de ce qui a changé et de ce qui reste (A78)"
etat local-path=absent longhorn=true zfs=true; sain; EXTRA=(REFUSES="zfs"); lancer --yes; EXTRA=()
assert_code 1 "$CODE" "une annotation refusée par le cluster rend 1"; assert_absent "$sortie" "[SUCCESS]" "aucun [SUCCESS] ne masque l'échec partiel"
assert_contient "$sortie" "Bilan : 2 annotation(s) appliquée(s), 1 non appliquée(s)" "le bilan compte appliquées et restantes"
assert_contient "$sortie" "Restaient : zfs" "et nomme ce qui reste à faire"; assert_contient "$sortie" "Forbidden" "la cause rendue par le cluster est citée"
assert_egal "true absent" "$(cat "$BAC/classes/local-path")" "la cible a été marquée avant l'échec : jamais zéro classe par défaut"
assert_egal "false absent" "$(cat "$BAC/classes/longhorn")" "et l'autre a bien été démarquée avant le refus"

titre "Annotation de la cible refusée — aucun démarquage n'est tenté"
etat local-path=absent longhorn=true zfs=true; sain; EXTRA=(REFUSES="local-path"); lancer --yes; EXTRA=()
assert_code 1 "$CODE" "un refus sur la seule annotation de la cible rend 1"; assert_absent "$sortie" "[SUCCESS]" "aucun [SUCCESS] ne masque l'échec"
assert_contient "$sortie" "« local-path »" "le refus nomme la classe visée"
assert_egal "1" "$(grep -c . <<<"$(annotes)")" "un seul annotate tenté : la boucle s'arrête au premier échec"
assert_contient "$(annotes)" "storageclass local-path" "et c'est bien celui de la cible"
assert_egal "true absent|true absent" "$(cat "$BAC/classes/longhorn")|$(cat "$BAC/classes/zfs")" "les autres restent marquées : rien n'a été démarqué après l'échec"

titre "Cause d'un annotate en échec — nommée comme pour une lecture"
etat local-path=absent longhorn=true; sain
EXTRA=(ANNOTATE_ERREUR='The connection to the server 127.0.0.1:6443 was refused - did you specify the right host or port?'); lancer --yes; EXTRA=()
assert_code 1 "$CODE" "un annotate sur un apiserver injoignable rend 1"; assert_contient "$sortie" "injoignable" "l'apiserver est nommé, comme sur une lecture"
assert_contient "$sortie" "install-kubectl.sh" "et renvoie vers TASK-062"; assert_absent "$sortie" "[SUCCESS]" "aucun [SUCCESS] ne masque l'échec"
sain; EXTRA=(ANNOTATE_ERREUR='Error from server (NotFound): storageclasses "local-path" not found'); lancer --yes; EXTRA=()
assert_code 1 "$CODE" "un annotate sur une classe disparue rend 1"; assert_contient "$sortie" "NotFound" "la ressource absente est nommée pour ce qu'elle est"
assert_egal "true absent" "$(cat "$BAC/classes/longhorn")" "et rien n'a été démarqué derrière l'échec"

titre "Délai dépassé — « timeout » enveloppe chaque appel"
REEL_TIMEOUT="$(command -v timeout)"
faux timeout <<EOF
#!/bin/sh
case "\${TIMEOUT_SUR:-}:\$*" in
    "get:7 kubectl get "*)           printf '%s\n' "\$*" >> "$BAC/timeout-appels"; exit 124 ;;
    "annotate:7 kubectl annotate "*) printf '%s\n' "\$*" >> "$BAC/timeout-appels"; exit 124 ;;
    *) exec $REEL_TIMEOUT "\$@" ;;
esac
EOF
etat local-path=true longhorn=true; sain; : > "$BAC/timeout-appels"; EXTRA=(TIMEOUT_SUR=get); lancer --yes; EXTRA=()
assert_code 1 "$CODE" "un appel kubectl qui expire rend 1"; assert_contient "$sortie" "délai dépassé" "le délai est nommé pour ce qu'il est"
assert_contient "$sortie" "kubectl get storageclass" "et l'appel qui a expiré est nommé"
assert_contient "$(head -1 "$BAC/timeout-appels")" "7 kubectl get storageclass " "le délai externe vaut 7 (5 + 2)"
assert_contient "$(head -1 "$BAC/timeout-appels")" "--request-timeout=5s" "et l'appel reste borné à 5 s"
sain; : > "$BAC/timeout-appels"; EXTRA=(TIMEOUT_SUR=annotate); lancer --yes; EXTRA=()
assert_code 1 "$CODE" "un annotate qui expire rend 1"; assert_contient "$sortie" "« longhorn »" "la classe dont l'annotation a expiré est nommée"
assert_contient "$sortie" "0 annotation(s) appliquée(s), 1 non appliquée(s)" "le bilan compte ce qui a été fait et ce qui reste"
assert_absent "$sortie" "[SUCCESS]" "aucun [SUCCESS] ne masque l'échec"
rm -f "$BAC/timeout"

titre "Vérification finale — l'état dérivé est signalé"
etat local-path=true longhorn=true; sain; EXTRA=(KUBECTL_DERIVE=longhorn); lancer --yes; EXTRA=()
assert_code 1 "$CODE" "une marque qui revient après coup fait rendre 1"; assert_absent "$sortie" "[SUCCESS]" "aucun [SUCCESS] ne masque l'écart"
# La liste des classes est jointe par un espace final : le motif le reprend tel quel.
assert_contient "$sortie" "2 classe(s) par défaut (local-path longhorn " "la relecture nomme l'écart et les classes"
assert_contient "$sortie" "K3s" "et dit d'où peut venir la dérive"

titre "Mutations — la suite entière doit échouer contre chacune"
# Ce qui est prouvé ici n'est pas qu'un mutant se comporte mal, mais que la SUITE
# le voie : chaque mutant est donc jugé par une relance complète de ce fichier
# contre lui. SUITE_SOUS_TEST désigne le script sous test, et empêche la relance
# de rejouer cette section.
MUT="$BAC/mutant-configure-storage.sh"
juge_mutant() {   # <libellé> : MUT porte le script à juger
    SUITE_SOUS_TEST="$MUT" timeout 300 bash "${BASH_SOURCE[0]}" >"$BAC/mutant-$1.log" 2>&1 && code=0 || code=$?
    assert_code_non_nul "$code" "la suite échoue contre le mutant « $1 »"
    assert_contient "$(cat "$BAC/mutant-$1.log")" "ÉCHEC" "et c'est une vérification qui l'a vu, pas un plantage"
}
cp "$CIBLE" "$MUT"; SUITE_SOUS_TEST="$MUT" timeout 300 bash "${BASH_SOURCE[0]}" >"$BAC/mutant-temoin.log" 2>&1 && code=0 || code=$?
assert_code 0 "$code" "copie intacte : la relance passe — les échecs des mutants ne viennent pas d'elle"
# Ordre inversé : la cible n'est plus marquée en tête du plan, elle l'est en queue.
sed -e 's#^grep -qxF "\$CIBLE" "\$TEMPORAIRE/defaut".*$#:#' -e 's#^done < "\$TEMPORAIRE/etat"$#&\n    PLAN+=("$CIBLE|$CLE|true")#' "$CIBLE" > "$MUT"
juge_mutant "ordre inversé"
# Clé bêta ignorée : le démarquage écrit la clé GA là où la bêta marquait.
sed -e 's#^CLE_B=.*$#CLE_B="$CLE"#' "$CIBLE" > "$MUT"
juge_mutant "clé bêta ignorée"
# Échec d'une annotation : la boucle doit s'arrêter là, sans rien démarquer.
sed -e 's#^\( *\)exit 1$#\1:#' "$CIBLE" > "$MUT"
juge_mutant "exit 1 de la boucle retiré"
sed -e 's#^\[ -t 0 \].*$#:#' -e 's#^confirm "Appliquer.*$#:#' "$CIBLE" > "$MUT"
juge_mutant "garde de confirmation retirée"

titre "Ce que le script ne fait jamais"
assert_egal "0" "$(grep -c require_root "$CIBLE" || true)" "aucun require_root"
assert_egal "0" "$(grep -vE '^[[:space:]]*#' "$CIBLE" | grep -c 'k3s.yaml' || true)" "aucune référence à k3s.yaml hors commentaire"
assert_egal "0" "$(grep -vc -- '--request-timeout=' "$BAC/kubectl-tous" || true)" "chaque appel kubectl de toute la suite porte --request-timeout"
assert_egal "0" "$(grep -vcE '^kubectl (get storageclass|annotate storageclass) ' "$BAC/kubectl-tous" || true)" "aucun appel kubectl ne sort de get ou annotate"
assert_egal "0" "$(grep -cE -- ' delete|--prune| create| patch | replace | edit |apply |scale' "$BAC/kubectl-tous" || true)" "aucune suppression ni verbe hors annotate"
assert_egal "0" "$(grep -- '^kubectl annotate' "$BAC/kubectl-tous" | grep -vc -e ' storageclass.kubernetes.io/is-default-class=' -e ' storageclass.beta.kubernetes.io/is-default-class=' || true)" "toute annotation porte une des deux clés par défaut, GA ou bêta"
assert_egal "0" "$(grep -c -- 'is-default-class- ' "$BAC/kubectl-tous" || true)" "la marque est retirée par =false, jamais par suppression de l'annotation"

bilan "TASK-068 / configure-storage.sh"
