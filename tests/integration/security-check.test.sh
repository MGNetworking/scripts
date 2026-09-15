#!/usr/bin/env bash
set -Eeuo pipefail
# tests/integration/security-check.test.sh — Linux/Security/security-check.sh (TASK-043).
_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_dir/lib/common.sh" ] && [ "$_dir" != "/" ]; do _dir="$(dirname "$_dir")"; done
# shellcheck source=/dev/null
source "$_dir/lib/common.sh"
# shellcheck source=/dev/null
source "$SCRIPTS_ROOT/tests/lib/assert.sh"
CIBLE="$SCRIPTS_ROOT/Linux/Security/security-check.sh"
REP_TMP="$(mktemp -d)"; chmod 755 "$REP_TMP"
F_OUT="$REP_TMP/stdout"; F_ERR="$REP_TMP/stderr"; CODE=0
F_JOURNAL="$REP_TMP/journal"; : > "$F_JOURNAL"
trap 'rm -rf "$REP_TMP"' EXIT
lancer() { CODE=0; ( "$@" ) >"$F_OUT" 2>"$F_ERR" </dev/null || CODE=$?; }
sortie() { cat "$F_OUT"; }; erreur() { cat "$F_ERR"; }; detail_de() { sed -n "s/^[A-Z]*  $1 — //p" "$F_OUT"; }
# sans_outil <dest> <binaire>... — un PATH de liens SANS ces binaires : les rendre
# fautifs ne suffirait pas, « command -v » les trouverait encore.
sans_outil() { local dest="$1"; shift; mkdir -p "$dest"; local d b
    for d in /usr/local/sbin /usr/local/bin /usr/sbin /usr/bin /sbin /bin; do
        for b in "$d"/*; do case " $* " in *" ${b##*/} "*) continue ;; esac
            [ -e "$dest/${b##*/}" ] || ln -s "$b" "$dest/${b##*/}" 2>/dev/null || true
        done; done; }
if [ ! -f "$CIBLE" ]; then
    ko "Linux/Security/security-check.sh existe" "fichier introuvable : $CIBLE"; bilan "TASK-043 / security-check.sh"
elif [ "$(uname -s 2>/dev/null || true)" != "Linux" ]; then
    saute_par_nature "l'ensemble des cas de security-check.sh" "cet hôte n'est pas un Linux"; bilan "TASK-043 / security-check.sh"
fi

FAUX="$REP_TMP/bin"; mkdir -p "$FAUX"
# Un seul faux pour les cinq outils : il dispatche sur le nom par lequel on l'appelle.
cat > "$FAUX/faux-outil" <<'FAUX_OUTIL'
#!/bin/sh
printf '%s %s\n' "${0##*/}" "$*" >> "$JOURNAL"
[ -z "${FAUX_ECHEC:-}" ] || exit "$FAUX_ECHEC"
case "${0##*/}" in
    sshd) [ -z "${SSHD_DORT:-}" ] || sleep "$SSHD_DORT"; [ -z "${SSH_MUET:-}" ] || exit 0
          printf 'port 22\npasswordauthentication %s\npermitrootlogin %s\n' "${SSH_MDP:-no}" "${SSH_ROOT:-no}" ;;
    ufw)  actif=active; inactif=inactive; statut='Status:'; defaut='Default:'
          [ "${LC_ALL:-}" = "C" ] || { actif=actif; inactif=inactif; statut='État :'; defaut='Par défaut :'; }
          [ "${UFW_ACTIF:-oui}" = "oui" ] || { actif="$inactif"; defaut=""; }
          printf '%s %s\n' "$statut" "$actif"
          [ -z "$defaut" ] || printf '%s %s (incoming), allow (outgoing)\n' "$defaut" "${UFW_ENTREE:-deny}" ;;
    fail2ban-client) printf 'Status\n|- Number of jail:\t1\n`- Jail list:\t%s\n' "${F2B_PRISONS:-sshd}" ;;
    getent) [ "${1:-}" = "passwd" ] || exit 2
            [ -z "${GETENT_MUET:-}" ] || exit 0
            printf '%s\n' 'root:x:0:0:root:/root:/bin/bash' 'max:x:1000:1000:Max:/home/max:/bin/bash'
            if [ "${COMPTE_UID0:-}" = "oui" ]; then printf '%s\n' 'fauxroot:x:0:0:Faux:/home/fauxroot:/bin/sh'; fi ;;
    apt-get) [ "$*" = "-s upgrade" ] || exit 2
             i=0; while [ "$i" -lt "${APT_MAJ:-0}" ]; do i=$((i + 1)); printf 'Inst paquet%s (1.0 deb) []\n' "$i"; done
             printf '%s upgraded, 0 newly installed.\n' "$i" ;;
    *) exit 127 ;;
