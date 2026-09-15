#!/usr/bin/env bash
set -Eeuo pipefail
# tests/integration/reboot-system.test.sh — Linux/System/reboot-system.sh (TASK-026).
# AUCUN REDÉMARRAGE : un faux « systemctl » en tête de PATH enregistre ses arguments et rend 0,
# un faux « who » fabrique les sessions. Le cas 4 est la garde de contraste des suivants.
# Ne JAMAIS lancer ceci sous le profil systemd : « systemctl reboot » y fonctionnerait pour de bon.

_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_dir/lib/common.sh" ] && [ "$_dir" != "/" ]; do _dir="$(dirname "$_dir")"; done
source "$_dir/lib/common.sh"
source "$SCRIPTS_ROOT/tests/lib/assert.sh"

CIBLE="$SCRIPTS_ROOT/Linux/System/reboot-system.sh"
if ! REP="$(mktemp -d)"; then printf 'mktemp -d a échoué\n' >&2; exit 3; fi
FAUX="$REP/faux"; FAUX_WHO="$REP/faux-who"; TRACE="$REP/trace"; SESSIONS="$REP/sessions"
F_OUT="$REP/out"; F_ERR="$REP/err"; CODE=0; PID_DPKG=""; VUE=""; TEMOIN_POSAIS="false"
mkdir -p "$FAUX" "$FAUX_WHO"; : > "$TRACE"
printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "%s"\n' "$TRACE" > "$FAUX/systemctl"
printf '#!/bin/sh\ncat "%s"\n' "$SESSIONS" > "$FAUX_WHO/who"
chmod +x "$FAUX/systemctl" "$FAUX_WHO/who"
printf 'max        pts/0        2026-09-15 09:12 (10.0.0.4)\nsauvegarde pts/1        2026-09-15 09:30 (10.0.0.9)\n' > "$SESSIONS"
nettoyer() {
    if [ -n "$PID_DPKG" ]; then kill "$PID_DPKG" 2>/dev/null || true; fi
    if [ "$TEMOIN_POSAIS" = "true" ]; then rm -f /run/reboot-required; fi
    rm -rf "$REP"; return 0
}
trap nettoyer EXIT

lancer() { CODE=0; ( "$@" ) >"$F_OUT" 2>"$F_ERR" </dev/null || CODE=$?; }
repondre() { CODE=0; printf '%s\n' "$1" | env "PATH=$FAUX:$PATH" bash "$CIBLE" >"$F_OUT" 2>"$F_ERR" || CODE=$?; }
trace() { cat "$TRACE"; }
relever() { VUE=""; if ! VUE="$(cat "$F_ERR")"; then VUE=""; fi; }
essai() { lancer env "PATH=$FAUX:$PATH" bash "$CIBLE" "$@"; relever; }
# Les deux branches du témoin se posent ici au lieu de dépendre de ce que l'image a laissé.
rm -f /run/reboot-required
EST_ROOT="false"; if [ "$(id -u)" -eq 0 ]; then EST_ROOT="true"; fi
# Lanceur non privilégié : le premier qui abaisse RÉELLEMENT l'UID. Un outil absent n'écrit
# rien, donc ne peut pas être pris pour un lanceur qui fonctionne.
LANCEUR_SANS_ROOT=()
if [ "$EST_ROOT" = "false" ]; then LANCEUR_SANS_ROOT=(env)
elif [ "$(setpriv --reuid=65534 --regid=65534 --clear-groups id -u 2>/dev/null)" = "65534" ]; then
    LANCEUR_SANS_ROOT=(setpriv --reuid=65534 --regid=65534 --clear-groups)
elif [ "$(runuser -u nobody -- id -u 2>/dev/null)" = "65534" ]; then
    LANCEUR_SANS_ROOT=(runuser -u nobody --)
fi
sans_root() { lancer env "LOG_DIR=$REP/journaux" "${LANCEUR_SANS_ROOT[@]}" "$@"; }

titre "1. Aide"
lancer bash "$CIBLE" --help
assert_code 0 "$CODE" "--help sort en 0"
for motif in "-y, --yes" "--si-necessaire" "--dry-run" "systemctl" "shutdown" "gestion de paquets" "reboot-required" "confirmation"; do assert_contient "$(cat "$F_OUT")" "$motif" "--help documente « $motif »"; done

titre "2. Usage refusé — code 2, avant toute lecture d'état"
lancer bash "$CIBLE" --option-qui-n-existe-pas
assert_code 2 "$CODE" "une option inconnue rend 2"
assert_contient "$(cat "$F_ERR")" "Option inconnue" "le refus nomme l'option"
assert_absent "$(cat "$F_ERR")" "Machine" "le refus précède toute lecture d'état"

titre "3. Privilège insuffisant"
if [ "${#LANCEUR_SANS_ROOT[@]}" -eq 0 ]; then
    saute_indisponible "le refus sans privilège, et la primauté de l'erreur d'usage" "aucun lanceur ne parvient à abaisser l'UID"
else
    sans_root bash "$CIBLE" -y
    assert_code 1 "$CODE" "sans privilège, le script rend 1"
    assert_contient "$(cat "$F_ERR")" "doit être exécuté en root" "le script dit pourquoi il refuse"
    sans_root bash "$CIBLE" --option-qui-n-existe-pas
    assert_code 2 "$CODE" "une ligne à la fois fautive et sans privilège rend 2"
fi

titre "4. systemctl absent — refus en 1, sans repli sur une autre commande"
if command -v systemctl >/dev/null 2>&1; then
    saute_indisponible "le refus quand systemctl est absent" "systemctl existe ici : il ne s'éprouve pas sans restreindre PATH"
