#!/usr/bin/env bash
# list-containers.sh — inventaire des conteneurs Docker, en lecture seule.
#
# Nom, image, état, identifiant court, ports publiés et réseaux. Les conteneurs
# en cours d'exécution par défaut ; --all ajoute les arrêtés, dans une section
# distincte.
#
# N'écrit rien, ne modifie rien et n'agit sur aucun conteneur : ni start, ni
# stop, ni restart, ni rm, ni prune. Aucun privilège root n'est requis — un
# compte membre du groupe docker suffit.
# Usage : ./list-containers.sh [--all] [--help]

set -Eeuo pipefail

_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_dir/lib/common.sh" ] && [ "$_dir" != "/" ]; do _dir="$(dirname "$_dir")"; done
source "$_dir/lib/common.sh"

TOUS="non"

# -------------------------------------------------------------------
# Aide
# -------------------------------------------------------------------
show_help() {
    cat <<'AIDE'
Usage : list-containers.sh [options]

Inventaire des conteneurs Docker, en lecture seule : nom, image, état,
identifiant court, ports publiés et réseaux de chacun.

Sans option, seuls les conteneurs EN COURS D'EXÉCUTION sont affichés.

Script en lecture seule : aucune modification, aucun privilège requis, aucune
action sur un conteneur. Ni start, ni stop, ni restart, ni rm, ni prune.

Options :
      --all          Ajouter les conteneurs arrêtés, dans une section distincte
  -h, --help         Afficher cette aide

Colonnes :
  NOM          nom du conteneur
  IMAGE        image dont il est issu, étiquette comprise
  ETAT         état annoncé par Docker — « Up 3 hours », « Exited (0) 2 days ago »
  IDENTIFIANT  douze premiers caractères de l'identifiant du conteneur
  PORTS        mappages de ports publiés, liste complète
  RESEAUX      réseaux auxquels le conteneur est rattaché

Chaque colonne est dimensionnée sur son contenu : aucune valeur n'est
tronquée. Les ports et les réseaux, seuls champs de longueur imprévisible,
sont les deux dernières colonnes.

Un conteneur est compté « en cours d'exécution » lorsque l'état annoncé
commence par « Up » ou par « Restarting ».

L'absence de conteneur n'est pas une panne : le script le dit en clair et
rend 0.

Codes de retour :
  0  inventaire produit, même lorsqu'il n'y a aucun conteneur à afficher
  1  inventaire impossible : commande « docker » absente, démon qui ne répond
     pas, ou socket dont l'accès est refusé à cet utilisateur
  2  erreur d'usage : option inconnue — seul cas de 2

Les trois causes du 1 se distinguent par le message, jamais par le code : la
ligne de commande de l'appelant était juste, c'est la machine qui ne suit
pas. Un refus d'accès à la socket vient de l'appartenance au groupe docker,
et le message le dit.
AIDE
}

# -------------------------------------------------------------------
# Arguments
# -------------------------------------------------------------------
# Avant tout préflight, et --help avant tout le reste : dans un conteneur sans
# Docker, l'aide est ce qu'on vient chercher. Une aide qui exigerait la
# commande serait illisible là où elle est le plus utile.
while [ "${1:-}" != "" ]; do
    case "$1" in
        --all)      TOUS="oui"; shift ;;
        -h|--help)  show_help; exit 0 ;;
        *)          die "Option inconnue : $1" 2 ;;
    esac
done

# -------------------------------------------------------------------
# Préflight
# -------------------------------------------------------------------
# Aucun privilège n'est exigé : Docker s'administre couramment par le groupe
# docker, et exiger root ferait échouer ce script sur les machines où il est le
# mieux configuré. Le refus d'accès à la socket est diagnostiqué plus bas, pas
# prévenu ici.
#
# require_cmd sort en 1 avec un message nommant la dépendance : la ligne de
# commande était juste, c'est la machine qui n'a pas ce qu'il faut. Rien n'est
# redéfini ici, le socle s'en charge.
require_cmd docker

# -------------------------------------------------------------------
# Diagnostic d'un échec de « docker ps »
# -------------------------------------------------------------------
# TROIS CAUSES, JAMAIS CONFONDUES, toutes en 1 : le client est absent (traité
# par require_cmd), le démon ne répond pas, ou la socket existe mais l'accès
# est refusé. Les deux dernières se ressemblent à l'usage et se réparent
# différemment ; le message de la troisième nomme le groupe docker, ce qui fait
# gagner un quart d'heure à qui découvre la machine.
#
# Le message brut du client n'est pas recopié : il est long, en anglais, et
# parfois traduit par le client lui-même. C'est le texte de Docker qui décide de
# la branche, pas ce qui est affiché.
diagnostiquer_echec() {
    local message="$1" premiere="${1%%$'\n'*}"

    case "$message" in
        *"permission denied"*)
            error "Accès refusé à la socket du démon Docker."
            error "Le compte « $(id -un) » n'appartient probablement pas au groupe docker."
            error "L'ajouter au groupe, puis rouvrir la session :"
            error "  sudo usermod -aG docker $(id -un)"
            exit 1
            ;;
        *"Cannot connect to the Docker daemon"*|*"Is the docker daemon running"*)
            error "Le démon Docker ne répond pas."
            error "Le client est installé, mais la socket ne mène à aucun démon."
            error "Vérifier le service : systemctl status docker"
            exit 1
            ;;
        *)
            error "« docker ps » a échoué : l'inventaire n'a pas pu être lu."
            if [ -n "$premiere" ]; then
                error "Message du client : $premiere"
            fi
            exit 1
            ;;
    esac
}

