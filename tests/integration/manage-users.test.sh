#!/usr/bin/env bash
set -Eeuo pipefail
# tests/integration/manage-users.test.sh — Linux/System/manage-users.sh (TASK-025).
#
# MODIFIE LE SYSTÈME : un compte, un groupe, et le groupe « sudo » de l'image.
# Fixtures retirées par un trap armé en conteneur jetable seulement. La clé est
# écrite HORS de /depot, monté en 0777 : un mode mesuré là-bas dirait le montage.
# Le mot de passe est jugé sur /etc/shadow, « $ » en tête valant condensé posé.
# L'idempotence passe par empreinte sous la garde « avant != après », sans
# laquelle un système déjà conforme ne prouverait rien.

_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_dir/lib/common.sh" ] && [ "$_dir" != "/" ]; do _dir="$(dirname "$_dir")"; done
source "$_dir/lib/common.sh"
# shellcheck source=/dev/null
source "$SCRIPTS_ROOT/tests/lib/assert.sh"

CIBLE="$SCRIPTS_ROOT/Linux/System/manage-users.sh"
COMPTE="mgnetessai"; COMPTE_DRY="mgnetessaidry"; GROUPE="mgnetgrp"
# Groupe distinct du compte : useradd pose lui-même un groupe privé du nom du
# compte (USERGROUPS_ENAB), et un groupe homonyme déjà présent le fait échouer.
SUDOERS="/etc/sudoers.d/mgnetworking-$COMPTE"; SUDOERS_DRY="/etc/sudoers.d/mgnetworking-$COMPTE_DRY"
COMPTE_HOME="/home/$COMPTE"; AUTORISE="$COMPTE_HOME/.ssh/authorized_keys"
CLE=""; SECONDE=""; CODE=0
if ! REP_TMP="$(mktemp -d)"; then printf 'mktemp -d a échoué\n' >&2; exit 3; fi
F_OUT="$REP_TMP/stdout"; F_ERR="$REP_TMP/stderr"

# Le groupe « sudo » existe dans cette image (base-passwd le pose), contrairement
# à ce que supposait la fiche : le refus ne s'éprouve qu'en le retirant, et son
# GID est relevé pour le rendre intact.
SUDO_GID=""; SUDO_PREEXISTAIT="false"
if getent group sudo >/dev/null 2>&1; then
    SUDO_PREEXISTAIT="true"
    if ! SUDO_GID="$(getent group sudo | cut -d: -f3)"; then SUDO_GID=""; fi
fi

retablir_groupe_sudo() {
    if [ "$SUDO_PREEXISTAIT" = "true" ] && ! getent group sudo >/dev/null 2>&1; then
        groupadd -g "$SUDO_GID" sudo
    fi
}

filet_de_securite() {
    userdel -r "$COMPTE" >/dev/null 2>&1 || true
    userdel -r "$COMPTE_DRY" >/dev/null 2>&1 || true
    groupdel "$GROUPE" >/dev/null 2>&1 || true
    if [ "$SUDO_PREEXISTAIT" = "false" ]; then groupdel sudo >/dev/null 2>&1 || true; fi
    retablir_groupe_sudo >/dev/null 2>&1 || true
    rm -f "$SUDOERS" "$SUDOERS_DRY" /etc/sudoers.d/.mgnetworking-* >/dev/null 2>&1 || true
    rmdir /etc/sudoers.d >/dev/null 2>&1 || true
    rm -rf "$REP_TMP" /tmp/mgnet-test-users-nobody
}

lancer() {
    CODE=0
    ( "$@" ) >"$F_OUT" 2>"$F_ERR" </dev/null || CODE=$?
}
sortie() { cat "$F_OUT"; }
erreur() { cat "$F_ERR"; }

# present/absent <chemin> <libellé> — remplacent les blocs if/ok/ko de cinq lignes.
present() { if [ -e "$1" ]; then ok "$2"; else ko "$2" "$1 est absent"; fi; }
absent()  { if [ -e "$1" ]; then ko "$2" "$1 subsiste"; else ok "$2"; fi; }

