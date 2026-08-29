#!/usr/bin/env bash
# tests/env/run-in-container.sh — exécute une commande dans un conteneur neuf.
#
# L'hôte est une machine Windows : ni apt, ni systemctl, ni /etc/os-release. Un
# script d'administration ne s'y exécute pas, et une lecture de code ne vaut pas
# une exécution. Toute validation comportementale passe donc par ici.
#
#   tests/env/run-in-container.sh -- bash -c 'cat /etc/os-release'
#   tests/env/run-in-container.sh -- Linux/System/system-info.sh
#   tests/env/run-in-container.sh --profil debian -- tests/run.sh unit
#
# Tout ce qui suit « -- » est exécuté tel quel dans le conteneur, depuis la
# racine du dépôt montée sur /depot. Le code de retour de la commande est
# transmis fidèlement à l'appelant.
#
# Le conteneur est détruit à la fin de chaque exécution : deux appels
# consécutifs partent d'un état strictement identique, ce sans quoi un test
# d'idempotence ne prouverait rien.
#
# Aucune confirmation n'est demandée : rien n'est détruit sur l'hôte. Le
# conteneur est jetable par construction et l'image est reconstruite en place.
# Si le démon Docker ne répond pas, le script s'arrête avec un code non nul —
# jamais un faux succès.

set -Eeuo pipefail

_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_dir/lib/common.sh" ] && [ "$_dir" != "/" ]; do _dir="$(dirname "$_dir")"; done
source "$_dir/lib/common.sh"

PROFIL="debian"
DRY_RUN="false"
RECONSTRUIRE="false"
COMMANDE=()

REPERTOIRE_ENV="$SCRIPTS_ROOT/tests/env"

# Point de montage du dépôt dans le conteneur, et répertoire de travail des
# commandes exécutées : les chemins relatifs des exemples ci-dessus en dépendent.
MONTAGE="/depot"

# Préfixe imposé par AGENTS.md §8 : les commandes Docker de l'agent ne portent
# que sur les images et conteneurs préfixés « mgnet-test- ». Tout ce que ce
# script crée doit donc l'être, sans exception.
PREFIXE="mgnet-test-"

# -------------------------------------------------------------------
# Aide
# -------------------------------------------------------------------
show_help() {
    cat <<'AIDE'
Usage : tests/env/run-in-container.sh [options] -- <commande> [arguments...]

Exécute une commande dans un conteneur Debian neuf, avec la racine du dépôt
montée en lecture-écriture sur /depot. Le conteneur est détruit ensuite : rien
ne survit d'une exécution à l'autre.

Tout ce qui suit « -- » est passé tel quel au conteneur. Son code de retour est
transmis fidèlement à l'appelant.

Options :
      --profil <nom>  Profil de conteneur (défaut : debian). Un profil <nom>
                      correspond au fichier tests/env/Dockerfile.<nom>.
      --reconstruire  Reconstruire l'image sans cache, en retéléchargeant
                      l'image de base. Sinon, l'image n'est construite que si
                      elle est absente.
      --dry-run       Afficher les commandes docker sans les exécuter.
  -h, --help          Afficher cette aide

Exemples :
  tests/env/run-in-container.sh -- bash -c 'cat /etc/os-release'
  tests/env/run-in-container.sh -- Linux/System/system-info.sh
  tests/env/run-in-container.sh --profil debian -- tests/run.sh unit
  tests/env/run-in-container.sh -- Linux/System/configure-swap.sh 512M --dry-run

Codes de retour :
  0       la commande exécutée dans le conteneur a réussi
  2       erreur d'usage — option inconnue, profil inexistant, commande absente
  3       environnement indisponible — docker absent ou démon arrêté ;
          rien n'a été exécuté
  4       échec de la construction de l'image ; rien n'a été exécuté
  autre   code de retour de la commande, transmis tel quel

Les codes 2, 3 et 4 peuvent aussi provenir de la commande elle-même : la
transmission fidèle du code de retour l'impose. Les messages [ERROR] du script
lèvent l'ambiguïté.
AIDE
}

