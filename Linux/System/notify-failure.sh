#!/usr/bin/env bash
set -Eeuo pipefail

# Alerte l'échec d'un script planifié, vers ntfy ou un webhook JSON. Un seul essai,
# borné : une tâche planifiée n'attend pas son notifieur. L'URL vaut secret — un
# sujet ntfy s'écrit comme un mot de passe — et seul l'hôte de destination est nommé.

_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_dir/lib/common.sh" ] && [ "$_dir" != "/" ]; do _dir="$(dirname "$_dir")"; done
source "$_dir/lib/common.sh"

CONFIG="notify"; NOM=""; CODE=""; SEC="false"

usage() {
    cat <<'AIDE'
notify-failure.sh — alerte l'échec d'un script planifié.
Usage : notify-failure.sh --script <nom> --code <entier> [options]

  --script <nom>   nom du script en échec, sans chemin, guillemet ni barre oblique inverse
  --code <entier>  code de retour rendu par ce script, sans zéro de tête
  --config <nom>   contexte chargé depuis config/<nom>.env — défaut : notify
  --dry-run        affiche méthode, format, destination et message, sans émettre
  -h, --help       cette aide

Configuration — config/notify.env, non versionné, copié de notify.env.example :
  NOTIFY_URL URL du sujet ntfy ou du webhook ; sans elle, rien n'est émis.
  NOTIFY_FORMAT « ntfy » (défaut) ou « webhook ».
  NOTIFY_JETON jeton facultatif, valable pour les deux formats, jamais affiché.
  NOTIFY_DELAI borne d'émission en secondes — défaut 10.
  URL et en-têtes partent par l'entrée standard (curl --config -) : en argument,
  la table des processus les montrerait à tout utilisateur de la machine.

Message : nom du script, code, machine, date, chemin du journal, rien d'autre —
texte pour ntfy, objet JSON de ces cinq champs pour webhook.

Codes de retour : 0 alerte émise ; 1 aucune alerte — configuration absente ou
inexploitable, curl manquant, émission refusée ou en échec, cause nommée ;
2 usage — --script ou --code manquant ou mal formé, format ou option inconnue.
--dry-run ne demande ni configuration ni curl : il rend 0, ou 2 si un argument
ou NOTIFY_FORMAT est refusé.
AIDE
}

while [ "${1:-}" != "" ]; do
    case "$1" in
        --script)   shift; [ -n "${1:-}" ] || die "--script attend le nom du script en échec." 2
                    NOM="$1"; shift ;;
        --code)     shift; [ -n "${1:-}" ] || die "--code attend le code de retour du script." 2
                    CODE="$1"; shift ;;
        --config)   shift; [ -n "${1:-}" ] || die "--config attend un nom de contexte." 2
                    CONFIG="$1"; shift ;;
        --dry-run)  SEC="true"; shift ;;
        -h|--help)  usage; exit 0 ;;
        *)          die "Option inconnue : $1" 2 ;;
    esac
done

