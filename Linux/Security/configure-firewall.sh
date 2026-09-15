#!/usr/bin/env bash
set -Eeuo pipefail

# Active ufw selon la décision 21 : deny en entrée, allow en sortie, SSH ouvert
# seul d'office. Seul script du dépôt capable de couper l'accès à la machine : la
# règle SSH est posée avant toute politique, relue dans « ufw show added » — lisible
# ufw actif comme inactif — avant « ufw enable ». Rien n'est jamais supprimé.
_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_dir/lib/common.sh" ] && [ "$_dir" != "/" ]; do _dir="$(dirname "$_dir")"; done
source "$_dir/lib/common.sh"

SSH_PORT="${SRV_SSH_PORT:-22}"
PORTS="${SRV_FIREWALL_PORTS:-}"
DEFAUT_UFW="${UFW_DEFAUT:-/etc/default/ufw}"
DRY_RUN="false"; OUI="false"; ACTIVER="non"; LISIBLE="oui"; IPV6="non"
ETAT=""; AJOUTE=""; DENY_SSH=""; PLAN=()

usage() {
    cat <<'EOF'
configure-firewall.sh — active ufw : deny en entrée, allow en sortie, SSH ouvert.

Usage : configure-firewall.sh [options]

  --port <p/tcp>   port à autoriser en plus, répétable (ex. --port 443/tcp)
  --dry-run        affiche l'état et les commandes prévues, sans rien modifier
  -y, --yes        ne pose aucune question (obligatoire hors terminal)
  -h, --help       affiche cette aide

SRV_SSH_PORT (défaut 22) et SRV_FIREWALL_PORTS, ports séparés par des espaces,
viennent de config/server.env, chargé par lib/common.sh.

La règle SSH est posée avant toute politique, puis relue dans « ufw show added »
avant l'activation ; absente, l'activation est refusée. Une règle déjà présente
n'est pas reposée, et rien n'est jamais supprimé.

Codes : 0 appliqué, conforme ou --dry-run ; 1 root, distribution, ufw, règle SSH
ou port d'écoute de sshd en défaut, confirmation refusée ; 2 option ou valeur
mal formée.
EOF
}

valider_port() {
    [[ "$1" =~ ^([1-9][0-9]{0,4})/(tcp|udp)$ ]] || return 1
    [ "$((10#${BASH_REMATCH[1]}))" -le 65535 ]
}

# Port réellement écouté : « sshd -T » sans lancer le démon, « ss -tlnp » à défaut.
# Invérifiable, on le dit sans bloquer — la relecture de la règle SSH, elle, bloque.
port_sshd() {
    local p=""
    p="$({ sshd -T 2>/dev/null || ss -tlnp 2>/dev/null; } | awk \
        '$1 == "port" {print $2; exit} /sshd/ {sub(/.*:/, "", $4); print $4; exit}')" || p=""
    printf '%s' "$p"
}

# « ufw status » est muet sur les règles tant qu'ufw est inactif ; « ufw show
# added » les donne dans les deux cas. Un échec de lecture n'est pas masqué.
rafraichir() {
    LISIBLE="oui"
    ETAT="$(ufw status verbose 2>/dev/null)" || LISIBLE="non"
    AJOUTE="$(ufw show added 2>/dev/null)" || LISIBLE="non"
}

# Autorisation du port depuis n'importe où : une restriction — « from
# 192.168.1.0/24 » — ne compte pas. Avec IPV6=yes, ufw pose aussi la règle v6.
regle_presente() {
    printf '%s\n' "$AJOUTE" | grep -qxF "ufw allow $1" || return 1
    [ "$IPV6" = "non" ] || printf '%s\n' "$AJOUTE" | grep -qxF "ufw allow $1 (v6)"
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
AUTRES=""
for p in $PORTS; do
    valider_port "$p" || die "Port mal formé : $p (forme attendue : 443/tcp)" 2
    case " $AUTRES " in *" $p "*) ;; *) AUTRES="$AUTRES $p" ;; esac
done

if [ "$DRY_RUN" != "true" ]; then
    require_root
    require_os debian ubuntu
    REEL="$(port_sshd)"
    if [ -z "$REEL" ]; then
        warn "Port d'écoute de sshd invérifiable : SRV_SSH_PORT n'a pas été confronté au démon."
    elif [ "$REEL" != "$SSH_PORT" ]; then
        die "SRV_SSH_PORT=$SSH_PORT, port d'écoute de sshd=$REEL : refus, rien n'a été modifié." 1
    fi
fi

