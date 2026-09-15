#!/usr/bin/env bash
# manage-users.sh — crée un compte d'administration : compte, répertoire personnel,
# shell, groupes, appartenance à sudo, clé SSH publique. Aucun mot de passe n'est
# défini, lu, généré ni demandé.
#
# L'invocation qui satisfait la garde de Linux/Security/configure-ssh.sh (décision 20) :
#   sudo Linux/System/manage-users.sh --utilisateur max --sudo --cle-fichier /root/max.pub
#
# Idempotent : relançable sans effet de bord.

set -Eeuo pipefail

_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_dir/lib/common.sh" ] && [ "$_dir" != "/" ]; do _dir="$(dirname "$_dir")"; done
source "$_dir/lib/common.sh"

UTILISATEUR=""; CLE_FICHIER=""; SHELL_UTILISATEUR="/bin/bash"
SUDO="false"; SUDO_NOPASSWD="false"; DRY_RUN="false"
GROUPES=(); CLE_TYPE=""; CLE_BLOB=""; CLE_LIGNE=""

usage() {
    cat <<'AIDE'
Usage : manage-users.sh --utilisateur <nom> [options]

Crée un compte d'administration non privilégié, utilisable par clé SSH.
--utilisateur vient de la ligne de commande, sinon de SRV_ADMIN_UTILISATEUR
(config/server.env) ; --cle-fichier, sinon de SRV_ADMIN_CLE_PUBLIQUE.

  --utilisateur <nom>      compte à créer ou à compléter
  --cle-fichier <chemin>   clé PUBLIQUE déposée dans authorized_keys
  --groupe <nom>           groupe à rejoindre — répétable, ajout seul
  --sudo                   ajoute le compte au groupe sudo
  --sudo-sans-mot-de-passe dépose /etc/sudoers.d/mgnetworking-<nom> en 0440
  --shell <chemin>         shell de connexion — défaut /bin/bash
      --dry-run            énumère les actions, sans rien modifier
  -h, --help               cette aide

Ce que ce script ne fait pas : définir, lire, générer ou demander un mot de passe,
fabriquer une paire de clés, supprimer ou verrouiller un compte, créer un groupe,
installer le paquet sudo. Sans --sudo-sans-mot-de-passe, sudo réclame le mot de
passe du compte : tant que « passwd <utilisateur> » n'a pas été exécuté,
l'élévation interactive est refusée — NOPASSWD n'est jamais déposé par défaut.

Codes de retour : 0 créé ou déjà conforme ; 1 privilège ou prérequis manquant et
rien n'a été modifié ; 2 usage — nom, clé, shell ou option refusés.
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

# Règles de nommage de useradd : lettre minuscule ou souligné, puis lettres
# minuscules, chiffres, souligné et tiret, 32 caractères au plus.
case "$UTILISATEUR" in
    "")     die "Aucun compte demandé : --utilisateur, ou SRV_ADMIN_UTILISATEUR dans config/server.env." 2 ;;
    root)   die "« root » est refusé : ce script crée un compte non privilégié." 2 ;;
    [!a-z_]*|*[!a-z0-9_-]*) die "Nom de compte invalide : « $UTILISATEUR » — lettre minuscule ou souligné, puis lettres minuscules, chiffres, souligné ou tiret ; useradd le refuserait." 2 ;;