# -------------------------------------------------------------------
# Arguments
# -------------------------------------------------------------------
while [ "${1:-}" != "" ]; do
    case "$1" in
        --profil)
            shift
            [ -n "${1:-}" ] || die "--profil attend un nom de profil." 2
            PROFIL="$1"; shift
            ;;
        --reconstruire) RECONSTRUIRE="true"; shift ;;
        --dry-run)      DRY_RUN="true"; shift ;;
        -h|--help)      show_help; exit 0 ;;
        --)
            shift
            COMMANDE=("$@")
            break
            ;;
        *) die "Option inconnue : $1 (la commande doit suivre « -- »)" 2 ;;
    esac
done

if [ "${#COMMANDE[@]}" -eq 0 ]; then
    error "Aucune commande à exécuter."
    error "Usage : tests/env/run-in-container.sh [options] -- <commande> [arguments...]"
    die "Rien n'a été exécuté." 2
fi

IMAGE="${PREFIXE}${PROFIL}:latest"
DOCKERFILE="$REPERTOIRE_ENV/Dockerfile.$PROFIL"

# Un nom unique par exécution : deux appels simultanés ne se marchent pas dessus,
# et un conteneur résiduel se rattache sans ambiguïté à l'appel qui l'a créé.
CONTENEUR="${PREFIXE}${PROFIL}-$$-$(date '+%Y%m%d%H%M%S')"

# -------------------------------------------------------------------
# Chemins et Git Bash
# -------------------------------------------------------------------
# Sous MSYS (Git Bash), tout argument qui ressemble à un chemin POSIX est
# réécrit avant d'atteindre docker.exe : « /depot » deviendrait
# « C:/Program Files/Git/depot ». Ces deux variables désactivent la réécriture ;
# elles sont sans effet sur un hôte Linux.
export MSYS_NO_PATHCONV=1
export MSYS2_ARG_CONV_EXCL='*'

# La réécriture étant désactivée, les chemins de l'hôte doivent être donnés à
# docker dans leur forme native : D:\Projet\script et non /d/Projet/script.
chemin_pour_docker() {
    if command -v cygpath >/dev/null 2>&1; then
        cygpath -w "$1"
    else
        printf '%s\n' "$1"
    fi
}

profils_disponibles() {
    local fichier liste=""
    for fichier in "$REPERTOIRE_ENV"/Dockerfile.*; do
        [ -f "$fichier" ] || continue
        liste="$liste ${fichier##*/Dockerfile.}"
    done
    printf '%s\n' "${liste# }"
}

# -------------------------------------------------------------------
# Préflight
# -------------------------------------------------------------------
if [ ! -f "$DOCKERFILE" ]; then
    error "Profil inconnu : $PROFIL (fichier attendu : tests/env/Dockerfile.$PROFIL)"
    die "Profils disponibles : $(profils_disponibles)" 2
fi

if ! command -v docker >/dev/null 2>&1; then
    error "La commande docker est introuvable sur cette machine."
    die "Environnement de test indisponible — rien n'a été exécuté." 3
fi

# « docker info » est le seul contrôle qui atteste que le démon répond : la
# présence du client ne prouve rien. Sans lui, un démon arrêté produirait une
# erreur tardive et confuse au moment du run.
# Le test porte aussi sur le contenu : selon les versions, le client sort en 0
# avec une version serveur vide quand le démon est arrêté.
version_serveur=""
if ! version_serveur="$(docker info --format '{{.ServerVersion}}' 2>/dev/null)" \
   || [ -z "$version_serveur" ]; then
    error "Le démon Docker ne répond pas."
    docker info 2>&1 | head -n 5 >&2 || true
    error "Démarrer Docker Desktop, attendre qu'il soit prêt, puis relancer."
    die "Environnement de test indisponible — rien n'a été exécuté." 3
fi
info "Démon Docker : version serveur $version_serveur"

# Les fins de ligne CRLF rendraient tout script inexécutable dans le conteneur
# (« bad interpreter »). Le dépôt impose LF par .gitattributes ; on vérifie que
# la copie de travail le respecte réellement, plutôt que de le supposer.
if LC_ALL=C grep -q $'\r' "$SCRIPTS_ROOT/lib/common.sh" 2>/dev/null; then
    warn "lib/common.sh contient des retours chariot (CRLF) dans la copie de travail."
    warn "Les scripts échoueront dans le conteneur. Correctif : git add --renormalize ."