# membre <compte> <groupe> <oui|non> <libellé>
membre() {
    if id -nG "$1" | grep -qw -- "$2"; then
        if [ "$3" = "oui" ]; then ok "$4"; else ko "$4" "groupes : $(id -nG "$1")"; fi
    elif [ "$3" = "oui" ]; then ko "$4" "groupes : $(id -nG "$1")"
    else ok "$4"; fi
}

assert_compte_absent() {
    if id -u "$1" >/dev/null 2>&1; then ko "$2" "le compte $1 existe"; else ok "$2"; fi
}

# Empreinte de tout ce qu'une création de compte peut toucher : les quatre
# fichiers de comptes, le CONTENU de /etc/sudoers.d et la liste des homes.
empreinte() {
    {
        cksum /etc/passwd /etc/group /etc/shadow /etc/gshadow 2>/dev/null
        find /etc/sudoers.d -mindepth 1 -maxdepth 1 -type f -exec cksum {} + 2>/dev/null | sort
        find /home -mindepth 1 -maxdepth 1 -printf '%f\n' 2>/dev/null | sort
    } | cksum
}

# noter <variable> — l'empreinte est prise en contexte de condition (TASK-018).
noter() { if ! printf -v "$1" '%s' "$(empreinte)"; then printf -v "$1" ''; fi; }
# Déclarées ici : printf -v affecte par nom, shellcheck ne le voit pas (SC2154).
avant=""; apres=""; apres2=""; complet_avant=""; complet_apres=""; dry_avant=""; dry_apres=""

# assert_empreinte <avant> <apres> <egal|different> <libellé>
assert_empreinte() {
    if [ "$1" = "$2" ]; then
        if [ "$3" = "different" ]; then ko "$4" "aucune modification relevée : la preuve serait vide"; else ok "$4"; fi
    elif [ "$3" = "egal" ]; then ko "$4" "l'état a changé : $1 puis $2"
    else ok "$4"; fi
}

# rang <motif> — numéro de la première ligne de stderr portant ce motif.
rang() { grep -nF -- "$1" "$F_ERR" 2>/dev/null | head -n 1 | cut -d: -f1; }

ordre() {
    local a="" b=""
    a="$(rang "$1")" || a=""
    b="$(rang "$2")" || b=""
    if [ -n "$a" ] && [ -n "$b" ] && [ "$a" -lt "$b" ]; then ok "$3"
    else ko "$3" "« $1 » ligne ${a:-absente}, « $2 » ligne ${b:-absente}"; fi
}

# --- Reconnaissance de l'environnement -------------------------------------
EST_LINUX="false"
case "$(uname -s 2>/dev/null)" in Linux) EST_LINUX="true" ;; esac
EST_DEBIAN="false"
if [ -r /etc/os-release ]; then
    case "$(sed -n 's/^ID=//p' /etc/os-release | tr -d '"')" in debian|ubuntu) EST_DEBIAN="true" ;; esac
fi
EST_ROOT="false"
if [ "$(id -u)" -eq 0 ]; then EST_ROOT="true"; fi
JETABLE="false"
if [ -f /.dockerenv ]; then JETABLE="true"
elif grep -qE '(docker|containerd|lxc)' /proc/1/cgroup 2>/dev/null; then JETABLE="true"
elif [ "${MGNET_TEST_JETABLE:-}" = "1" ]; then JETABLE="true"
fi

# Lanceur non privilégié : le premier qui abaisse RÉELLEMENT l'UID. Sans lui, les
# cas de privilège sont NON EXÉCUTÉS, jamais réussis.
LANCEUR_SANS_ROOT=()
if [ "$EST_ROOT" = "false" ]; then LANCEUR_SANS_ROOT=(env)
elif command -v setpriv >/dev/null 2>&1 \
     && [ "$(setpriv --reuid=65534 --regid=65534 --clear-groups id -u 2>/dev/null)" = "65534" ]; then
    LANCEUR_SANS_ROOT=(setpriv --reuid=65534 --regid=65534 --clear-groups)
elif command -v runuser >/dev/null 2>&1 && [ "$(runuser -u nobody -- id -u 2>/dev/null)" = "65534" ]; then
    LANCEUR_SANS_ROOT=(runuser -u nobody --)
