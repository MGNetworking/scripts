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
#   saute "cas non exécuté" "la raison, sans qualification"
#   saute_par_nature "cas systemd" "le profil debian n'a pas systemd"
#   saute_indisponible "lint conteneurisé" "le démon Docker ne répond pas"
#   bilan "lib/common.sh"
#
# Trois façons de ne pas exécuter un cas, jamais interchangeables :
#
#   saute               le cas n'a pas tourné, et le harnais n'en dit pas plus.
#                       Libellé neutre — la nature du saut n'a pas été relue ;
#   saute_par_nature    le cas a été relu et jugé hors d'atteinte PAR NATURE ;
#   saute_indisponible  l'ENVIRONNEMENT a manqué — le fichier sort en 3.
#
# « bilan » applique le modèle de tests/README.md §5 et sort avec le code qui
# convient : 1 si un cas est en défaut, 3 si aucun n'a réussi OU si un cas n'a
# pas pu être produit faute d'environnement, 4 s'il reste des cas non exécutés,
# 0 sinon. L'ordre de ces quatre tests n'est pas décoratif — voir le commentaire
# qui les accompagne.

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
# Trois compteurs de verdict — réussites, échecs, non exécutés. Un cas qui n'a
# pas pu tourner n'est jamais compté comme réussi.
#
# Le compteur des non exécutés se scinde en deux NATURES, et c'est tout l'objet
# de TASK-013 :
#
#   non_applicables    le cas est hors d'atteinte PAR NATURE — le profil
#                      « debian » n'a pas systemd et ne l'aura jamais. Limite
#                      assumée de l'environnement de test : ce qui a été prouvé
#                      le reste, le fichier sort en 4. C'est aussi, faute de
#                      mieux, le compteur des sauts dont la nature n'a pas
#                      encore été relue — « saute » y verse, sans l'affirmer à
#                      l'écran ;
#   indisponibilites   l'ENVIRONNEMENT A MANQUÉ — démon Docker coupé, réseau
#                      absent, outil attendu introuvable. La preuve existe, elle
#                      n'a pas pu être produite : le fichier sort en 3.
#
# « non_executes » demeure le total des deux, sous le même nom et le même sens.
reussites=0
echecs=0
non_executes=0
non_applicables=0
indisponibilites=0

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

# saute <libellé> [raison] — cas NON EXÉCUTÉ, sans qualification affichée.
#
# Libellé NEUTRE, et c'est délibéré. Ce que le harnais sait d'un tel saut se
# résume à ceci : le cas n'a pas tourné, et il n'est pas compté comme réussi. Il
# ne prétend rien de plus.
#
# La qualification d'un saut ne s'obtient pas par défaut : elle se relit, un cas
# à la fois, et se déclare alors par « saute_par_nature » ou par
# « saute_indisponible ». Tant qu'elle n'a pas été faite, la nommer à l'écran
# serait une affirmation que personne n'a établie — et sur un harnais dont
# l'objet est l'honnêteté des verdicts, une affirmation gratuite coûte plus cher
# que le silence.
#
# Ce que « saute » AFFIRME (rien) et ce qu'il COMPTE (non_applicables, donc un
# code 4) sont donc volontairement dissociés. Le compteur reste celui d'avant la
# qualification, pour qu'aucun verdict existant ne change tant que la relecture
# n'a pas eu lieu ; le message, lui, ne devance plus cette relecture. La ligne
# du bilan agrège les deux — relus et non relus — et se garde donc, elle aussi,
# de nommer une nature : elle dit ce que le compteur sait, « sans
# indisponibilité déclarée », et rien de plus.
#
# Dans le doute, employer « saute_indisponible » : un rouge à tort se voit et se
# corrige, un vert à tort ne se voit pas.
saute() {
    warn "NON EXÉCUTÉ : $1${2:+ — $2}"
    non_executes=$((non_executes + 1))
    non_applicables=$((non_applicables + 1))
}

# saute_par_nature <libellé> [raison] — cas NON APPLICABLE PAR NATURE, RELU.
#
# Mêmes compteurs et même verdict que « saute » : seul le message change, et
# avec lui ce que le harnais affirme. Ce nom est une SIGNATURE — l'employer,
# c'est déclarer qu'on a examiné ce cas précis et conclu qu'aucune exécution ne
# le rendra jamais atteignable ici : systemd absent du profil, CAP_SYS_ADMIN
# refusé au conteneur, récursion structurelle.
#
# Il ne convient pas à ce qui dépend de la MACHINE plutôt que du cas :
# « /etc/os-release illisible sur cet hôte » ou « le harnais ne tourne pas sous
# root » sont des propriétés de l'environnement courant, pas des limites de
# nature — elles tombent ailleurs sur une autre machine.
saute_par_nature() {
    warn "NON EXÉCUTÉ (non applicable par nature) : $1${2:+ — $2}"
    non_executes=$((non_executes + 1))
    non_applicables=$((non_applicables + 1))
}

# saute_indisponible <libellé> [raison] — ENVIRONNEMENT INDISPONIBLE.
#
# La preuve existe et serait produite ailleurs : c'est l'environnement qui a
# manqué. Un seul saut de cette nature fait sortir le fichier en 3 — rien n'est
# prouvé — quel que soit le nombre de cas réussis par ailleurs. C'est ce qui
# ferme le faux vert « presque tout est sauté, donc tout va bien ».
saute_indisponible() {
    warn "NON EXÉCUTÉ (environnement indisponible) : $1${2:+ — $2}"
    non_executes=$((non_executes + 1))
    indisponibilites=$((indisponibilites + 1))
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
#
# La ligne d'information n'étiquette pas la nature des sauts qu'elle décompte :
# « non_applicables » agrège ceux de « saute » — non relus — et ceux de
# « saute_par_nature » — relus. Les annoncer « par nature » affirmerait ce que
# ce compteur ne sait pas. Sous-affirmer ne produit jamais de faux vert ;
# sur-affirmer, si. Un fichier de cas dont TOUS les sauts sont qualifiés peut,
# lui, nommer la nature dans son propre bilan : voir tests/README.md §5.
# S'appelle en dernière instruction du fichier de cas : les branches 1, 3 et 4
# sortent, la branche nominale se contente de rendre la main — le fichier se
# termine alors sur le succès de « success », donc en 0.
bilan() {
    local etiquette="$1"

    info "Bilan $etiquette : $reussites vérification(s) réussie(s), $echecs échec(s), $non_executes NON EXÉCUTÉ(s) — dont $non_applicables sans indisponibilité déclarée et $indisponibilites indisponibilité(s) d'environnement"

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

    # Une indisponibilité suffit. « Au moins une réussite » ne fermait pas le
    # faux vert : quelques cas de préflight, qui n'ont besoin de rien, suffisent
    # à franchir ce seuil pendant que l'essentiel de la preuve s'évapore.
    # Testé AVANT les non applicables : les deux natures se côtoient, la plus
    # grave l'emporte.
    if [ "$indisponibilites" -gt 0 ]; then
        warn "$etiquette : $indisponibilites cas n'ont pas pu être produits faute d'environnement — rien n'est prouvé de fiable."
        exit 3
    fi

    if [ "$non_executes" -gt 0 ]; then
        warn "$etiquette : $non_executes vérification(s) NON EXÉCUTÉE(s) — les cas correspondants ne sont pas prouvés."
        exit 4
    fi

    success "$etiquette : tous les cas vérifiés ($reussites vérifications)."
}
