#!/usr/bin/env bash
set -Eeuo pipefail

# Active la prison sshd de fail2ban avec les valeurs de la distribution
# (décision 22) : un fichier dans jail.d/, que les mises à jour ne remplacent pas.
_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_dir/lib/common.sh" ] && [ "$_dir" != "/" ]; do _dir="$(dirname "$_dir")"; done
source "$_dir/lib/common.sh"
# Surchargeables : le test travaille dans un bac à sable, sans attente réelle.
JAIL_D="${FAIL2BAN_JAIL_D:-/etc/fail2ban/jail.d}"
ESSAIS="${FAIL2BAN_ESSAIS:-10}"; DELAI="${FAIL2BAN_DELAI:-1}"
PAQUET="fail2ban"; SERVICE="fail2ban"
FICHIER="$JAIL_D/mgnetworking-sshd.conf"; DRY_RUN="false"; OUI="false"
ATTENDU="# Déposé par Linux/Security/configure-fail2ban.sh.
# Valeurs de la distribution : aucune option n'est fixée ici (décision 22).
[sshd]
enabled = true"

usage() {
    cat <<'EOF'
configure-fail2ban.sh — active la prison sshd de fail2ban, valeurs de la distribution.

Usage : configure-fail2ban.sh [options]

  --dry-run        affiche l'état et les actions prévues, sans rien modifier
  -y, --yes        ne pose aucune question (obligatoire hors terminal)
  -h, --help       affiche cette aide

Installe fail2ban par apt-get s'il manque ; déjà présent, rien n'est réinstallé.
Dépose <jail.d>/mgnetworking-sshd.conf — [sshd], enabled = true — sans jamais
toucher jail.conf ni jail.local : aucune valeur n'y est fixée, ce sont celles de la
distribution (décision 22). Fichier identique, rien n'est réécrit. Le service n'est
activé et redémarré que si quelque chose a changé, puis le démon est attendu et
« fail2ban-client status sshd » vérifie que la prison est chargée.

Codes : 0 appliqué, conforme ou --dry-run ; 1 root, distribution, installation,
dépôt, activation, redémarrage, démon injoignable, vérification en défaut ou
confirmation refusée ; 2 option ou valeur mal formée.
EOF
}
# Le paquet : dpkg-query seul en juge — « command -v » ne dit pas qui a posé le binaire.
installe() { dpkg-query -W -f='${Status}' "$PAQUET" 2>/dev/null | grep -q "ok installed"; }

# Le fichier déposé ne dit rien de l'état réel : seul le démon prouve la prison.
# Il n'ouvre son socket qu'après le redémarrage — « status » le devancerait — et
# « ping », qui ne dépend d'aucune prison, est la sonde qui ne le fasse pas.
verifier() {
    local essai=0 etat
    until fail2ban-client ping >/dev/null 2>&1; do
        essai=$((essai + 1))
        [ "$essai" -lt "$ESSAIS" ] || die "fail2ban est injoignable : « fail2ban-client ping » muet après $ESSAIS essais." 1
        sleep "$DELAI"
    done
    etat="$(fail2ban-client status sshd 2>&1)" \
        || die "« fail2ban-client status sshd » échoue : la prison n'est pas chargée. fail2ban dit : $etat" 1
}
# Décision 45 : un ASSUME_YES hérité du parent ne confirme pas ce script.
export ASSUME_YES="false"
while [ "${1:-}" != "" ]; do
    case "$1" in
        --dry-run) DRY_RUN="true"; shift ;;
        -y|--yes)  export ASSUME_YES="true"; OUI="true"; shift ;;
        -h|--help) usage; exit 0 ;;
        *) die "Option inconnue : $1" 2 ;;
    esac
done

if [ "$DRY_RUN" != "true" ]; then
    require_root; require_os debian ubuntu; require_cmd apt-get dpkg-query systemctl
fi
PAQUET_PRESENT="non"; installe && PAQUET_PRESENT="oui"
# Sans le client, « prison non chargée » désignerait un binaire absent.
if [ "$DRY_RUN" != "true" ] && [ "$PAQUET_PRESENT" = "oui" ]; then require_cmd fail2ban-client; fi
CONFORME="non"; [ "$(cat "$FICHIER" 2>/dev/null || true)" != "$ATTENDU" ] || CONFORME="oui"
ENABLE="$(systemctl is-enabled "$SERVICE" 2>/dev/null || true)"
ACTIF="$(systemctl is-active "$SERVICE" 2>/dev/null || true)"
A_INSTALLER="non"; [ "$PAQUET_PRESENT" = "oui" ] || A_INSTALLER="oui"
A_DEPOSER="non";   [ "$CONFORME" = "oui" ]       || A_DEPOSER="oui"
A_ACTIVER="non";   [ "$ENABLE" = "enabled" ]     || A_ACTIVER="oui"
# Un « enable » seul ne charge aucune prison : redémarrer aussi quand le service
# vient d'être activé, sans quoi un « enable » raté au passage précédent laisse
# un fichier conforme que plus rien ne vient charger.
A_REDEMARRER="non"
if [ "$A_INSTALLER" = "oui" ] || [ "$A_DEPOSER" = "oui" ] \
    || [ "$A_ACTIVER" = "oui" ] || [ "$ACTIF" != "active" ]; then
    A_REDEMARRER="oui"
