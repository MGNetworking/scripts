#!/usr/bin/env bash
set -Eeuo pipefail
# update-docker.sh — met à jour le moteur Docker et ses composants, borné à ce
# que le socle a installé : ni les images applicatives, ni les autres paquets.

_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_dir/lib/common.sh" ] && [ "$_dir" != "/" ]; do _dir="$(dirname "$_dir")"; done
source "$_dir/lib/common.sh"

# Même liste que Docker/Installation/install-docker.sh : une divergence
# laisserait un composant installé que personne ne mettrait à jour.
PAQUETS="docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin"
DRY_RUN="false"

show_help() {
    cat <<'AIDE'
Usage : update-docker.sh [--dry-run] [-y|--yes] [--help]

Met à jour le moteur Docker et ses composants — docker-ce, docker-ce-cli,
containerd.io, docker-buildx-plugin, docker-compose-plugin — borné à ceux que
le socle a réellement installé. Un composant absent est signalé et jamais
installé au passage : installer relève d'install-docker.sh. Aucune image
applicative n'est touchée, rien n'est redéployé.

Le paquet du moteur redémarre le démon : les conteneurs en cours sont
interrompus, sauf si live-restore est actif. Le script les compte, lit
live-restore, annonce la coupure et attend une confirmation. Il ne modifie
jamais /etc/docker/daemon.json et ne redémarre jamais le serveur.

      --dry-run   relever et annoncer, sans installer ni redémarrer
  -y, --yes       ne rien demander — seul mode utilisable d'une tâche planifiée
  -h, --help      afficher cette aide

Codes : 0 mise à jour faite, simulée ou annulée ; 1 aucun composant installé
hors --dry-run, apt-get absent, système hors cibles, ou service docker inactif
après coup ; 2 usage.
AIDE
}

while [ "${1:-}" != "" ]; do
    case "$1" in
        --dry-run) DRY_RUN="true"; shift ;;
        -y|--yes)  export ASSUME_YES="true"; shift ;;
        -h|--help) show_help; exit 0 ;;
        *)         die "Option inconnue : $1" 2 ;;
    esac
done

[ "$DRY_RUN" = "true" ] || require_root
require_os debian ubuntu
require_cmd apt-get dpkg-query
# Sans cela, un dialogue apt suspendrait indéfiniment une tâche planifiée.
export DEBIAN_FRONTEND=noninteractive

# Version installée du paquet, vide s'il ne l'est pas. dpkg-query -W est une
# lecture ; l'échec y est NOMINAL — un paquet absent rend 1 — et le « || » le traite.
version_paquet() {
    local ligne
    ligne="$(dpkg-query -W -f='${Status} ${Version}' "$1" 2>/dev/null)" || ligne=""
    case "$ligne" in *"ok installed "*) printf '%s' "${ligne##* }" ;; esac
}

# « inconnu » hors d'un init systemd : systemctl ne répond pas, et ce n'est pas
# un échec du script. Un décompte de conteneurs vide, lui, ne vaut jamais zéro.
etat_service() { local e; e="$(systemctl is-active docker 2>/dev/null)" || e="inconnu"; printf '%s' "$e"; }
conteneurs_en_cours() { local n; n="$(docker ps -q 2>/dev/null | wc -l | tr -d ' ')" || n=""; printf '%s' "$n"; }
# live-restore est LU dans « docker info », jamais écrit : /etc/docker/daemon.json
# appartient à Docker/Configuration/configure-docker.sh.
live_restore_actif() { local v; v="$(docker info --format '{{.LiveRestoreEnabled}}' 2>/dev/null)" || v=""; [ "$v" = "true" ]; }

# Relevé, en une passe : il remplit INSTALLES et la table AVANT, écrite
# « paquet=version » — une version Debian ne porte pas d'espace.
relever() {
    local p v
    INSTALLES=(); AVANT=""
    printf '\nComposants Docker — état relevé :\n'
    for p in $PAQUETS; do
        v="$(version_paquet "$p")"
        if [ -n "$v" ]; then
            INSTALLES+=("$p"); AVANT="$AVANT $p=$v"
            printf '  %-24s %s\n' "$p" "$v"
        else
            printf "  %-24s absent — non installé, et ce script ne l'installe jamais\n" "$p"
        fi
    done
    printf '  %-24s %s\n' "service docker" "$(etat_service)"
}
version_avant() { local l; for l in $AVANT; do case "$l" in "$1="*) printf '%s' "${l#*=}"; return 0 ;; esac; done; }

