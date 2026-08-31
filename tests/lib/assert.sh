#!/usr/bin/env bash
# tests/lib/assert.sh — assertions minimales du harnais de tests.
#
# Bash pur, aucun framework : bats est absent de la machine de développement et
# ne se justifie pas pour ce volume. Les noms repris ici — titre, ok, ko, saute,
# assert_code, assert_contient — sont ceux déjà employés dans
# tests/acceptance/, afin qu'un fichier de cas se lise de la même façon quel que
# soit son niveau.
#
# Ce fichier est une BIBLIOTHÈQUE, pas un script :
#
#   - il se charge par « source » et ne s'exécute jamais seul ;
#   - il ne pose ni « set -Eeuo pipefail » ni trap : les deux s'appliqueraient
#     au shell appelant sans qu'il les ait demandés ;
#   - il ne redéfinit rien de ce que lib/common.sh fournit — info, warn, error,
#     success et die viennent de là, et de nulle part ailleurs.
#
# ATTENTION au nom de ce répertoire. La résolution en trois lignes des scripts
# du dépôt cherche « <candidat>/lib/common.sh » en remontant l'arborescence :
# depuis tests/, le premier candidat testé est donc « tests/lib/common.sh ».
# Tant que ce fichier n'existe pas, la remontée se poursuit jusqu'à la racine et
# tout va bien. **Ne jamais créer tests/lib/common.sh** : tous les scripts de
# tests/ chargeraient ce fichier-là au lieu du socle du dépôt.
#
# Usage :
#
#   source "$SCRIPTS_ROOT/tests/lib/assert.sh"
#
#   titre "1. Journalisation"
#   assert_code 1 "$CODE" "die sort en 1 par défaut"
#   assert_contient "$ERREUR" "[ERROR] message" "die préfixe son message"
#   saute "cas systemd" "le conteneur n'a pas systemd"
#   bilan "lib/common.sh"
#
# « bilan » applique le modèle de tests/README.md §5 et sort avec le code qui
# convient : 1 si un cas est en défaut, 3 si aucun n'a réussi, 4 si des cas
# n'étaient pas applicables ici, 0 sinon. L'ordre de ces trois tests n'est pas
# décoratif — voir le commentaire qui les accompagne.

# --- Garde contre un double chargement ------------------------------------
if [ -n "${_ASSERT_SH_CHARGE:-}" ]; then
    return 0
fi
_ASSERT_SH_CHARGE=1

# --- Socle -----------------------------------------------------------------
# Résolution identique à celle des scripts du dépôt, avec un nom de variable
# distinct : « _dir » appartient à l'appelant, l'écraser depuis une
# bibliothèque serait un effet de bord. Si common.sh est déjà chargé, sa propre
# garde fait de ce « source » une opération nulle.
_dir_assert="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_dir_assert/lib/common.sh" ] && [ "$_dir_assert" != "/" ]; do _dir_assert="$(dirname "$_dir_assert")"; done
# shellcheck source=/dev/null
source "$_dir_assert/lib/common.sh"
unset _dir_assert

# --- Compteurs -------------------------------------------------------------
# Trois compteurs, et trois seulement : réussites, échecs, non exécutés. Un cas
# qui n'a pas pu tourner n'est jamais compté comme réussi.
reussites=0
echecs=0
non_executes=0

# --- Verdicts élémentaires -------------------------------------------------
titre() { info "--- $* ---"; }

ok() {
    success "$1"
    reussites=$((reussites + 1))
}

# ko <libellé> [détail]
ko() {
    error "ÉCHEC : $1"
    if [ -n "${2:-}" ]; then
        printf '        %s\n' "$2" >&2
    fi
    echecs=$((echecs + 1))
}

# saute <libellé> [raison]
saute() {
    warn "NON EXÉCUTÉ : $1${2:+ — $2}"
    non_executes=$((non_executes + 1))
}

# --- Assertions ------------------------------------------------------------

