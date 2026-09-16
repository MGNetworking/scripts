#!/usr/bin/env bash
set -Eeuo pipefail
# tests/integration/disable-root-login.test.sh — Linux/Security/disable-root-login.sh
# (TASK-047). Ni sshd ni systemctl réels : deux faux en tête de PATH tracent chaque
# appel, un faux getent sert les comptes, /etc/ssh est un bac à sable. Le journal
# prouve l'ordre « sshd -t » → « sshd -T » → rechargement, l'absence de « restart »,
# et qu'un refus n'écrit rien. SSHD_REFUS, SSHD_T_REFUS, SSHD_T_VALEUR et
# SYSTEMCTL_REFUS font échouer les faux — ou mentir « sshd -T » — à volonté.
_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_dir/lib/common.sh" ] && [ "$_dir" != "/" ]; do _dir="$(dirname "$_dir")"; done
source "$_dir/lib/common.sh"
source "$SCRIPTS_ROOT/tests/lib/assert.sh"
CIBLE="$SCRIPTS_ROOT/Linux/Security/disable-root-login.sh"
BAC="$(mktemp -d)"; FAUX="$BAC/bin"; HOME_ADMIN="$BAC/home/admin"
chmod 755 "$BAC"; mkdir -p "$FAUX" "$HOME_ADMIN/.ssh"
export JOURNAL="$BAC/appels.log" SSHD_CONFIG="$BAC/sshd_config" SSHD_CONFIG_D="$BAC/sshd_config.d"
export PASSWD_FACTICE="$BAC/passwd" GROUP_FACTICE="$BAC/group"
export SSHD_REFUS="$BAC/sshd-refus" SSHD_T_REFUS="$BAC/sshd-t-refus" SSHD_T_VALEUR="$BAC/sshd-t-valeur"
export SYSTEMCTL_REFUS="$BAC/systemctl-refus" DEPOT="$SSHD_CONFIG_D/05-mgnetworking-root.conf"
trap 'rm -rf "$BAC"' EXIT
cat > "$FAUX/sshd" <<'EOF'
#!/bin/sh
printf 'sshd %s\n' "$*" >> "$JOURNAL"
case "$*" in
*-T*) [ -f "$SSHD_T_REFUS" ] && { printf "sshd: aucune clé d'hôte\n" >&2; exit 1; }
      printf 'permitrootlogin %s\n' "$(cat "$SSHD_T_VALEUR" 2>/dev/null || printf no)"; exit 0 ;;
esac
[ -f "$SSHD_REFUS" ] && { printf 'sshd: mauvaise configuration\n' >&2; exit 1; }
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
etat_neuf() {
    printf 'Include /etc/ssh/sshd_config.d/*.conf\n' > "$SSHD_CONFIG"
    rm -rf "$SSHD_CONFIG_D"; mkdir -p "$SSHD_CONFIG_D"
    rm -f "$SSHD_REFUS" "$SSHD_T_REFUS" "$SSHD_T_VALEUR" "$SYSTEMCTL_REFUS"; : > "$JOURNAL"
    printf 'admin:x:1000:1000:Admin:%s:/bin/bash\n' "$HOME_ADMIN" > "$PASSWD_FACTICE"
    printf 'sudo:x:27:admin\n' > "$GROUP_FACTICE"
    printf 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBExemple admin@poste\n' > "$HOME_ADMIN/.ssh/authorized_keys"
}
lancer() { CODE=0; SORTIE="$(PATH="$FAUX:$PATH" "$@" 2>&1 </dev/null)" || CODE=$?; }
depot() { cat "$DEPOT" 2>/dev/null || true; }
present() { [ -e "$DEPOT" ] && printf 'présent' || printf 'absent'; }
appels() { grep -cE '^(sshd|systemctl)' "$JOURNAL" || true; }
rechargements() { grep -c systemctl "$JOURNAL" || true; }
rang() { grep -nF -- "$1" "$JOURNAL" 2>/dev/null | head -n1 | cut -d: -f1 || true; }
avant() { local a b; a="$(rang "$1")"; b="$(rang "$2")"; if [ -n "$a" ] && [ -n "$b" ] && [ "$a" -lt "$b" ]; then ok "$3"; else ko "$3" "$1 (ligne ${a:-absente}) devrait précéder $2 (ligne ${b:-absente})"; fi; }
refus() { local libelle="$1" motif="$2"; shift 2; lancer bash "$CIBLE" "$@"; assert_code 1 "$CODE" "$libelle : rend 1"; assert_contient "$SORTIE" "$motif" "$libelle : le refus nomme la cause"; assert_egal "absent" "$(present)" "refus « $libelle » : aucun dépôt"; assert_egal "0" "$(appels)" "refus « $libelle » : ni sshd ni systemctl"; }

# Garde : un vrai sshd ou un vrai systemctl atteint par mégarde agirait sur la machine.
if [ "$(PATH="$FAUX:$PATH" command -v sshd)" != "$FAUX/sshd" ] || [ "$(PATH="$FAUX:$PATH" command -v systemctl)" != "$FAUX/systemctl" ]; then
    saute_indisponible "faux sshd et systemctl en tête de PATH" "PATH ne les désigne pas dans $FAUX"
    bilan "TASK-047 / disable-root-login.sh"
