#!/usr/bin/env bash
set -Eeuo pipefail

# Dépose un Secret docker-registry dans chaque namespace de SRV_K8S_NAMESPACES,
# à partir des identifiants de config/registry.env. Ceux-ci ne passent jamais en
# argument d'une commande, ne sont ni affichés ni journalisés.
_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_dir/lib/common.sh" ] && [ "$_dir" != "/" ]; do _dir="$(dirname "$_dir")"; done
source "$_dir/lib/common.sh"

CONFIG="registry"
SECRET="registry-credentials"
ANNOTATION="mgnetworking/empreinte"   # empreinte du JSON : comparer sans relire le Secret
DELAI=10        # --request-timeout de chaque appel kubectl, en secondes
MARGE=2         # « timeout » qui l'entoure : le laisser écrire son message
DRY_RUN="false"
# Décision 45 : un parent qui exporte ASSUME_YES ne confirme pas à ma place.
OUI="false"; export ASSUME_YES="false"
# Le journal et le brouillon d'erreur ne sont lisibles que par l'utilisateur.
umask 077
# Surcharge de test, lue avant tout trap et toute écriture de fichier.
if [ -e /.dockerenv ] && [ -n "${DELAI_TEST:-}" ]; then DELAI="$DELAI_TEST"; fi

usage() {
    cat <<'EOF'
configure-registry.sh — dépose un Secret docker-registry dans chaque namespace.

Usage : configure-registry.sh [--config <nom>] [--dry-run] [-y|--yes] [--help]

  --config <nom>  contexte chargé depuis config/<nom>.env — défaut : registry
  --dry-run       nomme les Secrets à créer ou à mettre à jour, sans appliquer
  -y, --yes       ne pose aucune question (obligatoire hors terminal)

Les identifiants viennent de config/registry.env, non versionné, copié de
registry.env.example : droits 600 et propriétaire courant exigés, sans quoi le
script refuse en 1 avant de le lire. REGISTRY_SERVEUR porte l'hôte ou hôte:port,
sans schéma ; REGISTRY_IDENTIFIANT et REGISTRY_JETON le compte et son jeton.

Le Secret, nommé registry-credentials, est de type
kubernetes.io/dockerconfigjson et porte une annotation d'empreinte qui dit,
sans le relire, s'il est déjà à jour. Guillemets et barres obliques inverses
sont échappés pour le JSON ; les caractères de contrôle sont refusés en 2. Un
Pod l'utilise ensuite par imagePullSecrets — jamais posé ici. kubectl résout
seul son kubeconfig (KUBECONFIG, sinon ~/.kube/config).

Codes de retour :
  0  chaque namespace de la liste porte le Secret à jour ; ou --dry-run
  1  configuration absente ou de droits trop larges, namespace de la liste
     absent du cluster, kubectl absent, apiserver injoignable, kubeconfig
     invalide, droits insuffisants, délai dépassé, confirmation refusée,
     application en échec
  2  option inconnue ; REGISTRY_SERVEUR, REGISTRY_IDENTIFIANT ou REGISTRY_JETON
     absent ou mal formé ; SRV_K8S_NAMESPACES absente ou mal formée
EOF
}

while [ "${1:-}" != "" ]; do
    case "$1" in
        --config)  shift; [ -n "${1:-}" ] || die "--config attend un nom de contexte." 2
                   CONFIG="$1"; shift ;;
        --dry-run) DRY_RUN="true"; shift ;;
        -y|--yes)  OUI="true"; export ASSUME_YES="true"; shift ;;
        --help|-h) usage; exit 0 ;;
        *) die "Option inconnue : $1" 2 ;;
    esac
done

# Droits et propriétaire lus par stat AVANT load_config : le fichier porte le
# jeton, et le charger d'abord l'aurait mis en mémoire et exporté pour rien.
FICHIER="config/$CONFIG.env"
[ -f "$SCRIPTS_ROOT/$FICHIER" ] || die "$FICHIER introuvable (modèle : $FICHIER.example) : le copier, le renseigner, puis « chmod 600 »." 1
DROITS="$(stat -c %a "$SCRIPTS_ROOT/$FICHIER")"
[ "$DROITS" = 600 ] || die "$FICHIER : droits $DROITS, 600 attendus — le jeton qu'il porte serait lisible par d'autres. Rien n'a été tenté." 1
PROPRIETAIRE="$(stat -c %u "$SCRIPTS_ROOT/$FICHIER")"
[ "$PROPRIETAIRE" = "$(id -u)" ] || die "$FICHIER : propriétaire $PROPRIETAIRE, alors que le script tourne sous l'utilisateur $(id -u). Rien n'a été tenté." 1
load_config "$CONFIG"

