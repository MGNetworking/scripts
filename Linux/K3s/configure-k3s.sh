#!/usr/bin/env bash
set -Eeuo pipefail

# Écrit /etc/rancher/k3s/config.yaml (décision 47). Le fichier appartient au
# script entier : il est produit, jamais édité. K3s ne le relit qu'au démarrage.

_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_dir/lib/common.sh" ] && [ "$_dir" != "/" ]; do _dir="$(dirname "$_dir")"; done
source "$_dir/lib/common.sh"

# Surchargeables : le fichier de cas travaille dans un bac à sable, hors de /etc.
CONFIG_DIR="${K3S_CONFIG_DIR:-/etc/rancher/k3s}"
FICHIER="$CONFIG_DIR/config.yaml"
SAN_LISTE="${SRV_K3S_TLS_SAN:-}"
MODE="600"
DRY_RUN="false"; OUI="false"

usage() {
    cat <<'EOF'
configure-k3s.sh — tient /etc/rancher/k3s/config.yaml (décision 47).

Usage : configure-k3s.sh [--dry-run] [-y|--yes] [--help]

  --dry-run   affiche la différence avec le fichier en place, sans rien écrire
  -y, --yes   ne pose aucune question (obligatoire hors terminal)

Le fichier appartient à ce script, entier : écrit par temporaire puis mv, en
0600, jamais complété ni fusionné. Deux clés, et rien d'autre :
  write-kubeconfig-mode: "0600"
  tls-san                noms d'hôte et adresses IP de SRV_K3S_TLS_SAN
                         (config/server.env, virgules) ; omise si vide.

Contenu identique, droits compris : rien n'est réécrit ni redémarré, seuls les
droits sont corrigés. Contenu différent : différence affichée, original
sauvegardé en <config.yaml>.<horodatage>.bak, K3s redémarré, diagnostic demandé
à Linux/K3s/verify-k3s.sh — en échec, original restauré.

Codes de retour :
  0  configuration écrite, déjà conforme, ou --dry-run
  1  privilège manquant, K3s absent, redémarrage ou diagnostic en échec
  2  option inconnue, ou valeur mal formée dans config/
EOF
}

# Décision 45 : un ASSUME_YES hérité du parent ne confirme pas ce script.
export ASSUME_YES="false"
while [ "${1:-}" != "" ]; do
    case "$1" in
        --dry-run) DRY_RUN="true"; shift ;;
        -y|--yes)  export ASSUME_YES="true"; OUI="true"; shift ;;
        --help|-h) usage; exit 0 ;;
        *) die "Option inconnue : $1" 2 ;;
    esac
done

est_ipv4() {
    local -a octets; IFS='.' read -r -a octets <<<"$1"
    [ "${#octets[@]}" -eq 4 ] || return 1
    local o
    for o in "${octets[@]}"; do
        case "$o" in ""|*[!0-9]*|????*) return 1 ;; esac
        [ "$((10#$o))" -le 255 ] || return 1
    done
}

# Deux « : » au moins, sans quoi « cafe1 » passerait pour une IPv6.
est_ipv6() {
    case "$1" in *[!0-9A-Fa-f:]*) return 1 ;; esac
    local colons="${1//[!:]}"
    [ "${#colons}" -ge 2 ]
}

# Au moins une lettre, sans quoi « 10.0.0.999 » passerait pour un nom d'hôte.
est_hote() {
    case "$1" in ""|.*|*.|*..*|*[!A-Za-z0-9.-]*) return 1 ;; esac
    case "$1" in *[A-Za-z]*) ;; *) return 1 ;; esac
    local -a labels; IFS='.' read -r -a labels <<<"$1"
    local l
    for l in "${labels[@]}"; do
        case "$l" in ""|*[!A-Za-z0-9-]*|-*|*-) return 1 ;; esac
        [ "${#l}" -le 63 ] || return 1
    done
}

# Chaque entrée est recopiée telle quelle dans un YAML, puis atteint le
# démarrage de K3s : elle doit être un nom d'hôte, une IPv4 ou une IPv6.
SAN=()
if [ -n "$SAN_LISTE" ]; then
    case "$SAN_LISTE" in *,) die "SRV_K3S_TLS_SAN mal formée (config/server.env) : virgule finale. Rien n'a été écrit." 2 ;; esac
    IFS=',' read -r -a SAN <<<"$SAN_LISTE"
    for entree in "${SAN[@]}"; do
        est_ipv4 "$entree" || est_ipv6 "$entree" || est_hote "$entree" \
            || die "SRV_K3S_TLS_SAN mal formée (config/server.env) : « $entree » n'est ni un nom d'hôte ni une adresse IP. Rien n'a été écrit." 2
    done
