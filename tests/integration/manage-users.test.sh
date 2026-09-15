#!/usr/bin/env bash
# tests/integration/manage-users.test.sh — Linux/System/manage-users.sh.
#
# TASK-025. MODIFIE LE SYSTÈME : crée un compte réel, un groupe du même nom, et
# le groupe « sudo » absent de l'image. Les fixtures sont retirées et leur
# retrait vérifié. Hors système jetable, tout est NON EXÉCUTÉ.
#
#   tests/env/run-in-container.sh -- tests/run.sh integration
#
# Trois choix ne se lisent pas dans le code : la clé est écrite HORS de /depot,
# que Docker Desktop monte en 0777 — un mode mesuré là-bas ne dirait rien ; le
# mot de passe est jugé sur /etc/shadow — tout champ commençant par « $ » est un
# condensé réellement posé, donc un échec ; l'idempotence passe par l'empreinte
# des fichiers de comptes avec la garde « P0 != A », sans laquelle un système
# déjà conforme rendrait des empreintes égales et ne prouverait rien.

set -Eeuo pipefail

_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_dir/lib/common.sh" ] && [ "$_dir" != "/" ]; do _dir="$(dirname "$_dir")"; done
source "$_dir/lib/common.sh"
# shellcheck source=/dev/null
source "$SCRIPTS_ROOT/tests/lib/assert.sh"

CIBLE="$SCRIPTS_ROOT/Linux/System/manage-users.sh"
COMPTE="mgnetessai"
COMPTE_DRY="mgnetessaidry"
# Groupe distinct du compte : useradd pose lui-même un groupe privé du nom du
# compte (USERGROUPS_ENAB), et un groupe homonyme déjà présent le fait échouer.
GROUPE="mgnetgrp"
SUDOERS="/etc/sudoers.d/mgnetworking-$COMPTE"
SUDOERS_DRY="/etc/sudoers.d/mgnetworking-$COMPTE_DRY"
CLE=""
REP_TMP="$(mktemp -d)"
F_OUT="$REP_TMP/stdout"
F_ERR="$REP_TMP/stderr"
CODE=0

# Le groupe « sudo » existe dans cette image (base-passwd le pose), contrairement
# à ce que supposait la fiche : le cas de refus n'est atteignable qu'en le
# retirant. Son GID est relevé pour le rendre intact — un groupe système retiré
# sans son numéro laisserait des fichiers orphelins.
SUDO_GID=""
SUDO_PREEXISTAIT="false"
if getent group sudo >/dev/null 2>&1; then
    SUDO_PREEXISTAIT="true"
    SUDO_GID="$(getent group sudo | cut -d: -f3)"
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
trap filet_de_securite EXIT

lancer() {
    CODE=0
    ( "$@" ) >"$F_OUT" 2>"$F_ERR" </dev/null || CODE=$?
}
sortie() { cat "$F_OUT"; }
erreur() { cat "$F_ERR"; }

# Empreinte de tout ce qu'une création de compte peut toucher : les quatre
# fichiers de comptes, le contenu de /etc/sudoers.d et la liste des homes.
etat() {
    local destination="$1" f
    {
        for f in /etc/passwd /etc/group /etc/shadow /etc/gshadow; do
            if [ -f "$f" ]; then cksum < "$f"; fi
        done
        if [ -d /etc/sudoers.d ]; then
            find /etc/sudoers.d -mindepth 1 -maxdepth 1 -printf '%f\n' 2>/dev/null | sort
        else
            printf 'sudoers.d absent\n'
        fi
        find /home -mindepth 1 -maxdepth 1 -printf '%f\n' 2>/dev/null | sort
    } > "$destination"
}

assert_etat_egal() {
    if diff -u "$1" "$2" > "$REP_TMP/diff" 2>&1; then
        ok "$3"
    else
        ko "$3" "$(head -n 8 "$REP_TMP/diff" | tr '\n' '|')"
    fi
}

assert_etat_different() {
    if diff -q "$1" "$2" >/dev/null 2>&1; then
        ko "$3" "aucune modification relevée : la preuve serait vide"
    else
        ok "$3"
    fi
}

assert_compte_absent() {
    if id -u "$1" >/dev/null 2>&1; then
        ko "$2" "le compte $1 existe"
    else
        ok "$2"
    fi
}

# rang <motif> — numéro de la première ligne de stderr portant ce motif.
rang() { grep -nF -- "$1" "$F_ERR" 2>/dev/null | head -n 1 | cut -d: -f1 || true; }