# -------------------------------------------------------------------
# Lecture de l'inventaire
# -------------------------------------------------------------------
# UN SEUL appel à « docker ps », pour les deux modes : --all change le drapeau
# passé au client, jamais le nombre d'appels. Deux appels — un pour les actifs,
# un pour les arrêtés — ouvriraient une fenêtre pendant laquelle un conteneur
# change d'état, et le tableau mélangerait deux instants.
#
# .Status et non .State : .Status est rendu par toutes les versions du client,
# tandis qu'un champ inconnu fait échouer le gabarit entier — donc l'inventaire
# — sur les machines anciennes. L'état affiché est celui que Docker annonce, et
# la catégorie se déduit de son préfixe : « Up 3 hours » comme « Restarting (1)
# 2 seconds ago » désignent un conteneur en cours d'exécution.
#
# LC_ALL=C n'est pas un ornement : les états sont écrits dans la locale du
# client, et le diagnostic ci-dessus cherche des mots anglais. La sortie doit
# être la même d'une machine à l'autre.
GABARIT=$'{{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}\t{{.Networks}}\t{{.ID}}'

OPTIONS=(ps)
if [ "$TOUS" = "oui" ]; then
    OPTIONS+=(--all)
fi
OPTIONS+=(--format "$GABARIT")

# La sortie d'erreur est fusionnée à la sortie standard : « docker ps » n'écrit
# rien sur sa sortie standard quand il échoue, et c'est ce message-là qui
# distingue les deux causes du démon.
#
# L'affectation est en CONTEXTE DE CONDITION. Sous sa forme nue, un « docker »
# en échec ferait parler deux fois le trap ERR du socle avant d'arrêter le
# script, sans que la cause soit nommée — le motif est celui de
# Linux/System/recensement-substitutions.md.
REPONSE=""
if ! REPONSE="$(LC_ALL=C docker "${OPTIONS[@]}" 2>&1)"; then
    diagnostiquer_echec "$REPONSE"
fi

# -------------------------------------------------------------------
# Analyse
# -------------------------------------------------------------------
# Tableaux parallèles, comme UNITES et LIGNES de check-services.sh : une entrée
# par conteneur affichable. Les largeurs de colonnes sont relevées au passage,
# en une seule lecture, et valent au minimum la longueur de leur en-tête.
NOMS=()
IMAGES=()
ETATS=()
IDS=()
PORTS=()
RESEAUX=()
CATEGORIES=()
COMPTE_ACTIF=0
COMPTE_ARRETE=0
LARGEUR_NOM=3
LARGEUR_IMAGE=5
LARGEUR_ETAT=4
LARGEUR_PORTS=5

analyser() {
    local sortie="$1"
    local ligne champ nom image statut ports reseaux identifiant categorie
    local -a champs

    NOMS=(); IMAGES=(); ETATS=(); IDS=(); PORTS=(); RESEAUX=(); CATEGORIES=()
    COMPTE_ACTIF=0
    COMPTE_ARRETE=0
    LARGEUR_NOM=3
    LARGEUR_IMAGE=5
    LARGEUR_ETAT=4
    LARGEUR_PORTS=5

    while IFS= read -r ligne; do
        [ -n "$ligne" ] || continue

        # Découpage sur les tabulations, CHAMPS VIDES COMPRIS. « IFS=$'\t' read »
        # ne convient pas ici : la tabulation est un blanc pour IFS, deux
        # tabulations voisines n'y comptent que pour un seul séparateur, et un
        # conteneur sans port publié — cas courant — décalerait d'un cran tout
        # ce qui suit. « read -d » n'a pas cette règle.
        champs=()
        while IFS= read -r -d $'\t' champ; do
            champs+=("$champ")
        done < <(printf '%s\t' "$ligne")

        # Six champs, pas un de moins : une ligne qui n'en porte pas six n'est
        # pas un conteneur — un avertissement du client, par exemple — et
        # l'afficher décalerait tout le tableau.
        [ "${#champs[@]}" -eq 6 ] || continue

        nom="${champs[0]}"
        image="${champs[1]}"
        statut="${champs[2]}"
        ports="${champs[3]}"
        reseaux="${champs[4]}"
        identifiant="${champs[5]}"

        categorie="arrete"
        case "$statut" in
            Up*|Restarting*) categorie="actif" ;;
        esac

        # Sans --all, « docker ps » ne rend déjà que ce qui tourne : ce filtre
        # est la seconde barrière, celle qui tient même si le client rend autre
        # chose que ce qu'on lui demande.
        if [ "$TOUS" != "oui" ] && [ "$categorie" != "actif" ]; then
            continue
        fi

        NOMS+=("$nom")
        IMAGES+=("$image")
        ETATS+=("$statut")
        PORTS+=("$ports")
        RESEAUX+=("$reseaux")
        IDS+=("${identifiant:0:12}")
        CATEGORIES+=("$categorie")

        if [ "$categorie" = "actif" ]; then
            COMPTE_ACTIF=$((COMPTE_ACTIF + 1))
        else
            COMPTE_ARRETE=$((COMPTE_ARRETE + 1))
        fi

        if [ "${#nom}" -gt "$LARGEUR_NOM" ]; then LARGEUR_NOM="${#nom}"; fi
        if [ "${#image}" -gt "$LARGEUR_IMAGE" ]; then LARGEUR_IMAGE="${#image}"; fi
        if [ "${#statut}" -gt "$LARGEUR_ETAT" ]; then LARGEUR_ETAT="${#statut}"; fi
        if [ "${#ports}" -gt "$LARGEUR_PORTS" ]; then LARGEUR_PORTS="${#ports}"; fi
    done <<< "$sortie"
}

