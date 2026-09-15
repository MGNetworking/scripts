#!/usr/bin/env bash
set -Eeuo pipefail
# audit-ports.sh — audit en lecture seule des ports TCP et UDP en écoute
# (TASK-042). Aucun privilège requis, rien n'est modifié.

_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_dir/lib/common.sh" ] && [ "$_dir" != "/" ]; do _dir="$(dirname "$_dir")"; done
source "$_dir/lib/common.sh"

usage() {
    cat <<'AIDE'
Usage : audit-ports.sh [-h|--help]

Relevé en lecture seule des ports TCP et UDP en écoute, par un unique appel à
« ss -H -tulpn ». Une ligne par écoute, en cinq colonnes :

  PROTO      tcp ou udp ;
  PORTÉE     exposé — l'écoute est joignable depuis le réseau ; local — elle
             ne l'est que depuis la machine ;
  ADRESSE    adresse d'écoute, sans son port ;
  PORT       port d'écoute ;
  PROCESSUS  le ou les processus qui détiennent l'écoute, séparés par une
             virgule.

Sont « exposées » les écoutes sur 0.0.0.0, [::] ou *, ainsi que sur toute
adresse qui n'est pas la boucle locale : une adresse d'interface reste
joignable depuis le réseau. Sont « locales » celles sur 127.0.0.0/8 ou [::1].

Le processus d'une écoute n'est lisible que par root : sans ce privilège, la
colonne affiche « inconnu (root requis) », et « inconnu » si l'écoute n'en a
aucun même en root. Le relevé se termine par un résumé et par la liste des
ports exposés.

Codes de retour :
  0  relevé produit, y compris s'il est vide ;
  1  ss absent ou en échec — aucun relevé ne peut être produit ;
  2  option inconnue.
AIDE
}

while [ "${1:-}" != "" ]; do
    case "$1" in
        -h|--help) usage; exit 0 ;;
        *)         die "Option inconnue : $1" 2 ;;
    esac
done

require_cmd ss

# Le noyau ne livre le processus d'une écoute qu'à root : le repli dit pourquoi
# la colonne est vide, ou se tait quand ce n'est pas la raison.
if [ "$(id -u)" -eq 0 ]; then
    PROCESSUS_INCONNU="inconnu"
else
    PROCESSUS_INCONNU="inconnu (root requis)"
fi

if ! releve="$(ss -H -tulpn)"; then
    die "ss a échoué : aucun relevé n'a pu être produit." 1
fi

# users:(("sshd",pid=800,fd=3)) donne « sshd » ; plusieurs détenants, « a,b ».
detenteurs() {
    local reste="$1" noms=""
    reste="${reste//users:/}"
    while [ -n "$reste" ]; do
        case "$reste" in *'("'*) ;; *) break ;; esac
        reste="${reste#*(\"}"
        noms="${noms:+$noms,}${reste%%\"*}"
    done
    printf '%s\n' "${noms:-$PROCESSUS_INCONNU}"
}

total=0; exposes=()

printf '%-5s %-7s %-22s %-6s %s\n' PROTO PORTÉE ADRESSE PORT PROCESSUS
while read -r proto _ _ _ locale _ reste; do
    [ -n "$proto" ] || continue
    total=$(( total + 1 ))
    port="${locale##*:}"
    adresse="${locale%:*}"
    case "$adresse" in
        127.*|'[::1]') portee="local" ;;
        *)             portee="exposé"; exposes+=("$port") ;;
    esac
    printf '%-5s %-7s %-22s %-6s %s\n' "$proto" "$portee" "$adresse" "$port" "$(detenteurs "$reste")"
done <<< "$releve"

if [ "$total" -eq 0 ]; then printf '  aucune écoute\n'; fi
printf '\nRésumé : %d écoute(s) relevée(s), dont %d exposée(s).\n' "$total" "${#exposes[@]}"
if [ "${#exposes[@]}" -eq 0 ]; then
    printf 'Ports exposés : aucun\n'
else
    printf 'Ports exposés : %s\n' "$(printf '%s\n' "${exposes[@]}" | sort -nu | paste -sd, -)"
fi
exit 0
