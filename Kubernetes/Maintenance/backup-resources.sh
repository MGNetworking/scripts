#!/usr/bin/env bash
set -Eeuo pipefail

# Exporte en YAML les manifests du cluster dans un dossier local, hors du dépôt.
# Lecture seule ; les Secrets ne sont jamais exportés — « get all » n'est pas employé.

_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_dir/lib/common.sh" ] && [ "$_dir" != "/" ]; do _dir="$(dirname "$_dir")"; done
source "$_dir/lib/common.sh"

TYPES_CLUSTER="namespaces storageclasses"
TYPES_NAMESPACES="deployments statefulsets daemonsets cronjobs services ingresses configmaps persistentvolumeclaims"
DELAI=30   # --request-timeout de chaque appel ; « timeout » l'entoure avec 2 s de marge
DEST_DEFAUT="/var/backups/kubernetes"

usage() {
    cat <<'EOF'
backup-resources.sh — exporte en YAML les manifests du cluster, hors dépôt.

Usage : backup-resources.sh [--output <dossier>] [--dry-run] [--help]

  --output <dossier>  destination ; à défaut SRV_K8S_BACKUP_DIR, sinon
                      /var/backups/kubernetes. Un sous-dossier horodaté y est
                      créé à chaque exécution — dossiers 0700, fichiers 0600.
  --dry-run           affiche destination, namespaces et types, n'écrit rien
  --help              affiche cette aide

Types exportés, et eux seuls : namespaces, deployments, statefulsets, daemonsets,
cronjobs, services, ingresses, configmaps, persistentvolumeclaims, storageclasses.
Les Secrets ne le sont jamais. Destination refusée si elle est dans le dépôt, chemin
résolu. Appels bornés par --request-timeout ; rien n'est écrit sur le cluster.

Codes de retour :
  0  export terminé, chemin affiché
  1  destination refusée, kubectl ou timeout introuvable, apiserver injoignable,
     droits insuffisants, délai dépassé, ou export incomplet
  2  option inconnue, ou --output sans valeur
EOF
}

DESTINATION=""
DRY_RUN="non"
while [ "${1:-}" != "" ]; do
    case "$1" in
        --help|-h) usage; exit 0 ;;
        --output)
            shift
            DESTINATION="${1:-}"
            [ -n "$DESTINATION" ] || die "L'option --output attend un dossier de destination." 2
            shift
            ;;
        --dry-run) DRY_RUN="oui"; shift ;;
        *) die "Option inconnue : $1" 2 ;;
    esac
done
[ -n "$DESTINATION" ] || DESTINATION="${SRV_K8S_BACKUP_DIR:-$DEST_DEFAUT}"

# Chemin résolu sans rien créer : on remonte au premier parent existant, dont
# « pwd -P » suit les liens, puis on recolle la partie absente — un lien
# symbolique vers le dépôt mène donc au même refus qu'un chemin relatif.
resoudre() {
    local chemin="$1" reste=""
    while [ -n "$chemin" ] && [ ! -d "$chemin" ]; do
        reste="/$(basename "$chemin")$reste"; chemin="$(dirname "$chemin")"
    done
    printf '%s%s\n' "$(cd "$chemin" && pwd -P)" "$reste"
}

