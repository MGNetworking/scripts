#!/usr/bin/env bash
# tests/integration/configure-ssh.test.sh — Linux/Security/configure-ssh.sh.
#
# TASK-046. Ni sshd ni systemctl réels : deux faux en tête de PATH tracent chaque
# appel, un faux getent sert les comptes, /etc/ssh est un bac à sable via
# SSHD_CONFIG et SSHD_CONFIG_D. Le journal des appels prouve qu'aucun « restart »
# n'a lieu, que « sshd -t » précède le rechargement, et qu'un refus n'écrit rien ;
# SSHD_REFUS et SYSTEMCTL_REFUS font échouer les faux à volonté.

_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_dir/lib/common.sh" ] && [ "$_dir" != "/" ]; do _dir="$(dirname "$_dir")"; done
source "$_dir/lib/common.sh"
source "$SCRIPTS_ROOT/tests/lib/assert.sh"

CIBLE="$SCRIPTS_ROOT/Linux/Security/configure-ssh.sh"
BAC="$(mktemp -d)"; chmod 755 "$BAC"
FAUX="$BAC/bin"; mkdir -p "$FAUX"
HOME_ADMIN="$BAC/home/admin"; mkdir -p "$HOME_ADMIN/.ssh"
HOME_ROOT="$BAC/home/root"; mkdir -p "$HOME_ROOT/.ssh"
export JOURNAL="$BAC/appels.log" SSHD_CONFIG="$BAC/sshd_config" SSHD_CONFIG_D="$BAC/sshd_config.d"
export PASSWD_FACTICE="$BAC/passwd" GROUP_FACTICE="$BAC/group"
export SSHD_REFUS="$BAC/sshd-refus" SYSTEMCTL_REFUS="$BAC/systemctl-refus"
export DEPOT="$SSHD_CONFIG_D/10-mgnetworking.conf"
trap 'rm -rf "$BAC"' EXIT

cat > "$FAUX/sshd" <<'EOF'
#!/bin/sh
printf 'sshd %s\n' "$*" >> "$JOURNAL"
[ -f "$SSHD_REFUS" ] && { printf 'sshd: ligne 3 : mauvaise configuration\n' >&2; exit 1; }
exit 0
EOF
cat > "$FAUX/systemctl" <<'EOF'
#!/bin/sh
printf 'systemctl %s\n' "$*" >> "$JOURNAL"
[ -f "$SYSTEMCTL_REFUS" ] && exit 1
exit 0
EOF
cat > "$FAUX/getent" <<'EOF'
#!/bin/sh
case "$1" in
passwd) awk -F: -v u="$2" '$1 == u {print; exit}' "$PASSWD_FACTICE" ;;
group)  awk -F: -v g="$2" '$1 == g {print; exit}' "$GROUP_FACTICE" ;;
esac
EOF
chmod +x "$FAUX/sshd" "$FAUX/systemctl" "$FAUX/getent"

# admin : compte non-root, membre de sudo par liste, avec une clé publique.
comptes_ok() {
    printf 'admin:x:1000:1000:Admin:%s:/bin/bash\n' "$HOME_ADMIN" > "$PASSWD_FACTICE"
    printf 'sudo:x:27:admin\n' > "$GROUP_FACTICE"
    printf 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBExemple admin@poste\n' > "$HOME_ADMIN/.ssh/authorized_keys"
}
etat_neuf() {
    printf 'Include /etc/ssh/sshd_config.d/*.conf\n' > "$SSHD_CONFIG"
    rm -rf "$SSHD_CONFIG_D"; mkdir -p "$SSHD_CONFIG_D"
    rm -f "$SSHD_REFUS" "$SYSTEMCTL_REFUS"; : > "$JOURNAL"
    comptes_ok
}

