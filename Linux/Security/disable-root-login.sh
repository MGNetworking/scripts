#!/usr/bin/env bash
set -Eeuo pipefail

# Interdit la connexion SSH directe de root (décision 19) par un fichier déposé
# dans sshd_config.d/, préfixé 05 pour être lu avant les autres : sshd retient la
# première valeur obtenue. Garde de la décision 20, puis « sshd -t », « sshd -T »,
# et retour arrière si l'un des deux échoue.
_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_dir/lib/common.sh" ] && [ "$_dir" != "/" ]; do _dir="$(dirname "$_dir")"; done
source "$_dir/lib/common.sh"

# Surchargeables pour que le test travaille dans un bac à sable.
SSHD_CONFIG="${SSHD_CONFIG:-/etc/ssh/sshd_config}"
SSHD_CONFIG_D="${SSHD_CONFIG_D:-/etc/ssh/sshd_config.d}"
FICHIER="$SSHD_CONFIG_D/05-mgnetworking-root.conf"
UTILISATEUR="${SRV_ADMIN_UTILISATEUR:-}"
DRY_RUN="false"; OUI="false"

ATTENDU="# Déposé par Linux/Security/disable-root-login.sh.
PermitRootLogin no"

usage() {
    cat <<'EOF'
disable-root-login.sh — interdit la connexion SSH directe de root.

Usage : disable-root-login.sh [options]

  --utilisateur <nom>  compte non-root, membre de sudo, avec clé — défaut
                       SRV_ADMIN_UTILISATEUR (config/server.env)
  --dry-run            affiche l'état et les actions prévues, sans rien modifier
  -y, --yes            ne pose aucune question (obligatoire hors terminal)
  -h, --help           affiche cette aide

Dépose <sshd_config.d>/05-mgnetworking-root.conf : PermitRootLogin no. Le préfixe
05 le fait lire avant les autres, sshd retenant la première valeur obtenue.
Fichier identique : rien n'est réécrit ni rechargé.

« sshd -t » valide, puis « sshd -T » confirme la valeur effective ; si l'un des
deux ou « systemctl reload ssh » échoue, l'état antérieur est restauré. Jamais de
restart. Refus si sshd_config n'inclut pas sshd_config.d/*.conf, ou si le compte
nommé est introuvable, root, hors de sudo, ou sans clé.

Codes : 0 appliqué, conforme ou --dry-run ; 1 root, distribution, inclusion,
compte, « sshd -t », « sshd -T » ou rechargement en défaut ; 2 option ou valeur
mal formée.
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

# Décision 45 : un ASSUME_YES hérité du parent ne confirme pas ce script.
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
    "") die "Aucun compte nommé : --utilisateur, ou SRV_ADMIN_UTILISATEUR dans config/server.env. Sans compte non-root à clé, couper root fermerait l'accès — rien n'a été modifié." 1 ;;
    root) die "« root » est refusé : la garde de la décision 20 exige un compte non-root. Rien n'a été modifié." 1 ;;
    [!a-z_]*|*[!a-z0-9_-]*) die "Nom de compte invalide : « $UTILISATEUR » — règle de useradd." 2 ;;
esac
[ "${#UTILISATEUR}" -le 32 ] || die "Nom de compte trop long : « $UTILISATEUR » — 32 au plus." 2

if [ "$DRY_RUN" != "true" ]; then
    require_root; require_os debian ubuntu; require_cmd sshd systemctl
fi

# Sans cet Include, le dépôt serait ignoré en silence ; sshd ignore la casse.
[ -r "$SSHD_CONFIG" ] || die "Configuration sshd illisible : $SSHD_CONFIG — rien n'a été modifié." 1
grep -qiE '^[[:space:]]*Include[[:space:]]+.*sshd_config\.d/\*\.conf' "$SSHD_CONFIG" \
    || die "$SSHD_CONFIG n'inclut pas sshd_config.d/*.conf : le fichier déposé serait ignoré. Rien n'a été modifié." 1
[ -d "$SSHD_CONFIG_D" ] || die "Répertoire absent : $SSHD_CONFIG_D — ce script ne le crée pas. Rien n'a été modifié." 1

# Décision 20 : sans compte non-root joignable par clé, couper root fermerait tout.
LIGNE="$(getent passwd "$UTILISATEUR" 2>/dev/null || true)"
[ -n "$LIGNE" ] || die "Compte introuvable : « $UTILISATEUR » — le créer d'abord (Linux/System/manage-users.sh). Rien n'a été modifié." 1
IFS=: read -r _ _ UID_CIBLE GID_CIBLE _ HOME_CIBLE _ <<<"$LIGNE"
[ "$UID_CIBLE" != "0" ] || die "« $UTILISATEUR » a l'UID 0 : la garde de la décision 20 exige un compte non-root. Rien n'a été modifié." 1
membre_sudo "$UTILISATEUR" "$GID_CIBLE" \
    || die "« $UTILISATEUR » n'est pas membre du groupe sudo : aucune correction ne serait possible après coup. Rien n'a été modifié." 1
