#!/usr/bin/env bash
# list-containers.sh — inventaire des conteneurs Docker, en lecture seule.
# Nom, image, état, identifiant court, ports et réseaux. Ni start, ni stop, ni
# restart, ni rm, ni prune ; aucun privilège root n'est requis.
set -Eeuo pipefail

_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_dir/lib/common.sh" ] && [ "$_dir" != "/" ]; do _dir="$(dirname "$_dir")"; done
source "$_dir/lib/common.sh"

TOUS="non"
DELAI=5

show_help() {
    cat <<'AIDE'
Usage : list-containers.sh [--all] [--help]

Inventaire des conteneurs Docker, en lecture seule : nom, image, état,
identifiant court, ports publiés et réseaux. Sans option, seuls les conteneurs
EN COURS D'EXÉCUTION sont affichés. Ni start, ni stop, ni rm, ni prune ; aucun
privilège root n'est requis — un compte du groupe docker suffit.

Options :
      --all          ajouter les conteneurs arrêtés, dans une section distincte
  -h, --help         afficher cette aide

Colonnes, dimensionnées sur leur contenu — aucune valeur n'est tronquée :
  NOM, IMAGE, ÉTAT (« Up 3 hours », « Exited (0) 2 days ago »)
  IDENTIFIANT (douze premiers caractères), PORTS, RÉSEAUX

Codes de retour :
  0  inventaire produit, même sans aucun conteneur à afficher
  1  inventaire impossible : « docker » absente, démon qui ne répond pas, ou
     socket dont l'accès est refusé — trois causes, trois messages distincts
  2  option inconnue — seul cas de 2
AIDE
}

while [ "${1:-}" != "" ]; do
    case "$1" in
        --all)     TOUS="oui"; shift ;;
        -h|--help) show_help; exit 0 ;;
        *)         die "Option inconnue : $1" 2 ;;
    esac
done

require_cmd docker

# Trois causes, jamais confondues, toutes en 1 : la ligne de commande de
# l'appelant était juste, c'est la machine qui ne suit pas. Le message brut du
# client n'est pas recopié — il est long, en anglais, et parfois traduit.
diagnostiquer_echec() {
    if [ "$1" -eq 124 ]; then
        error "Le démon Docker ne répond pas : « docker ps » n'a rien rendu en ${DELAI}s."
    elif [[ "$2" == *"permission denied"* ]]; then
        error "Accès refusé à la socket du démon Docker."
        error "Le compte « $(id -un) » n'appartient probablement pas au groupe docker."
        error "L'y ajouter — sudo usermod -aG docker $(id -un) — puis rouvrir la session."
    elif [[ "$2" == *"Cannot connect to the Docker daemon"* || "$2" == *"Is the docker daemon running"* ]]; then
        error "Le démon Docker ne répond pas : le client est installé, mais la socket ne mène à aucun démon."
    else
        error "« docker ps » a échoué : l'inventaire n'a pas pu être lu."
    fi
    exit 1
}

GABARIT=$'{{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}\t{{.Networks}}\t{{.ID}}'
OPTIONS=(ps)
[ "$TOUS" = "oui" ] && OPTIONS+=(--all)
OPTIONS+=(--format "$GABARIT")

# Borne de temps quand « timeout » est là : un démon figé ne doit pas suspendre
# l'inventaire.
BORNE=()
command -v timeout >/dev/null 2>&1 && BORNE=(timeout "$DELAI")

# Un SEUL appel à « docker ps », quel que soit le mode : --all change le drapeau
# passé au client, pas le nombre d'appels. LC_ALL=C fige les messages sur
# lesquels on décide. L'affectation est en contexte de condition : nue, elle
# ferait parler deux fois le trap ERR du socle.
CODE_DOCKER=0
REPONSE="$(LC_ALL=C "${BORNE[@]}" docker "${OPTIONS[@]}" 2>&1)" || CODE_DOCKER=$?
[ "$CODE_DOCKER" -eq 0 ] || diagnostiquer_echec "$CODE_DOCKER" "$REPONSE"