ordre() {
    local a b
    a="$(rang "$1")"
    b="$(rang "$2")"
    if [ -n "$a" ] && [ -n "$b" ] && [ "$a" -lt "$b" ]; then
        ok "$3"
    else
        ko "$3" "« $1 » ligne ${a:-absente}, « $2 » ligne ${b:-absente}"
    fi
}

# --- Reconnaissance de l'environnement -------------------------------------
EST_LINUX="false"
if [ "$(uname -s 2>/dev/null)" = "Linux" ]; then EST_LINUX="true"; fi
EST_DEBIAN="false"
if [ -r /etc/os-release ]; then
    identifiant="$(sed -n 's/^ID=//p' /etc/os-release | tr -d '"')"
    case "$identifiant" in debian|ubuntu) EST_DEBIAN="true" ;; esac
fi
EST_ROOT="false"
if [ "$(id -u)" -eq 0 ]; then EST_ROOT="true"; fi
JETABLE="false"
if [ -f /.dockerenv ]; then JETABLE="true"
elif grep -qE '(docker|containerd|lxc)' /proc/1/cgroup 2>/dev/null; then JETABLE="true"
elif [ "${MGNET_TEST_JETABLE:-}" = "1" ]; then JETABLE="true"
fi

# Lanceur non privilégié : le premier qui abaisse RÉELLEMENT l'UID. Sans lui,
# les cas de privilège sont NON EXÉCUTÉS, jamais réussis.
LANCEUR_SANS_ROOT=()
if [ "$EST_ROOT" = "false" ]; then
    LANCEUR_SANS_ROOT=(env)
elif command -v setpriv >/dev/null 2>&1 \
     && [ "$(setpriv --reuid=65534 --regid=65534 --clear-groups id -u 2>/dev/null)" = "65534" ]; then
    LANCEUR_SANS_ROOT=(setpriv --reuid=65534 --regid=65534 --clear-groups)
elif command -v runuser >/dev/null 2>&1 \
     && [ "$(runuser -u nobody -- id -u 2>/dev/null)" = "65534" ]; then
    LANCEUR_SANS_ROOT=(runuser -u nobody --)
fi

sans_root() {
    lancer env "LOG_DIR=/tmp/mgnet-test-users-nobody" "${LANCEUR_SANS_ROOT[@]}" "$@"
}

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

# La clé de fixture vit hors du dépôt monté : un mode mesuré dans /depot
# mesurerait le montage, pas le script.
CLE="$REP_TMP/essai.pub"
printf 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIExempleDeClePubliqueDeTest00000000000 essai@mgnet\n' > "$CLE"

titre "1. Aide"
lancer bash "$CIBLE" --help
assert_code 0 "$CODE" "--help sort en 0"
aide="$(sortie)"
for motif in "--utilisateur" "--cle-fichier" "--groupe" "--sudo" "--sudo-sans-mot-de-passe" \
             "--dry-run" "Ce que ce script ne fait pas" "élévation interactive" "passwd"; do
    assert_contient "$aide" "$motif" "--help documente « $motif »"
done

titre "2. Usage refusé — code 2, et aucune action"
# refus <libellé> <motif attendu sur stderr> [arguments...]
refus() {
    local libelle="$1" motif="$2"; shift 2
    lancer bash "$CIBLE" "$@"
    assert_code 2 "$CODE" "$libelle"
    if [ -n "$motif" ]; then
        assert_contient "$(erreur)" "$motif" "$libelle : le motif du refus est nommé"
    fi
    assert_compte_absent "$COMPTE" "$libelle : aucun compte n'a été créé"
}

refus "une option inconnue est refusée" "Option inconnue" --option-qui-n-existe-pas
refus "un appel sans argument est refusé" "Aucun compte demandé"
refus "--utilisateur sans valeur est refusé" "attend un nom de compte" --utilisateur
refus "--cle-fichier sans valeur est refusé" "attend un chemin de clé" --cle-fichier
refus "« root » est refusé comme cible" "root" --utilisateur root
refus "un nom commençant par une majuscule est refusé" "useradd" --utilisateur Root
refus "un nom commençant par un chiffre est refusé" "useradd" --utilisateur 1essai
refus "un nom contenant un point est refusé" "useradd" --utilisateur a.b
refus "un nom de plus de 32 caractères est refusé" "32" \
    --utilisateur aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
refus "un shell sans chemin absolu est refusé" "chemin absolu" --utilisateur essai --shell bash
refus "une clé publique introuvable est refusée" "introuvable" \
    --utilisateur essai --cle-fichier "$REP_TMP/absente.pub"

