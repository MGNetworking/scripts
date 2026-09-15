#!/usr/bin/env bash
# tests/integration/configure-firewall.test.sh — Linux/Security/configure-firewall.sh.
#
# TASK-045. Aucun ufw réel n'est lancé : un faux ufw en tête de PATH trace chaque
# appel et tient un état minimal. Il est fidèle sur le point qui décide de tout
# ici — inactif, il ne dit RIEN des règles, comme le vrai « ufw status » ; seul
# « ufw show added » les donne, actif ou non. Un faux sshd fixe le port d'écoute.
# C'est le journal des appels qui prouve l'ORDRE, et non la seule sortie.

_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_dir/lib/common.sh" ] && [ "$_dir" != "/" ]; do _dir="$(dirname "$_dir")"; done
source "$_dir/lib/common.sh"
source "$SCRIPTS_ROOT/tests/lib/assert.sh"

CIBLE="$SCRIPTS_ROOT/Linux/Security/configure-firewall.sh"
BAC="$(mktemp -d)"; chmod 755 "$BAC"
FAUX="$BAC/bin"; mkdir -p "$FAUX"
export UFW_LOG="$BAC/appels.log" UFW_ETAT="$BAC/etat"
trap 'rm -rf "$BAC"' EXIT

# UFW_AVALE nomme une cible que « allow » accepte sans l'inscrire : c'est la règle
# SSH qui ne tient pas, celle dont l'absence doit faire refuser l'activation.
cat > "$FAUX/ufw" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$UFW_LOG"
e="$UFW_ETAT"
case "$1" in
status)
    # Fidèle au vrai : inactif, ufw ne dit rien des règles ni des politiques.
    [ "$(cat "$e/actif" 2>/dev/null)" = active ] || { printf 'Status: inactive\n'; exit 0; }
    printf 'Status: active\nDefault: %s (incoming), %s (outgoing), disabled (routed)\n\n' \
        "$(cat "$e/entrant" 2>/dev/null || echo deny)" "$(cat "$e/sortant" 2>/dev/null || echo allow)"
    printf 'To                         Action      From\n--                         ------      ----\n'
    awk '$4 == "" || $4 == "(v6)" {v6 = ($4 == "(v6)")
         printf "%-26s %-11s Anywhere%s\n", $3 (v6 ? " (v6)" : ""), toupper($2), (v6 ? " (v6)" : "")}' \
        "$e/ajoute" 2>/dev/null
    ;;
show)
    # Les règles posées, lisibles ufw actif comme inactif : c'est ce que lit le
    # script, et ce que « status » ne dirait pas tant qu'ufw n'est pas activé.
    [ -s "$e/ajoute" ] || exit 0
    printf "Added user rules (see 'ufw status' for running rules):\n"
    cat "$e/ajoute"
    ;;
default)
    case "$3" in
    incoming) printf '%s\n' "$2" > "$e/entrant" ;;
    outgoing) printf '%s\n' "$2" > "$e/sortant" ;;
    esac
    ;;
allow)
    [ "$2" = "${UFW_AVALE:-}" ] && exit 0
    inscrire() { grep -qxF "$1" "$e/ajoute" 2>/dev/null || printf '%s\n' "$1" >> "$e/ajoute"; }
    inscrire "ufw allow $2"
    grep -q '^IPV6=yes' "${UFW_DEFAUT:-/etc/default/ufw}" 2>/dev/null && inscrire "ufw allow $2 (v6)"
    ;;
--force)
    [ "$2" = enable ] && echo active > "$e/actif"
    ;;
esac
exit 0
EOF

cat > "$FAUX/sshd" <<'EOF'
#!/bin/sh
printf 'port %s\n' "${SSHD_PORT:-22}"
EOF
chmod +x "$FAUX/ufw" "$FAUX/sshd"