fi

[ "$DRY_RUN" = "true" ] || { require_root; require_cmd systemctl diff install mktemp stat; }
command -v k3s >/dev/null 2>&1 \
    || die "K3s n'est pas installé sur cette machine : il n'y a rien à configurer. L'installation relève de Linux/K3s/install-k3s.sh." 1

contenu() {
    printf '# Généré par Linux/K3s/configure-k3s.sh — toute modification manuelle sera écrasée.\nwrite-kubeconfig-mode: "0600"\n'
    if [ "${#SAN[@]}" -gt 0 ]; then
        printf 'tls-san:\n'
        for entree in "${SAN[@]}"; do printf '  - "%s"\n' "$entree"; done
    fi
}
ATTENDU="$(contenu)"
droits() { stat -c '%a' "$FICHIER" 2>/dev/null || true; }

# cat échoue sur un fichier absent : la chaîne vide qui en revient n'est jamais le contenu attendu.
if [ "$(cat "$FICHIER" 2>/dev/null || true)" = "$ATTENDU" ]; then
    if [ "$(droits)" = "$MODE" ]; then
        success "$FICHIER est déjà conforme, droits compris : rien n'a été réécrit, rien n'a été redémarré."
        exit 0
    fi
    if [ "$DRY_RUN" = "true" ]; then
        info "[dry-run] $FICHIER a le bon contenu mais pas les droits $MODE : ils seraient corrigés. Rien n'a été écrit."
        exit 0
    fi
    chmod "$MODE" "$FICHIER"
    success "$FICHIER avait déjà le bon contenu : seuls ses droits ont été mis à $MODE, sans réécriture ni redémarrage."
    exit 0
fi

{
    printf '\nConfiguration en place et contenu prévu de %s\n' "$FICHIER"
    if [ -e "$FICHIER" ]; then
        code=0
        diff -u "$FICHIER" <(printf '%s\n' "$ATTENDU") || code=$?
        # 1 est le code de « les deux textes diffèrent » : le seul attendu ici.
        [ "$code" -le 1 ] || die "La différence n'a pas pu être affichée (diff, code $code) : rien n'a été écrit." 1
    else
        printf '  (fichier absent)\n%s\n' "$ATTENDU"
    fi
} >&2

if [ "$DRY_RUN" = "true" ]; then
    info "[dry-run] $FICHIER serait remplacé, l'original sauvegardé, puis K3s redémarré et son diagnostic demandé. Rien n'a été écrit."
    exit 0
fi

[ -t 0 ] || [ "$OUI" = "true" ] \
    || die "Écriture à confirmer, et aucun terminal n'est disponible. Relancer avec --yes." 1
confirm "Écrire $FICHIER et redémarrer K3s ?" || die "Configuration abandonnée." 1

install -d -m 0755 "$CONFIG_DIR"
TMP=""
nettoyer() { [ -z "$TMP" ] || rm -f "$TMP"; }
trap nettoyer EXIT
TMP="$(mktemp "$CONFIG_DIR/.config.yaml.XXXXXX")"
printf '%s\n' "$ATTENDU" > "$TMP"

sauvegarde=""
if [ -e "$FICHIER" ]; then
    sauvegarde="$FICHIER.$(date '+%Y%m%d-%H%M%S').bak"
    cp -p "$FICHIER" "$sauvegarde"
    info "Original sauvegardé : $sauvegarde"
fi
mv -f "$TMP" "$FICHIER"; TMP=""
chmod "$MODE" "$FICHIER"
info "$FICHIER écrit."

# Sans cette reprise, un k3s arrêté par un fichier refusé le resterait, alors que
# la configuration fautive vient d'être retirée.
restaurer() {
    if [ -n "$sauvegarde" ]; then
        mv -f "$sauvegarde" "$FICHIER"
        warn "Configuration précédente restaurée depuis $sauvegarde."
    else
        rm -f "$FICHIER"
        warn "$FICHIER retiré : aucun original à restaurer."
    fi
    run_logged systemctl restart k3s \
        || warn "K3s n'a pas pu être relancé avec la configuration précédente."
}

run_logged systemctl restart k3s \
    || { restaurer; die "Le redémarrage de k3s a échoué : la configuration écrite a été retirée." 1; }
bash "$SCRIPTS_ROOT/Linux/K3s/verify-k3s.sh" \
    || { restaurer; die "Le diagnostic du cluster échoue après redémarrage : l'original a été restauré." 1; }
success "K3s configuré : write-kubeconfig-mode $MODE${SAN_LISTE:+, tls-san $SAN_LISTE}."
