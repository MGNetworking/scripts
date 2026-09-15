#!/usr/bin/env bash
set -Eeuo pipefail
# manage-users.sh — compte d'administration : compte, home, shell, groupes, sudo
# et clé SSH publique, sans aucun mot de passe. Invocation nominale :
#   sudo Linux/System/manage-users.sh --utilisateur max --sudo --cle-fichier /root/max.pub

_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_dir/lib/common.sh" ] && [ "$_dir" != "/" ]; do _dir="$(dirname "$_dir")"; done
source "$_dir/lib/common.sh"

UTILISATEUR=""; CLE_FICHIER=""; SHELL_UTILISATEUR="/bin/bash"
SUDO="false"; SUDO_NOPASSWD="false"; DRY_RUN="false"
GROUPES=(); CLE_TYPE=""; CLE_BLOB=""; CLE_LIGNE=""

usage() {
    cat <<'AIDE'
Usage : manage-users.sh --utilisateur <nom> [options]
  --utilisateur <nom>        compte à créer ou à compléter
  --cle-fichier <chemin>     clé PUBLIQUE déposée dans authorized_keys
  --groupe <nom>             groupe à rejoindre — répétable, ajout seul
  --sudo                     ajoute le compte au groupe sudo
  --sudo-sans-mot-de-passe   dépose /etc/sudoers.d/mgnetworking-<nom> en 0440
  --shell <chemin>           shell de connexion — défaut /bin/bash
  --dry-run                  énumère les actions, sans rien modifier
  -h, --help                 cette aide
Défauts : SRV_ADMIN_UTILISATEUR, SRV_ADMIN_CLE_PUBLIQUE (config/server.env).
Ce que ce script ne fait pas : définir, lire, générer ou demander un mot de passe,
fabriquer une paire de clés, supprimer ou verrouiller un compte, créer un groupe,
installer sudo. Sans --sudo-sans-mot-de-passe, sudo réclame le mot de passe : tant
que « passwd <utilisateur> » n'a pas été exécuté, l'élévation interactive est refusée.
Codes : 0 conforme ; 1 prérequis manquant, rien modifié ; 2 usage refusé.
AIDE
}

while [ "${1:-}" != "" ]; do
    case "$1" in
        --utilisateur) shift; [ -n "${1:-}" ] || die "--utilisateur attend un nom de compte." 2; UTILISATEUR="$1"; shift ;;
        --cle-fichier) shift; [ -n "${1:-}" ] || die "--cle-fichier attend un chemin de clé." 2; CLE_FICHIER="$1"; shift ;;
        --groupe)      shift; [ -n "${1:-}" ] || die "--groupe attend un nom de groupe." 2; GROUPES+=("$1"); shift ;;
        --shell)       shift; [ -n "${1:-}" ] || die "--shell attend un chemin de shell." 2; SHELL_UTILISATEUR="$1"; shift ;;
        --sudo)        SUDO="true"; shift ;;
        --sudo-sans-mot-de-passe) SUDO="true"; SUDO_NOPASSWD="true"; shift ;;
        --dry-run)     DRY_RUN="true"; shift ;;
        -h|--help)     usage; exit 0 ;;
        *)             die "Option inconnue : $1" 2 ;;
    esac
done

UTILISATEUR="${UTILISATEUR:-${SRV_ADMIN_UTILISATEUR:-}}"
CLE_FICHIER="${CLE_FICHIER:-${SRV_ADMIN_CLE_PUBLIQUE:-}}"

case "$UTILISATEUR" in
    "")     die "Aucun compte demandé : --utilisateur, ou SRV_ADMIN_UTILISATEUR dans config/server.env." 2 ;;
    root)   die "« root » est refusé : ce script crée un compte non privilégié." 2 ;;
    [!a-z_]*|*[!a-z0-9_-]*) die "Nom de compte invalide : « $UTILISATEUR » — lettre minuscule ou souligné, puis lettres minuscules, chiffres, souligné ou tiret ; useradd le refuserait." 2 ;;