RACINE="$(cd "$SCRIPTS_ROOT" && pwd -P)"
DEST_RESOLU="$(resoudre "$DESTINATION")"
case "$DEST_RESOLU" in
    "$RACINE"|"$RACINE"/*) die "Destination refusée : $DEST_RESOLU est dans le dépôt ($RACINE), qui est public. Utiliser --output ou SRV_K8S_BACKUP_DIR hors du dépôt." ;;
esac

require_cmd kubectl timeout
TEMPORAIRE="$(mktemp -d)" || die "Répertoire temporaire indisponible."
trap 'rm -rf "$TEMPORAIRE"' EXIT

# Traduit l'échec d'un appel ; « fin » complète le message des rubriques qui ont
# leur propre mot à dire. Le 124 vient de « timeout » : l'appeler « injoignable »
# accuserait le cluster à tort.
echec() {
    local appel="$1" fin="${2:-}"
    [ -z "$ERREUR" ] || printf '%s\n' "$ERREUR" | sed 's/^/  /' >&2
    case "$CODE:$ERREUR" in
        124:*)       die "Délai dépassé (${DELAI} s) : $appel n'a pas répondu.$fin" ;;
        *Forbidden*) die "Droits insuffisants : $appel a été refusé.$fin" ;;
        *NotFound*)  die "L'apiserver ne connaît pas la ressource demandée par $appel.$fin" ;;
    esac
    die "L'apiserver n'a pas répondu : $appel a échoué.$fin"
}

# Retire resourceVersion, uid, managedFields et status : propres à l'instant du
# relevé. Un bloc se reconnaît à son indentation, où « - clé: » vaut deux
# colonnes de plus que le tiret.
filtre() {
    awk '
        /^[[:space:]]*[^[:space:]]/ {
            indent = match($0, /[^ ]/) - 1
            if ($0 ~ /^[ ]*- /) indent += 2
            if (bloc != "" && indent > bloc_indent) next
            bloc = ""
            cle = $0; sub(/^[ ]*/, "", cle); sub(/:.*/, "", cle)
            if (cle == "status" || cle == "managedFields") { bloc = cle; bloc_indent = indent; next }
            if (cle == "resourceVersion" || cle == "uid") next
        }
        { print }
    '
}

# Écrit l'export d'un type dans un fichier. La sortie d'erreur de kubectl reste à
# part du YAML : « No resources found » ne doit pas devenir une ligne du fichier.
exporter() {
    local fichier="$1"; shift
    CODE=0
    timeout "$((DELAI + 2))" kubectl "$@" --request-timeout="${DELAI}s" 2>"$TEMPORAIRE/err" | filtre > "$fichier" || CODE=$?
    [ "$CODE" = 0 ] || { ERREUR="$(cat "$TEMPORAIRE/err")"; echec "« kubectl $* »" " Dossier incomplet : $CIBLE"; }
    chmod 600 "$fichier"
}

# La sonde précède toute écriture, et donne la liste des namespaces : un apiserver
# muet ne doit pas laisser de dossier derrière lui.
CODE=0; REP="$(timeout "$((DELAI + 2))" kubectl get namespaces -o name --request-timeout="${DELAI}s" 2>"$TEMPORAIRE/err")" || CODE=$?
ERREUR="$(cat "$TEMPORAIRE/err")"
[ "$CODE" = 0 ] || echec "« kubectl get namespaces »"
NAMESPACES="$(printf '%s\n' "$REP" | sed -n 's|^namespace/||p')"
[ -n "$NAMESPACES" ] || die "Aucun namespace rendu par l'apiserver : rien n'a été écrit."

info "Destination : $DEST_RESOLU"

if [ "$DRY_RUN" = "oui" ]; then
    info "Namespaces : $(printf '%s\n' "$NAMESPACES" | tr '\n' ' ')"
    info "Types : $TYPES_CLUSTER (cluster) ; $TYPES_NAMESPACES (par namespace)"
    success "--dry-run : rien n'a été écrit."
    exit 0
fi

umask 077
mkdir -p "$DESTINATION" || die "Création impossible : $DESTINATION — sans root, /var/backups n'est pas inscriptible ; --output ou SRV_K8S_BACKUP_DIR désignent un autre dossier."
# mktemp -d : le sous-dossier porte l'horodatage et ne peut pas écraser une
# sauvegarde précédente, même pour deux exécutions de la même seconde.
CIBLE="$(mktemp -d "$DESTINATION/$(date +%Y%m%d-%H%M%S)-XXXXXX")" || die "Création impossible dans $DESTINATION."
chmod 700 "$CIBLE"

for type in $TYPES_CLUSTER; do exporter "$CIBLE/${type}.yaml" get "$type" -o yaml; done
for ns in $NAMESPACES; do
    for type in $TYPES_NAMESPACES; do exporter "$CIBLE/${type}.${ns}.yaml" get "$type" -n "$ns" -o yaml; done
done

success "Export terminé : $CIBLE"
