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
  ADRESSE    adresse d'écoute, telle que ss la donne, sans son port ;
  PORT       port d'écoute ;
  PROCESSUS  le ou les processus qui détiennent l'écoute, séparés par une
             virgule, un même nom n'étant retenu qu'une fois.

Sont « exposées » les écoutes sur 0.0.0.0, [::] ou *, ainsi que sur toute
adresse qui n'est pas la boucle locale : une adresse d'interface reste
joignable depuis le réseau. Sont « locales » celles sur 127.0.0.0/8, [::1] ou
[::ffff:127.0.0.0/8], suffixe de portée (%eth0) mis à part.

Le processus d'une écoute n'est lisible que par root : sans ce privilège, la
colonne affiche « inconnu (root requis) », et « inconnu » si l'écoute n'en a
aucun même en root. Le relevé se termine par un résumé — écoutes relevées,
écoutes exposées, ports exposés distincts — puis par la liste de ces ports.

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
    local reste="$1" noms="" nom
    reste="${reste//users:/}"
    while [ -n "$reste" ]; do
        case "$reste" in *'("'*) ;; *) break ;; esac
        reste="${reste#*(\"}"
        nom="${reste%%\"*}"
        case ",$noms," in *",$nom,"*) ;; *) noms="${noms:+$noms,}$nom" ;; esac
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
    # La portée se juge hors du suffixe %eth0 que ss accole aux adresses à zone.
    case "${adresse%%\%*}" in
        127.*|'[::1]'|'[::ffff:127.'*) portee="local" ;;
        *)                             portee="exposé"; exposes+=("$port") ;;
    esac
    printf '%-5s %-7s %-22s %-6s %s\n' "$proto" "$portee" "$adresse" "$port" "$(detenteurs "$reste")"
done <<< "$releve"

if [ "$total" -eq 0 ]; then printf '  aucune écoute\n'; fi
if [ "${#exposes[@]}" -eq 0 ]; then
    liste="aucun"; distincts=0
else
    liste="$(printf '%s\n' "${exposes[@]}" | sort -nu | paste -sd, -)"
    distincts="$(awk -F, '{print NF}' <<< "$liste")"
fi
printf '\nRésumé : %d écoute(s) relevée(s), dont %d exposée(s), sur %d port(s) exposé(s) distinct(s).\n' \
    "$total" "${#exposes[@]}" "$distincts"
printf 'Ports exposés : %s\n' "$liste"
exit 0
