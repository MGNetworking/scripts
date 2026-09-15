#!/usr/bin/env bash
set -Eeuo pipefail
# tests/integration/reboot-system.test.sh — Linux/System/reboot-system.sh (TASK-026).
# AUCUN REDÉMARRAGE : un faux « systemctl » en tête de PATH enregistre ses arguments et rend 0.
# Ne JAMAIS lancer ceci sous le profil systemd : « systemctl reboot » y serait réel.
_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_dir/lib/common.sh" ] && [ "$_dir" != "/" ]; do _dir="$(dirname "$_dir")"; done
source "$_dir/lib/common.sh"
source "$SCRIPTS_ROOT/tests/lib/assert.sh"
CIBLE="$SCRIPTS_ROOT/Linux/System/reboot-system.sh"
# Garde en tête, avant même de fabriquer un faux binaire : sur un hôte pourvu d'un
# vrai systemctl, une erreur de PATH redémarrerait la machine pour de bon.
if command -v systemctl >/dev/null 2>&1; then
    saute_indisponible "la totalité du fichier" "un vrai systemctl est présent : le faux ne serait pas prioritaire"
    bilan "TASK-026 / reboot-system.sh"
fi
if ! REP="$(mktemp -d)"; then printf 'mktemp -d a échoué\n' >&2; exit 3; fi
FAUX="$REP/faux"; SANS="$REP/sans-systemctl"; FAUX_WHO="$REP/faux-who"
TRACE="$REP/trace"; SESSIONS="$REP/sessions"
F_OUT="$REP/out"; F_ERR="$REP/err"; CODE=0; PID_DPKG=""; VUE=""; TEMOIN_POSAIS="false"
mkdir -p "$FAUX" "$SANS" "$FAUX_WHO"; : > "$TRACE"
# Tout binaire homonyme enregistre ses arguments dans la trace : c'est ainsi que le
# point de non-retour se prouve, et que l'absence de repli se constate.
faux() { printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "%s"\n' "$TRACE" > "$1"; chmod +x "$1"; }
faux "$FAUX/systemctl"; for nom in shutdown reboot telinit; do faux "$SANS/$nom"; done
printf '#!/bin/sh\ncat "%s"\n' "$SESSIONS" > "$FAUX_WHO/who"; chmod +x "$FAUX_WHO/who"
printf 'max        pts/0        2026-09-15 09:12 (10.0.0.4)\nsauvegarde pts/1        2026-09-15 09:30 (10.0.0.9)\n' > "$SESSIONS"
nettoyer() {
    if [ -n "$PID_DPKG" ]; then kill "$PID_DPKG" 2>/dev/null || true; fi
    if [ "$TEMOIN_POSAIS" = "true" ]; then rm -f /run/reboot-required; fi
    rm -rf "$REP"; return 0
}
trap nettoyer EXIT
lancer() { CODE=0; ( "$@" ) >"$F_OUT" 2>"$F_ERR" </dev/null || CODE=$?; }
relever() { VUE=""; if ! VUE="$(cat "$F_ERR")"; then VUE=""; fi; }
trace() { cat "$TRACE"; }
essai() { lancer env "PATH=$FAUX:$PATH" bash "$CIBLE" "$@"; relever; }
repondre() { CODE=0; printf '%s\n' "$1" | env "PATH=$FAUX:$PATH" bash "$CIBLE" >"$F_OUT" 2>"$F_ERR" || CODE=$?; relever; }
# Les deux branches du témoin se posent ici au lieu de dépendre de ce que l'image a laissé.
rm -f /run/reboot-required; EST_ROOT="false"; if [ "$(id -u)" -eq 0 ]; then EST_ROOT="true"; fi
# Lanceur non privilégié : le premier qui abaisse RÉELLEMENT l'UID. Un outil absent
# n'écrit rien, donc ne peut pas être pris pour un lanceur qui fonctionne.
abaisse_uid() { [ "$("$@" id -u 2>/dev/null)" = "65534" ]; }
LANCEUR_SANS_ROOT=()
if [ "$EST_ROOT" = "false" ]; then LANCEUR_SANS_ROOT=(env)
elif abaisse_uid setpriv --reuid=65534 --regid=65534 --clear-groups; then LANCEUR_SANS_ROOT=(setpriv --reuid=65534 --regid=65534 --clear-groups)
elif abaisse_uid runuser -u nobody --; then LANCEUR_SANS_ROOT=(runuser -u nobody --)
fi
sans_root() { lancer env "LOG_DIR=$REP/journaux" "${LANCEUR_SANS_ROOT[@]}" "$@"; }

titre "1. Aide"; lancer bash "$CIBLE" --help; assert_code 0 "$CODE" "--help sort en 0"
for motif in "-y, --yes" "--si-necessaire" "--dry-run" "systemctl" "shutdown" "gestion de paquets" "reboot-required" "confirmation"; do assert_contient "$(cat "$F_OUT")" "$motif" "--help documente « $motif »"; done
titre "2. Usage refusé — code 2, avant toute lecture d'état"
lancer bash "$CIBLE" --option-qui-n-existe-pas; relever
assert_code 2 "$CODE" "une option inconnue rend 2"
assert_contient "$VUE" "Option inconnue" "le refus nomme l'option"
assert_absent "$VUE" "Machine" "le refus précède toute lecture d'état"
titre "3. Privilège insuffisant"
if [ "${#LANCEUR_SANS_ROOT[@]}" -eq 0 ]; then saute_indisponible "le refus sans privilège, et la primauté de l'erreur d'usage" "aucun lanceur ne parvient à abaisser l'UID"
else
    sans_root bash "$CIBLE" -y; assert_code 1 "$CODE" "sans privilège, le script rend 1"
    assert_contient "$(cat "$F_ERR")" "doit être exécuté en root" "le script dit pourquoi il refuse"
    sans_root bash "$CIBLE" --option-qui-n-existe-pas; assert_code 2 "$CODE" "une ligne à la fois fautive et sans privilège rend 2"
fi
titre "4. systemctl absent — refus en 1, sans repli sur shutdown, reboot ni telinit"
# Garde de contraste : sans elle, une trace vide ne prouverait que des faux muets.
"$SANS/reboot" garde-de-contraste; assert_egal "garde-de-contraste" "$(trace)" "les faux binaires écrivent bien dans la trace"; : > "$TRACE"
lancer env "PATH=$SANS:$PATH" bash "$CIBLE" --dry-run -y; relever
assert_code 1 "$CODE" "sans systemctl, le script rend 1"
assert_contient "$VUE" "systemctl" "le refus nomme la dépendance absente"
assert_absent "$VUE" "Machine" "le refus précède la lecture d'état"
assert_egal "" "$(trace)" "aucun repli : ni shutdown, ni reboot, ni telinit n'ont été appelés"
if [ "$EST_ROOT" != "true" ]; then
    saute_indisponible "le refus de paquets, le résumé, la confirmation et la commande" "le harnais ne tourne pas sous root"
else
titre "5. Gestion de paquets en cours — refus en 1, processus nommé"
cp /bin/sleep "$REP/dpkg"; "$REP/dpkg" 60 & PID_DPKG=$!   # le nom suffit, et /proc le donne
for _ in 1 2 3 4 5 6 7 8 9 10; do [ "$(cat "/proc/$PID_DPKG/comm" 2>/dev/null)" = "dpkg" ] && break; sleep 0.2; done
essai --dry-run -y
assert_code 1 "$CODE" "un dpkg en cours fait refuser en 1"
assert_contient "$VUE" "gestion de paquets en cours" "le refus dit de quoi il s'agit"
assert_contient "$VUE" "dpkg" "le refus nomme le processus trouvé"
assert_egal "" "$(trace)" "le refus précède la commande de redémarrage"
kill "$PID_DPKG" 2>/dev/null || true; wait "$PID_DPKG" 2>/dev/null || true; PID_DPKG=""
essai --dry-run -y; assert_code 0 "$CODE" "garde de contraste : le même appel aboutit le processus disparu"
titre "6. --dry-run — le résumé, la commande affichée, rien de lancé"
DATE_AVANT="$(date '+%Y-%m-%d')"
essai --dry-run -y
assert_code 0 "$CODE" "--dry-run --yes sort en 0"
assert_contient "$VUE" "$(uname -n)" "le résumé nomme la machine"
if contient "$VUE" "$DATE_AVANT" || contient "$VUE" "$(date '+%Y-%m-%d')"; then ok "le résumé donne la date"; else ko "le résumé donne la date" "ni $DATE_AVANT ni $(date '+%Y-%m-%d') dans le résumé"; fi
assert_contient "$VUE" "En service : " "le temps de fonctionnement est lu dans /proc/uptime"
assert_absent "$VUE" "En service : inconnu" "et il est lu, non supposé"
assert_contient "$VUE" "Redémarrage nécessaire : non — /run/reboot-required est absent" "le témoin absent est constaté sur le disque"
assert_contient "$VUE" "Commande qui serait lancée : systemctl reboot" "--dry-run affiche la commande exacte"
assert_absent "$VUE" "[o/N]" "--dry-run ne demande aucune confirmation"
assert_egal "" "$(trace)" "aucune commande de redémarrage n'a été lancée"
titre "7. Sessions ouvertes — nommées, sans blocage à elles seules"
essai --dry-run -y
assert_contient "$VUE" "Sessions ouvertes : aucune" "un utmp vide est un cas nominal, pas une indisponibilité"
lancer env "PATH=$FAUX_WHO:$FAUX:$PATH" bash "$CIBLE" --dry-run -y; relever
assert_code 0 "$CODE" "des sessions ouvertes n'empêchent pas le redémarrage"
assert_contient "$VUE" "Sessions ouvertes : 2" "le résumé compte les sessions"
assert_contient "$VUE" "[WARN]     max        pts/0" "la session ouverte est nommée, sur une ligne [WARN]"
assert_contient "$VUE" "[WARN]     sauvegarde pts/1" "la seconde session l'est aussi"
assert_egal "" "$(trace)" "aucun redémarrage n'a été lancé"
titre "8. --si-necessaire sans témoin — rien à faire, et 0"
essai --si-necessaire -y
assert_code 0 "$CODE" "--si-necessaire rend 0 quand rien n'est nécessaire"
assert_contient "$VUE" "Aucun redémarrage n'est nécessaire" "le script dit pourquoi il ne fait rien"
assert_egal "" "$(trace)" "--si-necessaire ne redémarre pas"
essai --si-necessaire --dry-run -y; assert_code 0 "$CODE" "--si-necessaire --dry-run sort en 0 lui aussi"
assert_contient "$VUE" "Commande qui serait lancée : systemctl reboot" "et il montre la commande qu'il n'a pas lancée"
assert_egal "" "$(trace)" "--si-necessaire --dry-run ne redémarre pas non plus"
titre "9. Confirmation — rien sans réponse affirmative"
repondre "non"; assert_code 0 "$CODE" "une réponse négative rend 0 sans rien entreprendre"
assert_contient "$VUE" "[o/N]" "la confirmation est demandée"
assert_contient "$VUE" "Abandon" "le script annonce l'abandon"
assert_egal "" "$(trace)" "aucune commande de redémarrage n'a été lancée"
repondre ""; assert_code 0 "$CODE" "une réponse vide — le défaut — rend 0 sans rien entreprendre"
assert_egal "" "$(trace)" "la réponse vide non plus n'a rien lancé"
repondre "oui"; assert_code 0 "$CODE" "une réponse affirmative mène au redémarrage"
assert_egal "reboot" "$(trace)" "la confirmation acceptée atteint « reboot »"
titre "10. Sans --yes, une entrée fermée n'autorise rien — ASSUME_YES héritée non plus"
: > "$TRACE"
lancer env "PATH=$FAUX:$PATH" bash "$CIBLE"; relever
assert_code 0 "$CODE" "sans --yes et sur une entrée fermée, le script rend 0"
assert_contient "$VUE" "Abandon" "il est passé par la confirmation, qui n'a rien obtenu"
assert_egal "" "$(trace)" "une entrée fermée ne redémarre rien"
lancer env "PATH=$FAUX:$PATH" "ASSUME_YES=true" bash "$CIBLE"
assert_code 0 "$CODE" "ASSUME_YES=true dans l'environnement, sans --yes, rend 0"
assert_egal "" "$(trace)" "et la machine n'a pas redémarré non plus"
titre "11. --yes sans terminal — la tâche planifiée"
essai --yes
assert_code 0 "$CODE" "--yes va jusqu'au bout sans terminal"
assert_absent "$VUE" "[o/N]" "--yes ne demande rien"
assert_contient "$VUE" "Redémarrage demandé" "le script annonce le redémarrage"
assert_egal "reboot" "$(trace)" "« reboot » est la commande atteinte, et la seule"

titre "12. Redémarrage déclaré — lu sur le disque, pas supposé"
: > /run/reboot-required; TEMOIN_POSAIS="true"; : > "$TRACE"
essai --dry-run -y
assert_contient "$VUE" "Redémarrage nécessaire : oui" "le témoin posé est lu sur le disque"
assert_egal "" "$(trace)" "--dry-run n'a rien lancé"
essai --si-necessaire --yes; assert_code 0 "$CODE" "--si-necessaire procède quand le témoin est là"
assert_egal "reboot" "$(trace)" "la commande de redémarrage est atteinte"
fi

bilan "TASK-026 / reboot-system.sh"