printf 'ssh-ed25519 %s\nssh-ed25519 %s\n' \
    "AAAAC3NzaC1lZDI1NTE5AAAAIExempleDeClePubliqueDeTest00000000000" \
    "AAAAC3NzaC1lZDI1NTE5AAAAIExempleDeClePubliqueDeTest00000000001" > "$REP_TMP/deux.pub"
refus "une clé sur deux lignes est refusée" "une seule ligne" \
    --utilisateur essai --cle-fichier "$REP_TMP/deux.pub"
printf 'ssh-machin-chose AAAAC3NzaC1lZDI1NTE5AAAAIBla\n' > "$REP_TMP/type.pub"
refus "un type de clé inconnu est refusé" "Type de clé inconnu" \
    --utilisateur essai --cle-fichier "$REP_TMP/type.pub"
printf 'ssh-ed25519 pas!du!base64!!\n' > "$REP_TMP/base.pub"
refus "un second champ non base64 est refusé" "base64" \
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

titre "4. Groupe sudo absent — refus en 1, sans rien créer"
# Le paquet sudo n'est pas installé : c'est le cas nominal du refus, et il ne
# s'éprouve qu'ICI, avant que la suite ne pose le groupe.
if [ "$MODIFIANT" != "oui" ]; then
    saute "le refus quand le groupe sudo n'existe pas" "$MODIFIANT"
else
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
fi

titre "5. Création nominale — compte, home, shell, groupe, clé"
if [ "$MODIFIANT" != "oui" ]; then
    saute "la création du compte et le dépôt de la clé" "$MODIFIANT"
else
    groupadd "$GROUPE"
    if [ -n "$SUDO_GID" ]; then groupadd -g "$SUDO_GID" sudo; else groupadd sudo; fi
    etat "$REP_TMP/p0"

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
    assert_egal "/home/$COMPTE:/bin/bash" "$(getent passwd "$COMPTE" | cut -d: -f6,7)" \
        "le home et le shell de connexion sont ceux demandés"
    if [ -d "/home/$COMPTE" ]; then ok "le répertoire personnel est créé"; else ko "le répertoire personnel est créé" "absent"; fi

    case " $(id -nG "$COMPTE") " in
        *" $GROUPE "*) ok "le compte appartient au groupe demandé" ;;
        *) ko "le compte appartient au groupe demandé" "groupes : $(id -nG "$COMPTE")" ;;
    esac
    case " $(id -nG "$COMPTE") " in
        *" sudo "*) ko "sans --sudo, le compte n'entre PAS dans le groupe sudo" "il y est" ;;
        *) ok "sans --sudo, le compte n'entre PAS dans le groupe sudo" ;;
    esac

    AUTORISE="/home/$COMPTE/.ssh/authorized_keys"
    assert_egal "700 $COMPTE" "$(stat -c '%a %U' "/home/$COMPTE/.ssh")" \
        ".ssh est en 0700 et appartient au compte"
    assert_egal "600 $COMPTE" "$(stat -c '%a %U' "$AUTORISE")" \
        "authorized_keys est en 0600 et appartient au compte"
    assert_contient "$(cat "$AUTORISE")" "AAAAC3NzaC1lZDI1NTE5AAAAIExempleDeClePubliqueDeTest00000000000" \
        "la clé fournie est bien celle déposée"
    assert_egal "1" "$(grep -c 'ssh-ed25519' "$AUTORISE")" "la clé n'est présente qu'une fois"

    # Le mot de passe : « ! » (compte verrouillé) pour useradd sans -p. Un champ
    # commençant par « $ » serait un condensé réellement posé.
    champ_shadow="$(getent shadow "$COMPTE" | cut -d: -f2)"
    case "$champ_shadow" in
        '$'*) ko "aucun mot de passe n'est posé dans /etc/shadow" "condensé trouvé : $champ_shadow" ;;
        *)    ok "aucun mot de passe n'est posé dans /etc/shadow (champ « $champ_shadow »)" ;;
    esac

    etat "$REP_TMP/p1"
    assert_etat_different "$REP_TMP/p0" "$REP_TMP/p1" \
        "la première exécution modifie réellement le système"
fi

titre "6. Idempotence — seconde exécution complète"
if [ "$MODIFIANT" != "oui" ] || [ ! -f "/home/$COMPTE/.ssh/authorized_keys" ]; then
    saute "la seconde exécution ne modifie rien" "$MODIFIANT sans création préalable"