fi
sans_root() { lancer env "LOG_DIR=/tmp/mgnet-test-users-nobody" "${LANCEUR_SANS_ROOT[@]}" "$@"; }

if [ "$EST_LINUX" != "true" ] || [ ! -f "$CIBLE" ]; then
    saute "l'ensemble des cas de manage-users.sh" "hôte non Linux, ou $CIBLE introuvable"
    bilan "TASK-025 / manage-users.sh"
    exit 0
fi

MODIFIANT="oui"
if [ "$EST_ROOT" != "true" ]; then
    MODIFIANT="require_root arrête le script avant toute écriture"
elif [ "$JETABLE" != "true" ]; then
    MODIFIANT="cet hôte n'est pas un système jetable — ni /etc/passwd ni /etc/sudoers.d ne seront touchés"
elif [ "$EST_DEBIAN" != "true" ]; then
    MODIFIANT="l'hôte n'est ni Debian ni Ubuntu — require_os refuse le script"
fi
# Hors système jetable, rien n'a été créé : le filet ne doit pas être armé.
if [ "$MODIFIANT" = "oui" ]; then trap filet_de_securite EXIT; fi

CLE="$REP_TMP/essai.pub"
SECONDE="$REP_TMP/seconde.pub"
printf 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIExempleDeClePubliqueDeTest00000000000 essai@mgnet\n' > "$CLE"
printf 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIExempleDeClePubliqueDeTest00000000002 seconde@mgnet\n' > "$SECONDE"

titre "1. Aide"
lancer bash "$CIBLE" --help
assert_code 0 "$CODE" "--help sort en 0"
aide=""; if ! aide="$(sortie)"; then aide=""; fi
for motif in "--utilisateur" "--cle-fichier" "--groupe" "--sudo" "--sudo-sans-mot-de-passe" \
             "--shell" "--dry-run" "Ce que ce script ne fait pas" "élévation interactive" "passwd"; do
    assert_contient "$aide" "$motif" "--help documente « $motif »"
done

titre "2. Usage refusé — code 2, et aucun compte créé"
# refus <libellé> <cible> <motif attendu> [arguments...]
refus() {
    local libelle="$1" cible="$2" motif="$3"; shift 3
    lancer bash "$CIBLE" "$@"
    assert_code 2 "$CODE" "$libelle"
    assert_contient "$(erreur)" "$motif" "$libelle : le motif du refus est nommé"
    if [ -n "$cible" ]; then assert_compte_absent "$cible" "$libelle : le compte « $cible » n'a pas été créé"; fi
}

refus "une option inconnue est refusée" "" "Option inconnue" --option-qui-n-existe-pas
refus "un appel sans argument est refusé" "" "Aucun compte demandé"
refus "--utilisateur sans valeur est refusé" "" "attend un nom de compte" --utilisateur
refus "--cle-fichier sans valeur est refusé" "" "attend un chemin de clé" --cle-fichier
refus "« root » est refusé comme cible" "" "root" --utilisateur root
refus "un nom commençant par une majuscule est refusé" "Root" "useradd" --utilisateur Root
refus "un nom commençant par un chiffre est refusé" "1essai" "useradd" --utilisateur 1essai
refus "un nom contenant un point est refusé" "a.b" "useradd" --utilisateur a.b
refus "un nom de plus de 32 caractères est refusé" \
    "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" "32" --utilisateur aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
refus "un shell sans chemin absolu est refusé" "essai" "chemin absolu" --utilisateur essai --shell bash
refus "une clé publique introuvable est refusée" "essai" "introuvable" \
    --utilisateur essai --cle-fichier "$REP_TMP/absente.pub"

printf 'ssh-ed25519 %s\nssh-ed25519 %s\n' \
    "AAAAC3NzaC1lZDI1NTE5AAAAIExempleDeClePubliqueDeTest00000000000" \
    "AAAAC3NzaC1lZDI1NTE5AAAAIExempleDeClePubliqueDeTest00000000001" > "$REP_TMP/deux.pub"
refus "une clé sur deux lignes est refusée" "essai" "une seule ligne" \
    --utilisateur essai --cle-fichier "$REP_TMP/deux.pub"
