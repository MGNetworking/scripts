#!/usr/bin/env bash
# tests/integration/backup-resources.test.sh — Kubernetes/Maintenance/backup-resources.sh.
# Aucun cluster réel : un faux kubectl rend les formats, les messages et les codes
# du vrai, et note ses arguments. Le cluster simulé COMPTE des Secrets — c'est ce
# qui donne sa valeur au contrôle « aucun kind: Secret dans les fichiers produits ».
_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_dir/lib/common.sh" ] && [ "$_dir" != "/" ]; do _dir="$(dirname "$_dir")"; done
source "$_dir/lib/common.sh"
source "$SCRIPTS_ROOT/tests/lib/assert.sh"
CIBLE="$SCRIPTS_ROOT/Kubernetes/Maintenance/backup-resources.sh"
if [ ! -e /.dockerenv ]; then
    saute_indisponible "backup-resources.sh" "hors conteneur : un vrai kubectl ou un vrai cluster fausserait l'export"
    bilan "TASK-060 / backup-resources.sh"
fi
BAC="$(mktemp -d)"; export BAC
trap 'rm -rf "$BAC"' EXIT
present() { test -e "$1" && echo présente || echo absente; }
# Le faux kubectl tient les formats et les codes du vrai : « -o name » rend des
# lignes « namespace/<nom> », « -o yaml » le manifeste, et une liste vide rend le
# « No resources found » du vrai sur stderr — tenu à part du YAML par le script.
cat > "$BAC/kubectl" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$BAC/appels"
[ "${KUBECTL_INJOIGNABLE:-0}" = 1 ] && { echo "The connection to the server 127.0.0.1:6443 was refused" >&2; exit 1; }
case " ${KUBECTL_REFUS:-} " in *" $1 $2 "*) echo "Error from server (Forbidden): $2 is forbidden" >&2; exit 1 ;; esac
ns=""
[ "${3:-}" = -n ] && ns="-$4"
if [ "$1" = get ] && [ "$2" = namespaces ] && [ "${3:-}" = -o ] && [ "${4:-}" = name ]; then
    cat "$BAC/namespaces"; exit 0
fi
fic="$BAC/yaml-$2$ns"
if [ -s "$fic" ]; then cat "$fic"; else
    echo "No resources found${ns:+ in ${ns#-} namespace}." >&2
    printf 'apiVersion: v1\nitems: []\nkind: List\nmetadata:\n  resourceVersion: ""\n'
fi
EOF
chmod +x "$BAC/kubectl"
printf '%s\n' "namespace/default" "namespace/kube-system" > "$BAC/namespaces"
# Un manifeste aux formes réelles : metadata complet — uid, resourceVersion,
# managedFields, labels — plus spec et status peuplés. Le filtre doit en retirer
# tout ce qui est propre à l'instant du relevé, et rien d'autre.
manifeste() {   # <fichier> <kind> <nom> <namespace>
    cat > "$BAC/$1" <<EOF
apiVersion: apps/v1
items:
- apiVersion: apps/v1
  kind: $2
  metadata:
    creationTimestamp: "2026-09-16T10:00:00Z"
    labels:
      app: $3
    managedFields:
    - apiVersion: apps/v1
      fieldsType: FieldsV1
      manager: kubectl-create
    name: $3
    namespace: $4
    resourceVersion: "84213"
    uid: 6f1a2b3c-4d5e-6f70-8192-a3b4c5d6e7f8
  spec:
    replicas: 2
    selector:
      matchLabels:
        app: $3
  status:
    availableReplicas: 2
    conditions:
    - lastTransitionTime: "2026-09-16T10:00:05Z"
      status: "True"
      type: Available
kind: List
metadata:
  resourceVersion: ""
EOF
}
for paire in deployments=Deployment statefulsets=StatefulSet daemonsets=DaemonSet cronjobs=CronJob \
             services=Service ingresses=Ingress configmaps=ConfigMap persistentvolumeclaims=PersistentVolumeClaim; do
    for ns in default kube-system; do
        manifeste "yaml-${paire%%=*}-$ns" "${paire#*=}" "${paire%%=*}-1" "$ns"
    done