esac
[ "${#UTILISATEUR}" -le 32 ] || die "Nom de compte trop long : « $UTILISATEUR » — 32 au plus (règle de useradd)." 2
case "$SHELL_UTILISATEUR" in
    /*) ;;
    *)  die "Shell invalide : « $SHELL_UTILISATEUR » — un chemin absolu est attendu." 2 ;;
esac

# La forme d'une clé se contrôle sans ssh-keygen, absent d'une image minimale : un
# type connu, un second champ en base64, un commentaire facultatif.
valider_cle() {
    local ligne="" type="" blob=""
    local -a lignes=()
    [ -f "$1" ] || die "Clé publique introuvable : $1" 2
    while IFS= read -r ligne; do
        case "$ligne" in ''|'#'*) continue ;; esac
        lignes+=("$ligne")
    done < "$1"
    [ "${#lignes[@]}" -eq 1 ] || die "Clé publique invalide : $1 — une seule ligne attendue, ${#lignes[@]} trouvée(s)." 2
    read -r type blob _ <<< "${lignes[0]}"
    case "$type" in
        ssh-ed25519|ssh-rsa|ecdsa-sha2-*|sk-ssh-ed25519@openssh.com|sk-ecdsa-sha2-nistp256@openssh.com) ;;
        *) die "Type de clé inconnu : « $type » — attendu ssh-ed25519, ssh-rsa, ecdsa-sha2-* ou sk-*." 2 ;;
    esac
    case "$blob" in
        "") die "Clé publique invalide : le second champ est vide." 2 ;;
        *[!A-Za-z0-9+/=]*) die "Clé publique invalide : le second champ n'est pas du base64." 2 ;;
    esac
    CLE_TYPE="$type"; CLE_BLOB="$blob"; CLE_LIGNE="${lignes[0]}"
}
if [ -n "$CLE_FICHIER" ]; then valider_cle "$CLE_FICHIER"; fi

require_root
require_os debian ubuntu
require_cmd useradd usermod getent id stat

if [ "$SUDO" = "true" ]; then
    GROUPES+=(sudo)
    # Le groupe n'est jamais créé, le paquet jamais installé : le refus le dit.
    if ! getent group sudo >/dev/null 2>&1; then
        error "Le groupe « sudo » n'existe pas sur ce système, et ce script ne le crée pas."
        die "Prérequis manquant — rien n'a été modifié. Correctif : apt-get install sudo" 1
    fi
    command -v sudo >/dev/null 2>&1 || {
        warn "Le groupe « sudo » existe, mais la commande sudo est absente : l'appartenance"
        warn "sera posée, l'élévation restera impossible. Correctif : apt-get install sudo"
    }
fi

COMPTE_EXISTE="false"
if id -u "$UTILISATEUR" >/dev/null 2>&1; then COMPTE_EXISTE="true"; fi

# Home prévisible quand le compte n'existe pas : celui que posera --create-home, et
# que --dry-run doit pouvoir annoncer.
HOME_UTILISATEUR="/home/$UTILISATEUR"
if [ "$COMPTE_EXISTE" = "true" ]; then
    if ! HOME_UTILISATEUR="$(getent passwd "$UTILISATEUR" | cut -d: -f6)"; then
        die "Répertoire personnel de $UTILISATEUR illisible : « getent » a échoué."
    fi
fi
AUTORISE="$HOME_UTILISATEUR/.ssh/authorized_keys"

est_membre() {
    local groupes=""
    if ! groupes="$(id -nG "$1" 2>/dev/null)"; then return 1; fi
    case " $groupes " in *" $2 "*) return 0 ;; esac
    return 1
}

cle_deja_presente() {
    local ligne=""
    [ -f "$1" ] || return 1
    while IFS= read -r ligne; do
        case " $ligne " in *" $2 "*) return 0 ;; esac
    done < "$1"
    return 1
}

executer() {
    local description="$1"; shift
    if [ "$DRY_RUN" = "true" ]; then info "[dry-run] $description"; return 0; fi
    if ! "$@"; then die "Échec : $description"; fi
}

deposer_cle() {
    local rep="$HOME_UTILISATEUR/.ssh" tmp=""
    if [ "$DRY_RUN" = "true" ]; then
        info "[dry-run] Créerait $rep en 0700, propriétaire $UTILISATEUR."
        info "[dry-run] Ajouterait la clé $CLE_TYPE à $AUTORISE (0600, propriétaire $UTILISATEUR)."
        return 0
    fi
    mkdir -p "$rep"; chmod 0700 "$rep"; chown "$UTILISATEUR" "$rep"
    # Construit à côté puis renommé : un authorized_keys à demi écrit refuse la
    # connexion. Le nom temporaire commence par un point, sshd l'ignore.
    tmp="$rep/.authorized_keys.$$"
    if [ -f "$AUTORISE" ]; then cp "$AUTORISE" "$tmp"; else : > "$tmp"; fi
    printf '%s\n' "$CLE_LIGNE" >> "$tmp"
    chmod 0600 "$tmp"; chown "$UTILISATEUR" "$tmp"; mv -f "$tmp" "$AUTORISE"
    success "Clé publique déposée : $AUTORISE"
}

poser_regle_sudo() {
    # Nom sans point et sans tilde final : sudo ignore ces fichiers sans rien dire,
    # exactement comme cron dans /etc/cron.d.
    local repertoire="/etc/sudoers.d"
    local fichier="$repertoire/mgnetworking-$UTILISATEUR"
    local tmp="$repertoire/.mgnetworking-$UTILISATEUR.$$"
    local attendu=""
    attendu="$(printf '# Déposé par Linux/System/manage-users.sh.\n%s ALL=(ALL) NOPASSWD:ALL\n' "$UTILISATEUR")"
    if [ -f "$fichier" ] && [ "$(cat "$fichier")" = "$attendu" ]; then
        info "$fichier est déjà conforme : rien à déposer."
        return 0
    fi
    # Le paquet sudo pose ce répertoire ; sans lui, une règle n'aurait nulle part où
    # vivre. Le créer n'installe rien.
    if [ ! -d "$repertoire" ]; then
        if [ "$DRY_RUN" = "true" ]; then
            info "[dry-run] Créerait $repertoire en 0755, root:root."
        else
            install -d -m 0755 -o root -g root "$repertoire"
        fi
    fi
    if [ "$DRY_RUN" = "true" ]; then
        info "[dry-run] Déposerait $fichier en 0440, root:root :"
        printf '%s\n' "$attendu" | sed 's/^/    /' >&2
        return 0
    fi
    printf '%s\n' "$attendu" > "$tmp"; chmod 0440 "$tmp"; chown root:root "$tmp"
    # Une syntaxe fautive peut rendre sudo inutilisable pour tout le monde : la règle
    # est validée AVANT d'être mise en place.
    if command -v visudo >/dev/null 2>&1; then
        if ! visudo -c -f "$tmp" >/dev/null 2>&1; then
            rm -f "$tmp"
            die "Règle sudoers refusée par visudo — $fichier n'a pas été déposé."
        fi
    else
        warn "visudo est absent : la syntaxe de la règle n'a pas pu être vérifiée."
    fi
    mv -f "$tmp" "$fichier"
    success "Règle sudo sans mot de passe déposée : $fichier"
}

info "Aucun mot de passe n'est défini, lu, généré ni demandé par ce script."

if [ "$COMPTE_EXISTE" = "true" ]; then
    info "Le compte « $UTILISATEUR » existe déjà (UID $(id -u "$UTILISATEUR")) : rien à créer."
else
    executer "useradd --create-home --shell $SHELL_UTILISATEUR $UTILISATEUR" \
        useradd --create-home --shell "$SHELL_UTILISATEUR" "$UTILISATEUR"
fi

# usermod --append n'ajoute jamais qu'un groupe : aucune appartenance n'est retirée.
for groupe in "${GROUPES[@]}"; do
    if ! getent group "$groupe" >/dev/null 2>&1; then
        warn "Groupe introuvable : « $groupe » — ignoré, ce script ne crée aucun groupe."
    elif est_membre "$UTILISATEUR" "$groupe"; then
        info "$UTILISATEUR est déjà membre de « $groupe » : rien à ajouter."
    else
        executer "usermod --append --groups $groupe $UTILISATEUR" \
            usermod --append --groups "$groupe" "$UTILISATEUR"
    fi
done

if [ "$SUDO_NOPASSWD" = "true" ]; then poser_regle_sudo; fi

if [ -z "$CLE_FICHIER" ]; then
    warn "Aucune clé publique fournie : le compte ne pourra pas se connecter par clé."
elif cle_deja_presente "$AUTORISE" "$CLE_BLOB"; then
    info "La clé publique est déjà dans $AUTORISE : rien à déposer."
else
    deposer_cle
fi

if [ "$DRY_RUN" = "true" ]; then
    info "Mode --dry-run : aucune modification effectuée."
    exit 0
fi

MODE_AUTORISE=""
if [ -n "$CLE_FICHIER" ]; then
    if ! MODE_AUTORISE="$(stat -c '%a %U' "$AUTORISE" 2>/dev/null)"; then
        die "État de $AUTORISE illisible : « stat » a échoué."
    fi
    if [ "$MODE_AUTORISE" != "600 $UTILISATEUR" ]; then
        die "$AUTORISE devrait être en 0600 et appartenir à $UTILISATEUR (actuellement $MODE_AUTORISE)."
    fi
fi
id -u "$UTILISATEUR" >/dev/null 2>&1 || die "Le compte $UTILISATEUR est absent après création."

success "Compte prêt : $UTILISATEUR (shell $SHELL_UTILISATEUR, home $HOME_UTILISATEUR)."
info "Vérifier la connexion : ssh $UTILISATEUR@$(uname -n)"
if [ "$SUDO_NOPASSWD" != "true" ]; then
    info "Avant de durcir SSH : « passwd $UTILISATEUR » — sans mot de passe, sudo refuse"
    info "l'élévation interactive. Sinon, relancer avec --sudo-sans-mot-de-passe."
fi
info "Étape suivante : Linux/Security/configure-ssh.sh, puis disable-root-login.sh."