AUTORISE="$HOME_CIBLE/.ssh/authorized_keys"
CLES="$(grep -cvE '^[[:space:]]*(#|$)' "$AUTORISE" 2>/dev/null || true)"
[ "${CLES:-0}" -gt 0 ] \
    || die "Aucune clé publique dans $AUTORISE : interdire root fermerait la connexion. Rien n'a été modifié." 1

CONFORME="non"; [ "$(cat "$FICHIER" 2>/dev/null || true)" != "$ATTENDU" ] || CONFORME="oui"
{
    printf '\nÉtat actuel\n  compte : %s — UID %s, sudo, %s clé(s) dans %s\n' "$UTILISATEUR" "$UID_CIBLE" "$CLES" "$AUTORISE"
    if [ "$CONFORME" = "oui" ]; then printf '  %s : déjà conforme\n' "$FICHIER"
    elif [ -f "$FICHIER" ]; then printf '  %s : présent, à remplacer\n' "$FICHIER"
    else printf '  %s : absent, à déposer\n' "$FICHIER"; fi
    printf '\nContenu prévu de %s\n' "$FICHIER"; printf '%s\n' "$ATTENDU" | sed 's/^/  /'
    printf '\nActions prévues\n'
    if [ "$CONFORME" = "oui" ]; then printf '  aucune : ni écriture, ni rechargement\n'
    else printf '  dépôt en 0644 par temporaire puis mv ; sshd -t ; sshd -T ; systemctl reload ssh\n'; fi
} >&2

if [ "$DRY_RUN" = "true" ]; then info "[dry-run] rien n'a été exécuté ni modifié."; exit 0; fi
if [ "$CONFORME" = "oui" ]; then success "$FICHIER est déjà conforme : rien n'a été réécrit ni rechargé."; exit 0; fi
[ -t 0 ] || [ "$OUI" = "true" ] || die "Fichier à déposer, et aucun terminal disponible. Relancer avec --yes." 1
confirm "Interdire la connexion de root et recharger ssh ?" || die "Configuration abandonnée." 1

# Aucun temporaire ne survit à un échec, quel qu'en soit le code de sortie.
SAUVE=""; TMP=""
nettoyer() { [ -z "$TMP" ] || rm -f "$TMP"; [ -z "$SAUVE" ] || rm -f "$SAUVE"; }
trap nettoyer EXIT
restaurer() { if [ -n "$SAUVE" ]; then mv -f "$SAUVE" "$FICHIER"; else rm -f "$FICHIER"; fi; SAUVE=""; }
if [ -f "$FICHIER" ]; then SAUVE="$(mktemp "$SSHD_CONFIG_D/.05-mgnetworking-root-avant.XXXXXX")"; cp -p "$FICHIER" "$SAUVE"; fi
TMP="$(mktemp "$SSHD_CONFIG_D/.05-mgnetworking-root.XXXXXX")"
printf '%s\n' "$ATTENDU" > "$TMP"
chmod 0644 "$TMP"
mv -f "$TMP" "$FICHIER"; TMP=""
# Premier verrou : une configuration que sshd refuse fermerait toute connexion.
if ! ERREUR="$(sshd -t -f "$SSHD_CONFIG" 2>&1)"; then
    restaurer
    die "« sshd -t » refuse la configuration : l'état antérieur est restauré, rien n'a été rechargé. sshd dit : $ERREUR" 1
fi
# Second verrou : « sshd -t » ne dit pas quelle valeur l'emporte. Une directive de
# sshd_config placée avant l'Include primerait sur le fichier déposé.
if ! EFFECTIF="$(sshd -T -f "$SSHD_CONFIG" 2>&1)"; then
    restaurer
    die "« sshd -T » n'a pas pu établir la configuration effective : l'état antérieur est restauré, rien n'a été rechargé. sshd dit : $EFFECTIF" 1
fi
VALEUR="$(printf '%s\n' "$EFFECTIF" | awk 'tolower($1) == "permitrootlogin" { print tolower($2); exit }')"
if [ "$VALEUR" != "no" ]; then
    restaurer
    die "« sshd -T » annonce permitrootlogin ${VALEUR:-absent} : une directive de $SSHD_CONFIG prime sur $FICHIER. L'état antérieur est restauré, rien n'a été rechargé." 1
fi
# Troisième verrou : sans rechargement, sshd n'a pas relu le fichier, et le laisser
# en place ferait dire « déjà conforme » à la relance.
if ! run_logged systemctl reload ssh; then
    restaurer
    die "« systemctl reload ssh » a échoué : l'état antérieur est restauré, sshd garde sa configuration en vigueur. Vérifier « systemctl status ssh »." 1
fi
warn "Garder la session ouverte et tester une connexion avec « $UTILISATEUR » avant de la fermer : « reload » ne coupe pas les connexions en cours, le refus de root se verra à la suivante."
success "Connexion directe de root interdite — $FICHIER"
