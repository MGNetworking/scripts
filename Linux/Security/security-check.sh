#!/usr/bin/env bash
set -Eeuo pipefail
# security-check.sh — bilan de sécurité en LECTURE SEULE (TASK-043) : SSH,
# pare-feu, fail2ban, comptes à UID 0, mises à jour. Il constate, il ne répare rien.

_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_dir/lib/common.sh" ] && [ "$_dir" != "/" ]; do _dir="$(dirname "$_dir")"; done
source "$_dir/lib/common.sh"

# Borne de chaque commande interrogée, surchargeable ; un entier strictement positif.
BORNE="${BORNE:-10}"
case "$BORNE" in
    ''|*[!0-9]*) die "BORNE doit être un entier positif : « $BORNE »" 2 ;;
    0)           die "BORNE doit être supérieur à 0 : « $BORNE »" 2 ;;
esac

usage() {
    cat <<'AIDE'
Usage : security-check.sh [-h|--help]

Bilan de sécurité en lecture seule, une ligne par contrôle :
« STATUT  contrôle — détail », STATUT valant PASS, WARNING, FAIL ou INFO.

  SSH              sshd -T : PasswordAuthentication no, PermitRootLogin no ;
  pare-feu         ufw actif, « deny » ou « reject » en entrée ;
  fail2ban         service actif, prison sshd présente ;
  comptes à UID 0  aucun compte à UID 0 autre que root ;
  mises à jour     paquets en attente, d'après « apt-get -s upgrade ».

« sshd -T », « ufw status » et « fail2ban-client status » demandent root.
Ces trois commandes ne répondent pas sans root : leur contrôle sort alors en
INFO « non vérifiable » ; un outil absent ou une commande muette n'est jamais
PASS ni FAIL — ufw et fail2ban valent alors WARNING, les autres INFO. Chaque
commande est bornée (BORNE, 10 s), et apt-get est appelé en simulation seule.
Codes de retour : 0 aucun FAIL ; 1 au moins un FAIL ; 2 option inconnue ou
BORNE invalide.
AIDE
}

while [ "${1:-}" != "" ]; do
    case "$1" in
        -h|--help) usage; exit 0 ;;
        *)         die "Option inconnue : $1" 2 ;;
    esac
done

NB_PASS=0; NB_WARNING=0; NB_FAIL=0; NB_INFO=0; SORTIE=""
RACINE="non"; if [ "$(id -u)" -eq 0 ]; then RACINE="oui"; fi

# ligne <statut> <contrôle> <détail> — un verdict, et son décompte.
ligne() {
    printf '%s  %s — %s\n' "$1" "$2" "$3"
    case "$1" in
        PASS)    NB_PASS=$(( NB_PASS + 1 ))       ;;
        WARNING) NB_WARNING=$(( NB_WARNING + 1 )) ;;
        FAIL)    NB_FAIL=$(( NB_FAIL + 1 ))       ;;
        INFO)    NB_INFO=$(( NB_INFO + 1 ))       ;;
    esac
}

present() { command -v "$1" >/dev/null 2>&1; }

# interroger <commande...> — la commande, bornée et en locale C : « ufw status »
# traduit ses messages, que ce script lit en anglais.
interroger() {
    if present timeout; then LC_ALL=C timeout "$BORNE" "$@"; else LC_ALL=C "$@"; fi
}

# relever <contrôle> <statut si indisponible> <root|-> <commande...> — interroge
# la commande et met sa réponse dans SORTIE. Un binaire absent, une commande qui
# demande root quand on ne l'est pas, un échec ou une réponse vide rendent le
# contrôle « non vérifiable » et la fonction faux : rien de tout cela n'est un
# verdict.
relever() {
    local controle="$1" statut="$2" root="$3"; shift 3
    local binaire="$1" code=0
    if ! present "$binaire"; then ligne "$statut" "$controle" "$binaire absent — non vérifiable"; return 1; fi
    if [ "$root" = "root" ] && [ "$RACINE" != "oui" ]; then ligne INFO "$controle" "« $* » demande root — non vérifiable"; return 1; fi
    SORTIE="$(interroger "$@" 2>/dev/null)" || code=$?
    if [ "$code" -ne 0 ]; then
        ligne "$statut" "$controle" "« $* » injoignable (code $code) — non vérifiable"; return 1
    elif [ -z "$SORTIE" ]; then
        ligne INFO "$controle" "« $* » n'a rien répondu — non vérifiable"; return 1
    fi
    return 0
}

