#!/usr/bin/env bash
set -Eeuo pipefail
# audit-users.sh — audit en lecture seule des comptes de la machine (TASK-041) :
# UID 0, shells de connexion, groupes privilégiés, mots de passe vides.
# Ne modifie rien, ne réclame aucun privilège. Invocation : audit-users.sh [--help]

_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_dir/lib/common.sh" ] && [ "$_dir" != "/" ]; do _dir="$(dirname "$_dir")"; done
source "$_dir/lib/common.sh"

# Chemin de /etc/shadow, surchargeable : le fichier de cas y met une fixture
# plutôt que de toucher au vrai fichier.
FICHIER_SHADOW="${FICHIER_SHADOW:-/etc/shadow}"
GROUPES_PRIVILEGIES=(sudo adm docker)

usage() {
    cat <<'AIDE'
Usage : audit-users.sh [-h|--help]

Audit en lecture seule des comptes, en quatre rubriques :
  1. comptes à UID 0 — tout compte autre que root vaut un [WARN] ;
  2. comptes dotés d'un shell de connexion, un par ligne ;
  3. membres des groupes privilégiés sudo, adm et docker, un par ligne ;
  4. comptes au mot de passe vide dans /etc/shadow — chacun vaut un [WARN].

Un shell est « de connexion » s'il n'est ni vide, ni nologin, ni false, ni true.
Les listes vont sur stdout, les avertissements sur stderr.

Ce que ce script ne fait pas : modifier, créer, verrouiller ou supprimer un
compte ou un groupe ; toucher aux clés SSH ou aux sessions ouvertes. Aucun
privilège n'est requis : si /etc/shadow est illisible, il le dit et poursuit.
Chemin de /etc/shadow surchargeable par la variable FICHIER_SHADOW.

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

# getent, et jamais /etc/passwd : c'est lui qui interroge les sources de comptes
# réellement en service. Une lecture en échec arrête l'audit : sans comptes, il
# n'y a rien à auditer, et un rapport vide se lirait comme un rapport sain.
comptes=""
if ! comptes="$(getent passwd)"; then
    die "getent passwd a échoué : aucun compte ne peut être lu." 1
fi

uid0=(); shells=(); nb_comptes=0
while IFS=: read -r nom _ uid _ _ _ shell; do
    [ -n "$nom" ] || continue
    nb_comptes=$(( nb_comptes + 1 ))
    if [ "$uid" = "0" ]; then uid0+=("$nom"); fi
    case "$shell" in
        ''|*/nologin|*/false|*/true) ;;
        *) shells+=("$nom $shell") ;;
    esac
done <<< "$comptes"

printf '\n1. Comptes à UID 0\n'
if [ "${#uid0[@]}" -eq 0 ]; then printf '  aucun\n'; else printf '  %s\n' "${uid0[@]}"; fi
for nom in "${uid0[@]}"; do
    if [ "$nom" != "root" ]; then warn "Compte à UID 0 autre que root : $nom"; fi
done

printf '\n2. Comptes à shell de connexion\n'
if [ "${#shells[@]}" -eq 0 ]; then printf '  aucun\n'; else printf '  %s\n' "${shells[@]}"; fi

# Le champ des membres de getent group ne liste que les appartenances
# SECONDAIRES : un compte dont c'est le groupe principal n'y figure pas.
printf '\n3. Membres des groupes privilégiés\n'
for groupe in "${GROUPES_PRIVILEGIES[@]}"; do
    ligne=""
    if ! ligne="$(getent group "$groupe" 2>/dev/null)"; then
        printf '  %s : groupe absent\n' "$groupe"
    elif [ -z "${ligne##*:}" ]; then
        printf '  %s : aucun membre\n' "$groupe"
    else
        IFS=, read -r -a liste <<< "${ligne##*:}"
        for membre in "${liste[@]}"; do printf '  %s : %s\n' "$groupe" "$membre"; done
    fi
done

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

info "Audit terminé : $nb_comptes compte(s) lu(s), ${#uid0[@]} à UID 0, ${#shells[@]} à shell de connexion, $resume_mdp."
exit 0
