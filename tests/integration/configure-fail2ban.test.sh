#!/usr/bin/env bash
set -Eeuo pipefail
# tests/integration/configure-fail2ban.test.sh — Linux/Security/configure-fail2ban.sh
# (TASK-044). Aucune installation réelle : de faux apt-get, dpkg-query, systemctl et
# fail2ban-client en tête de PATH tracent chaque appel, jail.d est un bac à sable.
# PAQUET_POSE commande la réponse de dpkg-query, APT_REFUS fait échouer apt-get,
# SERVICE_ENABLED et SERVICE_ACTIF répondent à systemctl, F2B_REFUS fait échouer
# fail2ban-client — dont le faux exige que la prison ait été déposée.
_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_dir/lib/common.sh" ] && [ "$_dir" != "/" ]; do _dir="$(dirname "$_dir")"; done
source "$_dir/lib/common.sh"
source "$SCRIPTS_ROOT/tests/lib/assert.sh"
CIBLE="$SCRIPTS_ROOT/Linux/Security/configure-fail2ban.sh"
BAC="$(mktemp -d)"; FAUX="$BAC/bin"; JAIL_D="$BAC/jail.d"; DEPOT="$JAIL_D/mgnetworking-sshd.conf"
chmod 755 "$BAC"; mkdir -p "$FAUX"
export JOURNAL="$BAC/appels.log" FAIL2BAN_JAIL_D="$JAIL_D" DEPOT="$DEPOT"
export PAQUET_POSE="$BAC/paquet" APT_REFUS="$BAC/apt-refus" F2B_REFUS="$BAC/f2b-refus"
export SERVICE_ENABLED="$BAC/enabled" SERVICE_ACTIF="$BAC/actif" SYSTEMCTL_REFUS="$BAC/systemctl-refus"
ATTENDU="# Déposé par Linux/Security/configure-fail2ban.sh.
# Valeurs de la distribution : aucune option n'est fixée ici (décision 22).
[sshd]
enabled = true"
trap 'rm -rf "$BAC"' EXIT
cat > "$FAUX/dpkg-query" <<'EOF'
#!/bin/sh
printf 'dpkg-query %s\n' "$*" >> "$JOURNAL"
[ -f "$PAQUET_POSE" ] || exit 1
printf 'install ok installed\n'
EOF
cat > "$FAUX/apt-get" <<'EOF'
#!/bin/sh
printf 'apt-get %s\n' "$*" >> "$JOURNAL"
case "$1" in
install) [ -f "$APT_REFUS" ] && exit 100
         : > "$PAQUET_POSE"; mkdir -p "$FAIL2BAN_JAIL_D" ;;
