#!/usr/bin/env bash
set -Eeuo pipefail

# Durcit sshd par un fichier déposé dans sshd_config.d/ (décision 19) : mot de
# passe et clavier interactif refusés, clé publique seule, port inchangé. Deux
# verrous contre le verrouillage : un compte non-root avec sudo et clé
# (décision 20), et « sshd -t » avant rechargement, qui restaure l'état antérieur.
_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_dir/lib/common.sh" ] && [ "$_dir" != "/" ]; do _dir="$(dirname "$_dir")"; done
source "$_dir/lib/common.sh"

# Surchargeables pour que le test travaille dans un bac à sable.
SSHD_CONFIG="${SSHD_CONFIG:-/etc/ssh/sshd_config}"
SSHD_CONFIG_D="${SSHD_CONFIG_D:-/etc/ssh/sshd_config.d}"
FICHIER="$SSHD_CONFIG_D/10-mgnetworking.conf"
UTILISATEUR="${SRV_ADMIN_UTILISATEUR:-}"
DRY_RUN="false"; OUI="false"

ATTENDU="# Déposé par Linux/Security/configure-ssh.sh.
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes"

usage() {
    cat <<'EOF'
configure-ssh.sh — refuse le mot de passe SSH, garde la clé publique et le port.

Usage : configure-ssh.sh [options]

  --utilisateur <nom>  compte non-root, membre de sudo, avec clé — défaut
                       SRV_ADMIN_UTILISATEUR (config/server.env)
  --dry-run            affiche l'état et les actions prévues, sans rien modifier
  -y, --yes            ne pose aucune question (obligatoire hors terminal)
  -h, --help           affiche cette aide

Dépose <sshd_config.d>/10-mgnetworking.conf : PasswordAuthentication no,
KbdInteractiveAuthentication no, PubkeyAuthentication yes. Le port n'est jamais
touché ; fichier identique, rien n'est réécrit ni rechargé.

« sshd -t » valide la configuration avant le rechargement ; en échec, l'état
antérieur est restauré. Rechargement par « systemctl reload ssh », jamais
restart. Refus si sshd_config n'inclut pas sshd_config.d/*.conf, ou si le compte
nommé est introuvable, root, hors de sudo, ou sans clé dans authorized_keys.

Codes : 0 appliqué, conforme ou --dry-run ; 1 root, distribution, inclusion,
compte ou « sshd -t » en défaut ; 2 option ou valeur mal formée.
EOF
}

# Membre du groupe sudo : par son groupe primaire, ou listé dans le groupe.
membre_sudo() {
    local gid_sudo
    gid_sudo="$(getent group sudo 2>/dev/null | cut -d: -f3)"
    [ -n "$gid_sudo" ] || return 1
    [ "$2" = "$gid_sudo" ] && return 0
    getent group sudo 2>/dev/null | cut -d: -f4 | tr ',' '\n' | grep -qxF "$1"
}

# Décision 45 : ce script peut couper l'accès à la machine ; un ASSUME_YES
# hérité du parent ne le confirme pas, seul son propre --yes le fait.
export ASSUME_YES="false"
while [ "${1:-}" != "" ]; do
    case "$1" in
        --utilisateur)
            shift; [ "${1:-}" != "" ] || die "Option --utilisateur : valeur manquante." 2
            UTILISATEUR="$1"; shift ;;
        --dry-run) DRY_RUN="true"; shift ;;
        -y|--yes)  export ASSUME_YES="true"; OUI="true"; shift ;;
        -h|--help) usage; exit 0 ;;
        *) die "Option inconnue : $1" 2 ;;
    esac
done
case "$UTILISATEUR" in
    "") die "Aucun compte nommé : --utilisateur, ou SRV_ADMIN_UTILISATEUR dans config/server.env. Sans compte non-root à clé, refuser le mot de passe fermerait l'accès — rien n'a été modifié." 1 ;;
    root) die "« root » est refusé : la garde de la décision 20 exige un compte non-root. Rien n'a été modifié." 1 ;;
    [!a-z_]*|*[!a-z0-9_-]*) die "Nom de compte invalide : « $UTILISATEUR » — règle de useradd." 2 ;;
esac
[ "${#UTILISATEUR}" -le 32 ] || die "Nom de compte trop long : « $UTILISATEUR » — 32 au plus." 2

if [ "$DRY_RUN" != "true" ]; then
    require_root
    require_os debian ubuntu
fi

# Sans cet Include, le fichier déposé serait ignoré en silence.
[ -r "$SSHD_CONFIG" ] || die "Configuration sshd illisible : $SSHD_CONFIG — rien n'a été modifié." 1
grep -qE '^[[:space:]]*Include[[:space:]]+.*sshd_config\.d/\*\.conf' "$SSHD_CONFIG" \
    || die "$SSHD_CONFIG n'inclut pas sshd_config.d/*.conf : le fichier déposé serait ignoré. Rien n'a été modifié." 1
