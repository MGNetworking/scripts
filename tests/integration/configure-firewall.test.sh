#!/usr/bin/env bash
# tests/integration/configure-firewall.test.sh — Linux/Security/configure-firewall.sh.
#
# TASK-045. Aucun ufw réel n'est lancé : un faux ufw en tête de PATH trace
# chaque appel et tient un état minimal — règles, politiques, activation. C'est
# ce journal qui prouve l'ORDRE, et non la seule sortie du script. Le faux ne
# touchant à rien sur la machine, ce fichier ne réclame pas de système jetable.

_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_dir/lib/common.sh" ] && [ "$_dir" != "/" ]; do _dir="$(dirname "$_dir")"; done
source "$_dir/lib/common.sh"
source "$SCRIPTS_ROOT/tests/lib/assert.sh"

CIBLE="$SCRIPTS_ROOT/Linux/Security/configure-firewall.sh"
BAC="$(mktemp -d)"; chmod 755 "$BAC"
FAUX="$BAC/bin"; mkdir -p "$FAUX"
export UFW_LOG="$BAC/appels.log" UFW_ETAT="$BAC/etat"
trap 'rm -rf "$BAC"' EXIT

# UFW_AVALE nomme une cible que « allow » accepte sans l'inscrire : c'est la
# règle SSH qui ne tient pas, celle dont l'absence doit faire refuser l'activation.
cat > "$FAUX/ufw" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$UFW_LOG"
e="$UFW_ETAT"
case "$1" in
status)
    printf 'Status: %s\n' "$(cat "$e/actif" 2>/dev/null || echo inactive)"
    printf 'Default: %s (incoming), %s (outgoing), disabled (routed)\n' \
        "$(cat "$e/entrant" 2>/dev/null || echo deny)" \
        "$(cat "$e/sortant" 2>/dev/null || echo allow)"
    printf '\nTo                         Action      From\n--                         ------      ----\n'
    cat "$e/regles" 2>/dev/null
    ;;
default)
    case "$3" in
    incoming) printf '%s\n' "$2" > "$e/entrant" ;;
    outgoing) printf '%s\n' "$2" > "$e/sortant" ;;
    esac
    ;;
allow)
    : >> "$e/regles"
    [ "$2" = "${UFW_AVALE:-}" ] && exit 0
    if ! awk -v r="$2" '$1 == r {t = 1} END {exit !t}' "$e/regles"; then
        printf '%s     ALLOW       Anywhere\n' "$2" >> "$e/regles"
    fi
    ;;
--force)
    [ "$2" = enable ] && echo active > "$e/actif"
    ;;
esac
exit 0
EOF
chmod +x "$FAUX/ufw"

# État de départ : ufw inactif, aucune règle, et deux politiques FAUTIVES — sans
# quoi les commandes « ufw default » ne seraient jamais passées.
etat_neuf() {
    rm -rf "$UFW_ETAT"; mkdir -p "$UFW_ETAT"
    printf 'allow\n' > "$UFW_ETAT/entrant"
    printf 'deny\n'  > "$UFW_ETAT/sortant"
    : > "$UFW_LOG"
}

# Garde : un vrai ufw atteint par mégarde modifierait la machine qui teste.
if [ "$(PATH="$FAUX:$PATH" command -v ufw)" != "$FAUX/ufw" ]; then
    saute_indisponible "faux ufw en tête de PATH" "PATH ne désigne pas $FAUX/ufw"
    bilan "TASK-045 / configure-firewall.sh"
fi

# lancer [env VAR=valeur…] bash "$CIBLE" [options] — sans terminal, sous faux ufw.
lancer() {
    CODE=0
    SORTIE="$(PATH="$FAUX:$PATH" "$@" 2>&1 </dev/null)" || CODE=$?
}
rang() { grep -nF -- "$1" "$UFW_LOG" | head -n1 | cut -d: -f1; }

assert_avant() {
    local a b; a="$(rang "$1")"; b="$(rang "$2")"
    if [ -n "$a" ] && [ -n "$b" ] && [ "$a" -lt "$b" ]; then ok "$3"
    else ko "$3" "$1 (ligne ${a:-absente}) devrait précéder $2 (ligne ${b:-absente})"; fi
}