else
    empreinte_cle="$(cksum < "/home/$COMPTE/.ssh/authorized_keys")"
    lancer bash "$CIBLE" --utilisateur "$COMPTE" --cle-fichier "$CLE" --groupe "$GROUPE"
    assert_code 0 "$CODE" "la seconde exécution sort en 0"
    assert_contient "$(erreur)" "existe déjà" "le script reconnaît le compte existant"
    assert_contient "$(erreur)" "déjà membre" "le script reconnaît l'appartenance déjà posée"
    assert_contient "$(erreur)" "déjà dans" "le script reconnaît la clé déjà déposée"

    etat "$REP_TMP/p2"
    assert_etat_egal "$REP_TMP/p1" "$REP_TMP/p2" "la seconde exécution laisse les fichiers de comptes identiques"
    assert_egal "$empreinte_cle" "$(cksum < "/home/$COMPTE/.ssh/authorized_keys")" \
        "authorized_keys est inchangé — empreinte identique"
    assert_egal "1" "$(grep -c 'ssh-ed25519' "/home/$COMPTE/.ssh/authorized_keys")" \
        "la clé n'est pas dupliquée par la seconde exécution"
fi

titre "7. --sudo, et la règle NOPASSWD jamais accordée par défaut"
if [ "$MODIFIANT" != "oui" ] || ! getent group sudo >/dev/null 2>&1; then
    saute "l'appartenance au groupe sudo" "$MODIFIANT sans groupe sudo"
    saute "le dépôt de la règle sudoers" "$MODIFIANT sans groupe sudo"
else
    lancer bash "$CIBLE" --utilisateur "$COMPTE" --sudo
    assert_code 0 "$CODE" "--sudo sort en 0 quand le groupe existe"
    case " $(id -nG "$COMPTE") " in
        *" sudo "*) ok "--sudo ajoute le compte au groupe sudo" ;;
        *) ko "--sudo ajoute le compte au groupe sudo" "groupes : $(id -nG "$COMPTE")" ;;
    esac
    if command -v sudo >/dev/null 2>&1; then
        saute "l'avertissement sur la commande sudo absente" "sudo est installé sur cet hôte"
    else
        assert_contient "$(erreur)" "la commande sudo est absente" \
            "groupe sudo présent mais commande absente : le script avertit"
        assert_contient "$(erreur)" "l'élévation restera impossible" \
            "l'avertissement dit ce qui reste impossible"
    fi
    if [ -e "$SUDOERS" ]; then
        ko "aucune règle sudoers n'est déposée sans l'option" "$SUDOERS existe"
    else
        ok "aucune règle sudoers n'est déposée sans l'option"
    fi

    lancer bash "$CIBLE" --utilisateur "$COMPTE" --sudo-sans-mot-de-passe
    assert_code 0 "$CODE" "--sudo-sans-mot-de-passe sort en 0"
    if [ -f "$SUDOERS" ]; then ok "la règle sudoers est déposée"; else ko "la règle sudoers est déposée" "fichier absent"; fi
    assert_egal "440 root:root" "$(stat -c '%a %U:%G' "$SUDOERS" 2>/dev/null)" \
        "la règle est en 0440 et appartient à root:root"
    case "$(basename "$SUDOERS")" in
        *.*|*~) ko "le nom de la règle ne porte ni point ni tilde final" "$(basename "$SUDOERS")" ;;
        *)      ok "le nom de la règle ne porte ni point ni tilde final" ;;
    esac
    assert_contient "$(cat "$SUDOERS")" "$COMPTE ALL=(ALL) NOPASSWD:ALL" "la règle accorde NOPASSWD au compte"
    residus="$(find /etc/sudoers.d -maxdepth 1 -name '.mgnetworking-*' | wc -l | tr -d ' ')"
    assert_egal "0" "$residus" "aucun fichier temporaire ne subsiste dans /etc/sudoers.d"

    lancer bash "$CIBLE" --utilisateur "$COMPTE" --sudo-sans-mot-de-passe
    assert_code 0 "$CODE" "la règle déjà conforme ne fait pas échouer la seconde exécution"
    assert_contient "$(erreur)" "déjà conforme" "le script reconnaît la règle déjà conforme"
fi

titre "8. --dry-run — énumère dans l'ordre, et ne modifie rien"
if [ "$MODIFIANT" != "oui" ]; then
    saute "--dry-run n'écrit rien" "$MODIFIANT"