esac
exit 0
EOF
cat > "$FAUX/systemctl" <<'EOF'
#!/bin/sh
printf 'systemctl %s\n' "$*" >> "$JOURNAL"
case "$1" in
is-enabled) [ -f "$SERVICE_ENABLED" ] && { echo enabled; exit 0; }; echo disabled; exit 1 ;;
is-active)  [ -f "$SERVICE_ACTIF" ] && { echo active; exit 0; }; echo inactive; exit 3 ;;
enable)     [ -f "$SYSTEMCTL_REFUS" ] && exit 1; : > "$SERVICE_ENABLED"; exit 0 ;;
restart)    [ -f "$SYSTEMCTL_REFUS" ] && exit 1; : > "$SERVICE_ACTIF"; exit 0 ;;
esac
exit 0
EOF
cat > "$FAUX/fail2ban-client" <<'EOF'
#!/bin/sh
printf 'fail2ban-client %s\n' "$*" >> "$JOURNAL"
[ -f "$F2B_REFUS" ] && { echo 'ERROR  NOK: sshd not found' >&2; exit 1; }
[ -f "$DEPOT" ] || { echo 'ERROR  Jail sshd not found' >&2; exit 1; }
echo 'Status for the jail: sshd'
EOF
chmod +x "$FAUX"/*
etat_neuf() { rm -rf "$JAIL_D"; rm -f "$PAQUET_POSE" "$SERVICE_ACTIF" "$SERVICE_ENABLED" "$F2B_REFUS" "$APT_REFUS" "$SYSTEMCTL_REFUS"; : > "$JOURNAL"; }
etat_pret() { etat_neuf; mkdir -p "$JAIL_D"; : > "$PAQUET_POSE"; : > "$SERVICE_ACTIF"; : > "$SERVICE_ENABLED"; : > "$JOURNAL"; }
lancer() { CODE=0; SORTIE="$(PATH="$FAUX:$PATH" "$@" 2>&1 </dev/null)" || CODE=$?; }
depot() { cat "$DEPOT" 2>/dev/null || true; }
present() { [ -e "$DEPOT" ] && printf 'présent' || printf 'absent'; }
appels() { grep -cE "$1" "$JOURNAL" || true; }
mutations() { appels '^systemctl (enable|restart|start|stop) '; }
rang() { grep -nF -- "$1" "$JOURNAL" 2>/dev/null | head -n1 | cut -d: -f1 || true; }
avant() { local a b; a="$(rang "$1")"; b="$(rang "$2")"; if [ -n "$a" ] && [ -n "$b" ] && [ "$a" -lt "$b" ]; then ok "$3"; else ko "$3" "$1 (ligne ${a:-absente}) devrait précéder $2 (ligne ${b:-absente})"; fi; }

# Garde : un vrai apt-get, systemctl ou fail2ban-client atteint par mégarde agirait sur la machine.
if [ "$(PATH="$FAUX:$PATH" command -v dpkg-query)" != "$FAUX/dpkg-query" ] || [ "$(PATH="$FAUX:$PATH" command -v fail2ban-client)" != "$FAUX/fail2ban-client" ]; then
    saute_indisponible "faux binaires en tête de PATH" "PATH ne les désigne pas dans $FAUX"
    bilan "TASK-044 / configure-fail2ban.sh"
fi
titre "1. Aide et options"; lancer bash "$CIBLE" --help; assert_code 0 "$CODE" "--help rend 0"
for motif in "--dry-run" "--yes" "jail.d" "[sshd]" "enabled = true" "fail2ban-client status sshd" "2 option"; do
    assert_contient "$SORTIE" "$motif" "--help documente « $motif »"
done
lancer bash "$CIBLE" --frobnicate; assert_code 2 "$CODE" "une option inconnue rend 2"
titre "2. Root et cibles de la décision 14 — refus en 1, rien de modifié"
etat_pret; lancer setpriv --reuid=65534 --regid=65534 --clear-groups -- bash "$CIBLE" -y
assert_code 1 "$CODE" "sans privilège root : rend 1"; assert_contient "$SORTIE" "root" "le refus nomme le privilège manquant"
assert_egal "absent" "$(present)" "aucun dépôt sans root"; assert_egal "0" "$(mutations)" "aucun service touché sans root"
etat_pret; lancer env OS_ID=centos bash "$CIBLE" -y
assert_code 1 "$CODE" "une distribution hors cibles rend 1"; assert_contient "$SORTIE" "Distribution non supportée" "le refus nomme la distribution"
assert_egal "absent" "$(present)" "aucun dépôt hors cibles de la décision 14"
titre "3. --dry-run — l'état et ce qui serait fait, sans rien modifier"
etat_pret; lancer bash "$CIBLE" --dry-run; assert_code 0 "$CODE" "--dry-run rend 0"
for motif in "paquet fail2ban : installé" "absent, à déposer" "Contenu prévu" "systemctl restart" "fail2ban-client status sshd"; do
    assert_contient "$SORTIE" "$motif" "--dry-run montre « $motif »"
done
assert_egal "absent" "$(present)" "--dry-run n'écrit rien"; assert_egal "0" "$(mutations)" "--dry-run ne touche pas au service"
etat_neuf; lancer bash "$CIBLE" --dry-run; assert_code 0 "$CODE" "--dry-run rend 0 sans paquet installé"
assert_contient "$SORTIE" "absent, à installer par apt-get" "l'état annonce l'installation à venir"
assert_contient "$SORTIE" "apt-get install -y fail2ban" "les actions annoncent l'installation"
assert_egal "0" "$(appels '^apt-get')" "--dry-run n'appelle pas apt-get"
titre "4. Confirmation — sans terminal ni --yes, refus en 1"
etat_pret; lancer bash "$CIBLE"
assert_code 1 "$CODE" "sans terminal et sans --yes : rend 1"; assert_contient "$SORTIE" "--yes" "le message nomme l'option qui débloque"
assert_contient "$SORTIE" "absent, à déposer" "le changement est annoncé avant la question"
assert_egal "absent" "$(present)" "rien n'est déposé avant la confirmation"; assert_egal "0" "$(mutations)" "le service n'est pas touché avant la confirmation"
lancer env ASSUME_YES=true bash "$CIBLE"
assert_code 1 "$CODE" "un ASSUME_YES hérité, sans terminal, ne suffit pas"; assert_egal "absent" "$(present)" "rien n'est déposé, là non plus"
if command -v script >/dev/null 2>&1; then
    CODE=0; SORTIE="$(printf 'n\n' | PATH="$FAUX:$PATH" ASSUME_YES=true script -qec "bash $CIBLE" /dev/null 2>&1)" || CODE=$?
    assert_code 1 "$CODE" "ASSUME_YES hérité, avec un terminal : rend 1"
    assert_absent "$SORTIE" "Confirmation automatique" "l'ASSUME_YES du parent est ignoré"
    assert_contient "$SORTIE" "abandonnée" "la question est posée et « n » l'écarte"
    assert_egal "absent" "$(present)" "un refus n'écrit rien"
else
    saute_indisponible "ASSUME_YES hérité avec un terminal" "script (util-linux) absent"
fi
titre "5. Exécution — paquet absent : installé, prison déposée, service activé et redémarré"
etat_neuf; lancer bash "$CIBLE" --yes; assert_code 0 "$CODE" "configuration appliquée : rend 0"
assert_contient "$(cat "$JOURNAL")" "apt-get install -y fail2ban" "le paquet est installé par apt-get"
assert_egal "644" "$(stat -c '%a' "$DEPOT")" "le dépôt est en 0644"
assert_egal "$ATTENDU" "$(depot)" "le fichier porte exactement [sshd] enabled = true"
assert_egal "1" "$(find "$JAIL_D" -mindepth 1 | wc -l)" "aucun fichier temporaire ne subsiste"
assert_contient "$(cat "$JOURNAL")" "systemctl enable fail2ban" "le service est activé"
assert_contient "$(cat "$JOURNAL")" "systemctl restart fail2ban" "le service est redémarré"
assert_contient "$SORTIE" "prison sshd active" "le succès nomme la prison vérifiée"
avant "apt-get update" "apt-get install" "« apt-get update » précède l'installation"
avant "apt-get install" "systemctl restart fail2ban" "l'installation précède le redémarrage"
avant "systemctl restart fail2ban" "fail2ban-client status sshd" "la vérification suit le redémarrage"
titre "6. Seconde exécution — identique : rien n'est réinstallé, réécrit ni redémarré"
AVANT="$(stat -c '%i %Y %s' "$DEPOT")"; : > "$JOURNAL"; lancer bash "$CIBLE"
assert_code 0 "$CODE" "seconde exécution sans --yes : rend 0, aucune question"
assert_contient "$SORTIE" "déjà conforme" "elle dit ne rien avoir à faire"
assert_egal "$AVANT" "$(stat -c '%i %Y %s' "$DEPOT")" "le fichier n'est pas réécrit"
assert_egal "0" "$(appels '^apt-get')" "rien n'est réinstallé"; assert_egal "0" "$(mutations)" "le service n'est ni réactivé ni redémarré"
assert_contient "$(cat "$JOURNAL")" "fail2ban-client status sshd" "la prison est tout de même vérifiée"
printf '# autre\n[sshd]\nenabled = false\n' > "$DEPOT"; : > "$JOURNAL"; lancer bash "$CIBLE" -y
assert_code 0 "$CODE" "un contenu différent est remplacé"; assert_egal "$ATTENDU" "$(depot)" "le fichier est ramené au contenu attendu"
assert_contient "$(cat "$JOURNAL")" "systemctl restart fail2ban" "un dépôt redémarre le service"
titre "7. Échecs — installation, redémarrage et vérification de la prison"
etat_neuf; : > "$APT_REFUS"; lancer bash "$CIBLE" -y
assert_code 1 "$CODE" "« apt-get install » en échec : rend 1"; assert_contient "$SORTIE" "apt-get install" "le refus nomme la commande"
assert_egal "absent" "$(present)" "rien n'est déposé quand l'installation échoue"; assert_egal "0" "$(mutations)" "le service n'est pas touché"
etat_pret; : > "$SYSTEMCTL_REFUS"; lancer bash "$CIBLE" -y
assert_code 1 "$CODE" "« systemctl restart » en échec : rend 1"; assert_contient "$SORTIE" "systemctl restart fail2ban" "le refus nomme la commande"
assert_egal "0" "$(appels '^fail2ban-client')" "la prison n'est pas vérifiée après un redémarrage en échec"
etat_pret; : > "$F2B_REFUS"; lancer bash "$CIBLE" -y
assert_code 1 "$CODE" "« fail2ban-client status sshd » en échec : rend 1"
assert_contient "$SORTIE" "NOK" "le refus affiche la sortie de fail2ban-client"
etat_pret; printf '%s\n' "$ATTENDU" > "$DEPOT"; : > "$F2B_REFUS"; : > "$JOURNAL"; lancer bash "$CIBLE" -y
assert_code 1 "$CODE" "prison non chargée, sans rien à changer : rend 1"; assert_egal "0" "$(mutations)" "rien n'a été redémarré pour autant"

bilan "TASK-044 / configure-fail2ban.sh"
