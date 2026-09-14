#!/usr/bin/env bash
set -Eeuo pipefail

# Écrit /etc/docker/daemon.json, rotation des journaux de conteneurs en premier :
# sans elle, un conteneur bavard remplit /var/lib/docker jusqu'à saturer le
# disque. Les clés que ce script ne gère pas sont conservées ; leur fusion
# suppose jq. Aucune marque de propriété n'est déposée : dockerd rejette les
# directives qu'il ne connaît pas.

_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_dir/lib/common.sh" ] && [ "$_dir" != "/" ]; do _dir="$(dirname "$_dir")"; done
source "$_dir/lib/common.sh"

FICHIER="/etc/docker/daemon.json"
DRY_RUN="false"
LOG_DRIVER="${SRV_DOCKER_LOG_DRIVER:-json-file}"
LOG_MAX_SIZE="${SRV_DOCKER_LOG_MAX_SIZE:-10m}"
LOG_MAX_FILE="${SRV_DOCKER_LOG_MAX_FILE:-3}"

usage() {
    cat <<'EOF'
configure-docker.sh — écrit /etc/docker/daemon.json, rotation des journaux en premier.

Usage : configure-docker.sh [options]

  --log-driver <pilote>    json-file (défaut) ou local
  --log-max-size <taille>  10m, 512k, 1g…
  --log-max-file <nombre>  fichiers de journal conservés (entier positif)
  --dry-run                affiche le contenu visé, sans rien écrire ni redémarrer
  -y, --yes                ne pose aucune question (obligatoire hors terminal)
  -h, --help               affiche cette aide

Variables lues dans config/server.env, chargé par lib/common.sh :
  SRV_DOCKER_LOG_DRIVER, SRV_DOCKER_LOG_MAX_SIZE, SRV_DOCKER_LOG_MAX_FILE.
La ligne de commande prime sur ces variables.

Fichier écrit : /etc/docker/daemon.json — seules les clés log-driver et log-opts
sont posées ; toute autre clé déjà présente est conservée, ce qui suppose jq.
Sans jq, un fichier existant et divergent est refusé plutôt qu'écrasé.

Redémarrage du démon : pilote et rotation ne sont lus qu'à la CRÉATION d'un
conteneur. Le redémarrage interrompt ceux qui tournent — live-restore n'étant pas
actif par défaut, seuls ceux dotés d'une politique de redémarrage reviennent.
Les fichiers de journal existants ne sont ni tronqués ni supprimés.

Codes de retour :
  0  configuration écrite, ou déjà conforme
  1  privilège manquant, docker absent, jq requis mais absent, ou démon non revenu
  2  option inconnue ou valeur mal formée
EOF
}

# OUI dit si --yes a été passé ; lib/common.sh reste seul lecteur d'ASSUME_YES.
OUI="false"
while [ "${1:-}" != "" ]; do
    case "$1" in
        --dry-run) DRY_RUN="true"; shift ;;
        -y|--yes)  export ASSUME_YES="true"; OUI="true"; shift ;;
        --help|-h) usage; exit 0 ;;
        --log-driver|--log-max-size|--log-max-file)
            cle="$1"; shift
            [ "${1:-}" != "" ] || die "Option $cle : valeur manquante." 2
            case "$cle" in
                --log-driver)   LOG_DRIVER="$1" ;;
                --log-max-size) LOG_MAX_SIZE="$1" ;;
                --log-max-file) LOG_MAX_FILE="$1" ;;
            esac
            shift ;;
        *) die "Option inconnue : $1" 2 ;;
    esac
done

case "$LOG_DRIVER" in
    json-file|local) ;;
    *) die "Pilote de journalisation non supporté : $LOG_DRIVER (attendu : json-file ou local)" 2 ;;
esac
[[ "$LOG_MAX_SIZE" =~ ^[0-9]+[kKmMgG]$ ]] || die "Taille de journal mal formée : $LOG_MAX_SIZE" 2
[[ "$LOG_MAX_FILE" =~ ^[1-9][0-9]*$ ]] || die "Nombre de fichiers de journal mal formé : $LOG_MAX_FILE (entier positif attendu)" 2

JQ=""
if command -v jq >/dev/null 2>&1; then JQ="jq"; fi

contenu_cible() {
    printf '{\n  "log-driver": "%s",\n  "log-opts": {\n    "max-size": "%s",\n    "max-file": "%s"\n  }\n}\n' \
        "$LOG_DRIVER" "$LOG_MAX_SIZE" "$LOG_MAX_FILE"
}

# Conformité sémantique quand jq est là : un fichier correct mais compact ou
# réordonné n'est pas divergent. Sans jq, la comparaison reste textuelle.
est_conforme() {
    [ -f "$FICHIER" ] || return 1
    if [ -n "$JQ" ]; then
        # Filtre jq : les $d, $s, $f sont des variables jq, pas du shell.
        # shellcheck disable=SC2016
        if "$JQ" -e --arg d "$LOG_DRIVER" --arg s "$LOG_MAX_SIZE" --arg f "$LOG_MAX_FILE" \
            '."log-driver" == $d and ."log-opts"."max-size" == $s and ."log-opts"."max-file" == $f' \
            "$FICHIER" >/dev/null 2>&1; then
            return 0
        fi
        return 1
    fi
    [ "$(cat "$FICHIER")" = "$(contenu_cible)" ]
}

cible="$(contenu_cible)"
etat="absent"
if [ -f "$FICHIER" ]; then
    if est_conforme; then etat="conforme"; else etat="divergent"; fi