printf 'ssh-machin-chose AAAAC3NzaC1lZDI1NTE5AAAAIBla\n' > "$REP_TMP/type.pub"
refus "un type de clé inconnu est refusé" "essai" "Type de clé inconnu" \
    --utilisateur essai --cle-fichier "$REP_TMP/type.pub"
printf 'ssh-ed25519 pas!du!base64!!\n' > "$REP_TMP/base.pub"
refus "un second champ non base64 est refusé" "essai" "base64" \
    --utilisateur essai --cle-fichier "$REP_TMP/base.pub"

titre "3. Privilège insuffisant"
if [ "${#LANCEUR_SANS_ROOT[@]}" -eq 0 ]; then
    saute "le refus de s'exécuter sans privilège" "aucun lanceur ne parvient à abaisser l'UID"
    saute "la primauté de l'erreur d'usage sur le manque de privilège" \
        "aucun lanceur ne parvient à abaisser l'UID"
else
    sans_root bash "$CIBLE" --utilisateur essai
    assert_code 1 "$CODE" "le script refuse de s'exécuter sans privilège"
    assert_contient "$(erreur)" "doit être exécuté en root" "le script dit pourquoi il refuse"
    sans_root bash "$CIBLE" --option-qui-n-existe-pas
    assert_code 2 "$CODE" "l'erreur d'usage prime sur le manque de privilège"
    sans_root bash "$CIBLE" --utilisateur essai --cle-fichier "$REP_TMP/absente.pub"
    assert_code 2 "$CODE" "la clé fautive prime elle aussi sur le manque de privilège"
fi

titre "4. Prérequis manquants — refus en 1, sans rien créer"
if [ "$MODIFIANT" != "oui" ]; then
    saute "le refus quand le groupe sudo n'existe pas" "$MODIFIANT"
    saute "le refus d'un groupe demandé inexistant" "$MODIFIANT"
else
    # Le groupe sudo est retiré : c'est le cas nominal du refus, et il ne
    # s'éprouve qu'ICI, avant que la suite ne le rétablisse.
    groupdel sudo >/dev/null 2>&1 || true
    lancer bash "$CIBLE" --utilisateur "$COMPTE" --sudo
    assert_code 1 "$CODE" "le groupe sudo absent fait sortir en 1"
    assert_contient "$(erreur)" "groupe « sudo » n'existe pas" "le script nomme ce qui manque"
    assert_contient "$(erreur)" "apt-get install sudo" "le script refuse d'installer le paquet et donne le correctif"
    assert_contient "$(erreur)" "rien n'a été modifié" "le script annonce n'avoir rien modifié"
    assert_compte_absent "$COMPTE" "le refus précède la création du compte"
    if getent group sudo >/dev/null 2>&1; then
        ko "le groupe sudo n'a pas été créé" "le groupe existe désormais"
    else
        ok "le groupe sudo n'a pas été créé"
    fi
    lancer bash "$CIBLE" --utilisateur "$COMPTE" --groupe mgnetabsent
    assert_code 1 "$CODE" "un groupe demandé inexistant fait sortir en 1"
    assert_contient "$(erreur)" "Groupe « mgnetabsent » inconnu" "le refus nomme le groupe inconnu"
    assert_compte_absent "$COMPTE" "le groupe inconnu est refusé avant la création du compte"
fi

titre "5. Création nominale — compte, home, shell, groupe, clé"
if [ "$MODIFIANT" != "oui" ]; then
    saute "la création du compte et le dépôt de la clé" "$MODIFIANT"