fi
titre "1. Aide et options"; lancer bash "$CIBLE" --help; assert_code 0 "$CODE" "--help rend 0"
for motif in "--utilisateur" "SRV_ADMIN_UTILISATEUR" "05-mgnetworking-root.conf" "sshd -T" "systemctl reload ssh" "2 option"; do assert_contient "$SORTIE" "$motif" "--help documente « $motif »"; done
lancer bash "$CIBLE" --frobnicate; assert_code 2 "$CODE" "une option inconnue rend 2"
lancer bash "$CIBLE" --utilisateur; assert_code 2 "$CODE" "--utilisateur sans valeur rend 2"
lancer bash "$CIBLE" --utilisateur "Ad Min"; assert_code 2 "$CODE" "un nom de compte invalide rend 2"
titre "2. Garde de la décision 20 — refus en 1, en nommant la cause"
etat_neuf; refus "sans compte nommé" "--utilisateur" -y
etat_neuf; : > "$PASSWD_FACTICE"; refus "compte introuvable" "fantome" -y --utilisateur fantome
etat_neuf; printf 'toor:x:0:0::%s:/bin/bash\n' "$HOME_ADMIN" > "$PASSWD_FACTICE"; printf 'sudo:x:27:toor\n' > "$GROUP_FACTICE"; refus "compte d'UID 0" "toor" -y --utilisateur toor
etat_neuf; refus "« root » nommé" "non-root" -y --utilisateur root
etat_neuf; printf 'sudo:x:27:\n' > "$GROUP_FACTICE"; refus "hors du groupe sudo" "sudo" -y --utilisateur admin
etat_neuf; rm -f "$HOME_ADMIN/.ssh/authorized_keys"; refus "authorized_keys absent" "authorized_keys" -y --utilisateur admin
etat_neuf; printf 'Port 22\n' > "$SSHD_CONFIG"; refus "sshd_config sans Include" "sshd_config.d/*.conf" -y --utilisateur admin
titre "3. --dry-run — l'état et les actions prévues, sans rien modifier"
etat_neuf; lancer bash "$CIBLE" --dry-run --utilisateur admin; assert_code 0 "$CODE" "--dry-run rend 0"
for motif in "absent, à déposer" "PermitRootLogin no" "systemctl reload ssh" "1 clé(s)"; do assert_contient "$SORTIE" "$motif" "--dry-run montre « $motif »"; done
assert_egal "absent" "$(present)" "--dry-run n'écrit rien"; assert_egal "0" "$(appels)" "--dry-run n'appelle ni sshd ni systemctl"
titre "4. Exécution — dépôt en 0644, « sshd -t », « sshd -T », puis rechargement"
etat_neuf; lancer env SRV_ADMIN_UTILISATEUR=admin bash "$CIBLE" -y
assert_code 0 "$CODE" "configuration appliquée : rend 0"; assert_egal "644" "$(stat -c '%a' "$DEPOT")" "le dépôt est en 0644"
assert_egal "$(printf '# Déposé par Linux/Security/disable-root-login.sh.\nPermitRootLogin no')" "$(depot)" "le fichier déposé porte exactement la directive"
assert_egal "1" "$(find "$SSHD_CONFIG_D" -mindepth 1 | wc -l)" "aucun fichier temporaire ne subsiste"
avant "sshd -t" "sshd -T" "« sshd -t » précède « sshd -T »"
avant "sshd -T" "systemctl reload ssh" "« sshd -T » précède le rechargement"
assert_absent "$(cat "$JOURNAL")" "restart" "aucun « restart » n'est employé"; assert_contient "$SORTIE" "session ouverte" "l'avertissement demande de garder la session"
titre "5. Seconde exécution — identique, rien n'est réécrit ni rechargé"
AVANT="$(stat -c '%i %Y %s' "$DEPOT")"; : > "$JOURNAL"; lancer bash "$CIBLE" -y --utilisateur admin
assert_code 0 "$CODE" "seconde exécution rend 0, sans confirmation à donner"; assert_contient "$SORTIE" "déjà conforme" "elle dit ne rien avoir à faire"
assert_egal "$AVANT" "$(stat -c '%i %Y %s' "$DEPOT")" "le fichier n'est pas réécrit"; assert_egal "0" "$(appels)" "ni écriture, ni « sshd -t », ni rechargement"
ANCIEN="$(printf '# ancien\nPermitRootLogin yes')"
titre "6. « sshd -t » refuse — l'état antérieur est restauré, rien n'est rechargé"
etat_neuf; printf '# ancien\nPermitRootLogin yes\n' > "$DEPOT"; : > "$SSHD_REFUS"; lancer bash "$CIBLE" -y --utilisateur admin
assert_code 1 "$CODE" "« sshd -t » en échec : rend 1"; assert_contient "$SORTIE" "restauré" "le message dit l'état antérieur restauré"
assert_contient "$SORTIE" "mauvaise configuration" "le refus affiche la sortie d'erreur de sshd"
assert_egal "$ANCIEN" "$(depot)" "le contenu antérieur est en place"; assert_egal "0" "$(rechargements)" "aucun rechargement n'a suivi"
assert_egal "1" "$(find "$SSHD_CONFIG_D" -mindepth 1 | wc -l)" "aucun fichier temporaire ne subsiste"
titre "7. « sshd -T » ne confirme pas permitrootlogin no — restauré, en 1"
etat_neuf; printf '# ancien\nPermitRootLogin yes\n' > "$DEPOT"; printf 'yes\n' > "$SSHD_T_VALEUR"; lancer bash "$CIBLE" -y --utilisateur admin
assert_code 1 "$CODE" "valeur effective « yes » : rend 1"; assert_contient "$SORTIE" "permitrootlogin yes" "le refus cite la valeur effective"
assert_contient "$SORTIE" "restauré" "le message dit l'état antérieur restauré"; assert_egal "$ANCIEN" "$(depot)" "le contenu antérieur est en place"
assert_egal "0" "$(rechargements)" "aucun rechargement n'a suivi"
etat_neuf; : > "$SSHD_T_REFUS"; lancer bash "$CIBLE" -y --utilisateur admin
assert_code 1 "$CODE" "« sshd -T » en échec : rend 1"; assert_contient "$SORTIE" "clé d'hôte" "le refus affiche la sortie d'erreur de sshd"; assert_egal "absent" "$(present)" "sans état antérieur, le dépôt est retiré"
titre "8. « systemctl reload ssh » échoue — l'état antérieur est restauré"
etat_neuf; : > "$SYSTEMCTL_REFUS"; lancer bash "$CIBLE" -y --utilisateur admin
assert_code 1 "$CODE" "rechargement en échec : rend 1"; assert_contient "$SORTIE" "restauré" "le message dit l'état antérieur restauré"; assert_egal "absent" "$(present)" "sans état antérieur, le dépôt est retiré"
etat_neuf; printf '# ancien\nPermitRootLogin yes\n' > "$DEPOT"; : > "$SYSTEMCTL_REFUS"; lancer bash "$CIBLE" -y --utilisateur admin
assert_egal "$ANCIEN" "$(depot)" "le contenu antérieur est en place"
rm -f "$SYSTEMCTL_REFUS"; : > "$JOURNAL"; lancer bash "$CIBLE" -y --utilisateur admin
assert_code 0 "$CODE" "la relance après l'échec rend 0"; assert_absent "$SORTIE" "déjà conforme" "elle ne croit pas le travail fait"
assert_contient "$(cat "$JOURNAL")" "systemctl reload ssh" "le rechargement a eu lieu"
titre "9. Confirmation — sans terminal ni --yes, et décision 45"
etat_neuf; lancer bash "$CIBLE" --utilisateur admin
assert_code 1 "$CODE" "sans terminal et sans --yes : rend 1"; assert_contient "$SORTIE" "--yes" "le message nomme l'option qui débloque"
assert_egal "absent" "$(present)" "rien n'est déposé avant la confirmation"
lancer env ASSUME_YES=true bash "$CIBLE" --utilisateur admin; assert_code 1 "$CODE" "un ASSUME_YES hérité, sans terminal, ne suffit pas"; assert_egal "absent" "$(present)" "rien n'est déposé, là non plus"
if command -v script >/dev/null 2>&1; then
    CODE=0; SORTIE="$(printf 'n\n' | PATH="$FAUX:$PATH" ASSUME_YES=true script -qec "bash $CIBLE --utilisateur admin" /dev/null 2>&1)" || CODE=$?
    assert_code 1 "$CODE" "ASSUME_YES hérité, avec un terminal : rend 1"
    assert_absent "$SORTIE" "Confirmation automatique" "l'ASSUME_YES du parent est ignoré"
    assert_contient "$SORTIE" "abandonnée" "la question est posée et « n » l'écarte"
else
    saute_indisponible "ASSUME_YES hérité avec un terminal" "script (util-linux) absent"
fi
titre "10. Hors des cibles de la décision 14, et sans root"
etat_neuf; lancer env OS_ID=centos bash "$CIBLE" -y --utilisateur admin
assert_code 1 "$CODE" "distribution hors cibles : rend 1"; assert_contient "$SORTIE" "Distribution non supportée" "le refus nomme la distribution"
assert_egal "absent" "$(present)" "aucun dépôt avant le contrôle de distribution"
etat_neuf; lancer setpriv --reuid=65534 --regid=65534 --clear-groups -- bash "$CIBLE" -y --utilisateur admin
assert_code 1 "$CODE" "sans privilège root : rend 1"; assert_contient "$SORTIE" "root" "le refus nomme le privilège manquant"
assert_egal "absent" "$(present)" "aucun dépôt sans root"

bilan "TASK-047 / disable-root-login.sh"
