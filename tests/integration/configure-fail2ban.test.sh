#!/usr/bin/env bash
set -Eeuo pipefail
# tests/integration/configure-fail2ban.test.sh — Linux/Security/configure-fail2ban.sh
# (TASK-044). Aucune installation réelle : de faux apt-get, dpkg-query, systemctl,
# fail2ban-client et mv en tête de PATH tracent chaque appel, jail.d est un bac à
# sable inscriptible par l'utilisateur 65534. PAQUET_POSE commande dpkg-query ;
# APT_REFUS, APT_UPDATE_REFUS et APT_SANS_POSE gouvernent apt-get ; SERVICE_ENABLED
# et SERVICE_ACTIF répondent à systemctl, ENABLE_REFUS et SYSTEMCTL_REFUS font
# échouer enable et restart ; MV_REFUS fait échouer mv ; le faux fail2ban-client
# répond à « ping » selon F2B_MUET et F2B_TARDIF, et n'accepte « status sshd »
# qu'après un redémarrage postérieur au dépôt (F2B_RESTART), sauf F2B_REFUS.
_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_dir/lib/common.sh" ] && [ "$_dir" != "/" ]; do _dir="$(dirname "$_dir")"; done
source "$_dir/lib/common.sh"
source "$SCRIPTS_ROOT/tests/lib/assert.sh"
CIBLE="$SCRIPTS_ROOT/Linux/Security/configure-fail2ban.sh"
MV_REEL="$(type -P mv)"; export MV_REEL
BAC="$(mktemp -d)"; FAUX="$BAC/bin"; JAIL_D="$BAC/jail.d"; DEPOT="$JAIL_D/mgnetworking-sshd.conf"
chmod 777 "$BAC"; mkdir -p "$FAUX"
export JOURNAL="$BAC/appels.log" FAIL2BAN_JAIL_D="$JAIL_D" DEPOT="$DEPOT"
export PAQUET_POSE="$BAC/paquet" APT_REFUS="$BAC/apt-refus" F2B_REFUS="$BAC/f2b-refus"
export APT_UPDATE_REFUS="$BAC/apt-update-refus" APT_SANS_POSE="$BAC/apt-sans-pose"
export F2B_MUET="$BAC/f2b-muet" F2B_PING="$BAC/f2b-ping" F2B_RESTART="$BAC/f2b-restart"
export SERVICE_ENABLED="$BAC/enabled" SERVICE_ACTIF="$BAC/actif" SYSTEMCTL_REFUS="$BAC/systemctl-refus"
export ENABLE_REFUS="$BAC/enable-refus" MV_REFUS="$BAC/mv-refus"
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
update)  [ -f "$APT_UPDATE_REFUS" ] && exit 100 ;;
install) [ -f "$APT_REFUS" ] && exit 100
         [ -f "$APT_SANS_POSE" ] && exit 0
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
enable)     [ -f "$ENABLE_REFUS" ] && exit 1; : > "$SERVICE_ENABLED"; exit 0 ;;
restart)    [ -f "$SYSTEMCTL_REFUS" ] && { rm -f "$SERVICE_ACTIF"; exit 1; }
            : > "$SERVICE_ACTIF"; : > "$F2B_RESTART"; exit 0 ;;
esac
exit 0
EOF
cat > "$FAUX/fail2ban-client" <<'EOF'
#!/bin/sh
printf 'fail2ban-client %s\n' "$*" >> "$JOURNAL"
case "$1" in
ping)
    [ -f "$F2B_MUET" ] && exit 1
    n=$(cat "$F2B_PING" 2>/dev/null || echo 0); n=$((n + 1)); echo "$n" > "$F2B_PING"
    [ "$n" -gt "${F2B_TARDIF:-0}" ] && { echo pong; exit 0; }
    exit 1 ;;