esac
FAUX_OUTIL
chmod 755 "$FAUX/faux-outil"
for nom in sshd ufw fail2ban-client getent apt-get; do ln -s faux-outil "$FAUX/$nom"; done
# faux <VAR=valeur>... — le bilan, sur les faux outils.
faux() { lancer env "PATH=$FAUX:$PATH" JOURNAL="$F_JOURNAL" "$@" bash "$CIBLE"; }

titre "1. Aide et refus d'usage"
lancer bash "$CIBLE" --help
assert_code 0 "$CODE" "--help sort en 0"
for motif in "PASS, WARNING, FAIL ou INFO" "sshd -T" "ufw" "fail2ban" "UID 0" "apt-get -s upgrade" "BORNE" "Codes de retour" "demandent root" "sans root"; do assert_contient "$(sortie)" "$motif" "--help documente « $motif »"; done
lancer bash "$CIBLE" --nawak
assert_code 2 "$CODE" "une option inconnue sort en 2"
assert_contient "$(erreur)" "Option inconnue : --nawak" "le refus nomme l'option"
assert_egal "" "$(sortie)" "aucun bilan n'est produit avant le refus"
for cas in BORNE=0 BORNE=abc BORNE=-1; do lancer env "$cas" bash "$CIBLE"; assert_code 2 "$CODE" "$cas : refus en 2"; done
assert_contient "$(erreur)" "BORNE" "le refus d'une BORNE invalide nomme la variable"

titre "2. Machine saine — cinq PASS, code 0"
faux
assert_code 0 "$CODE" "une machine saine sort en 0"
for controle in SSH pare-feu fail2ban "comptes à UID 0" "mises à jour"; do assert_contient "$(sortie)" "PASS  $controle — " "« $controle » donne PASS"; done
assert_contient "$(sortie)" "Bilan : 5 PASS, 0 WARNING, 0 FAIL, 0 INFO" "le bilan final compte chaque statut"
for motif in "sshd -T" "ufw status verbose" "fail2ban-client status" "getent passwd" "apt-get -s upgrade"; do assert_contient "$(cat "$F_JOURNAL")" "$motif" "« $motif » est interrogé"; done
assert_absent "$(cat "$F_JOURNAL")" "apt-get update" "aucun « apt-get update » n'est lancé"
assert_absent "$(erreur)" "Échec (code" "le trap ERR n'ajoute aucune ligne"

titre "3. SSH — les deux réglages sont exigés"
for cas in "SSH_MDP=yes" "SSH_ROOT=prohibit-password" "SSH_ROOT=yes"; do
    faux "$cas"
    assert_code 1 "$CODE" "$cas : le bilan sort en 1"
    assert_contient "$(sortie)" "FAIL  SSH — " "$cas : SSH donne FAIL"
done
faux FAUX_ECHEC=255
assert_code 0 "$CODE" "un « sshd -T » en échec n'arrête pas le bilan"
assert_contient "$(sortie)" "INFO  SSH — " "un sshd muet donne INFO, jamais PASS"
assert_contient "$(detail_de SSH)" "non vérifiable" "le détail dit le contrôle non vérifiable"
faux SSH_MUET=oui
assert_code 0 "$CODE" "un « sshd -T » réussi mais vide ne sort pas en 1"
assert_contient "$(sortie)" "INFO  SSH — " "un « sshd -T » réussi mais vide donne INFO, jamais FAIL"

titre "4. Pare-feu — ufw actif, entrée restrictive, locale C"
for cas in "UFW_ACTIF=non" "UFW_ENTREE=allow"; do
    faux "$cas"
    assert_code 1 "$CODE" "$cas : le bilan sort en 1"
    assert_contient "$(sortie)" "FAIL  pare-feu — " "$cas : pare-feu donne FAIL"
done
assert_contient "$(detail_de pare-feu)" "deny" "le détail nomme la politique attendue"
faux UFW_ENTREE=reject
assert_code 0 "$CODE" "« reject (incoming) » est restrictif : le bilan sort en 0"
assert_contient "$(sortie)" "PASS  pare-feu — " "« reject (incoming) » donne PASS"
# Le faux ufw ne parle anglais que sous LC_ALL=C : sans ce forçage, ce cas rendrait FAIL.
assert_contient "$(env LC_ALL=C.UTF-8 PATH="$FAUX:$PATH" JOURNAL="$F_JOURNAL" ufw status verbose)" "État : actif" "garde : hors LC_ALL=C, le faux ufw répond en français"
faux
assert_code 0 "$CODE" "le script interroge en LC_ALL=C : le bilan sort en 0"
assert_contient "$(sortie)" "PASS  pare-feu — " "un ufw qui n'anglaisit que sous LC_ALL=C donne PASS"

