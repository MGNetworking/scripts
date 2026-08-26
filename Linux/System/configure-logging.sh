#!/usr/bin/env bash
# configure-logging.sh — met en place la journalisation du dépôt sur ce serveur.
#
# À lancer une fois par serveur, à la mise en route. Deux actions :
#   1. créer le répertoire des journaux avec les permissions adéquates ;
#   2. déposer la règle logrotate qui assure leur rotation.
#
# Idempotent : relançable sans effet de bord.

set -Eeuo pipefail

_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_dir/lib/common.sh" ] && [ "$_dir" != "/" ]; do _dir="$(dirname "$_dir")"; done
source "$_dir/lib/common.sh"

DRY_RUN="false"

# Le répertoire vient de common.sh, qui l'a lui-même résolu depuis
# config/server.env ou depuis sa valeur par défaut. Une seule source de vérité pour
# l'endroit où les journaux sont écrits et celui que logrotate doit surveiller.
REPERTOIRE_LOGS="$LOG_DIR"
ORIGINE_CHEMIN="valeur par défaut"
if [ -f "$SCRIPTS_ROOT/config/server.env" ]; then
    ORIGINE_CHEMIN="config/server.env"
fi
NOM_REGLE="$(basename "$REPERTOIRE_LOGS")"
FICHIER_REGLE="/etc/logrotate.d/$NOM_REGLE"

# Groupe propriétaire des journaux. « adm » est le groupe de lecture des
# journaux sur Debian et Ubuntu ; il n'existe pas partout.
GROUPE_LOGS="root"
if getent group adm >/dev/null 2>&1; then
    GROUPE_LOGS="adm"
fi

# -------------------------------------------------------------------
# Aide
# -------------------------------------------------------------------
show_help() {
    cat <<'AIDE'
Usage : configure-logging.sh [options]

Met en place la journalisation du dépôt sur ce serveur :

  1. crée le répertoire des journaux ;
  2. dépose la règle logrotate qui assure leur rotation hebdomadaire.

La règle couvre tous les fichiers *.log du répertoire : aucun script ajouté par
la suite ne nécessitera de reconfiguration.

À lancer une fois par serveur. Relançable sans effet de bord.

Options :
      --dry-run   Afficher ce qui serait fait, sans rien écrire.
  -y, --yes       Ne pas demander de confirmation avant de remplacer une règle
                  existante différente.
  -h, --help      Afficher cette aide
AIDE
}

while [ "${1:-}" != "" ]; do
    case "$1" in
        --dry-run)  DRY_RUN="true"; shift ;;
        -y|--yes)   ASSUME_YES="true"; shift ;;
        -h|--help)  show_help; exit 0 ;;
        *)          die "Option inconnue : $1" 2 ;;
    esac
done

# -------------------------------------------------------------------
# Préflight
# -------------------------------------------------------------------
require_root

if ! command -v logrotate >/dev/null 2>&1; then
    error "logrotate est introuvable."
    error "L'installer avec : apt-get install logrotate"
    die "Prérequis manquant."
fi

if [ ! -d /etc/logrotate.d ]; then
    die "/etc/logrotate.d est absent : installation de logrotate incomplète."
fi

# -------------------------------------------------------------------
# Règle logrotate attendue
# -------------------------------------------------------------------
regle_attendue() {
    cat <<REGLE
# Rotation des journaux du dépôt MGNetworking/script.
# Déposé par Linux/System/configure-logging.sh — ne pas modifier à la main :
# une prochaine exécution du script signalerait la différence.
$REPERTOIRE_LOGS/*.log {
    weekly
    rotate 8
    compress
    delaycompress
    missingok
    notifempty
    create 0640 root $GROUPE_LOGS
}
REGLE
}

# -------------------------------------------------------------------
# Répertoire des journaux
# -------------------------------------------------------------------
info "Répertoire des journaux : $REPERTOIRE_LOGS ($ORIGINE_CHEMIN)"

if [ -d "$REPERTOIRE_LOGS" ]; then
    info "Le répertoire existe déjà."
elif [ "$DRY_RUN" = "true" ]; then
    info "[dry-run] Créerait $REPERTOIRE_LOGS (0750 root:$GROUPE_LOGS)."
else
    mkdir -p "$REPERTOIRE_LOGS"
    success "Répertoire créé."
fi

# Les permissions sont réappliquées à chaque exécution : c'est ce qui rend le
# script idempotent, et cela corrige un répertoire créé auparavant par
# common.sh avec le umask par défaut.
if [ -d "$REPERTOIRE_LOGS" ]; then
    if [ "$DRY_RUN" = "true" ]; then
        info "[dry-run] Appliquerait 0750 root:$GROUPE_LOGS sur $REPERTOIRE_LOGS."
    else
        chown "root:$GROUPE_LOGS" "$REPERTOIRE_LOGS"
        chmod 0750 "$REPERTOIRE_LOGS"
        info "Permissions appliquées : 0750 root:$GROUPE_LOGS"
    fi
fi

# -------------------------------------------------------------------
# Règle logrotate
# -------------------------------------------------------------------
if [ -f "$FICHIER_REGLE" ]; then
    if regle_attendue | diff -q - "$FICHIER_REGLE" >/dev/null 2>&1; then
        success "La règle $FICHIER_REGLE est déjà en place et à jour."
        exit 0
    fi

    warn "$FICHIER_REGLE existe et diffère de la règle attendue."
    warn "Différences (- attendu, + en place) :"
    regle_attendue | diff -u - "$FICHIER_REGLE" | tail -n +3 >&2 || true

    if [ "$DRY_RUN" = "true" ]; then
        info "[dry-run] Remplacerait $FICHIER_REGLE."
        exit 0
    fi
    if ! confirm "Remplacer $FICHIER_REGLE ?"; then
        info "Abandon : la règle en place est conservée."
        exit 0
    fi
elif [ "$DRY_RUN" = "true" ]; then
    info "[dry-run] Créerait $FICHIER_REGLE :"
    regle_attendue | sed 's/^/    /' >&2
    exit 0
fi

regle_attendue > "$FICHIER_REGLE"
chmod 0644 "$FICHIER_REGLE"
success "Règle écrite : $FICHIER_REGLE"

# -------------------------------------------------------------------
# Vérification
# -------------------------------------------------------------------
# « logrotate -d » simule sans rien modifier : il valide la syntaxe et affiche
# ce qui serait fait à la prochaine rotation.
info "Vérification de la règle…"
if run_logged logrotate -d "$FICHIER_REGLE"; then
    success "Journalisation configurée. Rotation hebdomadaire, 8 semaines conservées."
else
    die "logrotate rejette la règle : $FICHIER_REGLE"
fi
