#!/usr/bin/env bash
set -Eeuo pipefail
# tests/integration/audit-ports.test.sh — Linux/Security/audit-ports.sh (TASK-042).
# ss est remplacé par un faux binaire qui note ses arguments : aucun port réel
# n'est lu hors du dernier cas, et l'appel unique est vérifié.
_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_dir/lib/common.sh" ] && [ "$_dir" != "/" ]; do _dir="$(dirname "$_dir")"; done
source "$_dir/lib/common.sh"
source "$SCRIPTS_ROOT/tests/lib/assert.sh"
CIBLE="$SCRIPTS_ROOT/Linux/Security/audit-ports.sh"
REP_TMP="$(mktemp -d)"; chmod 755 "$REP_TMP"
F_OUT="$REP_TMP/stdout"; F_ERR="$REP_TMP/stderr"; CODE=0
F_JOURNAL="$REP_TMP/ss.journal"; F_SORTIE="$REP_TMP/ss.sortie"
trap 'rm -rf "$REP_TMP"' EXIT
lancer() { CODE=0; ( "$@" ) >"$F_OUT" 2>"$F_ERR" </dev/null || CODE=$?; }
sortie() { cat "$F_OUT"; }
erreur() { cat "$F_ERR"; }
# champ <adresse> <port> <n> — le champ n de la ligne qui écoute là, ou rien.
champ() { awk -v a="$1" -v p="$2" -v n="$3" '$3 == a && $4 == p {print $n; exit}' "$F_OUT"; }
# combien <portée> — les lignes d'écoute de cette portée ; sans argument, toutes.
combien() { awk -v p="${1:-}" '$1 ~ /^(tcp|udp)$/ && (p == "" || $2 == p) {n++} END {print n + 0}' "$F_OUT"; }
# journal_vide — le faux ss note chaque appel : à vider avant chaque relevé.
journal_vide() { : > "$F_JOURNAL"; chmod 666 "$F_JOURNAL"; }
# sans_ss <dest> — un PATH de liens SANS ss : le rendre fautif ne suffirait pas.
sans_ss() { local d b; mkdir -p "$1"
    for d in /usr/local/sbin /usr/local/bin /usr/sbin /usr/bin /sbin /bin; do
        for b in "$d"/*; do [ "${b##*/}" = ss ] || [ -e "$1/${b##*/}" ] || ln -s "$b" "$1/${b##*/}" 2>/dev/null || true; done
    done; }
# faux_ss — rend F_SORTIE, en retirant la colonne des processus hors root.
faux_ss() { mkdir -p "$FAUX"
    cat > "$FAUX/ss" <<'FAUX_SS'
#!/bin/sh
printf '%s\n' "$*" >> "$JOURNAL_SS"
[ -f "$F_SORTIE" ] || exit 0
if [ "$(id -u)" = 0 ]; then cat "$F_SORTIE"
else sed 's/ users:((.*$//' "$F_SORTIE"; fi
FAUX_SS
    chmod 755 "$FAUX/ss"; }
# MOINS — de quoi abaisser l'UID, quand le fichier tourne déjà en root.
MOINS=()
if [ "$(id -u)" = "0" ] && setpriv --reuid=65534 --regid=65534 --clear-groups true 2>/dev/null; then
    MOINS=(setpriv --reuid=65534 --regid=65534 --clear-groups)
elif [ "$(id -u)" = "0" ] && runuser -u nobody -- true 2>/dev/null; then
    MOINS=(runuser -u nobody --)
fi

if [ ! -f "$CIBLE" ]; then
    ko "Linux/Security/audit-ports.sh existe" "fichier introuvable : $CIBLE"
    bilan "TASK-042 / audit-ports.sh"
fi
if [ "$(uname -s 2>/dev/null || true)" != "Linux" ]; then
    saute_par_nature "l'ensemble des cas d'audit-ports.sh" "cet hôte n'est pas un Linux"
    bilan "TASK-042 / audit-ports.sh"