relever
if [ "${#INSTALLES[@]}" -eq 0 ]; then
    warn "Aucun composant Docker n'est installé : rien à mettre à jour. Docker/Installation/install-docker.sh les installe."
    [ "$DRY_RUN" = "true" ] && { info "[dry-run] Aucun index de paquets rafraîchi, aucun paquet installé."; exit 0; }
    die "Rien à mettre à jour : aucun composant Docker n'est installé." 1
fi

# L'interruption est annoncée AVANT la confirmation, jamais découverte après.
CONTENEURS="$(conteneurs_en_cours)"
if [ -z "$CONTENEURS" ]; then
    warn "Démon Docker injoignable : le nombre de conteneurs en cours n'a pas pu être relevé."
elif [ "$CONTENEURS" = "0" ]; then
    info "Aucun conteneur en cours : le redémarrage du démon n'interrompra rien."
else
    warn "$CONTENEURS conteneur(s) en cours d'exécution seront INTERROMPUS par la mise à jour du moteur."
fi
if live_restore_actif; then
    info "live-restore est actif : les conteneurs survivent au redémarrage du démon. containerd n'y est pas sensible — le mettre à jour les interrompt."
else
    warn "live-restore n'est pas actif : le démon redémarré à l'installation emportera les conteneurs en cours. Ce script ne l'active pas : cela relève de Docker/Configuration/configure-docker.sh."
fi

printf '\nComposants à mettre à jour — %d :\n' "${#INSTALLES[@]}"
printf '  %s\n' "${INSTALLES[@]}"

if [ "$DRY_RUN" = "true" ]; then
    printf '\nCommandes qui seraient exécutées :\n  apt-get update\n  apt-get install --only-upgrade -y %s\n' "${INSTALLES[*]}"
    info "[dry-run] Aucun paquet installé, aucun démon redémarré, aucune image touchée."
    exit 0
fi

confirm "Mettre à jour ces ${#INSTALLES[@]} composant(s) ? Les conteneurs en cours seront interrompus." \
    || { info "Mise à jour annulée : rien n'a été installé, aucun démon redémarré."; exit 0; }

# L'index n'est rafraîchi qu'ici : avec des composants installés, une mise à
# jour lue sur un index périmé ne vaut rien ; et un refus n'aura rien déclenché.
run_logged apt-get update
# --only-upgrade borne la mise à jour à cette liste : « apt-get upgrade » emporterait tout le système.
run_logged apt-get install --only-upgrade -y "${INSTALLES[@]}"

printf '\nComposants — avant / après :\n'
for p in $PAQUETS; do
    a="$(version_avant "$p")"; b="$(version_paquet "$p")"
    if [ -z "$a" ] && [ -z "$b" ]; then etat="absent avant comme après"
    elif [ -z "$a" ]; then etat="APPARU"
    elif [ -z "$b" ]; then etat="RETIRÉ"
    elif [ "$a" = "$b" ]; then etat="inchangé"
    else etat="mis à jour"
    fi
    printf '  %-24s %-22s %s → %s\n' "$p" "$etat" "${a:-absent}" "${b:-absent}"
done
ETAT="$(etat_service)"
printf '  %-24s %s\n' "service docker" "$ETAT"
case "$ETAT" in
    active)  success "Le service docker est actif." ;;
    inconnu) warn "État du service docker invérifiable ici : « systemctl is-active docker » n'a pas répondu. Diagnostic : systemctl status docker ; journalctl -u docker -n 50" ;;
    *)       die "Le service docker n'est pas actif après la mise à jour ($ETAT). Diagnostic : systemctl status docker ; journalctl -u docker -n 50" 1 ;;
esac

success "Mise à jour terminée. Aucune image, aucun conteneur, aucun volume n'a été touché."