SERVEUR="${REGISTRY_SERVEUR:-}"; IDENTIFIANT="${REGISTRY_IDENTIFIANT:-}"; JETON="${REGISTRY_JETON:-}"
# Le fichier est chargé exporté (décision 7) : les valeurs quittent
# l'environnement des processus fils dès qu'elles sont lues.
unset REGISTRY_SERVEUR REGISTRY_IDENTIFIANT REGISTRY_JETON
[ -n "$SERVEUR" ] || die "REGISTRY_SERVEUR absent : renseigner l'adresse du registry dans $FICHIER (modèle : $FICHIER.example). Rien n'a été tenté." 2
[ -n "$IDENTIFIANT" ] || die "REGISTRY_IDENTIFIANT absent : renseigner le compte du registry dans $FICHIER. Rien n'a été tenté." 2
[ -n "$JETON" ] || die "REGISTRY_JETON absent : renseigner le jeton du registry dans $FICHIER. Rien n'a été tenté." 2
case "$SERVEUR" in
    *[!A-Za-z0-9.:_-]*) die "REGISTRY_SERVEUR mal formé : nom d'hôte ou hôte:port attendu, sans schéma, sans barre oblique ni espace. Rien n'a été tenté." 2 ;;
esac
case "$IDENTIFIANT" in *[[:cntrl:]]*) die "REGISTRY_IDENTIFIANT porte un caractère de contrôle : refusé, il rendrait le JSON invalide. Rien n'a été tenté." 2 ;; esac
case "$JETON" in *[[:cntrl:]]*) die "REGISTRY_JETON porte un caractère de contrôle : refusé, il rendrait le JSON invalide. Rien n'a été tenté." 2 ;; esac

LISTE="${SRV_K8S_NAMESPACES:-}"
[ -n "$LISTE" ] || die "Liste des namespaces absente : renseigner SRV_K8S_NAMESPACES dans config/server.env. Rien n'a été tenté." 2
case "$LISTE" in
    ,*|*,|*,,*) die "Liste mal formée dans SRV_K8S_NAMESPACES : entrée vide (virgule en tête ou en trop). Rien n'a été tenté." 2 ;;
    *[[:space:]]*) die "Liste mal formée dans SRV_K8S_NAMESPACES : blanc ou retour à la ligne. Rien n'a été tenté." 2 ;;
esac
IFS=',' read -r -a NAMESPACES <<< "$LISTE"
for n in "${NAMESPACES[@]}"; do
    # RFC 1123, jugé avant tout appel : un nom douteux irait sinon jusqu'à
    # kubectl, qui le lirait comme une option.
    case "$n" in
        *[!a-z0-9-]*|[!a-z0-9]*|*[!a-z0-9]) die "Nom mal formé dans SRV_K8S_NAMESPACES : « $n » — minuscules, chiffres et « - » attendus, 63 caractères au plus. Rien n'a été tenté." 2 ;;
    esac
done

command -v kubectl >/dev/null 2>&1 || die "kubectl est introuvable dans le PATH : voir Kubernetes/Installation/install-kubectl.sh (TASK-062)."
require_cmd timeout base64 sha256sum stat
TEMPORAIRE="$(mktemp -d)" || die "Répertoire temporaire indisponible."
trap 'rm -rf "$TEMPORAIRE"' EXIT

# Le JSON du dockerconfigjson. Guillemets et barres obliques inverses sont
# échappés : une valeur qui en porte un reste valide. Les caractères de
# contrôle, eux, ont été refusés plus haut. L'empreinte du JSON sert à comparer
# sans jamais relire le Secret en clair, ni le décoder.
echapper() { local v="$1"; v="${v//\\/\\\\}"; printf '%s' "${v//\"/\\\"}"; }
AUTH="$(printf '%s:%s' "$IDENTIFIANT" "$JETON" | base64 -w0)"
JSON="$(printf '{"auths":{"%s":{"username":"%s","password":"%s","auth":"%s"}}}' \
    "$SERVEUR" "$(echapper "$IDENTIFIANT")" "$(echapper "$JETON")" "$AUTH")"
SOMME="$(printf '%s' "$JSON" | sha256sum)"; EMPREINTE="${SOMME%% *}"
DONNEES="$(printf '%s' "$JSON" | base64 -w0)"
unset JSON AUTH SOMME

manifeste() {   # <namespace> — sur la sortie standard, jamais sur disque
    cat <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: $SECRET
  namespace: $1
  annotations:
    $ANNOTATION: $EMPREINTE
type: kubernetes.io/dockerconfigjson
data:
  .dockerconfigjson: $DONNEES
EOF
}

# REP — stdout — et ERREUR — stderr, tenu à part : un avertissement mêlé à une
# lecture serait pris pour une donnée. L'entrée standard de l'appel est celle de
# l'appelant : « < <(manifeste "$n") » pour un apply, « < /dev/null » sinon.
REP=""; ERREUR=""; CODE=0
appel() {   # <verbe kubectl...>
    CODE=0
    REP="$(timeout "$((DELAI + MARGE))" kubectl "$@" --request-timeout="${DELAI}s" 2>"$TEMPORAIRE/erreur")" || CODE=$?
    ERREUR="$(cat "$TEMPORAIRE/erreur")"
}

