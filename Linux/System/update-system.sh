#!/usr/bin/env bash
# update-system.sh — mise à jour des paquets du système.
#
# Cible : Debian et Ubuntu.
# Ne redémarre jamais le serveur : un redémarrage nécessaire est signalé,
# jamais déclenché.

set -Eeuo pipefail

_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_dir/lib/common.sh" ] && [ "$_dir" != "/" ]; do _dir="$(dirname "$_dir")"; done
source "$_dir/lib/common.sh"

DRY_RUN="false"

# -------------------------------------------------------------------
# Aide
# -------------------------------------------------------------------
show_help() {
    cat <<'AIDE'
Usage : update-system.sh [options]

Met à jour les paquets installés (Debian, Ubuntu).

Déroulement : rafraîchissement de l'index des paquets, résumé des mises à jour
disponibles, confirmation, puis mise à jour. Le serveur n'est jamais redémarré ;
si un redémarrage devient nécessaire, il est signalé en fin d'exécution.

Options :
      --dry-run   Afficher les mises à jour disponibles sans rien installer.
                  L'index des paquets est tout de même rafraîchi, sans quoi la
                  liste serait périmée.
  -y, --yes       Ne pas demander de confirmation (automatisation, cron).
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
require_os debian ubuntu
require_cmd apt-get

# apt-get ne doit jamais ouvrir de dialogue : sans cela, une mise à jour
# lancée par cron resterait bloquée indéfiniment sur une question.
export DEBIAN_FRONTEND=noninteractive

# -------------------------------------------------------------------
# Index des paquets
# -------------------------------------------------------------------
info "Rafraîchissement de l'index des paquets…"
run_logged apt-get update

# -------------------------------------------------------------------
# Résumé des changements
# -------------------------------------------------------------------
# « apt-get -s upgrade » simule sans rien modifier : chaque paquet qui serait
# installé apparaît sur une ligne commençant par « Inst ».
simulation="$(apt-get -s upgrade 2>/dev/null || true)"
a_installer="$(printf '%s\n' "$simulation" | grep '^Inst ' || true)"

if [ -z "$a_installer" ]; then
    success "Le système est à jour, aucun paquet à mettre à niveau."
    exit 0
fi

nombre="$(printf '%s\n' "$a_installer" | wc -l | tr -d ' ')"
info "$nombre paquet(s) à mettre à jour :"
# Sur stderr, comme les messages de common.sh : la liste est un diagnostic,
# pas une donnée produite par le script.
printf '%s\n' "$a_installer" | awk '{print "    " $2 " " $3}' >&2

if [ "$DRY_RUN" = "true" ]; then
    info "Mode --dry-run : aucune modification effectuée."
    exit 0
fi

# -------------------------------------------------------------------
# Confirmation puis mise à jour
# -------------------------------------------------------------------
if ! confirm "Mettre à jour ces $nombre paquet(s) ?"; then
    info "Abandon à la demande de l'utilisateur."
    exit 0
fi

info "Mise à jour en cours…"
run_logged apt-get upgrade -y

# -------------------------------------------------------------------
# Vérification
# -------------------------------------------------------------------
restant="$(apt-get -s upgrade 2>/dev/null | grep -c '^Inst ' || true)"
if [ "$restant" -gt 0 ]; then
    # Un paquet retenu (phased update, dépendance non satisfaite) n'est pas une
    # erreur : « apt-get upgrade » n'installe ni ne supprime rien de nouveau.
    warn "$restant paquet(s) n'ont pas été mis à jour (paquets retenus)."
    warn "Les examiner avec : apt-get --simulate dist-upgrade"
fi

if [ -f /var/run/reboot-required ]; then
    warn "Un redémarrage est nécessaire pour appliquer certaines mises à jour."
    if [ -r /var/run/reboot-required.pkgs ]; then
        warn "Paquets concernés : $(tr '\n' ' ' < /var/run/reboot-required.pkgs)"
    fi
    warn "Ce script ne redémarre jamais : utiliser Linux/System/reboot-system.sh."
fi

success "Mise à jour terminée."