fi

titre "1. Aide et refus d'usage"
lancer bash "$CIBLE" --help
assert_code 0 "$CODE" "--help sort en 0"
for motif in "PROTO" "PORTÉE" "ADRESSE" "PROCESSUS" "exposé" "local" "ss -H -tulpn" "inconnu (root requis)" "Codes de retour"; do
    assert_contient "$(sortie)" "$motif" "--help documente « $motif »"
done
lancer bash "$CIBLE" --nawak
assert_code 2 "$CODE" "une option inconnue sort en 2"
assert_contient "$(erreur)" "Option inconnue : --nawak" "le refus nomme l'option"
assert_egal "" "$(sortie)" "aucun relevé n'est produit avant le refus"

titre "2. ss absent — code 1"
SANS_SS="$REP_TMP/sans-ss"
sans_ss "$SANS_SS"
if PATH="$SANS_SS" command -v ss >/dev/null 2>&1; then ko "garde : ss est masqué" "il y reste visible"; else ok "garde : ss est masqué"; fi
lancer env "PATH=$SANS_SS" bash "$CIBLE"
assert_code 1 "$CODE" "sans ss, le script sort en 1"
assert_contient "$(erreur)" "ss" "le refus nomme la commande manquante"
assert_egal "" "$(sortie)" "sans ss, aucun relevé n'est produit"

FAUX="$REP_TMP/bin"; faux_ss
titre "3. Relevé vide — code 0, colonnes et résumé"
journal_vide
lancer env "PATH=$FAUX:$PATH" JOURNAL_SS="$F_JOURNAL" F_SORTIE="$REP_TMP/absent" bash "$CIBLE"
assert_code 0 "$CODE" "un relevé vide sort en 0"
S="$(sortie)"
for motif in "PROTO" "PORTÉE" "ADRESSE" "PROCESSUS" "aucune écoute" "Ports exposés : aucun"; do
    assert_contient "$S" "$motif" "le relevé vide porte « $motif »"
done
assert_contient "$S" "Résumé : 0 écoute(s) relevée(s), dont 0 exposée(s)." "le résumé compte zéro écoute"
assert_absent "$(erreur)" "Échec (code" "le trap ERR n'ajoute aucune ligne"

# Dix écoutes : les trois formes d'exposition, les deux boucles locales, une
# adresse d'interface, deux détenants, et une écoute sans processus.
cat > "$F_SORTIE" <<'SORTIE'
udp UNCONN 0 0 0.0.0.0:68 0.0.0.0:* users:(("dhclient",pid=700,fd=6))
tcp LISTEN 0 128 0.0.0.0:22 0.0.0.0:* users:(("sshd",pid=800,fd=3))
tcp LISTEN 0 511 *:80 *:* users:(("nginx",pid=900,fd=6))
tcp LISTEN 0 511 [::]:443 [::]:* users:(("nginx",pid=901,fd=7))
tcp LISTEN 0 128 192.168.1.5:8080 0.0.0.0:* users:(("java",pid=950,fd=8))
tcp LISTEN 0 128 127.0.0.1:631 0.0.0.0:* users:(("cupsd",pid=600,fd=9))
tcp LISTEN 0 128 [::1]:631 [::]:* users:(("cupsd",pid=601,fd=10))
tcp LISTEN 0 128 127.0.0.53%lo:53 0.0.0.0:* users:(("systemd-resolve",pid=500,fd=13))
udp UNCONN 0 0 0.0.0.0:5353 0.0.0.0:* users:(("avahi",pid=1,fd=1),("avahi",pid=2,fd=2))
tcp LISTEN 0 128 0.0.0.0:9999 0.0.0.0:*
SORTIE