fi

# -------------------------------------------------------------------
# Image
# -------------------------------------------------------------------
CHEMIN_DOCKERFILE="$(chemin_pour_docker "$DOCKERFILE")"
CHEMIN_CONTEXTE="$(chemin_pour_docker "$REPERTOIRE_ENV")"
CHEMIN_DEPOT="$(chemin_pour_docker "$SCRIPTS_ROOT")"

image_presente() {
    docker image inspect "$IMAGE" >/dev/null 2>&1
}

construire_image() {
    local options=()
    if [ "$RECONSTRUIRE" = "true" ]; then
        # --pull : repartir de la dernière debian:12 publiée.
        # --no-cache : ignorer les couches déjà construites.
        options+=(--pull --no-cache)
    fi

    if [ "$DRY_RUN" = "true" ]; then
        info "[dry-run] docker build ${options[*]:-} -f $CHEMIN_DOCKERFILE -t $IMAGE $CHEMIN_CONTEXTE"
        return 0
    fi

    info "Construction de l'image $IMAGE (première construction : téléchargement de debian:12)…"
    if ! run_logged docker build "${options[@]}" \
            -f "$CHEMIN_DOCKERFILE" -t "$IMAGE" "$CHEMIN_CONTEXTE"; then
        die "Échec de la construction de l'image $IMAGE — rien n'a été exécuté." 4
    fi
    success "Image prête : $IMAGE"
}

if [ "$RECONSTRUIRE" = "true" ]; then
    construire_image
elif image_presente; then
    info "Image déjà présente : $IMAGE (--reconstruire pour la refaire)"
else
    construire_image
fi

# -------------------------------------------------------------------
# Résumé
# -------------------------------------------------------------------
info "Profil     : $PROFIL"
info "Image      : $IMAGE"
info "Conteneur  : $CONTENEUR (détruit en fin d'exécution)"
info "Dépôt      : $CHEMIN_DEPOT -> $MONTAGE (lecture-écriture)"
info "Commande   : ${COMMANDE[*]}"

if [ "$DRY_RUN" = "true" ]; then
    info "[dry-run] docker run --rm --name $CONTENEUR -v $CHEMIN_DEPOT:$MONTAGE -w $MONTAGE $IMAGE ${COMMANDE[*]}"
    success "[dry-run] Aucune exécution — rien n'a été lancé."
    exit 0
fi

# -------------------------------------------------------------------
# Exécution
# -------------------------------------------------------------------
# --rm détruit le conteneur en sortie normale. Le filet ci-dessous couvre les
# cas où il ne suffit pas : interruption au clavier, échec du démon en cours de
# route. Aucun état ne doit survivre à l'exécution.
# La fonction n'est pas morte : elle est appelée par le « trap … EXIT » posé
# juste en dessous. shellcheck ne suit pas les trap et la croit inatteignable.
# D'où SC2317 désactivé.
# shellcheck disable=SC2317
nettoyer_conteneur() {
    local code="$?"
    if docker ps -a --filter "name=^${CONTENEUR}$" --format '{{.Names}}' 2>/dev/null | grep -q .; then
        warn "Conteneur résiduel $CONTENEUR : suppression."
        docker rm -f "$CONTENEUR" >/dev/null 2>&1 || true
    fi
    return "$code"
}
trap nettoyer_conteneur EXIT

# La sortie de la commande n'est délibérément ni capturée ni redirigée : stdout
# et stderr du conteneur sont ceux de l'appelant. « run_logged » enverrait tout
# sur stderr et fausserait un « cat » ou un « tests/run.sh » lu par un tiers.
code_retour=0
docker run --rm \
    --name "$CONTENEUR" \
    -v "$CHEMIN_DEPOT:$MONTAGE" \
    -w "$MONTAGE" \
    "$IMAGE" \
    "${COMMANDE[@]}" || code_retour="$?"

# -------------------------------------------------------------------
# Vérification
# -------------------------------------------------------------------
if [ "$code_retour" -eq 0 ]; then
    success "Commande terminée dans $PROFIL — code de retour 0."
else
    error "Commande terminée dans $PROFIL — code de retour $code_retour."
fi

exit "$code_retour"
