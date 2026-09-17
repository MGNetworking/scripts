#!/usr/bin/env bash
set -Eeuo pipefail

# Ramène le cluster à une seule StorageClass par défaut : la cible. Seules les
# annotations par défaut sont touchées ; aucune classe n'est créée ni supprimée.
_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_dir/lib/common.sh" ] && [ "$_dir" != "/" ]; do _dir="$(dirname "$_dir")"; done
source "$_dir/lib/common.sh"

DELAI=10        # --request-timeout de chaque appel kubectl, en secondes
MARGE=2         # « timeout » qui l'entoure : le laisser écrire son message
CLE="storageclass.kubernetes.io/is-default-class"        # clé GA, posée sur la cible
CLE_B="storageclass.beta.kubernetes.io/is-default-class" # clé bêta, encore lue par l'admission
# Les points d'une clé sont échappés : sans eux, kubectl les lit comme un chemin
# d'objet. Les deux clés sont relevées, et non la seule GA. Le séparateur est un
# « | », jamais un espace : une annotation absente ne s'imprime pas, et une
# colonne vide décalerait les suivantes — la clé bêta se lirait en clé GA. Un
# nom de StorageClass étant un sous-domaine RFC 1123, il n'en porte aucun.
JP='{range .items[*]}{.metadata.name}{"|"}{.metadata.annotations.storageclass\.kubernetes\.io/is-default-class}{"|"}{.metadata.annotations.storageclass\.beta\.kubernetes\.io/is-default-class}{"\n"}{end}'
DRY_RUN="false"
# Décision 45 : un parent qui exporte ASSUME_YES ne confirme pas à ma place.
# OUI est le seul témoin lu par ce script ; ASSUME_YES n'est lu que par confirm.
OUI="false"; export ASSUME_YES="false"
# Surcharge de test, lue avant tout trap et toute écriture de fichier.
if [ -e /.dockerenv ] && [ -n "${DELAI_TEST:-}" ]; then DELAI="$DELAI_TEST"; fi

usage() {
    cat <<'EOF'
configure-storage.sh — ramène le cluster à une seule StorageClass par défaut.

Usage : configure-storage.sh [--dry-run] [-y|--yes] [--help]

  --dry-run    affiche les annotations qui changeraient, sans rien annoter
  -y, --yes    ne pose aucune question (obligatoire hors terminal)

La classe cible est SRV_K8S_STORAGE_CLASS (config/server.env), local-path à
défaut ; elle doit exister dans le cluster, le script n'en crée aucune. Elle est
marquée AVANT que les autres soient démarquées : jamais zéro classe par défaut.
Les autres voient leur annotation ramenée à « false » — jamais supprimée — et
rien n'est créé, supprimé ni réappliqué.

Une classe est par défaut si l'une des deux clés vaut « true » : la clé GA
storageclass.kubernetes.io/is-default-class, celle que reçoit la cible, ou la
clé bêta storageclass.beta.kubernetes.io/is-default-class, que le script ramène
aussi à « false » là où elle marque une autre classe.

K3s réapplique ses manifestes intégrés au démarrage, dont local-path et sa
marque : ce que ce script retire peut revenir. Il n'y remédie pas ; sa
vérification finale signale l'écart si l'état a dérivé. kubectl résout seul son
kubeconfig (KUBECONFIG, sinon ~/.kube/config).

Codes de retour :
  0  la cible est la seule classe par défaut, ou l'était déjà ; ou --dry-run
  1  kubectl absent, apiserver injoignable, droits insuffisants, kubeconfig
     invalide, délai dépassé, cible absente, confirmation refusée, annotation
     ou relecture en échec
  2  option inconnue, ou nom de classe mal formé
EOF
}

while [ "${1:-}" != "" ]; do
    case "$1" in
        --dry-run) DRY_RUN="true"; shift ;;
        -y|--yes)  OUI="true"; export ASSUME_YES="true"; shift ;;
        --help|-h) usage; exit 0 ;;
        *) die "Option inconnue : $1" 2 ;;
    esac