esac
[ "${#UTILISATEUR}" -le 32 ] || die "Nom de compte trop long : « $UTILISATEUR » — 32 au plus (règle de useradd)." 2
case "$SHELL_UTILISATEUR" in /*) ;; *) die "Shell invalide : « $SHELL_UTILISATEUR » — un chemin absolu est attendu." 2 ;; esac

# La forme d'une clé se contrôle sans ssh-keygen, absent d'une image minimale.
if [ -n "$CLE_FICHIER" ]; then
    [ -f "$CLE_FICHIER" ] || die "Clé publique introuvable : $CLE_FICHIER" 2
    mapfile -t _lignes < <(grep -vE '^[[:space:]]*(#|$)' "$CLE_FICHIER")
    [ "${#_lignes[@]}" -eq 1 ] || die "Clé publique invalide : $CLE_FICHIER — une seule ligne attendue, ${#_lignes[@]} trouvée(s)." 2
    CLE_LIGNE="${_lignes[0]}"; read -r CLE_TYPE CLE_BLOB _ <<< "$CLE_LIGNE"
    case "$CLE_TYPE" in ssh-ed25519|ssh-rsa|ecdsa-sha2-*|sk-*) ;; *) die "Type de clé inconnu : « $CLE_TYPE » — attendu ssh-ed25519, ssh-rsa, ecdsa-sha2-* ou sk-*." 2 ;; esac
    case "${CLE_BLOB:-}" in
        "")                die "Clé publique invalide : le second champ est vide." 2 ;;
        *[!A-Za-z0-9+/=]*) die "Clé publique invalide : le second champ n'est pas du base64." 2 ;;
    esac
fi

require_root
require_os debian ubuntu
require_cmd useradd usermod getent id stat cut mktemp

if [ "$SUDO" = "true" ]; then
    GROUPES+=(sudo)
    # Ni le groupe ni le paquet ne sont créés ici : le refus dit lequel manque.
    if ! getent group sudo >/dev/null 2>&1; then
        error "Le groupe « sudo » n'existe pas sur ce système, et ce script ne le crée pas."
        die "Prérequis manquant — rien n'a été modifié. Correctif : apt-get install sudo" 1
    fi
    command -v sudo >/dev/null 2>&1 || warn "Le groupe « sudo » existe, mais la commande sudo est absente : l'appartenance sera posée, l'élévation restera impossible."
fi
for groupe in "${GROUPES[@]}"; do
    getent group "$groupe" >/dev/null 2>&1 || die "Groupe « $groupe » inconnu — ce script n'en crée aucun. Rien n'a été modifié." 1
done

HOME_UTILISATEUR="/home/$UTILISATEUR"
if id -u "$UTILISATEUR" >/dev/null 2>&1; then
    if ! HOME_UTILISATEUR="$(getent passwd "$UTILISATEUR" | cut -d: -f6)"; then die "Répertoire personnel de $UTILISATEUR illisible."; fi
fi
AUTORISE="$HOME_UTILISATEUR/.ssh/authorized_keys"

executer() {
    if [ "$DRY_RUN" = "true" ]; then info "[dry-run] $*"; return 0; fi
    "$@"
}

poser_regle_sudo() {
    local fichier="/etc/sudoers.d/mgnetworking-$UTILISATEUR" tmp=""
    local attendu="# Déposé par Linux/System/manage-users.sh.
$UTILISATEUR ALL=(ALL) NOPASSWD:ALL"
    if [ -f "$fichier" ] && [ "$(cat "$fichier")" = "$attendu" ]; then info "$fichier est déjà conforme : rien à déposer."; return 0; fi
    # Nom sans point ni tilde final — sudo ignore ces fichiers sans rien dire,
    # comme cron dans /etc/cron.d — et /etc/sudoers.d vient du paquet sudo.
    [ -d /etc/sudoers.d ] || die "« /etc/sudoers.d » est absent : installez le paquet sudo — rien n'a été modifié." 1
    if [ "$DRY_RUN" = "true" ]; then
        info "[dry-run] Déposerait $fichier en 0440, root:root :"; printf '%s\n' "$attendu" | sed 's/^/    /' >&2; return 0
    fi
    tmp="$(mktemp /etc/sudoers.d/.mgnetworking-XXXXXX)"
    printf '%s\n' "$attendu" > "$tmp"; chmod 0440 "$tmp"; chown root:root "$tmp"
    # Une syntaxe fautive peut rendre sudo inutilisable pour tout le monde :
    # la règle est validée AVANT d'être mise en place.
    if command -v visudo >/dev/null 2>&1 && ! visudo -c -f "$tmp" >/dev/null 2>&1; then
        rm -f "$tmp"; die "Règle sudoers refusée par visudo — $fichier n'a pas été déposé."
    fi
    command -v visudo >/dev/null 2>&1 || warn "visudo est absent : la syntaxe de la règle n'a pas pu être vérifiée."
    mv -f "$tmp" "$fichier"; success "Règle sudo sans mot de passe déposée : $fichier"
}

# root écrit dans le home d'un utilisateur : un lien symbolique y détournerait
# l'écriture vers un fichier qu'il choisit. sshd, lui, refuse sans rien dire une
# clé mal protégée — les droits sont donc corrigés, pas seulement signalés.
deposer_cle() {
    local rep="$HOME_UTILISATEUR/.ssh" tmp=""
    [ ! -L "$rep" ] || die "« $rep » est un lien symbolique : refus d'écrire à travers. Rien n'a été modifié." 1
    [ ! -L "$AUTORISE" ] || die "« $AUTORISE » est un lien symbolique : refus d'écrire à travers. Rien n'a été modifié." 1
    if grep -qxF "$CLE_LIGNE" "$AUTORISE" 2>/dev/null; then
        info "La clé publique est déjà dans $AUTORISE : rien à déposer."
    else
        mkdir -p "$rep"
        tmp="$(mktemp "$rep/.authorized_keys.XXXXXX")"
        [ ! -f "$AUTORISE" ] || cat "$AUTORISE" > "$tmp"
        # Sans saut de ligne final, la clé se collerait à la dernière ligne.
        if [ -s "$tmp" ] && [ -n "$(tail -c 1 "$tmp")" ]; then printf '\n' >> "$tmp"; fi
        printf '%s\n' "$CLE_LIGNE" >> "$tmp"; mv -f "$tmp" "$AUTORISE"
        success "Clé publique déposée : $AUTORISE"
    fi
    chmod 0700 "$rep"; chown "$UTILISATEUR" "$rep"; chmod 0600 "$AUTORISE"; chown "$UTILISATEUR" "$AUTORISE"
}

info "Aucun mot de passe n'est défini, lu, généré ni demandé par ce script."

if id -u "$UTILISATEUR" >/dev/null 2>&1; then
    info "Le compte « $UTILISATEUR » existe déjà (UID $(id -u "$UTILISATEUR")) : rien à créer."
else
    executer useradd --create-home --shell "$SHELL_UTILISATEUR" "$UTILISATEUR"
fi

# usermod --append n'ajoute jamais qu'un groupe : aucune appartenance n'est retirée.
for groupe in "${GROUPES[@]}"; do
    if id -nG "$UTILISATEUR" | grep -qw -- "$groupe"; then
        info "$UTILISATEUR est déjà membre de « $groupe » : rien à ajouter."
    else
        executer usermod --append --groups "$groupe" "$UTILISATEUR"
    fi
done

if [ "$SUDO_NOPASSWD" = "true" ]; then poser_regle_sudo; fi

if [ -n "$CLE_FICHIER" ] && [ "$DRY_RUN" = "true" ]; then
    info "[dry-run] Créerait $HOME_UTILISATEUR/.ssh en 0700, propriétaire $UTILISATEUR."
    info "[dry-run] Ajouterait la clé $CLE_TYPE à $AUTORISE, sauf si déjà présente."
elif [ -n "$CLE_FICHIER" ]; then
    deposer_cle
fi

if [ "$DRY_RUN" = "true" ]; then info "Mode --dry-run : aucune modification effectuée."; exit 0; fi

success "Compte prêt : $UTILISATEUR — shell $(getent passwd "$UTILISATEUR" | cut -d: -f7), home $HOME_UTILISATEUR."
info "Vérifier la connexion : ssh $UTILISATEUR@$(uname -n)"
if [ -z "$CLE_FICHIER" ]; then warn "Aucune clé publique fournie : --cle-fichier reste à faire avant de durcir SSH."; fi
if [ "$SUDO_NOPASSWD" != "true" ]; then
    info "Avant de durcir SSH : « passwd $UTILISATEUR » — sans mot de passe, sudo refuse"
    info "l'élévation interactive. Sinon, relancer avec --sudo-sans-mot-de-passe."
fi
info "Étape suivante : Linux/Security/configure-ssh.sh, puis disable-root-login.sh."
