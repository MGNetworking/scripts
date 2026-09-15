#!/usr/bin/env bash
# tests/integration/notify-failure.test.sh — Linux/System/notify-failure.sh.
#
# TASK-024. Le conteneur n'a pas curl : le chemin d'émission est éprouvé par un
# faux « curl » en tête de PATH, qui enregistre ses arguments et rend le verdict
# qu'on lui demande — aucune émission réelle. La configuration ne peut pas vivre
# dans config/, zone interdite : un bac à sable recopie lib/common.sh et le
# script, et s'enracine de lui-même, SCRIPTS_ROOT se résolvant depuis
# l'emplacement de common.sh. L'identité des copies est prouvée avant usage.

_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_dir/lib/common.sh" ] && [ "$_dir" != "/" ]; do _dir="$(dirname "$_dir")"; done
source "$_dir/lib/common.sh"
source "$SCRIPTS_ROOT/tests/lib/assert.sh"

CIBLE="$SCRIPTS_ROOT/Linux/System/notify-failure.sh"
BASH_BIN="$(command -v bash)"
SECRET="https://ntfy.exemple.test/sujet-tres-secret"
JETON="jeton-tres-secret"
BAC="$(mktemp -d)"
trap 'rm -rf "$BAC"' EXIT
mkdir -p "$BAC/lib" "$BAC/config" "$BAC/Linux/System" "$BAC/bin" "$BAC/bin-nu" "$BAC/logs"
cp "$SCRIPTS_ROOT/lib/common.sh" "$BAC/lib/common.sh"
cp "$CIBLE" "$BAC/Linux/System/notify-failure.sh"
BAC_SH="$BAC/Linux/System/notify-failure.sh"

# Le faux curl enregistre ses arguments, puis agit selon STUB_MODE. Le mode
# « delai » ne dort que la borne reçue en argument : un appel non borné l'endort
# 10 s, ce que le cas du délai sanctionne. Aucune socket n'est ouverte.
cat > "$BAC/bin/curl" <<'STUB'
#!/bin/sh
printf '%s\n' "$*" >> "$STUB_ARGS"
max=10
for a in "$@"; do case "$a" in ''|*[!0-9]*) ;; *) max="$a" ;; esac; done
case "$STUB_MODE" in
    2xx)    printf '200\n'; exit 0 ;;
    erreur) printf '500\n'; exit 0 ;;
    muet)   exit 0 ;;
    dns)    printf 'curl: (6) Could not resolve host\n' >&2; exit 6 ;;
    delai)  sleep "$max"; exit 28 ;;
    *)      printf '200\n'; exit 0 ;;
esac
STUB
chmod +x "$BAC/bin/curl"
for outil in cat date uname dirname basename mkdir id sleep; do
    for d in "$BAC/bin" "$BAC/bin-nu"; do ln -sf "$(command -v "$outil")" "$d/$outil"; done
done

SORTIE=""; CODE=0; MODE="2xx"; CHEMIN="$BAC/bin"
# Le script ne voit que ces outils-là, plus curl ; son journal reste dans le bac.
lancer() {
    local cible="$1"; shift
    SORTIE="$(STUB_ARGS="$BAC/appels" STUB_MODE="$MODE" PATH="$CHEMIN" LOG_DIR="$BAC/logs" \
        "$BASH_BIN" "$cible" "$@" 2>&1)" && CODE=0 || CODE=$?
}
appels() { if [ -f "$BAC/appels" ]; then cat "$BAC/appels"; fi; }
# config_ecrire <format> [url] [delai] — config/notify.env du bac à sable.
config_ecrire() {
    printf 'NOTIFY_URL="%s"\nNOTIFY_FORMAT="%s"\nNOTIFY_JETON="%s"\nNOTIFY_DELAI="%s"\n' \
        "${2:-$SECRET}" "$1" "$JETON" "${3:-10}" > "$BAC/config/notify.env"
}

titre "Bac à sable — copies fidèles du script et de son socle"
if cmp -s "$CIBLE" "$BAC_SH" && cmp -s "$SCRIPTS_ROOT/lib/common.sh" "$BAC/lib/common.sh"; then
    ok "le bac à sable porte des copies fidèles du script et de son socle"
else
    ko "le bac à sable porte des copies fidèles du script et de son socle" "les fichiers diffèrent"
fi

