#!/usr/bin/env bash
set -Eeuo pipefail
# update-docker.sh — met à jour le moteur Docker et ses composants, borné à ce que le socle a installé.

_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_dir/lib/common.sh" ] && [ "$_dir" != "/" ]; do _dir="$(dirname "$_dir")"; done
source "$_dir/lib/common.sh"

# Même liste que Docker/Installation/install-docker.sh : une divergence laisserait un composant installé que personne ne mettrait à jour.
PAQUETS="docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin"
DRY_RUN="false"
# OUI dit si --yes a été passé ; lib/common.sh reste seul lecteur d'ASSUME_YES.
OUI="false"
show_help() {
    cat <<'AIDE'
Usage : update-docker.sh [--dry-run] [-y|--yes] [--help]

Met à jour le moteur Docker et ses composants — docker-ce, docker-ce-cli, containerd.io,
docker-buildx-plugin, docker-compose-plugin — borné à ceux que le socle a réellement
installé ; un composant absent est signalé, jamais installé au passage. Aucune image
applicative n'est touchée. Cibles : Debian 12/13, Ubuntu 22.04/24.04 LTS.

Mettre à jour le moteur redémarre le démon : les conteneurs en cours sont interrompus, sauf
si live-restore est actif. Le script les compte, lit live-restore, annonce la coupure et
attend une confirmation. Il ne modifie jamais /etc/docker/daemon.json.

      --dry-run   relever et annoncer, sans installer ni redémarrer
  -y, --yes       ne rien demander — seul mode utilisable d'une tâche planifiée
  -h, --help      afficher cette aide

Codes : 0 mise à jour faite, simulée ou annulée ; 1 aucun composant installé hors --dry-run, système
ou outil hors cibles, question impossible à poser, service docker inactif après coup ; 2 usage.
AIDE
}

while [ "${1:-}" != "" ]; do
    case "$1" in
        --dry-run) DRY_RUN="true"; shift ;;
        -y|--yes)  export ASSUME_YES="true"; OUI="true"; shift ;;
        -h|--help) show_help; exit 0 ;;
        *)         die "Option inconnue : $1" 2 ;;
    esac
done

[ "$DRY_RUN" = "true" ] || require_root
require_os debian ubuntu
# Mêmes cibles qu'install-docker.sh, décidées une fois : orchestration/decisions.md, décision 14.
case "$OS_ID $OS_VERSION" in
    "debian 12"|"debian 13"|"ubuntu 22.04"|"ubuntu 24.04") ;;
    *) die "Version non supportée : $OS_ID $OS_VERSION (attendu : Debian 12/13, Ubuntu 22.04/24.04)" ;;
esac
require_cmd apt-get dpkg-query
# Sans cela, un dialogue apt suspendrait indéfiniment une tâche planifiée.
export DEBIAN_FRONTEND=noninteractive

# Version installée du paquet, vide s'il ne l'est pas : lire un paquet absent rend 1, échec NOMINAL que le « || » traite.
version_paquet() {
    local ligne
    ligne="$(dpkg-query -W -f='${Status} ${Version}' "$1" 2>/dev/null)" || ligne=""
    case "$ligne" in *"ok installed "*) printf '%s' "${ligne##* }" ;; esac
}

# systemctl is-active écrit son état ET rend un code non nul quand le service ne l'est pas : la sortie prime sur le code.
etat_service() { local e; e="$(systemctl is-active docker 2>/dev/null)" || e="${e:-inconnu}"; printf '%s' "$e"; }

# Ces deux lectures rendent une chaîne VIDE quand le démon ne répond pas : « illisible », jamais « zéro
# conteneur » ni « live-restore inactif » ; live-restore est LU, jamais écrit — daemon.json appartient à configure-docker.sh.
conteneurs_en_cours() { local n; n="$(docker ps -q 2>/dev/null | wc -l | tr -d ' ')" || n=""; printf '%s' "$n"; }
live_restore() { local v; v="$(docker info --format '{{.LiveRestoreEnabled}}' 2>/dev/null)" || v=""; printf '%s' "$v"; }

# Relevé, en une passe : il remplit INSTALLES et la table AVANT « paquet=version ».
relever() {
    local p v
    INSTALLES=(); AVANT=""
    printf '\nComposants Docker — état relevé :\n'
    for p in $PAQUETS; do
        v="$(version_paquet "$p")"
        if [ -n "$v" ]; then INSTALLES+=("$p"); AVANT="$AVANT $p=$v"; printf '  %-24s %s\n' "$p" "$v"
        else printf "  %-24s absent — non installé, et ce script ne l'installe jamais\n" "$p"; fi
    done
    printf '  %-24s %s\n' "service docker" "$(etat_service)"
}
version_avant() { local l; for l in $AVANT; do case "$l" in "$1="*) printf '%s' "${l#*=}"; return 0 ;; esac; done; }