# Garde : un vrai sshd ou un vrai systemctl atteint par mégarde agirait sur la machine.
if [ "$(PATH="$FAUX:$PATH" command -v sshd)" != "$FAUX/sshd" ] \
   || [ "$(PATH="$FAUX:$PATH" command -v systemctl)" != "$FAUX/systemctl" ]; then
    saute_indisponible "faux sshd et systemctl en tête de PATH" "PATH ne les désigne pas dans $FAUX"
    bilan "TASK-046 / configure-ssh.sh"
fi

lancer() { CODE=0; SORTIE="$(PATH="$FAUX:$PATH" "$@" 2>&1 </dev/null)" || CODE=$?; }
depot() { cat "$DEPOT" 2>/dev/null || true; }
present() { [ -e "$DEPOT" ] && printf 'présent' || printf 'absent'; }
modifications() { grep -cE '^(sshd|systemctl)' "$JOURNAL" || true; }
rang() { grep -nF -- "$1" "$JOURNAL" | head -n1 | cut -d: -f1; }
assert_avant() {
    local a b; a="$(rang "$1")"; b="$(rang "$2")"
    if [ -n "$a" ] && [ -n "$b" ] && [ "$a" -lt "$b" ]; then ok "$3"
    else ko "$3" "$1 (ligne ${a:-absente}) devrait précéder $2 (ligne ${b:-absente})"; fi
}
# Après CHAQUE refus de la garde : rien de déposé, ni sshd ni systemctl appelés.
assert_rien() {
    assert_egal "absent" "$(present)"  "refus « $1 » : aucun dépôt"
    assert_egal "0" "$(modifications)" "refus « $1 » : aucun appel"
}

titre "Aide et options"
lancer bash "$CIBLE" --help
assert_code 0 "$CODE" "--help rend 0"
assert_contient "$SORTIE" "--utilisateur"         "--help documente les options"
assert_contient "$SORTIE" "SRV_ADMIN_UTILISATEUR" "--help nomme la variable lue"
assert_contient "$SORTIE" "10-mgnetworking.conf"  "--help nomme le fichier déposé"
assert_contient "$SORTIE" "systemctl reload ssh"  "--help dit le rechargement employé"
assert_contient "$SORTIE" "2 option"              "--help documente les codes de retour"
lancer bash "$CIBLE" --frobnicate
assert_code 2 "$CODE" "une option inconnue rend 2"
lancer bash "$CIBLE" --utilisateur
assert_code 2 "$CODE" "--utilisateur sans valeur rend 2"
lancer bash "$CIBLE" --utilisateur "Ad Min"
assert_code 2 "$CODE" "un nom de compte invalide rend 2"