else
    groupadd "$GROUPE"
    if [ -n "$SUDO_GID" ]; then groupadd -g "$SUDO_GID" sudo; else groupadd sudo; fi
    avant="$(empreinte)"

    lancer bash "$CIBLE" --utilisateur "$COMPTE" --cle-fichier "$CLE" --groupe "$GROUPE"
    assert_code 0 "$CODE" "la création nominale sort en 0"
    assert_contient "$(erreur)" "Aucun mot de passe n'est défini, lu, généré ni demandé" \
        "le script annonce qu'il ne touche à aucun mot de passe"
    assert_contient "$(erreur)" "Clé publique déposée" "le dépôt de la clé est annoncé"
    assert_contient "$(erreur)" "Compte prêt" "le résumé final est affiché"
    assert_contient "$(erreur)" "Vérifier la connexion : ssh $COMPTE@" \
        "le résumé dit comment vérifier la connexion"
    assert_contient "$(erreur)" "configure-ssh.sh" \
        "le résumé nomme ce qu'il reste à faire avant de durcir SSH"
    assert_contient "$(erreur)" "passwd $COMPTE" "le résumé rappelle le mot de passe à définir"

    if id -u "$COMPTE" >/dev/null 2>&1; then ok "le compte existe"; else ko "le compte existe" "id -u a échoué"; fi
    assert_egal "$COMPTE_HOME:/bin/bash" "$(getent passwd "$COMPTE" | cut -d: -f6,7)" \
        "le home et le shell de connexion sont ceux demandés"
    if [ -d "$COMPTE_HOME" ]; then ok "le répertoire personnel est créé"; else ko "le répertoire personnel est créé" "absent"; fi
    membre "$COMPTE" "$GROUPE" oui "le compte appartient au groupe demandé"
    membre "$COMPTE" sudo non "sans --sudo, le compte n'entre PAS dans le groupe sudo"

    assert_egal "700 $COMPTE" "$(stat -c '%a %U' "$COMPTE_HOME/.ssh")" ".ssh est en 0700 et appartient au compte"
    assert_egal "600 $COMPTE" "$(stat -c '%a %U' "$AUTORISE")" \
        "authorized_keys est en 0600 et appartient au compte"
    assert_contient "$(cat "$AUTORISE")" "AAAAC3NzaC1lZDI1NTE5AAAAIExempleDeClePubliqueDeTest00000000000" \
        "la clé fournie est bien celle déposée"
    assert_egal "1" "$(grep -c 'ssh-ed25519' "$AUTORISE")" "la clé n'est présente qu'une fois"

    # « ! » (compte verrouillé) pour useradd sans -p : un champ commençant par
    # « $ » serait un condensé réellement posé.
    champ_shadow=""; if ! champ_shadow="$(getent shadow "$COMPTE" | cut -d: -f2)"; then champ_shadow=""; fi
    case "$champ_shadow" in
        '$'*) ko "aucun mot de passe n'est posé dans /etc/shadow" "condensé trouvé : $champ_shadow" ;;
        *)    ok "aucun mot de passe n'est posé dans /etc/shadow (champ « $champ_shadow »)" ;;
    esac

    noter apres
    assert_empreinte "$avant" "$apres" different \
        "la première exécution modifie réellement le système"
fi

titre "6. Idempotence — seconde exécution complète"
if [ "$MODIFIANT" != "oui" ] || [ ! -f "$AUTORISE" ]; then
    saute "la seconde exécution ne modifie rien" "$MODIFIANT sans création préalable"
else
    empreinte_cle=""; if ! empreinte_cle="$(cksum < "$AUTORISE")"; then empreinte_cle=""; fi
    lancer bash "$CIBLE" --utilisateur "$COMPTE" --cle-fichier "$CLE" --groupe "$GROUPE"
    assert_code 0 "$CODE" "la seconde exécution sort en 0"
    assert_contient "$(erreur)" "existe déjà" "le script reconnaît le compte existant"
    assert_contient "$(erreur)" "déjà membre" "le script reconnaît l'appartenance déjà posée"
    assert_contient "$(erreur)" "déjà dans" "le script reconnaît la clé déjà déposée"
    noter apres2
    assert_empreinte "$apres" "$apres2" egal \
        "la seconde exécution laisse les fichiers de comptes identiques"
    assert_egal "$empreinte_cle" "$(cksum < "$AUTORISE")" \
        "authorized_keys est inchangé — empreinte identique"
    assert_egal "1" "$(grep -c 'ssh-ed25519' "$AUTORISE")" \
        "la clé n'est pas dupliquée par la seconde exécution"
fi

titre "7. --sudo, la règle NOPASSWD, et l'appel complet rejoué"
if [ "$MODIFIANT" != "oui" ] || ! getent group sudo >/dev/null 2>&1; then
    saute "l'appartenance au groupe sudo et la règle sudoers" "$MODIFIANT sans groupe sudo"