# -------------------------------------------------------------------
# Affichage
# -------------------------------------------------------------------
# Cellule de largeur fixe, comptée en caractères. Le remplissage laisse toujours
# au moins une espace, qui sépare les colonnes.
#
# LES EN-TÊTES SONT SANS ACCENT, et ce n'est pas une coquille : la largeur d'une
# cellule se compte en octets dès que la locale n'est pas multibyte — un serveur
# en LANG=C suffit —, et « ÉTAT » y occuperait cinq octets pour quatre colonnes
# affichées. Le tableau se décalerait d'un cran sur ces machines-là. Les noms
# accentués restent dans l'aide, où rien n'est aligné.
cellule() {
    local texte="$1" largeur="$2" remplissage
    remplissage=$(( largeur - ${#texte} + 1 ))
    if [ "$remplissage" -lt 1 ]; then
        remplissage=1
    fi
    printf '%s%*s' "$texte" "$remplissage" ""
}

# L'identifiant fait douze caractères, quelle que soit la version du client :
# c'est la longueur de l'identifiant court qu'il rend, et celle que le script
# ramène de toute façon.
LARGEUR_ID=12

entete() {
    printf '  %s%s%s%s%s%s\n' \
        "$(cellule "NOM" "$LARGEUR_NOM")" \
        "$(cellule "IMAGE" "$LARGEUR_IMAGE")" \
        "$(cellule "ETAT" "$LARGEUR_ETAT")" \
        "$(cellule "IDENTIFIANT" "$LARGEUR_ID")" \
        "$(cellule "PORTS" "$LARGEUR_PORTS")" \
        "RESEAUX"
}

ligne_conteneur() {
    local i="$1"
    printf '  %s%s%s%s%s%s\n' \
        "$(cellule "${NOMS[i]}" "$LARGEUR_NOM")" \
        "$(cellule "${IMAGES[i]}" "$LARGEUR_IMAGE")" \
        "$(cellule "${ETATS[i]}" "$LARGEUR_ETAT")" \
        "$(cellule "${IDS[i]}" "$LARGEUR_ID")" \
        "$(cellule "${PORTS[i]}" "$LARGEUR_PORTS")" \
        "${RESEAUX[i]}"
}

section() {
    local categorie="$1" titre="$2" nombre="$3" vide="$4"
    local i

    printf '\n%s — %s\n' "$titre" "$nombre"
    printf '%s\n' "------------------------------------------------------------"

    if [ "$nombre" -eq 0 ]; then
        printf '%s\n' "$vide"
        return 0
    fi

    entete
    for i in "${!NOMS[@]}"; do
        [ "${CATEGORIES[i]}" = "$categorie" ] || continue
        ligne_conteneur "$i"
    done
}

message_vide() {
    printf 'Aucun conteneur à afficher'
    if [ "$TOUS" = "oui" ]; then
        printf " : cette machine n'en compte aucun, ni en cours d'exécution ni arrêté.\n"
    else
        printf " : aucun n'est en cours d'exécution (--all montre aussi les conteneurs arrêtés).\n"
    fi
}

afficher() {
    if [ "$COMPTE_ACTIF" -eq 0 ] && [ "$COMPTE_ARRETE" -eq 0 ]; then
        message_vide
        return 0
    fi

    section actif "Conteneurs en cours d'exécution" "$COMPTE_ACTIF" \
        "  Aucun conteneur en cours d'exécution."
    if [ "$TOUS" = "oui" ]; then
        section arrete "Conteneurs arrêtés" "$COMPTE_ARRETE" \
            "  Aucun conteneur arrêté."
    fi
}

# -------------------------------------------------------------------
# Exécution
# -------------------------------------------------------------------
info "Inventaire des conteneurs Docker — lecture seule."
analyser "$REPONSE"
afficher

# Le cas vide rend 0 : une machine sans conteneur n'est pas en panne. C'est le
# même raisonnement que l'inventaire de check-services.sh — un diagnostic rend
# compte, il ne juge pas.
exit 0