titre "5. fail2ban — le service et la prison sshd"
faux F2B_PRISONS=nginx
assert_code 0 "$CODE" "une prison sshd absente ne sort pas en 1"
assert_contient "$(sortie)" "WARNING  fail2ban — " "un fail2ban actif sans prison sshd donne WARNING"
assert_contient "$(sortie)" "Bilan : 4 PASS, 1 WARNING, 0 FAIL, 0 INFO" "le WARNING est compté dans le bilan"
faux FAUX_ECHEC=1
assert_contient "$(sortie)" "WARNING  fail2ban — " "un service injoignable donne WARNING"

titre "6. Comptes à UID 0"
faux COMPTE_UID0=oui
assert_code 1 "$CODE" "un compte à UID 0 autre que root sort en 1"
assert_contient "$(sortie)" "FAIL  comptes à UID 0 — " "un compte à UID 0 autre que root donne FAIL"
assert_contient "$(detail_de "comptes à UID 0")" "fauxroot" "le détail nomme le compte fautif"
faux GETENT_MUET=oui
assert_code 0 "$CODE" "un « getent passwd » réussi mais vide ne sort pas en 1"
assert_contient "$(sortie)" "INFO  comptes à UID 0 — " "un « getent passwd » muet donne INFO, jamais PASS"

titre "7. Mises à jour en attente"
faux APT_MAJ=3
assert_code 0 "$CODE" "des mises à jour en attente ne sortent pas en 1"
assert_contient "$(sortie)" "WARNING  mises à jour — " "des mises à jour en attente donnent WARNING"
assert_egal "3 mise(s) à jour en attente" "$(detail_de "mises à jour")" "le détail donne leur nombre"

titre "8. Les cinq outils absents — jamais PASS, jamais FAIL"
SANS="$REP_TMP/sans-outils"
sans_outil "$SANS" sshd ufw fail2ban-client getent apt-get
manquants=""
for b in sshd ufw fail2ban-client getent apt-get; do
    if PATH="$SANS" command -v "$b" >/dev/null 2>&1; then manquants="$manquants $b"; fi
done
assert_egal "" "$manquants" "garde : les cinq outils sont masqués, un par un"
lancer env "PATH=$SANS" bash "$CIBLE"
assert_code 0 "$CODE" "aucun outil absent ne produit de FAIL"
assert_egal "0" "$(grep -c '^PASS  ' "$F_OUT" || true)" "aucun contrôle ne rend PASS sans son outil"
for controle in SSH "comptes à UID 0" "mises à jour"; do assert_contient "$(sortie)" "INFO  $controle — " "« $controle » sans son outil donne INFO"; done
for controle in pare-feu fail2ban; do assert_contient "$(sortie)" "WARNING  $controle — " "« $controle » sans son outil donne WARNING"; done
assert_contient "$(sortie)" "Bilan : 0 PASS, 2 WARNING, 0 FAIL, 3 INFO" "le bilan compte les INFO et les WARNING"

titre "9. La borne de temps"
DEBUT="$SECONDS"; faux BORNE=1 SSHD_DORT=20; DUREE=$(( SECONDS - DEBUT ))
assert_code 0 "$CODE" "un sshd qui ne répond pas ne fait pas échouer le bilan"
assert_contient "$(sortie)" "INFO  SSH — " "un sshd qui dépasse la borne donne INFO"
if [ "$DUREE" -lt 10 ]; then ok "l'interrogation est bornée — $DUREE s, contre 20 s pour le faux sshd"
else ko "l'interrogation est bornée" "le bilan a duré $DUREE s : la borne n'a pas mordu"; fi

titre "10. La machine réelle, et la lecture seule"
touch "$REP_TMP/temoin"
AVANT="$(cksum /etc/passwd /etc/group 2>/dev/null | cksum)"
lancer bash "$CIBLE"
NB_FAIL="$(grep -c '^FAIL  ' "$F_OUT" || true)"
ATTENDU=0; [ "$NB_FAIL" -eq 0 ] || ATTENDU=1
assert_code "$ATTENDU" "$CODE" "le code suit les $NB_FAIL FAIL de la machine réelle"
assert_egal "$NB_FAIL" "$(sed -n 's/^Bilan : .*, \([0-9]*\) FAIL,.*$/\1/p' "$F_OUT")" "le bilan compte les FAIL comme les lignes"
for controle in SSH pare-feu fail2ban "comptes à UID 0" "mises à jour"; do assert_contient "$(sortie)" "$controle — " "« $controle » rend un verdict sur la machine réelle"; done
assert_egal "$AVANT" "$(cksum /etc/passwd /etc/group 2>/dev/null | cksum)" "les fichiers de comptes sont inchangés"
ECRITURES="$(find /etc /home /root -newer "$REP_TMP/temoin" -not -path "$LOG_DIR/*" 2>/dev/null || true)"
assert_egal "" "$ECRITURES" "aucun fichier n'est modifié hors du répertoire de journaux"

bilan "TASK-043 / security-check.sh"