done
manifeste yaml-namespaces Namespace kube-system ""
manifeste yaml-storageclasses StorageClass standard ""
# Le cluster simulé compte un Secret : si le script le demandait, il l'obtiendrait.
manifeste yaml-secrets-default Secret mot-de-passe default
rm -f "$BAC/yaml-daemonsets-kube-system"   # un type sans objet : « No resources found »
CODE=0; sortie=""
# Chaque lancer repart d'un journal vierge : « appels » ne porte que sur le cas.
lancer() { : > "$BAC/appels"; CODE=0; sortie="$(PATH="$BAC:$PATH" bash "$CIBLE" "$@" 2>&1)" || CODE=$?; }
# La suite des fichiers produits, tous types et namespaces confondus.
produit() { cat "$1"/*.yaml; }

titre "Codes d'usage"
sortie="$(bash "$CIBLE" --help 2>&1)" && code=0 || code=$?
assert_code 0 "$code" "--help rend 0"
assert_contient "$sortie" "Codes de retour" "--help documente les codes de retour"
assert_contient "$sortie" "SRV_K8S_BACKUP_DIR" "--help documente la variable de repli"
assert_contient "$sortie" "storageclasses" "--help nomme les types exportés"
sortie="$(bash "$CIBLE" --option-inexistante 2>&1)" && code=0 || code=$?
assert_code 2 "$code" "une option inconnue rend 2"
sortie="$(bash "$CIBLE" --output 2>&1)" && code=0 || code=$?
assert_code 2 "$code" "--output sans valeur rend 2"
assert_contient "$sortie" "[ERROR]" "et le manque de valeur est signalé en [ERROR]"

titre "Destination — précédence, affichage, refus du dépôt"
lancer --dry-run
assert_code 0 "$CODE" "sans --output ni variable, le script rend 0"
assert_contient "$sortie" "Destination : /var/backups/kubernetes" "la destination par défaut est affichée"
export SRV_K8S_BACKUP_DIR="$BAC/depuis-env"
lancer --dry-run
assert_contient "$sortie" "$BAC/depuis-env" "SRV_K8S_BACKUP_DIR prime sur la valeur par défaut"
lancer --output "$BAC/depuis-option" --dry-run
assert_contient "$sortie" "$BAC/depuis-option" "--output prime sur SRV_K8S_BACKUP_DIR"
assert_absent "$sortie" "$BAC/depuis-env" "la variable n'est alors pas retenue"
unset SRV_K8S_BACKUP_DIR
lancer --output "$SCRIPTS_ROOT/sauvegardes"
assert_code 1 "$CODE" "une destination dans le dépôt est refusée"
assert_contient "$sortie" "Destination refusée" "le refus est nommé pour ce qu'il est"
assert_contient "$sortie" "$SCRIPTS_ROOT/sauvegardes" "et la destination refusée est nommée"
assert_egal "absente" "$(present "$SCRIPTS_ROOT/sauvegardes")" "rien n'est écrit dans le dépôt"
assert_absent "$sortie" "[SUCCESS]" "et rien n'est déclaré terminé"
( cd "$SCRIPTS_ROOT" && PATH="$BAC:$PATH" bash "$CIBLE" --output sauvegardes-rel ) >/dev/null 2>&1 && code=0 || code=$?
assert_code 1 "$code" "un chemin relatif qui mène au dépôt est refusé"
assert_egal "absente" "$(present "$SCRIPTS_ROOT/sauvegardes-rel")" "et rien n'y est créé"
ln -s "$SCRIPTS_ROOT" "$BAC/lien-vers-depot"
lancer --output "$BAC/lien-vers-depot/sauvegardes"
assert_code 1 "$CODE" "un lien symbolique vers le dépôt est refusé"
assert_contient "$sortie" "Destination refusée" "le refus est nommé là aussi, chemin résolu"

titre "kubectl introuvable, puis timeout introuvable"
sortie="$(PATH="/usr/bin:/bin" bash "$CIBLE" --output "$BAC/sans-kubectl" 2>&1)" && code=0 || code=$?
assert_code 1 "$code" "sans kubectl, le script rend 1"
assert_contient "$sortie" "Commande(s) requise(s) introuvable(s) : kubectl" "c'est le message de require_cmd"
assert_egal "absente" "$(present "$BAC/sans-kubectl")" "aucun dossier n'est créé"
# Un PATH qui porte tout sauf « timeout » : require_cmd doit le nommer, seul.
BASH_REEL="$(command -v bash)"
mkdir -p "$BAC/seul"
for outil in basename cat chmod date dirname id mkdir mktemp rm sed awk tr; do
    ln -s "$(command -v "$outil")" "$BAC/seul/$outil"
done
ln -s "$BAC/kubectl" "$BAC/seul/kubectl"
sortie="$(PATH="$BAC/seul" "$BASH_REEL" "$CIBLE" --output "$BAC/sans-timeout" 2>&1)" && CODE=0 || CODE=$?
assert_code 1 "$CODE" "sans timeout, le script rend 1"
assert_contient "$sortie" "Commande(s) requise(s) introuvable(s) : timeout" "et c'est timeout qu'il nomme"
assert_egal "absente" "$(present "$BAC/sans-timeout")" "aucun dossier n'est créé là non plus"

titre "Apiserver injoignable, puis droit refusé — avant toute écriture"
export KUBECTL_INJOIGNABLE=1
lancer --output "$BAC/sortie-muette"
unset KUBECTL_INJOIGNABLE
assert_code 1 "$CODE" "un apiserver injoignable rend 1"
assert_contient "$sortie" "[ERROR]" "l'échec est signalé en [ERROR]"
assert_contient "$sortie" "apiserver" "il nomme l'apiserver"
assert_contient "$sortie" "was refused" "la raison rendue par kubectl est montrée"
assert_egal "1" "$(wc -l < "$BAC/appels")" "un seul appel est tenté : la sonde arrête tout"
assert_egal "absente" "$(present "$BAC/sortie-muette")" "aucun dossier n'est créé"
assert_absent "$sortie" "[SUCCESS]" "et rien n'est déclaré terminé"
export KUBECTL_REFUS="get namespaces"
lancer --output "$BAC/sortie-refus"
unset KUBECTL_REFUS
assert_code 1 "$CODE" "un « get namespaces » refusé rend 1"
assert_contient "$sortie" "Droits insuffisants" "le refus est nommé pour ce qu'il est"
assert_absent "$sortie" "apiserver n'a pas répondu" "et non pris pour un apiserver muet"
assert_egal "absente" "$(present "$BAC/sortie-refus")" "aucun dossier n'est créé"

titre "--dry-run — destination, namespaces et types, sans rien écrire"
lancer --output "$BAC/dry" --dry-run
assert_code 0 "$CODE" "--dry-run rend 0"
assert_contient "$sortie" "Destination : $BAC/dry" "il affiche la destination retenue"
assert_contient "$sortie" "default" "il affiche les namespaces du cluster"
assert_contient "$sortie" "kube-system" "tous les namespaces"
assert_contient "$sortie" "storageclasses" "il affiche les types de cluster"
assert_contient "$sortie" "persistentvolumeclaims" "et les types relevés par namespace"
assert_egal "absente" "$(present "$BAC/dry")" "et il n'écrit rien"
assert_contient "$(cat "$BAC/appels")" "get namespaces -o name" "la liste des namespaces est demandée à l'apiserver"
assert_absent "$(cat "$BAC/appels")" "-o yaml" "aucun type n'est exporté"

titre "Export — arborescence, droits, contenu filtré"
lancer --output "$BAC/sortie"
assert_code 0 "$CODE" "l'export rend 0"
assert_contient "$sortie" "[SUCCESS]" "il le dit en [SUCCESS]"
DOSSIER="$(find "$BAC/sortie" -mindepth 1 -maxdepth 1 -type d)"
assert_contient "$sortie" "$DOSSIER" "le [SUCCESS] nomme le chemin produit"
assert_contient "$(basename "$DOSSIER")" "$(date +%Y%m%d)" "le sous-dossier porte la date du jour"
assert_egal "700" "$(stat -c %a "$DOSSIER")" "le sous-dossier horodaté est en 0700"
assert_egal "0" "$(find "$DOSSIER" -type f ! -perm 600 | wc -l)" "tous les fichiers produits sont en 0600"
assert_egal "18" "$(find "$DOSSIER" -type f | wc -l)" "un fichier par namespace et par type, plus les deux types de cluster"
assert_egal "présente" "$(present "$DOSSIER/deployments.default.yaml")" "un fichier par namespace et par type"
assert_egal "présente" "$(present "$DOSSIER/persistentvolumeclaims.kube-system.yaml")" "y compris pour le second namespace"
assert_egal "présente" "$(present "$DOSSIER/storageclasses.yaml")" "storageclasses, type de cluster, une seule fois"
assert_egal "présente" "$(present "$DOSSIER/namespaces.yaml")" "namespaces aussi"
CONTENU="$(produit "$DOSSIER")"
assert_contient "$CONTENU" "kind: Deployment" "le manifeste est exporté"
assert_contient "$CONTENU" "app: deployments-1" "avec ses labels"
assert_contient "$CONTENU" "replicas: 2" "et son spec"
assert_contient "$CONTENU" "namespace: kube-system" "chaque namespace a bien son propre contenu"
assert_absent "$CONTENU" "resourceVersion" "resourceVersion est retiré"
assert_absent "$CONTENU" "uid:" "uid est retiré"
assert_absent "$CONTENU" "managedFields" "managedFields est retiré"
assert_absent "$CONTENU" "manager: kubectl-create" "et son contenu avec lui"
assert_absent "$CONTENU" "status:" "le bloc status est retiré"
assert_absent "$CONTENU" "availableReplicas" "et son contenu avec lui"
assert_absent "$CONTENU" "lastTransitionTime" "y compris dans les listes imbriquées"
assert_absent "$CONTENU" "kind: Secret" "aucun objet Secret dans les fichiers produits"
assert_absent "$CONTENU" "No resources found" "le message de kubectl n'entre pas dans le YAML"
APPELS="$(cat "$BAC/appels")"
assert_contient "$APPELS" "get deployments -n default -o yaml --request-timeout=30s" "chaque type est demandé pour chaque namespace"
assert_contient "$APPELS" "get persistentvolumeclaims -n kube-system -o yaml" "sans exception"
assert_contient "$APPELS" "get storageclasses -o yaml --request-timeout=30s" "les types de cluster sont demandés sans namespace"
assert_egal "0" "$(grep -vcE -- '--request-timeout=[0-9]+s' "$BAC/appels" || true)" "chaque appel kubectl est borné"
assert_absent "$APPELS" "secrets" "le type Secret n'est jamais demandé, même au cluster qui en compte"
assert_absent "$APPELS" " all" "« get all » n'est jamais employé"

titre "Échec en cours d'export — le dossier incomplet est nommé (A78)"
export KUBECTL_REFUS="get configmaps"
lancer --output "$BAC/partiel"
unset KUBECTL_REFUS
assert_code 1 "$CODE" "un refus en cours d'export rend 1"
assert_contient "$sortie" "Droits insuffisants" "le refus est nommé pour ce qu'il est"
assert_contient "$sortie" "Dossier incomplet : $BAC/partiel/" "le dossier incomplet est nommé"
assert_egal "1" "$(find "$BAC/partiel" -mindepth 1 -maxdepth 1 -type d | wc -l)" "et il reste sur le disque, reconnaissable"
assert_absent "$sortie" "[SUCCESS]" "jamais [SUCCESS] : rien n'est déclaré terminé"

titre "Deux exécutions de la même seconde — aucun écrasement"
lancer --output "$BAC/sortie"
assert_code 0 "$CODE" "une seconde exécution rend 0"
assert_egal "2" "$(find "$BAC/sortie" -mindepth 1 -maxdepth 1 -type d | wc -l)" "elle crée son propre dossier horodaté"
assert_egal "18" "$(find "$BAC/sortie" -mindepth 1 -maxdepth 1 -type d | sort | head -1 | xargs -I{} find {} -type f | wc -l)" "sans tronquer la précédente"

titre "Délai dépassé — « timeout » enveloppe l'appel et le dit"
REEL_TIMEOUT="$(command -v timeout)"
: > "$BAC/timeout-appels"
# Un faux « timeout » : il n'intercepte que « get services » et rend 124 comme le
# vrai au bout du délai — l'attente réelle serait de 32 secondes.
cat > "$BAC/timeout" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >> "$BAC/timeout-appels"
case "\$*" in *" get services "*) exit 124 ;; esac
exec "$REEL_TIMEOUT" "\$@"
EOF
chmod +x "$BAC/timeout"
lancer --output "$BAC/lent"
assert_code 1 "$CODE" "un appel qui expire rend 1"
assert_contient "$sortie" "délai dépassé" "le délai est nommé pour ce qu'il est"
assert_absent "$sortie" "injoignable" "et non pris pour un apiserver injoignable"
assert_contient "$(cat "$BAC/timeout-appels")" "32 kubectl get services -n default -o yaml --request-timeout=30s" "« timeout » reçoit le délai de l'appel majoré de 2 s"
assert_absent "$sortie" "[SUCCESS]" "jamais [SUCCESS] : l'export est amputé (A78)"
rm -f "$BAC/timeout"

titre "kubectl seul, en lecture seule"
for verbe in delete apply patch exec cordon drain scale rollout edit create; do
    assert_absent "$APPELS" "$verbe" "aucun appel « $verbe » : rien n'est modifié sur le cluster"
done
assert_absent "$(cat "$CIBLE")" "k3s.yaml" "aucune référence à /etc/rancher/k3s/k3s.yaml : kubectl résout son kubeconfig"
assert_absent "$(cat "$CIBLE")" "k3s kubectl" "kubectl est appelé directement"
assert_absent "$(cat "$CIBLE")" "require_root" "aucun require_root : le script s'exécute sans root"
assert_absent "$(cat "$CIBLE")" "get all" "« get all » n'apparaît pas non plus dans le script"
assert_absent "$(cat "$CIBLE")" "secrets" "le type secrets n'y figure pas"

bilan "TASK-060 / backup-resources.sh"