status)
    [ -f "$F2B_REFUS" ] && { echo 'ERROR  NOK: sshd not found' >&2; exit 1; }
    [ -f "$DEPOT" ] || { echo 'ERROR  Jail sshd not found' >&2; exit 1; }
    [ -f "$F2B_RESTART" ] || { echo 'ERROR  Jail sshd not loaded : jamais redémarré' >&2; exit 1; }
    [ "$DEPOT" -nt "$F2B_RESTART" ] && { echo 'ERROR  Jail sshd not loaded : déposé depuis' >&2; exit 1; }
    echo 'Status for the jail: sshd'; exit 0 ;;
esac
exit 0
EOF
cat > "$FAUX/mv" <<'EOF'
#!/bin/sh
printf 'mv %s\n' "$*" >> "$JOURNAL"
[ -f "$MV_REFUS" ] && { echo 'mv : échec simulé' >&2; exit 1; }
exec "$MV_REEL" "$@"
EOF
chmod +x "$FAUX"/*
etat_neuf() {
    rm -rf "$JAIL_D"
    rm -f "$PAQUET_POSE" "$SERVICE_ACTIF" "$SERVICE_ENABLED" "$F2B_REFUS" "$F2B_MUET" "$F2B_PING" \
          "$F2B_RESTART" "$APT_REFUS" "$APT_UPDATE_REFUS" "$APT_SANS_POSE" \
          "$ENABLE_REFUS" "$SYSTEMCTL_REFUS" "$MV_REFUS"
    : > "$JOURNAL"; chmod 666 "$JOURNAL"
}
# Paquet posé et service actif, mais NON activé : « enabled » seul décide.
etat_base() { etat_neuf; mkdir -p "$JAIL_D"; chmod 777 "$JAIL_D"; : > "$PAQUET_POSE"; : > "$SERVICE_ACTIF"; }
etat_pret() { etat_base; : > "$SERVICE_ENABLED"; }
lancer() { CODE=0; SORTIE="$(PATH="$FAUX:$PATH" "$@" 2>&1 </dev/null)" || CODE=$?; }
depot() { cat "$DEPOT" 2>/dev/null || true; }
present() { [ -e "$DEPOT" ] && printf 'présent' || printf 'absent'; }
service_actif() { [ -f "$SERVICE_ACTIF" ] && printf 'actif' || printf 'inactif'; }
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
assert_code 1 "$CODE" "sans terminal : rend 1 même avec un ASSUME_YES hérité"
assert_contient "$SORTIE" "aucun terminal" "ici le refus tient à l'absence de terminal, pas à la décision 45"
assert_egal "absent" "$(present)" "le refus faute de terminal n'écrit rien"
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
titre "7. Échecs d'installation — apt-get, puis le contrôle qui suit"
etat_neuf; : > "$APT_UPDATE_REFUS"; lancer bash "$CIBLE" -y
assert_code 1 "$CODE" "« apt-get update » en échec : rend 1"; assert_contient "$SORTIE" "apt-get update" "le refus nomme la commande"
assert_egal "0" "$(appels '^apt-get install')" "l'installation n'est pas tentée"; assert_egal "absent" "$(present)" "rien n'est déposé"
etat_neuf; : > "$APT_REFUS"; lancer bash "$CIBLE" -y
assert_code 1 "$CODE" "« apt-get install » en échec : rend 1"; assert_contient "$SORTIE" "apt-get install" "le refus nomme la commande"
assert_egal "absent" "$(present)" "rien n'est déposé quand l'installation échoue"; assert_egal "0" "$(mutations)" "le service n'est pas touché"
etat_neuf; : > "$APT_SANS_POSE"; lancer bash "$CIBLE" -y
assert_code 1 "$CODE" "paquet toujours absent après installation : rend 1"
assert_contient "$SORTIE" "reste absent" "le refus dit que le paquet n'est pas là"
assert_egal "absent" "$(present)" "rien n'est déposé sans paquet"; assert_egal "0" "$(mutations)" "le service n'est pas touché"
titre "8. Service — échecs, état laissé derrière, et rattrapage au passage suivant"
etat_base; : > "$ENABLE_REFUS"; lancer bash "$CIBLE" -y
assert_code 1 "$CODE" "« systemctl enable » en échec : rend 1"; assert_contient "$SORTIE" "systemctl enable fail2ban" "le refus nomme la commande"
assert_egal "$ATTENDU" "$(depot)" "la prison est déjà déposée quand l'activation échoue"
rm -f "$ENABLE_REFUS"; : > "$JOURNAL"; lancer bash "$CIBLE" -y
assert_code 0 "$CODE" "l'activation ratée se rattrape au passage suivant"
assert_contient "$(cat "$JOURNAL")" "systemctl restart fail2ban" "le rattrapage redémarre, sans quoi la prison resterait déchargée"
assert_contient "$(cat "$JOURNAL")" "fail2ban-client status sshd" "et la prison est alors vérifiée"
etat_pret; : > "$SYSTEMCTL_REFUS"; lancer bash "$CIBLE" -y
assert_code 1 "$CODE" "« systemctl restart » en échec : rend 1"; assert_contient "$SORTIE" "systemctl restart fail2ban" "le refus nomme la commande"
assert_egal "inactif" "$(service_actif)" "le redémarrage raté laisse le service inactif"
assert_egal "0" "$(appels '^fail2ban-client')" "la prison n'est pas vérifiée après un redémarrage en échec"
rm -f "$SYSTEMCTL_REFUS"; : > "$JOURNAL"; lancer bash "$CIBLE" -y
assert_code 0 "$CODE" "le redémarrage raté se rattrape au passage suivant"
assert_contient "$(cat "$JOURNAL")" "systemctl restart fail2ban" "le rattrapage redémarre bien"
assert_contient "$(cat "$JOURNAL")" "fail2ban-client status sshd" "et la prison est chargée"
titre "9. Prison — vérification, attente du démon, et démon qui ne vient pas"
etat_pret; : > "$F2B_REFUS"; lancer bash "$CIBLE" -y
assert_code 1 "$CODE" "« fail2ban-client status sshd » en échec : rend 1"
assert_contient "$SORTIE" "NOK" "le refus affiche la sortie de fail2ban-client"
assert_egal "1" "$(appels '^fail2ban-client ping')" "le démon répond du premier coup : un seul ping"
etat_pret; printf '%s\n' "$ATTENDU" > "$DEPOT"; : > "$F2B_REFUS"; : > "$JOURNAL"; lancer bash "$CIBLE" -y
assert_code 1 "$CODE" "prison non chargée, sans rien à changer : rend 1"; assert_egal "0" "$(mutations)" "rien n'a été redémarré pour autant"
etat_base; lancer env F2B_TARDIF=2 FAIL2BAN_ESSAIS=5 FAIL2BAN_DELAI=0 bash "$CIBLE" -y
assert_code 0 "$CODE" "un démon qui tarde à ouvrir son socket : rend 0"
assert_egal "3" "$(appels '^fail2ban-client ping')" "les trois essais ont eu lieu avant que le démon réponde"
assert_contient "$(cat "$JOURNAL")" "fail2ban-client status sshd" "la prison est vérifiée une fois le démon joignable"
etat_base; : > "$F2B_MUET"; lancer env FAIL2BAN_ESSAIS=2 FAIL2BAN_DELAI=0 bash "$CIBLE" -y
assert_code 1 "$CODE" "un démon qui ne répond jamais : rend 1"; assert_contient "$SORTIE" "ping" "le refus dit que le démon est injoignable"
assert_egal "0" "$(appels '^fail2ban-client status')" "la prison n'est pas interrogée quand le démon se tait"
titre "10. Échec d'écriture — aucun temporaire ne subsiste dans jail.d"
etat_pret; : > "$MV_REFUS"; lancer bash "$CIBLE" -y
assert_code 1 "$CODE" "un « mv » en échec : rend 1"
assert_egal "absent" "$(present)" "le dépôt n'existe pas"
assert_egal "0" "$(find "$JAIL_D" -name '.mgnetworking-sshd.*' | wc -l)" "aucun temporaire laissé derrière"
assert_egal "0" "$(mutations)" "le service n'est pas touché"

bilan "TASK-044 / configure-fail2ban.sh"