else
    lancer bash "$CIBLE" --utilisateur "$COMPTE" --sudo
    assert_code 0 "$CODE" "--sudo sort en 0 quand le groupe existe"
    membre "$COMPTE" sudo oui "--sudo ajoute le compte au groupe sudo"
    membre "$COMPTE" "$GROUPE" oui "l'appartenance antérieure survit à l'ajout de sudo"
    assert_contient "$(erreur)" "Aucune clé publique fournie" "sans --cle-fichier, le résumé le dit"
    if command -v sudo >/dev/null 2>&1; then
        saute "l'avertissement sur la commande sudo absente" "sudo est installé sur cet hôte"
    else
        assert_contient "$(erreur)" "la commande sudo est absente" \
            "groupe sudo présent mais commande absente : le script avertit"
        assert_contient "$(erreur)" "l'élévation restera impossible" \
            "l'avertissement dit ce qui reste impossible"
    fi
    absent "$SUDOERS" "aucune règle sudoers n'est déposée sans l'option"

    # /etc/sudoers.d vient du paquet sudo : absent de l'image, la fixture le pose
    # — le script, lui, ne le crée pas.
    install -d -m 0755 -o root -g root /etc/sudoers.d
    lancer bash "$CIBLE" --utilisateur "$COMPTE" --sudo-sans-mot-de-passe
    assert_code 0 "$CODE" "--sudo-sans-mot-de-passe sort en 0"
    present "$SUDOERS" "la règle sudoers est déposée"
    assert_egal "440 root:root" "$(stat -c '%a %U:%G' "$SUDOERS" 2>/dev/null)" \
        "la règle est en 0440 et appartient à root:root"
    case "$(basename "$SUDOERS")" in
        *.*|*~) ko "le nom de la règle ne porte ni point ni tilde final" "$(basename "$SUDOERS")" ;;
        *)      ok "le nom de la règle ne porte ni point ni tilde final" ;;
    esac
    assert_contient "$(cat "$SUDOERS")" "$COMPTE ALL=(ALL) NOPASSWD:ALL" "la règle accorde NOPASSWD au compte"
    residus=""; if ! residus="$(find /etc/sudoers.d -mindepth 1 -maxdepth 1 -name '.mgnetworking-*' -printf '%f\n')"; then residus=""; fi
    assert_egal "" "$residus" "aucun fichier temporaire ne subsiste dans /etc/sudoers.d"
    listing=""; if ! listing="$(find /etc/sudoers.d -mindepth 1 -maxdepth 1 -printf '%f\n' | sort)"; then listing=""; fi
    assert_egal "mgnetworking-$COMPTE" "$listing" "/etc/sudoers.d ne contient que la règle déposée"

    # L'appel de la garde de configure-ssh.sh, rejoué tel quel : il ne doit rien
    # changer, contenu de /etc/sudoers.d compris.
    noter complet_avant
    lancer bash "$CIBLE" --utilisateur "$COMPTE" --sudo --sudo-sans-mot-de-passe --cle-fichier "$CLE"
    assert_code 0 "$CODE" "l'appel complet (--sudo --sudo-sans-mot-de-passe --cle-fichier) sort en 0"
    assert_contient "$(erreur)" "déjà conforme" "le script reconnaît la règle sudo déjà conforme"
    noter complet_apres
    assert_empreinte "$complet_avant" "$complet_apres" egal \
        "l'appel complet rejoué ne modifie rien — /etc/sudoers.d compris"
fi

titre "8. --dry-run — énumère dans l'ordre, et ne modifie rien"
if [ "$MODIFIANT" != "oui" ]; then
    saute "--dry-run n'écrit rien" "$MODIFIANT"
