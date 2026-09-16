#!/usr/bin/env bash
set -Eeuo pipefail

# Désinstalle K3s par le désinstallateur officiel, après avoir listé ce qui sera
# détruit et obtenu une confirmation. Décision 47 : ce désinstallateur seul,
# aucune suppression écrite à la main.
#
# Chemins détruits, relevés dans install.sh, fonctions create_killall et
# create_uninstall (https://raw.githubusercontent.com/k3s-io/k3s/master/install.sh) :
# /var/lib/cni par k3s-killall.sh, puis k3s.service et k3s.service.env,
# /etc/rancher/k3s, /run/k3s, /run/flannel, /var/lib/rancher/k3s,
# /var/lib/kubelet, le binaire k3s et k3s-killall.sh. Ni /var/log/pods ni
# /var/log/containers : aucun des deux scripts ne les supprime.

_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_dir/lib/common.sh" ] && [ "$_dir" != "/" ]; do _dir="$(dirname "$_dir")"; done
source "$_dir/lib/common.sh"

# Décision 45 : un parent qui exporte ASSUME_YES ne confirme pas à ma place.
export ASSUME_YES="false"
# Un INSTALL_K3S_* ou un K3S_* hérité — URL du cluster, jeton de nœud — n'a rien
# à faire dans l'environnement du désinstallateur, ni dans le journal. compgen
# rend 1 quand rien ne correspond : c'est le cas courant.
for _v in $(compgen -v INSTALL_K3S_ || true) $(compgen -v K3S_ || true); do unset "$_v"; done
unset _v

DRY_RUN="false"
OUI="false"

usage() {
    cat <<'EOF'
uninstall-k3s.sh — désinstalle K3s par le désinstallateur officiel.

Usage : uninstall-k3s.sh [--dry-run] [-y|--yes] [--help]

  --dry-run   affiche ce qui serait détruit, sans rien supprimer
  -y, --yes   ne pose aucune question (obligatoire hors terminal)

Destructif : les volumes local-path des pods, sous /var/lib/rancher/k3s/storage,
disparaissent avec le reste ; aucune sauvegarde n'est faite ici.

Root est requis, --dry-run compris. Décision 47 : seul
/usr/local/bin/k3s-uninstall.sh supprime quelque chose, après le résumé. K3s
absent rend 0 ; un nœud agent, ou un k3s sans désinstallateur, est refusé en 1
sans rien supprimer.

Codes de retour :
  0  K3s désinstallé, déjà absent, ou simulation
  1  root manquant, désinstallateur absent, nœud agent, confirmation refusée,
     échec du désinstallateur, ou état final incomplet
  2  option inconnue
EOF
}

while [ "${1:-}" != "" ]; do
    case "$1" in
        --dry-run) DRY_RUN="true"; shift ;;
        -y|--yes)  export ASSUME_YES="true"; OUI="true"; shift ;;
        --help|-h) usage; exit 0 ;;
        *) die "Option inconnue : $1" 2 ;;
    esac
done

require_root
require_cmd du cut systemctl

# Surcharge de test : la racine visée ne se déplace QUE dans un conteneur, et
# jamais en silence — sur une machine réelle, rien ne détourne la désinstallation.
RACINE=""
if [ -e /.dockerenv ] && [ -n "${RACINE_TEST:-}" ]; then
    RACINE="$RACINE_TEST"
    warn "Racine de test : RACINE_TEST détourne la désinstallation vers $RACINE (conteneur seulement)."
fi

DESINSTALLATEUR="$RACINE/usr/local/bin/k3s-uninstall.sh"
DESINSTALLATEUR_AGENT="$RACINE/usr/local/bin/k3s-agent-uninstall.sh"
UNITE="$RACINE/etc/systemd/system/k3s.service"
STORAGE="$RACINE/var/lib/rancher/k3s/storage"
# Ce qu'il détruit : cette liste sert au résumé ET au verdict, relu après coup.
DETRUITS=("$RACINE/etc/rancher/k3s" "$RACINE/var/lib/rancher/k3s" "$RACINE/var/lib/kubelet"
          "$RACINE/var/lib/cni" "$RACINE/run/k3s" "$RACINE/run/flannel"
          "$RACINE/usr/local/bin/k3s-killall.sh" "$RACINE/etc/systemd/system/k3s.service.env")

