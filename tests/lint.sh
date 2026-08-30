#!/usr/bin/env bash
# tests/lint.sh — analyse statique de tous les scripts du dépôt.
#
# Deux contrôles, de portées très différentes :
#
#   - bash -n      syntaxe seule. Toujours disponible, ne détecte presque rien
#                  au-delà d'une accolade oubliée.
#   - shellcheck   analyse réelle : variables non quotées, tests fragiles, cd
#                  sans garde. Absent de certaines machines — dans ce cas le
#                  résultat est NON EXÉCUTÉ, jamais PASS.
#
# Les deux tirets ci-dessus ne sont pas décoratifs : un commentaire dont le
# premier mot est « shellcheck » est lu par l'outil comme une directive, et ce
# fichier ne s'analysait plus (SC1073, SC1072). Ne pas les retirer.
#
# Les deux scripts Synology hérités ne sont pas encore au standard du dépôt.
# La tolérance dont ils bénéficient porte sur le STYLE, jamais sur la SYNTAXE :
# un shellcheck en défaut passe en WARN, une erreur de syntaxe reste bloquante.
#
# Sans cette distinction, un de ces fichiers pourrait devenir syntaxiquement
# cassé sans que « 0 erreur » cesse de s'afficher — le contrôle mentirait.

set -Eeuo pipefail

_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_dir/lib/common.sh" ] && [ "$_dir" != "/" ]; do _dir="$(dirname "$_dir")"; done
source "$_dir/lib/common.sh"

# Scripts tolérés hors standard, avec la tâche qui les remettra à niveau.
FICHIERS_HERITES="
Synology/Plex/organize-series.sh
Synology/Plex/update-plex.sh
"

# SC1090 et SC1091 : shellcheck ne peut pas suivre « source "$_dir/lib/common.sh" »,
# dont le chemin n'est connu qu'à l'exécution. C'est le mécanisme même du dépôt,
# décrit dans docs/architecture-technique.md — l'avertissement est sans objet ici.
SHELLCHECK_EXCLUS="SC1090,SC1091"

# -------------------------------------------------------------------
# Aide
# -------------------------------------------------------------------
show_help() {
    cat <<'AIDE'
Usage : tests/lint.sh [options] [fichier...]

Analyse statique des scripts du dépôt. Sans argument, analyse tous les .sh.

Options :
      --strict    Faire échouer aussi sur les scripts hérités.
  -h, --help      Afficher cette aide

Codes de retour :
  0   aucune erreur
  1   au moins une erreur
  2   erreur d'usage
AIDE
}

STRICT="false"
FICHIERS_DEMANDES=()

while [ "${1:-}" != "" ]; do
    case "$1" in
        --strict)  STRICT="true"; shift ;;
        -h|--help) show_help; exit 0 ;;
        -*)        die "Option inconnue : $1" 2 ;;
        *)         FICHIERS_DEMANDES+=("$1"); shift ;;
    esac
done

# -------------------------------------------------------------------
# Collecte des fichiers
# -------------------------------------------------------------------
est_herite() {
    local chemin="$1"
    local herite
    for herite in $FICHIERS_HERITES; do
        if [ "$chemin" = "$herite" ]; then
            return 0
        fi
    done
    return 1
}

# Chemin relatif à la racine du dépôt, pour un affichage lisible.
chemin_relatif() {
    printf '%s\n' "${1#"$SCRIPTS_ROOT"/}"
}

fichiers=()
if [ "${#FICHIERS_DEMANDES[@]}" -gt 0 ]; then
    for f in "${FICHIERS_DEMANDES[@]}"; do
        [ -f "$f" ] || die "Fichier introuvable : $f" 2
        fichiers+=("$f")
    done
else
    while IFS= read -r f; do
        fichiers+=("$f")
    done < <(find "$SCRIPTS_ROOT" -type f -name '*.sh' \
                  -not -path '*/.git/*' -not -path '*/logs/*' | sort)
fi

if [ "${#fichiers[@]}" -eq 0 ]; then
    die "Aucun script à analyser." 1
fi

# -------------------------------------------------------------------
# Analyse
# -------------------------------------------------------------------
SHELLCHECK_DISPONIBLE="false"
if command -v shellcheck >/dev/null 2>&1; then
    SHELLCHECK_DISPONIBLE="true"
fi

info "Analyse statique — ${#fichiers[@]} fichier(s)"

erreurs=0
avertissements=0

for fichier in "${fichiers[@]}"; do
    relatif="$(chemin_relatif "$fichier")"
    herite="false"
    if est_herite "$relatif" && [ "$STRICT" = "false" ]; then
        herite="true"
    fi

    probleme=""
    nature=""

    if ! sortie="$(bash -n "$fichier" 2>&1)"; then
        probleme="syntaxe : $sortie"
        nature="syntaxe"
    elif [ "$SHELLCHECK_DISPONIBLE" = "true" ]; then
        if ! sortie="$(shellcheck --exclude="$SHELLCHECK_EXCLUS" "$fichier" 2>&1)"; then
            probleme="$sortie"
            nature="style"
        fi
    fi

    # La tolérance des scripts hérités ne couvre que le style. Une erreur de
    # syntaxe reste bloquante pour tous : un script qui ne s'analyse plus est
    # cassé, hérité ou non.
    if [ -z "$probleme" ]; then
        success "$relatif"
    elif [ "$herite" = "true" ] && [ "$nature" = "style" ]; then
        warn "$relatif — script hérité, hors standard (non bloquant)"
        printf '%s\n' "$probleme" >&2
        avertissements=$((avertissements + 1))
    else
        error "$relatif"
        printf '%s\n' "$probleme" >&2
        erreurs=$((erreurs + 1))
    fi
done

# -------------------------------------------------------------------
# Bilan
# -------------------------------------------------------------------
if [ "$SHELLCHECK_DISPONIBLE" = "false" ]; then
    warn "shellcheck absent : analyse approfondie NON EXÉCUTÉE (seule la syntaxe a été vérifiée)"
fi

if [ "$erreurs" -gt 0 ]; then
    die "Analyse statique : $erreurs erreur(s) sur ${#fichiers[@]} fichier(s)." 1
fi

if [ "$avertissements" -gt 0 ]; then
    success "Analyse statique : ${#fichiers[@]} fichier(s), 0 erreur, $avertissements averti(s)."
else
    success "Analyse statique : ${#fichiers[@]} fichier(s), 0 erreur."
fi
