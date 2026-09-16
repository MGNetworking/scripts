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
Les Secrets ne le sont jamais. Destination refusée si elle est dans le dépôt,
chemin résolu. Appels bornés par --request-timeout ; rien n'est écrit sur le cluster.

Codes de retour :
  0  export terminé, chemin affiché
  1  destination refusée, kubectl, timeout ou realpath introuvable, apiserver
     injoignable, droits insuffisants, délai dépassé, ou export incomplet
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

require_cmd kubectl timeout realpath

# Le refus porte sur le chemin RÉSOLU, et c'est lui qui est créé ensuite.
# « realpath -m » traite les « .. » même derrière un composant absent et suit les
# liens existants : aucun détour ne mène dans le dépôt, qui est public.
RACINE="$(cd "$SCRIPTS_ROOT" && pwd -P)"
DEST_RESOLU="$(realpath -m -- "$DESTINATION")"
case "$DEST_RESOLU" in
    "$RACINE"|"$RACINE"/*) die "Destination refusée : $DEST_RESOLU est dans le dépôt ($RACINE), qui est public. Utiliser --output ou SRV_K8S_BACKUP_DIR hors du dépôt." ;;
esac

TEMPORAIRE="$(mktemp -d)" || die "Répertoire temporaire indisponible."
trap 'rm -rf "$TEMPORAIRE"' EXIT

# Traduit l'échec d'un appel ; « fin » complète le message des rubriques qui ont
# leur propre mot à dire. Le 124 vient de « timeout » : l'appeler « injoignable »
# accuserait le cluster à tort.
echec() {
    local appel="$1" fin="${2:-}"
    [ -z "$ERREUR" ] || printf '%s\n' "$ERREUR" | sed 's/^/  /' >&2
    case "$CODE:$ERREUR" in
        124:*) die "L'appel a été interrompu : délai dépassé (${DELAI} s) — $appel.$fin" ;;
        *Forbidden*) die "Droits insuffisants : $appel a été refusé.$fin" ;;
        *"doesn't have a resource type"*) die "Type de ressource inconnu de l'apiserver : $appel.$fin" ;;
    esac
    die "L'apiserver n'a pas répondu : $appel a échoué.$fin"
}

# Le format de « kubectl get <type> -o yaml » est fixe : une List dont chaque item
# commence par « - » en colonne 0, ses clés indentées de 2 et celles de son metadata
# de 4. Le retrait est donc STRUCTUREL et non textuel — un « status: » de ConfigMap
# est conservé, celui d'un item est retiré. kubectl ≥ 1.21 omet déjà managedFields.
filtre() {
    awk '
        function ind(l) { return match(l, /[^ ]/) - 1 }
        function cle(l) { c = l; sub(/^ */, "", c); sub(/^- /, "", c); sub(/:.*/, "", c); return c }
        /^[[:space:]]*$/ { print; next }
        {
            i = ind($0)
            if (bloc != "" && (i > bloc_i || (i == bloc_i && $0 ~ /^ *- /))) next
            bloc = ""
            n = cle($0)
            if ($0 ~ /^- /)          { item = 1; meta = (n == "metadata") }
            else if (i == 0)         { item = 0; meta = 0 }
            else if (item && i == 2) { meta = (n == "metadata") }
            if (item && i == 2 && n == "status") { bloc = n; bloc_i = 2; next }
            if (meta && i == 4 && (n == "uid" || n == "resourceVersion" || n == "managedFields")) { bloc = n; bloc_i = 4; next }
            if (!item && i == 2 && n == "resourceVersion") next
            print
        }
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
mkdir -p "$DEST_RESOLU" || die "Création impossible : $DEST_RESOLU — sans root, /var/backups n'est pas inscriptible ; --output ou SRV_K8S_BACKUP_DIR désignent un autre dossier."
# mktemp -d : le sous-dossier porte l'horodatage et ne peut pas écraser une
# sauvegarde précédente, même pour deux exécutions de la même seconde.
CIBLE="$(mktemp -d "$DEST_RESOLU/$(date +%Y%m%d-%H%M%S)-XXXXXX")" || die "Création impossible dans $DEST_RESOLU."
chmod 700 "$CIBLE"

for type in $TYPES_CLUSTER; do exporter "$CIBLE/${type}.yaml" get "$type" -o yaml; done
for ns in $NAMESPACES; do
    for type in $TYPES_NAMESPACES; do exporter "$CIBLE/${type}.${ns}.yaml" get "$type" -n "$ns" -o yaml; done
done

success "Export terminé : $CIBLE"