done

# RFC 1123, jugé avant tout appel : sinon kubectl lirait le nom comme une option.
CIBLE="${SRV_K8S_STORAGE_CLASS:-local-path}"
case "$CIBLE" in
    ""|*[!a-z0-9.-]*) die "Nom de StorageClass mal formé : « $CIBLE » — minuscules, chiffres, « - » et « . » attendus." 2 ;;
    [!a-z0-9]*|*[!a-z0-9]|*..*|*.-*|*-.*) die "Nom de StorageClass mal formé : « $CIBLE » — un sous-domaine RFC 1123 commence et finit par un caractère alphanumérique, et « . » ou « - » ne s'y suivent jamais." 2 ;;
esac
[ "${#CIBLE}" -le 253 ] || die "Nom de StorageClass trop long : « $CIBLE » — 253 caractères au plus." 2

command -v kubectl >/dev/null 2>&1 || die "kubectl est introuvable dans le PATH : voir Kubernetes/Installation/install-kubectl.sh (TASK-062)."
require_cmd timeout
TEMPORAIRE="$(mktemp -d)" || die "Répertoire temporaire indisponible."
trap 'rm -rf "$TEMPORAIRE"' EXIT

# REP — stdout — et ERREUR — stderr, tenu à part : un avertissement mêlé à une
# lecture serait pris pour une donnée.
REP=""; ERREUR=""; CODE=0
appel() {   # <verbe kubectl...>
    CODE=0
    REP="$(timeout "$((DELAI + MARGE))" kubectl "$@" --request-timeout="${DELAI}s" 2>"$TEMPORAIRE/erreur")" || CODE=$?
    ERREUR="$(cat "$TEMPORAIRE/erreur")"
}

# Cause du dernier échec, sans sortir : echec() et la boucle d'annotation la
# partagent. Le 124 vient de « timeout », pas du cluster.
cause() {
    case "$CODE:$ERREUR" in
        124:*) printf 'délai dépassé (%s s), appel interrompu par timeout' "$DELAI" ;;
        *Forbidden*) printf 'Droits insuffisants (Forbidden), refus du cluster' ;;
        *Unauthorized*|*x509*|*"error loading config file"*) printf 'Kubeconfig invalide ou périmé' ;;
        *NotFound*) printf 'Ressource absente du cluster (NotFound)' ;;
        *"connection refused"*|*"was refused"*|*"Unable to connect"*|*"no such host"*|*"i/o timeout"*) printf "L'apiserver est injoignable — vérifier l'accès par install-kubectl.sh (TASK-062)" ;;
        *) printf 'le cluster a répondu, et a refusé : la cause est dans le message ci-dessus' ;;
    esac
}

echec() {   # <appel> : n'est appelée que pour une lecture, et sort en 1
    [ -z "$ERREUR" ] || printf '%s\n' "$ERREUR" | sed 's/^/  /' >&2
    die "$1 : $(cause)."
}

# Un seul relevé sert au compte, à la présence de la cible et aux marques posées.
relever() {
    appel get storageclass -o "jsonpath=$JP"
    [ "$CODE" = 0 ] || echec "« kubectl get storageclass »"
    printf '%s\n' "$REP" | grep . > "$TEMPORAIRE/etat" || true
    TOTAL="$(grep -c . "$TEMPORAIRE/etat" || true)"
    awk -F'|' '{print $1}' "$TEMPORAIRE/etat" > "$TEMPORAIRE/noms"
    awk -F'|' '$2 == "true" || $3 == "true" {print $1}' "$TEMPORAIRE/etat" > "$TEMPORAIRE/defaut"
}

