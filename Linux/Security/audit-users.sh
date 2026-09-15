#!/usr/bin/env bash
set -Eeuo pipefail
# audit-users.sh — audit en lecture seule des comptes (TASK-041) : UID 0, shells
# de connexion, groupes privilégiés, mots de passe vides. Sans privilège requis.

_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_dir/lib/common.sh" ] && [ "$_dir" != "/" ]; do _dir="$(dirname "$_dir")"; done
source "$_dir/lib/common.sh"

# Chemins surchargeables : le fichier de cas y met des fixtures, pas les vrais.
FICHIER_SHADOW="${FICHIER_SHADOW:-/etc/shadow}"
FICHIER_SHELLS="${FICHIER_SHELLS:-/etc/shells}"
GROUPES_PRIVILEGIES=(sudo adm docker)

usage() {
    cat <<'AIDE'
Usage : audit-users.sh [-h|--help]

Audit en lecture seule des comptes, en quatre rubriques :
  1. comptes à UID 0 — tout compte autre que root vaut un [WARN] ;
  2. comptes dotés d'un shell de connexion, un par ligne ;
  3. membres des groupes privilégiés sudo, adm et docker, un par ligne —
     appartenance secondaire comme groupe principal ;
  4. comptes au mot de passe vide dans /etc/shadow — chacun vaut un [WARN].

Un shell est « de connexion » s'il figure dans /etc/shells et n'est ni nologin,
ni false, ni true : sync, shutdown et halt n'en sont donc pas. Les listes vont
sur stdout, les avertissements sur stderr. Rien n'est modifié — ni compte, ni
groupe, ni clé SSH, ni session — et aucun privilège n'est requis : un /etc/shadow
illisible est signalé et l'audit se poursuit. Chemins surchargeables :
FICHIER_SHADOW et FICHIER_SHELLS.

Codes de retour :
  0  audit produit — y compris si des comptes sont signalés ;
  1  getent absent : sans lui, aucun compte ne peut être lu ;
  2  option inconnue.
AIDE
}

while [ "${1:-}" != "" ]; do
    case "$1" in
        -h|--help) usage; exit 0 ;;
        *)         die "Option inconnue : $1" 2 ;;
    esac
done

require_cmd getent

# /etc/shells dit quels shells sont ouverts à la connexion : c'est ce qui écarte
# sync, shutdown et halt. Liste tenue en « :chemin:chemin: », sans tableau.
shells_valides=":"; shells_lus=""
if [ -r "$FICHIER_SHELLS" ]; then
    shells_lus="oui"
    while read -r chemin; do
        case "$chemin" in ''|\#*) continue ;; esac
        shells_valides="$shells_valides$chemin:"
    done < "$FICHIER_SHELLS"
else
    warn "$FICHIER_SHELLS est illisible : les shells de connexion ne sont pas déterminés."
fi

# getent, et jamais /etc/passwd : c'est lui qui interroge les sources réellement
# en service. Une lecture en échec arrête l'audit — un rapport vide se lirait
# sinon comme un rapport sain.
comptes=""
if ! comptes="$(getent passwd)"; then
    die "getent passwd a échoué : aucun compte ne peut être lu." 1
fi

uid0=(); connexion=(); nb_comptes=0
while IFS=: read -r nom _ uid _ _ _ shell; do
    [ -n "$nom" ] || continue
    nb_comptes=$(( nb_comptes + 1 ))
    if [ "$uid" = "0" ]; then uid0+=("$nom"); fi
    case "$shell" in
        ''|*/nologin|*/false|*/true) ;;
        *) case "$shells_valides" in *":$shell:"*) connexion+=("$nom $shell") ;; esac ;;
    esac
done <<< "$comptes"

printf '\n1. Comptes à UID 0\n'
if [ "${#uid0[@]}" -eq 0 ]; then printf '  aucun\n'; else printf '  %s\n' "${uid0[@]}"; fi
for nom in "${uid0[@]}"; do
    if [ "$nom" != "root" ]; then warn "Compte à UID 0 autre que root : $nom"; fi
done

printf '\n2. Comptes à shell de connexion\n'
if [ -z "$shells_lus" ]; then printf '  non vérifié\n'
elif [ "${#connexion[@]}" -eq 0 ]; then printf '  aucun\n'
else printf '  %s\n' "${connexion[@]}"; fi

# Membres d'un groupe privilégié : les appartenances secondaires que getent
# rend, plus les comptes dont c'est le groupe PRINCIPAL — absents de ce champ.
# getent rend 2 pour un groupe inexistant ; tout autre échec est une panne de
# la source de comptes, et se dit comme tel.
membres_de() {
    local groupe="$1" ligne="" code=0 gid="" liste=""
    local -a membres=()
    ligne="$(getent group "$groupe" 2>/dev/null)" || code=$?
    case "$code" in
        2)  printf '  %s : groupe absent\n' "$groupe"; return 0 ;;
        0)  ;;
        *)  warn "getent group $groupe a échoué : la source de comptes est en panne."
            printf '  %s : non vérifié\n' "$groupe"; return 0 ;;
    esac
    gid="${ligne#*:*:}"; gid="${gid%%:*}"
    liste="${ligne##*:}"
    while IFS=: read -r nom _ _ gid_compte _ _ _; do
        [ -n "$nom" ] || continue
        [ "$gid_compte" = "$gid" ] || continue
        case ",$liste," in *",$nom,"*) ;; *) liste="${liste:+$liste,}$nom" ;; esac
    done <<< "$comptes"
    if [ -z "$liste" ]; then printf '  %s : aucun membre\n' "$groupe"; return 0; fi
    IFS=, read -r -a membres <<< "$liste"
    for membre in "${membres[@]}"; do printf '  %s : %s\n' "$groupe" "$membre"; done
}

printf '\n3. Membres des groupes privilégiés\n'
for groupe in "${GROUPES_PRIVILEGIES[@]}"; do membres_de "$groupe"; done

# Un champ vide est un compte SANS mot de passe ; « ! » et « * » sont des
# comptes verrouillés, qui ne sont pas signalés.
printf '\n4. Comptes au mot de passe vide\n'
vides=(); resume_mdp="non vérifiés — $FICHIER_SHADOW illisible"; shadow=""
if [ ! -r "$FICHIER_SHADOW" ]; then
    warn "$FICHIER_SHADOW est illisible : les mots de passe vides ne sont pas vérifiés."
    printf '  non vérifié\n'
elif ! shadow="$(< "$FICHIER_SHADOW")"; then
    warn "$FICHIER_SHADOW n'a pas pu être lu : les mots de passe vides ne sont pas vérifiés."
    printf '  non vérifié\n'
else
    while IFS=: read -r nom mdp _; do
        if [ -n "$nom" ] && [ -z "$mdp" ]; then
            vides+=("$nom")
            warn "Compte sans mot de passe : $nom"
        fi
    done <<< "$shadow"
    if [ "${#vides[@]}" -eq 0 ]; then printf '  aucun\n'; else printf '  %s\n' "${vides[@]}"; fi
    resume_mdp="${#vides[@]} sans mot de passe"
fi

info "Audit terminé : $nb_comptes compte(s) lu(s), ${#uid0[@]} à UID 0, ${#connexion[@]} à shell de connexion, $resume_mdp."
exit 0