fi

if [ "$DRY_RUN" = "true" ]; then
    case "$etat" in
        conforme) info "[dry-run] $FICHIER est déjà conforme : rien à écrire." ;;
        absent)
            printf '\nContenu visé (%s)\n%s\n' "$FICHIER" "$cible" >&2
            info "[dry-run] $FICHIER sera créé, puis le démon redémarré." ;;
        divergent)
            printf '\nContenu actuel\n%s\n\nContenu visé\n%s\n' "$(cat "$FICHIER")" "$cible" >&2
            if [ -n "$JQ" ]; then
                info "[dry-run] $FICHIER sera remplacé par la fusion, l'original sauvegardé, puis le démon redémarré."
            else
                info "[dry-run] $FICHIER diverge et jq est absent : une exécution réelle refusera (code 1) sans rien écrire."
            fi ;;
    esac
    exit 0
fi

require_root
require_cmd docker

if [ "$etat" = "conforme" ]; then
    success "$FICHIER est déjà conforme : aucune écriture, aucun redémarrage."
    exit 0
fi

contenu="$cible"
if [ "$etat" = "divergent" ]; then
    if [ -z "$JQ" ]; then
        warn "jq est requis pour fusionner $FICHIER sans écraser les clés qu'il ne gère pas."
        printf '\nContenu qui aurait été écrit :\n%s\n' "$cible" >&2
        die "jq absent : rien n'a été écrit." 1
    fi
    # Filtre jq : les $d, $s, $f sont des variables jq, pas du shell.
    # shellcheck disable=SC2016
    if ! contenu="$("$JQ" --arg d "$LOG_DRIVER" --arg s "$LOG_MAX_SIZE" --arg f "$LOG_MAX_FILE" \
        '."log-driver" = $d | ."log-opts"."max-size" = $s | ."log-opts"."max-file" = $f' \
        "$FICHIER" 2>/dev/null)"; then
        die "$FICHIER n'est pas un JSON valide : rien n'a été écrit." 1
    fi
fi

{
    printf '\nChangements prévus\n'
    printf '  Fichier                %s\n' "$FICHIER"
    printf '  Pilote de journal      %s\n' "$LOG_DRIVER"
    printf '  Taille maximale        %s\n' "$LOG_MAX_SIZE"
    printf '  Fichiers conservés     %s\n' "$LOG_MAX_FILE"
    printf '  Redémarrage du démon   oui\n'
} >&2

en_cours="?"
if docker ps -q >/dev/null 2>&1; then
    en_cours="$(docker ps -q 2>/dev/null | wc -l | tr -d ' ')"
fi
info "$en_cours conteneur(s) en cours seront interrompus par le redémarrage."

[ -t 0 ] || [ "$OUI" = "true" ] \
    || die "Écriture à confirmer, et aucun terminal n'est disponible. Relancer avec --yes." 1
confirm "Écrire $FICHIER et redémarrer le démon ?" || die "Configuration abandonnée." 1

mkdir -p /etc/docker
tmp="$(mktemp "$FICHIER.XXXXXX")"
nettoyer() { if [ -n "$tmp" ]; then rm -f "$tmp"; fi; }
trap nettoyer EXIT

printf '%s\n' "$contenu" > "$tmp"
# Sans jq, seul le contenu que ce script construit lui-même peut être écrit
# (voir plus haut) : la construction garantit sa validité, et la validation par
# jq n'a donc de sens que lorsque jq est là.
if [ -n "$JQ" ] && ! "$JQ" empty "$tmp" >/dev/null 2>&1; then
    die "Le JSON produit est invalide : rien n'a été installé." 1
fi

sauvegarde=""
if [ "$etat" = "divergent" ]; then
    sauvegarde="$FICHIER.$(date '+%Y%m%d-%H%M%S').bak"
    cp -p "$FICHIER" "$sauvegarde"
    info "Original sauvegardé : $sauvegarde"
fi

mv "$tmp" "$FICHIER"
tmp=""
chmod 0644 "$FICHIER"
info "$FICHIER écrit."

# Restauration suivie d'une relance : sans elle, un démon arrêté par un fichier
# refusé le reste, alors que la configuration fautive vient d'être retirée.
restaurer_original() {
    if [ -n "$sauvegarde" ] && [ -f "$sauvegarde" ]; then
        cp -p "$sauvegarde" "$FICHIER"
        warn "Configuration précédente restaurée depuis $sauvegarde."
    else
        rm -f "$FICHIER"
        warn "$FICHIER retiré : aucun original à restaurer."
    fi
    if ! run_logged systemctl restart docker; then
        warn "Le démon n'a pas pu être relancé avec la configuration précédente."
    fi
}

if ! run_logged systemctl restart docker; then
    warn "Le redémarrage du démon a échoué."
    restaurer_original
    die "Configuration en échec : le démon n'a pas redémarré." 1
fi

revenu="non"
for essai in 1 2 3; do
    if docker version >/dev/null 2>&1; then revenu="oui"; break; fi
    if [ "$essai" -lt 3 ]; then sleep 1; fi
done

if [ "$revenu" != "oui" ]; then
    warn "Le démon Docker ne répond pas après redémarrage."
    restaurer_original
    die "Configuration en échec : le démon n'est pas revenu." 1
fi

success "Docker configuré : journalisation $LOG_DRIVER, $LOG_MAX_SIZE, $LOG_MAX_FILE."
info "La rotation ne vaut que pour les conteneurs créés ensuite ; les journaux existants ne sont pas purgés."