if [ -r "$DEFAUT_UFW" ] && grep -q '^IPV6=yes' "$DEFAUT_UFW"; then IPV6="oui"; fi
if command -v ufw >/dev/null 2>&1; then UFW="oui"; else UFW="non"; fi
if [ "$UFW" = "non" ] && [ "$DRY_RUN" != "true" ]; then
    info "ufw absent : installation par apt-get."
    run_logged apt-get update
    run_logged apt-get install -y ufw
    command -v ufw >/dev/null 2>&1 || die "ufw reste introuvable après l'installation." 1
    UFW="oui"
fi
[ "$UFW" != "oui" ] || rafraichir
[ "$UFW" != "non" ] || [ "$DRY_RUN" != "true" ] \
    || info "[dry-run] ufw absent : il serait installé par apt-get, puis les règles posées."

# La règle SSH d'abord, avant toute politique : entre deux commandes, l'entrée ne
# doit jamais être fermée alors que le port d'administration n'est pas ouvert.
SSH_CIBLE="$SSH_PORT/tcp"
if regle_presente "$SSH_CIBLE"; then info "Règle SSH déjà présente : $SSH_CIBLE."
else PLAN+=("allow $SSH_CIBLE"); fi
for p in $AUTRES; do
    if regle_presente "$p"; then info "Règle déjà présente : $p — non reposée."
    else PLAN+=("allow $p"); fi
done
if [[ "$ETAT" == *"deny (incoming)"* ]]; then info "Politique entrante déjà deny : non reposée."
else PLAN+=("default deny incoming"); fi
if [[ "$ETAT" == *"allow (outgoing)"* ]]; then info "Politique sortante déjà allow : non reposée."
else PLAN+=("default allow outgoing"); fi
case "$ETAT" in
    *"Status: active"*) info "ufw est déjà actif." ;;
    *)                  ACTIVER="oui" ;;
esac

# Une règle deny sur ce port l'emporterait sur la nôtre : refuser en la nommant
# vaut mieux qu'activer un ufw qui couperait l'accès sans retour.
DENY_SSH="$(printf '%s\n' "$AJOUTE" | awk -v c="$SSH_CIBLE" '$1 == "ufw" && $2 == "deny" && ($3 == c || $0 ~ ("port " c " ")) {print; exit}')"

{
    printf '\nÉtat actuel de ufw\n'
    if [ "$LISIBLE" = "non" ]; then printf "  illisible : ufw n’a rien rendu\n"
    elif [ -n "$ETAT" ]; then printf '%s\n' "$ETAT"
    else printf '  ufw absent : état inconnu\n'; fi
    printf '\nCommandes ufw prévues, dans cet ordre\n'
    [ "${#PLAN[@]}" -gt 0 ] || [ "$ACTIVER" = "oui" ] || printf '  aucune\n'
    for c in "${PLAN[@]}"; do printf '  ufw %s\n' "$c"; done
    [ "$ACTIVER" != "oui" ] || printf '  ufw --force enable\n'
    [ -z "$DENY_SSH" ] || printf '  refus : « %s » porte déjà sur %s\n' "$DENY_SSH" "$SSH_CIBLE"
} >&2

if [ "$DRY_RUN" = "true" ]; then info "[dry-run] rien n'a été exécuté ni modifié."; exit 0; fi
[ -z "$DENY_SSH" ] || die "« $DENY_SSH » existe déjà sur $SSH_CIBLE : ufw garderait la sienne, la retirer d'abord." 1
[ "${#PLAN[@]}" -gt 0 ] || [ "$ACTIVER" = "oui" ] || { success "ufw est déjà conforme : rien à faire."; exit 0; }
[ -t 0 ] || [ "$OUI" = "true" ] \
    || die "Règles à appliquer, et aucun terminal n'est disponible. Relancer avec --yes." 1
confirm "Appliquer ces règles et activer ufw ?" || die "Configuration abandonnée." 1

for c in "${PLAN[@]}"; do
    read -ra args <<< "$c"
    run_logged ufw "${args[@]}"
done
rafraichir
if ! regle_presente "$SSH_CIBLE"; then
    die "Règle SSH $SSH_CIBLE absente de « ufw show added » : activation refusée, l'accès serait coupé." 1
fi
info "Règle SSH confirmée dans « ufw show added » : $SSH_CIBLE."
[ "$ACTIVER" != "oui" ] || run_logged ufw --force enable
success "ufw en place : entrée deny, sortie allow, $SSH_CIBLE${AUTRES:+ et$AUTRES} autorisé(s)."
