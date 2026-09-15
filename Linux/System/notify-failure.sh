#!/usr/bin/env bash
set -Eeuo pipefail

# Alerte l'échec d'un script planifié, vers ntfy ou un webhook JSON. Un seul
# essai, borné dans le temps : une tâche planifiée ne doit jamais attendre son
# notifieur. L'URL de destination vaut secret — un sujet ntfy public s'écrit
# comme un mot de passe — et n'est jamais affichée : seul l'hôte est nommé.

_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_dir/lib/common.sh" ] && [ "$_dir" != "/" ]; do _dir="$(dirname "$_dir")"; done
source "$_dir/lib/common.sh"

CONFIG="notify"
NOM=""
CODE=""
SEC="false"

usage() {
    cat <<'AIDE'
notify-failure.sh — alerte l'échec d'un script planifié.
Usage : notify-failure.sh --script <nom> --code <entier> [options]

  --script <nom>   nom du script en échec, extension comprise
  --code <entier>  code de retour rendu par ce script
  --config <nom>   contexte chargé depuis config/<nom>.env — défaut : notify
  --dry-run        affiche méthode, format, destination et message, sans émettre
  -h, --help       cette aide

Configuration — config/notify.env, non versionné, copié de notify.env.example :
  NOTIFY_URL URL du sujet ntfy ou du webhook ; sans elle, rien n'est émis.
  NOTIFY_FORMAT « ntfy » (défaut) ou « webhook » ; NOTIFY_JETON jeton facultatif,
  jamais affiché ; NOTIFY_DELAI borne d'émission en secondes — défaut 10.

Message : nom du script, code, machine, date, chemin du journal, rien d'autre —
texte pour ntfy, objet JSON de ces cinq champs pour webhook.

Codes de retour : 0 alerte émise ; 1 aucune alerte — configuration absente ou
inexploitable, curl manquant, émission refusée ou en échec, la cause est nommée ;
2 usage — --script ou --code manquant ou mal formé, format ou option inconnue.
--dry-run ne demande ni configuration ni curl, et rend toujours 0.
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

case "$NOM" in
    "") die "--script est requis : nom du script en échec." 2 ;;
    */*|*[[:space:]]*) die "Nom de script invalide : « $NOM » — un nom de fichier, sans chemin." 2 ;;
esac
case "$CODE" in
    ""|*[!0-9]*) die "--code est requis : un entier positif ou nul, reçu « $CODE »." 2 ;;
esac

# Nom affichable du fichier attendu ; le chemin complet ne sort jamais d'ici.
# Fichier absent, --dry-run reste utilisable : il sert à lire ce qui serait émis
# avant d'écrire le .env.
FICHIER="config/$CONFIG.env"
if [ -f "$SCRIPTS_ROOT/$FICHIER" ]; then
    load_config "$CONFIG"
fi

FORMAT="${NOTIFY_FORMAT:-ntfy}"
case "$FORMAT" in
    ntfy|webhook) ;;
    *) die "NOTIFY_FORMAT inconnu : « $FORMAT » — attendu « ntfy » ou « webhook »." 2 ;;
esac

# Borne illisible ramenée au défaut plutôt que refusée : personne ne lirait un 2.
DELAI="${NOTIFY_DELAI:-10}"
case "$DELAI" in
    ""|*[!0-9]*|0) warn "NOTIFY_DELAI inexploitable : « $DELAI » — borne ramenée à 10 s."
                   DELAI=10 ;;
esac

URL="${NOTIFY_URL:-}"
JETON="${NOTIFY_JETON:-}"
# Hôte seul : schéma, chemin et sujet ntfy — qui vaut mot de passe — restent tus.
HOTE="${URL#*://}"; HOTE="${HOTE%%/*}"; HOTE="${HOTE##*@}"

MACHINE="$(uname -n 2>/dev/null || echo inconnue)"
DATE="$(date '+%Y-%m-%d %H:%M:%S')"
JOURNAL="$LOG_DIR/${NOM%.sh}.log"

if [ "$FORMAT" = "ntfy" ]; then
    MESSAGE="Échec de $NOM (code $CODE) sur $MACHINE le $DATE — journal : $JOURNAL"
else
    MESSAGE="$(printf '{"script":"%s","code":%s,"machine":"%s","date":"%s","journal":"%s"}' "$NOM" "$CODE" "$MACHINE" "$DATE" "$JOURNAL")"
fi

if [ "$SEC" = "true" ]; then
    info "Simulation : rien ne sera émis."
    printf '  Méthode     : POST\n  Format      : %s\n  Destination : %s\n  Message     : %s\n' \
        "$FORMAT" "${HOTE:-non configurée}" "$MESSAGE" >&2
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

ARGS=(--silent --output /dev/null --write-out '%{http_code}' --max-time "$DELAI")
if [ "$FORMAT" = "ntfy" ] && [ -n "$JETON" ]; then
    ARGS+=(--header "Authorization: Bearer $JETON")
elif [ "$FORMAT" = "webhook" ]; then
    ARGS+=(--header 'Content-Type: application/json')
fi
ARGS+=(--data "$MESSAGE" "$URL")

# La sortie d'erreur de curl recopie l'URL en clair dans ses messages d'échec :
# elle est écartée, et la cause redite ici par code de retour.
RETOUR=0
REPONSE="$(curl "${ARGS[@]}" 2>/dev/null)" || RETOUR=$?

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