titre "Garde de la décision 20 — refus en 1, en nommant le compte"
etat_neuf
lancer bash "$CIBLE" -y
assert_code 1 "$CODE" "sans compte nommé : rend 1"
assert_contient "$SORTIE" "--utilisateur" "le refus dit où prendre le nom"
assert_rien "sans compte nommé"
etat_neuf; : > "$PASSWD_FACTICE"
lancer bash "$CIBLE" -y --utilisateur fantome
assert_code 1 "$CODE" "compte introuvable : rend 1"
assert_contient "$SORTIE" "fantome" "le refus nomme le compte"
assert_rien "compte introuvable"
# toor a tout pour plaire — sudo et clé — sauf l'UID 0 : seul ce contrôle peut
# produire le refus, et il doit nommer le compte.
etat_neuf
printf 'toor:x:0:0::%s:/bin/bash\n' "$HOME_ROOT" > "$PASSWD_FACTICE"
printf 'sudo:x:27:toor\n' > "$GROUP_FACTICE"
printf 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBExemple toor@poste\n' > "$HOME_ROOT/.ssh/authorized_keys"
lancer bash "$CIBLE" -y --utilisateur toor
assert_code 1 "$CODE" "un compte d'UID 0 : rend 1"
assert_contient "$SORTIE" "toor" "le refus nomme le compte d'UID 0"
assert_rien "compte d'UID 0"
etat_neuf
lancer bash "$CIBLE" -y --utilisateur root
assert_code 1 "$CODE" "« root » nommé : rend 1"
assert_contient "$SORTIE" "root" "le refus nomme « root »"
assert_rien "« root » nommé"
etat_neuf; printf 'sudo:x:27:\n' > "$GROUP_FACTICE"
lancer bash "$CIBLE" -y --utilisateur admin
assert_code 1 "$CODE" "hors du groupe sudo : rend 1"
assert_contient "$SORTIE" "sudo" "le refus nomme le groupe manquant"
assert_contient "$SORTIE" "admin" "le refus hors sudo nomme le compte"
assert_rien "hors du groupe sudo"
etat_neuf; : > "$HOME_ADMIN/.ssh/authorized_keys"
lancer bash "$CIBLE" -y --utilisateur admin
assert_code 1 "$CODE" "authorized_keys vide : rend 1"
assert_rien "authorized_keys vide"
etat_neuf; printf '# aucune clé ici\n\n' > "$HOME_ADMIN/.ssh/authorized_keys"
lancer bash "$CIBLE" -y --utilisateur admin
assert_code 1 "$CODE" "authorized_keys sans clé : rend 1"
assert_rien "authorized_keys sans clé"
etat_neuf; rm -f "$HOME_ADMIN/.ssh/authorized_keys"
lancer bash "$CIBLE" -y --utilisateur admin
assert_code 1 "$CODE" "authorized_keys absent : rend 1"
assert_contient "$SORTIE" "authorized_keys" "le refus nomme le fichier attendu"
assert_egal "absent" "$(present)"            "aucun refus n'a déposé de fichier"
assert_egal "0" "$(modifications)"           "aucun refus n'a appelé sshd ni systemctl"

titre "Membre de sudo par son groupe primaire — accepté"
etat_neuf
printf 'admin:x:1000:27:Admin:%s:/bin/bash\n' "$HOME_ADMIN" > "$PASSWD_FACTICE"
printf 'sudo:x:27:\n' > "$GROUP_FACTICE"
lancer bash "$CIBLE" -y --utilisateur admin
assert_code 0 "$CODE" "GID primaire = GID de sudo, liste vide : rend 0"
assert_egal "présent" "$(present)" "le dépôt a bien eu lieu"
assert_contient "$(cat "$JOURNAL")" "systemctl reload ssh" "le rechargement a bien eu lieu"

titre "Inclusion de sshd_config.d — refus en 1"
etat_neuf; printf 'Port 22\n' > "$SSHD_CONFIG"
lancer bash "$CIBLE" -y --utilisateur admin
assert_code 1 "$CODE" "sshd_config sans Include : rend 1"
assert_contient "$SORTIE" "sshd_config.d/*.conf" "le refus nomme l'inclusion attendue"
assert_egal "0" "$(modifications)" "rien n'est validé ni rechargé"

titre "--dry-run — l'état et les actions prévues, sans rien modifier"
etat_neuf
lancer bash "$CIBLE" --dry-run --utilisateur admin
assert_code 0 "$CODE" "--dry-run rend 0"
assert_contient "$SORTIE" "absent, à déposer"           "--dry-run montre l'état du fichier"
assert_contient "$SORTIE" "PasswordAuthentication no"   "--dry-run montre le contenu prévu"
assert_contient "$SORTIE" "systemctl reload ssh"        "--dry-run montre le rechargement prévu"
assert_contient "$SORTIE" "1 clé(s)"                    "--dry-run montre la clé trouvée"
assert_egal "absent" "$(present)"  "--dry-run n'écrit rien"
assert_egal "0" "$(modifications)" "--dry-run n'appelle ni sshd ni systemctl"