titre "Aide et erreurs d'usage"
lancer "$CIBLE" --help; assert_code 0 "$CODE" "--help rend 0"
assert_contient "$SORTIE" "--config <nom>"    "--help documente les options"
assert_contient "$SORTIE" "config/notify.env" "--help nomme le fichier de configuration attendu"
assert_contient "$SORTIE" "objet JSON"        "--help documente le format du message"
assert_contient "$SORTIE" "Codes de retour"   "--help documente les codes de retour"
lancer "$CIBLE"; assert_code 2 "$CODE" "sans argument, le script refuse en 2"
lancer "$CIBLE" --script update-system.sh; assert_code 2 "$CODE" "--code manquant rend 2"
lancer "$CIBLE" --code 1; assert_code 2 "$CODE" "--script manquant rend 2"
lancer "$CIBLE" --script update-system.sh --code abc; assert_code 2 "$CODE" "un code non entier rend 2"
lancer "$CIBLE" --script update-system.sh --code 1 --inconnue; assert_code 2 "$CODE" "une option inconnue rend 2"

titre "Sans configuration exploitable — rien n'est émis"
rm -f "$BAC/appels"
lancer "$CIBLE" --script update-system.sh --code 1 --config tache-024-inexistant
assert_code 1 "$CODE" "une configuration absente rend 1"
assert_contient "$SORTIE" "config/tache-024-inexistant.env" "le fichier attendu est nommé"
assert_egal "" "$(appels)" "aucune émission n'a été tentée"
config_ecrire ntfy "pas-une-adresse"; lancer "$BAC_SH" --script update-system.sh --code 1
assert_code 1 "$CODE" "une URL sans schéma rend 1"
assert_contient "$SORTIE" "NOTIFY_URL inexploitable" "la cause est nommée"
assert_egal "" "$(appels)" "aucune émission n'a été tentée"
config_ecrire pigeon-voyageur; lancer "$BAC_SH" --script update-system.sh --code 1
assert_code 2 "$CODE" "un NOTIFY_FORMAT inconnu rend 2"

titre "Émission ntfy — réponse 2xx"
config_ecrire ntfy; rm -f "$BAC/appels"
lancer "$BAC_SH" --script update-system.sh --code 3
assert_code 0 "$CODE" "une réponse 200 rend 0"
appel="$(appels)"
assert_contient "$appel" "$SECRET" "l'URL de la configuration est celle interrogée"
assert_contient "$appel" "--max-time 10" "l'émission est bornée dans le temps"
assert_contient "$appel" "Authorization: Bearer $JETON" "le jeton est transmis à curl"
for champ in "update-system.sh" "code 3" "$(uname -n)" "$(date '+%Y-%m-%d')" "$BAC/logs/update-system.log"; do
    assert_contient "$appel" "$champ" "le message porte « $champ »"
done
assert_contient "$SORTIE" "ntfy.exemple.test" "l'hôte de destination est affiché"
assert_absent   "$SORTIE" "sujet-tres-secret" "le sujet ntfy n'est pas affiché"
assert_absent   "$SORTIE" "$JETON" "le jeton n'est pas affiché"

titre "Émission webhook — corps JSON"
config_ecrire webhook; rm -f "$BAC/appels"
lancer "$BAC_SH" --script backup-resources.sh --code 2
assert_code 0 "$CODE" "le format webhook émet aussi"
appel="$(appels)"
assert_contient "$appel" "Content-Type: application/json" "le corps est annoncé comme du JSON"
assert_contient "$appel" '"script":"backup-resources.sh"' "le JSON porte le nom du script"
assert_contient "$appel" "\"journal\":\"$BAC/logs/backup-resources.log\"" "le JSON porte le chemin du journal"
assert_absent   "$appel" "Échec de" "le corps texte de ntfy n'est pas employé"

titre "Échecs d'émission — la cause est nommée"
config_ecrire ntfy
MODE="erreur"; lancer "$BAC_SH" --script update-system.sh --code 1
assert_code 1 "$CODE" "une réponse hors 2xx rend 1"
assert_contient "$SORTIE" "hors de la plage 2xx" "la cause est la réponse HTTP"
MODE="muet"; lancer "$BAC_SH" --script update-system.sh --code 1
assert_code 1 "$CODE" "une réponse illisible rend 1"
MODE="dns"; lancer "$BAC_SH" --script update-system.sh --code 1
assert_code 1 "$CODE" "une résolution de nom en échec rend 1"
assert_contient "$SORTIE" "Résolution de nom en échec" "la cause est la résolution de nom"
assert_absent   "$SORTIE" "Could not resolve" "le message brut de curl ne filtre pas"