# « status » est une lecture : seule une autre commande modifie la machine.
assert_aucune_modification() {
    assert_egal "0" "$(grep -cv '^status' "$UFW_LOG" || true)" "$1"
}

titre "Aide et options"
lancer bash "$CIBLE" --help
assert_code 0 "$CODE" "--help rend 0"
assert_contient "$SORTIE" "--port"       "--help documente les options"
assert_contient "$SORTIE" "SRV_SSH_PORT" "--help nomme les variables lues"
assert_contient "$SORTIE" "ufw status"   "--help dit l'ordre suivi"
assert_contient "$SORTIE" "2 option"     "--help documente les codes de retour"
lancer bash "$CIBLE" --frobnicate
assert_code 2 "$CODE" "une option inconnue rend 2"
lancer bash "$CIBLE" --port
assert_code 2 "$CODE" "--port sans valeur rend 2"

titre "Valeurs mal formées — refus avant toute commande ufw"
etat_neuf
for mauvais in 443 443/sctp 0/tcp 70000/tcp -1/tcp; do
    lancer bash "$CIBLE" -y --port "$mauvais"
    assert_code 2 "$CODE" "« --port $mauvais » est refusé en 2"
done
for mauvais in abc 70000 22/tcp; do
    lancer env SRV_SSH_PORT="$mauvais" bash "$CIBLE" -y
    assert_code 2 "$CODE" "« SRV_SSH_PORT=$mauvais » est refusé en 2"
done
assert_aucune_modification "aucune commande ufw n'est passée avant la validation"

titre "--dry-run — l'état et les commandes prévues, sans rien modifier"
etat_neuf
lancer bash "$CIBLE" --dry-run
assert_code 0 "$CODE" "--dry-run rend 0"
assert_contient "$SORTIE" "Status: inactive"          "--dry-run montre l'état lu par ufw status"
assert_contient "$SORTIE" "ufw default deny incoming" "--dry-run montre la politique entrante prévue"
assert_contient "$SORTIE" "ufw allow 22/tcp"          "--dry-run montre la règle SSH par défaut"
assert_contient "$SORTIE" "ufw --force enable"        "--dry-run montre l'activation prévue"
assert_egal "allow" "$(cat "$UFW_ETAT/entrant")"      "--dry-run n'a pas touché aux politiques"
assert_aucune_modification "--dry-run n'a passé aucune commande modificatrice"

titre "Exécution — politiques, règle SSH avant l'activation, ports ouverts"
etat_neuf
lancer env SRV_SSH_PORT=2222 SRV_FIREWALL_PORTS="443/tcp 80/udp" bash "$CIBLE" -y --port 8443/tcp
assert_code 0 "$CODE" "configuration appliquée : rend 0"
assert_avant "default deny incoming" "default allow outgoing" "la politique entrante est posée avant la sortante"
assert_avant "default allow outgoing" "allow 2222/tcp"        "les politiques précèdent la règle SSH"
assert_avant "allow 2222/tcp" "force enable"                  "la règle SSH est posée avant l'activation"
assert_avant "allow 8443/tcp" "force enable"                  "le port de --port est autorisé avant l'activation"
assert_contient "$(cat "$UFW_ETAT/regles")" "80/udp"  "les ports de SRV_FIREWALL_PORTS sont autorisés"
assert_contient "$(cat "$UFW_ETAT/regles")" "443/tcp" "le premier port de SRV_FIREWALL_PORTS aussi"
assert_egal "deny"   "$(cat "$UFW_ETAT/entrant")" "politique entrante deny"
assert_egal "allow"  "$(cat "$UFW_ETAT/sortant")" "politique sortante allow"
assert_egal "active" "$(cat "$UFW_ETAT/actif")"   "ufw est activé"
assert_contient "$SORTIE" "Règle SSH confirmée"   "la relecture de la règle SSH est annoncée"
avant="$(rang "force enable")"
assert_contient "$(sed -n "$((avant - 1))p" "$UFW_LOG")" "status" \
    "l'activation est immédiatement précédée d'un « ufw status »"