# Cause du dernier échec, RÉSUMÉE : le message brut de kubectl apply n'est jamais
# recopié, il peut porter l'objet reçu, donc le jeton. Le 124 vient de timeout.
cause() {
    case "$CODE:$ERREUR" in
        124:*) printf 'délai dépassé (%s s), appel interrompu par timeout' "$DELAI" ;;
        *Forbidden*) printf 'Droits insuffisants : le cluster a refusé' ;;
        *Unauthorized*|*x509*|*"error loading config file"*) printf 'Kubeconfig invalide ou périmé' ;;
        *NotFound*) printf 'Ressource absente du cluster (NotFound)' ;;
        *"connection refused"*|*"was refused"*|*"Unable to connect"*|*"no such host"*|*"i/o timeout"*) printf "L'apiserver est injoignable — vérifier l'accès par install-kubectl.sh (TASK-062)" ;;
        *) printf 'le cluster a répondu, et a refusé' ;;
    esac
}

echec() {   # <appel> : n'est appelée que pour une lecture, et sort en 1
    [ -z "$ERREUR" ] || printf '%s\n' "$ERREUR" | sed 's/^/  /' >&2
    die "$1 : $(cause)."
}

# Préflight et relevé des namespaces en un seul appel : il prouve que l'API
# répond, et dit lesquels existent. Tous sont jugés avant le moindre apply.
appel get namespaces -o name < /dev/null
[ "$CODE" = 0 ] || echec "« kubectl get namespaces -o name »"
printf '%s\n' "$REP" | sed -n 's|^namespace/||p' > "$TEMPORAIRE/namespaces"
ABSENTS=""
for n in "${NAMESPACES[@]}"; do
    grep -qxF "$n" "$TEMPORAIRE/namespaces" || ABSENTS="$ABSENTS $n"
done
[ -z "$ABSENTS" ] || die "Namespace(s) absent(s) du cluster :$ABSENTS. Rien n'a été appliqué — les créer d'abord par Kubernetes/Configuration/configure-namespaces.sh (TASK-067)." 1

# État de chaque Secret : absent (NotFound), empreinte identique, ou périmée.
A_CREER=(); A_JOUR=(); A_MAJ=()
for n in "${NAMESPACES[@]}"; do
    appel get secret "$SECRET" -n "$n" -o "jsonpath={.metadata.annotations.$ANNOTATION}" < /dev/null
    if [ "$CODE" != 0 ]; then
        case "$ERREUR" in *NotFound*) A_CREER+=("$n"); continue ;; esac
        echec "« kubectl get secret $SECRET -n $n »"
    fi
    if [ "$REP" = "$EMPREINTE" ]; then A_JOUR+=("$n"); else A_MAJ+=("$n"); fi
done

if [ "${#A_CREER[@]}" -eq 0 ] && [ "${#A_MAJ[@]}" -eq 0 ]; then
    success "Le Secret $SECRET est déjà à jour dans les ${#NAMESPACES[@]} namespace(s) de SRV_K8S_NAMESPACES : aucun changement."
    exit 0
fi

if [ "$DRY_RUN" = "true" ]; then
    printf '\nSecret %s :\n' "$SECRET"
    [ "${#A_CREER[@]}" -eq 0 ] || printf '  à créer (%s) : %s\n' "${#A_CREER[@]}" "${A_CREER[*]}"
    [ "${#A_MAJ[@]}" -eq 0 ] || printf '  à mettre à jour (%s) : %s\n' "${#A_MAJ[@]}" "${A_MAJ[*]}"
    [ "${#A_JOUR[@]}" -eq 0 ] || printf '  déjà à jour (%s) : %s\n' "${#A_JOUR[@]}" "${A_JOUR[*]}"
    info "[dry-run] kubectl apply n'a pas été appelé : ni le contenu du Secret ni les identifiants ne sont affichés."
    exit 0
fi

A_FAIRE=$(( ${#A_CREER[@]} + ${#A_MAJ[@]} ))
[ -t 0 ] || [ "$OUI" = "true" ] || die "$A_FAIRE Secret(s) à appliquer, et aucun terminal n'est disponible. Relancer avec --yes. Rien n'a été appliqué." 1
confirm "Appliquer le Secret $SECRET dans $A_FAIRE namespace(s) ?" || die "Configuration abandonnée : rien n'a été appliqué." 1

FAITS=0; ECHEC=""
for n in "${A_CREER[@]}" "${A_MAJ[@]}"; do
    appel apply -f - < <(manifeste "$n")
    # Un refus arrête la boucle : les suivants ne sont pas tentés, et le bilan
    # ci-dessous le dit plutôt que de laisser croire à une liste complète.
    if [ "$CODE" != 0 ]; then ECHEC="$n"; break; fi
    printf '  %s\n' "$REP"
    FAITS=$((FAITS + 1))
done
if [ -n "$ECHEC" ]; then
    error "Secret $SECRET non appliqué dans « $ECHEC » : $(cause)."
    error "Secret $SECRET : $FAITS appliqué(s), 1 échoué ($ECHEC), $((A_FAIRE - FAITS - 1)) non tenté(s). Tous les namespaces ne le portent pas."
    exit 1
fi
success "Secret $SECRET appliqué dans $A_FAIRE namespace(s) : ${#A_CREER[@]} créé(s), ${#A_MAJ[@]} mis à jour. Rien n'a été supprimé."