titre "4. Un relevé fixe, colonne par colonne"
journal_vide
lancer env "PATH=$FAUX:$PATH" JOURNAL_SS="$F_JOURNAL" F_SORTIE="$F_SORTIE" bash "$CIBLE"
assert_code 0 "$CODE" "le relevé fixe sort en 0"
assert_egal "-H -tulpn" "$(cat "$F_JOURNAL")" "ss est appelé avec exactement -H -tulpn"
assert_egal "1" "$(wc -l < "$F_JOURNAL" | tr -d ' ')" "ss n'est appelé qu'une fois"
while read -r proto adresse port portee processus; do
    assert_egal "$proto" "$(champ "$adresse" "$port" 1)" "$adresse:$port — protocole $proto"
    assert_egal "$portee" "$(champ "$adresse" "$port" 2)" "$adresse:$port — portée $portee"
    assert_egal "$adresse" "$(champ "$adresse" "$port" 3)" "$adresse:$port — adresse rendue sans son port"
    assert_egal "$port" "$(champ "$adresse" "$port" 4)" "$adresse:$port — port"
    assert_egal "$processus" "$(champ "$adresse" "$port" 5)" "$adresse:$port — processus $processus"
done <<'ATTENDU'
tcp 0.0.0.0 22 exposé sshd
udp 0.0.0.0 68 exposé dhclient
tcp * 80 exposé nginx
tcp [::] 443 exposé nginx
tcp 192.168.1.5 8080 exposé java
tcp 127.0.0.1 631 local cupsd
tcp [::1] 631 local cupsd
tcp 127.0.0.53%lo 53 local systemd-resolve
tcp 0.0.0.0 9999 exposé inconnu
ATTENDU
assert_egal "avahi,avahi" "$(champ 0.0.0.0 5353 5)" "deux détenants sont listés, séparés par une virgule"
assert_egal "10" "$(combien)" "les dix écoutes sont rendues, une par ligne"
assert_egal "7" "$(combien exposé)" "sept écoutes sont dites exposées"
assert_egal "3" "$(combien local)" "trois écoutes sont dites locales"
assert_contient "$(sortie)" "Résumé : 10 écoute(s) relevée(s), dont 7 exposée(s)." "le résumé compte les écoutes et les exposées"
assert_egal "Ports exposés : 22,68,80,443,5353,8080,9999" "$(grep -F 'Ports exposés : ' "$F_OUT")" "les ports exposés sont comptés et listés, sans doublon ni port local"

titre "5. Sans privilège — le processus n'est pas lisible"
journal_vide
lancer "${MOINS[@]}" env "PATH=$FAUX:$PATH" JOURNAL_SS="$F_JOURNAL" F_SORTIE="$F_SORTIE" bash "$CIBLE"
assert_code 0 "$CODE" "sans privilège, le relevé sort en 0"
assert_egal "10" "$(grep -cF 'inconnu (root requis)' "$F_OUT" || true)" "chaque processus illisible est dit « inconnu (root requis) »"
assert_egal "7" "$(combien exposé)" "les portées sont rendues sans privilège"
assert_egal "1" "$(wc -l < "$F_JOURNAL" | tr -d ' ')" "ss n'est appelé qu'une fois, sans privilège non plus"

titre "6. Le relevé réel de la machine, et la lecture seule"
touch "$REP_TMP/temoin"
lancer bash "$CIBLE"
assert_code 0 "$CODE" "le relevé réel sort en 0"
for motif in "PROTO" "Résumé : "; do assert_contient "$(sortie)" "$motif" "le relevé réel porte « $motif »"; done
assert_absent "$(erreur)" "Échec (code" "le trap ERR n'ajoute aucune ligne"
ECRITURES="$(find /etc /home /root -newer "$REP_TMP/temoin" -not -path "$LOG_DIR/*" 2>/dev/null || true)"
assert_egal "" "$ECRITURES" "aucun fichier n'est modifié hors du répertoire de journaux"

bilan "TASK-042 / audit-ports.sh"
