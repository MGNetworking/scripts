#!/usr/bin/env bash
set -Eeuo pipefail

# Active ufw selon la décision 21 : deny en entrée, allow en sortie, SSH ouvert
# seul d'office. Seul script du dépôt capable de couper l'accès à la machine :
# la règle SSH est posée puis relue dans « ufw status » AVANT « ufw enable », et
# le script refuse d'activer tant qu'elle n'y figure pas. Aucune règle n'est
# supprimée — ni ufw reset, ni nftables ou iptables direct.

_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_dir/lib/common.sh" ] && [ "$_dir" != "/" ]; do _dir="$(dirname "$_dir")"; done
source "$_dir/lib/common.sh"

SSH_PORT="${SRV_SSH_PORT:-22}"
PORTS="${SRV_FIREWALL_PORTS:-}"
DRY_RUN="false"; OUI="false"; ACTIVER="non"; UFW="non"; ETAT=""; PLAN=()

usage() {
    cat <<'EOF'
configure-firewall.sh — active ufw : deny en entrée, allow en sortie, SSH ouvert.

Usage : configure-firewall.sh [options]

  --port <p/tcp>      port à autoriser en plus, répétable (ex. --port 443/tcp)
  --dry-run           affiche l'état et les commandes prévues, sans rien modifier
  -y, --yes           ne pose aucune question (obligatoire hors terminal)
  -h, --help          affiche cette aide

SRV_SSH_PORT (défaut 22) et SRV_FIREWALL_PORTS, ports séparés par des espaces,
sont lus dans config/server.env, chargé par lib/common.sh.

Ordre : politiques, règle SSH, autres ports, relecture de « ufw status », puis
activation. Une règle déjà présente n'est pas reposée ; la règle SSH absente de
« ufw status » fait refuser l'activation, qui couperait sinon l'accès. Aucune
règle n'est jamais supprimée.

Codes : 0 appliqué, déjà conforme ou --dry-run ; 1 root, distribution, ufw ou
règle SSH manquants, confirmation refusée ; 2 option ou valeur mal formée.
EOF
}

valider_port() {
    [[ "$1" =~ ^([1-9][0-9]{0,4})/(tcp|udp)$ ]] || return 1
    [ "$((10#${BASH_REMATCH[1]}))" -le 65535 ]
}

# État courant relu après chaque commande : c'est cette relecture qui prouve la
# présence de la règle SSH avant l'activation.
rafraichir() { ETAT="$(ufw status verbose 2>/dev/null || true)"; }

# Présente au sens de « ufw status » : une ligne « <cible> ALLOW … ».
regle_presente() {
    printf '%s\n' "$ETAT" | awk -v r="$1" '$1 == r && $2 == "ALLOW" {t = 1} END {exit !t}'
}

# Décision 45 : un parent qui exporterait ASSUME_YES ne confirme pas ce script,
# qui peut couper l'accès à la machine ; seul --yes le fait.
export ASSUME_YES="false"
while [ "${1:-}" != "" ]; do
    case "$1" in
        --port)
            shift; [ "${1:-}" != "" ] || die "Option --port : valeur manquante." 2
            PORTS="$PORTS $1"; shift ;;
        --dry-run) DRY_RUN="true"; shift ;;
        -y|--yes)  export ASSUME_YES="true"; OUI="true"; shift ;;
        -h|--help) usage; exit 0 ;;
        *) die "Option inconnue : $1" 2 ;;
    esac
done

if ! [[ "$SSH_PORT" =~ ^[1-9][0-9]{0,4}$ ]] || [ "$((10#$SSH_PORT))" -gt 65535 ]; then
    die "Port SSH mal formé : $SSH_PORT (entier de 1 à 65535 attendu)" 2
fi

# Un port peut venir de SRV_FIREWALL_PORTS et d'un --port : une règle, une fois.
AUTRES=""
for p in $PORTS; do
    valider_port "$p" || die "Port mal formé : $p (forme attendue : 443/tcp)" 2
    case " $AUTRES " in *" $p "*) ;; *) AUTRES="$AUTRES $p" ;; esac