titre "Exécution — dépôt en 0644, « sshd -t », puis rechargement"
etat_neuf
lancer env SRV_ADMIN_UTILISATEUR=admin bash "$CIBLE" -y
assert_code 0 "$CODE" "configuration appliquée : rend 0"
assert_egal "$(printf '# Déposé par Linux/Security/configure-ssh.sh.\nPasswordAuthentication no\nKbdInteractiveAuthentication no\nPubkeyAuthentication yes')" \
    "$(depot)" "le fichier déposé porte exactement les trois directives"
assert_absent "$(depot)" "Port" "le port n'est pas touché"
assert_egal "644" "$(stat -c '%a' "$DEPOT")" "le dépôt est en 0644"
assert_egal "1" "$(find "$SSHD_CONFIG_D" -mindepth 1 | wc -l)" "aucun fichier temporaire ne subsiste"
assert_avant "sshd -t" "systemctl reload ssh" "« sshd -t » précède le rechargement"
assert_contient "$(cat "$JOURNAL")" "reload ssh" "le rechargement passe par reload ssh"
assert_absent "$(cat "$JOURNAL")" "restart"      "aucun « restart » n'est employé"
assert_contient "$SORTIE" "session ouverte" "l'avertissement demande de garder la session"
assert_contient "$SORTIE" "SSH durci"       "le succès est annoncé"

titre "Seconde exécution — identique, rien n'est réécrit ni rechargé"
AVANT="$(stat -c '%i %Y %s' "$DEPOT")"; : > "$JOURNAL"
lancer bash "$CIBLE" -y --utilisateur admin
assert_code 0 "$CODE" "seconde exécution rend 0, sans confirmation à donner"
assert_contient "$SORTIE" "déjà conforme" "elle dit ne rien avoir à faire"
assert_egal "$AVANT" "$(stat -c '%i %Y %s' "$DEPOT")" "le fichier n'est pas réécrit"
assert_egal "0" "$(modifications)" "ni « sshd -t » ni rechargement"

titre "« sshd -t » refuse — l'état antérieur est restauré, rien n'est rechargé"
etat_neuf
printf '# ancien fichier\nPasswordAuthentication yes\n' > "$DEPOT"
: > "$SSHD_REFUS"
lancer bash "$CIBLE" -y --utilisateur admin
assert_code 1 "$CODE" "« sshd -t » en échec : rend 1"
assert_contient "$SORTIE" "restauré" "le message dit l'état antérieur restauré"
assert_contient "$SORTIE" "mauvaise configuration" "le refus affiche la sortie d'erreur de sshd"
assert_egal "$(printf '# ancien fichier\nPasswordAuthentication yes')" "$(depot)" "le contenu antérieur est en place"
assert_egal "0" "$(grep -c systemctl "$JOURNAL" || true)" "aucun rechargement n'a suivi"
assert_egal "1" "$(find "$SSHD_CONFIG_D" -mindepth 1 | wc -l)" "aucun fichier temporaire ne subsiste"
etat_neuf; : > "$SSHD_REFUS"
lancer bash "$CIBLE" -y --utilisateur admin
assert_code 1 "$CODE" "« sshd -t » en échec, sans état antérieur : rend 1"
assert_egal "absent" "$(present)" "le fichier déposé est retiré"