# Le corps JSON porte ces valeurs telles quelles : un guillemet ou une barre
# oblique inverse dans le nom, un zéro de tête dans le code, l'invalideraient.
case "$NOM" in
    "") die "--script est requis : nom du script en échec." 2 ;;
    */*|*[[:space:]]*) die "Nom de script invalide : « $NOM » — un nom de fichier, sans chemin." 2 ;;
    *'"'*|*\\*) die "Nom de script invalide : « $NOM » — un guillemet ou une barre oblique inverse rendrait le corps JSON invalide." 2 ;;
esac
case "$CODE" in
    ""|*[!0-9]*) die "--code est requis : un entier positif ou nul, reçu « $CODE »." 2 ;;
    0[0-9]*) die "--code invalide : « $CODE » — un zéro de tête rendrait le corps JSON invalide." 2 ;;
esac

# Fichier absent, --dry-run reste utilisable : il sert à lire ce qui serait émis.
FICHIER="config/$CONFIG.env"
if [ -f "$SCRIPTS_ROOT/$FICHIER" ]; then load_config "$CONFIG"; fi

FORMAT="${NOTIFY_FORMAT:-ntfy}"
case "$FORMAT" in ntfy|webhook) ;; *) die "NOTIFY_FORMAT inconnu : « $FORMAT » — attendu « ntfy » ou « webhook »." 2 ;; esac

# Borne illisible ramenée au défaut plutôt que refusée : personne ne lirait un 2.
DELAI="${NOTIFY_DELAI:-10}"
case "$DELAI" in
    ""|*[!0-9]*|0) warn "NOTIFY_DELAI inexploitable : « $DELAI » — borne ramenée à 10 s."; DELAI=10 ;;
esac

URL="${NOTIFY_URL:-}"; JETON="${NOTIFY_JETON:-}"
# Hôte seul : schéma, chemin, paramètres et sujet ntfy — qui vaut mot de passe —
# restent tus. Sans schéma reconnu, rien n'est affiché plutôt qu'une URL entière.
HOTE=""
case "$URL" in
    *://*) HOTE="${URL#*://}"; HOTE="${HOTE%%[?#]*}"; HOTE="${HOTE%%/*}"; HOTE="${HOTE##*@}" ;;
esac

MACHINE="$(uname -n 2>/dev/null || echo inconnue)"; DATE="$(date '+%Y-%m-%d %H:%M:%S')"
JOURNAL="$LOG_DIR/${NOM%.sh}.log"
MESSAGE="Échec de $NOM (code $CODE) sur $MACHINE le $DATE — journal : $JOURNAL"
if [ "$FORMAT" = "webhook" ]; then
    MESSAGE="$(printf '{"script":"%s","code":%s,"machine":"%s","date":"%s","journal":"%s"}' "$NOM" "$CODE" "$MACHINE" "$DATE" "$JOURNAL")"
fi

if [ "$SEC" = "true" ]; then
    info "Simulation : rien ne sera émis."
    info "Méthode     : POST"
    info "Format      : $FORMAT"
    info "Destination : ${HOTE:-non configurée}"
    info "Message     : $MESSAGE"
    exit 0
fi

if [ -z "$URL" ]; then
    warn "Aucune configuration exploitable : renseigner NOTIFY_URL dans $FICHIER (modèle : $FICHIER.example). Rien n'a été émis."
    exit 1
fi
case "$URL" in
    http://*|https://*) ;;
    *) warn "NOTIFY_URL inexploitable dans $FICHIER : une adresse commençant par http ou https est attendue. Rien n'a été émis."
       exit 1 ;;
esac

require_cmd curl

# URL et en-têtes passent par l'entrée standard (curl --config -) : en argument,
# tout utilisateur de la machine les lirait dans la table des processus, et
# l'URL vaut mot de passe. Le corps, lui, ne porte aucun secret.
echapper() { local v="$1"; v="${v//\\/\\\\}"; printf '%s' "${v//\"/\\\"}"; }
CONF="url = \"$(echapper "$URL")\""
if [ -n "$JETON" ]; then CONF+=$'\n'"header = \"Authorization: Bearer $(echapper "$JETON")\""; fi
if [ "$FORMAT" = "webhook" ]; then CONF+=$'\n'"header = \"Content-Type: application/json\""; fi

ARGS=(--config - --silent --output /dev/null --write-out '%{http_code}' --max-time "$DELAI" --data "$MESSAGE")

# La sortie d'erreur de curl recopie l'URL en clair dans ses messages d'échec :
# elle est écartée, et la cause redite ici par code de retour.
RETOUR=0
REPONSE="$(printf '%s\n' "$CONF" | curl "${ARGS[@]}" 2>/dev/null)" || RETOUR=$?

if [ "$RETOUR" -ne 0 ]; then
    case "$RETOUR" in
        6)  warn "Résolution de nom en échec pour l'hôte ${HOTE:-inconnu} — aucune alerte émise." ;;
        7)  warn "Connexion refusée par l'hôte ${HOTE:-inconnu} — aucune alerte émise." ;;
        28) warn "Délai dépassé (${DELAI}s) vers l'hôte ${HOTE:-inconnu} — aucune alerte émise." ;;
        *)  warn "curl a échoué (code $RETOUR) vers l'hôte ${HOTE:-inconnu} — aucune alerte émise." ;;
    esac
    exit 1
fi

case "$REPONSE" in
    2[0-9][0-9]) ;;
    "") warn "Aucune réponse HTTP de l'hôte ${HOTE:-inconnu} — aucune alerte émise."; exit 1 ;;
    *)  warn "Réponse HTTP $REPONSE hors de la plage 2xx — aucune alerte émise."; exit 1 ;;
esac

success "Alerte émise vers ${HOTE:-inconnu} : $NOM, code $CODE."