relever
if [ "${#INSTALLES[@]}" -eq 0 ]; then
    warn "Il n'y a rien à mettre à jour : aucun composant Docker n'est installé. Docker/Installation/install-docker.sh les installe."
    [ "$DRY_RUN" = "true" ] && { info "[dry-run] Aucun index de paquets rafraîchi, aucun paquet installé."; exit 0; }
    die "Rien à mettre à jour : aucun composant Docker n'est installé." 1
fi

# Annoncé AVANT la confirmation, jamais découvert après : décompte illisible, parc vide et live-restore
# actif ne disent pas la même chose à qui doit répondre. Chaque cas pose aussi son libellé de confirmation.
LIVE="$(live_restore)"; CONTENEURS="$(conteneurs_en_cours)"
if [ -z "$CONTENEURS" ]; then
    COUPURE="L'état des conteneurs en cours n'a pas pu être relevé."
    warn "Démon Docker injoignable : ni le nombre de conteneurs en cours ni l'état de live-restore n'ont pu être lus — live-restore est illisible, non inactif."
elif [ "$CONTENEURS" = "0" ]; then
    COUPURE="Aucun conteneur en cours d'exécution."; info "Aucun conteneur en cours : le redémarrage du démon n'interrompra rien."
elif [ "$LIVE" = "true" ]; then
    COUPURE="live-restore est actif : les conteneurs en cours devraient survivre."; info "live-restore est actif : les $CONTENEURS conteneur(s) en cours survivent au redémarrage du démon. Que containerd n'y est pas sensible n'a PAS été mesuré ici : sa mise à jour peut les interrompre."
else
    COUPURE="Les conteneurs en cours seront interrompus."; warn "$CONTENEURS conteneur(s) en cours d'exécution seront INTERROMPUS par la mise à jour du moteur : live-restore n'est pas actif, et ce script ne l'active pas — cela relève de Docker/Configuration/configure-docker.sh."
fi

A_JOUR=("${INSTALLES[@]}")
if [ "$DRY_RUN" = "true" ]; then
    # Index rafraîchi même en simulation : « apt-get -s » a besoin d'un index à jour, et cet update ne fait que lire le cache.
    run_logged apt-get update || warn "Index des paquets non rafraîchi : la liste ci-dessous peut être incomplète."
    # « apt-get -s » simule ; les crochets de « Inst p <ancienne> » séparent une mise à niveau d'une installation, hors de ce ressort.
    simulation="$(apt-get -s install --only-upgrade "${INSTALLES[@]}" 2>/dev/null || true)"
    mapfile -t A_JOUR < <(printf '%s\n' "$simulation" | awk '/^Inst / && $3 ~ /^\[/ {print $2}')
fi

printf '\nComposants à mettre à jour — %d :\n' "${#A_JOUR[@]}"
[ "${#A_JOUR[@]}" -eq 0 ] || printf '  %s\n' "${A_JOUR[*]}"

if [ "$DRY_RUN" = "true" ]; then
    printf '\nCommandes qui seraient exécutées :\n  apt-get update\n'
    [ "${#A_JOUR[@]}" -eq 0 ] || printf '  apt-get install --only-upgrade -y %s\n' "${A_JOUR[*]}"
    info "[dry-run] Aucun paquet installé, aucun démon redémarré, aucune image touchée."
    exit 0
fi

[ -t 0 ] || [ "$OUI" = "true" ] || die "Mise à jour à confirmer, et aucun terminal n'est disponible. Relancer avec --yes." 1
confirm "Mettre à jour ces ${#A_JOUR[@]} composant(s) ? $COUPURE" || { info "Mise à jour annulée : rien n'a été installé, aucun démon redémarré."; exit 0; }

# L'index n'est rafraîchi qu'ici, après le feu vert : un refus n'aura rien déclenché.
run_logged apt-get update
# --only-upgrade borne la mise à jour à cette liste : « apt-get upgrade » emporterait tout le système.
run_logged apt-get install --only-upgrade -y "${INSTALLES[@]}"

printf '\nComposants — avant / après :\n'
for p in $PAQUETS; do
    a="$(version_avant "$p")"; b="$(version_paquet "$p")"; etat="inchangé"
    if [ -z "$a" ]; then etat="absent avant comme après"; [ -z "$b" ] || etat="APPARU"
    elif [ -z "$b" ]; then etat="RETIRÉ"
    elif [ "$a" != "$b" ]; then etat="mis à jour"
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
