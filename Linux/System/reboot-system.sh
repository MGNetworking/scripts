#!/usr/bin/env bash
set -Eeuo pipefail
# reboot-system.sh — redémarrage explicite et confirmé du serveur.
#   sudo Linux/System/reboot-system.sh --dry-run   # tout vérifier, ne rien lancer
#   sudo Linux/System/reboot-system.sh             # demande confirmation
#   sudo Linux/System/reboot-system.sh --yes       # sans confirmation (planifié)

_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_dir/lib/common.sh" ] && [ "$_dir" != "/" ]; do _dir="$(dirname "$_dir")"; done
source "$_dir/lib/common.sh"

SI_NECESSAIRE="false"; DRY_RUN="false"
# La commande de redémarrage, écrite une seule fois : c'est celle que --dry-run
# affiche, et celle qu'un faux systemctl peut enregistrer à la place d'agir.
COMMANDE=(systemctl reboot)

usage() {
    cat <<'AIDE'
Usage : reboot-system.sh [options]

Redémarre la machine après vérification. Aucun repli sur shutdown, halt ni
telinit : systemctl est requis, et son absence fait sortir en 1.

Contrôles, dans cet ordre : arguments, privilèges, distribution (debian, ubuntu),
systemctl, opération de gestion de paquets en cours — refus en 1, processus
nommé —, puis résumé : machine, date, temps de fonctionnement, redémarrage
déclaré ou non par /run/reboot-required, sessions ouvertes. Les sessions
avertissent et sont nommées ; leur présence n'empêche jamais à elle seule le
redémarrage. La confirmation vient en dernier.

Options :
  -y, --yes            Ne rien demander : tâche planifiée, sans terminal.
      --si-necessaire  Ne redémarrer que si /run/reboot-required est présent ;
                       sinon ne rien faire, et rendre 0.
      --dry-run        Parcourir tous les contrôles, afficher la commande exacte
                       qui serait lancée, et ne pas la lancer.
  -h, --help           Afficher cette aide

Codes : 0 redémarrage demandé, ou rien à faire avec --si-necessaire ;
        1 prérequis manquant ou refus ; 2 usage refusé.
AIDE
}

while [ "${1:-}" != "" ]; do
    case "$1" in
        --si-necessaire) SI_NECESSAIRE="true"; shift ;;
        --dry-run)       DRY_RUN="true"; shift ;;
        # ASSUME_YES est lue par confirm(), dans lib/common.sh.
        -y|--yes)        export ASSUME_YES="true"; shift ;;
        -h|--help)       usage; exit 0 ;;
        *)               die "Option inconnue : $1" 2 ;;
    esac
done

require_root
require_os debian ubuntu
require_cmd systemctl pgrep

# Redémarrer pendant un dpkg laisse un système à moitié configuré, parfois non
# amorçable : c'est le contrôle qui justifie ce script, et il précède toute
# lecture d'état. Le nom du processus suffit à le reconnaître.
for processus in dpkg apt apt-get aptitude; do
    pids=""
    if ! pids="$(pgrep -x "$processus")"; then pids=""; fi
    if [ -n "$pids" ]; then
        die "Opération de gestion de paquets en cours : « $processus » (PID ${pids//$'\n'/, }) — redémarrer maintenant laisserait un système à moitié configuré. Rien n'a été fait." 1
    fi
done

# --- Résumé, avant le geste irréversible -----------------------------------
HOTE=""; if ! HOTE="$(uname -n)"; then HOTE="inconnu"; fi
DATE=""; if ! DATE="$(date '+%Y-%m-%d %H:%M:%S %Z')"; then DATE="inconnue"; fi

uptime_sec=""
if ! uptime_sec="$(cut -d. -f1 /proc/uptime)"; then uptime_sec=""; fi
UPTIME="inconnu"
case "$uptime_sec" in
    ''|*[!0-9]*) ;;
    *) UPTIME="$((uptime_sec / 86400)) j $(((uptime_sec % 86400) / 3600)) h $(((uptime_sec % 3600) / 60)) min" ;;
esac

# Le témoin est lu sur le disque, jamais supposé : /var/run en est un lien.
NECESSAIRE="non"
if [ -e /run/reboot-required ]; then NECESSAIRE="oui"; fi

SESSIONS=""
if command -v who >/dev/null 2>&1; then
    if ! SESSIONS="$(who 2>/dev/null)"; then SESSIONS=""; fi
else
    warn "« who » est absent : les sessions ouvertes ne peuvent pas être listées."
fi
NB_SESSIONS=0
if ! NB_SESSIONS="$(grep -c . <<< "$SESSIONS")"; then NB_SESSIONS=0; fi

info "Machine    : $HOTE"
info "Date       : $DATE"
info "En service : $UPTIME"
if [ "$NECESSAIRE" = "oui" ]; then
    info "Redémarrage nécessaire : oui — /run/reboot-required est présent."
    PAQUETS=""
    if ! PAQUETS="$(tr '\n' ' ' < /run/reboot-required.pkgs 2>/dev/null)"; then PAQUETS=""; fi
    if [ -n "$PAQUETS" ]; then info "Paquets concernés : $PAQUETS"; fi
else
    info "Redémarrage nécessaire : non — /run/reboot-required est absent."
fi
if [ "$NB_SESSIONS" -eq 0 ]; then
    info "Sessions ouvertes : aucune."
else
    warn "Sessions ouvertes : $NB_SESSIONS — elles seront coupées par le redémarrage."
    printf '%s\n' "$SESSIONS" | sed 's/^/    /' >&2
fi
info "Action     : redémarrage immédiat — ${COMMANDE[*]}"

if [ "$SI_NECESSAIRE" = "true" ] && [ "$NECESSAIRE" = "non" ]; then
    success "Aucun redémarrage n'est nécessaire : rien n'a été fait."
    exit 0
fi

if [ "$DRY_RUN" = "true" ]; then
    info "[dry-run] Commande qui serait lancée : ${COMMANDE[*]}"
    info "Mode --dry-run : aucun redémarrage n'a été déclenché."
    exit 0
fi

if ! confirm "Redémarrer $HOTE maintenant ?"; then
    info "Abandon à la demande de l'utilisateur : rien n'a été fait."
    exit 0
fi

if ! run_logged "${COMMANDE[@]}"; then
    die "« ${COMMANDE[*]} » a échoué — la machine n'a pas été redémarrée." 1
fi
success "Redémarrage demandé : la machine va s'arrêter."