controle_ssh() {
    relever SSH INFO - sshd -T || return 0
    local mdp racine
    mdp="$(awk 'tolower($1) == "passwordauthentication" {print tolower($2)}' <<< "$SORTIE" | tail -n 1)"
    racine="$(awk 'tolower($1) == "permitrootlogin" {print tolower($2)}' <<< "$SORTIE" | tail -n 1)"
    if [ "$mdp" = "no" ] && [ "$racine" = "no" ]; then
        ligne PASS SSH "PasswordAuthentication no, PermitRootLogin no"
    else
        ligne FAIL SSH "PasswordAuthentication ${mdp:-absente}, PermitRootLogin ${racine:-absent} — les deux doivent valoir no"
    fi
}

controle_parefeu() {
    relever pare-feu WARNING root ufw status verbose || return 0
    grep -q "Status: active" <<< "$SORTIE" || { ligne FAIL pare-feu "ufw inactif"; return 0; }
    local politique
    politique="$(sed -n 's/^Default: \([^ ]*\) (incoming).*/\1/p' <<< "$SORTIE" | tail -n 1)"
    case "$politique" in
        deny|reject) ligne PASS pare-feu "ufw actif, entrée en $politique" ;;
        *) ligne FAIL pare-feu "ufw actif, mais l'entrée n'est ni deny ni reject (${politique:-illisible})" ;;
    esac
}

controle_fail2ban() {
    relever fail2ban WARNING root fail2ban-client status || return 0
    # « Jail list :  sshd, nginx » -> « sshd,nginx » : sshd est cherché comme
    # jeton entier, sans quoi « sshd-ddos » passerait pour la prison sshd.
    local liste="${SORTIE#*Jail list:}"
    liste="${liste%%$'\n'*}"
    case ",${liste//[[:space:]]/}," in
        *",sshd,"*) ligne PASS fail2ban "service actif, prison sshd présente" ;;
        *) ligne WARNING fail2ban "service actif, prison sshd absente" ;;
    esac
}

controle_comptes() {
    relever "comptes à UID 0" INFO - getent passwd || return 0
    local intrus
    intrus="$(awk -F: '$1 != "root" && $3 == 0 {print $1}' <<< "$SORTIE" | tr '\n' ' ')"
    if [ -z "$intrus" ]; then ligne PASS "comptes à UID 0" "seul root a l'UID 0"
    else ligne FAIL "comptes à UID 0" "compte(s) à UID 0 autre(s) que root : ${intrus% }"; fi
}

controle_maj() {
    # « -s » simule : rien n'est installé ; « apt-get update » n'est jamais lancé.
    relever "mises à jour" INFO - apt-get -s upgrade || return 0
    local nombre
    nombre="$(awk '/^Inst / {n++} END {print n + 0}' <<< "$SORTIE")"
    if [ "$nombre" -eq 0 ]; then ligne PASS "mises à jour" "aucune mise à jour en attente"
    else ligne WARNING "mises à jour" "$nombre mise(s) à jour en attente"; fi
}

printf 'Bilan de sécurité — lecture seule\n\n'
controle_ssh
controle_parefeu
controle_fail2ban
controle_comptes
controle_maj
printf '\nBilan : %d PASS, %d WARNING, %d FAIL, %d INFO\n' "$NB_PASS" "$NB_WARNING" "$NB_FAIL" "$NB_INFO"

[ "$NB_FAIL" -eq 0 ] || die "Bilan de sécurité : $NB_FAIL contrôle(s) en échec." 1
success "Bilan de sécurité : aucun contrôle en échec."
exit 0