else
    etat "$REP_TMP/dry-avant"
    lancer bash "$CIBLE" --utilisateur "$COMPTE_DRY" --cle-fichier "$CLE" \
        --groupe "$GROUPE" --sudo-sans-mot-de-passe --dry-run
    assert_code 0 "$CODE" "--dry-run sort en 0"
    apercu="$(erreur)"
    assert_contient "$apercu" "[dry-run] useradd --create-home --shell /bin/bash $COMPTE_DRY" \
        "--dry-run annonce la création du compte"
    assert_contient "$apercu" "[dry-run] usermod --append --groups $GROUPE $COMPTE_DRY" \
        "--dry-run annonce l'ajout au groupe"
    assert_contient "$apercu" "[dry-run] usermod --append --groups sudo $COMPTE_DRY" \
        "--dry-run annonce l'ajout au groupe sudo"
    assert_contient "$apercu" "[dry-run] Déposerait $SUDOERS_DRY" \
        "--dry-run annonce la règle sudoers"
    assert_contient "$apercu" "[dry-run] Ajouterait la clé ssh-ed25519" \
        "--dry-run annonce le dépôt de la clé"
    assert_contient "$apercu" "aucune modification effectuée" "--dry-run annonce n'avoir rien modifié"
    ordre "useradd --create-home" "usermod --append --groups $GROUPE" \
        "--dry-run annonce la création du compte avant l'ajout aux groupes"
    ordre "usermod --append --groups sudo" "Déposerait $SUDOERS_DRY" \
        "--dry-run annonce l'appartenance sudo avant la règle NOPASSWD"
    ordre "Déposerait $SUDOERS_DRY" "Ajouterait la clé" \
        "--dry-run annonce la règle sudoers avant le dépôt de la clé"

    assert_compte_absent "$COMPTE_DRY" "--dry-run ne crée aucun compte"
    if [ -e "/home/$COMPTE_DRY" ]; then
        ko "--dry-run ne crée aucun répertoire personnel" "/home/$COMPTE_DRY existe"
    else
        ok "--dry-run ne crée aucun répertoire personnel"
    fi
    if [ -e "$SUDOERS_DRY" ]; then
        ko "--dry-run ne dépose aucune règle sudoers" "$SUDOERS_DRY existe"
    else
        ok "--dry-run ne dépose aucune règle sudoers"
    fi
    etat "$REP_TMP/dry-apres"
    assert_etat_egal "$REP_TMP/dry-avant" "$REP_TMP/dry-apres" "--dry-run ne modifie aucun fichier de comptes"
fi

titre "9. Nettoyage — les fixtures sont retirées"
if [ "$MODIFIANT" = "oui" ]; then
    userdel -r "$COMPTE" >/dev/null 2>&1 || true
    groupdel "$GROUPE" >/dev/null 2>&1 || true
    rm -f "$SUDOERS" || true
    groupdel sudo >/dev/null 2>&1 || true
    assert_compte_absent "$COMPTE" "le compte de fixture est retiré"
    if [ -e "/home/$COMPTE" ]; then
        ko "le répertoire personnel de fixture est retiré" "/home/$COMPTE subsiste"
    else
        ok "le répertoire personnel de fixture est retiré"
    fi
    if getent group "$GROUPE" >/dev/null 2>&1; then
        ko "le groupe de fixture est retiré" "$GROUPE subsiste"
    else
        ok "le groupe de fixture est retiré"
    fi
    # Le groupe sudo est rendu à son état d'origine : retiré s'il n'existait pas,
    # rétabli avec son GID s'il préexistait.
    if [ "$SUDO_PREEXISTAIT" = "true" ]; then
        retablir_groupe_sudo
        gid_final="absent"
        if ! gid_final="$(getent group sudo | cut -d: -f3)"; then gid_final="absent"; fi
        assert_egal "$SUDO_GID" "$gid_final" "le groupe sudo préexistant est rendu intact, GID compris"
    elif getent group sudo >/dev/null 2>&1; then
        ko "le groupe sudo de fixture est retiré" "sudo subsiste"
    else
        ok "le groupe sudo de fixture est retiré"
    fi
    if [ -e "$SUDOERS" ]; then
        ko "la règle sudoers de fixture est retirée" "$SUDOERS subsiste"
    else
        ok "la règle sudoers de fixture est retirée"
    fi
else
    saute "le nettoyage des fixtures" "$MODIFIANT — rien n'a été créé"
fi

bilan "TASK-025 / manage-users.sh"