else
    noter dry_avant
    lancer bash "$CIBLE" --utilisateur "$COMPTE_DRY" --cle-fichier "$CLE" \
        --groupe "$GROUPE" --sudo-sans-mot-de-passe --dry-run
    assert_code 0 "$CODE" "--dry-run sort en 0"
    apercu=""; if ! apercu="$(erreur)"; then apercu=""; fi
    assert_contient "$apercu" "[dry-run] useradd --create-home --shell /bin/bash $COMPTE_DRY" \
        "--dry-run annonce la création du compte"
    assert_contient "$apercu" "[dry-run] usermod --append --groups $GROUPE $COMPTE_DRY" \
        "--dry-run annonce l'ajout au groupe"
    assert_contient "$apercu" "[dry-run] usermod --append --groups sudo $COMPTE_DRY" \
        "--dry-run annonce l'ajout au groupe sudo"
    assert_contient "$apercu" "[dry-run] Déposerait $SUDOERS_DRY" "--dry-run annonce la règle sudoers"
    assert_contient "$apercu" "[dry-run] Ajouterait la clé ssh-ed25519" "--dry-run annonce le dépôt de la clé"
    assert_contient "$apercu" "aucune modification effectuée" "--dry-run annonce n'avoir rien modifié"
    ordre "useradd --create-home" "usermod --append --groups $GROUPE" \
        "--dry-run annonce la création du compte avant l'ajout aux groupes"
    ordre "usermod --append --groups sudo" "Déposerait $SUDOERS_DRY" \
        "--dry-run annonce l'appartenance sudo avant la règle NOPASSWD"
    ordre "Déposerait $SUDOERS_DRY" "Ajouterait la clé" \
        "--dry-run annonce la règle sudoers avant le dépôt de la clé"
    assert_compte_absent "$COMPTE_DRY" "--dry-run ne crée aucun compte"
    absent "/home/$COMPTE_DRY" "--dry-run ne crée aucun répertoire personnel"
    absent "$SUDOERS_DRY" "--dry-run ne dépose aucune règle sudoers"
    noter dry_apres
    assert_empreinte "$dry_avant" "$dry_apres" egal "--dry-run ne modifie aucun fichier de comptes"
fi

titre "9. Dépôt de clé — saut de ligne final, liens symboliques, modes"
if [ "$MODIFIANT" != "oui" ] || [ ! -f "$AUTORISE" ]; then
    saute "le saut de ligne final, les liens symboliques et les modes" "$MODIFIANT sans création préalable"
else
    # authorized_keys sans saut de ligne final : la clé suivante ne doit pas se
    # coller à la dernière ligne.
    printf '%s' "$(head -n 1 "$AUTORISE")" > "$AUTORISE"
    lancer bash "$CIBLE" --utilisateur "$COMPTE" --cle-fichier "$SECONDE"
    assert_code 0 "$CODE" "le dépôt sur un fichier sans saut de ligne final sort en 0"
    assert_egal "2" "$(grep -c '^ssh-ed25519' "$AUTORISE")" "les deux clés occupent chacune leur ligne"
    assert_contient "$(cat "$AUTORISE")" "seconde@mgnet" "la seconde clé est bien déposée"

    # ~/.ssh ou authorized_keys en lien symbolique : root écrirait à travers, vers
    # un fichier choisi par l'utilisateur.
    mv "$AUTORISE" "$REP_TMP/vrai_autorise"
    ln -s "$REP_TMP/vrai_autorise" "$AUTORISE"
    lancer bash "$CIBLE" --utilisateur "$COMPTE" --cle-fichier "$SECONDE"
    assert_code 1 "$CODE" "un authorized_keys en lien symbolique est refusé en 1"
    assert_contient "$(erreur)" "lien symbolique" "le refus nomme le lien symbolique"
    rm -f "$AUTORISE"; mv "$REP_TMP/vrai_autorise" "$AUTORISE"

    # sshd refuse silencieusement une clé mal protégée : le mode est corrigé.
    chmod 0755 "$COMPTE_HOME/.ssh"; chmod 0644 "$AUTORISE"
    lancer bash "$CIBLE" --utilisateur "$COMPTE" --cle-fichier "$SECONDE"
    assert_code 0 "$CODE" "un mode trop permissif ne fait pas échouer l'exécution"
    assert_egal "700 $COMPTE" "$(stat -c '%a %U' "$COMPTE_HOME/.ssh")" "le mode de .ssh est corrigé"
    assert_egal "600 $COMPTE" "$(stat -c '%a %U' "$AUTORISE")" "le mode de authorized_keys est corrigé"
fi

bilan "TASK-025 / manage-users.sh"
