#!/usr/bin/env bash
set -Eeuo pipefail

# Désinstalle K3s par le désinstallateur officiel, après avoir listé ce qui sera
# détruit et obtenu une confirmation. Décision 47 : ce désinstallateur seul,
# aucune suppression écrite à la main.

_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_dir/lib/common.sh" ] && [ "$_dir" != "/" ]; do _dir="$(dirname "$_dir")"; done
source "$_dir/lib/common.sh"

# Décision 45 : un parent qui exporte ASSUME_YES ne confirme pas à ma place.
export ASSUME_YES="false"
# Un INSTALL_K3S_* ou un K3S_* hérité — URL du cluster, jeton de nœud — n'a rien
# à faire dans l'environnement du désinstallateur, ni dans le journal.
# compgen rend 1 quand rien ne correspond : c'est le cas courant.
for _p in INSTALL_K3S_ K3S_; do
    for _v in $(compgen -v "$_p" || true); do unset "$_v"; done
done
unset _p _v

DRY_RUN="false"
OUI="false"

usage() {
    cat <<'EOF'
uninstall-k3s.sh — désinstalle K3s par le désinstallateur officiel.

Usage : uninstall-k3s.sh [--dry-run] [-y|--yes] [--help]

  --dry-run   affiche ce qui serait détruit, sans rien supprimer
  -y, --yes   ne pose aucune question (obligatoire hors terminal)

Destructif : les volumes local-path des pods, sous
/var/lib/rancher/k3s/storage, disparaissent avec le reste. Aucune sauvegarde
n'est faite ici — la sauvegarde des ressources relève d'un script distinct.

Root est requis, --dry-run compris. Décision 47 : seul
/usr/local/bin/k3s-uninstall.sh supprime quelque chose, après le résumé.
K3s absent rend 0 ; un k3s sans désinstallateur est refusé en 1, sans rien
supprimer.

Codes de retour :
  0  K3s désinstallé, déjà absent, ou simulation
  1  root manquant, désinstallateur absent, confirmation refusée, échec du
     désinstallateur, ou état final incomplet
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
require_cmd du systemctl

# Surcharge de test : la racine visée ne se déplace QUE dans un conteneur. Sur
# une machine réelle, aucune variable héritée ne détourne la désinstallation.
RACINE=""
if [ -e /.dockerenv ] && [ -n "${RACINE_TEST:-}" ]; then RACINE="$RACINE_TEST"; fi

DESINSTALLATEUR="$RACINE/usr/local/bin/k3s-uninstall.sh"
UNITE="$RACINE/etc/systemd/system/k3s.service"
STORAGE="$RACINE/var/lib/rancher/k3s/storage"
# Ce que le désinstallateur officiel détruit. Cette liste ne sert QU'AU RÉSUMÉ :
# la suppression lui appartient, et c'est l'état relu après coup qui fait foi.
DONNEES=("$RACINE/etc/rancher/k3s" "$RACINE/var/lib/rancher/k3s" "$RACINE/var/lib/kubelet"
         "$RACINE/var/lib/cni" "$RACINE/var/log/pods" "$RACINE/var/log/containers")

BINAIRE=""
if command -v k3s >/dev/null 2>&1; then BINAIRE="$(command -v k3s)"; fi
if [ -z "$BINAIRE" ] && [ ! -x "$DESINSTALLATEUR" ]; then
    success "K3s n'est pas installé sur cette machine : ni binaire k3s, ni $DESINSTALLATEUR. Rien à désinstaller, rien n'a été touché."
    exit 0
fi
if [ ! -x "$DESINSTALLATEUR" ]; then
    die "Le désinstallateur officiel $DESINSTALLATEUR est absent : ce script ne supprime rien lui-même (décision 47). Rien n'a été supprimé." 1
fi

# Taille d'un chemin, ou « absente » : le résumé ne doit pas laisser croire à
# des données qui n'existent pas.
taille() {
    if [ ! -e "$1" ]; then printf 'absente'; return 0; fi
    du -sh "$1" 2>/dev/null | cut -f1 || printf 'illisible'
}

printf '\nCe que %s détruira\n\n' "$DESINSTALLATEUR"
for p in "${DONNEES[@]}"; do
    printf '  %-52s %s\n' "$p" "$(taille "$p")"
    if [ "$p" = "$RACINE/var/lib/rancher/k3s" ]; then
        printf '    %-50s %s\n' "dont $STORAGE (volumes local-path des pods)" "$(taille "$STORAGE")"
    fi
done
ETAT_SERVICE="$(systemctl is-active k3s 2>/dev/null || true)"
printf '\n  Binaire à supprimer  : %s\n  Unité à supprimer    : %s\n  État du service k3s  : %s\n  Sauvegarde préalable : aucune\n\n' \
    "${BINAIRE:-aucun}" "$UNITE" "${ETAT_SERVICE:-inconnu}"

if [ "$DRY_RUN" = "true" ]; then
    info "[dry-run] Commande prévue : $DESINSTALLATEUR"
    info "[dry-run] Aucune suppression : binaire, unité et répertoires listés sont intacts."
    exit 0
fi

[ -t 0 ] || [ "$OUI" = "true" ] \
    || die "Désinstallation à confirmer, et aucun terminal n'est disponible. Relancer avec --yes." 1
confirm "Désinstaller K3s et détruire les données listées ci-dessus ?" \
    || die "Désinstallation abandonnée : rien n'a été supprimé." 1

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
for p in "${DONNEES[@]}"; do
    if [ -e "$p" ]; then RESTE="$RESTE $p"; fi
done
ETAT_SERVICE="$(systemctl is-active k3s 2>/dev/null || true)"
if [ "$ETAT_SERVICE" = "active" ]; then RESTE="$RESTE service k3s toujours actif"; fi

if [ "$CODE_DESINSTALLATION" -ne 0 ] || [ -n "$RESTE" ]; then
    die "Désinstallation incomplète (désinstallateur : code $CODE_DESINSTALLATION ; subsiste :${RESTE:- rien}). Reprendre à la main, ou par le désinstallateur officiel s'il est encore en place — ce script ne supprime rien lui-même (décision 47)." 1
fi
success "K3s désinstallé : binaire, unité et répertoires de données ont disparu."
info "Docker, les règles ufw et config/ ne sont pas touchés. Réinstaller : Linux/K3s/install-k3s.sh."