titre "Seconde exécution — ne change rien, et le dit"
: > "$UFW_LOG"
lancer env SRV_SSH_PORT=2222 SRV_FIREWALL_PORTS="443/tcp 80/udp" bash "$CIBLE" --port 8443/tcp
assert_code 0 "$CODE" "seconde exécution rend 0, sans confirmation à donner"
assert_contient "$SORTIE" "Règle SSH déjà présente"       "la règle SSH n'est pas reposée"
assert_contient "$SORTIE" "Règle déjà présente : 443/tcp" "les autres règles non plus"
assert_contient "$SORTIE" "déjà conforme"                 "la seconde exécution dit ne rien avoir à faire"
assert_aucune_modification "aucune commande ufw n'est passée"

titre "Règle SSH absente de « ufw status » — refus d'activer"
etat_neuf
lancer env UFW_AVALE=22/tcp bash "$CIBLE" -y
assert_code 1 "$CODE" "règle SSH absente : rend 1"
assert_contient "$SORTIE" "22/tcp"           "le refus nomme la règle manquante"
assert_contient "$SORTIE" "activation refusée" "le refus dit que l'activation est écartée"
assert_absent "$(cat "$UFW_LOG")" "force enable" "ufw n'est jamais activé"
if [ -e "$UFW_ETAT/actif" ]; then etat_f="actif"; else etat_f="inactif"; fi
assert_egal "inactif" "$etat_f" "ufw reste inactif"

titre "Confirmation — sans terminal ni --yes, et décision 45"
etat_neuf
lancer bash "$CIBLE"
assert_code 1 "$CODE" "sans terminal et sans --yes : rend 1"
assert_contient "$SORTIE" "--yes"     "le message nomme l'option qui débloque"
assert_absent "$SORTIE" "Échec (code" "aucune ligne du trap ERR : refus délibéré"
assert_aucune_modification "rien n'est appliqué avant la confirmation"
etat_neuf
lancer env ASSUME_YES=true bash "$CIBLE"
assert_code 1 "$CODE" "un ASSUME_YES hérité du parent ne confirme pas (décision 45)"
assert_aucune_modification "toujours aucune commande ufw"

titre "ufw absent — installé par apt-get avant toute règle"
BD="$BAC/sans-ufw"; mkdir -p "$BD"
export APT_LOG="$BAC/apt.log"
cat > "$BD/apt-get" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >> "$APT_LOG"
[ "\$1" = install ] && cp "$FAUX/ufw" "$BD/ufw"
exit 0
EOF
chmod +x "$BD/apt-get"
etat_neuf; : > "$APT_LOG"
CODE=0
SORTIE="$(PATH="$BD:/usr/bin:/bin" bash "$CIBLE" -y 2>&1 </dev/null)" || CODE=$?
assert_code 0 "$CODE" "ufw installé puis configuré : rend 0"
assert_egal "update" "$(head -n1 "$APT_LOG")"              "apt-get update est passé en premier"
assert_contient "$(sed -n 2p "$APT_LOG")" "install -y ufw" "puis apt-get install -y ufw"
assert_avant "allow 22/tcp" "force enable" "l'ufw installé sert ensuite à poser la règle SSH"

titre "Hors des cibles de la décision 14, et sans root"
etat_neuf
lancer env OS_ID=centos bash "$CIBLE" -y
assert_code 1 "$CODE" "distribution hors cibles : rend 1"
assert_contient "$SORTIE" "Distribution non supportée" "le refus nomme la distribution"
assert_aucune_modification "aucune commande ufw avant le contrôle de distribution"
etat_neuf
lancer setpriv --reuid=65534 --regid=65534 --clear-groups -- bash "$CIBLE" -y
assert_code 1 "$CODE" "sans privilège root : rend 1"
assert_contient "$SORTIE" "root" "le refus nomme le privilège manquant"
assert_aucune_modification "aucune commande ufw sans root"

bilan "TASK-045 / configure-firewall.sh"