titre "« systemctl reload ssh » échoue — l'état antérieur est restauré"
etat_neuf; : > "$SYSTEMCTL_REFUS"
lancer bash "$CIBLE" -y --utilisateur admin
assert_code 1 "$CODE" "rechargement en échec : rend 1"
assert_contient "$SORTIE" "restauré" "le message dit l'état antérieur restauré"
assert_egal "absent" "$(present)" "sans état antérieur, le dépôt est retiré"
assert_egal "0" "$(find "$SSHD_CONFIG_D" -mindepth 1 | wc -l)" "ni dépôt ni temporaire ne subsistent"
etat_neuf
printf '# ancien fichier\nPasswordAuthentication yes\n' > "$DEPOT"
: > "$SYSTEMCTL_REFUS"
lancer bash "$CIBLE" -y --utilisateur admin
assert_code 1 "$CODE" "rechargement en échec, avec état antérieur : rend 1"
assert_egal "$(printf '# ancien fichier\nPasswordAuthentication yes')" "$(depot)" "le contenu antérieur est en place"
assert_egal "1" "$(find "$SSHD_CONFIG_D" -mindepth 1 | wc -l)" "aucun fichier temporaire ne subsiste"
# Le dépôt a été retiré : la relance doit reprendre le travail, et non dire
# « déjà conforme » — ce que ferait un fichier laissé en place après l'échec.
rm -f "$SYSTEMCTL_REFUS"; : > "$JOURNAL"
lancer bash "$CIBLE" -y --utilisateur admin
assert_code 0 "$CODE" "la relance après l'échec rend 0"
assert_absent "$SORTIE" "déjà conforme" "elle ne croit pas le travail fait"
assert_contient "$(depot)" "PasswordAuthentication no" "le dépôt est en place"
assert_contient "$(cat "$JOURNAL")" "sshd -t" "« sshd -t » a été rejoué"
assert_contient "$(cat "$JOURNAL")" "systemctl reload ssh" "le rechargement a eu lieu"

titre "Confirmation — sans terminal ni --yes, et décision 45"
etat_neuf
lancer bash "$CIBLE" --utilisateur admin
assert_code 1 "$CODE" "sans terminal et sans --yes : rend 1"
assert_contient "$SORTIE" "--yes"     "le message nomme l'option qui débloque"
assert_absent "$SORTIE" "Échec (code" "aucune ligne du trap ERR : refus délibéré"
assert_egal "absent" "$(present)"     "rien n'est déposé avant la confirmation"
assert_egal "0" "$(modifications)"    "rien n'est validé ni rechargé"
etat_neuf
lancer env ASSUME_YES=true bash "$CIBLE" --utilisateur admin
assert_code 1 "$CODE" "un ASSUME_YES hérité, sans terminal, ne suffit pas"
assert_egal "absent" "$(present)" "rien n'est déposé"
etat_neuf
if command -v script >/dev/null 2>&1; then
    # Avec un terminal, un ASSUME_YES hérité non remis à false confirmerait tout
    # seul : c'est ici, et nulle part ailleurs, que la remise à false se prouve.
    CODE=0
    SORTIE="$(printf 'n\n' | PATH="$FAUX:$PATH" ASSUME_YES=true \
        script -qec "bash $CIBLE --utilisateur admin" /dev/null 2>&1)" || CODE=$?
    assert_code 1 "$CODE" "ASSUME_YES hérité, avec un terminal : rend 1"
    assert_absent "$SORTIE" "Confirmation automatique" "l'ASSUME_YES du parent est ignoré"
    assert_contient "$SORTIE" "abandonnée" "la question est posée et « n » l'écarte"
    assert_egal "absent" "$(present)" "rien n'est déposé après ce refus"
else
    saute_indisponible "ASSUME_YES hérité avec un terminal" "script (util-linux) absent"
fi

titre "Hors des cibles de la décision 14, et sans root"
etat_neuf
lancer env OS_ID=centos bash "$CIBLE" -y --utilisateur admin
assert_code 1 "$CODE" "distribution hors cibles : rend 1"
assert_contient "$SORTIE" "Distribution non supportée" "le refus nomme la distribution"
assert_egal "absent" "$(present)" "aucun dépôt avant le contrôle de distribution"
etat_neuf
lancer setpriv --reuid=65534 --regid=65534 --clear-groups -- bash "$CIBLE" -y --utilisateur admin
assert_code 1 "$CODE" "sans privilège root : rend 1"
assert_contient "$SORTIE" "root" "le refus nomme le privilège manquant"
assert_egal "absent" "$(present)" "aucun dépôt sans root"

bilan "TASK-046 / configure-ssh.sh"