done

# --dry-run ne modifie rien : il ne réclame ni root ni ufw, il décrit.
if [ "$DRY_RUN" != "true" ]; then
    require_root
    require_os debian ubuntu
fi

if command -v ufw >/dev/null 2>&1; then UFW="oui"; fi
if [ "$UFW" = "non" ] && [ "$DRY_RUN" != "true" ]; then
    info "ufw absent : installation par apt-get."
    run_logged apt-get update
    run_logged apt-get install -y ufw
    command -v ufw >/dev/null 2>&1 || die "ufw reste introuvable après l'installation." 1
    UFW="oui"
fi
if [ "$UFW" = "oui" ]; then
    rafraichir
elif [ "$DRY_RUN" = "true" ]; then
    info "[dry-run] ufw absent : il serait installé par apt-get, puis les règles posées."
fi

# Planification — l'ordre du tableau est celui des commandes passées.
if [[ "$ETAT" == *"deny (incoming)"* ]]; then info "Politique entrante déjà deny : non reposée."
else PLAN+=("default deny incoming"); fi
if [[ "$ETAT" == *"allow (outgoing)"* ]]; then info "Politique sortante déjà allow : non reposée."
else PLAN+=("default allow outgoing"); fi

SSH_CIBLE="$SSH_PORT/tcp"
if regle_presente "$SSH_CIBLE"; then
    info "Règle SSH déjà présente : $SSH_CIBLE."
else
    PLAN+=("allow $SSH_CIBLE")
fi
for p in $AUTRES; do
    if regle_presente "$p"; then
        info "Règle déjà présente : $p — non reposée."
    else
        PLAN+=("allow $p")
    fi
done
case "$ETAT" in
    *"Status: active"*) info "ufw est déjà actif." ;;
    *)                  ACTIVER="oui" ;;
esac

{
    printf '\nÉtat actuel de ufw\n'
    if [ -n "$ETAT" ]; then printf '%s\n' "$ETAT"; else printf '  ufw absent : état inconnu\n'; fi
    printf '\nCommandes ufw prévues, dans cet ordre\n'
    if [ "${#PLAN[@]}" -eq 0 ] && [ "$ACTIVER" = "non" ]; then printf '  aucune\n'; fi
    for c in "${PLAN[@]}"; do printf '  ufw %s\n' "$c"; done
    if [ "$ACTIVER" = "oui" ]; then printf '  ufw --force enable\n'; fi
} >&2

if [ "$DRY_RUN" = "true" ]; then
    info "[dry-run] aucune commande n'a été exécutée : rien n'a été modifié."
    exit 0
fi
if [ "${#PLAN[@]}" -eq 0 ] && [ "$ACTIVER" = "non" ]; then
    success "ufw est déjà conforme : rien à faire."
    exit 0
fi
[ -t 0 ] || [ "$OUI" = "true" ] \
    || die "Règles à appliquer, et aucun terminal n'est disponible. Relancer avec --yes." 1
confirm "Appliquer ces règles et activer ufw ?" || die "Configuration abandonnée." 1

for c in "${PLAN[@]}"; do
    read -ra args <<< "$c"
    run_logged ufw "${args[@]}"
    rafraichir
done

# Le cœur de la tâche : la règle SSH relue juste avant l'activation, sans quoi
# activer couperait la session en cours.
rafraichir
if ! regle_presente "$SSH_CIBLE"; then
    die "Règle SSH $SSH_CIBLE absente de « ufw status » : activation refusée, l'accès à la machine serait coupé." 1
fi
info "Règle SSH confirmée dans « ufw status » : $SSH_CIBLE."

if [ "$ACTIVER" = "oui" ]; then
    run_logged ufw --force enable
    success "ufw activé : entrée deny, sortie allow, $SSH_CIBLE${AUTRES:+ et$AUTRES} autorisé(s)."
else
    success "Règles appliquées : ufw était déjà actif."
fi