BINAIRE="$(command -v k3s || true)"
if [ ! -x "$DESINSTALLATEUR" ] && [ -x "$DESINSTALLATEUR_AGENT" ]; then
    die "Ce nœud est un agent K3s : $DESINSTALLATEUR_AGENT est présent, $DESINSTALLATEUR non. Désinstaller un agent est hors du périmètre de ce script (décision 47). Rien n'a été supprimé." 1
fi
if [ -z "$BINAIRE" ] && [ ! -x "$DESINSTALLATEUR" ]; then
    success "K3s n'est pas installé sur cette machine : ni binaire k3s, ni $DESINSTALLATEUR. Rien à désinstaller, rien n'a été touché."
    exit 0
fi
if [ ! -x "$DESINSTALLATEUR" ]; then
    die "Le désinstallateur officiel $DESINSTALLATEUR est absent : ce script ne supprime rien lui-même (décision 47). Rien n'a été supprimé." 1
fi

# Taille d'un chemin ; un du partiel rend la taille déjà écrite, ou « illisible ».
taille() {
    local t=""
    if [ ! -e "$1" ]; then printf 'absente'; return 0; fi
    t="$(du -sh "$1" 2>/dev/null | cut -f1)" || t="${t:-illisible}"
    printf '%s' "${t:-illisible}"
}

printf '\nCe que %s détruira\n\n' "$DESINSTALLATEUR"
for p in "${DETRUITS[@]}"; do
    printf '  %s %s\n' "$p" "$(taille "$p")"
    if [ "$p" = "$RACINE/var/lib/rancher/k3s" ]; then
        printf '    dont %s (volumes local-path des pods) %s\n' "$STORAGE" "$(taille "$STORAGE")"
    fi
done
ETAT_SERVICE="$(systemctl is-active k3s 2>/dev/null || true)"
printf '\n  Binaire à supprimer  : %s\n  Unité à supprimer    : %s\n  État du service k3s  : %s\n  Sauvegarde préalable : aucune\n\n' \
    "${BINAIRE:-aucun}" "$UNITE" "${ETAT_SERVICE:-inconnu}"

if [ "$DRY_RUN" = "true" ]; then
    info "[dry-run] Commande prévue : $DESINSTALLATEUR — rien n'a été supprimé."
    exit 0
fi

[ -t 0 ] || [ "$OUI" = "true" ] || die "Désinstallation à confirmer, et aucun terminal n'est disponible. Relancer avec --yes." 1
confirm "Désinstaller K3s et détruire les données listées ci-dessus ?" || die "Désinstallation abandonnée : rien n'a été supprimé." 1

CODE_DESINSTALLATION=0
run_logged "$DESINSTALLATEUR" || CODE_DESINSTALLATION=$?

# État relu : c'est lui, et non la liste du résumé, qui décide du verdict.
RESTE=""
if command -v k3s >/dev/null 2>&1; then RESTE="$RESTE ${BINAIRE:-k3s}"; fi
if [ -e "$UNITE" ]; then
    RESTE="$RESTE $UNITE"
elif systemctl is-enabled k3s >/dev/null 2>&1; then
    RESTE="$RESTE unité k3s, que systemd connaît encore"
fi
for p in "${DETRUITS[@]}"; do
    if [ -e "$p" ]; then RESTE="$RESTE $p"; fi
done
ETAT_SERVICE="$(systemctl is-active k3s 2>/dev/null || true)"
if [ "$ETAT_SERVICE" = "active" ]; then RESTE="$RESTE service k3s toujours actif"; fi

if [ "$CODE_DESINSTALLATION" -ne 0 ] || [ -n "$RESTE" ]; then
    # Un 0 sans rien supprimé est la signature de l'arrêt anticipé du désinstallateur.
    CAUSE=""
    if [ "$CODE_DESINSTALLATION" -eq 0 ] && [ -e "$UNITE" ] && [ -e "$RACINE/etc/rancher/k3s" ]; then
        CAUSE=" Il n'a rien supprimé : cause probable, d'autres unités k3s*.service ou /etc/init.d/k3s* — le désinstallateur officiel refuse alors de désinstaller et sort en 0."
    fi
    die "Désinstallation incomplète (désinstallateur : code $CODE_DESINSTALLATION ; subsiste :${RESTE:- rien}).${CAUSE} Reprendre à la main, ou par le désinstallateur officiel s'il est encore en place — ce script ne supprime rien lui-même (décision 47)." 1
fi
success "K3s désinstallé : binaire, unité et répertoires de données ont disparu."
info "Docker, les règles ufw et config/ ne sont pas touchés. Réinstaller : Linux/K3s/install-k3s.sh."