else
    lancer bash "$CIBLE" --dry-run -y
    assert_code 1 "$CODE" "sans systemctl, le script rend 1"
    assert_contient "$(cat "$F_ERR")" "systemctl" "le refus nomme la dépendance absente"
    assert_absent "$(cat "$F_ERR")" "Machine" "le refus précède la lecture d'état"
    assert_egal "" "$(trace)" "aucune commande de redémarrage n'a été tentée : aucun repli"
fi

if [ "$EST_ROOT" != "true" ]; then
    saute_indisponible "le refus de paquets, le résumé, la confirmation et la commande" "le harnais ne tourne pas sous root"
else
titre "5. Gestion de paquets en cours — refus en 1, processus nommé"
cp /bin/sleep "$REP/dpkg"; "$REP/dpkg" 60 & PID_DPKG=$!   # le nom suffit à pgrep
for _ in 1 2 3 4 5 6 7 8 9 10; do pgrep -x dpkg >/dev/null 2>&1 && break; sleep 0.2; done
essai --dry-run -y
assert_code 1 "$CODE" "un dpkg en cours fait refuser en 1"
assert_contient "$VUE" "gestion de paquets en cours" "le refus dit de quoi il s'agit"
assert_contient "$VUE" "dpkg" "le refus nomme le processus trouvé"
assert_egal "" "$(trace)" "le refus précède la commande de redémarrage"
kill "$PID_DPKG" 2>/dev/null || true; wait "$PID_DPKG" 2>/dev/null || true; PID_DPKG=""
essai --dry-run -y
assert_code 0 "$CODE" "garde de contraste : le même appel aboutit le processus disparu"

titre "6. --dry-run — le résumé, la commande affichée, rien de lancé"
essai --dry-run -y
assert_code 0 "$CODE" "--dry-run --yes sort en 0"
assert_contient "$VUE" "$(uname -n)" "le résumé nomme la machine"
assert_contient "$VUE" "$(date '+%Y-%m-%d')" "le résumé donne la date"
assert_contient "$VUE" "En service : " "le temps de fonctionnement est lu dans /proc/uptime"
assert_absent "$VUE" "En service : inconnu" "et il est lu, non supposé"
assert_contient "$VUE" "Redémarrage nécessaire : non — /run/reboot-required est absent" "le témoin absent est constaté sur le disque, et le fichier lu est nommé"
assert_contient "$VUE" "Commande qui serait lancée : systemctl reboot" "--dry-run affiche la commande exacte"
assert_absent "$VUE" "[o/N]" "--dry-run ne demande aucune confirmation"
assert_egal "" "$(trace)" "aucune commande de redémarrage n'a été lancée"

titre "7. Sessions ouvertes — nommées, sans blocage à elles seules"
essai --dry-run -y
assert_contient "$VUE" "Sessions ouvertes : aucune" "un utmp vide est un cas nominal, pas une indisponibilité"
lancer env "PATH=$FAUX_WHO:$FAUX:$PATH" bash "$CIBLE" --dry-run -y; relever
assert_code 0 "$CODE" "des sessions ouvertes n'empêchent pas le redémarrage"
assert_contient "$VUE" "Sessions ouvertes : 2" "le résumé compte les sessions"
assert_contient "$VUE" "max        pts/0" "la session ouverte est nommée dans le résumé"
assert_contient "$VUE" "sauvegarde pts/1" "la seconde session l'est aussi"
assert_egal "" "$(trace)" "aucun redémarrage n'a été lancé"

titre "8. --si-necessaire sans témoin — rien à faire, et 0"
essai --si-necessaire -y
assert_code 0 "$CODE" "--si-necessaire rend 0 quand rien n'est nécessaire"
assert_contient "$VUE" "Aucun redémarrage n'est nécessaire" "le script dit pourquoi il ne fait rien"
assert_egal "" "$(trace)" "--si-necessaire ne redémarre pas"

titre "9. Confirmation — rien sans réponse affirmative"
: > "$TRACE"; repondre "non"
assert_code 0 "$CODE" "une réponse négative rend 0 sans rien entreprendre"
assert_contient "$(cat "$F_ERR")" "[o/N]" "la confirmation est demandée"
assert_contient "$(cat "$F_ERR")" "Abandon" "le script annonce l'abandon"
assert_egal "" "$(trace)" "aucune commande de redémarrage n'a été lancée"
repondre ""; assert_code 0 "$CODE" "une réponse vide — le défaut — rend 0 sans rien entreprendre"
assert_egal "" "$(trace)" "la réponse vide non plus n'a rien lancé"

titre "10. --yes sans terminal — la tâche planifiée"
essai --yes
assert_code 0 "$CODE" "--yes va jusqu'au bout sans terminal"
assert_absent "$VUE" "[o/N]" "--yes ne demande rien"
assert_contient "$VUE" "Redémarrage demandé" "le script annonce le redémarrage"
assert_egal "reboot" "$(trace)" "« reboot » est la commande atteinte, et la seule"

titre "11. Redémarrage déclaré — lu sur le disque, pas supposé"
: > /run/reboot-required; TEMOIN_POSAIS="true"; : > "$TRACE"
essai --dry-run -y
assert_contient "$VUE" "Redémarrage nécessaire : oui" "le témoin posé est lu sur le disque"
assert_egal "" "$(trace)" "--dry-run n'a rien lancé"
essai --si-necessaire --yes
assert_code 0 "$CODE" "--si-necessaire procède quand le témoin est là"
assert_egal "reboot" "$(trace)" "la commande de redémarrage est atteinte"
fi

bilan "TASK-026 / reboot-system.sh"