[ -d "$SSHD_CONFIG_D" ] || die "Répertoire absent : $SSHD_CONFIG_D — ce script ne le crée pas. Rien n'a été modifié." 1

# Décision 20 : sans compte non-root joignable par clé, refuser le mot de passe
# supprimerait le dernier moyen d'entrer.
LIGNE="$(getent passwd "$UTILISATEUR" 2>/dev/null || true)"
[ -n "$LIGNE" ] || die "Compte introuvable : « $UTILISATEUR » — le créer d'abord (Linux/System/manage-users.sh). Rien n'a été modifié." 1
UID_CIBLE="$(cut -d: -f3 <<<"$LIGNE")"
GID_CIBLE="$(cut -d: -f4 <<<"$LIGNE")"
HOME_CIBLE="$(cut -d: -f6 <<<"$LIGNE")"
[ "$UID_CIBLE" != "0" ] || die "« $UTILISATEUR » a l'UID 0 : la garde de la décision 20 exige un compte non-root. Rien n'a été modifié." 1
membre_sudo "$UTILISATEUR" "$GID_CIBLE" \
    || die "« $UTILISATEUR » n'est pas membre du groupe sudo : aucune correction ne serait possible après coup. Rien n'a été modifié." 1
AUTORISE="$HOME_CIBLE/.ssh/authorized_keys"
CLES="$(grep -cvE '^[[:space:]]*(#|$)' "$AUTORISE" 2>/dev/null || true)"
[ "${CLES:-0}" -gt 0 ] \
    || die "Aucune clé publique dans $AUTORISE : refuser le mot de passe fermerait la connexion. Rien n'a été modifié." 1

ACTUEL=""
[ ! -f "$FICHIER" ] || ACTUEL="$(cat "$FICHIER")"
CONFORME="non"; [ "$ACTUEL" != "$ATTENDU" ] || CONFORME="oui"

{
    printf '\nÉtat actuel\n'
    printf '  compte : %s — UID %s, sudo, %s clé(s) dans %s\n' "$UTILISATEUR" "$UID_CIBLE" "$CLES" "$AUTORISE"
    if [ "$CONFORME" = "oui" ]; then printf '  %s : déjà conforme\n' "$FICHIER"
    elif [ -f "$FICHIER" ]; then printf '  %s : présent, à remplacer\n' "$FICHIER"
    else printf '  %s : absent, à déposer\n' "$FICHIER"; fi
    printf '\nContenu prévu de %s\n' "$FICHIER"
    printf '%s\n' "$ATTENDU" | sed 's/^/  /'
    printf '\nActions prévues\n'
    if [ "$CONFORME" = "oui" ]; then printf '  aucune : ni écriture, ni rechargement\n'
    else printf '  dépôt en 0644 par temporaire puis mv ; sshd -t -f %s ; systemctl reload ssh\n' "$SSHD_CONFIG"; fi
} >&2

if [ "$DRY_RUN" = "true" ]; then info "[dry-run] rien n'a été exécuté ni modifié."; exit 0; fi
if [ "$CONFORME" = "oui" ]; then success "$FICHIER est déjà conforme : rien n'a été réécrit ni rechargé."; exit 0; fi
[ -t 0 ] || [ "$OUI" = "true" ] \
    || die "Fichier à déposer, et aucun terminal n'est disponible. Relancer avec --yes." 1
confirm "Déposer $FICHIER et recharger ssh ?" || die "Configuration abandonnée." 1

SAUVE=""
if [ -f "$FICHIER" ]; then
    SAUVE="$(mktemp "$SSHD_CONFIG_D/.10-mgnetworking-avant.XXXXXX")"
    cp -p "$FICHIER" "$SAUVE"
fi
TMP="$(mktemp "$SSHD_CONFIG_D/.10-mgnetworking.XXXXXX")"
printf '%s\n' "$ATTENDU" > "$TMP"
chmod 0644 "$TMP"
mv -f "$TMP" "$FICHIER"

# Second verrou : une configuration que sshd refuse fermerait toute connexion.
if sshd -t -f "$SSHD_CONFIG" >/dev/null 2>&1; then
    [ -z "$SAUVE" ] || rm -f "$SAUVE"
else
    if [ -n "$SAUVE" ]; then mv -f "$SAUVE" "$FICHIER"; else rm -f "$FICHIER"; fi
    die "« sshd -t » refuse la configuration : l'état antérieur est restauré, rien n'a été rechargé." 1
fi

run_logged systemctl reload ssh
warn "Garder la session ouverte et tester une nouvelle connexion avant de la fermer : « reload » ne coupe pas les connexions en cours, une configuration fautive se verrait à la suivante."
success "SSH durci : mot de passe et clavier interactif refusés, clé publique seule, port inchangé — $FICHIER"
