#!/usr/bin/env bash
set -Eeuo pipefail
# security-check.sh — bilan de sécurité en LECTURE SEULE (TASK-043) : SSH,
# pare-feu, fail2ban, comptes à UID 0, mises à jour. Il constate, il ne répare rien.

_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_dir/lib/common.sh" ] && [ "$_dir" != "/" ]; do _dir="$(dirname "$_dir")"; done
source "$_dir/lib/common.sh"

# Borne de chaque commande interrogée. Surchargeable pour être éprouvée.
BORNE="${BORNE:-10}"

usage() {
    cat <<'AIDE'
Usage : security-check.sh [-h|--help]

Bilan de sécurité en lecture seule. Une ligne par contrôle, de la forme
« STATUT  contrôle — détail », STATUT valant PASS, WARNING, FAIL ou INFO :

  SSH              sshd -T : PasswordAuthentication no et PermitRootLogin no ;
  pare-feu         ufw actif, « deny » en entrée ;
  fail2ban         service actif, prison sshd présente ;
  comptes à UID 0  aucun compte à UID 0 autre que root ;
  mises à jour     paquets en attente, d'après « apt-get -s upgrade ».

Un ufw ou un fail2ban absent vaut WARNING ; un outil qu'on ne peut interroger
— sshd, getent, apt-get — vaut INFO « non vérifiable », jamais PASS. Chaque
commande est bornée (BORNE, 10 s) et apt-get n'est appelé qu'en simulation,
jamais suivi d'un « update ». Le bilan final compte les quatre statuts.

Codes de retour :  0 aucun FAIL ;  1 au moins un FAIL ;  2 option inconnue.
AIDE
}

while [ "${1:-}" != "" ]; do
    case "$1" in
        -h|--help) usage; exit 0 ;;
        *)         die "Option inconnue : $1" 2 ;;
    esac
done

NB_PASS=0; NB_WARNING=0; NB_FAIL=0; NB_INFO=0

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

# interroger <commande...> — la commande, bornée. Sans l'outil timeout, elle est
# lancée telle quelle : mieux vaut un contrôle non borné que pas de contrôle.
interroger() {
    if present timeout; then timeout "$BORNE" "$@"; else "$@"; fi
}

# outil <binaire> <contrôle> <statut si absent> — vrai si le binaire répond.
# Sinon rend la ligne du contrôle et rend faux : un outil absent n'est jamais un
# PASS ni un FAIL — le contrôle était possible, il a manqué son objet.
outil() {
    if present "$1"; then return 0; fi
    ligne "$3" "$2" "$1 absent — non vérifiable"
    return 1
}

controle_ssh() {
    outil sshd SSH INFO || return 0
    local config="" code=0 mdp racine
    config="$(interroger sshd -T 2>/dev/null)" || code=$?
    if [ "$code" -ne 0 ]; then ligne INFO SSH "« sshd -T » a échoué (code $code) — non vérifiable"; return 0; fi
    mdp="$(awk 'tolower($1) == "passwordauthentication" {print tolower($2)}' <<< "$config" | tail -n 1)"
    racine="$(awk 'tolower($1) == "permitrootlogin" {print tolower($2)}' <<< "$config" | tail -n 1)"
    if [ "$mdp" = "no" ] && [ "$racine" = "no" ]; then
        ligne PASS SSH "PasswordAuthentication no, PermitRootLogin no"
    else
        ligne FAIL SSH "PasswordAuthentication ${mdp:-absente}, PermitRootLogin ${racine:-absent} — les deux doivent valoir no"
    fi
}

controle_parefeu() {
    outil ufw pare-feu WARNING || return 0
    local etat="" code=0
    etat="$(interroger ufw status verbose 2>/dev/null)" || code=$?
    if [ "$code" -ne 0 ]; then ligne INFO pare-feu "« ufw status verbose » a échoué (code $code) — non vérifiable"; return 0; fi
    case "$etat" in
        *"Status: active"*) ;;
        *) ligne FAIL pare-feu "ufw inactif"; return 0 ;;
    esac
    case "$etat" in
        *"deny (incoming)"*) ligne PASS pare-feu "ufw actif, deny en entrée" ;;
        *) ligne FAIL pare-feu "ufw actif, mais l'entrée n'est pas en deny" ;;
    esac
}

controle_fail2ban() {
    outil fail2ban-client fail2ban WARNING || return 0
    local etat="" code=0 liste=""
    etat="$(interroger fail2ban-client status 2>/dev/null)" || code=$?
    if [ "$code" -ne 0 ]; then ligne WARNING fail2ban "service injoignable (code $code) — fail2ban est-il démarré ?"; return 0; fi
    # « Jail list :  sshd, nginx » -> « sshd,nginx » : sshd est cherché comme
    # jeton entier, sans quoi « sshd-ddos » passerait pour la prison sshd.
    liste="${etat#*Jail list:}"; liste="${liste%%$'\n'*}"
    case ",${liste//[[:space:]]/}," in
        *",sshd,"*) ligne PASS fail2ban "service actif, prison sshd présente" ;;
        *) ligne WARNING fail2ban "service actif, prison sshd absente" ;;
    esac
}

controle_comptes() {
    outil getent "comptes à UID 0" INFO || return 0
    local comptes="" code=0 intrus=()
    comptes="$(interroger getent passwd 2>/dev/null)" || code=$?
    if [ "$code" -ne 0 ]; then ligne INFO "comptes à UID 0" "« getent passwd » a échoué (code $code) — non vérifiable"; return 0; fi
    while IFS=: read -r nom _ uid _; do
        if [ -n "$nom" ] && [ "$uid" = "0" ] && [ "$nom" != "root" ]; then intrus+=("$nom"); fi
    done <<< "$comptes"
    if [ "${#intrus[@]}" -eq 0 ]; then ligne PASS "comptes à UID 0" "seul root a l'UID 0"
    else ligne FAIL "comptes à UID 0" "compte(s) à UID 0 autre(s) que root : ${intrus[*]}"; fi
}

controle_maj() {
    outil apt-get "mises à jour" INFO || return 0
    # « -s » simule : rien n'est installé, rien n'est écrit. « apt-get update »
    # n'est jamais lancé — il écrirait dans /var/lib/apt, et ce script ne
    # modifie rien.
    local simulation="" code=0 nombre=""
    simulation="$(interroger apt-get -s upgrade 2>/dev/null)" || code=$?
    if [ "$code" -ne 0 ]; then ligne INFO "mises à jour" "« apt-get -s upgrade » a échoué (code $code) — non vérifiable"; return 0; fi
    nombre="$(awk '/^Inst / {n++} END {print n + 0}' <<< "$simulation")"
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