fi
A_FAIRE="non"; [ "$A_INSTALLER$A_DEPOSER$A_ACTIVER$A_REDEMARRER" = "nonnonnonnon" ] || A_FAIRE="oui"
ETAT_PAQUET="absent, à installer par apt-get"; [ "$PAQUET_PRESENT" = "oui" ] && ETAT_PAQUET="installé"
ETAT_FICHIER="absent, à déposer"; [ -e "$FICHIER" ] && ETAT_FICHIER="présent, à remplacer"
[ "$CONFORME" = "oui" ] && ETAT_FICHIER="déjà conforme"
{
    printf '\nÉtat actuel\n'
    printf '  paquet %s : %s\n' "$PAQUET" "$ETAT_PAQUET"
    printf '  %s : %s\n' "$FICHIER" "$ETAT_FICHIER"
    printf '  service %s : %s, %s\n' "$SERVICE" "${ENABLE:-inconnu}" "${ACTIF:-inconnu}"
    printf '\nContenu prévu de %s\n' "$FICHIER"
    printf '%s\n' "$ATTENDU" | sed 's/^/  /'
    printf '\nActions prévues\n'
    if [ "$A_FAIRE" = "non" ]; then printf '  aucune modification, puis vérification de la prison\n'
    else
        [ "$A_INSTALLER" = "non" ]  || printf '  apt-get update ; apt-get install -y %s\n' "$PAQUET"
        [ "$A_DEPOSER" = "non" ]    || printf '  dépôt en 0644 par temporaire puis mv\n'
        [ "$A_ACTIVER" = "non" ]    || printf '  systemctl enable %s\n' "$SERVICE"
        [ "$A_REDEMARRER" = "non" ] || printf '  systemctl restart %s\n' "$SERVICE"
        printf '  attente du démon ; fail2ban-client status sshd\n'
    fi
} >&2
if [ "$DRY_RUN" = "true" ]; then info "[dry-run] rien n'a été exécuté ni modifié."; exit 0; fi
if [ "$A_FAIRE" = "non" ]; then
    verifier
    success "fail2ban est déjà conforme : rien n'a été installé, déposé, activé ni redémarré."
    exit 0
fi

[ -t 0 ] || [ "$OUI" = "true" ] \
    || die "Changement à appliquer, et aucun terminal n'est disponible. Relancer avec --yes." 1
confirm "Appliquer ces changements à fail2ban ?" || die "Configuration abandonnée." 1

if [ "$A_INSTALLER" = "oui" ]; then
    info "fail2ban absent : installation par apt-get."
    run_logged apt-get update || die "« apt-get update » a échoué : rien n'a été installé." 1
    run_logged apt-get install -y "$PAQUET" || die "« apt-get install -y $PAQUET » a échoué : rien n'a été installé." 1
    installe || die "fail2ban reste absent après l'installation : rien n'a été déposé ni activé." 1
    require_cmd fail2ban-client
fi

if [ "$A_DEPOSER" = "oui" ]; then
    [ -d "$JAIL_D" ] || install -d -m 0755 "$JAIL_D"
    TMP=""
    nettoyer() { [ -z "$TMP" ] || rm -f "$TMP"; }
    trap nettoyer EXIT
    TMP="$(mktemp "$JAIL_D/.mgnetworking-sshd.XXXXXX")"
    printf '%s\n' "$ATTENDU" > "$TMP"
    chmod 0644 "$TMP"
    mv -f "$TMP" "$FICHIER"; TMP=""
    trap - EXIT
    info "Prison sshd déposée : $FICHIER"
fi

if [ "$A_ACTIVER" = "oui" ]; then
    run_logged systemctl enable "$SERVICE" || die "« systemctl enable $SERVICE » a échoué." 1
fi
if [ "$A_REDEMARRER" = "oui" ]; then
    run_logged systemctl restart "$SERVICE" \
        || die "« systemctl restart $SERVICE » a échoué : la prison déposée n'est pas chargée." 1
fi

verifier
success "fail2ban : prison sshd active — $FICHIER (valeurs de la distribution)."