# État de départ : ufw inactif, aucune règle ajoutée, et deux politiques FAUTIVES
# — sans quoi les commandes « ufw default » ne seraient jamais passées.
etat_neuf() {
    rm -rf "$UFW_ETAT"; mkdir -p "$UFW_ETAT"
    printf 'allow\n' > "$UFW_ETAT/entrant"
    printf 'deny\n'  > "$UFW_ETAT/sortant"
    : > "$UFW_ETAT/ajoute"
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

# « status » et « show » sont des lectures : seule une autre commande modifie.
assert_aucune_modification() {
    assert_egal "0" "$(grep -cvE '^(status|show)' "$UFW_LOG" || true)" "$1"
}
# Nombre d'appels « allow » portant exactement sur la cible donnée.
nb_allow() { grep -c "^allow $1\$" "$UFW_LOG" || true; }

titre "Aide et options"
lancer bash "$CIBLE" --help
assert_code 0 "$CODE" "--help rend 0"
assert_contient "$SORTIE" "--port"         "--help documente les options"
assert_contient "$SORTIE" "SRV_SSH_PORT"   "--help nomme les variables lues"
assert_contient "$SORTIE" "ufw show added" "--help dit l'ordre suivi"
assert_contient "$SORTIE" "2 option"       "--help documente les codes de retour"
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

titre "Port d'écoute de sshd — confronté à SRV_SSH_PORT avant tout"
etat_neuf
lancer env SSHD_PORT=2222 bash "$CIBLE" -y
assert_code 1 "$CODE" "sshd écoute 2222 et SRV_SSH_PORT vaut 22 : rend 1"
assert_contient "$SORTIE" "SRV_SSH_PORT=22" "le refus nomme le port configuré"
assert_contient "$SORTIE" "2222"            "le refus nomme le port réel de sshd"
assert_aucune_modification "refus avant toute commande ufw"
etat_neuf
lancer env SSHD_PORT=2222 SRV_SSH_PORT=2222 bash "$CIBLE" -y
assert_code 0 "$CODE" "les deux ports concordent : rend 0"

titre "--dry-run — l'état et les commandes prévues, sans rien modifier"
etat_neuf
lancer bash "$CIBLE" --dry-run
assert_code 0 "$CODE" "--dry-run rend 0"
assert_contient "$SORTIE" "Status: inactive"          "--dry-run montre l'état lu par ufw"
assert_contient "$SORTIE" "ufw allow 22/tcp"          "--dry-run montre la règle SSH par défaut"
assert_contient "$SORTIE" "ufw default deny incoming" "--dry-run montre la politique entrante prévue"
assert_contient "$SORTIE" "ufw --force enable"        "--dry-run montre l'activation prévue"
assert_egal "allow" "$(cat "$UFW_ETAT/entrant")"      "--dry-run n'a pas touché aux politiques"
assert_aucune_modification "--dry-run n'a passé aucune commande modificatrice"

titre "Exécution — règle SSH d'abord, puis ports, politiques et activation"
etat_neuf
lancer env SSHD_PORT=2222 SRV_SSH_PORT=2222 SRV_FIREWALL_PORTS="443/tcp 80/udp" \
    bash "$CIBLE" -y --port 8443/tcp
assert_code 0 "$CODE" "configuration appliquée : rend 0"
assert_avant "allow 2222/tcp" "default deny incoming" "la règle SSH précède toute politique"
assert_avant "default deny incoming" "default allow outgoing" "la politique entrante précède la sortante"
assert_avant "allow 8443/tcp" "force enable" "le port de --port est autorisé avant l'activation"
assert_contient "$(cat "$UFW_ETAT/ajoute")" "80/udp"  "les ports de SRV_FIREWALL_PORTS sont autorisés"
assert_contient "$(cat "$UFW_ETAT/ajoute")" "443/tcp" "le premier port de SRV_FIREWALL_PORTS aussi"
assert_egal "deny"   "$(cat "$UFW_ETAT/entrant")" "politique entrante deny"
assert_egal "allow"  "$(cat "$UFW_ETAT/sortant")" "politique sortante allow"
assert_egal "active" "$(cat "$UFW_ETAT/actif")"   "ufw est activé"
assert_contient "$SORTIE" "Règle SSH confirmée"   "la relecture de la règle SSH est annoncée"
avant="$(rang "force enable")"
assert_contient "$(sed -n "$((avant - 1))p" "$UFW_LOG")" "show added" \
    "l'activation est immédiatement précédée d'une relecture des règles"

titre "Seconde exécution — ne change rien, et le dit"
: > "$UFW_LOG"
lancer env SSHD_PORT=2222 SRV_SSH_PORT=2222 SRV_FIREWALL_PORTS="443/tcp 80/udp" \
    bash "$CIBLE" --port 8443/tcp
assert_code 0 "$CODE" "seconde exécution rend 0, sans confirmation à donner"
assert_contient "$SORTIE" "Règle SSH déjà présente"       "la règle SSH n'est pas reposée"
assert_contient "$SORTIE" "Règle déjà présente : 443/tcp" "les autres règles non plus"
assert_contient "$SORTIE" "déjà conforme"                 "la seconde exécution dit ne rien avoir à faire"
assert_aucune_modification "aucune commande ufw n'est passée"

titre "ufw inactif — « ufw show added » fait foi, la règle n'est pas reposée"
etat_neuf
printf 'ufw allow 2222/tcp\n' > "$UFW_ETAT/ajoute"
lancer env SSHD_PORT=2222 SRV_SSH_PORT=2222 bash "$CIBLE" -y
assert_code 0 "$CODE" "règle lue malgré un ufw inactif : rend 0"
assert_contient "$SORTIE" "Règle SSH déjà présente" "la règle est vue sans que ufw soit actif"
assert_egal "0" "$(nb_allow 2222/tcp)" "elle n'est pas reposée pour autant"
assert_egal "active" "$(cat "$UFW_ETAT/actif")" "les politiques sont posées, puis ufw activé"

titre "ufw déjà actif et sans règle SSH — l'allow SSH passe avant les politiques"
etat_neuf
printf 'active\n' > "$UFW_ETAT/actif"
lancer env SSHD_PORT=2222 SRV_SSH_PORT=2222 bash "$CIBLE" -y
assert_code 0 "$CODE" "règle SSH ajoutée à un ufw actif : rend 0"
assert_avant "allow 2222/tcp" "default deny incoming" "l'allow SSH précède « default deny incoming »"
assert_absent "$(cat "$UFW_LOG")" "force enable" "un ufw déjà actif n'est pas réactivé"

titre "Règle SSH — seule une autorisation depuis n'importe où compte"
etat_neuf
printf 'ufw allow from 192.168.1.0/24 to any port 22 proto tcp\n' > "$UFW_ETAT/ajoute"
lancer bash "$CIBLE" -y
assert_code 0 "$CODE" "une autorisation restreinte ne dispense pas de la générale : rend 0"
assert_egal "1" "$(nb_allow 22/tcp)" "la règle générale est donc reposée"
etat_neuf
printf 'ufw deny 22/tcp\n' > "$UFW_ETAT/ajoute"
lancer bash "$CIBLE" -y
assert_code 1 "$CODE" "une règle deny sur le port SSH rend 1"
assert_contient "$SORTIE" "ufw deny 22/tcp" "le refus nomme la règle en place"
assert_absent "$(cat "$UFW_LOG")" "force enable" "ufw n'est pas activé"
assert_aucune_modification "rien n'est appliqué tant que la règle deny est là"

titre "IPV6=yes — la règle v6 est attendue elle aussi"
etat_neuf
printf 'IPV6=yes\n' > "$BAC/default-ufw"
printf 'ufw allow 22/tcp\n' > "$UFW_ETAT/ajoute"
lancer env UFW_DEFAUT="$BAC/default-ufw" bash "$CIBLE" -y
assert_code 0 "$CODE" "règle v4 seule complétée : rend 0"
assert_contient "$(cat "$UFW_ETAT/ajoute")" "ufw allow 22/tcp (v6)" "la règle v6 manquante est posée"

titre "Règle SSH absente de « ufw show added » — refus d'activer"
etat_neuf
lancer env UFW_AVALE=22/tcp bash "$CIBLE" -y
assert_code 1 "$CODE" "règle SSH absente : rend 1"
assert_contient "$SORTIE" "22/tcp"             "le refus nomme la règle manquante"
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
etat_neuf
if command -v script >/dev/null 2>&1; then
    # Avec un terminal, un ASSUME_YES hérité non remis à false confirmerait tout
    # seul : c'est ici, et nulle part ailleurs, que la remise à false se prouve.
    CODE=0
    SORTIE="$(printf 'n\n' | PATH="$FAUX:$PATH" ASSUME_YES=true \
        script -qec "bash $CIBLE" /dev/null 2>&1)" || CODE=$?
    assert_code 1 "$CODE" "ASSUME_YES hérité, avec un terminal : rend 1"
    assert_absent "$SORTIE" "Confirmation automatique" "l'ASSUME_YES du parent est ignoré"
    assert_contient "$SORTIE" "abandonnée" "la question est posée et « n » l'écarte"
    assert_aucune_modification "aucune commande ufw après ce refus"
else
    saute_indisponible "ASSUME_YES hérité avec un terminal" "script (util-linux) absent"
fi

titre "ufw absent — installé par apt-get avant toute règle"
BD="$BAC/sans-ufw"; mkdir -p "$BD"
export APT_LOG="$BAC/apt.log"
cat > "$BD/apt-get" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >> "$APT_LOG"
[ "\$1" = install ] && cp "$FAUX/ufw" "$BD/ufw"
exit 0
EOF
cp "$FAUX/sshd" "$BD/sshd"
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