titre "Délai borné — la borne vient de la configuration"
config_ecrire ntfy "$SECRET" 1; rm -f "$BAC/appels"
MODE="delai"; debut=$SECONDS
lancer "$BAC_SH" --script update-system.sh --code 1
ecoule=$(( SECONDS - debut ))
assert_code 1 "$CODE" "un dépassement du délai rend 1"
assert_contient "$SORTIE" "Délai dépassé" "la cause est le délai"
assert_contient "$(appels)" "--max-time 1" "la borne configurée est celle transmise à curl"
if [ "$ecoule" -lt 4 ]; then ok "la main est rendue en ${ecoule}s, dans la borne d'une seconde"
else ko "la main est rendue en ${ecoule}s : l'émission n'était pas bornée"; fi

titre "curl manquant"
rm -f "$BAC/appels"
CHEMIN="$BAC/bin-nu"; lancer "$BAC_SH" --script update-system.sh --code 1; CHEMIN="$BAC/bin"
assert_code 1 "$CODE" "l'absence de curl rend 1"
assert_contient "$SORTIE" "curl" "la dépendance manquante est nommée"
assert_egal "" "$(appels)" "aucune émission n'a été tentée"

titre "--config change le fichier chargé"
printf 'NOTIFY_URL="https://autre.exemple.test/sujet"\nNOTIFY_FORMAT="ntfy"\n' > "$BAC/config/ailleurs.env"
rm -f "$BAC/appels"; MODE="2xx"
lancer "$BAC_SH" --script update-system.sh --code 1 --config ailleurs
assert_code 0 "$CODE" "--config ailleurs charge config/ailleurs.env"
assert_contient "$(appels)" "autre.exemple.test" "l'URL vient du fichier demandé"
assert_contient "$SORTIE" "config/ailleurs.env" "le fichier chargé est nommé"
assert_absent   "$SORTIE" "sujet-tres-secret" "le fichier par défaut n'est pas chargé"

titre "--dry-run — rien n'est émis"
rm -f "$BAC/appels"
lancer "$CIBLE" --script update-system.sh --code 1 --config tache-024-inexistant --dry-run
assert_code 0 "$CODE" "--dry-run rend 0 sans configuration et sans curl"
assert_contient "$SORTIE" "Méthode     : POST" "la méthode est affichée"
assert_contient "$SORTIE" "Format      : ntfy" "le format est affiché"
assert_contient "$SORTIE" "update-system.sh" "le message qui serait émis est affiché"
assert_egal "" "$(appels)" "aucune émission n'a eu lieu"
lancer "$BAC_SH" --script update-system.sh --code 1 --dry-run
assert_code 0 "$CODE" "--dry-run rend 0 avec une configuration"
assert_contient "$SORTIE" "Destination : ntfy.exemple.test" "l'hôte de destination est affiché"
assert_absent   "$SORTIE" "sujet-tres-secret" "--dry-run ne montre pas le sujet ntfy"
assert_absent   "$SORTIE" "$JETON" "--dry-run ne montre pas le jeton"
assert_egal "" "$(appels)" "--dry-run n'émet rien"

titre "Le journal ne porte ni l'URL ni le jeton"
rm -f "$BAC/logs/notify-failure.log" "$BAC/appels"; MODE="2xx"
lancer "$BAC_SH" --script update-system.sh --code 1
journal=""; if [ -f "$BAC/logs/notify-failure.log" ]; then journal="$(cat "$BAC/logs/notify-failure.log")"; fi
assert_non_vide "$journal" "le script tient un journal"
assert_contient "$journal" "ntfy.exemple.test" "seul l'hôte y figure"
assert_absent "$journal" "sujet-tres-secret" "le sujet ntfy n'est pas journalisé"
assert_absent "$journal" "$JETON" "le jeton n'est pas journalisé"

titre "config/notify.env.example — le modèle versionné"
EXEMPLE="$SCRIPTS_ROOT/config/notify.env.example"
exemple=""; if [ -f "$EXEMPLE" ]; then exemple="$(cat "$EXEMPLE")"; fi
assert_non_vide "$exemple" "le modèle est versionné"
assert_absent "$exemple" "://" "le modèle ne porte aucune URL, même d'exemple"
for variable in NOTIFY_URL NOTIFY_FORMAT NOTIFY_JETON NOTIFY_DELAI; do
    assert_contient "$exemple" "$variable" "le modèle documente $variable"
done
assert_contient "$exemple" "Sans cette ligne : « ntfy »." "le défaut du format est documenté"
assert_contient "$exemple" "Sans cette ligne : 10." "le défaut du délai est documenté"
if grep -qE '^[[:space:]]*NOTIFY_[A-Z_]*=' "$EXEMPLE"; then
    ko "aucune variable n'est active dans le modèle" "une affectation non commentée s'y trouve"
else ok "aucune variable n'est active dans le modèle"; fi

bilan "TASK-024 / notify-failure.sh"