# assert_code <attendu> <obtenu> <libellé>
# Comparaison de chaînes et non d'entiers : un code de retour illisible doit
# produire un échec de test, jamais une erreur d'arithmétique du harnais.
assert_code() {
    local attendu="$1" obtenu="$2" libelle="$3"
    if [ "$obtenu" = "$attendu" ]; then
        ok "$libelle — code $obtenu"
    else
        ko "$libelle" "code attendu $attendu, obtenu $obtenu"
    fi
}

# assert_code_non_nul <obtenu> <libellé>
# Pour les critères qui exigent « un code non nul » sans en fixer la valeur.
assert_code_non_nul() {
    local obtenu="$1" libelle="$2"
    if [ "$obtenu" != "0" ]; then
        ok "$libelle — code $obtenu"
    else
        ko "$libelle" "code non nul attendu, obtenu 0"
    fi
}

# assert_egal <attendu> <obtenu> <libellé>
assert_egal() {
    local attendu="$1" obtenu="$2" libelle="$3"
    if [ "$obtenu" = "$attendu" ]; then
        ok "$libelle"
    else
        ko "$libelle" "attendu « $attendu », obtenu « $obtenu »"
    fi
}

# assert_non_vide <valeur> <libellé>
assert_non_vide() {
    local valeur="$1" libelle="$2"
    if [ -n "$valeur" ]; then
        ok "$libelle — « $valeur »"
    else
        ko "$libelle" "valeur vide"
    fi
}

# contient <texte> <motif> — recherche de sous-chaîne LITTÉRALE.
#
# Deux pièges évités ici, et c'est pourquoi cette forme est préférée à un grep :
#
#   - « printf … | grep -q » est un tube. grep -q sort dès la première
#     correspondance ; printf peut alors recevoir SIGPIPE, et « pipefail »
#     ferait échouer le tube alors même que le motif a été trouvé ;
#   - dans « [[ chaîne == motif ]] », les portions du motif entre guillemets
#     sont littérales. « $motif » l'est donc entièrement, ce qui permet d'y
#     chercher les crochets des messages du dépôt — [INFO], [o/N] — qu'un
#     motif de glob ou une expression régulière interpréteraient.
contient() {
    [[ "$1" == *"$2"* ]]
}

# assert_contient <texte> <motif> <libellé>
assert_contient() {
    local texte="$1" motif="$2" libelle="$3"
    if contient "$texte" "$motif"; then
        ok "$libelle"
    else
        ko "$libelle" "motif absent : « $motif »"
    fi
}

# assert_absent <texte> <motif> <libellé>
assert_absent() {
    local texte="$1" motif="$2" libelle="$3"
    if contient "$texte" "$motif"; then
        ko "$libelle" "motif présent alors qu'il ne devrait pas : « $motif »"
    else
        ok "$libelle"
    fi
}

# --- Bilan -----------------------------------------------------------------

# bilan <étiquette>
# Traduit les trois compteurs en code de retour, selon tests/README.md §2 et §5.
# S'appelle en dernière instruction du fichier de cas : les branches 1, 3 et 4
# sortent, la branche nominale se contente de rendre la main — le fichier se
# termine alors sur le succès de « success », donc en 0.
bilan() {
    local etiquette="$1"

    info "Bilan $etiquette : $reussites vérification(s) réussie(s), $echecs échec(s), $non_executes NON EXÉCUTÉ(s)"

    if [ "$echecs" -gt 0 ]; then
        die "$etiquette : $echecs cas en défaut." 1
    fi

    # Testé AVANT le cas des non exécutés : sans cet ordre, une suite
    # intégralement sautée sortirait en 4 — réussite partielle — alors qu'elle
    # n'aurait rien prouvé. Le 4 exige au moins une réussite.
    if [ "$reussites" -eq 0 ]; then
        warn "$etiquette : aucune vérification n'a pu être exécutée — rien n'est prouvé."
        exit 3
    fi

    if [ "$non_executes" -gt 0 ]; then
        warn "$etiquette : $non_executes vérification(s) NON EXÉCUTÉE(s) — les cas correspondants ne sont pas prouvés."
        exit 4
    fi

    success "$etiquette : tous les cas vérifiés ($reussites vérifications)."
}