relever
AVANT="$TOTAL"
grep -qxF "$CIBLE" "$TEMPORAIRE/noms" || die "La classe cible « $CIBLE » est absente du cluster ($TOTAL classe(s) : $(tr '\n' ' ' < "$TEMPORAIRE/noms")). Rien n'a été modifié, et ce script n'en crée aucune : la renseigner dans SRV_K8S_STORAGE_CLASS, ou l'installer d'abord." 1

if [ "$(grep -c . "$TEMPORAIRE/defaut" || true)" = 1 ] && grep -qxF "$CIBLE" "$TEMPORAIRE/defaut"; then
    success "« $CIBLE » est déjà la seule StorageClass par défaut : aucun changement."
    exit 0
fi

# Plan d'annotations, cible en tête : jamais zéro classe par défaut, même si un
# démarquage échoue. Une autre classe est démarquée clé par clé, à « false »,
# jamais par suppression de l'annotation.
PLAN=()
grep -qxF "$CIBLE" "$TEMPORAIRE/defaut" || PLAN+=("$CIBLE|$CLE|true")
while IFS='|' read -r n ga beta; do
    [ "$n" != "$CIBLE" ] || continue
    if [ "$ga" = "true" ]; then PLAN+=("$n|$CLE|false"); fi
    if [ "$beta" = "true" ]; then PLAN+=("$n|$CLE_B|false"); fi
done < "$TEMPORAIRE/etat"
VOULEES="${#PLAN[@]}"
printf '\nAnnotations à changer (%s) :\n' "$VOULEES"
for a in "${PLAN[@]}"; do IFS='|' read -r n cle v <<<"$a"; printf '  %s  %s=%s\n' "$n" "$cle" "$v"; done
[ "$VOULEES" -le 1 ] || info "« $CIBLE » est annotée en premier : le cluster ne passe jamais par zéro classe par défaut."

if [ "$DRY_RUN" = "true" ]; then
    info "[dry-run] kubectl annotate n'a pas été appelé : rien n'a été modifié."
    exit 0
fi
[ -t 0 ] || [ "$OUI" = "true" ] || die "Annotations à confirmer, et aucun terminal n'est disponible. Relancer avec --yes." 1
confirm "Appliquer ces $VOULEES annotation(s) ? « $CIBLE » restera la seule StorageClass par défaut." || die "Configuration abandonnée : rien n'a été modifié." 1

FAITES=0
for a in "${PLAN[@]}"; do
    IFS='|' read -r n cle v <<<"$a"
    appel annotate storageclass "$n" "$cle=$v" --overwrite
    if [ "$CODE" != 0 ]; then
        printf '%s\n' "$ERREUR" | sed 's/^/  /' >&2
        error "Annotation de « $n » ($cle=$v) non appliquée : $(cause)."
        error "Bilan : $FAITES annotation(s) appliquée(s), $((VOULEES - FAITES)) non appliquée(s). Restaient : ${PLAN[*]:FAITES}. « $CIBLE » n'est peut-être pas la seule classe par défaut."
        exit 1
    fi
    printf '%s\n' "$REP" | sed 's/^/  /'
    FAITES=$((FAITES + 1))
done

relever
[ "$TOTAL" = "$AVANT" ] || die "Relecture : $TOTAL StorageClass dans le cluster, $AVANT avant les annotations — le nombre a changé, or ce script n'en crée ni n'en supprime aucune." 1
if [ "$(grep -c . "$TEMPORAIRE/defaut" || true)" != 1 ] || ! grep -qxF "$CIBLE" "$TEMPORAIRE/defaut"; then
    die "Relecture : $(grep -c . "$TEMPORAIRE/defaut" || true) classe(s) par défaut ($(tr '\n' ' ' < "$TEMPORAIRE/defaut")) — « $CIBLE » seule était attendue. Si une classe a repris sa marque, K3s a pu réappliquer ses manifestes au redémarrage : relancer ce script." 1
fi
success "« $CIBLE » est la seule StorageClass par défaut ($FAITES annotation(s) changée(s), $TOTAL classe(s) au total). Aucune classe n'a été créée ni supprimée."