# Deux tableaux de lignes brutes, un par catégorie : les champs ne sont découpés
# qu'à l'affichage, là où sept tableaux parallèles devaient rester d'accord.
ACTIFS=()
ARRETES=()
while IFS= read -r ligne; do
    [ -n "$ligne" ] || continue
    IFS=$'\t' read -r _ _ statut _ <<< "$ligne"
    case "$statut" in
        Up*|Restarting*) ACTIFS+=("$ligne") ;;
        # Seconde barrière : sans --all, le client ne rend déjà que ce qui tourne.
        *) if [ "$TOUS" = "oui" ]; then ARRETES+=("$ligne"); fi ;;
    esac
done <<< "$REPONSE"

C=()
# Découpe une ligne en six champs, tabulations VIDES comprises : « IFS=$'\t'
# read » fondrait deux tabulations voisines, et un conteneur sans port publié
# — cas courant — décalerait d'un cran tout ce qui suit.
champs() {
    C=()
    local champ
    while IFS= read -r -d $'\t' champ; do C+=("$champ"); done < <(printf '%s\t' "$1")
    [ "${#C[@]}" -eq 6 ]
}

# Largeurs relevées sur le contenu. Les en-têtes sont sans accent : leur largeur
# se compte en octets dès que la locale n'est pas multibyte.
L_NOM=3; L_IMAGE=5; L_ETAT=4; L_PORTS=5; L_ID=12
largeurs() {
    local ligne
    for ligne in "$@"; do
        champs "$ligne" || continue
        [ "${#C[0]}" -gt "$L_NOM" ]   && L_NOM="${#C[0]}"
        [ "${#C[1]}" -gt "$L_IMAGE" ] && L_IMAGE="${#C[1]}"
        [ "${#C[2]}" -gt "$L_ETAT" ]  && L_ETAT="${#C[2]}"
        [ "${#C[3]}" -gt "$L_PORTS" ] && L_PORTS="${#C[3]}"
    done
    # Sans ce retour, le dernier test du dernier tour — souvent faux — ferait
    # sortir la fonction en 1, et set -e emporterait le script.
    return 0
}
largeurs "${ACTIFS[@]}" "${ARRETES[@]}"

cellule() {
    local texte="$1" remplissage
    remplissage=$(( $2 - ${#texte} + 1 ))
    [ "$remplissage" -gt 0 ] || remplissage=1
    printf '%s%*s' "$texte" "$remplissage" ""
}

# Une seule fonction pour l'en-tête et pour les lignes ; l'identifiant y est
# ramené à douze caractères, et ports et réseaux restent les dernières colonnes.
rangee() {
    printf '  %s%s%s%s%s%s\n' \
        "$(cellule "$1" "$L_NOM")" "$(cellule "$2" "$L_IMAGE")" \
        "$(cellule "$3" "$L_ETAT")" "$(cellule "${4:0:12}" "$L_ID")" \
        "$(cellule "$5" "$L_PORTS")" "$6"
}

afficher() {
    local titre="$1" ligne
    shift
    printf '\n%s — %d\n%s\n' "$titre" "$#" "------------------------------------------------------------"
    if [ "$#" -eq 0 ]; then printf '  Aucun.\n'; return 0; fi
    rangee NOM IMAGE ÉTAT IDENTIFIANT PORTS RÉSEAUX
    for ligne in "$@"; do
        champs "$ligne" || continue
        # Le gabarit suit l'ordre de Docker, où l'identifiant ferme la ligne ;
        # le tableau, lui, le place avant les deux colonnes de longueur libre.
        rangee "${C[0]}" "${C[1]}" "${C[2]}" "${C[5]}" "${C[3]}" "${C[4]}"
    done
}

info "Inventaire des conteneurs Docker — lecture seule."

# Le cas vide rend 0 : une machine sans conteneur n'est pas en panne.
if [ "${#ACTIFS[@]}" -eq 0 ] && [ "${#ARRETES[@]}" -eq 0 ]; then
    AVIS="aucun n'est en cours d'exécution (--all montre aussi les arrêtés)"
    [ "$TOUS" = "oui" ] && AVIS="cette machine n'en compte aucun, ni actif ni arrêté"
    printf 'Aucun conteneur à afficher : %s.\n' "$AVIS"
else
    afficher "Conteneurs en cours d'exécution" "${ACTIFS[@]}"
    if [ "$TOUS" = "oui" ]; then afficher "Conteneurs arrêtés" "${ARRETES[@]}"; fi
fi
