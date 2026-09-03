#!/usr/bin/env bash
# tests/integration/linux-system.test.sh — les six scripts de Linux/System, exécutés.
#
# Critères de TASK-004, éprouvés par l'exécution réelle et non par la lecture :
#
#   1. --help affiché, code 0                        groupe « préflight »
#   2. refus sans privilège pour les scripts modifiants  groupe « préflight »
#   3. --dry-run ne modifie aucun fichier            groupe « dry-run »
#   4. deux exécutions de suite laissent le système identique  groupe « idempotence »
#   5. system-info.sh tourne sans privilège, code 0  groupe « system-info »
#   6. option inconnue refusée avec le code 2        groupe « préflight »
#
# L'énoncé s'arrête à ces six critères. Ce fichier en éprouve un septième, de
# son propre chef, parce qu'il a de la valeur et que le groupe « préflight » le
# rendait accessible sans frais :
#
#   +. OS non supporté refusé (require_os)           groupe « préflight »
#
# TASK-016 y ajoute le verrouillage de quatre corrections de codes de retour et
# de messages, groupe « 1 bis » :
#
#   a. --file sans valeur : code 2, message préfixé [ERROR], UNE ligne
#   b. valeur d'argument invalide : code 2 sur les trois scripts concernés
#   c. le trap ERR ne double plus le diagnostic de configure-swap.sh
#   d. un argument obligatoire manquant ne déverse plus l'aide sur stderr
#
# et la non-régression qui les borne, groupe « 1 ter » : sans privilège mais
# avec des arguments valides, un script rend toujours 1 — un privilège
# insuffisant est un échec d'exécution, pas une erreur d'usage (ADR-0003,
# décision 10). Avec une option inconnue ou une valeur invalide, il rend 2 :
# les arguments sont vérifiés avant les privilèges.
#
# TASK-017 y ajoute le verrouillage de la validation de --file, section 5 du
# groupe « 1 bis » et groupe « 3 bis » :
#
#   e. une valeur commençant par un tiret est refusée en 2, sans que dirname
#      la voie ni que le trap ERR double le diagnostic
#   f. un chemin relatif est refusé en 2, et rien ne naît dans le répertoire
#      courant — le cas grave, éprouvé avec SRV_SWAP_SIZE imposé
#   g. --dry-run et -y placés APRÈS un --file valide restent actifs : c'est
#      l'assertion qui manquait, et la seule qui prouve que --file ne consomme
#      plus l'option suivante
#
# TASK-019 y ajoute le verrouillage du contrôle de la NATURE de la cible,
# section 6 du groupe « 1 bis », deux cas nominaux au groupe « 3 » et le groupe
# « 3 ter » :
#
#   h. un fichier ordinaire existant est refusé en 2 et reste INTACT — contenu
#      et inode relevés avant et après ; c'est le cas qui motive la tâche, le
#      « rm -f » du script le supprimait sur un simple oui
#   i. un répertoire et « / » sont refusés en 2, sans message brut de rm ni
#      ligne de trap, avec un décompte MESURÉ des lignes [ERROR]
#   j. les deux cibles nominales continuent de passer : le chemin inexistant
#      (« créer »), et le fichier d'échange inactif reconnu à sa signature
#      SWAPSPACE2 (« remplacer ») — seule preuve directe de cette lecture
#   k. le chemin par défaut /swapfile est contrôlé lui aussi, et le contrôle
#      reste APRÈS require_root : sans privilège, le script rend toujours 1
#
# Le second tour de TASK-019 — valider_fichier_swap prend un paramètre de moment,
# « avant-root » ou « apres-root » — ajoute les cas f et g de cette section 6 :
#
#   l. les cinq refus valent AUSSI sans privilège, en 2 et en quatre lignes :
#      les arguments se jugent avant les privilèges, et l'aiguillage sur le
#      moment n'a différé aucun d'eux
#   m. le SEUL verdict différé est celui d'une cible illisible : sans privilège
#      elle rend 1 et non 2 — la régression que le relecteur avait mesurée —
#      et en root le refus ordinaire tranche, en 2
#
# TASK-018 y ajoute le verrouillage du NON-DOUBLEMENT du trap ERR sur les
# substitutions de commande, groupes « 3 quater », « 4 bis » et « 4 ter » :
#
#   n. le répertoire d'accueil absent — « --file /pas/de/dossier/swapfile » —
#      est refusé en 2 sur TROIS lignes mesurées, sans ligne de trap, AVEC ET
#      SANS privilège : les arguments se jugent avant les privilèges, et
#      l'absence d'un répertoire se constate sans le moindre droit
#   n bis. le SEUL verdict que le script ait encore raison de différer : un
#      ancêtre du chemin non traversable rend 1 sans privilège — jamais
#      « Répertoire introuvable » — et le chemin nominal passe en root. Un
#      témoin, chemin absent sous des ancêtres traversables, interdit de
#      conclure que « sans privilège » vaudrait « toujours différé »
#   o. « stat » en échec, provoqué par un stub en tête de PATH, ne produit que
#      le diagnostic métier — aucune ligne de trap, aucun message brut de bash
#   p. « mktemp » en échec, provoqué par un TMPDIR pointant sur un chemin
#      absent, rend 1 sur TROIS lignes, laisse /etc/hosts strictement intact et
#      la sauvegarde en place
#   p bis. la lecture du fuseau courant : le chemin nominal sans une seule ligne
#      [ERROR] deux fois de suite, /etc/timezone vide qui part au repli, le faux
#      « tr », et les trois sources en échec — non fatal avant l'application,
#      fatal à la vérification
#   q. la VALEUR rendue par dirname et par df -BM est confrontée à une mesure du
#      harnais, à 64 Mo près — la seule assertion qui verrait une condition
#      rendant une valeur fausse sans rien dire
#   r. le chemin nominal « 512M --dry-run » ne porte AUCUNE ligne [ERROR] et va
#      jusqu'au résumé des opérations, deux exécutions de suite
#
# Le quatrième tour ajoute les groupes « 3 quinquies » et « 4 quater », pour six
# affectations que le recensement avait manquées — system-info.sh en entier, deux
# « hostname » et un « wc | tr ». Elles ont une propriété que les précédentes
# n'avaient pas : LEUR ÉCHEC N'EST PAS FATAL, et c'est ce qui est verrouillé :
#
#   s. « nproc » en échec : system-info.sh sort en 0 et affiche « non
#      disponible » — un script de diagnostic dégrade, il ne meurt pas
#   t. « awk » en échec sur /proc/meminfo, « free » masqué par un bac à sable de
#      liens : les deux valeurs dégradent, code 0, deux avertissements mesurés
#   u. « wc » en échec : « ? paquet(s) », code 0, la liste des paquets produite
#      malgré tout — avec un faux apt-get pour que le site soit atteint
#   v. « hostname » en échec, ses DEUX sites en un seul appel : code 0,
#      « inconnu » plutôt qu'une chaîne vide, /etc/hosts réécrit malgré tout.
#      « require_cmd hostname » n'y protégeait de rien — il prouve que la
#      commande existe, pas qu'elle réussit
#
# COMMENT LIRE LES DÉCOMPTES DE CE FICHIER. Le nombre de lignes que le trap ERR
# produit n'est pas un invariant du motif : il dépend de la profondeur d'appel et
# du flux. Mesuré — trois lignes quand la substitution appelle une fonction, deux
# pour une affectation directe, AUCUNE en position d'argument, et une seule si le
# trap écrivait sur stdout, le sous-shell capturant alors les autres. Voir
# Linux/System/recensement-substitutions.md §1. Chaque décompte est mesuré sur
# son site.
#
# Les quatre sites corrigés de configure-cron.sh ont leur propre fichier :
# tests/integration/configure-cron.test.sh, groupe « 8 bis ».
#
# Le cinquième et dernier tour ferme les sept sites que le quatrième laissait en
# forme nue — six affectations plus le « dirname » —, groupes « 3 sexies » et
# « 4 quinquies ». Le relecteur avait qualifié ces réserves d'ABANDON DÉGUISÉ :
# la raison invoquée était toujours « aucune cause n'atteint ce site », et elle
# avait été démentie quatre fois par la même mutation d'une ligne.
#
#   w. « dirname » en échec : code 1, DEUX lignes [ERROR] mesurées, dirname
#      nommé. Sa branche n'avait jamais été empruntée — le site est allé et venu
#      trois fois avant d'être tranché
#   x. « sed » puis « tr » dans en_megaoctets : code 1 et NON 2, et surtout PAS
#      de « Taille invalide ». Un outil en échec ne fait pas d'une taille juste
#      une faute de l'appelant. La non-régression du refus métier borde le cas
#   y. « basename » dans configure-logging.sh : code 1, trois lignes, LOG_DIR et
#      son origine cités, et le socle intact — le stub est sélectif
#   z. « date » dans configure-hostname.sh : fatal, /etc/hosts strictement
#      intact, AUCUNE sauvegarde déposée
#   aa. « date » dans la phase fstab de configure-swap.sh : fatal APRÈS
#      l'activation. Le fichier d'échange SUBSISTE — « trap - EXIT » a été
#      désarmé — et la ligne à inscrire à la main est donnée
#   bb. la boucle de suffixe ne rappelle plus « date » : le nom suffixé réutilise
#      l'horodatage déjà lu, et le compteur d'appels du faux date le mesure
#
# Il ne reste au groupe 5 qu'une seule réserve de forme nue, d'une autre nature
# que le doublement.
#
# TASK-021 y ajoute le SEPTIÈME script du domaine, check-disk.sh — diagnostic de
# stockage en lecture seule stricte —, groupe « 2 bis » :
#
#   cc. les six refus en 2, et surtout l'ABSENCE DE TOUTE SORTIE avant chacun :
#       les arguments se valident avant qu'un seul chiffre ne soit lu
#   dd. le tableau n'est PAS VIDE en conteneur : « overlay » figure aux deux
#       sections d'occupation, et c'est un DÉCOMPTE de lignes qui le voit — un
#       filtre naïf produirait un écran blanc sur lequel toutes les assertions
#       de contenu resteraient vertes
#   ee. le code 0 sous n'importe quelle commande défaillante, une par une : df,
#       du, lsblk en échec, lsblk ABSENT, awk, sort. Chaque fois un [WARN]
#       nommant la cause, « non disponible » à l'affichage, et AUCUNE ligne
#       « Échec (code » — le motif de TASK-018, qu'un script neuf ne doit pas
#       réintroduire
#   ff. LA SORTIE PARTIELLE : « df » et « du » rendent 1 dès qu'un seul point de
#       montage leur résiste, APRÈS avoir écrit tout ce qu'ils ont pu. Le script
#       décide sur le VIDE, pas sur le code. Éprouvé deux fois — par un faux df
#       qui écrit puis sort en 1, et par le cas réel d'un « du » sur « / » sans
#       privilège
#   gg. le seuil est ATTEINT (« -ge ») et non DÉPASSÉ (« -gt ») : à occupation
#       exactement égale au seuil, le [WARN] doit sortir. Un « -gt » resterait
#       vert sous tout jeu de données qui ne tombe pas pile sur la valeur
#   hh. la lecture seule, prouvée sur la totalité du groupe : empreinte de tout
#       /etc et « find -newer », journal excepté
#
# CE FICHIER MODIFIE LE SYSTÈME. Il n'écrit rien tant qu'il n'a pas reconnu un
# système jetable (conteneur Docker, ou MGNET_TEST_JETABLE=1) : ailleurs, les
# groupes modifiants se déclarent NON EXÉCUTÉS plutôt que de réécrire
# /etc/hosts d'une machine de travail.
#
#   tests/env/run-in-container.sh -- tests/run.sh integration
#
# ---------------------------------------------------------------------------
# Comment l'idempotence est prouvée ici, et pourquoi la preuve tient
# ---------------------------------------------------------------------------
#
#   empreinte P0 -> exécution 1 -> empreinte A -> exécution 2 -> empreinte B
#
# « A == B » ne suffit pas. Sur un système déjà conforme, les deux exécutions ne
# font rien, les trois empreintes sont égales et le test passe sans rien
# prouver. C'est exactement ce que la règle « un conteneur neuf par cas » vise à
# empêcher. Chaque cas exige donc AUSSI « P0 != A » : le premier passage doit
# avoir réellement modifié quelque chose. Une preuve d'idempotence à vide
# devient alors un échec, et non un succès silencieux.
#
# Ce fichier tourne à l'intérieur d'un unique conteneur — c'est là que
# « tests/run.sh integration » est invoqué, et docker n'y est pas disponible
# pour en créer d'autres. Trois dispositions remplacent le conteneur neuf par
# cas, et sont vérifiées et non supposées :
#
#   - les groupes non modifiants passent en premier (préflight, system-info,
#     dry-run) ; le groupe « idempotence » est le dernier ;
#   - l'empreinte relevée juste avant le groupe « idempotence » est comparée à
#     « info-avant », relevée à l'ouverture du groupe « system-info ». Si elle a
#     bougé, le groupe entier est déclaré NON EXÉCUTÉ : on ne prouve pas une
#     idempotence depuis un état inconnu. Le groupe « préflight », antérieur à
#     « info-avant », échappe à cette garde — voir la note posée au-dessus du
#     contrôle lui-même ;
#   - les trois cas d'idempotence portent sur des fichiers DISJOINTS —
#     /etc/localtime et /etc/timezone, /etc/hosts, /etc/logrotate.d/<règle> —
#     aucun ne prépare le terrain d'un autre.
#
# ---------------------------------------------------------------------------
# Recouvrement assumé avec tests/acceptance/TASK-011-*
# ---------------------------------------------------------------------------
#
# TASK-011 éprouve déjà, dans onze conteneurs neufs, le préflight, les
# --dry-run et l'idempotence de cinq de ces six scripts. Ses assertions sont
# formulées autour des corrections d'analyse statique qu'elle portait (SC1087,
# export ASSUME_YES) et disparaîtront avec elle. Le niveau « integration » est
# le domicile durable de ces preuves : le recouvrement est ici assumé, borné à
# UN conteneur au lieu de onze, et signalé dans tests/README.md.
#
# Ce que ce fichier apporte que TASK-011 n'a pas :
#   - system-info.sh, qu'elle ne couvre que par « --help » ;
#   - l'exigence « P0 != A », qui interdit une idempotence prouvée à vide ;
#   - une empreinte de TOUT /etc, et non d'une liste de fichiers choisis
#     d'avance : un fichier inattendu est vu ;
#   - le cas « /etc/hosts déjà conforme par un alias », chemin de
#     hosts_deja_conforme() qu'aucun cas existant n'emprunte.

set -Eeuo pipefail

_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_dir/lib/common.sh" ] && [ "$_dir" != "/" ]; do _dir="$(dirname "$_dir")"; done
source "$_dir/lib/common.sh"
# shellcheck source=/dev/null
source "$SCRIPTS_ROOT/tests/lib/assert.sh"

SYS="$SCRIPTS_ROOT/Linux/System"

INFO_SH="$SYS/system-info.sh"
HOSTNAME_SH="$SYS/configure-hostname.sh"
LOGGING_SH="$SYS/configure-logging.sh"
SWAP_SH="$SYS/configure-swap.sh"
TIMEZONE_SH="$SYS/configure-timezone.sh"
UPDATE_SH="$SYS/update-system.sh"

# Les six scripts du répertoire. system-info.sh est le seul qui ne modifie
# rien : il figure dans le premier lot, pas dans le second.
SIX_SCRIPTS="$INFO_SH $HOSTNAME_SH $LOGGING_SH $SWAP_SH $TIMEZONE_SH $UPDATE_SH"
CINQ_MODIFIANTS="$HOSTNAME_SH $LOGGING_SH $SWAP_SH $TIMEZONE_SH $UPDATE_SH"

FUSEAU_CIBLE="Europe/Paris"

REP_TMP="$(mktemp -d)"
F_OUT="$REP_TMP/stdout"
F_ERR="$REP_TMP/stderr"
CODE=0

trap 'rm -rf "$REP_TMP"' EXIT

# ===================================================================
# Outillage
# ===================================================================

# lancer <commande...> — exécute dans un SOUS-SHELL et capture le code.
#
# Le sous-shell est indispensable : les scripts posent « set -Eeuo pipefail » et
# lib/common.sh un « trap ERR ». Un script qui meurt en 2 tuerait le harnais si
# on ne l'isolait pas. L'entrée standard est fermée : confirm() lit alors une
# réponse vide et refuse, ce qui rend les chemins « sans -y » observables.
lancer() {
    CODE=0
    ( "$@" ) >"$F_OUT" 2>"$F_ERR" </dev/null || CODE=$?
}

# lancer_depuis <répertoire> <commande...> — « lancer », depuis un répertoire
# de travail donné.
#
# Le « cd » a lieu DANS le sous-shell : le répertoire courant du harnais n'est
# jamais déplacé, et un cas qui échoue ne laisse pas les suivants ailleurs.
# Utile au seul cas où le répertoire courant est l'objet même de la preuve — un
# chemin relatif donné à --file y ferait naître le fichier d'échange.
lancer_depuis() {
    local repertoire="$1"; shift
    CODE=0
    ( cd "$repertoire" && "$@" ) >"$F_OUT" 2>"$F_ERR" </dev/null || CODE=$?
}

sortie()  { cat "$F_OUT"; }
erreur()  { cat "$F_ERR"; }

# empreinte <fichier> — état des fichiers que ces scripts peuvent toucher.
#
# TOUT /etc est relevé, contenu compris, et non une liste de fichiers arrêtée
# d'avance : c'est ce qui permet de voir une écriture qu'on n'attendait pas.
# 119 fichiers dans l'image de test, quelques dizaines de millisecondes.
#
# LOG_DIR est délibérément hors de l'empreinte : lib/common.sh y écrit un
# journal au seul chargement, avant même que le script n'ait lu ses arguments.
# L'y inclure rendrait toute empreinte différente de la précédente et aucun
# --dry-run ne pourrait jamais être déclaré inoffensif. Les écritures hors
# journaux sont surveillées séparément, par ecritures_depuis().
empreinte() {
    local destination="$1"
    local code=0

    {
        # « -exec … + » groupe les arguments : un seul cksum pour tout /etc.
        find /etc -type f -exec cksum {} + 2>/dev/null | sort
        find /etc -type l -printf 'lien %p -> %l\n' 2>/dev/null | sort
        printf 'hostname %s\n' "$(hostname)"
        printf 'swaps %s\n' "$(cksum < /proc/swaps)"
        if [ -e /swapfile ]; then
            printf 'swapfile %s octets\n' "$(stat -c %s /swapfile)"
        else
            printf 'swapfile absent\n'
        fi
    } > "$destination" || code=$?

    # find rend 1 dès qu'un fichier disparaît entre le parcours et le cksum. Le
    # code est relevé plutôt qu'ignoré : un relevé incomplet fausserait les
    # comparaisons qui suivent, et doit se voir à l'écran.
    if [ "$code" -ne 0 ]; then
        warn "Relevé d'empreinte incomplet (code $code) : $destination"
    fi
}

# ecritures_depuis <témoin> <destination> — fichiers modifiés depuis le témoin.
#
# La référence est un fichier et non une date : « find -newer » compare à la
# précision du système de fichiers, là où « -newermt @secondes » arrondit et
# ferait remonter tout ce que le conteneur a écrit dans la même seconde.
#
# /var/log est exclu — c'est le domicile des journaux, dont l'écriture n'est
# pas une modification du système au sens de --dry-run. Les caches apt et la
# base dpkg le sont aussi : update-system.sh rafraîchit l'index de paquets même
# en --dry-run, et son aide le dit.
ecritures_depuis() {
    local temoin="$1" destination="$2"
    local racine code=0
    local -a racines=()

    for racine in /etc /root /usr /opt /srv /var /boot; do
        if [ -d "$racine" ]; then
            racines+=("$racine")
        fi
    done

    find "${racines[@]}" -newer "$temoin" \
        -not -path '/var/log' \
        -not -path '/var/log/*' \
        -not -path '/var/cache/apt' \
        -not -path '/var/cache/apt/*' \
        -not -path '/var/lib/apt' \
        -not -path '/var/lib/apt/*' \
        -not -path '/var/lib/dpkg' \
        -not -path '/var/lib/dpkg/*' \
        2>/dev/null | sort > "$destination" || code=$?

    if [ "$code" -ne 0 ]; then
        warn "Relevé des écritures incomplet (code $code) : $destination"
    fi
}

# assert_empreinte_egale <avant> <après> <libellé>
assert_empreinte_egale() {
    local avant="$1" apres="$2" libelle="$3"
    if diff -u "$avant" "$apres" > "$REP_TMP/diff" 2>&1; then
        ok "$libelle"
    else
        ko "$libelle" "$(head -n 12 "$REP_TMP/diff" | tr '\n' '|')"
    fi
}

# assert_empreinte_differente <avant> <après> <libellé>
# Garde anti-preuve-à-vide : une idempotence mesurée sur un système que la
# première exécution n'a pas touché ne prouve rien.
assert_empreinte_differente() {
    local avant="$1" apres="$2" libelle="$3"
    if diff -q "$avant" "$apres" >/dev/null 2>&1; then
        ko "$libelle" "aucune modification relevée : la preuve d'idempotence serait vide"
    else
        ok "$libelle"
    fi
}

# assert_aucune_ecriture <témoin> <libellé>
assert_aucune_ecriture() {
    local temoin="$1" libelle="$2"
    ecritures_depuis "$temoin" "$REP_TMP/ecritures"
    if [ -s "$REP_TMP/ecritures" ]; then
        ko "$libelle" "$(tr '\n' ' ' < "$REP_TMP/ecritures")"
    else
        ok "$libelle"
    fi
}

# empreinte_fichier <chemin> — l'état d'UN fichier, contenu compris.
#
# L'empreinte de tout /etc, plus haut, sert à prouver qu'un script n'a rien
# touché. Celle-ci sert l'inverse : montrer qu'un fichier NOMMÉMENT confié à un
# script qui s'apprêtait à le supprimer est ressorti intact. Elle relève le
# contenu (cksum), la taille, l'inode et la date de modification : un fichier
# supprimé puis recréé à l'identique — ce que ferait « rm -f » suivi d'une
# création — changerait d'inode même si le contenu revenait par miracle.
#
# « cksum < fichier » plutôt que « cksum fichier » : la sortie ne porte alors
# pas le nom du fichier, et l'empreinte reste comparable telle quelle.
#
# ABSENT est une valeur d'empreinte à part entière : comparer deux relevés dont
# le premier vaut ABSENT est une preuve vide, et les cas qui l'emploient posent
# une garde explicite avant de comparer.
empreinte_fichier() {
    local chemin="$1"
    if [ -e "$chemin" ]; then
        printf '%s | %s' "$(cksum < "$chemin")" "$(stat -c '%s %i %Y' "$chemin")"
    else
        printf 'ABSENT'
    fi
}

# --- Mesure du VOLUME de stderr --------------------------------------------
# Ce que ces deux fonctions permettent d'exiger n'est pas dans le contenu d'un
# message mais dans sa QUANTITÉ : « une seule ligne », « une seule ligne
# [ERROR] ». C'est la seule forme d'assertion qui empêche une aide entière ou un
# second diagnostic de revenir sur stderr — une assertion de contenu reste verte
# pendant qu'on ajoute des lignes autour d'elle.
#
# Le « || [ -n "$ligne" ] » compte la dernière ligne même si le fichier ne se
# termine pas par un saut de ligne : sans lui, un diagnostic sans « \n » final
# serait décompté à zéro et l'assertion passerait pour de mauvaises raisons.

# nb_lignes_erreur — nombre de lignes de stderr du dernier « lancer ».
nb_lignes_erreur() {
    local ligne n=0
    while IFS= read -r ligne || [ -n "$ligne" ]; do
        n=$(( n + 1 ))
    done < "$F_ERR"
    printf '%s' "$n"
}

# nb_lignes_contenant <motif> — lignes de stderr portant ce motif LITTÉRAL.
# « contient » vient de tests/lib/assert.sh : les crochets de [ERROR] y sont
# littéraux, là où un grep les prendrait pour une classe de caractères.
nb_lignes_contenant() {
    local motif="$1"
    local ligne n=0
    while IFS= read -r ligne || [ -n "$ligne" ]; do
        if contient "$ligne" "$motif"; then
            n=$(( n + 1 ))
        fi
    done < "$F_ERR"
    printf '%s' "$n"
}

# assert_au_plus <maximum> <obtenu> <libellé>
# Une borne, et non une égalité : elle laisse la place à une reformulation du
# diagnostic sans laisser passer les vingt-huit lignes d'une aide.
assert_au_plus() {
    local maximum="$1" obtenu="$2" libelle="$3"
    if [ "$obtenu" -le "$maximum" ] 2>/dev/null; then
        ok "$libelle — $obtenu ligne(s), $maximum au maximum"
    else
        ko "$libelle" "au plus $maximum ligne(s) attendue(s), obtenu $obtenu"
    fi
}

# valeur_imposee_par_config <variable> — la variable est-elle déjà fournie ?
#
# Les cas « argument obligatoire manquant » n'ont de sens que si config/server.env
# ne fournit pas la valeur : le script la prendrait alors et ne diagnostiquerait
# rien. lib/common.sh charge ce fichier avec « set -a » depuis TASK-015, donc la
# variable est exportée jusqu'ici ; le contrôle du fichier double la vérification
# pour le cas où elle serait vide mais définie.
SERVER_ENV="$SCRIPTS_ROOT/config/server.env"
valeur_imposee_par_config() {
    local variable="$1"
    if [ -n "${!variable:-}" ]; then
        return 0
    fi
    if [ -f "$SERVER_ENV" ] \
        && grep -qE "^[[:space:]]*(export[[:space:]]+)?$variable=." "$SERVER_ENV"; then
        return 0
    fi
    return 1
}

# ===================================================================
# Reconnaissance de l'environnement
# ===================================================================
titre "0. Environnement"

EST_LINUX="false"
if [ "$(uname -s 2>/dev/null)" = "Linux" ]; then
    EST_LINUX="true"
fi

EST_DEBIAN="false"
if [ -r /etc/os-release ]; then
    identifiant="$(sed -n 's/^ID=//p' /etc/os-release | tr -d '"')"
    case "$identifiant" in
        debian|ubuntu) EST_DEBIAN="true" ;;
    esac
fi

EST_ROOT="false"
if [ "$(id -u)" -eq 0 ]; then
    EST_ROOT="true"
fi

# Un système jetable, et rien d'autre, autorise les groupes modifiants.
JETABLE="false"
if [ -f /.dockerenv ]; then
    JETABLE="true"
elif grep -qE '(docker|containerd|lxc)' /proc/1/cgroup 2>/dev/null; then
    JETABLE="true"
elif [ "${MGNET_TEST_JETABLE:-}" = "1" ]; then
    JETABLE="true"
fi

info "Linux : $EST_LINUX — Debian/Ubuntu : $EST_DEBIAN — root : $EST_ROOT — jetable : $JETABLE"

# Lanceur non privilégié. Trois candidats éprouvés dans l'ordre : le premier qui
# abaisse RÉELLEMENT l'UID est retenu. Sans lui, les cas de privilège sont
# déclarés NON EXÉCUTÉS — jamais réussis.
LANCEUR_SANS_ROOT=()
LOG_DIR_NOBODY="/tmp/mgnet-integration-nobody"

choisir_lanceur_sans_root() {
    local uid=""

    if [ "$EST_ROOT" = "false" ]; then
        LANCEUR_SANS_ROOT=(env)
        return 0
    fi

    if command -v setpriv >/dev/null 2>&1; then
        uid="$(setpriv --reuid=65534 --regid=65534 --clear-groups id -u 2>/dev/null)" || uid=""
        if [ "$uid" = "65534" ]; then
            LANCEUR_SANS_ROOT=(setpriv --reuid=65534 --regid=65534 --clear-groups)
            return 0
        fi
    fi

    if command -v runuser >/dev/null 2>&1; then
        uid="$(runuser -u nobody -- id -u 2>/dev/null)" || uid=""
        if [ "$uid" = "65534" ]; then
            LANCEUR_SANS_ROOT=(runuser -u nobody --)
            return 0
        fi
    fi

    return 1
}

SANS_ROOT_DISPONIBLE="false"
if choisir_lanceur_sans_root; then
    SANS_ROOT_DISPONIBLE="true"
    info "Lanceur non privilégié : ${LANCEUR_SANS_ROOT[*]}"
fi

# sans_root <commande...> — la commande, exécutée sans privilège.
# LOG_DIR part dans /tmp : sans cela lib/common.sh tenterait d'écrire son
# journal dans le dépôt monté, qui n'appartient pas à « nobody ».
sans_root() {
    lancer env "LOG_DIR=$LOG_DIR_NOBODY" "${LANCEUR_SANS_ROOT[@]}" "$@"
}

# Rien à faire hors Linux : ces scripts n'y démarrent même pas.
if [ "$EST_LINUX" != "true" ]; then
    saute "l'ensemble des cas de Linux/System" "cet hôte n'est pas un Linux — ces scripts ne s'y exécutent pas"
    bilan "TASK-004 / Linux/System"
    exit 0
fi

# logrotate conditionne configure-logging.sh. Il est absent de l'image de test :
# la tentative d'installation a lieu ICI, avant toute empreinte, pour que la
# mutation de la base dpkg ne vienne pas polluer une comparaison.
LOGROTATE_DISPONIBLE="false"
if command -v logrotate >/dev/null 2>&1; then
    LOGROTATE_DISPONIBLE="true"
elif [ "$EST_ROOT" = "true" ] && [ "$JETABLE" = "true" ]; then
    info "logrotate absent : tentative d'installation…"
    if apt-get update -qq >/dev/null 2>&1 && apt-get install -y -qq logrotate >/dev/null 2>&1; then
        LOGROTATE_DISPONIBLE="true"
        info "logrotate installé."
    fi
fi

REGLE_LOGROTATE="/etc/logrotate.d/$(basename "$LOG_DIR")"

# ===================================================================
# 1. Préflight — aide, option inconnue, privilèges, OS
# ===================================================================
titre "1. Préflight des six scripts"

for script in $SIX_SCRIPTS; do
    nom="$(basename "$script")"

    lancer bash "$script" --help
    assert_code 0 "$CODE" "$nom --help sort en 0"
    assert_contient "$(sortie)" "Usage :" "$nom --help écrit son usage sur stdout"

    lancer bash "$script" -h
    assert_code 0 "$CODE" "$nom -h sort en 0"

    lancer bash "$script" --option-qui-n-existe-pas
    assert_code 2 "$CODE" "$nom refuse une option inconnue"
    assert_contient "$(erreur)" "Option inconnue" "$nom nomme l'option inconnue"
done

# ===================================================================
# 1 bis. Erreurs d'usage — les quatre corrections de TASK-016
# ===================================================================
# Ces cas sont placés dans le groupe « préflight » parce qu'ils n'écrivent RIEN :
# chacun meurt pendant l'analyse des arguments ou la validation, avant
# require_root et avant la moindre modification. Le groupe reste non modifiant,
# et la garde d'état du groupe « idempotence » n'en est pas troublée.
#
# La convention verrouillée ici est celle de docs/architecture-technique.md §6 :
#
#   2  erreur d'usage      option inconnue, argument manquant, VALEUR INVALIDE
#   1  échec d'exécution   privilège insuffisant, dépendance absente
#
# Les quatre défauts que TASK-016 a corrigés étaient tous des écarts à cette
# règle, et aucune assertion ne les voyait — c'est ce trou que ce sous-groupe
# ferme.
titre "1 bis. Erreurs d'usage — codes, préfixes et volume de stderr"

# --- 1. Un argument d'option manquant : code 2, préfixé, en UNE ligne -------
# « --file » était lu par « FICHIER_SWAP="${1:?--file attend un chemin}" ». Cette
# expansion écrit un message brut de bash — sans préfixe [ERROR], précédé du nom
# du script et d'un numéro de ligne — et fait sortir le shell en 1. Les trois
# assertions ferment trois aspects distincts du défaut : le code, la forme du
# message, et son volume.
lancer bash "$SWAP_SH" --file
assert_code 2 "$CODE" "configure-swap.sh --file sans valeur : erreur d'usage"
assert_contient "$(erreur)" "[ERROR] --file attend un chemin." \
    "configure-swap.sh --file sans valeur : message préfixé [ERROR]"
assert_egal "1" "$(nb_lignes_erreur)" \
    "configure-swap.sh --file sans valeur : une seule ligne sur stderr"
# Le décompte ci-dessus ne suffit PAS à voir revenir « ${1:?…} » : le message
# brut de bash tient lui aussi sur une ligne. Cette assertion-ci nomme sa forme
# — « configure-swap.sh: line 62: 1: --file attend un chemin » — et c'est elle,
# avec les deux précédentes, qui ferme le défaut.
assert_absent "$(erreur)" "configure-swap.sh: line" \
    "configure-swap.sh --file sans valeur : aucun message brut de bash sur stderr"

# --- 2. Une valeur d'argument invalide rend 2 sur les trois scripts ---------
# configure-swap.sh appelait déjà « die … 2 » ; configure-timezone.sh et
# configure-hostname.sh appelaient « die » sans code, donc 1. Le même appel mal
# formé rendait ainsi deux codes différents selon le script visé.
#
# Les chemins de validation éprouvés ici sont ceux propres à chaque script, et
# non un seul cas répété : fuseau inexistant, répertoire technique de zoneinfo,
# tentative de remontée d'arborescence, caractère interdit dans un nom d'hôte.
lancer bash "$TIMEZONE_SH" Zone/Inexistante
assert_code 2 "$CODE" "configure-timezone.sh refuse un fuseau inexistant"
assert_contient "$(erreur)" "[ERROR] Fuseau inconnu : « Zone/Inexistante »." \
    "configure-timezone.sh nomme le fuseau refusé"

lancer bash "$TIMEZONE_SH" posix/UTC
assert_code 2 "$CODE" "configure-timezone.sh refuse un répertoire technique de zoneinfo"
assert_contient "$(erreur)" "[ERROR] « posix/UTC » est un répertoire technique de zoneinfo, pas un fuseau." \
    "configure-timezone.sh explique pourquoi posix/ est refusé"

lancer bash "$TIMEZONE_SH" ../etc/passwd
assert_code 2 "$CODE" "configure-timezone.sh refuse un fuseau contenant « .. »"
assert_contient "$(erreur)" "[ERROR] Fuseau invalide : « ../etc/passwd »." \
    "configure-timezone.sh nomme le fuseau invalide"

lancer bash "$HOSTNAME_SH" mon_serveur
assert_code 2 "$CODE" "configure-hostname.sh refuse un caractère interdit dans le nom"
assert_contient "$(erreur)" "[ERROR] Segment invalide : « mon_serveur » — lettres, chiffres et tirets uniquement." \
    "configure-hostname.sh dit quels caractères il accepte"

# « -mauvais- » n'atteint JAMAIS valider_nom : son tiret initial le fait basculer
# sur « Option inconnue » dès l'analyse des arguments. Le code est le même — 2 —
# mais pour une autre raison. L'assertion de message le dit explicitement, faute
# de quoi ce cas passerait pour une preuve de la validation du nom, qu'il
# n'exerce pas. C'est la nuance relevée par le relecteur de TASK-016.
lancer bash "$HOSTNAME_SH" -mauvais-
assert_code 2 "$CODE" "configure-hostname.sh refuse « -mauvais- »"
assert_contient "$(erreur)" "[ERROR] Option inconnue : -mauvais-" \
    "configure-hostname.sh traite « -mauvais- » en option inconnue, et non en nom invalide"

# Les trois autres branches de valider_nom. Sans elles, une seule des cinq
# sorties de la fonction serait épinglée, et un « die » sans code rétabli sur
# les quatre autres passerait sans être vu.
lancer bash "$HOSTNAME_SH" "mon..serveur"
assert_code 2 "$CODE" "configure-hostname.sh refuse un segment vide"
assert_contient "$(erreur)" "[ERROR] Nom invalide : segment vide" \
    "configure-hostname.sh nomme le segment vide"

lancer bash "$HOSTNAME_SH" "serveur.-x"
assert_code 2 "$CODE" "configure-hostname.sh refuse un segment commençant par un tiret"
assert_contient "$(erreur)" "commence ou finit par un tiret" \
    "configure-hostname.sh explique le refus du tiret"

# 254 caractères : un de trop pour le nom entier, mais chaque segment reste sous
# la limite de 63, faute de quoi c'est l'autre branche qui répondrait.
nom_trop_long="$(printf 'a%.0s' $(seq 1 60)).$(printf 'b%.0s' $(seq 1 60)).$(printf 'c%.0s' $(seq 1 60)).$(printf 'd%.0s' $(seq 1 60)).eeeeeeeeee"
assert_egal "254" "${#nom_trop_long}" "le nom d'essai fait bien 254 caractères"
lancer bash "$HOSTNAME_SH" "$nom_trop_long"
assert_code 2 "$CODE" "configure-hostname.sh refuse un nom de plus de 253 caractères"
assert_contient "$(erreur)" "[ERROR] Nom trop long : 254 caractères (253 au maximum)." \
    "configure-hostname.sh nomme la longueur refusée"

lancer bash "$HOSTNAME_SH" "$(printf 'z%.0s' $(seq 1 64))"
assert_code 2 "$CODE" "configure-hostname.sh refuse un segment de plus de 63 caractères"
assert_contient "$(erreur)" "(63 caractères au maximum)" \
    "configure-hostname.sh nomme la limite de segment"

lancer bash "$SWAP_SH" abc
assert_code 2 "$CODE" "configure-swap.sh refuse une taille non numérique"

lancer bash "$SWAP_SH" 12X
assert_code 2 "$CODE" "configure-swap.sh refuse une unité inconnue"

# Ce « die » est hors de en_megaoctets — il n'a jamais souffert du doublon de
# trap — mais il relève de la même convention et rendait déjà 2. L'y épingler
# évite qu'il en sorte par la suite.
lancer bash "$SWAP_SH" 32
assert_code 2 "$CODE" "configure-swap.sh refuse une taille inférieure au minimum"
assert_contient "$(erreur)" "[ERROR] Taille trop faible : 32 Mo (64 Mo au minimum)." \
    "configure-swap.sh nomme le minimum"

# --- 3. Le trap ERR ne double plus le diagnostic ----------------------------
# en_megaoctets rendait sa valeur par « printf » sur stdout : elle s'exécutait
# donc dans une substitution de commande. Son « die » ne quittait que ce
# sous-shell ; le code remonté au shell principal faisait échouer l'affectation,
# et le trap ERR de lib/common.sh ajoutait une seconde ligne :
#
#   [ERROR] Taille invalide : « abc » (exemples : 2G, 512M, 2048).
#   [ERROR] Échec (code 2) à la ligne 143 de configure-swap.sh.
#
# La fonction renseigne désormais une variable globale et s'appelle hors
# substitution. UNE ASSERTION D'ABSENCE EST FACILE À ÉCRIRE CREUSE : sur un
# stderr vide, mal capturé ou pris sur le mauvais flux, elle serait verte sans
# rien prouver. Trois gardes l'encadrent donc — le code, la présence effective du
# diagnostic métier, et le DÉCOMPTE des lignes [ERROR], qui reste juste même si
# le libellé du trap change un jour dans lib/common.sh.
lancer bash "$SWAP_SH" abc
assert_code 2 "$CODE" "configure-swap.sh abc : erreur d'usage"
assert_contient "$(erreur)" "[ERROR] Taille invalide : « abc » (exemples : 2G, 512M, 2048)." \
    "configure-swap.sh abc : le diagnostic métier est bien là — la garde de l'assertion d'absence"
assert_absent "$(erreur)" "Échec (code" \
    "configure-swap.sh abc : le trap ERR n'ajoute aucune ligne au diagnostic"
assert_egal "1" "$(nb_lignes_contenant '[ERROR]')" \
    "configure-swap.sh abc : stderr ne porte qu'une seule ligne [ERROR]"

# L'autre « die » de en_megaoctets, sur la branche des unités. Il empruntait le
# même sous-shell et souffrait du même doublon.
lancer bash "$SWAP_SH" 12X
assert_contient "$(erreur)" "[ERROR] Unité inconnue dans « 12X » (attendu G ou M)." \
    "configure-swap.sh 12X : le diagnostic métier est bien là"
assert_absent "$(erreur)" "Échec (code" \
    "configure-swap.sh 12X : le trap ERR n'ajoute aucune ligne au diagnostic"
assert_egal "1" "$(nb_lignes_contenant '[ERROR]')" \
    "configure-swap.sh 12X : stderr ne porte qu'une seule ligne [ERROR]"

# --- 4. Un argument obligatoire manquant : un diagnostic, pas l'aide --------
# configure-hostname.sh appelait « show_help >&2 » : vingt-huit lignes d'aide sur
# stderr, dans lesquelles les deux lignes de diagnostic se perdaient.
#
# C'est LE DÉCOMPTE qui verrouille ce point. Les assertions de contenu
# resteraient toutes vertes si l'aide revenait autour d'elles ; seule une borne
# sur le nombre de lignes s'y oppose. Les assertions d'absence de « Usage : » et
# de « Options : » la doublent en nommant ce qui n'a rien à faire là.
if valeur_imposee_par_config SRV_HOSTNAME; then
    saute "configure-hostname.sh sans nom : diagnostic court plutôt que l'aide entière" \
        "SRV_HOSTNAME est fourni par l'environnement ou config/server.env — le script ne diagnostiquerait rien"
else
    lancer bash "$HOSTNAME_SH"
    assert_code 2 "$CODE" "configure-hostname.sh sans nom : erreur d'usage"
    assert_contient "$(erreur)" "[ERROR] Nom d'hôte manquant." \
        "configure-hostname.sh sans nom : dit ce qui manque"
    assert_contient "$(erreur)" "configure-hostname.sh --help" \
        "configure-hostname.sh sans nom : renvoie vers l'aide au lieu de la déverser"
    assert_au_plus 5 "$(nb_lignes_erreur)" \
        "configure-hostname.sh sans nom : stderr reste court"
    assert_absent "$(sortie)" "Usage :" \
        "configure-hostname.sh sans nom : l'aide n'est pas non plus écrite sur stdout"
    assert_absent "$(erreur)" "Usage :" \
        "configure-hostname.sh sans nom : l'aide n'est pas déversée sur stderr"
    assert_absent "$(erreur)" "Options :" \
        "configure-hostname.sh sans nom : la liste des options n'est pas déversée sur stderr"
fi

# Le script voisin, sur le même critère. Il n'a jamais porté le défaut : cette
# assertion l'empêche de le contracter.
if valeur_imposee_par_config SRV_TIMEZONE; then
    saute "configure-timezone.sh sans fuseau : diagnostic court plutôt que l'aide entière" \
        "SRV_TIMEZONE est fourni par l'environnement ou config/server.env — le script ne diagnostiquerait rien"
else
    lancer bash "$TIMEZONE_SH"
    assert_code 2 "$CODE" "configure-timezone.sh sans fuseau : erreur d'usage"
    assert_contient "$(erreur)" "[ERROR] Fuseau horaire manquant." \
        "configure-timezone.sh sans fuseau : dit ce qui manque"
    assert_au_plus 5 "$(nb_lignes_erreur)" \
        "configure-timezone.sh sans fuseau : stderr reste court"
    assert_absent "$(erreur)" "Usage :" \
        "configure-timezone.sh sans fuseau : l'aide n'est pas déversée sur stderr"
fi

# --- 5. La valeur de --file est contrôlée — TASK-017 ------------------------
# « --file » acceptait n'importe quelle chaîne non vide. Le contrôle posé par
# TASK-016 — « [ -n "${1:-}" ] » — ne rejetait que la valeur VIDE : son objet
# était le code de retour, pas la nature de la valeur. Deux dangers restaient
# ouverts, et deux refus distincts les ferment.
#
# Les deux cas meurent pendant l'analyse des arguments, avant require_root et
# avant la moindre écriture : ils ont leur place dans ce groupe non modifiant.

# a. Une valeur commençant par un tiret — l'option avalée.
#
#   $ configure-swap.sh 512M --file --dry-run
#   [INFO] Fichier d'échange : --dry-run
#   dirname: unrecognized option '--dry-run'
#   [ERROR] Échec (code 1) à la ligne 195 de configure-swap.sh.
#
# Rien n'était écrit, mais PAR ACCIDENT : dirname refusait une chaîne commençant
# par deux tirets et « set -Eeuo pipefail » tuait le script avant l'allocation.
# Le garde-fou disparaissait avec n'importe quelle autre valeur — d'où le cas b.
#
# Les deux assertions d'absence épinglent les deux lignes exactes de cette trace
# — « dirname: » et « Échec (code » — et le DÉCOMPTE des lignes [ERROR] voit
# revenir celle du trap même si son libellé change un jour dans lib/common.sh.
# Ce refus en produit QUATRE : trois « error » puis le « die ».
#
# L'assertion « dirname: » garde tout son sens depuis que dirname est passé en
# contexte de condition (TASK-018, cinquième tour). Elle ne surveille pas le
# doublement, qui est traité ailleurs : elle prouve que la valeur n'ATTEINT JAMAIS
# dirname. Le diagnostic de la condition — « Répertoire d'accueil … indéterminable »
# — se produirait plus loin dans le script, et le message brut de dirname, lui,
# n'est éteint par aucune redirection : la condition suspend errexit et le trap,
# elle ne muselle pas la commande. Les deux se verraient donc si le refus de
# TASK-017 tombait.
lancer bash "$SWAP_SH" 512M --file --dry-run
assert_code 2 "$CODE" "configure-swap.sh --file --dry-run : erreur d'usage"
assert_contient "$(erreur)" "[ERROR] Valeur refusée pour --file : « --dry-run »." \
    "configure-swap.sh --file --dry-run : nomme la valeur refusée"
assert_absent "$(erreur)" "dirname:" \
    "configure-swap.sh --file --dry-run : dirname ne voit jamais la valeur"
assert_absent "$(erreur)" "Échec (code" \
    "configure-swap.sh --file --dry-run : le trap ERR n'ajoute aucune ligne au diagnostic"
assert_absent "$(erreur)" "Fichier d'échange : --dry-run" \
    "configure-swap.sh --file --dry-run : l'option n'est jamais retenue comme chemin"
assert_egal "4" "$(nb_lignes_contenant '[ERROR]')" \
    "configure-swap.sh --file --dry-run : stderr porte les quatre lignes du refus, pas une de plus"

# b. Un chemin relatif — le fichier d'échange égaré, le cas grave.
#
# L'ordre inversé « configure-swap.sh --file 2G » prend « 2G » pour un chemin.
# SRV_SWAP_SIZE est imposé DANS L'ENVIRONNEMENT DE L'APPEL, et ce n'est pas un
# détail : sans lui le script s'arrêterait faute de taille, sur le seul
# diagnostic d'état, et le cas ne prouverait rien du chemin. Avec lui, plus rien
# n'arrêtait le script avant la création du fichier.
#
# Le répertoire courant est un répertoire VIDE et jetable — c'est là que le
# fichier serait né — et son contenu est relevé avant et après.
# contenu_repertoire <répertoire> <destination> — ce que le répertoire porte.
# « find » plutôt que « ls » : un nom de fichier exotique y survit (SC2012), et
# la ligne d'en-tête garantit qu'un relevé vide reste un relevé, et non un
# fichier vide qu'une redirection ratée produirait tout aussi bien.
contenu_repertoire() {
    local repertoire="$1" destination="$2"
    {
        printf 'contenu de %s\n' "$repertoire"
        find "$repertoire" -mindepth 1 -printf '%y %s %P\n' 2>/dev/null | sort
    } > "$destination"
}

REP_COURANT_VIDE="$REP_TMP/cwd-vide"
mkdir -p "$REP_COURANT_VIDE"
contenu_repertoire "$REP_COURANT_VIDE" "$REP_TMP/cwd-avant"

lancer_depuis "$REP_COURANT_VIDE" env SRV_SWAP_SIZE=512M bash "$SWAP_SH" --file 2G
assert_code 2 "$CODE" "configure-swap.sh --file 2G : erreur d'usage"
assert_contient "$(erreur)" "[ERROR] Chemin relatif refusé pour --file : « 2G »." \
    "configure-swap.sh --file 2G : nomme le chemin relatif refusé"
assert_absent "$(erreur)" "Échec (code" \
    "configure-swap.sh --file 2G : le trap ERR n'ajoute aucune ligne au diagnostic"
assert_egal "3" "$(nb_lignes_contenant '[ERROR]')" \
    "configure-swap.sh --file 2G : stderr porte les trois lignes du refus, pas une de plus"
# Le refus a lieu AVANT tout : ni résumé des opérations, ni création. C'est
# cette paire d'absences qui rougit si la contrainte de chemin absolu tombe —
# le relevé de répertoire ci-dessous, lui, resterait vert, le script effaçant
# de lui-même le fichier qu'il vient de créer quand swapon échoue.
assert_absent "$(erreur)" "Opérations prévues" \
    "configure-swap.sh --file 2G : aucune opération n'est même envisagée"
assert_absent "$(erreur)" "Création de" \
    "configure-swap.sh --file 2G : aucun fichier d'échange n'est créé"

contenu_repertoire "$REP_COURANT_VIDE" "$REP_TMP/cwd-apres"
assert_empreinte_egale "$REP_TMP/cwd-avant" "$REP_TMP/cwd-apres" \
    "configure-swap.sh --file 2G ne dépose rien dans le répertoire courant"

# c. Le refus tient à l'ABSENCE de chemin absolu, et non à la ressemblance de
# « 2G » avec une taille : un chemin relatif ordinaire est refusé de la même
# façon. Sans ce cas, une correction qui se contenterait de rejeter les tailles
# passerait le cas b.
lancer bash "$SWAP_SH" 512M --file essai/swapfile
assert_code 2 "$CODE" "configure-swap.sh --file essai/swapfile : erreur d'usage"
assert_contient "$(erreur)" "[ERROR] Chemin relatif refusé pour --file : « essai/swapfile »." \
    "configure-swap.sh --file essai/swapfile : nomme le chemin relatif refusé"

# d. Non-régression : « --file » sans valeur rend toujours 2, avec le message
# exact que la section 1 de ce groupe épingle. Le durcissement de TASK-017 a
# laissé ce contrôle intact — les assertions de la section 1 sont la preuve, et
# celle-ci n'a donc pas à être dupliquée ici.

# --- 6. La NATURE de la cible de --file est contrôlée — TASK-019 ------------
# TASK-017 a fermé la question de la FORME du chemin : absolu, sans tiret
# initial. Celle de sa NATURE restait entière, et c'est elle qui portait le
# risque réel. « configure-swap.sh 64M --file /etc/passwd » passait la
# validation de TASK-017, annonçait « créer /etc/passwd », demandait
# confirmation — et le « rm -f » de la création SUPPRIMAIT le fichier sur un
# simple oui. Un répertoire, lui, faisait mourir le script sur le message brut
# « rm: cannot remove … : Is a directory », doublé de la ligne du trap ERR.
#
# Ces cas meurent tous à l'analyse des arguments, avant require_root et avant
# afficher_etat : leur stderr ne porte donc QUE les lignes du refus, ce qui rend
# un décompte exact possible — et c'est cette forme d'assertion, pas celle de
# contenu, qui verrait revenir une ligne de trap ou un message de rm. Le
# rédacteur des tests de TASK-017 avait posé un tel décompte de tête sans jamais
# l'observer ; ici il est MESURÉ, refus par refus, et les chiffres viennent de
# l'exécution.
#
# Le groupe reste non modifiant : les cibles jetables sont créées dans REP_TMP,
# hors de l'empreinte de /etc comme du champ d'ecritures_depuis.
#
# LE PLACEMENT DE « -y » N'EST PAS LIBRE, et c'est une précaution contre le test
# lui-même. Un cas qui arme ASSUME_YES ouvre au script la voie de l'exécution
# réelle : si le contrôle que ce cas éprouve venait à tomber, le script créerait
# et activerait un fichier d'échange et compléterait /etc/fstab — sur la machine
# où le test tourne. « -y » n'est donc armé que dans les cas GARDÉS PAR JETABLE.
# Ailleurs, « lancer » ferme l'entrée standard : confirm() y lit une réponse
# vide et refuse, et rien ne peut être écrit même si le refus n'a pas lieu.

# refus_de_cible <libellé> <ligne attendue> — le tronc commun des refus.
#
# Les cinq assertions d'absence seraient creuses sur un stderr vide ou mal
# capturé : elles sont donc encadrées par la ligne de diagnostic exigée juste
# avant et par les deux décomptes qui les suivent. Le flux doit contenir
# exactement ce qu'on y attend, et rien d'autre.
#
# Les DEUX formes de confirmation sont épinglées, parce que confirm() en a deux :
# « Confirmation automatique : … » quand ASSUME_YES est armée, et l'invite
# « Appliquer ces opérations ? [o/N] » sinon. Un cas qui n'arme pas « -y » ne
# prouverait rien de la première ; il prouve la seconde, et c'est la même
# frontière — le refus tombe avant que la question ne soit seulement posée.
refus_de_cible() {
    local libelle="$1" ligne="$2"

    assert_code 2 "$CODE" "$libelle : erreur d'usage"
    assert_contient "$(erreur)" "$ligne" \
        "$libelle : nomme la cible et ce qu'elle est"
    assert_absent "$(erreur)" "rm: cannot remove" \
        "$libelle : le rm -f n'est jamais atteint"
    assert_absent "$(erreur)" "Échec (code" \
        "$libelle : le trap ERR n'ajoute aucune ligne au diagnostic"
    assert_absent "$(erreur)" "Confirmation automatique" \
        "$libelle : aucune confirmation automatique n'est prononcée"
    assert_absent "$(erreur)" "Appliquer ces opérations ?" \
        "$libelle : le refus tombe avant que la question ne soit posée"
    assert_absent "$(erreur)" "Opérations prévues" \
        "$libelle : aucune opération n'est même envisagée"
    assert_egal "4" "$(nb_lignes_contenant '[ERROR]')" \
        "$libelle : stderr porte les quatre lignes du refus, pas une de plus"
    assert_egal "4" "$(nb_lignes_erreur)" \
        "$libelle : stderr ne porte rien d'autre que ces quatre lignes"
}

# a. Un fichier ordinaire existant — le cas qui motive la tâche, joué sur une
#    cible JETABLE pour qu'il puisse tourner partout, y compris hors conteneur.
#
#    Sans « -y », délibérément : voir la note ci-dessus. Ce que ce cas prouve de
#    la confirmation est l'absence de l'INVITE ; le cas b, gardé, prouve celle de
#    la confirmation automatique.
FICHIER_ORDINAIRE="$REP_TMP/fichier-ordinaire"
printf 'contenu qui ne doit pas disparaître\n' > "$FICHIER_ORDINAIRE"
ORDINAIRE_AVANT="$(empreinte_fichier "$FICHIER_ORDINAIRE")"
assert_absent "$ORDINAIRE_AVANT" "ABSENT" \
    "garde : la cible ordinaire existe bien avant l'appel"

lancer bash "$SWAP_SH" 64M --file "$FICHIER_ORDINAIRE"
refus_de_cible "configure-swap.sh --file <fichier ordinaire>" \
    "[ERROR] Cible refusée pour --file : « $FICHIER_ORDINAIRE » existe et n'est pas un fichier d'échange."
assert_egal "$ORDINAIRE_AVANT" "$(empreinte_fichier "$FICHIER_ORDINAIRE")" \
    "configure-swap.sh --file <fichier ordinaire> : le fichier est intact, au contenu et à l'inode"

# b. /etc/passwd — la cible exacte de l'énoncé de TASK-019, « -y » compris.
#
#    Ce cas CONFIE /etc/passwd à un script qu'on soupçonne précisément de le
#    supprimer : tant que le contrôle tient, il ne se passe rien ; le jour où il
#    tombe, le système perd son fichier de comptes. Il ne s'exécute donc que sur
#    un système jetable, et se déclare NON EXÉCUTÉ ailleurs — le cas a, lui,
#    tourne partout et couvre la même branche du script.
#
#    L'ordre des options est celui de l'énoncé, « --file » puis « -y ». Le refus
#    tombe alors avant même que « -y » ne soit lu, et l'absence de « Confirmation
#    automatique » est ici doublement acquise. Le cas où elle MORD — ASSUME_YES
#    réellement armée quand le refus tombe — est celui du groupe 3 ter, où
#    « -y » n'est suivi d'aucun --file.
if [ "$JETABLE" != "true" ]; then
    saute "configure-swap.sh 64M --file /etc/passwd -y" \
        "ce cas confie /etc/passwd à un script soupçonné de le supprimer — réservé à un système jetable ; le cas a couvre la même branche sur une cible jetable"
else
    PASSWD_AVANT="$(empreinte_fichier /etc/passwd)"
    assert_absent "$PASSWD_AVANT" "ABSENT" \
        "garde : /etc/passwd existe bien avant l'appel"

    lancer bash "$SWAP_SH" 64M --file /etc/passwd -y
    refus_de_cible "configure-swap.sh 64M --file /etc/passwd -y" \
        "[ERROR] Cible refusée pour --file : « /etc/passwd » existe et n'est pas un fichier d'échange."
    assert_contient "$(erreur)" "[ERROR] Le script supprime sa cible avant de la recréer : ce fichier serait détruit." \
        "configure-swap.sh --file /etc/passwd : dit ce qui aurait été détruit"
    assert_absent "$(erreur)" "créer      /etc/passwd" \
        "configure-swap.sh --file /etc/passwd : la suppression n'est plus annoncée comme une création"
    assert_egal "$PASSWD_AVANT" "$(empreinte_fichier /etc/passwd)" \
        "configure-swap.sh 64M --file /etc/passwd -y : /etc/passwd est intact, au contenu et à l'inode"
fi

# c. Un répertoire — le cas mineur, celui du message brut de rm.
REP_CIBLE="$REP_TMP/rep-cible"
mkdir -p "$REP_CIBLE"
lancer bash "$SWAP_SH" 64M --file "$REP_CIBLE"
refus_de_cible "configure-swap.sh 64M --file <répertoire>" \
    "[ERROR] Cible refusée pour --file : « $REP_CIBLE » est un répertoire."
if [ -d "$REP_CIBLE" ]; then
    ok "configure-swap.sh --file <répertoire> : le répertoire est toujours là"
else
    ko "configure-swap.sh --file <répertoire> : le répertoire est toujours là" "$REP_CIBLE a disparu"
fi

# d. La racine — même nature, mais aucune erreur de frappe n'est plus proche du
#    désastre.
lancer bash "$SWAP_SH" 64M --file /
refus_de_cible "configure-swap.sh 64M --file /" \
    "[ERROR] Cible refusée pour --file : « / » est un répertoire."

# e. Un lien symbolique — refusé pour une autre raison, et le diagnostic la
#    nomme : le fichier d'échange remplacerait le lien, sa cible resterait en
#    place, et l'espace annoncé ne serait pas celui qui est occupé.
LIEN_CIBLE="$REP_TMP/lien-vers-fichier"
ln -sf "$FICHIER_ORDINAIRE" "$LIEN_CIBLE"
lancer bash "$SWAP_SH" 64M --file "$LIEN_CIBLE"
refus_de_cible "configure-swap.sh 64M --file <lien symbolique>" \
    "[ERROR] Lien symbolique refusé pour --file : « $LIEN_CIBLE »."
assert_egal "$ORDINAIRE_AVANT" "$(empreinte_fichier "$FICHIER_ORDINAIRE")" \
    "configure-swap.sh --file <lien symbolique> : la cible du lien est intacte"

# f. Les cinq refus valent AUSSI sans privilège — le second tour de TASK-019.
#
# La correction a donné un second paramètre à valider_fichier_swap, « avant-root »
# ou « apres-root », et diffère UN verdict selon le moment. Le risque d'un tel
# aiguillage est qu'il en diffère d'autres au passage : un refus qui ne tomberait
# plus qu'en root laisserait l'appelant sans « sudo » recevoir 1 — privilège
# manquant — pour une ligne de commande fautive, alors que la convention du dépôt
# réserve le 2 à l'usage et veut que les arguments soient jugés AVANT les
# privilèges.
#
# Les cinq mêmes refus sont donc rejoués sans privilège. Leurs cibles vivent dans
# un répertoire traversable par tous, et ce n'est pas un détail : sous REP_TMP,
# créé en mode 700, « nobody » ne pourrait même pas les voir, tous les chemins
# passeraient pour inexistants, et les cinq cas seraient verts sans rien prouver.
# Les gardes du cas g mesurent cette visibilité au lieu de la supposer.
REP_CIBLES="/tmp/mgnet-integration-cibles"
rm -rf "$REP_CIBLES"
mkdir -p "$REP_CIBLES/rep-visible"
chmod 755 "$REP_CIBLES" "$REP_CIBLES/rep-visible"
CIBLE_ORDINAIRE="$REP_CIBLES/ordinaire"
CIBLE_LIEN="$REP_CIBLES/lien"
CIBLE_600="$REP_CIBLES/illisible-600"
printf 'contenu qui ne doit pas disparaître\n' > "$CIBLE_ORDINAIRE"
chmod 644 "$CIBLE_ORDINAIRE"
ln -sf "$CIBLE_ORDINAIRE" "$CIBLE_LIEN"
printf 'ce fichier n%s est pas un fichier d%s échange\n' "'" "'" > "$CIBLE_600"
chmod 600 "$CIBLE_600"

if [ "$SANS_ROOT_DISPONIBLE" != "true" ]; then
    saute "les cinq refus de cible rejoués sans privilège" \
        "aucun lanceur ne parvient à abaisser l'UID sur cet hôte"
else
    sans_root bash "$SWAP_SH" 64M --file "$CIBLE_ORDINAIRE"
    refus_de_cible "configure-swap.sh --file <fichier ordinaire> sans privilège" \
        "[ERROR] Cible refusée pour --file : « $CIBLE_ORDINAIRE » existe et n'est pas un fichier d'échange."

    sans_root bash "$SWAP_SH" 64M --file "$REP_CIBLES/rep-visible"
    refus_de_cible "configure-swap.sh --file <répertoire> sans privilège" \
        "[ERROR] Cible refusée pour --file : « $REP_CIBLES/rep-visible » est un répertoire."

    sans_root bash "$SWAP_SH" 64M --file /
    refus_de_cible "configure-swap.sh --file / sans privilège" \
        "[ERROR] Cible refusée pour --file : « / » est un répertoire."

    sans_root bash "$SWAP_SH" 64M --file "$CIBLE_LIEN"
    refus_de_cible "configure-swap.sh --file <lien symbolique> sans privilège" \
        "[ERROR] Lien symbolique refusé pour --file : « $CIBLE_LIEN »."

    # /etc/passwd est en 644 : « nobody » le voit et le lit, le refus tombe donc
    # au même endroit qu'en root. Le cas est sans danger même si le contrôle
    # régressait — require_root arrêterait le script bien avant le « rm -f » — et
    # n'a donc pas besoin de la garde JETABLE du cas b.
    sans_root bash "$SWAP_SH" 64M --file /etc/passwd
    refus_de_cible "configure-swap.sh --file /etc/passwd sans privilège" \
        "[ERROR] Cible refusée pour --file : « /etc/passwd » existe et n'est pas un fichier d'échange."
fi

# g. Le SEUL verdict différé : la cible qui existe et n'est pas lisible.
#
# C'est la régression qu'a mesurée le relecteur. Une cible en mode 600 que
# l'appelant ne peut pas lire n'est pas une cible fautive : c'est un regard sans
# les droits. La juger à l'analyse des arguments rendait 2 à un appelant dont la
# ligne de commande était juste et à qui il ne manquait qu'un « sudo ». Le
# verdict est donc différé — require_root reproche le privilège, code 1 — et le
# second appel, « apres-root », tranche une fois les droits acquis.
#
# Les deux gardes ne sont pas décoratives. Si « nobody » ne VOYAIT pas la cible,
# le chemin passerait pour inexistant, le script irait jusqu'à require_root et
# rendrait 1 : la bonne réponse pour la mauvaise raison, et le cas resterait vert
# sous n'importe quelle mutation. Visible ET illisible pour l'appelant se mesure
# donc, et ne se suppose pas.
if [ "$EST_ROOT" != "true" ] || [ "$SANS_ROOT_DISPONIBLE" != "true" ]; then
    saute "le verdict différé sur une cible illisible" \
        "exige root pour poser une cible en 600 que le lanceur non privilégié ne puisse pas lire"
else
    # « stat » puis « cat », et non « bash -c "[ -e … ]" » : les deux mesurent la
    # même chose sans faire voyager d'expression à travers un « -c », forme que
    # l'analyse statique signale à raison (SC2016) comme une expansion qui n'aura
    # pas lieu là où on la lit. stat réussit si le chemin est VU — il ne demande
    # que le droit de traverser le répertoire ; cat échoue s'il n'est pas LISIBLE.
    lancer "${LANCEUR_SANS_ROOT[@]}" stat "$CIBLE_600"
    assert_code 0 "$CODE" \
        "garde : sans privilège, la cible en 600 est bien VUE — le chemin ne passe pas pour inexistant"
    lancer "${LANCEUR_SANS_ROOT[@]}" cat "$CIBLE_600"
    assert_code_non_nul "$CODE" \
        "garde : sans privilège, la cible en 600 n'est pas LISIBLE — le verdict a bien de quoi être différé"

    # Le cas de la régression : sans privilège, c'est 1 et non 2.
    sans_root bash "$SWAP_SH" 64M --file "$CIBLE_600"
    assert_code 1 "$CODE" \
        "configure-swap.sh --file <cible 600 illisible> sans privilège : le privilège manquant prime, code 1"
    assert_contient "$(erreur)" "[ERROR] Ce script doit être exécuté en root (ou via sudo)." \
        "configure-swap.sh --file <cible 600> sans privilège : c'est bien le privilège qui est reproché"
    assert_absent "$(erreur)" "Cible refusée pour --file" \
        "configure-swap.sh --file <cible 600> sans privilège : la cible n'est pas jugée sans les droits de la lire"
    assert_absent "$(erreur)" "Échec (code" \
        "configure-swap.sh --file <cible 600> sans privilège : le trap ERR n'ajoute aucune ligne"
    assert_egal "1" "$(nb_lignes_contenant '[ERROR]')" \
        "configure-swap.sh --file <cible 600> sans privilège : une seule ligne [ERROR], celle du privilège"

    # La même cible, EN ROOT. Le verdict différé aboutit alors — et il aboutit
    # sur le refus ORDINAIRE, ce qui est MESURÉ et non déduit : root lit un
    # fichier en 600, « [ ! -r ] » y est faux, et c'est la branche « existe et
    # n'est pas un fichier d'échange » qui tranche. Le refus tombe bien, en 2 :
    # la correction n'a ouvert aucun passage à une cible que le script
    # détruirait.
    lancer bash "$SWAP_SH" 64M --file "$CIBLE_600"
    refus_de_cible "configure-swap.sh --file <cible 600 illisible> en root" \
        "[ERROR] Cible refusée pour --file : « $CIBLE_600 » existe et n'est pas un fichier d'échange."
    assert_absent "$(empreinte_fichier "$CIBLE_600")" "ABSENT" \
        "configure-swap.sh --file <cible 600> en root : la cible est toujours là"

    # Ce que ce fichier NE prouve PAS, et pourquoi il ne le prouvera pas ici.
    #
    # La branche « apres-root » du cas illisible — celle qui dit « Vérifier les
    # droits de lecture sur ce chemin, ou en choisir un autre. » — exige un
    # fichier régulier que ROOT ne puisse pas lire. Quatre montages ont été
    # essayés dans ce conteneur, et les quatre ont échoué : mode 600, root passe
    # outre ; « setpriv --bounding-set=-dac_override,-dac_read_search » ;
    # « capsh --drop=cap_dac_override,cap_dac_read_search » ; « capsh --caps= ».
    # Dans les quatre cas « id -u » rend 0 et « [ -r ] » rend 0 — root conserve
    # le contournement DAC.
    #
    # Le message reste donc SANS PREUVE ici. Il n'est pas pour autant du code
    # mort dans l'absolu : NFS en root_squash, ou un refus MAC (SELinux,
    # AppArmor), rendent la branche atteignable sur un vrai serveur. Aucun de ces
    # montages n'est à portée du profil « debian ».
    saute_par_nature "le refus d'une cible illisible EN ROOT, et sa ligne « Vérifier les droits de lecture sur ce chemin »" \
        "root contourne les permissions DAC dans ce conteneur — quatre montages mesurés (mode 600, setpriv --bounding-set, capsh --drop, capsh --caps=), tous rendus lisibles"
fi

titre "1 ter. Privilèges et OS"

# --- Refus sans privilège ---------------------------------------------------
# require_root sort en 1 : dans ce dépôt, le code 2 est réservé à l'erreur
# d'usage. system-info.sh est absent de cette liste — son cas est l'inverse,
# et il est traité au groupe suivant.
if [ "$SANS_ROOT_DISPONIBLE" != "true" ]; then
    for script in $CINQ_MODIFIANTS; do
        saute "$(basename "$script") refuse de s'exécuter sans privilège" \
            "aucun lanceur ne parvient à abaisser l'UID sur cet hôte"
    done
else
    sans_root bash "$HOSTNAME_SH" essai-mgnet
    assert_code 1 "$CODE" "configure-hostname.sh refuse de s'exécuter sans privilège"
    assert_contient "$(erreur)" "doit être exécuté en root" "configure-hostname.sh dit pourquoi il refuse"

    sans_root bash "$TIMEZONE_SH" "$FUSEAU_CIBLE"
    assert_code 1 "$CODE" "configure-timezone.sh refuse de s'exécuter sans privilège"

    sans_root bash "$LOGGING_SH"
    assert_code 1 "$CODE" "configure-logging.sh refuse de s'exécuter sans privilège"

    sans_root bash "$SWAP_SH" 512M
    assert_code 1 "$CODE" "configure-swap.sh refuse de s'exécuter sans privilège"

    sans_root bash "$UPDATE_SH"
    assert_code 1 "$CODE" "update-system.sh refuse de s'exécuter sans privilège"

    # L'erreur d'usage prime sur le manque de privilège : sinon un appel mal
    # formé serait masqué par un message de permission. Les CINQ scripts sont
    # éprouvés, et non le seul update-system.sh : la garantie porte sur l'ORDRE
    # « arguments puis privilèges », qui se vérifie script par script.
    for script in $CINQ_MODIFIANTS; do
        nom="$(basename "$script")"
        sans_root bash "$script" --option-qui-n-existe-pas
        assert_code 2 "$CODE" "$nom sans privilège : l'option inconnue prime, code 2"
    done

    # Même ordre pour une VALEUR invalide : la validation précède require_root.
    # Ces trois cas sont le pendant exact des trois précédents — mêmes scripts,
    # mêmes arguments, mais valides — et c'est leur mise en regard qui prouve la
    # frontière d'ADR-0003 décision 10 : 1 quand la commande est juste et que
    # seul le privilège manque, 2 dès que la commande elle-même est fautive.
    sans_root bash "$HOSTNAME_SH" mon_serveur
    assert_code 2 "$CODE" "configure-hostname.sh sans privilège : le nom invalide prime, code 2"

    sans_root bash "$TIMEZONE_SH" Zone/Inexistante
    assert_code 2 "$CODE" "configure-timezone.sh sans privilège : le fuseau inconnu prime, code 2"

    sans_root bash "$SWAP_SH" abc
    assert_code 2 "$CODE" "configure-swap.sh sans privilège : la taille invalide prime, code 2"
    assert_absent "$(erreur)" "Échec (code" \
        "configure-swap.sh abc sans privilège : le trap ERR n'ajoute aucune ligne"

    rm -rf "$LOG_DIR_NOBODY"
fi

# --- Refus d'un OS non supporté --------------------------------------------
# update-system.sh est le seul des six à appeler require_os. /etc/os-release
# est un fichier ordinaire de l'image : le remplacer le temps d'un appel est le
# seul moyen d'éprouver ce refus sans une seconde image. Il est remis en place
# immédiatement, et l'empreinte du groupe suivant le vérifie.
if [ "$EST_ROOT" = "true" ] && [ "$JETABLE" = "true" ]; then
    cp /etc/os-release "$REP_TMP/os-release.origine"
    printf 'ID=fedora\nVERSION_ID="41"\nPRETTY_NAME="Fedora (simulée par le test)"\n' > /etc/os-release
    lancer bash "$UPDATE_SH" --dry-run
    cat "$REP_TMP/os-release.origine" > /etc/os-release

    assert_code 1 "$CODE" "update-system.sh refuse un OS non supporté"
    assert_contient "$(erreur)" "Distribution non supportée" "update-system.sh nomme la distribution refusée"

    if cmp -s /etc/os-release "$REP_TMP/os-release.origine"; then
        ok "/etc/os-release a été remis dans son état d'origine"
    else
        ko "/etc/os-release a été remis dans son état d'origine" "le fichier diffère de la sauvegarde"
    fi
else
    saute "refus d'un OS non supporté par update-system.sh" \
        "exige root sur un système jetable — /etc/os-release doit être remplacé le temps d'un appel"
fi

# ===================================================================
# 2. system-info.sh — lecture seule, sans privilège
# ===================================================================
# Le seul des six qu'aucun test d'exécution ne couvrait jusqu'ici au-delà de
# « --help ». C'est aussi le seul qui ne doit exiger aucun privilège.
titre "2. system-info.sh"

SECTIONS="Système Processeur Mémoire Stockage Réseau Identité"

empreinte "$REP_TMP/info-avant"
touch "$REP_TMP/temoin-info"

lancer bash "$INFO_SH"
assert_code 0 "$CODE" "system-info.sh sort en 0"

texte="$(sortie)"
for section in $SECTIONS; do
    assert_contient "$texte" "$section" "system-info.sh affiche la section « $section »"
done
assert_contient "$texte" "Distribution" "system-info.sh affiche la distribution"

empreinte "$REP_TMP/info-apres"
assert_empreinte_egale "$REP_TMP/info-avant" "$REP_TMP/info-apres" \
    "system-info.sh ne modifie aucun fichier"
assert_aucune_ecriture "$REP_TMP/temoin-info" \
    "system-info.sh n'écrit rien hors du répertoire de journaux"

# Critère 5 : sans privilège, et en 0.
if [ "$SANS_ROOT_DISPONIBLE" != "true" ]; then
    saute "system-info.sh s'exécute sans privilège" \
        "aucun lanceur ne parvient à abaisser l'UID sur cet hôte"
else
    sans_root bash "$INFO_SH"
    assert_code 0 "$CODE" "system-info.sh s'exécute sans privilège et sort en 0"
    assert_contient "$(sortie)" "Distribution" "system-info.sh non privilégié produit son rapport"
    rm -rf "$LOG_DIR_NOBODY"
fi

# Critère 4 pour ce script : deux exécutions de suite, système identique.
empreinte "$REP_TMP/info-idem-a"
lancer bash "$INFO_SH"
assert_code 0 "$CODE" "system-info.sh seconde exécution sort en 0"
empreinte "$REP_TMP/info-idem-b"
assert_empreinte_egale "$REP_TMP/info-idem-a" "$REP_TMP/info-idem-b" \
    "system-info.sh exécuté deux fois laisse le système identique"

# ===================================================================
# 2 bis. check-disk.sh — diagnostic de stockage, en lecture seule
# ===================================================================
# TASK-021. Septième script du domaine, et le second — avec system-info.sh — à
# ne rien modifier et à n'exiger aucun privilège. Son contrat tient en une
# phrase : IL REND 0 QUOI QU'IL CONSTATE. Seule une erreur d'usage rend 2.
#
# Ce groupe est placé ici, entre « system-info.sh » et « --dry-run », parce
# qu'il n'écrit RIEN : la garde d'état du groupe « idempotence » — qui compare
# l'empreinte relevée à l'ouverture du groupe 2 à celle relevée juste avant le
# groupe 4 — n'en est donc pas troublée. C'est vérifié plutôt que supposé, par
# l'empreinte et le « find -newer » des sections c et j.
#
# Ce que ce groupe éprouve, par ordre d'importance :
#
#   a. les refus en 2, ET l'ABSENCE DE TOUTE SORTIE avant le refus — les
#      arguments se valident avant que le premier chiffre ne soit lu ;
#   b. le chemin nominal, et surtout que LE TABLEAU N'EST PAS VIDE dans un
#      conteneur : « overlay » figure aux sections « Systèmes de fichiers » et
#      « Inodes ». Un filtre écrit naïvement afficherait un écran vide, et ce
#      fichier passerait au vert sans que rien ne le signale — c'est le piège
#      que TASK-021 nomme, et seul un DÉCOMPTE de lignes le voit ;
#   c. la lecture seule, empreinte de tout /etc et « find -newer » à l'appui ;
#   d. deux exécutions consécutives ;
#   e. LA DÉGRADATION, une commande en échec à la fois — df, du, lsblk,
#      lsblk absent, awk, sort. Chaque fois : un [WARN] nommant la cause,
#      « non disponible » à l'affichage, code 0, et AUCUNE ligne « Échec (code »
#      du trap ERR — le motif de TASK-018, qu'un script neuf ne doit pas
#      réintroduire ;
#   f. LA SORTIE PARTIELLE, régression la plus probable de ce script. « df » et
#      « du » rendent 1 dès qu'UN SEUL point de montage leur résiste, APRÈS
#      avoir écrit tout ce qu'ils ont pu. Le script décide sur le VIDE, jamais
#      sur le code. Qui « simplifierait » la gestion du code de retour casserait
#      cela sans qu'aucune autre assertion ne s'en aperçoive ;
#   g. le seuil, et le fait qu'il est ATTEINT (« -ge ») et non DÉPASSÉ
#      (« -gt ») : à occupation égale au seuil, le [WARN] doit sortir ;
#   h. les inodes non déclarés — « non disponible » plutôt qu'un pourcentage
#      faux ;
#   i. les trois bornes de l'analyse des répertoires : --top, la profondeur 1,
#      et « -x » qui interdit de franchir un point de montage.
#
# DEUX ASSERTIONS DE CE GROUPE ONT ÉTÉ RETOURNÉES, ET C'EST LE SCRIPT QUI A
# CHANGÉ. Toutes deux portaient, au premier tour, le commentaire « épinglé sans
# être approuvé » : le fichier de cas décrivait le comportement observé tout en
# disant en quoi il était faux. Les deux défauts ont été corrigés, les deux
# attentes suivent, et chacune porte à son endroit le diagnostic de ce qui a été
# tranché — sections e.7 et g bis.
#
#   défaut 1  un « awk » en échec sur /proc/partitions affichait « aucun
#             périphérique bloc visible », qui AFFIRME une absence, pendant que
#             son [WARN] disait « non disponible ». Un drapeau « lue » sépare
#             désormais l'ignorance du constat — et le cas e.8, nouveau, éprouve
#             l'AUTRE branche : sans lui, la correction se réduirait à un
#             message renommé ;
#   défaut 2  une valeur fautive de config/server.env rendait 2 pour le seuil et
#             0 pour le répertoire. La règle ne dépend plus que de l'ORIGINE :
#             ligne de commande fautive → 2, configuration fautive → [WARN],
#             repli, code 0. L'assertion décisive du groupe g bis n'est ni le
#             code ni le message, c'est LE TABLEAU EST PRODUIT.
#
# Un TROISIÈME site relève de la même règle et n'était couvert par rien : le
# refus d'un --repertoire à tiret ne s'applique plus qu'à la ligne de commande.
# Le groupe g ter le juge et le couvre, jusqu'au cas qui tranche — un répertoire
# réellement nommé « -x », que le script parcourt.
#
# CE QUI N'EST PAS COMPARÉ ICI : les deux sorties standard, octet pour octet.
# Mesuré — deux exécutions consécutives diffèrent d'une ligne, le total de /tmp
# ayant grossi entre les deux du fait du journal de lib/common.sh. Ce que
# l'idempotence exige de ce script-ci est ailleurs : le système inchangé (§d) et
# la même LISTE de systèmes de fichiers.
#
# La garde « P0 != A » du groupe 4 n'a pas de sens ici, et son absence est
# délibérée : elle interdit une idempotence prouvée à vide sur un script qui
# MODIFIE. Celui-ci ne modifie rien par contrat — exiger qu'il ait changé
# quelque chose au premier passage reviendrait à exiger qu'il viole ce contrat.
titre "2 bis. check-disk.sh"

CHECK_DISK_SH="$SYS/check-disk.sh"

# Témoin du groupe entier : AUCUNE des exécutions qui suivent, y compris celles
# sous stub et celle sans privilège, ne doit écrire hors du répertoire de
# journaux. Relevé ici, contrôlé en fin de groupe.
touch "$REP_TMP/temoin-disque-groupe"

# --- Outillage propre à ce script ------------------------------------------
# « valeur_de_ligne » existe déjà dans ce fichier, mais elle n'est définie qu'au
# groupe 3 quinquies, plus bas : un appel ici tomberait sur une commande
# introuvable. D'où ces lecteurs, nommés distinctement.

# valeur_ligne_disque <libellé> — la valeur affichée en face de ce libellé, sur
# le stdout du dernier « lancer ». Le remplissage étant calculé par le script à
# partir de la longueur du libellé, on lit la VALEUR et non la ligne entière.
valeur_ligne_disque() {
    local libelle="$1" ligne
    while IFS= read -r ligne || [ -n "$ligne" ]; do
        case "$ligne" in
            "  $libelle"*)
                ligne="${ligne#"  $libelle"}"
                while [ "${ligne# }" != "$ligne" ]; do
                    ligne="${ligne# }"
                done
                printf '%s' "$ligne"
                return 0
                ;;
        esac
    done < "$F_OUT"
    return 0
}

# section_disque <titre> — le corps d'une section de la sortie.
# Une section commence à son titre et s'arrête à la première ligne vide : c'est
# exactement la mise en page que « titre() » produit dans le script.
section_disque() {
    local titre_section="$1" ligne dans="non"
    while IFS= read -r ligne || [ -n "$ligne" ]; do
        if [ "$ligne" = "$titre_section" ]; then
            dans="oui"
            continue
        fi
        [ "$dans" = "oui" ] || continue
        if [ -z "$ligne" ]; then
            dans="non"
            continue
        fi
        printf '%s\n' "$ligne"
    done < "$F_OUT"
}

# montages_disque <titre de section> — les points de montage d'un tableau
# d'occupation, un par ligne, la ligne de tirets et l'en-tête écartés.
montages_disque() {
    local ligne montage
    while IFS= read -r ligne || [ -n "$ligne" ]; do
        case "$ligne" in
            '-'*|'  Monté sur'*) continue ;;
        esac
        read -r montage _ <<< "$ligne"
        [ -n "$montage" ] || continue
        printf '%s\n' "$montage"
    done < <(section_disque "$1")
}

# nb_montages <titre de section> — le nombre de lignes de ce tableau.
# C'EST LE DÉCOMPTE QUI VOIT UN TABLEAU VIDE. Une assertion de contenu, elle,
# resterait verte sur un écran blanc.
nb_montages() {
    local ligne n=0
    while IFS= read -r ligne || [ -n "$ligne" ]; do
        [ -n "$ligne" ] || continue
        n=$(( n + 1 ))
    done < <(montages_disque "$1")
    printf '%s' "$n"
}

# occupation_disque <titre de section> <point de montage> — le dernier champ de
# la ligne de ce montage, c'est-à-dire son pourcentage. Chaîne vide si le
# montage est absent, ou si sa ligne ne porte pas six champs.
occupation_disque() {
    local section="$1" cible="$2" ligne
    local -a champs
    while IFS= read -r ligne || [ -n "$ligne" ]; do
        case "$ligne" in
            '-'*|'  Monté sur'*) continue ;;
        esac
        read -r -a champs <<< "$ligne"
        [ "${#champs[@]}" -ge 6 ] || continue
        [ "${champs[0]}" = "$cible" ] || continue
        printf '%s' "${champs[$(( ${#champs[@]} - 1 ))]}"
        return 0
    done < <(section_disque "$section")
    return 0
}

# montage_present <titre de section> <point de montage> — appartenance EXACTE.
#
# « assert_contient » ne convient PAS pour « / » : c'est une sous-chaîne de tout
# point de montage, et l'assertion resterait verte sur une liste où la racine ne
# figure pas. Mesuré — sous la mutation qui ajoute « overlay » aux
# pseudo-systèmes écartés, la forme « assert_contient … "/" » ne rougissait pas,
# « /depot » et « /etc/hosts » suffisant à la satisfaire.
montage_present() {
    local section="$1" cible="$2" montage
    while IFS= read -r montage || [ -n "$montage" ]; do
        if [ "$montage" = "$cible" ]; then
            return 0
        fi
    done < <(montages_disque "$section")
    return 1
}

# chemins_classement — les répertoires listés par la section des consommateurs.
# L'en-tête « Taille  Répertoire » ouvre le tableau, qui court jusqu'à la fin du
# flux — la dernière ligne écrite par le script étant vide.
chemins_classement() {
    local ligne dans="non" chemin
    while IFS= read -r ligne || [ -n "$ligne" ]; do
        case "$ligne" in
            *"Taille  Répertoire") dans="oui"; continue ;;
        esac
        [ "$dans" = "oui" ] || continue
        [ -n "$ligne" ] || continue
        read -r _ chemin <<< "$ligne"
        [ -n "$chemin" ] || continue
        printf '%s\n' "$chemin"
    done < "$F_OUT"
}

# nb_entrees_classement — le nombre d'entrées du classement, pour éprouver --top.
nb_entrees_classement() {
    local ligne n=0
    while IFS= read -r ligne || [ -n "$ligne" ]; do
        [ -n "$ligne" ] || continue
        n=$(( n + 1 ))
    done < <(chemins_classement)
    printf '%s' "$n"
}

# nb_lignes_sortie_contenant <motif> — lignes de STDOUT portant ce motif.
# Le pendant de « nb_lignes_contenant », qui ne lit que stderr. Les tableaux de
# ce script partent sur stdout : sans ce décompte, « les deux tableaux ont
# dégradé » ne se distinguerait pas de « un seul l'a fait ».
nb_lignes_sortie_contenant() {
    local motif="$1" ligne n=0
    while IFS= read -r ligne || [ -n "$ligne" ]; do
        if contient "$ligne" "$motif"; then
            n=$(( n + 1 ))
        fi
    done < "$F_OUT"
    printf '%s' "$n"
}

# invariants_disque <libellé> — les quatre invariants de TOUTE dégradation de ce
# script, sur le dernier « lancer ». Le code 0 est l'assertion décisive ; les
# trois autres verrouillent le motif de TASK-018, qu'un script neuf pourrait
# réintroduire sans que personne ne le voie.
invariants_disque() {
    local libelle="$1"
    assert_code 0 "$CODE" "check-disk.sh, $libelle : sort en 0"
    assert_egal "0" "$(nb_lignes_contenant '[ERROR]')" \
        "check-disk.sh, $libelle : aucune ligne [ERROR] — ce n'est pas une erreur, c'est une lacune"
    assert_absent "$(erreur)" "Échec (code" \
        "check-disk.sh, $libelle : le trap ERR n'ajoute aucune ligne"
    assert_absent "$(erreur)" "check-disk.sh: line" \
        "check-disk.sh, $libelle : aucun message brut de bash sur stderr"
}

# refus_disque <libellé> <motif attendu> <arguments...>
# Le refus, et ce qui compte davantage : QUE RIEN N'AIT ÉTÉ PRODUIT AVANT LUI.
# Un stdout strictement vide est la seule forme qui le voie — une assertion
# d'absence de titre resterait verte sur un flux vide comme sur un flux mal
# capturé. Sa garde de contraste est le chemin nominal de la section b, qui
# exige au contraire un stdout riche.
refus_disque() {
    local libelle="$1" motif="$2"; shift 2

    lancer bash "$CHECK_DISK_SH" "$@"
    assert_code 2 "$CODE" "check-disk.sh refuse $libelle"
    assert_contient "$(erreur)" "$motif" "check-disk.sh, $libelle : la cause est nommée"
    assert_egal "1" "$(nb_lignes_contenant '[ERROR]')" \
        "check-disk.sh, $libelle : une seule ligne [ERROR]"
    assert_egal "1" "$(nb_lignes_erreur)" \
        "check-disk.sh, $libelle : stderr ne porte QUE ce diagnostic"
    assert_absent "$(erreur)" "Usage :" \
        "check-disk.sh, $libelle : l'aide n'est pas déversée sur stderr"
    assert_absent "$(erreur)" "Échec (code" \
        "check-disk.sh, $libelle : le trap ERR n'ajoute aucune ligne"
    assert_egal "" "$(sortie)" \
        "check-disk.sh, $libelle : AUCUNE sortie de diagnostic avant le refus"
}

# --- a. Aide et refus d'usage ----------------------------------------------
lancer bash "$CHECK_DISK_SH" --help
assert_code 0 "$CODE" "check-disk.sh --help sort en 0"
aide_disque="$(sortie)"
assert_contient "$aide_disque" "Usage : check-disk.sh" "check-disk.sh --help écrit son usage sur stdout"
assert_contient "$aide_disque" "--seuil <1-100>" "l'aide de check-disk.sh documente --seuil"
assert_contient "$aide_disque" "--repertoire <chemin>" "l'aide de check-disk.sh documente --repertoire"
assert_contient "$aide_disque" "--top <1-100>" "l'aide de check-disk.sh documente --top"
assert_contient "$aide_disque" "--sans-repertoires" "l'aide de check-disk.sh documente --sans-repertoires"
assert_contient "$aide_disque" "--tous" "l'aide de check-disk.sh documente --tous"
assert_contient "$aide_disque" "Défaut : 85" "l'aide de check-disk.sh donne la valeur par défaut du seuil"
assert_contient "$aide_disque" "SRV_DISK_SEUIL" "l'aide de check-disk.sh nomme l'origine du seuil"
assert_contient "$aide_disque" "SRV_DISK_REPERTOIRE" "l'aide de check-disk.sh nomme l'origine du répertoire"
assert_contient "$aide_disque" "Codes de retour :" "l'aide de check-disk.sh documente les codes de retour"
# La règle d'origine fait partie du contrat : l'aide doit la dire, sans quoi un
# appelant attendrait un 2 d'un server.env mal saisi et ne le verrait jamais.
assert_contient "$aide_disque" "erreur d'usage sur la LIGNE DE COMMANDE" \
    "l'aide de check-disk.sh borne le code 2 à la ligne de commande"
assert_contient "$aide_disque" "Une valeur fautive venue de config/server.env ne rend jamais 2" \
    "l'aide de check-disk.sh documente le repli d'une valeur de configuration fautive"
assert_egal "0" "$(nb_lignes_erreur)" "check-disk.sh --help n'écrit rien sur stderr"

lancer bash "$CHECK_DISK_SH" -h
assert_code 0 "$CODE" "check-disk.sh -h sort en 0"
assert_contient "$(sortie)" "Usage : check-disk.sh" "check-disk.sh -h écrit son usage sur stdout"

refus_disque "un seuil non numérique" \
    "[ERROR] --seuil : « abc » n'est pas un entier (ligne de commande)." \
    --seuil abc
refus_disque "un seuil nul" \
    "[ERROR] --seuil : « 0 » est hors bornes (ligne de commande)" \
    --seuil 0
refus_disque "un seuil de 101" \
    "[ERROR] --seuil : « 101 » est hors bornes (ligne de commande)" \
    --seuil 101
refus_disque "un --top nul" \
    "[ERROR] --top : « 0 » est hors bornes (ligne de commande)" \
    --top 0
refus_disque "un répertoire inexistant" \
    "[ERROR] --repertoire : « /pas/la » n'est pas un répertoire" \
    --repertoire /pas/la
refus_disque "une option inconnue" \
    "[ERROR] Option inconnue : --option-qui-n-existe-pas" \
    --option-qui-n-existe-pas
refus_disque "un --seuil sans valeur" \
    "[ERROR] --seuil attend un entier de 1 à 100." \
    --seuil
# Le piège que l'aide du script annonce : sans ce contrôle, « --tous » devient
# le répertoire analysé et l'option demandée disparaît en silence.
#
# Ce contrôle ne s'applique plus qu'à la LIGNE DE COMMANDE. Sa moitié « venu de
# config/server.env » — où il n'y a aucun jeton suivant à avaler — est éprouvée
# en g ter. Ces deux refus-ci sont la moitié qui doit rester en 2 : un correctif
# qui aurait retiré le contrôle au lieu de le conditionner les ferait rougir.
refus_disque "un --repertoire suivi d'une option" \
    "[ERROR] --repertoire : « --tous » commence par un tiret" \
    --repertoire --tous
refus_disque "un --repertoire à valeur courte commençant par un tiret" \
    "[ERROR] --repertoire : « -x » commence par un tiret (ligne de commande) — c'est une option, pas un chemin." \
    --repertoire -x

# --- b. Chemin nominal — et le tableau n'est PAS vide -----------------------
empreinte "$REP_TMP/disque-avant"
touch "$REP_TMP/temoin-disque"

lancer bash "$CHECK_DISK_SH"
invariants_disque "chemin nominal"

texte_disque="$(sortie)"
SECTIONS_DISQUE=(
    "Diagnostic de stockage"
    "Systèmes de fichiers"
    "Inodes"
    "Périphériques et partitions"
    "Répertoires les plus consommateurs"
)
for section in "${SECTIONS_DISQUE[@]}"; do
    assert_contient "$texte_disque" "$section" "check-disk.sh affiche la section « $section »"
done

# Le rappel des paramètres et de leur ORIGINE, en tête de la sortie.
assert_egal "85 % (valeur par défaut)" "$(valeur_ligne_disque "Seuil d'alerte")" \
    "check-disk.sh rappelle le seuil et son origine"
assert_egal "pseudo-systèmes écartés, overlay conservé" "$(valeur_ligne_disque "Filtre")" \
    "check-disk.sh rappelle le filtre appliqué"
assert_egal "/ (valeur par défaut)" "$(valeur_ligne_disque "Répertoire analysé")" \
    "check-disk.sh rappelle le répertoire analysé et son origine"
assert_egal "10 (valeur par défaut)" "$(valeur_ligne_disque "Entrées affichées")" \
    "check-disk.sh rappelle le nombre d'entrées et son origine"

# L'ASSERTION QUI VOIT L'ÉCRAN VIDE. Un filtre qui écarterait « overlay » —
# « ne garder que ext4, xfs, btrfs » — ne produirait AUCUNE ligne ici, et toutes
# les assertions de contenu de ce groupe resteraient vertes sur un tableau vide.
# Seul le décompte le voit.
NB_FS_DEFAUT="$(nb_montages "Systèmes de fichiers")"
if [ "$NB_FS_DEFAUT" -ge 1 ]; then
    ok "check-disk.sh : le tableau des systèmes de fichiers n'est PAS vide — $NB_FS_DEFAUT ligne(s)"
else
    ko "check-disk.sh : le tableau des systèmes de fichiers n'est PAS vide" \
        "aucune ligne retenue par le filtre — l'écran est vide"
fi
NB_INODES_DEFAUT="$(nb_montages "Inodes")"
if [ "$NB_INODES_DEFAUT" -ge 1 ]; then
    ok "check-disk.sh : le tableau des inodes n'est PAS vide — $NB_INODES_DEFAUT ligne(s)"
else
    ko "check-disk.sh : le tableau des inodes n'est PAS vide" "aucune ligne — l'écran est vide"
fi

# « overlay » nommément : c'est le système de fichiers de la racine d'un
# conteneur, et le seul que celui-ci ait à montrer.
TYPE_RACINE=""
if command -v df >/dev/null 2>&1; then
    TYPE_RACINE="$(df -P -T / 2>/dev/null | awk 'NR == 2 { print $2 }')" || TYPE_RACINE=""
fi
if [ "$TYPE_RACINE" != "overlay" ]; then
    saute "check-disk.sh conserve « overlay » aux deux tableaux d'occupation" \
        "la racine de cet hôte est de type « ${TYPE_RACINE:-inconnu} » et non « overlay » — le piège du tableau vide ne s'y reproduit pas"
else
    assert_contient "$(section_disque "Systèmes de fichiers")" "overlay" \
        "check-disk.sh n'écarte PAS « overlay » du tableau des systèmes de fichiers"
    assert_contient "$(section_disque "Inodes")" "overlay" \
        "check-disk.sh n'écarte PAS « overlay » du tableau des inodes"
    if montage_present "Systèmes de fichiers" "/"; then
        ok "check-disk.sh affiche la racine « / » parmi les systèmes de fichiers"
    else
        ko "check-disk.sh affiche la racine « / » parmi les systèmes de fichiers" \
            "liste obtenue : $(montages_disque "Systèmes de fichiers" | tr '\n' ' ')"
    fi
    if montage_present "Inodes" "/"; then
        ok "check-disk.sh affiche la racine « / » parmi les tableaux d'inodes"
    else
        ko "check-disk.sh affiche la racine « / » parmi les tableaux d'inodes" \
            "liste obtenue : $(montages_disque "Inodes" | tr '\n' ' ')"
    fi
fi

# La racine porte bien un POURCENTAGE, et non une cellule vide.
OCCUP_RACINE="$(occupation_disque "Systèmes de fichiers" "/")"
case "$OCCUP_RACINE" in
    [0-9]*%) ok "check-disk.sh affiche l'occupation de la racine — « $OCCUP_RACINE »" ;;
    *)       ko "check-disk.sh affiche l'occupation de la racine" \
                "valeur obtenue « $OCCUP_RACINE », un pourcentage était attendu" ;;
esac

# GARDES DE CONTRASTE de tout le reste du groupe. Sans elles, un « non
# disponible » constaté sous stub pourrait venir d'ailleurs.
assert_egal "" "$(valeur_ligne_disque "Occupation")" \
    "garde : sans stub, aucune ligne « Occupation » — les deux tableaux sont bien produits"
assert_egal "" "$(valeur_ligne_disque "Analyse")" \
    "garde : sans stub, aucune ligne « Analyse » — la section des répertoires est bien produite"
TOTAL_NOMINAL="$(valeur_ligne_disque "Total (ce montage)")"
if [ -n "$TOTAL_NOMINAL" ] && [ "$TOTAL_NOMINAL" != "non disponible" ]; then
    ok "garde : sans stub, le total du répertoire analysé est une vraie valeur — « $TOTAL_NOMINAL »"
else
    ko "garde : sans stub, le total du répertoire analysé est une vraie valeur" \
        "valeur obtenue « $TOTAL_NOMINAL » — les cas dégradés ne prouveraient rien"
fi
NB_CLASSEMENT_NOMINAL="$(nb_entrees_classement)"
if [ "$NB_CLASSEMENT_NOMINAL" -ge 1 ]; then
    ok "garde : sans stub, le classement des répertoires porte $NB_CLASSEMENT_NOMINAL entrée(s)"
else
    ko "garde : sans stub, le classement des répertoires n'est pas vide" "aucune entrée"
fi
NB_PERIPH_NOMINAL="$(nb_montages "Périphériques et partitions")"
if [ "$NB_PERIPH_NOMINAL" -ge 1 ]; then
    ok "garde : sans stub, la section des périphériques porte $NB_PERIPH_NOMINAL ligne(s)"
else
    ko "garde : sans stub, la section des périphériques n'est pas vide" "aucune ligne"
fi

# L'autre moitié du filtre : les pseudo-systèmes sont bien écartés par défaut.
if ! df -P -T 2>/dev/null | awk 'NR > 1 && $2 == "tmpfs" { trouve = 1 } END { exit !trouve }'; then
    saute "check-disk.sh écarte les pseudo-systèmes de fichiers par défaut" \
        "cet hôte ne monte aucun tmpfs — le filtre n'aurait rien à écarter, le cas ne prouverait rien"
else
    assert_absent "$(section_disque "Systèmes de fichiers")" "tmpfs" \
        "check-disk.sh écarte les pseudo-systèmes (tmpfs) du tableau par défaut"
fi

# --- c. La lecture seule, prouvée ------------------------------------------
empreinte "$REP_TMP/disque-apres"
assert_empreinte_egale "$REP_TMP/disque-avant" "$REP_TMP/disque-apres" \
    "check-disk.sh ne modifie aucun fichier"
assert_aucune_ecriture "$REP_TMP/temoin-disque" \
    "check-disk.sh n'écrit rien hors du répertoire de journaux"

# --- d. Deux exécutions consécutives ---------------------------------------
# Ce qui est comparé : le système, et la LISTE des systèmes de fichiers. Pas les
# deux sorties octet pour octet — mesuré, elles diffèrent d'une ligne, le total
# de /tmp ayant grossi du journal que lib/common.sh venait d'y écrire.
empreinte "$REP_TMP/disque-idem-a"
lancer bash "$CHECK_DISK_SH"
assert_code 0 "$CODE" "check-disk.sh seconde exécution sort en 0"
MONTAGES_IDEM_A="$(montages_disque "Systèmes de fichiers")"
lancer bash "$CHECK_DISK_SH"
assert_code 0 "$CODE" "check-disk.sh troisième exécution sort en 0"
MONTAGES_IDEM_B="$(montages_disque "Systèmes de fichiers")"
empreinte "$REP_TMP/disque-idem-b"
assert_empreinte_egale "$REP_TMP/disque-idem-a" "$REP_TMP/disque-idem-b" \
    "check-disk.sh exécuté deux fois laisse le système identique"
assert_egal "$MONTAGES_IDEM_A" "$MONTAGES_IDEM_B" \
    "check-disk.sh exécuté deux fois liste les mêmes systèmes de fichiers"

# --- e. La dégradation, une commande en échec à la fois ---------------------
# Un binaire homonyme en tête de PATH : la mutation la moins coûteuse du dépôt,
# et celle qui a démenti quatre arbitrages de non-traitement au chantier
# TASK-018. « command -v df » établit que la commande existe, pas qu'elle
# réussit.
REP_STUB_DISQUE_DF="$REP_TMP/stub-disque-df"
REP_STUB_DISQUE_DU="$REP_TMP/stub-disque-du"
REP_STUB_DISQUE_LSBLK="$REP_TMP/stub-disque-lsblk"
REP_STUB_DISQUE_AWK="$REP_TMP/stub-disque-awk"
REP_STUB_DISQUE_SORT="$REP_TMP/stub-disque-sort"
REP_STUB_DISQUE_DF_PARTIEL="$REP_TMP/stub-disque-df-partiel"
REP_STUB_DISQUE_DF_PLEIN="$REP_TMP/stub-disque-df-plein"
REP_STUB_DISQUE_DF_INODES="$REP_TMP/stub-disque-df-inodes"
REP_SANS_LSBLK="$REP_TMP/bin-sans-lsblk"

mkdir -p "$REP_STUB_DISQUE_DF" "$REP_STUB_DISQUE_DU" "$REP_STUB_DISQUE_LSBLK" \
    "$REP_STUB_DISQUE_AWK" "$REP_STUB_DISQUE_SORT" "$REP_STUB_DISQUE_DF_PARTIEL" \
    "$REP_STUB_DISQUE_DF_PLEIN" "$REP_STUB_DISQUE_DF_INODES"

printf '#!/bin/sh\nexit 1\n' > "$REP_STUB_DISQUE_DF/df"
printf '#!/bin/sh\nexit 1\n' > "$REP_STUB_DISQUE_DU/du"
printf '#!/bin/sh\nexit 1\n' > "$REP_STUB_DISQUE_LSBLK/lsblk"
printf '#!/bin/sh\nexit 1\n' > "$REP_STUB_DISQUE_AWK/awk"
printf '#!/bin/sh\nexit 1\n' > "$REP_STUB_DISQUE_SORT/sort"
chmod +x "$REP_STUB_DISQUE_DF/df" "$REP_STUB_DISQUE_DU/du" \
    "$REP_STUB_DISQUE_LSBLK/lsblk" "$REP_STUB_DISQUE_AWK/awk" \
    "$REP_STUB_DISQUE_SORT/sort"

# garde_stub_echoue <nom> <commande...> — sans elle, un stub mal posé rendrait
# le cas vert pour la plus mauvaise des raisons : la commande n'a jamais échoué.
garde_stub_echoue() {
    local nom="$1"; shift
    if "$@" >/dev/null 2>&1; then
        ko "garde : le faux « $nom » échoue bien" "le stub a rendu 0"
    else
        ok "garde : le faux « $nom » échoue bien"
    fi
}

garde_stub_echoue "df" "$REP_STUB_DISQUE_DF/df" -P -T -h
garde_stub_echoue "du" "$REP_STUB_DISQUE_DU/du" -x -h --max-depth=1 -- /
garde_stub_echoue "lsblk" "$REP_STUB_DISQUE_LSBLK/lsblk"
garde_stub_echoue "awk" "$REP_STUB_DISQUE_AWK/awk" '{ print }' /etc/hostname
garde_stub_echoue "sort" "$REP_STUB_DISQUE_SORT/sort" /etc/hostname

# e.1 — « df » en échec : les DEUX tableaux d'occupation dégradent.
lancer env "PATH=$REP_STUB_DISQUE_DF:$PATH" bash "$CHECK_DISK_SH"
invariants_disque "« df » en échec"
assert_contient "$(erreur)" "[WARN] « df » a échoué : occupation des systèmes de fichiers non disponible." \
    "check-disk.sh, « df » en échec : la cause est nommée pour les systèmes de fichiers"
assert_contient "$(erreur)" "[WARN] « df -i » a échoué : occupation des inodes non disponible." \
    "check-disk.sh, « df » en échec : la cause est nommée pour les inodes"
assert_egal "2" "$(nb_lignes_contenant '[WARN]')" \
    "check-disk.sh, « df » en échec : deux avertissements mesurés, un par tableau"
assert_egal "non disponible" "$(valeur_ligne_disque "Occupation")" \
    "check-disk.sh, « df » en échec : l'occupation dégrade en « non disponible »"
assert_egal "2" "$(nb_lignes_sortie_contenant "non disponible")" \
    "check-disk.sh, « df » en échec : les DEUX tableaux dégradent, et pas seulement le premier"
assert_contient "$(sortie)" "Périphériques et partitions" \
    "check-disk.sh, « df » en échec : les sections suivantes sont toujours produites"
if [ "$(nb_entrees_classement)" -ge 1 ]; then
    ok "check-disk.sh, « df » en échec : le classement des répertoires est produit malgré tout"
else
    ko "check-disk.sh, « df » en échec : le classement des répertoires est produit malgré tout" \
        "aucune entrée — une dégradation en a emporté une autre"
fi

# e.2 — « du » en échec.
lancer env "PATH=$REP_STUB_DISQUE_DU:$PATH" bash "$CHECK_DISK_SH"
invariants_disque "« du » en échec"
assert_contient "$(erreur)" "[WARN] « du » n'a rien pu lire sous « / » : répertoires consommateurs non disponibles." \
    "check-disk.sh, « du » en échec : la cause est nommée"
assert_egal "1" "$(nb_lignes_contenant '[WARN]')" \
    "check-disk.sh, « du » en échec : un seul avertissement mesuré"
assert_egal "non disponible" "$(valeur_ligne_disque "Analyse")" \
    "check-disk.sh, « du » en échec : l'analyse dégrade en « non disponible »"
if [ "$(nb_montages "Systèmes de fichiers")" -ge 1 ]; then
    ok "check-disk.sh, « du » en échec : le tableau des systèmes de fichiers est intact"
else
    ko "check-disk.sh, « du » en échec : le tableau des systèmes de fichiers est intact" "tableau vide"
fi

# e.3 — « lsblk » en ÉCHEC : repli sur /proc/partitions.
lancer env "PATH=$REP_STUB_DISQUE_LSBLK:$PATH" bash "$CHECK_DISK_SH"
invariants_disque "« lsblk » en échec"
assert_contient "$(erreur)" "[WARN] « lsblk » a échoué : repli sur /proc/partitions." \
    "check-disk.sh, « lsblk » en échec : la cause est nommée et le repli annoncé"
assert_contient "$(section_disque "Périphériques et partitions")" "Taille" \
    "check-disk.sh, « lsblk » en échec : le repli /proc/partitions produit son en-tête"
if [ "$(nb_montages "Périphériques et partitions")" -ge 2 ]; then
    ok "check-disk.sh, « lsblk » en échec : le repli /proc/partitions liste des périphériques"
else
    ko "check-disk.sh, « lsblk » en échec : le repli /proc/partitions liste des périphériques" \
        "la section est vide ou réduite à son en-tête"
fi

# e.4 — « lsblk » ABSENT : c'est le critère d'acceptation, et il ne se prouve
# pas en mettant la commande en échec. « command -v lsblk » réussirait encore et
# la branche « introuvable » resterait fermée. Un bac à sable de liens
# symboliques reproduit le PATH sans lui, et rien n'est touché sur le système.
mkdir -p "$REP_SANS_LSBLK"
for repertoire in /usr/local/sbin /usr/local/bin /usr/sbin /usr/bin /sbin /bin; do
    [ -d "$repertoire" ] || continue
    for binaire in "$repertoire"/*; do
        nom="${binaire##*/}"
        [ "$nom" != "lsblk" ] || continue
        [ -e "$REP_SANS_LSBLK/$nom" ] || ln -s "$binaire" "$REP_SANS_LSBLK/$nom" 2>/dev/null || true
    done
done
if PATH="$REP_SANS_LSBLK" command -v lsblk >/dev/null 2>&1; then
    ko "garde : « lsblk » est bien masqué dans le bac à sable" \
        "il y reste visible — la branche « introuvable » ne serait pas atteinte"
else
    ok "garde : « lsblk » est bien masqué dans le bac à sable"
fi

lancer env "PATH=$REP_SANS_LSBLK" bash "$CHECK_DISK_SH"
invariants_disque "« lsblk » absent"
assert_contient "$(erreur)" "[WARN] « lsblk » est introuvable : repli sur /proc/partitions." \
    "check-disk.sh, « lsblk » absent : l'absence est nommée et le repli annoncé"
if [ "$(nb_montages "Périphériques et partitions")" -ge 2 ]; then
    ok "check-disk.sh, « lsblk » absent : le repli /proc/partitions liste des périphériques"
else
    ko "check-disk.sh, « lsblk » absent : le repli /proc/partitions liste des périphériques" \
        "la section est vide ou réduite à son en-tête"
fi

# e.5 — « awk » en échec. Deux sites de la section des répertoires : le total et
# le classement. Le troisième site — l'awk de /proc/partitions — n'est atteint
# que si lsblk n'a rien donné ; il est éprouvé en e.7.
lancer env "PATH=$REP_STUB_DISQUE_AWK:$PATH" bash "$CHECK_DISK_SH"
invariants_disque "« awk » en échec"
assert_contient "$(erreur)" "[WARN] « awk » a échoué : total de « / » non disponible." \
    "check-disk.sh, « awk » en échec : le total nomme sa cause"
assert_contient "$(erreur)" "[WARN] Classement des répertoires non disponible : « awk » ou « sort » a échoué." \
    "check-disk.sh, « awk » en échec : le classement nomme sa cause"
assert_egal "2" "$(nb_lignes_contenant '[WARN]')" \
    "check-disk.sh, « awk » en échec : deux avertissements mesurés, un par site"
assert_egal "non disponible" "$(valeur_ligne_disque "Total (ce montage)")" \
    "check-disk.sh, « awk » en échec : le total dégrade en « non disponible »"
assert_egal "aucun" "$(valeur_ligne_disque "Sous-répertoires")" \
    "check-disk.sh, « awk » en échec : le classement dégrade en « aucun »"
if [ "$(nb_montages "Systèmes de fichiers")" -ge 1 ]; then
    ok "check-disk.sh, « awk » en échec : les tableaux d'occupation sont intacts"
else
    ko "check-disk.sh, « awk » en échec : les tableaux d'occupation sont intacts" "tableau vide"
fi

# e.6 — « sort » en échec. Un seul site : le classement. Le total, lui, reste
# une vraie valeur — c'est ce qui distingue ce cas du précédent, et ce qui
# prouve que le pipeline n'a pas été jeté en bloc.
lancer env "PATH=$REP_STUB_DISQUE_SORT:$PATH" bash "$CHECK_DISK_SH"
invariants_disque "« sort » en échec"
assert_contient "$(erreur)" "[WARN] Classement des répertoires non disponible : « awk » ou « sort » a échoué." \
    "check-disk.sh, « sort » en échec : la cause est nommée"
assert_egal "1" "$(nb_lignes_contenant '[WARN]')" \
    "check-disk.sh, « sort » en échec : un seul avertissement mesuré"
assert_egal "aucun" "$(valeur_ligne_disque "Sous-répertoires")" \
    "check-disk.sh, « sort » en échec : le classement dégrade en « aucun »"
TOTAL_SOUS_SORT="$(valeur_ligne_disque "Total (ce montage)")"
if [ -n "$TOTAL_SOUS_SORT" ] && [ "$TOTAL_SOUS_SORT" != "non disponible" ]; then
    ok "check-disk.sh, « sort » en échec : le total reste une vraie valeur — « $TOTAL_SOUS_SORT »"
else
    ko "check-disk.sh, « sort » en échec : le total reste une vraie valeur" \
        "valeur obtenue « $TOTAL_SOUS_SORT » — la dégradation a débordé sur un site voisin"
fi

# e.7 — « awk » en échec SUR /proc/partitions. Ce site n'est atteint que si lsblk
# n'a rien donné : les deux montages se cumulent.
#
# ASSERTION RETOURNÉE — LE SCRIPT A ÉTÉ CORRIGÉ, PAS LE TEST PLIÉ.
#
# Ce cas attendait « aucun périphérique bloc visible ». Il l'attendait en le
# dénonçant : le [WARN] émis juste au-dessus disait « non disponible » —
# l'IGNORANCE, la table n'a pas pu être lue — pendant que la ligne affichée
# AFFIRMAIT une absence que personne n'avait établie. Les deux issues se
# rejoignaient sur le même appel à « ligne ».
#
# Ce qui a été tranché : « section_peripheriques » porte désormais un drapeau
# « lue » qui sépare les deux. Un « awk » en échec donne « non disponible », le
# mot que ce script emploie partout ailleurs pour une information hors
# d'atteinte ; « aucun périphérique bloc visible » reste réservé au cas où la
# table a bien été LUE et se trouve vide. C'est le vrai qui a changé, pas
# l'attente : l'assertion d'origine avait raison de gêner.
#
# Le cas e.8 éprouve l'AUTRE branche du même drapeau. Les deux vont ensemble :
# retourner celle-ci sans ouvrir celle-là reviendrait à renommer un message au
# lieu de vérifier qu'on en distingue bien deux.
lancer env "PATH=$REP_STUB_DISQUE_AWK:$REP_SANS_LSBLK" bash "$CHECK_DISK_SH" --sans-repertoires
invariants_disque "« awk » en échec sur /proc/partitions"
assert_contient "$(erreur)" "[WARN] « lsblk » est introuvable : repli sur /proc/partitions." \
    "check-disk.sh, awk + lsblk absent : le repli est bien emprunté"
assert_contient "$(erreur)" "[WARN] « awk » a échoué sur /proc/partitions : périphériques et partitions non disponibles." \
    "check-disk.sh, awk + lsblk absent : la cause est nommée"
assert_egal "non disponible" "$(valeur_ligne_disque "Périphériques")" \
    "check-disk.sh, awk + lsblk absent : la ligne affichée dit « non disponible » — l'ignorance, le même mot que le [WARN], et non une absence affirmée"
assert_absent "$(sortie)" "aucun périphérique bloc visible" \
    "check-disk.sh, awk + lsblk absent : aucune absence n'est AFFIRMÉE — la table n'a pas été lue"

# e.8 — LA TABLE A ÉTÉ LUE, ET ELLE EST VIDE. L'autre branche du drapeau « lue ».
#
# Sans ce cas, la correction du défaut 1 se réduirait à un message renommé :
# rien ne prouverait que « aucun périphérique bloc visible » reste atteignable,
# ni qu'il est réservé au constat. Un futur « simplificateur » qui remplacerait
# les deux issues par la seule « non disponible » ne ferait rougir personne.
#
# Le montage est un faux « awk » SÉLECTIF qui RÉUSSIT en ne produisant rien sur
# /proc/partitions, et délègue le reste au vrai awk. C'est la seule façon
# d'obtenir une table vide sans remonter /proc, ce qu'un conteneur ne permet pas.
REP_STUB_AWK_MUET="$REP_TMP/stub-disque-awk-muet"
mkdir -p "$REP_STUB_AWK_MUET"
# Les guillemets simples sont VOULUS : ces printf écrivent le CORPS d'un script,
# et « $argument » comme « $@ » doivent y arriver littéralement pour être
# développés par le stub à son exécution, pas ici. C'est ce que SC2016 signale,
# et c'est ce qu'on veut.
# shellcheck disable=SC2016
{
    printf '#!/bin/sh\n'
    printf 'for argument in "$@"; do\n'
    printf '    [ "$argument" = "/proc/partitions" ] || continue\n'
    printf '    exit 0\n'
    printf 'done\n'
    printf 'exec %s "$@"\n' "$(command -v awk)"
} > "$REP_STUB_AWK_MUET/awk"
chmod +x "$REP_STUB_AWK_MUET/awk"
if [ -z "$("$REP_STUB_AWK_MUET/awk" 'NR > 2 { print }' /proc/partitions)" ] \
    && "$REP_STUB_AWK_MUET/awk" 'NR > 2 { print }' /proc/partitions >/dev/null 2>&1; then
    ok "garde : le faux « awk » muet RÉUSSIT et ne produit rien sur /proc/partitions"
else
    ko "garde : le faux « awk » muet RÉUSSIT et ne produit rien sur /proc/partitions" \
        "le stub a échoué, ou a produit une table — la branche « lue et vide » ne serait pas atteinte"
fi
# shellcheck disable=SC2016
if [ -n "$("$REP_STUB_AWK_MUET/awk" '{ print $1 }' /proc/uptime)" ]; then
    ok "garde : le faux « awk » muet délègue tout le reste au vrai awk"
else
    ko "garde : le faux « awk » muet délègue tout le reste au vrai awk" \
        "le stub a intercepté une lecture qu'il devait déléguer"
fi

lancer env "PATH=$REP_STUB_AWK_MUET:$REP_SANS_LSBLK" bash "$CHECK_DISK_SH" --sans-repertoires
invariants_disque "table de périphériques lue et vide"
assert_egal "aucun périphérique bloc visible" "$(valeur_ligne_disque "Périphériques")" \
    "check-disk.sh, table lue et VIDE : l'absence est affirmée — c'est un constat, pas une ignorance"
assert_absent "$(erreur)" "« awk » a échoué sur /proc/partitions" \
    "check-disk.sh, table lue et vide : aucun échec d'awk n'est annoncé — awk a réussi"
assert_egal "1" "$(nb_lignes_contenant '[WARN]')" \
    "check-disk.sh, table lue et vide : le seul avertissement est celui de « lsblk » introuvable"

rm -rf "$REP_STUB_AWK_MUET"

# --- f. La sortie PARTIELLE — la régression la plus probable ----------------
# « df » et « du » rendent 1 dès qu'UN SEUL point de montage leur résiste, APRÈS
# avoir écrit tout ce qu'ils ont pu. Le script décide sur le VIDE, pas sur le
# code. Quelqu'un qui « simplifierait » la gestion du code de retour — un
# « if ! sortie=… ; then warn ; return ; fi » à la place du contrôle de vide —
# jetterait cette sortie-là, et aucune autre assertion de ce fichier ne le
# verrait.
cat > "$REP_STUB_DISQUE_DF_PARTIEL/df" <<'FAUXDF'
#!/bin/sh
echo "Filesystem     Type      Size  Used Avail Use% Mounted on"
echo "/dev/essai     ext4       10G    9G    1G  90% /essai"
exit 1
FAUXDF
chmod +x "$REP_STUB_DISQUE_DF_PARTIEL/df"
if "$REP_STUB_DISQUE_DF_PARTIEL/df" -P -T -h >/dev/null 2>&1; then
    ko "garde : le faux « df » partiel rend un code non nul" "le stub a rendu 0"
else
    ok "garde : le faux « df » partiel rend un code non nul"
fi

lancer env "PATH=$REP_STUB_DISQUE_DF_PARTIEL:$PATH" bash "$CHECK_DISK_SH" --sans-repertoires
invariants_disque "« df » partiel"
assert_contient "$(erreur)" "[WARN] « df » n'a pas pu interroger tous les points de montage : le tableau ci-dessous est partiel." \
    "check-disk.sh, « df » partiel : le caractère partiel est annoncé pour les systèmes de fichiers"
assert_contient "$(erreur)" "[WARN] « df -i » n'a pas pu interroger tous les points de montage : le tableau ci-dessous est partiel." \
    "check-disk.sh, « df » partiel : le caractère partiel est annoncé pour les inodes"
# LES ASSERTIONS DÉCISIVES : la sortie partielle est EXPLOITÉE, pas jetée.
assert_egal "1" "$(nb_montages "Systèmes de fichiers")" \
    "check-disk.sh, « df » partiel : le tableau des systèmes de fichiers est AFFICHÉ malgré le code 1"
assert_egal "1" "$(nb_montages "Inodes")" \
    "check-disk.sh, « df » partiel : le tableau des inodes est AFFICHÉ malgré le code 1"
assert_contient "$(section_disque "Systèmes de fichiers")" "/essai" \
    "check-disk.sh, « df » partiel : la ligne que df a pu écrire est bien lue"
assert_egal "" "$(valeur_ligne_disque "Occupation")" \
    "check-disk.sh, « df » partiel : AUCUNE ligne « Occupation : non disponible » — le vide seul décide"
assert_contient "$(erreur)" "[WARN] Seuil de 85 % atteint — /essai (/dev/essai) : 90 % occupés" \
    "check-disk.sh, « df » partiel : le seuil est évalué sur les lignes obtenues"

# f.2 — « du » sur « / » sans privilège. Le cas RÉEL, et non un stub : /root et
# quelques répertoires de /var résistent à un compte ordinaire, et « du » rend 1
# après avoir calculé tout le reste.
if [ "$SANS_ROOT_DISPONIBLE" != "true" ]; then
    saute "check-disk.sh : « du » partiel sans privilège sur « / »" \
        "aucun lanceur ne parvient à abaisser l'UID sur cet hôte"
elif "${LANCEUR_SANS_ROOT[@]}" du -x -h --max-depth=1 -- / >/dev/null 2>&1; then
    saute "check-disk.sh : « du » partiel sans privilège sur « / »" \
        "« du » réussit ici sans privilège — aucun répertoire ne lui résiste, le cas ne prouverait rien"
else
    ok "garde : « du -x » sur « / » rend un code non nul sans privilège"
    sans_root bash "$CHECK_DISK_SH" --repertoire /
    invariants_disque "sans privilège, « du » partiel"
    assert_contient "$(erreur)" "[WARN] « du » n'a pas pu lire tous les sous-répertoires de « / »" \
        "check-disk.sh sans privilège : le caractère partiel du « du » est annoncé"
    # L'ASSERTION DÉCISIVE : le classement s'affiche MALGRÉ le [WARN].
    NB_CLASSEMENT_SANS_ROOT="$(nb_entrees_classement)"
    if [ "$NB_CLASSEMENT_SANS_ROOT" -ge 1 ]; then
        ok "check-disk.sh sans privilège : le classement est AFFICHÉ malgré le [WARN] — $NB_CLASSEMENT_SANS_ROOT entrée(s)"
    else
        ko "check-disk.sh sans privilège : le classement est AFFICHÉ malgré le [WARN]" \
            "aucune entrée — la sortie partielle de « du » a été jetée sur son code de retour"
    fi
    TOTAL_SANS_ROOT="$(valeur_ligne_disque "Total (ce montage)")"
    if [ -n "$TOTAL_SANS_ROOT" ] && [ "$TOTAL_SANS_ROOT" != "non disponible" ]; then
        ok "check-disk.sh sans privilège : le total reste une vraie valeur — « $TOTAL_SANS_ROOT »"
    else
        ko "check-disk.sh sans privilège : le total reste une vraie valeur" \
            "valeur obtenue « $TOTAL_SANS_ROOT »"
    fi
    if [ "$(nb_montages "Systèmes de fichiers")" -ge 1 ]; then
        ok "check-disk.sh sans privilège : le tableau des systèmes de fichiers est produit"
    else
        ko "check-disk.sh sans privilège : le tableau des systèmes de fichiers est produit" "tableau vide"
    fi
    rm -rf "$LOG_DIR_NOBODY"
fi

# --- g. Le seuil — ATTEINT, et non dépassé ---------------------------------
# La comparaison du script est « -ge ». Un « -gt » resterait vert sous tout jeu
# de données où l'occupation ne tombe pas EXACTEMENT sur le seuil : d'où un faux
# « df » qui annonce 90 %, et deux appels en regard — --seuil 90 doit avertir,
# --seuil 91 doit se taire.
cat > "$REP_STUB_DISQUE_DF_PLEIN/df" <<'FAUXDF'
#!/bin/sh
echo "Filesystem     Type      Size  Used Avail Use% Mounted on"
echo "/dev/essai     ext4       10G    9G    1G  90% /essai"
exit 0
FAUXDF
chmod +x "$REP_STUB_DISQUE_DF_PLEIN/df"
if "$REP_STUB_DISQUE_DF_PLEIN/df" -P -T -h >/dev/null 2>&1; then
    ok "garde : le faux « df » à 90 % rend 0"
else
    ko "garde : le faux « df » à 90 % rend 0" "le stub a rendu un code non nul"
fi

lancer env "PATH=$REP_STUB_DISQUE_DF_PLEIN:$PATH" bash "$CHECK_DISK_SH" --seuil 90 --sans-repertoires
invariants_disque "seuil ATTEINT — 90 % pour un seuil de 90"
assert_contient "$(erreur)" "[WARN] Seuil de 90 % atteint — /essai (/dev/essai) : 90 % occupés" \
    "check-disk.sh : une occupation ÉGALE au seuil est signalée — « -ge », et non « -gt »"
assert_contient "$(erreur)" "[WARN] Seuil de 90 % atteint — /essai (/dev/essai) : 90 % des inodes consommés" \
    "check-disk.sh : le même seuil vaut pour les inodes, et à égalité"

lancer env "PATH=$REP_STUB_DISQUE_DF_PLEIN:$PATH" bash "$CHECK_DISK_SH" --seuil 91 --sans-repertoires
invariants_disque "seuil NON atteint — 90 % pour un seuil de 91"
assert_absent "$(erreur)" "Seuil de 91 % atteint" \
    "check-disk.sh : une occupation INFÉRIEURE au seuil ne produit aucun avertissement"
assert_egal "0" "$(nb_lignes_contenant '[WARN]')" \
    "check-disk.sh : sous le seuil, stderr ne porte aucun avertissement"

lancer env "PATH=$REP_STUB_DISQUE_DF_PLEIN:$PATH" bash "$CHECK_DISK_SH" --sans-repertoires
invariants_disque "seuil par défaut — 90 % pour le défaut de 85"
assert_contient "$(erreur)" "[WARN] Seuil de 85 % atteint — /essai (/dev/essai) : 90 % occupés" \
    "check-disk.sh : le seuil par défaut de 85 % s'applique sans qu'on le demande"

# Sur les vrais systèmes de fichiers de cet hôte : un seuil de 1 % avertit
# forcément, et le code de retour n'en est PAS changé. C'est la décision de la
# tâche — un diagnostic constate, il ne juge pas.
lancer bash "$CHECK_DISK_SH" --seuil 1 --sans-repertoires
assert_code 0 "$CODE" "check-disk.sh --seuil 1 : un seuil atteint ne change PAS le code de retour"
invariants_disque "--seuil 1 sur les systèmes de fichiers réels"
assert_contient "$(erreur)" "[WARN] Seuil de 1 % atteint" \
    "check-disk.sh --seuil 1 : au moins un système de fichiers est signalé"
NB_WARN_SEUIL_1="$(nb_lignes_contenant '[WARN]')"
if [ "$NB_WARN_SEUIL_1" -ge 1 ]; then
    ok "check-disk.sh --seuil 1 : $NB_WARN_SEUIL_1 avertissement(s) émis"
else
    ko "check-disk.sh --seuil 1 : au moins un avertissement est émis" "aucun [WARN] sur stderr"
fi

# --- g bis. L'origine des valeurs, et la préséance -------------------------
# SRV_DISK_SEUIL et SRV_DISK_REPERTOIRE sont transmises par l'ENVIRONNEMENT et
# non par un config/server.env écrit pour l'occasion : lib/common.sh charge ce
# fichier avec « set -a » depuis TASK-015, les deux chemins aboutissent donc à
# la même variable exportée. Ce qui reste NON PROUVÉ ici est dit au groupe 5.
lancer env SRV_DISK_SEUIL=50 bash "$CHECK_DISK_SH" --sans-repertoires
assert_code 0 "$CODE" "check-disk.sh accepte un seuil venu de la configuration"
assert_egal "50 % (config/server.env)" "$(valeur_ligne_disque "Seuil d'alerte")" \
    "check-disk.sh : le seuil de la configuration prime sur la valeur par défaut, et son origine est nommée"

lancer env SRV_DISK_SEUIL=50 bash "$CHECK_DISK_SH" --seuil 70 --sans-repertoires
assert_code 0 "$CODE" "check-disk.sh accepte un seuil de ligne de commande par-dessus la configuration"
assert_egal "70 % (ligne de commande)" "$(valeur_ligne_disque "Seuil d'alerte")" \
    "check-disk.sh : la ligne de commande prime sur la configuration, et son origine est nommée"

lancer env SRV_DISK_REPERTOIRE=/usr bash "$CHECK_DISK_SH" --top 2
assert_code 0 "$CODE" "check-disk.sh analyse le répertoire donné par la configuration"
assert_egal "/usr (config/server.env)" "$(valeur_ligne_disque "Répertoire analysé")" \
    "check-disk.sh : le répertoire de la configuration est retenu, et son origine nommée"
# Et c'est bien /usr qui a été PARCOURU, pas seulement affiché. La ligne
# « Répertoire » de la section ne peut pas servir ici : « valeur_ligne_disque »
# la confondrait avec « Répertoire analysé », dont elle est un préfixe. Les
# chemins du classement, eux, ne mentent pas.
CHEMINS_HORS_USR=""
NB_CHEMINS_USR=0
while IFS= read -r chemin_classe; do
    [ -n "$chemin_classe" ] || continue
    NB_CHEMINS_USR=$(( NB_CHEMINS_USR + 1 ))
    case "$chemin_classe" in
        /usr/*) ;;
        *) CHEMINS_HORS_USR="$CHEMINS_HORS_USR $chemin_classe" ;;
    esac
done < <(chemins_classement)
if [ "$NB_CHEMINS_USR" -ge 1 ] && [ -z "$CHEMINS_HORS_USR" ]; then
    ok "check-disk.sh : c'est bien /usr qui a été parcouru — $NB_CHEMINS_USR sous-répertoire(s), tous sous /usr/"
else
    ko "check-disk.sh : c'est bien /usr qui a été parcouru" \
        "$NB_CHEMINS_USR entrée(s), hors de /usr :${CHEMINS_HORS_USR:- aucune}"
fi

lancer env SRV_DISK_REPERTOIRE=/usr bash "$CHECK_DISK_SH" --repertoire /etc --top 2
assert_code 0 "$CODE" "check-disk.sh accepte un répertoire de ligne de commande par-dessus la configuration"
assert_egal "/etc (ligne de commande)" "$(valeur_ligne_disque "Répertoire analysé")" \
    "check-disk.sh : la ligne de commande prime sur la configuration pour le répertoire"

# ASSERTION RETOURNÉE — LE SCRIPT A ÉTÉ CORRIGÉ, PAS LE TEST PLIÉ.
#
# Ce cas attendait le code 2 pour « SRV_DISK_SEUIL=abc ». Il l'attendait en le
# dénonçant : le script raisonnait lui-même, en toutes lettres, qu'une valeur
# héritée de config/server.env « ne reproche rien à la commande tapée » — et
# n'appliquait ce raisonnement qu'à --repertoire. Un server.env mal saisi
# privait donc l'appelant de TOUT son tableau de disques pour le seuil, et de
# rien pour le répertoire. Un diagnostic qui refuse de diagnostiquer.
#
# Ce qui a été tranché : UNE SEULE RÈGLE, qui ne dépend plus que de l'ORIGINE.
#
#   ligne de commande fautive   [ERROR], code 2 — l'appelant s'est trompé
#   config/server.env fautif    [WARN], repli, code 0 — la commande était juste
#
# Ce que le repli retient diffère d'une valeur à l'autre, et c'est le seul
# écart : le seuil retombe sur 85 %, qui reste une comparaison utile ; le
# répertoire ne retombe PAS sur « / » — ce serait parcourir une arborescence que
# personne n'a demandée — sa section est sautée.
#
# L'assertion décisive de ce groupe n'est ni le code ni le message : c'est LE
# TABLEAU EST PRODUIT. C'était tout l'objet du changement.
lancer env SRV_DISK_SEUIL=abc bash "$CHECK_DISK_SH" --sans-repertoires
invariants_disque "seuil de configuration non numérique"
assert_contient "$(erreur)" "[WARN] « abc » (config/server.env, SRV_DISK_SEUIL) n'est pas un entier :" \
    "check-disk.sh : le repli nomme la variable ET la valeur refusée"
assert_contient "$(erreur)" "[WARN] repli sur le seuil par défaut, 85 %." \
    "check-disk.sh : le repli nomme la valeur RETENUE à la place"
assert_egal "2" "$(nb_lignes_contenant '[WARN]')" \
    "check-disk.sh : deux avertissements mesurés pour un seuil de configuration refusé"
assert_absent "$(erreur)" "[ERROR]" \
    "check-disk.sh : une valeur de configuration fautive ne produit AUCUNE ligne [ERROR] — la commande tapée était juste"
assert_egal "85 % (valeur par défaut, SRV_DISK_SEUIL refusé)" "$(valeur_ligne_disque "Seuil d'alerte")" \
    "check-disk.sh : l'en-tête porte le repli et dit que SRV_DISK_SEUIL a été refusé"
# L'ASSERTION DÉCISIVE.
if [ "$(nb_montages "Systèmes de fichiers")" -ge 1 ]; then
    ok "check-disk.sh : le TABLEAU des systèmes de fichiers est produit malgré le seuil de configuration refusé"
else
    ko "check-disk.sh : le TABLEAU des systèmes de fichiers est produit malgré le seuil de configuration refusé" \
        "tableau vide — le diagnostic refuse encore de diagnostiquer"
fi
if [ "$(nb_montages "Inodes")" -ge 1 ]; then
    ok "check-disk.sh : le tableau des inodes est produit malgré le seuil de configuration refusé"
else
    ko "check-disk.sh : le tableau des inodes est produit malgré le seuil de configuration refusé" "tableau vide"
fi

# Le même repli pour l'autre motif de refus — hors bornes, et non « pas un
# entier ». Les deux « case » de valider_entier sont ainsi tous deux empruntés
# par le chemin du repli, et pas seulement par celui du refus.
lancer env SRV_DISK_SEUIL=0 bash "$CHECK_DISK_SH" --sans-repertoires
invariants_disque "seuil de configuration hors bornes"
assert_contient "$(erreur)" "[WARN] « 0 » (config/server.env, SRV_DISK_SEUIL) est hors bornes — attendu un entier de 1 à 100, sans zéro initial :" \
    "check-disk.sh : un seuil de configuration hors bornes est replié, et la précision est conservée"
assert_contient "$(erreur)" "[WARN] repli sur le seuil par défaut, 85 %." \
    "check-disk.sh : le repli d'un seuil hors bornes retient lui aussi 85 %"
assert_egal "85 % (valeur par défaut, SRV_DISK_SEUIL refusé)" "$(valeur_ligne_disque "Seuil d'alerte")" \
    "check-disk.sh : l'en-tête porte le repli pour un seuil hors bornes"
if [ "$(nb_montages "Systèmes de fichiers")" -ge 1 ]; then
    ok "check-disk.sh : le tableau est produit malgré un seuil de configuration hors bornes"
else
    ko "check-disk.sh : le tableau est produit malgré un seuil de configuration hors bornes" "tableau vide"
fi

# LA PRÉSÉANCE. Une ligne de commande valide reprend la main sur une
# configuration fautive : il n'y a alors RIEN à replier, et aucun [WARN] de
# repli ne doit sortir. Sans cette assertion, un script qui avertirait d'abord
# et lirait la ligne de commande ensuite passerait inaperçu.
lancer env SRV_DISK_SEUIL=abc bash "$CHECK_DISK_SH" --seuil 70 --sans-repertoires
invariants_disque "configuration fautive, ligne de commande valide"
assert_egal "70 % (ligne de commande)" "$(valeur_ligne_disque "Seuil d'alerte")" \
    "check-disk.sh : la ligne de commande reprend la main sur une configuration fautive"
assert_absent "$(erreur)" "repli sur le seuil par défaut" \
    "check-disk.sh : aucun repli n'est annoncé quand la ligne de commande a tranché"
assert_absent "$(erreur)" "SRV_DISK_SEUIL" \
    "check-disk.sh : la variable fautive n'est même pas mentionnée — elle n'a jamais servi"

# LA NON-RÉGRESSION DU 2 EN LIGNE DE COMMANDE. Les quatre refus de la section a
# — « --seuil abc », « --seuil 0 », « --seuil 101 », « --top 0 » — gardent leur
# code 2, leur unique ligne [ERROR] et leur message au caractère près. Ils sont
# la moitié que le repli ne doit PAS avoir emportée : un correctif qui aurait
# replié TOUTES les valeurs fautives, quelle qu'en soit l'origine, les ferait
# rougir. Ils ne sont pas rejoués ici, ils sont plus haut, et c'est leur place —
# ce commentaire dit seulement qu'ils bordent ce groupe-ci.
#
# « --top » n'a pas de source dans config/server.env, et le script l'écrit :
# c'est un confort d'affichage, pas une donnée de machine. Son origine est donc
# toujours « ligne de commande » ou une valeur par défaut valide par
# construction — il n'y a aucun repli à éprouver de son côté.

# Un répertoire de configuration inutilisable ne prive PAS l'appelant du reste
# du diagnostic : avertissement, section sautée, code 0.
lancer env SRV_DISK_REPERTOIRE=/pas/la bash "$CHECK_DISK_SH"
invariants_disque "répertoire de configuration inexistant"
assert_contient "$(erreur)" "[WARN] « /pas/la » (config/server.env) n'est pas un répertoire, ou n'est pas accessible :" \
    "check-disk.sh : un répertoire de configuration inutilisable est signalé, pas refusé"
assert_contient "$(erreur)" "[WARN] la section des répertoires consommateurs est sautée." \
    "check-disk.sh : la conséquence est annoncée"
assert_egal "non disponible" "$(valeur_ligne_disque "Analyse")" \
    "check-disk.sh : la section des répertoires dégrade en « non disponible »"
if [ "$(nb_montages "Systèmes de fichiers")" -ge 1 ]; then
    ok "check-disk.sh : le reste du diagnostic est produit malgré le répertoire inutilisable"
else
    ko "check-disk.sh : le reste du diagnostic est produit malgré le répertoire inutilisable" "tableau vide"
fi

# --- g ter. Le TROISIÈME site de la règle d'origine ------------------------
# Le refus d'un --repertoire commençant par un tiret ne s'applique plus que si
# l'origine est la ligne de commande. Aucun cas ne couvrait ce chemin ; il a été
# jugé avant d'être couvert, et voici le jugement.
#
# LE CONTRÔLE EST JUSTE, ET SA RESTRICTION L'EST AUSSI. Sa raison d'être n'a
# jamais été la sûreté : c'est d'empêcher « --repertoire --tous » d'avaler le
# jeton argv suivant et de perdre l'option demandée en silence. Une valeur
# héritée d'une variable d'environnement n'a AUCUN jeton suivant — le piège
# n'existe pas là. Restait à vérifier que rien en aval ne prend un chemin à
# tiret pour une option : les deux seuls consommateurs sont « du … -- "$REP" »,
# dont le « -- » ferme la question, et « awk -v racine="$REP" », où la valeur
# est le membre droit d'une affectation. Vérifié par exécution ci-dessous, et
# non par lecture : le second cas fait analyser un répertoire RÉELLEMENT nommé
# « -x ».
#
# g ter.1 — le cas ordinaire : « -x » venu de la configuration n'est qu'un
# chemin introuvable de plus. Le contrôle suivant s'en charge, sans rendre 2.
lancer env SRV_DISK_REPERTOIRE=-x bash "$CHECK_DISK_SH"
invariants_disque "répertoire de configuration commençant par un tiret"
assert_absent "$(erreur)" "commence par un tiret" \
    "check-disk.sh : un chemin à tiret venu de la configuration n'est PAS traité en erreur d'usage"
assert_contient "$(erreur)" "[WARN] « -x » (config/server.env) n'est pas un répertoire, ou n'est pas accessible :" \
    "check-disk.sh : il est traité comme n'importe quel chemin introuvable de la configuration"
assert_contient "$(erreur)" "[WARN] la section des répertoires consommateurs est sautée." \
    "check-disk.sh : la conséquence est la même que pour tout autre chemin introuvable"
assert_egal "non disponible" "$(valeur_ligne_disque "Analyse")" \
    "check-disk.sh : la section des répertoires dégrade, le reste est produit"
if [ "$(nb_montages "Systèmes de fichiers")" -ge 1 ]; then
    ok "check-disk.sh : le tableau est produit malgré un répertoire de configuration à tiret"
else
    ko "check-disk.sh : le tableau est produit malgré un répertoire de configuration à tiret" "tableau vide"
fi

# g ter.2 — LE CAS QUI TRANCHE. Un répertoire RÉELLEMENT nommé « -x », et le
# script le parcourt. C'est la seule exécution qui prouve que « -x » traverse
# tout l'aval du script — « du -- », « awk -v racine= » — sans y être pris pour
# une option. Sans elle, « ce n'est qu'un chemin » resterait une lecture du code.
#
# Le répertoire vit hors de REP_TMP par commodité de « cd », et le harnais s'y
# déplace dans un SOUS-SHELL : le répertoire courant du fichier de cas n'est
# jamais changé, et le chemin relatif « -x » ne se résout que là.
REP_TIRET="$REP_TMP/bac-a-tiret"
mkdir -p "$REP_TIRET"
mkdir -p "$REP_TIRET/-x/sous-repertoire-temoin"
dd if=/dev/zero of="$REP_TIRET/-x/sous-repertoire-temoin/remplissage" bs=1024 count=200 >/dev/null 2>&1
if [ -d "$REP_TIRET/-x" ]; then
    ok "garde : un répertoire réellement nommé « -x » a été créé"
else
    ko "garde : un répertoire réellement nommé « -x » a été créé" "$REP_TIRET/-x est absent"
fi

lancer_depuis "$REP_TIRET" env SRV_DISK_REPERTOIRE=-x bash "$CHECK_DISK_SH" --top 5
invariants_disque "répertoire « -x » réel, venu de la configuration"
assert_egal "-x (config/server.env)" "$(valeur_ligne_disque "Répertoire analysé")" \
    "check-disk.sh : « -x » est retenu comme répertoire à analyser"
assert_absent "$(erreur)" "n'est pas un répertoire" \
    "check-disk.sh : « -x » existant, aucun repli n'est déclenché"
TOTAL_TIRET="$(valeur_ligne_disque "Total (ce montage)")"
if [ -n "$TOTAL_TIRET" ] && [ "$TOTAL_TIRET" != "non disponible" ]; then
    ok "check-disk.sh : « du -- \"-x\" » a bien mesuré le répertoire — total « $TOTAL_TIRET »"
else
    ko "check-disk.sh : « du -- \"-x\" » a bien mesuré le répertoire" \
        "total obtenu « $TOTAL_TIRET » — le tiret a été pris pour une option quelque part en aval"
fi
assert_contient "$(chemins_classement)" "-x/sous-repertoire-temoin" \
    "check-disk.sh : le classement de « -x » est produit — « awk -v racine=-x » ne s'y est pas trompé non plus"

rm -rf "$REP_TIRET"

# --- h. Les inodes non déclarés --------------------------------------------
# btrfs, ZFS et certains overlay n'en déclarent pas : « df -i » écrit « - ».
# Un pourcentage calculé là-dessus donnerait 0 % ou 100 % sur un système de
# fichiers qui, par construction, ne peut pas en manquer.
#
# Le faux « df » est SÉLECTIF : il ne rend « - » que pour l'appel « -i », et un
# tableau ordinaire pour l'autre. Un stub total ne distinguerait pas les deux
# sections, et le cas ne dirait plus laquelle a dégradé.
cat > "$REP_STUB_DISQUE_DF_INODES/df" <<'FAUXDF'
#!/bin/sh
for argument in "$@"; do
    if [ "$argument" = "-i" ]; then
        echo "Filesystem     Type     Inodes IUsed IFree IUse% Mounted on"
        echo "/dev/essai     btrfs         -     -     -     - /essai"
        exit 0
    fi
done
echo "Filesystem     Type      Size  Used Avail Use% Mounted on"
echo "/dev/essai     btrfs      10G    9G    1G  90% /essai"
exit 0
FAUXDF
chmod +x "$REP_STUB_DISQUE_DF_INODES/df"
if [ "$("$REP_STUB_DISQUE_DF_INODES/df" -P -T -i -h | awk 'NR == 2 { print $3 }')" = "-" ]; then
    ok "garde : le faux « df » ne déclare aucun inode pour l'appel « -i »"
else
    ko "garde : le faux « df » ne déclare aucun inode pour l'appel « -i »" \
        "le stub n'a pas rendu « - » en troisième champ"
fi

# Garde de contraste : sur les vrais systèmes de fichiers de cet hôte, la racine
# porte un pourcentage d'inodes. Sans elle, le « non disponible » du cas suivant
# pourrait venir d'ailleurs.
lancer bash "$CHECK_DISK_SH" --sans-repertoires
OCCUP_INODES_RACINE="$(occupation_disque "Inodes" "/")"
case "$OCCUP_INODES_RACINE" in
    [0-9]*%) ok "garde : sans stub, la racine porte un pourcentage d'inodes — « $OCCUP_INODES_RACINE »" ;;
    *)       saute "check-disk.sh : contraste du cas « inodes non déclarés »" \
                "la racine de cet hôte n'en déclare pas non plus — valeur lue « $OCCUP_INODES_RACINE »" ;;
esac

lancer env "PATH=$REP_STUB_DISQUE_DF_INODES:$PATH" bash "$CHECK_DISK_SH" --sans-repertoires
invariants_disque "inodes non déclarés"
assert_contient "$(section_disque "Inodes")" "non disponible (ce système de fichiers ne déclare pas d'inodes)" \
    "check-disk.sh : un système de fichiers sans inodes affiche « non disponible », jamais un pourcentage faux"
assert_absent "$(section_disque "Inodes")" "0%" \
    "check-disk.sh : aucun pourcentage n'est calculé sur un total d'inodes absent"
# L'autre tableau, lui, reste chiffré : la dégradation est LOCALE à la ligne.
assert_egal "90%" "$(occupation_disque "Systèmes de fichiers" "/essai")" \
    "check-disk.sh : le tableau des blocs reste chiffré quand celui des inodes dégrade"
assert_absent "$(erreur)" "des inodes consommés" \
    "check-disk.sh : aucun seuil n'est évalué sur un pourcentage d'inodes absent"

# --- h bis. Un pourcentage de BLOCS non déclaré ----------------------------
# Le pendant du cas précédent, du côté des blocs : « df » écrit « - » dans la
# colonne « Use% » pour un système de fichiers qui ne compte pas ses blocs — ZFS
# avec quotas, certains montages FUSE. Le script s'en garde par un
# « [ -n "$POURCENTAGE_NUMERIQUE" ] » devant la comparaison au seuil.
#
# CE CAS EXISTE PARCE QUE LA MUTATION L'A DEMANDÉ. Retirer cette garde ne
# faisait rougir AUCUNE assertion du groupe : aucun jeu de données n'atteignait
# la comparaison avec un pourcentage vide. La garde était donc écrite et non
# vérifiée — et sans elle, « [ : -ge 85 ] » déverse un message brut de bash sur
# stderr, que l'invariant de dégradation voit.
REP_STUB_DISQUE_DF_SANSPCT="$REP_TMP/stub-disque-df-sans-pourcentage"
mkdir -p "$REP_STUB_DISQUE_DF_SANSPCT"
cat > "$REP_STUB_DISQUE_DF_SANSPCT/df" <<'FAUXDF'
#!/bin/sh
echo "Filesystem     Type      Size  Used Avail Use% Mounted on"
echo "/dev/essai     zfs        10G    9G    1G    - /essai"
exit 0
FAUXDF
chmod +x "$REP_STUB_DISQUE_DF_SANSPCT/df"
if [ "$("$REP_STUB_DISQUE_DF_SANSPCT/df" -P -T -h | awk 'NR == 2 { print $6 }')" = "-" ]; then
    ok "garde : le faux « df » ne déclare aucun pourcentage d'occupation"
else
    ko "garde : le faux « df » ne déclare aucun pourcentage d'occupation" \
        "le stub n'a pas rendu « - » en sixième champ"
fi

lancer env "PATH=$REP_STUB_DISQUE_DF_SANSPCT:$PATH" bash "$CHECK_DISK_SH" --sans-repertoires
invariants_disque "pourcentage de blocs non déclaré"
assert_egal "-" "$(occupation_disque "Systèmes de fichiers" "/essai")" \
    "check-disk.sh : un pourcentage d'occupation non déclaré est recopié tel quel, jamais interprété"
assert_absent "$(erreur)" "Seuil de 85 % atteint" \
    "check-disk.sh : aucun seuil n'est évalué sur un pourcentage de blocs absent"
assert_contient "$(section_disque "Inodes")" "non disponible (ce système de fichiers ne déclare pas d'inodes)" \
    "check-disk.sh : le tableau des inodes dégrade lui aussi, faute de pourcentage"

rm -rf "$REP_STUB_DISQUE_DF_SANSPCT"

# --- i. Les trois bornes de l'analyse des répertoires ----------------------
lancer bash "$CHECK_DISK_SH" --top 3
assert_code 0 "$CODE" "check-disk.sh --top 3 sort en 0"
assert_egal "3 (ligne de commande)" "$(valeur_ligne_disque "Entrées affichées")" \
    "check-disk.sh --top 3 rappelle la valeur et son origine"
NB_TOP3="$(nb_entrees_classement)"
if [ "$NB_TOP3" -le 3 ] && [ "$NB_TOP3" -ge 1 ]; then
    ok "check-disk.sh --top 3 borne le classement à 3 entrées — $NB_TOP3 affichée(s)"
else
    ko "check-disk.sh --top 3 borne le classement à 3 entrées" "$NB_TOP3 entrée(s) affichée(s)"
fi

# La profondeur 1 : aucun chemin à deux niveaux sous le répertoire analysé.
lancer bash "$CHECK_DISK_SH"
assert_code 0 "$CODE" "check-disk.sh sort en 0 — mesure de la profondeur d'analyse"
CHEMINS_PROFONDS=""
while IFS= read -r chemin_classe; do
    [ -n "$chemin_classe" ] || continue
    case "${chemin_classe#/}" in
        */*) CHEMINS_PROFONDS="$CHEMINS_PROFONDS $chemin_classe" ;;
    esac
done < <(chemins_classement)
if [ -z "$CHEMINS_PROFONDS" ]; then
    ok "check-disk.sh borne l'analyse à la profondeur 1 sous « / »"
else
    ko "check-disk.sh borne l'analyse à la profondeur 1 sous « / »" \
        "chemins de profondeur supérieure :$CHEMINS_PROFONDS"
fi

# « -x » : aucun point de montage n'est franchi. Le montage témoin est CHOISI
# dans la liste que le script vient lui-même d'afficher, plutôt que nommé
# d'avance : sur un hôte qui n'en aurait aucun, le cas se déclare non exécuté au
# lieu de passer à vide.
MONTAGE_TEMOIN=""
while IFS= read -r montage_liste; do
    [ -n "$montage_liste" ] || continue
    [ "$montage_liste" != "/" ] || continue
    case "${montage_liste#/}" in
        */*) continue ;;
    esac
    MONTAGE_TEMOIN="$montage_liste"
    break
done < <(printf '%s\n' "$MONTAGES_IDEM_B")
if [ -z "$MONTAGE_TEMOIN" ]; then
    saute "check-disk.sh ne franchit aucun point de montage sous « / »" \
        "cet hôte n'expose aucun montage de premier niveau distinct de « / » — il n'y a rien à ne pas franchir"
else
    assert_absent "$(chemins_classement)" "$MONTAGE_TEMOIN" \
        "check-disk.sh ne franchit pas le point de montage « $MONTAGE_TEMOIN » (option -x)"
fi

# --sans-repertoires saute la section entière, et le dit.
lancer bash "$CHECK_DISK_SH" --sans-repertoires
assert_code 0 "$CODE" "check-disk.sh --sans-repertoires sort en 0"
assert_egal "aucun (--sans-repertoires)" "$(valeur_ligne_disque "Répertoire analysé")" \
    "check-disk.sh --sans-repertoires l'annonce dans le rappel des paramètres"
assert_egal "désactivée (--sans-repertoires)" "$(valeur_ligne_disque "Analyse")" \
    "check-disk.sh --sans-repertoires saute la section des répertoires"
assert_absent "$(erreur)" "Analyse de « / » en cours" \
    "check-disk.sh --sans-repertoires ne lance aucun « du »"
assert_egal "0" "$(nb_entrees_classement)" \
    "check-disk.sh --sans-repertoires n'affiche aucune entrée de classement"

# --tous lève le filtre.
lancer bash "$CHECK_DISK_SH" --tous --sans-repertoires
assert_code 0 "$CODE" "check-disk.sh --tous sort en 0"
assert_egal "aucun — tous les systèmes de fichiers (--tous)" "$(valeur_ligne_disque "Filtre")" \
    "check-disk.sh --tous l'annonce dans le rappel des paramètres"
NB_FS_TOUS="$(nb_montages "Systèmes de fichiers")"
if ! df -P -T 2>/dev/null | awk 'NR > 1 && $2 == "tmpfs" { trouve = 1 } END { exit !trouve }'; then
    saute "check-disk.sh --tous montre les pseudo-systèmes que le filtre écarte" \
        "cet hôte ne monte aucun tmpfs — le filtre n'a rien à lever"
else
    if [ "$NB_FS_TOUS" -gt "$NB_FS_DEFAUT" ]; then
        ok "check-disk.sh --tous montre plus de systèmes de fichiers que le filtre par défaut — $NB_FS_TOUS contre $NB_FS_DEFAUT"
    else
        ko "check-disk.sh --tous montre plus de systèmes de fichiers que le filtre par défaut" \
            "$NB_FS_TOUS avec --tous, $NB_FS_DEFAUT sans — le filtre n'écarte donc rien"
    fi
    assert_contient "$(section_disque "Systèmes de fichiers")" "tmpfs" \
        "check-disk.sh --tous n'écarte plus les pseudo-systèmes"
fi

# --- j. Aucune écriture, sur TOUT le groupe --------------------------------
# Le témoin a été posé à l'ouverture. Une quarantaine d'exécutions plus tard —
# sous stub, sans privilège, avec des valeurs de configuration — rien ne doit
# avoir été écrit hors du répertoire de journaux.
assert_aucune_ecriture "$REP_TMP/temoin-disque-groupe" \
    "check-disk.sh : AUCUNE des exécutions de ce groupe n'a écrit hors du répertoire de journaux"

rm -rf "$REP_STUB_DISQUE_DF" "$REP_STUB_DISQUE_DU" "$REP_STUB_DISQUE_LSBLK" \
    "$REP_STUB_DISQUE_AWK" "$REP_STUB_DISQUE_SORT" "$REP_STUB_DISQUE_DF_PARTIEL" \
    "$REP_STUB_DISQUE_DF_PLEIN" "$REP_STUB_DISQUE_DF_INODES" "$REP_SANS_LSBLK"

# ===================================================================
# 3. --dry-run — critère 3
# ===================================================================
# Une empreinte avant, une après, et la liste des fichiers écrits entre les
# deux. L'empreinte seule ne verrait pas un fichier créé hors de /etc ; la
# liste seule ne verrait pas une réécriture à l'identique de la même taille.
# Les deux ensemble ne laissent pas de trou.
titre "3. --dry-run des quatre scripts modifiant des fichiers"

dry_run_inoffensif() {
    local libelle="$1"; shift

    empreinte "$REP_TMP/dry-avant"
    touch "$REP_TMP/temoin-dry"
    lancer "$@"

    assert_code 0 "$CODE" "$libelle sort en 0"
    empreinte "$REP_TMP/dry-apres"
    assert_empreinte_egale "$REP_TMP/dry-avant" "$REP_TMP/dry-apres" \
        "$libelle ne modifie aucun fichier"
    assert_aucune_ecriture "$REP_TMP/temoin-dry" \
        "$libelle n'écrit rien hors du répertoire de journaux"
}

if [ "$EST_ROOT" != "true" ]; then
    saute "les quatre --dry-run" "require_root arrête ces scripts avant leur mode --dry-run"
elif [ "$EST_DEBIAN" != "true" ]; then
    saute "les quatre --dry-run" "l'hôte n'est ni Debian ni Ubuntu"
else
    # Le nom demandé diffère du nom courant : sans cela le script sortirait sur
    # « Rien à faire » et le --dry-run ne serait pas atteint.
    dry_run_inoffensif "configure-hostname.sh --dry-run" \
        bash "$HOSTNAME_SH" essai-integration --dry-run
    assert_contient "$(erreur)" "aucune modification effectuée" \
        "configure-hostname.sh --dry-run annonce qu'il n'a rien modifié"

    dry_run_inoffensif "configure-timezone.sh --dry-run" \
        bash "$TIMEZONE_SH" "$FUSEAU_CIBLE" --dry-run
    assert_contient "$(erreur)" "aucune modification effectuée" \
        "configure-timezone.sh --dry-run annonce qu'il n'a rien modifié"

    dry_run_inoffensif "configure-swap.sh --dry-run" \
        bash "$SWAP_SH" 512M --dry-run
    assert_contient "$(erreur)" "aucune modification effectuée" \
        "configure-swap.sh --dry-run annonce qu'il n'a rien modifié"

    # La conversion des unités est le SEUL endroit où le passage d'un « printf »
    # sur stdout à une variable globale — la correction du doublon de trap —
    # pouvait abîmer une valeur sans que rien d'autre ne s'en aperçoive : une
    # variable mal renseignée resterait vide, et « $(( nombre * 1024 )) » ne
    # produirait plus 2048. Le cas 512M ci-dessus n'emprunte pas cette branche,
    # l'unité M étant recopiée telle quelle.
    dry_run_inoffensif "configure-swap.sh 2G --dry-run" \
        bash "$SWAP_SH" 2G --dry-run
    assert_contient "$(erreur)" "Taille demandée : 2048 Mo (argument : 2G)" \
        "configure-swap.sh convertit 2G en 2048 Mo"
    assert_contient "$(erreur)" "créer      /swapfile (2048 Mo)" \
        "configure-swap.sh annonce la création à 2048 Mo, valeur portée jusqu'au résumé"

    # --- Garde de non-régression : une option derrière --file — TASK-017 ---
    # CE CAS NE DÉMONTRE PAS LE CORRECTIF, et il faut le savoir pour ne pas s'y
    # fier à tort. Mesuré par le relecteur sur le configure-swap.sh de master :
    # « 2G --file /swapfile --dry-run » y donnait DÉJÀ « Mode --dry-run » et le
    # code 0. L'ancien code ne consommait qu'un seul jeton ; le défaut
    # n'apparaissait que lorsque l'option ÉTAIT elle-même la valeur — c'est le
    # cas 5a qui le prouve, pas celui-ci.
    #
    # Ce que ce cas apporte : la garantie qu'en fermant le défaut, on n'a pas
    # cassé le chemin nominal. Une validation trop gourmande qui consommerait le
    # jeton suivant le ferait rougir. Aucune autre assertion de ce fichier ne
    # place une option derrière une valeur de --file.
    dry_run_inoffensif "configure-swap.sh 2G --file /swapfile --dry-run" \
        bash "$SWAP_SH" 2G --file /swapfile --dry-run
    assert_contient "$(erreur)" "[INFO] Mode --dry-run : aucune modification effectuée." \
        "configure-swap.sh 2G --file /swapfile --dry-run : --dry-run reste actif après --file"
    assert_contient "$(erreur)" "[INFO] Fichier d'échange : /swapfile" \
        "configure-swap.sh 2G --file /swapfile --dry-run : le chemin donné est bien retenu"

    # Un chemin absolu AUTRE que le défaut : sans lui, les deux assertions
    # précédentes passeraient encore si --file était purement et simplement
    # ignoré, /swapfile étant la valeur par défaut de FICHIER_SWAP.
    if [ -e /var/swapfile-essai ]; then
        ko "garde : /var/swapfile-essai n'existe pas avant l'appel" \
            "le cas ne prouverait plus que le chemin INEXISTANT reste accepté"
    else
        ok "garde : /var/swapfile-essai n'existe pas avant l'appel"
    fi
    dry_run_inoffensif "configure-swap.sh 512M --file /var/swapfile-essai --dry-run" \
        bash "$SWAP_SH" 512M --file /var/swapfile-essai --dry-run
    assert_contient "$(erreur)" "créer      /var/swapfile-essai (512 Mo)" \
        "configure-swap.sh --file <chemin absolu> vise bien le fichier demandé"

    # --- Les DEUX cas nominaux de TASK-019, et ce qu'ils coûtent s'ils cassent -
    # Le contrôle de nature ajouté par TASK-019 refuse tout ce qu'il ne
    # reconnaît pas. Deux cibles doivent continuer de passer, et ce sont les
    # seules qui aient un usage : le chemin qui ne désigne rien — création — et
    # le fichier d'échange existant — redimensionnement. Un contrôle trop
    # sévère rendrait le script inutilisable sans qu'aucun refus ne paraisse
    # fautif ; c'est la régression la plus chère de cette tâche.
    #
    # Le premier cas est celui qui précède : /var/swapfile-essai n'existe pas —
    # la garde ci-dessus le vérifie plutôt que de le supposer — et le résumé
    # annonce toujours « créer ». L'assertion d'absence ci-dessous en fixe le
    # sens du côté de TASK-019 : aucun refus de cible sur ce chemin.
    assert_absent "$(erreur)" "Cible refusée pour --file" \
        "configure-swap.sh --file <chemin absolu inexistant> : la création reste acceptée"

    # Le second cas est le seul de tout le dépôt à éprouver la SIGNATURE. Un
    # fichier d'échange se reconnaît de deux façons, et le groupe swap-fstab de
    # tests/acceptance/interne/TASK-011-cas-conteneur.sh n'emprunte que la
    # première : il pose un fichier creux au chemin qu'expose /proc/swaps, sans
    # aucune signature. La lecture des dix octets « SWAPSPACE2 » écrits par
    # mkswap n'a donc ici que cette seule preuve directe — d'où le fichier
    # réellement produit par mkswap, et non imité.
    #
    # La signature est relevée AVANT l'appel, à l'offset que le script emploie :
    # sans cette garde, un mkswap muet ou une page de taille inattendue ferait
    # rougir le cas sans qu'on sache pourquoi, et la preuve se lirait comme un
    # défaut du script.
    SWAP_MKSWAP="$REP_TMP/swapfile-mkswap"
    dd if=/dev/zero of="$SWAP_MKSWAP" bs=1M count=64 status=none
    chmod 600 "$SWAP_MKSWAP"
    if mkswap "$SWAP_MKSWAP" >/dev/null 2>&1; then
        SIGNATURE_LUE="$(dd if="$SWAP_MKSWAP" bs=1 skip=4086 count=10 2>/dev/null | tr -d '\000')"
        assert_egal "SWAPSPACE2" "$SIGNATURE_LUE" \
            "garde : mkswap a écrit SWAPSPACE2 aux dix derniers octets de la première page"

        dry_run_inoffensif "configure-swap.sh 64M --file <fichier mkswap> --dry-run" \
            bash "$SWAP_SH" 64M --file "$SWAP_MKSWAP" --dry-run
        assert_contient "$(erreur)" "remplacer  $SWAP_MKSWAP (64 Mo -> 64 Mo)" \
            "configure-swap.sh reconnaît un fichier d'échange inactif par sa signature et le redimensionne"
        assert_absent "$(erreur)" "Cible refusée pour --file" \
            "configure-swap.sh --file <fichier mkswap> : aucun refus de cible"
        assert_absent "$(erreur)" "Échec (code" \
            "configure-swap.sh --file <fichier mkswap> : aucune ligne de trap"
        # Ce fichier est en mode 600, comme tout fichier d'échange, et il
        # traverse la validation DEUX fois depuis le second tour de TASK-019 :
        # une fois « avant-root » à la lecture de --file, une fois « apres-root »
        # au préflight. C'est le chemin nominal que l'aiguillage sur le moment
        # pouvait casser — un « n'est pas lisible » prononcé à l'un des deux
        # passages refuserait un fichier d'échange parfaitement valide.
        assert_absent "$(erreur)" "n'est pas lisible" \
            "configure-swap.sh --file <fichier mkswap en 600> : les deux passages de validation le laissent passer"
    else
        saute_indisponible "reconnaissance d'un fichier d'échange par sa signature" \
            "mkswap n'a pas pu préparer $SWAP_MKSWAP — la seule preuve directe de la lecture de SWAPSPACE2 est perdue"
    fi

    # Sans taille, configure-swap.sh n'est qu'un diagnostic : il ne doit pas
    # davantage écrire.
    dry_run_inoffensif "configure-swap.sh sans taille" bash "$SWAP_SH"

    if [ "$LOGROTATE_DISPONIBLE" != "true" ]; then
        saute "configure-logging.sh --dry-run" "logrotate absent de l'image et non installable"
    else
        dry_run_inoffensif "configure-logging.sh --dry-run" \
            bash "$LOGGING_SH" --dry-run
        assert_contient "$(erreur)" "[dry-run] Créerait $REGLE_LOGROTATE" \
            "configure-logging.sh --dry-run annonce la règle sans la déposer"
        if [ -f "$REGLE_LOGROTATE" ]; then
            ko "configure-logging.sh --dry-run ne dépose pas la règle" "$REGLE_LOGROTATE créé"
        else
            ok "configure-logging.sh --dry-run ne dépose pas la règle"
        fi
    fi
fi

# ===================================================================
# 3 bis. -y reste actif après --file — TASK-017
# ===================================================================
# « -y » ne s'observe pas comme « --dry-run ». confirm() n'est appelé qu'APRÈS
# la sortie du mode d'essai à blanc : le prouver exige une exécution RÉELLE, et
# c'est la seule de ce fichier.
#
# Elle est bornée par construction : le fichier d'échange visé est placé dans le
# répertoire jetable du test, jamais /swapfile. swapon est refusé au conteneur
# non privilégié — le script le diagnostique, supprime lui-même son fichier
# incomplet et sort en 1. Ce qui est éprouvé ici n'est donc pas l'activation du
# swap, qui reste NON EXÉCUTÉE au groupe 5, mais la seule ligne « Confirmation
# automatique », que « -y » seul produit.
#
# Les deux moitiés sont mises en regard — sans « -y » puis avec — parce que la
# seconde seule ne dirait pas d'où vient la différence. L'entrée standard est
# fermée par « lancer » : confirm() y lit une réponse vide et refuse.
#
# Une empreinte encadre le groupe. Elle prouve que cette exécution réelle n'a
# rien laissé hors du répertoire jetable, et protège du même geste la garde
# d'état du groupe 4, qui suit.
#
# PORTÉE EXACTE, pour ne pas s'y fier à tort : comme le cas « --dry-run » de la
# section 3, ce groupe est une garde de NON-RÉGRESSION, pas la démonstration du
# correctif. Le relecteur a mesuré que « -y » derrière une valeur de --file
# fonctionnait déjà sur master : l'ancien code ne consommait qu'un seul jeton, et
# le défaut n'apparaissait que lorsque l'option ÉTAIT la valeur. Ce qui prouve le
# correctif, c'est le cas 5a. Ce groupe garantit qu'on ne l'a pas payé en cassant
# le chemin nominal.
titre "3 bis. -y reste actif après --file"

if [ "$EST_ROOT" != "true" ]; then
    saute "-y reste actif après --file <chemin absolu>" \
        "require_root arrête le script avant confirm() — l'exécution réelle exige root"
elif [ "$JETABLE" != "true" ]; then
    saute "-y reste actif après --file <chemin absolu>" \
        "ce cas exécute réellement configure-swap.sh — réservé à un système jetable"
else
    FICHIER_ESSAI="$REP_TMP/swapfile-essai"
    empreinte "$REP_TMP/y-avant"

    # La moitié témoin : sans « -y », le script demande et renonce.
    lancer bash "$SWAP_SH" 64M --file "$FICHIER_ESSAI"
    assert_code 0 "$CODE" "configure-swap.sh 64M --file <absolu> sans -y : renonce proprement"
    assert_contient "$(erreur)" "[INFO] Abandon à la demande de l'utilisateur." \
        "configure-swap.sh sans -y : demande confirmation et renonce"
    assert_absent "$(erreur)" "Confirmation automatique" \
        "configure-swap.sh sans -y : aucune confirmation automatique"
    if [ -e "$FICHIER_ESSAI" ]; then
        ko "configure-swap.sh sans -y ne crée aucun fichier d'échange" "$FICHIER_ESSAI existe"
    else
        ok "configure-swap.sh sans -y ne crée aucun fichier d'échange"
    fi

    # La même commande, « -y » placé APRÈS la valeur de --file. C'est la seule
    # différence entre les deux appels.
    lancer bash "$SWAP_SH" 64M --file "$FICHIER_ESSAI" -y
    assert_contient "$(erreur)" "[INFO] Confirmation automatique : Appliquer ces opérations ?" \
        "configure-swap.sh 64M --file <absolu> -y : -y reste actif après --file"
    assert_absent "$(erreur)" "Abandon à la demande de l'utilisateur" \
        "configure-swap.sh avec -y : plus aucune demande de confirmation"
    assert_contient "$(erreur)" "[INFO] Fichier d'échange : $FICHIER_ESSAI" \
        "configure-swap.sh avec -y : le chemin donné est bien retenu"

    # La suite appartient au contrat de cet environnement, et non au correctif :
    # swapon y est refusé. Si ce code passait un jour à 0, le swap aurait été
    # RÉELLEMENT activé et le saut du groupe 5 aurait cessé d'être vrai — mieux
    # vaut alors une assertion rouge qu'un silence.
    assert_code 1 "$CODE" "configure-swap.sh avec -y : swapon refusé au conteneur, échec d'exécution"
    assert_contient "$(erreur)" "[ERROR] L'activation du swap a échoué." \
        "configure-swap.sh avec -y : l'échec de swapon est diagnostiqué"
    if [ -e "$FICHIER_ESSAI" ]; then
        ko "configure-swap.sh supprime le fichier d'échange incomplet" "$FICHIER_ESSAI subsiste"
    else
        ok "configure-swap.sh supprime le fichier d'échange incomplet"
    fi

    empreinte "$REP_TMP/y-apres"
    assert_empreinte_egale "$REP_TMP/y-avant" "$REP_TMP/y-apres" \
        "l'exécution réelle du groupe 3 bis ne laisse rien hors du répertoire jetable"
fi

# ===================================================================
# 3 ter. Le chemin par DÉFAUT est contrôlé lui aussi — TASK-019
# ===================================================================
# valider_fichier_swap ne voit que la valeur de --file, à l'analyse des
# arguments : le chemin par défaut /swapfile ne lui était jamais soumis, et
# c'est pourtant la même cible et le même « rm -f ». TASK-019 a donc ajouté un
# SECOND appel, après require_root.
#
# Les deux moitiés de cette phrase sont éprouvées ici, et elles se tiennent :
# le second appel doit exister — cas a — et il doit être placé APRÈS
# require_root — cas b. Un correctif qui remonterait l'appel avant require_root
# passerait le cas a et ferait rougir le cas b ; un correctif qui retirerait
# l'appel ferait l'inverse.
#
# CE GROUPE ÉCRIT /swapfile — un répertoire, puis un fichier ordinaire — et le
# retire aussitôt. Il exige donc root et un système jetable, et l'empreinte qui
# l'encadre vérifie la restitution plutôt que de la supposer : la garde d'état
# du groupe 4, qui suit, compare l'empreinte à celle du groupe 2 et
# déclarerait tout le groupe NON EXÉCUTÉ si /swapfile subsistait.
titre "3 ter. Le chemin par défaut /swapfile"

if [ "$EST_ROOT" != "true" ]; then
    saute "le contrôle du chemin par défaut /swapfile" \
        "le second appel a lieu après require_root — l'atteindre exige root"
elif [ "$JETABLE" != "true" ]; then
    saute "le contrôle du chemin par défaut /swapfile" \
        "ce groupe crée puis retire /swapfile — réservé à un système jetable"
elif [ -e /swapfile ]; then
    saute "le contrôle du chemin par défaut /swapfile" \
        "/swapfile existe déjà sur ce système — le remplacer sortirait du cadre de ce fichier"
else
    empreinte "$REP_TMP/defaut-avant"

    # a. /swapfile est un répertoire, et aucun --file n'est donné. Sans le
    #    second appel, le script irait jusqu'au « rm -f », qui refuserait — il
    #    n'est pas récursif — et mourrait sur le message brut de rm, doublé de
    #    la ligne du trap. « -y » est armé pour que ce chemin soit réellement
    #    ouvert : sans lui, le script s'arrêterait sur la confirmation refusée
    #    et le défaut resterait invisible.
    mkdir -p /swapfile
    lancer bash "$SWAP_SH" 2G -y
    rmdir /swapfile

    assert_code 2 "$CODE" "configure-swap.sh 2G, /swapfile étant un répertoire : erreur d'usage"
    assert_contient "$(erreur)" "[ERROR] Cible refusée pour --file : « /swapfile » est un répertoire." \
        "configure-swap.sh 2G : le chemin par défaut est contrôlé comme l'est une valeur de --file"
    assert_absent "$(erreur)" "rm: cannot remove" \
        "configure-swap.sh 2G : le rm -f n'est jamais atteint"
    assert_absent "$(erreur)" "Échec (code" \
        "configure-swap.sh 2G : le trap ERR n'ajoute aucune ligne au diagnostic"
    assert_absent "$(erreur)" "Confirmation automatique" \
        "configure-swap.sh 2G : le refus précède toute confirmation"
    assert_absent "$(erreur)" "Opérations prévues" \
        "configure-swap.sh 2G : aucune opération n'est même envisagée"
    # Le DÉCOMPTE, et non les seules absences. Il ne peut pas porter ici sur
    # tout stderr : le refus a lieu après afficher_etat, qui précède
    # require_root, et le flux porte donc aussi l'état du swap. Compter les
    # lignes [ERROR] voit revenir celle du trap même si son libellé change un
    # jour dans lib/common.sh, là où l'assertion d'absence ci-dessus est liée à
    # son texte.
    assert_egal "4" "$(nb_lignes_contenant '[ERROR]')" \
        "configure-swap.sh 2G : stderr porte les quatre lignes du refus, pas une de plus"

    # b. Le second appel est bien APRÈS require_root. /swapfile est cette fois
    #    un fichier ordinaire que le script ne reconnaîtrait pas — et qui, en
    #    mode 600 appartenant à root, n'est même pas lisible par « nobody ».
    #    Placé avant require_root, le contrôle rendrait 2 ; placé après, c'est
    #    le privilège manquant qui est reproché, code 1. Sans cette cible
    #    refusable, les deux placements donneraient le même résultat et le cas
    #    ne prouverait rien : /swapfile absent est accepté par la validation.
    if [ "$SANS_ROOT_DISPONIBLE" != "true" ]; then
        saute "configure-swap.sh 512M sans privilège rend 1 alors que /swapfile est une cible refusable" \
            "aucun lanceur ne parvient à abaisser l'UID sur cet hôte"
    else
        printf 'ceci n%s est pas un fichier d%s échange\n' "'" "'" > /swapfile
        chmod 600 /swapfile
        sans_root bash "$SWAP_SH" 512M
        rm -f /swapfile
        rm -rf "$LOG_DIR_NOBODY"

        assert_code 1 "$CODE" \
            "configure-swap.sh 512M sans privilège : le privilège manquant prime, code 1"
        assert_contient "$(erreur)" "[ERROR] Ce script doit être exécuté en root (ou via sudo)." \
            "configure-swap.sh 512M sans privilège : c'est bien le privilège qui est reproché"
        assert_absent "$(erreur)" "Cible refusée pour --file" \
            "configure-swap.sh 512M sans privilège : la cible n'est pas jugée avant le privilège"
        assert_absent "$(erreur)" "Échec (code" \
            "configure-swap.sh 512M sans privilège : le trap ERR n'ajoute aucune ligne"
    fi

    empreinte "$REP_TMP/defaut-apres"
    assert_empreinte_egale "$REP_TMP/defaut-avant" "$REP_TMP/defaut-apres" \
        "le groupe 3 ter laisse /swapfile dans l'état où il l'a trouvé"
fi

# ===================================================================
# 3 quater. Le trap ERR ne double plus les SUBSTITUTIONS — TASK-018
# ===================================================================
# TASK-016 avait corrigé un CAS — en_megaoctets — là où il y avait un MOTIF :
# toute substitution de commande dont le contenu peut échouer s'exécute dans un
# sous-shell qui hérite du « trap ERR » de lib/common.sh. Le trap parle une
# première fois dans le sous-shell, une seconde dans le shell principal pour
# l'affectation en échec, et aucune des deux lignes ne dit la cause :
#
#   [ERROR] Échec (code 1) à la ligne 195 de configure-swap.sh.
#   [ERROR] Échec (code 1) à la ligne 195 de configure-swap.sh.
#
# TASK-018, second tour, a repris onze sites dans quatre scripts :
# configure-swap.sh, configure-hostname.sh, configure-cron.sh et
# configure-timezone.sh — les deux derniers ayant échappé au recensement du
# premier tour. Deux formes : l'affectation placée en contexte de condition, et
# la fonction qui renseigne une globale au lieu d'écrire sur stdout.
#
# CE GROUPE NE LES PROUVE PAS TOUS, et il faut le savoir pour ne pas s'y fier à
# tort. Ce qui suit vaut pour configure-swap.sh ; les sites de configure-cron.sh
# vivent dans tests/integration/configure-cron.test.sh, celui de
# configure-hostname.sh au groupe 4 bis, ceux de configure-timezone.sh au groupe
# 4 ter. Le compte est établi par MUTATION — chaque site remis en forme nue, le
# fichier de cas relancé — et non par lecture :
#
#   UN site a une cause d'échec atteignable, et sa correction est prouvée ici :
#   « stat » en échec, cas d, par un stub en tête de PATH. Remis en forme nue, il
#   fait rougir ce fichier ;
#
#   UN deuxième — le df -T du répertoire d'accueil — n'avait qu'une cause
#   atteignable, le répertoire absent, et TASK-018 l'a interceptée par un
#   contrôle explicite déplacé dans valider_fichier_swap. C'est ce contrôle que
#   les cas a, b et b bis éprouvent, et rien d'autre : le df -T remis seul en
#   forme nue laisse ce fichier ENTIÈREMENT VERT, la garde le précédant
#   toujours ;
#
#   TROIS ne s'atteignent pas du tout — df -BM et les deux awk sur /proc. Remis
#   en forme nue, aucun ne fait rougir quoi que ce soit. Leur correction reste
#   NON VÉRIFIÉE PAR L'EXÉCUTION, et le groupe 5 la déclare telle, un site à la
#   fois ;
#
#   dirname a fait TROIS allers-retours, et c'est le site le plus instructif du
#   chantier. Corrigé au premier tour ; REMIS en forme nue au second, sa branche
#   « if ! » ayant été jugée du code mort ; remis en condition au cinquième,
#   l'argument de code mort ne couvrant que l'ABSENCE de la commande et jamais
#   son ÉCHEC — un binaire homonyme en tête de PATH l'atteint, comme il a atteint
#   « hostname » derrière son require_cmd. Le cas e ci-dessous l'éprouve, et sa
#   valeur reste éprouvée au cas c.
#
# Ce que ce groupe éprouve à la place des sites hors d'atteinte, c'est la VALEUR
# que ces substitutions rendent — cas c. Une condition mal formée qui renverrait
# la mauvaise valeur ne produirait aucun message : c'est la régression la plus
# discrète de TASK-018, et la seule assertion qui la verrait est celle qui
# compare un nombre mesuré.
#
# Aucun cas de ce groupe n'écrit : chacun meurt avant le résumé des opérations,
# ou tourne en --dry-run. Il est donc placé après le groupe 3 ter et avant la
# garde d'état du groupe 4, qu'il ne trouble pas.
titre "3 quater. Le non-doublement du trap ERR sur les substitutions"

# Le répertoire de stubs et le fichier d'échange témoin vivent dans le
# répertoire jetable du test : rien n'en sort.
REP_STUB="$REP_TMP/stub"
SWAP_TEMOIN="$REP_TMP/swapfile-temoin"

# --- a. Le répertoire d'accueil n'existe pas -------------------------------
# C'est la seule cause d'échec de df qui s'atteigne depuis la ligne de commande,
# donc le seul endroit où la correction de ce site se PROUVE au lieu de se
# garder.
#
# « --file /pas/de/dossier/swapfile » franchissait toute la validation — une
# cible absente est le cas nominal d'une création — puis df n'avait rien à
# mesurer sur un chemin inexistant : le script sortait en 1 sur deux lignes de
# trap muettes. Le refus est désormais explicite, en 2, et prononcé par
# valider_fichier_swap dès l'ANALYSE DES ARGUMENTS.
#
# Le second tour de TASK-018 a déplacé ce contrôle : il était après
# require_root, il est maintenant au moment « avant-root ». La justification du
# placement initial était fausse, et le relecteur l'a mesuré — l'absence d'un
# répertoire se constate sans le moindre privilège. Les deux moitiés du cas
# disent donc la même chose : root ou non, la réponse est 2.
#
# Le DÉCOMPTE est ce qui verrouille le non-doublement : il voit revenir la ligne
# du trap même si son libellé change un jour dans lib/common.sh, là où
# l'assertion d'absence est liée à son texte. Le refus précédant désormais
# afficher_etat, stderr ne porte plus RIEN d'autre : le décompte porte donc
# aussi sur TOUT stderr, et pas seulement sur les lignes [ERROR]. Trois lignes,
# MESURÉES dans le conteneur et non reprises d'un compte rendu.
REP_ABSENT="/pas/de/dossier"
SWAP_SANS_DOSSIER="$REP_ABSENT/swapfile"

# refus_repertoire_absent <libellé> — les neuf assertions du refus, jouées à
# l'identique avec et sans privilège. La duplication serait ici une faiblesse :
# c'est l'IDENTITÉ des deux verdicts qui est l'objet du cas.
refus_repertoire_absent() {
    local libelle="$1"

    assert_code 2 "$CODE" \
        "$libelle : erreur d'usage"
    assert_contient "$(erreur)" "[ERROR] Répertoire introuvable : « $REP_ABSENT »." \
        "$libelle : nomme le répertoire manquant"
    assert_contient "$(erreur)" "[ERROR] Le fichier d'échange « $SWAP_SANS_DOSSIER » ne peut pas y être créé." \
        "$libelle : nomme la cible impossible"
    assert_absent "$(erreur)" "Échec (code" \
        "$libelle : le trap ERR n'ajoute aucune ligne au diagnostic"
    assert_absent "$(erreur)" "df:" \
        "$libelle : df ne voit jamais ce chemin"
    assert_absent "$(erreur)" "configure-swap.sh: line" \
        "$libelle : aucun message brut de bash sur stderr"
    assert_egal "3" "$(nb_lignes_contenant '[ERROR]')" \
        "$libelle : trois lignes [ERROR], pas une de plus"
    assert_egal "3" "$(nb_lignes_erreur)" \
        "$libelle : stderr ne porte QUE ces trois lignes — le refus précède l'affichage d'état"
    assert_absent "$(erreur)" "Opérations prévues" \
        "$libelle : aucune opération n'est même envisagée"
}

if [ -e "$REP_ABSENT" ]; then
    saute "configure-swap.sh --file <répertoire absent> : refus en 2, sans ligne de trap" \
        "$REP_ABSENT existe sur cet hôte — le cas ne porterait plus sur un répertoire absent"
    saute "configure-swap.sh --file <répertoire absent> sans privilège : le même refus, en 2" \
        "$REP_ABSENT existe sur cet hôte — le cas ne porterait plus sur un répertoire absent"
else
    lancer bash "$SWAP_SH" 64M --file "$SWAP_SANS_DOSSIER"
    refus_repertoire_absent "configure-swap.sh --file <répertoire absent>"

    if [ -e "$REP_ABSENT" ]; then
        ko "configure-swap.sh --file <répertoire absent> ne crée rien" "$REP_ABSENT est apparu"
    else
        ok "configure-swap.sh --file <répertoire absent> ne crée rien"
    fi

    # --- b. Le MÊME refus, sans privilège ----------------------------------
    # Les arguments se jugent avant les privilèges : une ligne de commande
    # fautive se reproche en 2 avec ou sans « sudo ». C'est la contrepartie
    # exacte du cas b bis ci-dessous, qui montre le seul verdict que le script
    # ait encore raison de différer.
    if [ "$SANS_ROOT_DISPONIBLE" != "true" ]; then
        saute "configure-swap.sh --file <répertoire absent> sans privilège : le même refus, en 2" \
            "aucun lanceur ne parvient à abaisser l'UID sur cet hôte"
    else
        sans_root bash "$SWAP_SH" 64M --file "$SWAP_SANS_DOSSIER"
        rm -rf "$LOG_DIR_NOBODY"
        refus_repertoire_absent "configure-swap.sh --file <répertoire absent> sans privilège"
        assert_absent "$(erreur)" "doit être exécuté en root" \
            "configure-swap.sh --file <répertoire absent> sans privilège : l'argument fautif prime sur le privilège manquant"
    fi
fi

# --- b bis. Un ANCÊTRE non traversable : le seul verdict différé -----------
# « [ -d /a/b ] » est faux dans deux cas qui n'ont rien à voir : « b » n'existe
# pas, ou « a » existe et n'est pas traversable par celui qui regarde. Le second
# tour de TASK-018 les sépare par ancetres_traversables, et diffère le refus à
# « apres-root » quand la conclusion d'absence ne serait pas fiable.
#
# Sans cette fonction, un appelant sans privilège s'entendrait reprocher en 2 un
# répertoire qui existe parfaitement. C'est la régression que ce cas ferme, et
# elle n'est visible qu'ici : le cas b, dont tous les ancêtres sont traversables,
# reste vert avec ou sans ancetres_traversables.
#
# TROIS moitiés, et c'est leur mise en regard qui prouve quelque chose :
#
#   1. ancêtre opaque, sans privilège -> 1, le privilège manquant, JAMAIS
#      « Répertoire introuvable » ;
#   2. ancêtres traversables et répertoire réellement absent, sans privilège
#      -> 2, le refus ordinaire. C'est le témoin qui interdit de conclure que
#      « sans privilège » vaudrait « toujours différé » ;
#   3. le même chemin qu'en 1, mais en root -> le cas NOMINAL passe, code 0.
#
# Le répertoire opaque vit hors du répertoire jetable du test : « mktemp -d »
# crée en 700, ce qui rendrait tout chemin qu'il contient opaque à « nobody » et
# ferait passer la moitié 2 pour de mauvaises raisons.
REP_OPAQUE="/tmp/mgnet-test-opaque"
SWAP_SOUS_OPAQUE="$REP_OPAQUE/sous/swapfile"
REP_TRAVERSABLE_ABSENT="/tmp/mgnet-test-absent"

if [ "$EST_ROOT" != "true" ]; then
    saute "configure-swap.sh --file <sous un ancêtre opaque> : le verdict est différé" \
        "poser un répertoire en 700 appartenant à root exige root"
elif [ "$SANS_ROOT_DISPONIBLE" != "true" ]; then
    saute "configure-swap.sh --file <sous un ancêtre opaque> : le verdict est différé" \
        "aucun lanceur ne parvient à abaisser l'UID sur cet hôte"
elif [ -e "$REP_OPAQUE" ] || [ -e "$REP_TRAVERSABLE_ABSENT" ]; then
    saute "configure-swap.sh --file <sous un ancêtre opaque> : le verdict est différé" \
        "$REP_OPAQUE ou $REP_TRAVERSABLE_ABSENT existe déjà sur cet hôte"
else
    mkdir -p "$REP_OPAQUE/sous"
    chown root:root "$REP_OPAQUE"
    chmod 700 "$REP_OPAQUE"

    # Deux gardes. Sans elles, la moitié 1 passerait aussi bien sur un chemin
    # simplement absent, et ne prouverait rien de ce qu'elle annonce.
    if "${LANCEUR_SANS_ROOT[@]}" test -x "$REP_OPAQUE" 2>/dev/null; then
        ko "garde : $REP_OPAQUE est opaque à l'utilisateur non privilégié" \
            "il reste traversable — le cas ne porterait pas sur ce qu'il annonce"
    else
        ok "garde : $REP_OPAQUE est opaque à l'utilisateur non privilégié"
    fi
    if [ -d "$REP_OPAQUE/sous" ]; then
        ok "garde : $REP_OPAQUE/sous existe réellement — son absence n'est qu'apparente"
    else
        ko "garde : $REP_OPAQUE/sous existe réellement" "le répertoire n'a pas pu être créé"
    fi

    # 1. Le verdict est différé : c'est le privilège qui est reproché, en 1.
    sans_root bash "$SWAP_SH" 64M --file "$SWAP_SOUS_OPAQUE"
    rm -rf "$LOG_DIR_NOBODY"
    assert_code 1 "$CODE" \
        "configure-swap.sh --file <sous un ancêtre opaque> sans privilège : échec d'exécution, code 1"
    assert_contient "$(erreur)" "[ERROR] Ce script doit être exécuté en root (ou via sudo)." \
        "configure-swap.sh --file <sous un ancêtre opaque> sans privilège : c'est le privilège qui est reproché"
    assert_absent "$(erreur)" "Répertoire introuvable" \
        "configure-swap.sh --file <sous un ancêtre opaque> sans privilège : un répertoire qui EXISTE n'est jamais déclaré introuvable"
    assert_absent "$(erreur)" "Échec (code" \
        "configure-swap.sh --file <sous un ancêtre opaque> sans privilège : le trap ERR n'ajoute aucune ligne"
    assert_egal "1" "$(nb_lignes_contenant '[ERROR]')" \
        "configure-swap.sh --file <sous un ancêtre opaque> sans privilège : une seule ligne [ERROR]"

    # 2. Le témoin. Ancêtres traversables — /tmp est en 1777 — et répertoire
    #    réellement absent : le refus ordinaire tranche, sans privilège.
    sans_root bash "$SWAP_SH" 64M --file "$REP_TRAVERSABLE_ABSENT/swapfile"
    rm -rf "$LOG_DIR_NOBODY"
    assert_code 2 "$CODE" \
        "témoin : <répertoire absent sous des ancêtres traversables>, sans privilège : erreur d'usage"
    assert_contient "$(erreur)" "[ERROR] Répertoire introuvable : « $REP_TRAVERSABLE_ABSENT »." \
        "témoin : le refus ordinaire tranche sans privilège — le différé n'est pas la règle générale"

    # 3. Le chemin NOMINAL, en root. Un ancetres_traversables trop gourmand
    #    refuserait ici un chemin parfaitement valide.
    lancer bash "$SWAP_SH" 64M --file "$SWAP_SOUS_OPAQUE" --dry-run
    assert_code 0 "$CODE" \
        "configure-swap.sh --file <sous un ancêtre opaque> en root : le chemin nominal passe"
    assert_contient "$(erreur)" "créer      $SWAP_SOUS_OPAQUE (64 Mo)" \
        "configure-swap.sh --file <sous un ancêtre opaque> en root : la création est annoncée"
    assert_egal "0" "$(nb_lignes_contenant '[ERROR]')" \
        "configure-swap.sh --file <sous un ancêtre opaque> en root : aucune ligne [ERROR]"

    rm -rf "$REP_OPAQUE"
    if [ -e "$REP_OPAQUE" ]; then
        ko "le répertoire opaque jetable est supprimé" "$REP_OPAQUE subsiste"
    else
        ok "le répertoire opaque jetable est supprimé"
    fi
fi
# --- c. La VALEUR rendue par dirname et par df -BM -------------------------
# Les affectations corrigées de configure-swap.sh sont en contexte de condition.
# Une condition mal formée qui rendrait la MAUVAISE VALEUR ne produirait aucun
# message : le script continuerait sur un nombre faux. Aucune assertion
# d'absence, aucun décompte de lignes ne le verrait.
#
# Ce cas vaut aussi pour dirname, désormais en condition lui aussi (cinquième
# tour). Son non-doublement est éprouvé au cas e ; ce qu'aucune assertion de ce
# cas-là ne verrait, c'est une condition bien formée qui rendrait la MAUVAISE
# valeur — le script continuerait sans un mot. C'est ici que cela se voit.
#
# Deux valeurs sont donc mesurées, par le seul chemin qui les fasse apparaître à
# l'écran :
#
#   repertoire_swap   « Espace insuffisant sur / » — dirname /swapfile vaut « / »
#   espace_libre_mo   le nombre de mégaoctets annoncé, confronté à celui que le
#                     harnais mesure lui-même par le même df
#
# La taille demandée est calculée à partir de l'espace réellement libre : le cas
# ne dépend d'aucune constante et reste vrai sur un disque de n'importe quelle
# taille. Le script meurt avant le résumé des opérations — rien n'est écrit.
#
# La comparaison admet un écart : l'espace libre du conteneur bouge de quelques
# mégaoctets pendant l'exécution — journaux, index apt. La tolérance est de
# 64 Mo, assez pour absorber ce bruit et bien trop peu pour laisser passer une
# erreur d'un gigaoctet. Ce qui est prouvé n'est pas l'égalité au mégaoctet
# près, mais que la substitution rend une MESURE, et non zéro, ni une chaîne
# vide, ni la ligne d'en-tête de df.
if [ "$EST_ROOT" != "true" ]; then
    saute "configure-swap.sh : les substitutions rendent la bonne valeur" \
        "le calcul d'espace a lieu après require_root — l'atteindre exige root"
elif [ -e /swapfile ]; then
    saute "configure-swap.sh : les substitutions rendent la bonne valeur" \
        "/swapfile existe sur cet hôte — sa taille entrerait dans le besoin net et fausserait la mesure"
else
    ESPACE_MESURE="$(df -P -BM / | awk 'NR == 2 { gsub(/M/, "", $4); print $4 }')"
    if ! [ "${ESPACE_MESURE:-0}" -gt 0 ] 2>/dev/null; then
        saute_indisponible "configure-swap.sh : les substitutions rendent la bonne valeur" \
            "le harnais n'a pas pu mesurer lui-même l'espace libre de / — la comparaison n'aurait pas de référence"
    else
        TAILLE_EXCESSIVE=$(( ESPACE_MESURE + 1024 ))
        lancer bash "$SWAP_SH" "${TAILLE_EXCESSIVE}M" --dry-run

        assert_code 1 "$CODE" \
            "configure-swap.sh <taille supérieure à l'espace libre> : échec d'exécution"
        assert_contient "$(erreur)" "[ERROR] Espace insuffisant sur / :" \
            "configure-swap.sh : dirname rend bien « / » comme répertoire d'accueil de /swapfile"
        assert_contient "$(erreur)" "Mo nécessaires." \
            "configure-swap.sh : le besoin net est calculé et annoncé"
        assert_absent "$(erreur)" "Échec (code" \
            "configure-swap.sh <taille supérieure à l'espace libre> : le trap ERR n'ajoute aucune ligne"
        assert_egal "2" "$(nb_lignes_contenant '[ERROR]')" \
            "configure-swap.sh <taille supérieure à l'espace libre> : stderr porte les deux lignes du refus, pas une de plus"
        assert_absent "$(erreur)" "Opérations prévues" \
            "configure-swap.sh <taille supérieure à l'espace libre> : aucune opération n'est même envisagée"

        # La valeur elle-même, extraite du diagnostic et confrontée à la mesure
        # du harnais. C'est la seule assertion de ce fichier qui verrait une
        # condition rendant une valeur fausse sans rien dire.
        ESPACE_ANNONCE="$(sed -n 's/^.*Espace insuffisant sur \/ : \([0-9][0-9]*\) Mo libres.*$/\1/p' "$F_ERR" | tail -n 1)"
        if [ -z "$ESPACE_ANNONCE" ]; then
            ko "configure-swap.sh : df -BM rend une mesure d'espace libre" \
                "aucun nombre n'a pu être extrait du diagnostic"
        elif ! [ "$ESPACE_ANNONCE" -gt 0 ] 2>/dev/null; then
            ko "configure-swap.sh : df -BM rend une mesure d'espace libre" \
                "espace annoncé « $ESPACE_ANNONCE », mesuré $ESPACE_MESURE Mo"
        else
            if [ "$ESPACE_ANNONCE" -ge "$ESPACE_MESURE" ]; then
                ECART=$(( ESPACE_ANNONCE - ESPACE_MESURE ))
            else
                ECART=$(( ESPACE_MESURE - ESPACE_ANNONCE ))
            fi
            if [ "$ECART" -le 64 ]; then
                ok "configure-swap.sh : df -BM rend une mesure d'espace libre — $ESPACE_ANNONCE Mo annoncés, $ESPACE_MESURE Mo mesurés par le harnais"
            else
                ko "configure-swap.sh : df -BM rend une mesure d'espace libre" \
                    "espace annoncé $ESPACE_ANNONCE Mo, mesuré $ESPACE_MESURE Mo — écart de $ECART Mo"
            fi
        fi
    fi
fi

# --- d. « stat » en échec : lire_taille_actuelle ---------------------------
# Sous l'ancienne forme — « TAILLE_ACTUELLE_MO="$(taille_actuelle_mo)" », la
# fonction rendant sa valeur par printf autour de « $(stat …) » — un stat en
# échec faisait parler le trap plusieurs fois. La fonction renseigne désormais
# une globale et la lecture est en condition : un seul diagnostic, qui nomme la
# cause.
#
# CE QUE LA MUTATION A RÉELLEMENT MESURÉ, et qui corrige le commentaire du
# script lui-même — il annonce « trois fois ». Sous la forme nue, stderr porte :
#
#   [ERROR] Échec (code 1) à la ligne 490 de configure-swap.sh.
#   configure-swap.sh: line 490: / 1024 / 1024 : syntax error: operand expected
#   [ERROR] Échec (code 1) à la ligne 496 de configure-swap.sh.
#
# soit DEUX lignes [ERROR] du trap, et non trois, plus un message brut de bash :
# la substitution interne vidée, l'arithmétique « $(( / 1024 / 1024 )) » devient
# une erreur de syntaxe. Le décompte à deux ne rougit donc PAS sous cette
# mutation — l'ancienne forme en produisait deux elle aussi. Ce qui rougit, ce
# sont les deux assertions de contenu : le diagnostic métier est absent, et
# « Échec (code » présent. Le décompte les borde, il ne les remplace pas, et
# l'assertion sur le message brut de bash ferme la troisième ligne.
#
# L'échec est provoqué par un faux « stat » en tête de PATH — le seul moyen
# d'atteindre ce site, la disparition du fichier entre le test et la lecture
# n'étant pas reproductible. Le PATH n'est modifié que pour l'appel : le harnais
# garde le sien.
#
# La cible doit être un fichier d'échange reconnu, sans quoi valider_fichier_swap
# la refuserait avant que lire_taille_actuelle ne soit atteinte. D'où le fichier
# réellement produit par mkswap, et la garde qui vérifie que le MÊME appel
# réussit SANS le stub : sans elle, un refus de cible ou un mkswap muet rendrait
# le cas vert pour la mauvaise raison.
if [ "$EST_ROOT" != "true" ]; then
    saute "configure-swap.sh : « stat » en échec ne produit qu'un diagnostic" \
        "la lecture de taille a lieu après require_root — l'atteindre exige root"
elif ! command -v mkswap >/dev/null 2>&1; then
    saute_indisponible "configure-swap.sh : « stat » en échec ne produit qu'un diagnostic" \
        "mkswap est absent — aucune cible reconnue comme fichier d'échange ne peut être préparée"
else
    dd if=/dev/zero of="$SWAP_TEMOIN" bs=1M count=64 status=none 2>/dev/null
    chmod 600 "$SWAP_TEMOIN"

    if ! mkswap "$SWAP_TEMOIN" >/dev/null 2>&1; then
        saute_indisponible "configure-swap.sh : « stat » en échec ne produit qu'un diagnostic" \
            "mkswap n'a pas pu préparer $SWAP_TEMOIN — la cible ne serait pas reconnue comme fichier d'échange"
    else
        # Garde 1 : sans le stub, le même appel passe, et rend la BONNE taille.
        # Ce qui échouera ensuite est donc bien « stat », et rien d'autre.
        lancer bash "$SWAP_SH" 64M --file "$SWAP_TEMOIN" --dry-run
        assert_code 0 "$CODE" \
            "garde : sans le stub, configure-swap.sh --file <fichier mkswap> --dry-run passe"
        assert_contient "$(erreur)" "remplacer  $SWAP_TEMOIN (64 Mo -> 64 Mo)" \
            "garde : lire_taille_actuelle rend bien 64 Mo — la valeur, et pas seulement l'absence d'erreur"

        # Garde 2 : le stub échoue réellement. Un stub muet rendrait tout le cas
        # creux.
        mkdir -p "$REP_STUB"
        printf '#!/bin/sh\nexit 1\n' > "$REP_STUB/stat"
        chmod +x "$REP_STUB/stat"
        if "$REP_STUB/stat" -c %s "$SWAP_TEMOIN" >/dev/null 2>&1; then
            ko "garde : le faux « stat » échoue bien" "le stub a rendu 0"
        else
            ok "garde : le faux « stat » échoue bien"
        fi

        lancer env "PATH=$REP_STUB:$PATH" bash "$SWAP_SH" 64M --file "$SWAP_TEMOIN" --dry-run

        assert_code 1 "$CODE" \
            "configure-swap.sh, « stat » en échec : échec d'exécution"
        assert_contient "$(erreur)" "[ERROR] Taille de $SWAP_TEMOIN illisible." \
            "configure-swap.sh, « stat » en échec : le diagnostic nomme la cause"
        assert_absent "$(erreur)" "Échec (code" \
            "configure-swap.sh, « stat » en échec : le trap ERR n'ajoute aucune ligne"
        assert_absent "$(erreur)" "configure-swap.sh: line" \
            "configure-swap.sh, « stat » en échec : aucun message brut de bash sur stderr"
        assert_egal "2" "$(nb_lignes_contenant '[ERROR]')" \
            "configure-swap.sh, « stat » en échec : deux lignes [ERROR] — celles du diagnostic, mesurées"
        assert_absent "$(erreur)" "Opérations prévues" \
            "configure-swap.sh, « stat » en échec : aucune opération n'est envisagée sur une taille inconnue"

        rm -rf "$REP_STUB"
        rm -f "$SWAP_TEMOIN"
    fi
fi
# ===================================================================
# 3 quinquies. Les lectures DÉGRADÉES — system-info.sh, update-system.sh
# ===================================================================
# Quatrième tour de TASK-018. Le recensement avait manqué system-info.sh en
# entier, plus le décompte de paquets d'update-system.sh. Trois affectations y
# sont passées en contexte de condition, et elles ont une propriété commune que
# les précédentes n'avaient pas : LEUR ÉCHEC N'EST PAS FATAL.
#
# C'est le point que ce groupe verrouille, et il compte plus que le décompte de
# lignes. system-info.sh est un script de diagnostic en lecture seule : sa nature
# est de DÉGRADER — « non disponible » — pas de mourir parce qu'un nproc manque.
# Sous la forme nue, un faux nproc en tête de PATH le tuait en 1 sur deux lignes
# de trap. L'assertion décisive de chaque cas est donc « code 0 », et la valeur
# affichée juste après.
#
# COMMENT LIRE LES DÉCOMPTES DE CE FICHIER. Le nombre de lignes que le trap ERR
# produit n'est PAS un invariant du motif : il dépend de la profondeur d'appel et
# du flux. Mesuré par le relecteur — une affectation dont la substitution appelle
# une FONCTION en produit trois, une affectation directe en produit deux, et une
# substitution en POSITION D'ARGUMENT n'en produit aucune, le script poursuivant
# alors son cours. Voir Linux/System/recensement-substitutions.md §1. Chaque
# décompte de ce fichier est donc mesuré sur son site, jamais déduit d'un autre.
#
# Aucun cas de ce groupe n'écrit dans /etc : system-info.sh ne fait que lire, et
# update-system.sh tourne en --dry-run. Le groupe est placé avant la garde d'état
# du groupe 4, qu'il ne trouble pas.
titre "3 quinquies. Les lectures dégradées — system-info.sh, update-system.sh"

# valeur_de_ligne <libellé> — la valeur que system-info.sh affiche en face de ce
# libellé, sur le stdout du dernier « lancer ».
#
# Le remplissage est calculé par le script à partir de la longueur du libellé :
# le recopier ici figerait une mise en forme qui ne regarde pas ces cas. On lit
# donc la valeur, pas la ligne entière — et c'est la VALEUR qui est l'objet de la
# preuve : « non disponible » plutôt qu'un nombre, ou l'inverse.
valeur_de_ligne() {
    local libelle="$1" ligne
    while IFS= read -r ligne || [ -n "$ligne" ]; do
        case "$ligne" in
            "  $libelle"*)
                ligne="${ligne#"  $libelle"}"
                while [ "${ligne# }" != "$ligne" ]; do
                    ligne="${ligne# }"
                done
                printf '%s' "$ligne"
                return 0
                ;;
        esac
    done < "$F_OUT"
    return 0
}

REP_STUB_NPROC="$REP_TMP/stub-nproc"
REP_STUB_AWK="$REP_TMP/stub-awk"
REP_SANS_FREE="$REP_TMP/bin-sans-free"
REP_STUB_WC="$REP_TMP/stub-wc"
REP_STUB_APT="$REP_TMP/stub-apt"

# --- a. « nproc » en échec : le script dégrade, il ne meurt pas -------------
# « command -v nproc » établissait que la commande existe, pas qu'elle réussit.
# C'est la même erreur de raisonnement que « require_cmd hostname », et elle se
# dément de la même façon : un binaire homonyme en tête de PATH.
if [ "$EST_LINUX" != "true" ]; then
    saute "system-info.sh : « nproc » en échec dégrade sans tuer le script" \
        "ces scripts ne s'exécutent pas hors Linux"
else
    mkdir -p "$REP_STUB_NPROC"
    printf '#!/bin/sh\nexit 1\n' > "$REP_STUB_NPROC/nproc"
    chmod +x "$REP_STUB_NPROC/nproc"
    if "$REP_STUB_NPROC/nproc" >/dev/null 2>&1; then
        ko "garde : le faux « nproc » échoue bien" "le stub a rendu 0"
    else
        ok "garde : le faux « nproc » échoue bien"
    fi

    # Garde de contraste : SANS le stub, la valeur est un nombre. Sans elle, le
    # cas serait vert sur une machine où « Cœurs logiques » vaudrait déjà
    # « non disponible » pour une tout autre raison.
    lancer bash "$INFO_SH"
    assert_code 0 "$CODE" "garde : system-info.sh sans stub sort en 0"
    COEURS_NOMINAL="$(valeur_de_ligne "Cœurs logiques")"
    if [ -n "$COEURS_NOMINAL" ] && [ "$COEURS_NOMINAL" != "non disponible" ]; then
        ok "garde : system-info.sh sans stub affiche un nombre de cœurs — « $COEURS_NOMINAL »"
    else
        ko "garde : system-info.sh sans stub affiche un nombre de cœurs" \
            "valeur obtenue « $COEURS_NOMINAL » — le cas ne prouverait rien"
    fi

    lancer env "PATH=$REP_STUB_NPROC:$PATH" bash "$INFO_SH"
    # L'assertion décisive. Sous la forme nue, ce code valait 1.
    assert_code 0 "$CODE" \
        "system-info.sh, « nproc » en échec : sort en 0 — un script de diagnostic dégrade, il ne meurt pas"
    assert_egal "non disponible" "$(valeur_de_ligne "Cœurs logiques")" \
        "system-info.sh, « nproc » en échec : la valeur dégrade en « non disponible »"
    assert_contient "$(erreur)" "[WARN] « nproc » a échoué : le nombre de cœurs logiques reste indéterminé." \
        "system-info.sh, « nproc » en échec : la cause est nommée"
    assert_absent "$(erreur)" "Échec (code" \
        "system-info.sh, « nproc » en échec : le trap ERR n'ajoute aucune ligne"
    assert_absent "$(erreur)" "system-info.sh: line" \
        "system-info.sh, « nproc » en échec : aucun message brut de bash sur stderr"
    assert_egal "0" "$(nb_lignes_contenant '[ERROR]')" \
        "system-info.sh, « nproc » en échec : aucune ligne [ERROR] — ce n'est pas une erreur, c'est une lacune"
    assert_egal "1" "$(nb_lignes_contenant '[WARN]')" \
        "system-info.sh, « nproc » en échec : un seul avertissement mesuré"
    assert_egal "1" "$(nb_lignes_erreur)" \
        "system-info.sh, « nproc » en échec : stderr ne porte QUE cet avertissement"
    # Non-régression : le reste du rapport est intact. Une dégradation ne doit
    # pas en emporter d'autres.
    for section in $SECTIONS; do
        assert_contient "$(sortie)" "$section" \
            "system-info.sh, « nproc » en échec : la section « $section » est toujours produite"
    done

    rm -rf "$REP_STUB_NPROC"
fi

# --- b. « awk » en échec sur /proc/meminfo : la branche de repli ------------
# Ces deux lectures ne sont atteintes que si « free » est ABSENT : le script le
# préfère quand il existe. Le masquer est donc la première moitié du montage, et
# elle ne se fait pas en le mettant en échec — « command -v free » réussirait
# encore et la branche resterait fermée. Un bac à sable de liens symboliques
# reproduit le PATH sans lui, et rien n'est touché sur le système.
#
# La seconde moitié est un faux « awk » SÉLECTIF : il ne refuse que les lectures
# de MemTotal et MemAvailable, et délègue tout le reste au vrai awk. Un stub
# total casserait les cinq autres awk de ce script et le cas ne dirait plus quel
# site a parlé.
if [ "$EST_LINUX" != "true" ] || [ ! -r /proc/meminfo ]; then
    saute "system-info.sh : « awk » en échec sur /proc/meminfo" \
        "exige un Linux avec /proc/meminfo lisible"
else
    mkdir -p "$REP_SANS_FREE" "$REP_STUB_AWK"
    for repertoire in /usr/local/sbin /usr/local/bin /usr/sbin /usr/bin /sbin /bin; do
        [ -d "$repertoire" ] || continue
        for binaire in "$repertoire"/*; do
            nom="${binaire##*/}"
            [ "$nom" != "free" ] || continue
            [ -e "$REP_SANS_FREE/$nom" ] || ln -s "$binaire" "$REP_SANS_FREE/$nom" 2>/dev/null || true
        done
    done

    {
        printf '#!/bin/sh\n'
        printf 'case "$*" in *MemTotal*|*MemAvailable*) exit 1 ;; esac\n'
        printf 'exec %s "$@"\n' "$(command -v awk)"
    } > "$REP_STUB_AWK/awk"
    chmod +x "$REP_STUB_AWK/awk"

    # Trois gardes. Sans elles, le cas serait vert parce que le montage a raté.
    if PATH="$REP_SANS_FREE" command -v free >/dev/null 2>&1; then
        ko "garde : « free » est bien masqué dans le bac à sable" \
            "il y reste visible — la branche /proc/meminfo ne serait pas atteinte"
    else
        ok "garde : « free » est bien masqué dans le bac à sable"
    fi
    if "$REP_STUB_AWK/awk" '/^MemTotal:/ {print}' /proc/meminfo >/dev/null 2>&1; then
        ko "garde : le faux « awk » refuse les lectures de MemTotal" "le stub a rendu 0"
    else
        ok "garde : le faux « awk » refuse les lectures de MemTotal"
    fi
    # Les guillemets simples sont VOULUS : « $1 » est un champ awk, à développer
    # par awk et non par bash. C'est ce que SC2016 signale, et c'est ce qu'on veut.
    # shellcheck disable=SC2016
    if "$REP_STUB_AWK/awk" '{print $1}' /proc/uptime >/dev/null 2>&1; then
        ok "garde : le faux « awk » délègue tout le reste au vrai awk"
    else
        ko "garde : le faux « awk » délègue tout le reste au vrai awk" "le stub a refusé une lecture qu'il devait déléguer"
    fi

    # Garde de contraste : le bac à sable SEUL ouvre bien la branche de repli, et
    # elle rend un vrai nombre. C'est ce qui distingue « awk a échoué » de
    # « la branche n'a jamais été atteinte ».
    lancer env "PATH=$REP_SANS_FREE" bash "$INFO_SH"
    assert_code 0 "$CODE" "garde : system-info.sh sans « free » sort en 0"
    RAM_NOMINALE="$(valeur_de_ligne "RAM totale")"
    if [ -n "$RAM_NOMINALE" ] && [ "$RAM_NOMINALE" != "non disponible" ]; then
        ok "garde : la branche /proc/meminfo est bien empruntée et rend une valeur — « $RAM_NOMINALE »"
    else
        ko "garde : la branche /proc/meminfo est bien empruntée et rend une valeur" \
            "valeur obtenue « $RAM_NOMINALE » — le cas suivant ne prouverait rien"
    fi

    lancer env "PATH=$REP_STUB_AWK:$REP_SANS_FREE" bash "$INFO_SH"
    assert_code 0 "$CODE" \
        "system-info.sh, « awk » en échec sur /proc/meminfo : sort en 0"
    assert_egal "non disponible" "$(valeur_de_ligne "RAM totale")" \
        "system-info.sh, « awk » en échec : RAM totale dégrade en « non disponible »"
    assert_egal "non disponible" "$(valeur_de_ligne "RAM disponible")" \
        "system-info.sh, « awk » en échec : RAM disponible dégrade en « non disponible »"
    assert_contient "$(erreur)" "[WARN] MemTotal illisible dans /proc/meminfo : « awk » a échoué." \
        "system-info.sh, « awk » en échec : la première lecture nomme sa cause"
    assert_contient "$(erreur)" "[WARN] MemAvailable illisible dans /proc/meminfo : « awk » a échoué." \
        "system-info.sh, « awk » en échec : la seconde lecture nomme sa cause"
    assert_absent "$(erreur)" "Échec (code" \
        "system-info.sh, « awk » en échec : le trap ERR n'ajoute aucune ligne"
    assert_absent "$(erreur)" "system-info.sh: line" \
        "system-info.sh, « awk » en échec : aucun message brut de bash sur stderr"
    assert_egal "0" "$(nb_lignes_contenant '[ERROR]')" \
        "system-info.sh, « awk » en échec : aucune ligne [ERROR]"
    assert_egal "2" "$(nb_lignes_contenant '[WARN]')" \
        "system-info.sh, « awk » en échec : deux avertissements mesurés, un par lecture"
    assert_egal "2" "$(nb_lignes_erreur)" \
        "system-info.sh, « awk » en échec : stderr ne porte QUE ces deux avertissements"
    assert_contient "$(sortie)" "Stockage" \
        "system-info.sh, « awk » en échec : les sections suivantes sont toujours produites"

    rm -rf "$REP_SANS_FREE" "$REP_STUB_AWK"
fi

# --- c. « wc » en échec : le décompte de paquets d'update-system.sh ---------
# Ce site n'est atteint que si la simulation d'apt-get annonce au moins un
# paquet : sans cela le script sort plus haut sur « Le système est à jour ».
# L'image de test n'a aucun paquet obsolète — mesuré, le cas nominal du groupe 3
# emprunte cette sortie-là — d'où un faux « apt-get » qui répond deux lignes
# « Inst » à « -s upgrade » et délègue tout le reste au vrai apt-get, « update »
# compris.
#
# Les deux stubs vivent dans DEUX répertoires distincts, et ce n'est pas un
# détail : la garde de contraste a besoin du faux apt-get SANS le faux wc.
#
# Le « --dry-run » borne le cas : rien n'est installé, et l'index de paquets est
# la seule chose qu'apt écrive — ce que le groupe 3 fait déjà.
if [ "$EST_ROOT" != "true" ]; then
    saute "update-system.sh : « wc » en échec laisse « ? paquet(s) »" \
        "require_root arrête le script avant la simulation"
elif [ "$EST_DEBIAN" != "true" ]; then
    saute "update-system.sh : « wc » en échec laisse « ? paquet(s) »" \
        "l'hôte n'est ni Debian ni Ubuntu — require_os refuse le script"
else
    mkdir -p "$REP_STUB_WC" "$REP_STUB_APT"
    printf '#!/bin/sh\nexit 1\n' > "$REP_STUB_WC/wc"
    # Les guillemets simples sont VOULUS ici aussi : ces printf écrivent le CORPS
    # d'un script, et « $1 », « $2 » et « $@ » doivent y arriver littéralement
    # pour être développés par le stub à son exécution, pas ici.
    # shellcheck disable=SC2016
    {
        printf '#!/bin/sh\n'
        printf 'if [ "$1" = "-s" ] && [ "$2" = "upgrade" ]; then\n'
        printf '  echo "Inst mgnet-essai-un (1.0-1 Debian:12 [amd64])"\n'
        printf '  echo "Inst mgnet-essai-deux (2.0-1 Debian:12 [amd64])"\n'
        printf '  exit 0\n'
        printf 'fi\n'
        printf 'exec %s "$@"\n' "$(command -v apt-get)"
    } > "$REP_STUB_APT/apt-get"
    chmod +x "$REP_STUB_WC/wc" "$REP_STUB_APT/apt-get"

    if "$REP_STUB_WC/wc" -l < /etc/hostname >/dev/null 2>&1; then
        ko "garde : le faux « wc » échoue bien" "le stub a rendu 0"
    else
        ok "garde : le faux « wc » échoue bien"
    fi
    if [ "$("$REP_STUB_APT/apt-get" -s upgrade | grep -c '^Inst ')" = "2" ]; then
        ok "garde : le faux « apt-get » annonce bien deux paquets à installer"
    else
        ko "garde : le faux « apt-get » annonce bien deux paquets à installer" \
            "la simulation ne rend pas deux lignes « Inst »"
    fi

    # Garde de contraste : avec le seul faux apt-get, le décompte est un NOMBRE.
    # Sans elle, le « ? » du cas suivant pourrait venir d'ailleurs.
    lancer env "PATH=$REP_STUB_APT:$PATH" bash "$UPDATE_SH" --dry-run
    assert_code 0 "$CODE" "garde : update-system.sh --dry-run sort en 0 avec le seul faux apt-get"
    assert_contient "$(erreur)" "[INFO] 2 paquet(s) à mettre à jour :" \
        "garde : sans le faux « wc », le décompte est un nombre"

    lancer env "PATH=$REP_STUB_WC:$REP_STUB_APT:$PATH" bash "$UPDATE_SH" --dry-run
    assert_code 0 "$CODE" \
        "update-system.sh, « wc » en échec : sort en 0 — le décompte ne sert qu'à l'affichage"
    assert_contient "$(erreur)" "[INFO] ? paquet(s) à mettre à jour :" \
        "update-system.sh, « wc » en échec : le décompte dégrade en « ? », et non en chaîne vide"
    assert_contient "$(erreur)" "[WARN] Décompte des paquets impossible : « wc » ou « tr » a échoué." \
        "update-system.sh, « wc » en échec : la cause est nommée"
    assert_contient "$(erreur)" "mgnet-essai-un" \
        "update-system.sh, « wc » en échec : la LISTE des paquets est produite malgré tout"
    assert_contient "$(erreur)" "[INFO] Mode --dry-run : aucune modification effectuée." \
        "update-system.sh, « wc » en échec : le script va jusqu'au bout de son chemin"
    assert_absent "$(erreur)" "Échec (code" \
        "update-system.sh, « wc » en échec : le trap ERR n'ajoute aucune ligne"
    assert_absent "$(erreur)" "update-system.sh: line" \
        "update-system.sh, « wc » en échec : aucun message brut de bash sur stderr"
    assert_egal "0" "$(nb_lignes_contenant '[ERROR]')" \
        "update-system.sh, « wc » en échec : aucune ligne [ERROR]"
    assert_egal "1" "$(nb_lignes_contenant '[WARN]')" \
        "update-system.sh, « wc » en échec : un seul avertissement mesuré"

    rm -rf "$REP_STUB_WC" "$REP_STUB_APT"
fi

# ===================================================================
# 3 sexies. Les sept sites FERMÉS au cinquième tour — TASK-018
# ===================================================================
# Le quatrième tour laissait six affectations en forme nue, plus le « dirname »
# de configure-swap.sh, avec une raison écrite pour chacune. Le relecteur a
# qualifié cela d'ABANDON DÉGUISÉ, et il avait raison : la raison invoquée était
# toujours la même — « aucune cause n'atteint ce site » — et elle a été démentie
# quatre fois de suite par la même mutation d'une ligne, un binaire homonyme en
# tête de PATH.
#
# Le cas de dirname mérite d'être retenu, parce qu'il est allé et venu trois
# fois : corrigé au premier tour, REMIS en forme nue au second — sa branche
# « if ! » ayant été jugée du code mort —, remis en condition au cinquième.
# L'argument de code mort couvrait l'ABSENCE de la commande, jamais son ÉCHEC.
# C'est mot pour mot celui qui protégeait « NOM_ACTUEL="$(hostname)" » derrière un
# require_cmd, et qui n'a pas tenu davantage.
#
# Quatre sites se prouvent sans rien écrire, et sont ici. Les trois autres —
# deux « date » et la boucle de suffixe — modifient ou s'exécutent après une
# activation de swap : ils sont au groupe 4 quinquies.
#
# LES STUBS SONT SÉLECTIFS, et il faut savoir pourquoi. Un faux « dirname » total
# casserait les trois lignes de résolution en tête de chaque script, qui
# l'appellent AVANT le chargement du socle ; un faux « sed » total tuerait
# afficher_etat, qui s'exécute avant en_megaoctets ; un faux « basename » total
# ferait échouer le « LOG_FILE="$LOG_DIR/$(basename …).log" » de lib/common.sh —
# une affectation, donc un doublement, mais dans le socle et non dans le site
# visé. Chaque stub ne refuse donc que l'appel du site éprouvé et délègue le
# reste au vrai binaire, dont le chemin absolu est résolu ici : le PATH est
# détourné, un « exec dirname » se rappellerait lui-même à l'infini.
titre "3 sexies. Les sept sites fermés au cinquième tour"

REP_STUB_DIRNAME="$REP_TMP/stub-dirname"
REP_STUB_SED="$REP_TMP/stub-sed"
REP_STUB_TR2="$REP_TMP/stub-tr2"
REP_STUB_BASENAME="$REP_TMP/stub-basename"

# --- e. « dirname » en échec — le site tranché trois fois -------------------
# Sa branche n'a jamais été empruntée jusqu'ici : c'est le premier cas du dépôt à
# l'ouvrir. Le stub ne refuse que l'appel portant « -- », qui est la signature du
# site — les lignes de résolution appellent « dirname "$_dir" », sans séparateur.
if [ "$EST_ROOT" != "true" ]; then
    saute "configure-swap.sh : « dirname » en échec" \
        "le site est après require_root — l'atteindre exige root"
else
    mkdir -p "$REP_STUB_DIRNAME"
    # Guillemets simples VOULUS : ces printf écrivent le CORPS d'un script, et
    # « $1 » comme « $@ » doivent y arriver littéralement pour être développés
    # par le stub à son exécution, pas ici. C'est ce que SC2016 signale.
    # shellcheck disable=SC2016
    {
        printf '#!/bin/sh\n'
        printf 'if [ "$1" = "--" ]; then exit 1; fi\n'
        printf 'exec %s "$@"\n' "$(command -v dirname)"
    } > "$REP_STUB_DIRNAME/dirname"
    chmod +x "$REP_STUB_DIRNAME/dirname"

    if "$REP_STUB_DIRNAME/dirname" -- /a/b >/dev/null 2>&1; then
        ko "garde : le faux « dirname » refuse l'appel avec « -- »" "le stub a rendu 0"
    else
        ok "garde : le faux « dirname » refuse l'appel avec « -- »"
    fi
    if [ "$("$REP_STUB_DIRNAME/dirname" /a/b 2>/dev/null)" = "/a" ]; then
        ok "garde : le faux « dirname » délègue les autres appels au vrai binaire"
    else
        ko "garde : le faux « dirname » délègue les autres appels au vrai binaire" \
            "l'appel sans « -- » n'a pas rendu « /a » — les lignes de résolution ne fonctionneraient pas"
    fi

    lancer env "PATH=$REP_STUB_DIRNAME:$PATH" bash "$SWAP_SH" 512M --dry-run

    assert_code 1 "$CODE" \
        "configure-swap.sh, « dirname » en échec : échec d'exécution, code 1"
    assert_contient "$(erreur)" "[ERROR] Répertoire d'accueil de /swapfile indéterminable : « dirname » a échoué." \
        "configure-swap.sh, « dirname » en échec : le diagnostic NOMME dirname"
    assert_contient "$(erreur)" "[ERROR] Vérifier « dirname » dans le PATH, puis relancer." \
        "configure-swap.sh, « dirname » en échec : le remède est donné"
    assert_absent "$(erreur)" "Échec (code" \
        "configure-swap.sh, « dirname » en échec : le trap ERR n'ajoute aucune ligne"
    assert_absent "$(erreur)" "configure-swap.sh: line" \
        "configure-swap.sh, « dirname » en échec : aucun message brut de bash sur stderr"
    # DEUX lignes, et non une : « error » puis « die ». Mesuré dans le conteneur.
    assert_egal "2" "$(nb_lignes_contenant '[ERROR]')" \
        "configure-swap.sh, « dirname » en échec : deux lignes [ERROR] mesurées"
    assert_absent "$(erreur)" "Opérations prévues" \
        "configure-swap.sh, « dirname » en échec : aucune opération n'est envisagée"

    rm -rf "$REP_STUB_DIRNAME"
fi

# --- f et g. « sed » puis « tr » dans en_megaoctets -------------------------
# Le point de ces deux cas n'est pas le décompte, c'est le CODE et l'ABSENCE d'un
# message. Une taille réellement invalide vaut 2 et dit « Taille invalide » ; un
# outil en échec sur une taille parfaitement valide est un échec d'exécution — 1
# — et ne doit surtout pas la faire passer pour fautive. C'est la seule chose que
# ces deux cas prouvent, et c'est ce qui les rend nécessaires : sans eux, le
# script pourrait reprocher à l'appelant une taille qu'il a bien écrite.
#
# La taille employée est « 512M », que le groupe 3 fait passer sans encombre.
if [ "$EST_ROOT" != "true" ]; then
    saute "configure-swap.sh : « sed » en échec dans en_megaoctets" \
        "en_megaoctets s'exécute avant require_root, mais le cas se lit avec les autres — non joué hors root"
    saute "configure-swap.sh : « tr » en échec dans en_megaoctets" \
        "idem"
else
    mkdir -p "$REP_STUB_SED" "$REP_STUB_TR2"
    # Le stub sed ne refuse que l'expression du site : « s/[^0-9]//g ».
    # afficher_etat, qui s'exécute avant, emploie « s/^/  /» et doit passer.
    {
        printf '#!/bin/sh\n'
        printf 'case "$*" in *"[^0-9]"*) exit 1 ;; esac\n'
        printf 'exec %s "$@"\n' "$(command -v sed)"
    } > "$REP_STUB_SED/sed"
    # Le stub tr ne refuse que la mise en majuscules du site. est_fichier_swap
    # emploie « tr -d '\000' » et doit passer.
    {
        printf '#!/bin/sh\n'
        printf 'case "$*" in *"[:lower:]"*) exit 1 ;; esac\n'
        printf 'exec %s "$@"\n' "$(command -v tr)"
    } > "$REP_STUB_TR2/tr"
    chmod +x "$REP_STUB_SED/sed" "$REP_STUB_TR2/tr"

    if printf 'a1' | "$REP_STUB_SED/sed" 's/[^0-9]//g' >/dev/null 2>&1; then
        ko "garde : le faux « sed » refuse l'expression du site" "le stub a rendu 0"
    else
        ok "garde : le faux « sed » refuse l'expression du site"
    fi
    if [ "$(printf 'x' | "$REP_STUB_SED/sed" 's/^/  /' 2>/dev/null)" = "  x" ]; then
        ok "garde : le faux « sed » délègue les autres expressions"
    else
        ko "garde : le faux « sed » délègue les autres expressions" \
            "afficher_etat mourrait avant en_megaoctets et le cas ne prouverait rien"
    fi
    if printf 'a' | "$REP_STUB_TR2/tr" '[:lower:]' '[:upper:]' >/dev/null 2>&1; then
        ko "garde : le faux « tr » refuse la mise en majuscules du site" "le stub a rendu 0"
    else
        ok "garde : le faux « tr » refuse la mise en majuscules du site"
    fi

    # f. sed, sur la lecture du nombre.
    lancer env "PATH=$REP_STUB_SED:$PATH" bash "$SWAP_SH" 512M --dry-run
    assert_code 1 "$CODE" \
        "configure-swap.sh, « sed » en échec : échec d'exécution, code 1 — et non 2"
    assert_contient "$(erreur)" "[ERROR] Lecture du nombre impossible dans « 512M » : « sed » a échoué." \
        "configure-swap.sh, « sed » en échec : le diagnostic nomme sed et la valeur reçue"
    assert_absent "$(erreur)" "Taille invalide" \
        "configure-swap.sh, « sed » en échec : la taille de l'appelant n'est PAS déclarée invalide"
    assert_absent "$(erreur)" "Échec (code" \
        "configure-swap.sh, « sed » en échec : le trap ERR n'ajoute aucune ligne"
    assert_absent "$(erreur)" "configure-swap.sh: line" \
        "configure-swap.sh, « sed » en échec : aucun message brut de bash sur stderr"
    assert_egal "2" "$(nb_lignes_contenant '[ERROR]')" \
        "configure-swap.sh, « sed » en échec : deux lignes [ERROR] mesurées"

    # g. tr, sur la lecture de l'unité. Le second site de la même fonction : il
    #    n'est atteint que si le premier a réussi, d'où deux stubs distincts.
    lancer env "PATH=$REP_STUB_TR2:$PATH" bash "$SWAP_SH" 512M --dry-run
    assert_code 1 "$CODE" \
        "configure-swap.sh, « tr » en échec : échec d'exécution, code 1 — et non 2"
    assert_contient "$(erreur)" "[ERROR] Lecture de l'unité impossible dans « 512M » : « sed » ou « tr » a échoué." \
        "configure-swap.sh, « tr » en échec : le diagnostic nomme les deux outils possibles"
    assert_absent "$(erreur)" "Taille invalide" \
        "configure-swap.sh, « tr » en échec : la taille de l'appelant n'est PAS déclarée invalide"
    assert_absent "$(erreur)" "Unité inconnue" \
        "configure-swap.sh, « tr » en échec : l'unité n'est pas davantage déclarée inconnue"
    assert_absent "$(erreur)" "Échec (code" \
        "configure-swap.sh, « tr » en échec : le trap ERR n'ajoute aucune ligne"
    assert_egal "2" "$(nb_lignes_contenant '[ERROR]')" \
        "configure-swap.sh, « tr » en échec : deux lignes [ERROR] mesurées"

    # Non-régression : les deux refus MÉTIER gardent leur code 2 et leur message.
    # C'est l'autre moitié de la distinction, et sans elle les deux cas ci-dessus
    # passeraient encore si en_megaoctets renvoyait 1 pour tout.
    lancer bash "$SWAP_SH" abc --dry-run
    assert_code 2 "$CODE" "non-régression : une taille réellement invalide vaut toujours 2"
    assert_contient "$(erreur)" "[ERROR] Taille invalide : « abc » (exemples : 2G, 512M, 2048)." \
        "non-régression : le diagnostic métier est intact"

    rm -rf "$REP_STUB_SED" "$REP_STUB_TR2"
fi

# --- h. « basename » dans configure-logging.sh ------------------------------
# Le site consigné aux points en suspens §6, laissé nu pendant quatre tours.
# Le stub ne refuse que l'appel portant le répertoire des journaux : celui de
# lib/common.sh, « basename "${0%.sh}" », est une AFFECTATION du socle et son
# échec produirait un doublement dans un fichier qui n'est pas celui qu'on
# éprouve.
#
# Ce cas meurt avant tout — avant même require_root, le site étant en tête de
# fichier. Il ne dépend donc d'aucun privilège, et rien n'est écrit.
mkdir -p "$REP_STUB_BASENAME"
# Guillemets simples VOULUS : « $1 » et « $@ » sont développés par le stub à son
# exécution, pas ici — c'est ce que SC2016 signale.
# shellcheck disable=SC2016
{
    printf '#!/bin/sh\n'
    printf 'case "$1" in %s) exit 1 ;; esac\n' "$LOG_DIR"
    printf 'exec %s "$@"\n' "$(command -v basename)"
} > "$REP_STUB_BASENAME/basename"
chmod +x "$REP_STUB_BASENAME/basename"

if "$REP_STUB_BASENAME/basename" "$LOG_DIR" >/dev/null 2>&1; then
    ko "garde : le faux « basename » refuse l'appel sur LOG_DIR" "le stub a rendu 0"
else
    ok "garde : le faux « basename » refuse l'appel sur LOG_DIR"
fi
if [ "$("$REP_STUB_BASENAME/basename" /a/b 2>/dev/null)" = "b" ]; then
    ok "garde : le faux « basename » délègue les autres appels — lib/common.sh reste intact"
else
    ko "garde : le faux « basename » délègue les autres appels" \
        "le socle échouerait à son chargement et le cas ne porterait pas sur configure-logging.sh"
fi

lancer env "PATH=$REP_STUB_BASENAME:$PATH" bash "$LOGGING_SH" --dry-run

assert_code 1 "$CODE" \
    "configure-logging.sh, « basename » en échec : échec d'exécution, code 1"
assert_contient "$(erreur)" "[ERROR] Nom de la règle logrotate indéterminable : « basename » a échoué sur" \
    "configure-logging.sh, « basename » en échec : le diagnostic nomme basename"
assert_contient "$(erreur)" "« $LOG_DIR » (valeur par défaut)." \
    "configure-logging.sh, « basename » en échec : le répertoire ET son origine sont cités"
assert_contient "$(erreur)" "[ERROR] Vérifier cette valeur — LOG_DIR — et « basename » dans le PATH." \
    "configure-logging.sh, « basename » en échec : la variable en cause est nommée"
assert_absent "$(erreur)" "Échec (code" \
    "configure-logging.sh, « basename » en échec : le trap ERR n'ajoute aucune ligne"
assert_absent "$(erreur)" "configure-logging.sh: line" \
    "configure-logging.sh, « basename » en échec : aucun message brut de bash sur stderr"
assert_absent "$(erreur)" "common.sh: line" \
    "configure-logging.sh, « basename » en échec : le socle n'a pas été touché par le stub"
assert_egal "3" "$(nb_lignes_contenant '[ERROR]')" \
    "configure-logging.sh, « basename » en échec : trois lignes [ERROR] mesurées"
assert_egal "3" "$(nb_lignes_erreur)" \
    "configure-logging.sh, « basename » en échec : stderr ne porte QUE ces trois lignes — le refus précède tout"

rm -rf "$REP_STUB_BASENAME"


# ===================================================================
# 4. Idempotence — critère 4
# ===================================================================
titre "4. Idempotence — deux exécutions de suite"

# idempotent <libellé> <motif-attendu-au-second-passage> -- <commande...>
#
# Le protocole complet, garde anti-preuve-à-vide comprise.
idempotent() {
    local libelle="$1" motif="$2"; shift 2
    if [ "${1:-}" = "--" ]; then
        shift
    fi

    empreinte "$REP_TMP/idem-p0"

    lancer "$@"
    assert_code 0 "$CODE" "$libelle : première exécution sort en 0"
    empreinte "$REP_TMP/idem-a"
    assert_empreinte_differente "$REP_TMP/idem-p0" "$REP_TMP/idem-a" \
        "$libelle : la première exécution modifie réellement le système"

    lancer "$@"
    assert_code 0 "$CODE" "$libelle : seconde exécution sort en 0"
    assert_contient "$(erreur)" "$motif" "$libelle : la seconde exécution annonce n'avoir rien à faire"
    empreinte "$REP_TMP/idem-b"
    assert_empreinte_egale "$REP_TMP/idem-a" "$REP_TMP/idem-b" \
        "$libelle : la seconde exécution laisse le système identique"
}

GROUPE_IDEMPOTENCE="oui"
if [ "$EST_ROOT" != "true" ]; then
    GROUPE_IDEMPOTENCE="require_root arrête ces scripts avant toute modification"
elif [ "$JETABLE" != "true" ]; then
    GROUPE_IDEMPOTENCE="cet hôte n'est pas un système jetable — /etc/hosts et /etc/localtime ne seront pas réécrits"
elif [ "$EST_DEBIAN" != "true" ]; then
    GROUPE_IDEMPOTENCE="l'hôte n'est ni Debian ni Ubuntu"
fi

# Ce contrôle compare l'état courant à « info-avant », relevée à l'ouverture du
# groupe « system-info » — et non à l'état du tout début du fichier. Ce qu'il
# prouve exactement : ni « system-info » ni « dry-run » n'ont modifié le système.
# Une dérive causée par le groupe « préflight », qui les précède, lui
# échapperait.
#
# Le trou est résiduel et couvert autrement : la seule écriture du préflight est
# le remplacement temporaire de /etc/os-release pour éprouver require_os, et sa
# restauration porte sa propre assertion (« /etc/os-release a été remis dans son
# état d'origine »). Aucun autre cas du préflight n'écrit quoi que ce soit.
if [ "$GROUPE_IDEMPOTENCE" = "oui" ]; then
    empreinte "$REP_TMP/etat-avant-idempotence"
    if diff -u "$REP_TMP/info-avant" "$REP_TMP/etat-avant-idempotence" > "$REP_TMP/derive" 2>&1; then
        ok "l'état de départ du groupe « idempotence » est intact — les groupes précédents n'ont rien modifié"
    else
        GROUPE_IDEMPOTENCE="le système a dérivé pendant les groupes précédents — $(head -n 8 "$REP_TMP/derive" | tr '\n' '|')"
    fi
fi

if [ "$GROUPE_IDEMPOTENCE" != "oui" ]; then
    saute "configure-timezone.sh exécuté deux fois de suite" "$GROUPE_IDEMPOTENCE"
    saute "configure-hostname.sh exécuté deux fois de suite" "$GROUPE_IDEMPOTENCE"
    saute "configure-logging.sh exécuté deux fois de suite" "$GROUPE_IDEMPOTENCE"
    saute "configure-swap.sh exécuté deux fois de suite" "$GROUPE_IDEMPOTENCE"
    saute "update-system.sh exécuté deux fois de suite" "$GROUPE_IDEMPOTENCE"
else
    # --- configure-timezone.sh : /etc/localtime et /etc/timezone ------------
    if [ ! -f "/usr/share/zoneinfo/$FUSEAU_CIBLE" ]; then
        saute "configure-timezone.sh exécuté deux fois de suite" \
            "/usr/share/zoneinfo/$FUSEAU_CIBLE absent de cet hôte"
    else
        idempotent "configure-timezone.sh $FUSEAU_CIBLE" "Rien à faire" \
            -- bash "$TIMEZONE_SH" "$FUSEAU_CIBLE" -y
        lien="$(readlink -f /etc/localtime)"
        assert_egal "/usr/share/zoneinfo/$FUSEAU_CIBLE" "$lien" \
            "/etc/localtime pointe bien sur $FUSEAU_CIBLE après les deux passages"
    fi

    # --- configure-logging.sh : /etc/logrotate.d/<règle> --------------------
    if [ "$LOGROTATE_DISPONIBLE" != "true" ]; then
        saute "configure-logging.sh exécuté deux fois de suite" \
            "logrotate absent de l'image et non installable"
    else
        idempotent "configure-logging.sh" "déjà en place et à jour" \
            -- bash "$LOGGING_SH"
    fi

    # --- configure-hostname.sh : /etc/hosts ---------------------------------
    # Le nom demandé est celui de la machine : le changement porte alors sur le
    # seul /etc/hosts. Renommer réellement exige CAP_SYS_ADMIN — déclaré NON
    # EXÉCUTÉ plus bas.
    nom_courant="$(hostname)"
    idempotent "configure-hostname.sh $nom_courant" "Rien à faire" \
        -- bash "$HOSTNAME_SH" "$nom_courant" -y

    lignes="$(grep -cE '^[[:space:]]*127\.0\.1\.1[[:space:]]' /etc/hosts)" || lignes="0"
    assert_egal "1" "$lignes" "/etc/hosts porte exactement une ligne 127.0.1.1 après deux passages"

    sauvegardes="$(find /etc -maxdepth 1 -name 'hosts.bak-*' | wc -l | tr -d ' ')"
    assert_egal "1" "$sauvegardes" \
        "une seule sauvegarde de /etc/hosts a été créée — le second passage n'en refait pas"

    # Chemin de hosts_deja_conforme() qu'aucun autre cas n'emprunte : le nom
    # demandé n'est pas le nom principal de la ligne, mais l'un de ses alias.
    # Le script doit conclure « rien à faire » et surtout ne pas réécrire la
    # ligne sur son modèle, ce qui ferait perdre les alias en place.
    printf '127.0.0.1\tlocalhost\n127.0.1.1\tautre-nom\t%s\n' "$nom_courant" > /etc/hosts
    empreinte "$REP_TMP/alias-avant"
    lancer bash "$HOSTNAME_SH" "$nom_courant" -y
    assert_code 0 "$CODE" "configure-hostname.sh sort en 0 quand le nom n'est qu'un alias de la ligne"
    assert_contient "$(erreur)" "Rien à faire" \
        "configure-hostname.sh reconnaît le nom en position d'alias"
    empreinte "$REP_TMP/alias-apres"
    assert_empreinte_egale "$REP_TMP/alias-avant" "$REP_TMP/alias-apres" \
        "configure-hostname.sh ne réécrit pas une ligne dont le nom est déjà un alias"

    # --- configure-swap.sh : --dry-run seulement ----------------------------
    # L'activation exige CAP_SYS_ADMIN, refusé au conteneur : seul le chemin
    # sans écriture est éprouvé ici, deux fois de suite.
    #
    # Les quatre assertions ajoutées par TASK-018 bornent le CHEMIN NOMINAL, et
    # c'est ce que les six affectations mises en contexte de condition pouvaient
    # casser le plus discrètement. Une condition mal formée n'aurait pas produit
    # de message : elle aurait rendu une valeur vide ou fausse, et le script
    # aurait continué. Le décompte à ZÉRO ligne [ERROR] voit un diagnostic
    # apparaître là où il n'y en avait pas ; le résumé « créer /swapfile
    # (512 Mo) » voit la valeur elle-même — il n'est produit que si
    # repertoire_swap, type_fs, TAILLE_ACTUELLE_MO et espace_libre_mo ont tous
    # les quatre été renseignés correctement.
    empreinte "$REP_TMP/swap-a"
    lancer bash "$SWAP_SH" 512M --dry-run
    assert_code 0 "$CODE" "configure-swap.sh --dry-run première exécution sort en 0"
    assert_egal "0" "$(nb_lignes_contenant '[ERROR]')" \
        "configure-swap.sh --dry-run première exécution : aucune ligne [ERROR] sur stderr"
    assert_contient "$(erreur)" "créer      /swapfile (512 Mo)" \
        "configure-swap.sh --dry-run première exécution : les substitutions rendent bien leurs valeurs"
    lancer bash "$SWAP_SH" 512M --dry-run
    assert_code 0 "$CODE" "configure-swap.sh --dry-run seconde exécution sort en 0"
    assert_egal "0" "$(nb_lignes_contenant '[ERROR]')" \
        "configure-swap.sh --dry-run seconde exécution : aucune ligne [ERROR] sur stderr"
    assert_contient "$(erreur)" "[INFO] Mode --dry-run : aucune modification effectuée." \
        "configure-swap.sh --dry-run seconde exécution : le chemin nominal va jusqu'au bout"
    empreinte "$REP_TMP/swap-b"
    assert_empreinte_egale "$REP_TMP/swap-a" "$REP_TMP/swap-b" \
        "configure-swap.sh --dry-run exécuté deux fois laisse le système identique"

    # --- update-system.sh : --dry-run seulement -----------------------------
    # « apt-get upgrade » réel est hors du périmètre de TASK-004 : l'image n'a
    # aucun paquet obsolète et une mise à jour dans un conteneur de test
    # n'apporterait aucune information. Le chemin sans écriture, lui, se
    # vérifie : l'index de paquets est rafraîchi, /etc ne bouge pas.
    paquets_avant="$(dpkg-query -W -f='${Package} ${Version}\n' | sort | cksum)"
    empreinte "$REP_TMP/update-a"
    lancer bash "$UPDATE_SH" --dry-run
    assert_code 0 "$CODE" "update-system.sh --dry-run première exécution sort en 0"
    lancer bash "$UPDATE_SH" --dry-run
    assert_code 0 "$CODE" "update-system.sh --dry-run seconde exécution sort en 0"
    empreinte "$REP_TMP/update-b"
    assert_empreinte_egale "$REP_TMP/update-a" "$REP_TMP/update-b" \
        "update-system.sh --dry-run exécuté deux fois laisse /etc identique"
    paquets_apres="$(dpkg-query -W -f='${Package} ${Version}\n' | sort | cksum)"
    assert_egal "$paquets_avant" "$paquets_apres" \
        "update-system.sh --dry-run n'installe aucun paquet"
fi

# ===================================================================
# 4 bis. « mktemp » en échec — configure-hostname.sh, TASK-018
# ===================================================================
# Le septième site corrigé, et le seul hors de configure-swap.sh. Sous la forme
# nue « temporaire="$(mktemp)" », un mktemp en échec — /tmp plein, monté en
# lecture seule, TMPDIR pointant sur un chemin absent — s'annonçait deux fois :
# dans le sous-shell de la substitution, puis dans le shell principal pour
# l'affectation. Deux lignes de trap identiques, et pas un mot sur ce qui
# manquait.
#
# Sa cause d'échec S'ATTEINT depuis l'environnement de l'appel : TMPDIR est lu
# par mktemp. C'est le troisième et dernier des sept sites qui se prouve par
# l'exécution.
#
# CE GROUPE ÉCRIT : il réécrit /etc/hosts pour que le script ait quelque chose à
# faire, et le script crée sa sauvegarde avant d'atteindre mktemp. Il est donc
# placé APRÈS le groupe 4 — la garde d'état de l'idempotence compare l'empreinte
# à celle du groupe 2 et déclarerait tout le groupe NON EXÉCUTÉ si celui-ci le
# précédait. L'état antérieur est restitué à la fin.
#
# Le nom demandé est le nom COURANT de la machine : le changement porte alors
# sur le seul /etc/hosts. Renommer réellement exige CAP_SYS_ADMIN, refusé au
# conteneur — le script mourrait avant d'atteindre mktemp et le cas ne prouverait
# rien.
titre "4 bis. « mktemp » en échec — configure-hostname.sh"

TMPDIR_ABSENT="/pas/de/tmpdir"

if [ "$EST_ROOT" != "true" ]; then
    saute "configure-hostname.sh, « mktemp » en échec : un seul diagnostic, /etc/hosts intact" \
        "require_root arrête le script avant toute écriture"
elif [ "$JETABLE" != "true" ]; then
    saute "configure-hostname.sh, « mktemp » en échec : un seul diagnostic, /etc/hosts intact" \
        "ce groupe réécrit /etc/hosts — réservé à un système jetable"
elif [ -e "$TMPDIR_ABSENT" ]; then
    saute "configure-hostname.sh, « mktemp » en échec : un seul diagnostic, /etc/hosts intact" \
        "$TMPDIR_ABSENT existe sur cet hôte — mktemp y réussirait"
else
    NOM_COURANT_4BIS="$(hostname)"
    cp -p /etc/hosts "$REP_TMP/hosts.avant-4bis"

    # Aucune ligne 127.0.1.1, et le nom de la machine nulle part : le script a
    # donc un changement à appliquer et atteint le bloc /etc/hosts. Sans cela il
    # sortirait sur « Rien à faire » et mktemp ne serait jamais appelé.
    printf '127.0.0.1\tlocalhost\n' > /etc/hosts

    HOSTS_AVANT="$(empreinte_fichier /etc/hosts)"
    SAUVEGARDES_AVANT="$(find /etc -maxdepth 1 -name 'hosts.bak-*' | wc -l | tr -d ' ')"

    lancer env "TMPDIR=$TMPDIR_ABSENT" bash "$HOSTNAME_SH" "$NOM_COURANT_4BIS" -y

    assert_code 1 "$CODE" \
        "configure-hostname.sh, « mktemp » en échec : échec d'exécution, code 1"
    assert_contient "$(erreur)" "[ERROR] Fichier temporaire impossible à créer dans $TMPDIR_ABSENT." \
        "configure-hostname.sh, « mktemp » en échec : le diagnostic nomme le répertoire en cause"
    assert_contient "$(erreur)" "[ERROR] /etc/hosts n'a pas été modifié" \
        "configure-hostname.sh, « mktemp » en échec : le diagnostic dit ce qui n'a PAS été fait"
    assert_absent "$(erreur)" "Échec (code" \
        "configure-hostname.sh, « mktemp » en échec : le trap ERR n'ajoute aucune ligne"
    assert_absent "$(erreur)" "mktemp:" \
        "configure-hostname.sh, « mktemp » en échec : le message brut de mktemp est remplacé par le diagnostic"
    # Le décompte, MESURÉ dans le conteneur : deux « error » puis le « die ». Il
    # voit revenir la ligne du trap même si son libellé change un jour dans
    # lib/common.sh, là où l'assertion d'absence ci-dessus est liée à son texte.
    assert_egal "3" "$(nb_lignes_contenant '[ERROR]')" \
        "configure-hostname.sh, « mktemp » en échec : stderr porte les trois lignes du refus, pas une de plus"

    # /etc/hosts INTACT — contenu, taille, inode et date. Le script échoue entre
    # la sauvegarde et la réécriture : si le « cat > /etc/hosts » était atteint
    # avec un « $temporaire » vide, le fichier serait vidé sans que le décompte
    # de lignes s'en aperçoive.
    HOSTS_APRES="$(empreinte_fichier /etc/hosts)"
    assert_egal "$HOSTS_AVANT" "$HOSTS_APRES" \
        "configure-hostname.sh, « mktemp » en échec : /etc/hosts est resté strictement intact"

    # La sauvegarde annoncée existe vraiment, et porte bien l'état d'origine :
    # le diagnostic promet à l'appelant qu'elle « reste en place ».
    SAUVEGARDES_APRES="$(find /etc -maxdepth 1 -name 'hosts.bak-*' | wc -l | tr -d ' ')"
    assert_egal "$(( SAUVEGARDES_AVANT + 1 ))" "$SAUVEGARDES_APRES" \
        "configure-hostname.sh, « mktemp » en échec : la sauvegarde a bien été créée avant l'échec"

    CHEMIN_SAUVEGARDE="$(sed -n 's/^.*\[INFO\] Sauvegarde : \(.*\)$/\1/p' "$F_ERR" | tail -n 1)"
    if [ -z "$CHEMIN_SAUVEGARDE" ]; then
        ko "configure-hostname.sh, « mktemp » en échec : la sauvegarde nommée dans le diagnostic existe" \
            "aucun chemin de sauvegarde n'a pu être extrait de stderr"
    elif [ ! -f "$CHEMIN_SAUVEGARDE" ]; then
        ko "configure-hostname.sh, « mktemp » en échec : la sauvegarde nommée dans le diagnostic existe" \
            "$CHEMIN_SAUVEGARDE est annoncé mais absent du disque"
    elif ! cmp -s "$CHEMIN_SAUVEGARDE" /etc/hosts; then
        ko "configure-hostname.sh, « mktemp » en échec : la sauvegarde nommée dans le diagnostic existe" \
            "$CHEMIN_SAUVEGARDE diffère de /etc/hosts"
    else
        ok "configure-hostname.sh, « mktemp » en échec : la sauvegarde nommée dans le diagnostic existe et porte l'état d'origine"
    fi

    # Restitution : /etc/hosts tel qu'il était, et la sauvegarde produite par ce
    # groupe retirée. Aucun cas ultérieur ne relève /etc, mais un résidu resterait
    # un résidu.
    cat "$REP_TMP/hosts.avant-4bis" > /etc/hosts
    if [ -n "$CHEMIN_SAUVEGARDE" ]; then
        rm -f "$CHEMIN_SAUVEGARDE"
    fi
fi

# ===================================================================
# 4 ter. La lecture du fuseau courant — configure-timezone.sh, TASK-018
# ===================================================================
# Trois corrections de TASK-018 vivent ici, et elles n'ont pas la même portée :
#
#   1. les deux lectures « ancien_fichier="$(tr -d … < /etc/timezone)" » et son
#      jumeau de la vérification, passées en contexte de condition ;
#   2. « fuseau_actuel », qui renseigne désormais la globale FUSEAU_ACTUEL et
#      n'est plus appelée en substitution. C'est la correction que ce groupe a
#      FAIT NAÎTRE : deux de ses assertions sont restées rouges un tour entier
#      avant qu'elle n'existe.
#
# Ce qu'il y avait à corriger en 2, MESURÉ à l'époque sous un faux « tr » :
#
#   [ERROR] Échec (code 1) à la ligne 150 de configure-timezone.sh.
#   [INFO] Fuseau actuel  :   (2026-09-02 12:00:00 UTC)
#
# Une ligne de trap qui ne nomme rien, et surtout : le « return 0 » placé après
# le « tr » effaçait le code de celui-ci, la substitution rendait 0, et
# FUSEAU_ACTUEL valait la CHAÎNE VIDE. Le script comparait le fuseau demandé à
# rien, puis l'appliquait sur cette base. C'est le motif de TASK-018 dans sa
# forme la plus coûteuse : pas un message en trop, une décision prise sur rien.
#
# Chaque source est maintenant lue en condition, l'échec de l'une fait passer à
# la suivante en le DISANT, et la fonction rend 1 quand aucune n'a répondu. Deux
# appels, deux traitements de cet échec — non fatal avant l'application, fatal à
# la vérification — et ce groupe éprouve le premier.
#
# DEUX choses sont donc mesurées, et il faut les distinguer :
#
#   a. la NON-RÉGRESSION du chemin nominal, DEUX FOIS DE SUITE. C'est là que la
#      réécriture de fuseau_actuel peut régresser sans bruit : une source mal
#      lue ne produit aucun message, elle produit une comparaison fausse. Le
#      seul garde-fou est d'exiger la VALEUR affichée, et pas seulement
#      l'absence d'erreur ;
#   b. le CHEMIN D'ÉCHEC de la première lecture, atteint par un faux « tr ».
#
# CE GROUPE ÉCRIT /etc/localtime et /etc/timezone. Il est placé APRÈS le groupe
# 4 — dont la garde d'état compare l'empreinte à celle du groupe 2 — et rend
# l'état où il l'a trouvé, ce qu'il vérifie plutôt que de le supposer.
titre "4 ter. La lecture du fuseau courant — configure-timezone.sh"

FUSEAU_INTERMEDIAIRE="Etc/UTC"
REP_STUB_TR="$REP_TMP/stub-tr"
REP_STUB_RL="$REP_TMP/stub-readlink"

RAISON_4TER="oui"
if [ "$EST_ROOT" != "true" ]; then
    RAISON_4TER="require_root arrête le script avant toute écriture"
elif [ "$JETABLE" != "true" ]; then
    RAISON_4TER="ce groupe réécrit /etc/localtime et /etc/timezone — réservé à un système jetable"
elif [ ! -f "/usr/share/zoneinfo/$FUSEAU_INTERMEDIAIRE" ] || [ ! -f "/usr/share/zoneinfo/$FUSEAU_CIBLE" ]; then
    RAISON_4TER="/usr/share/zoneinfo ne fournit pas les deux fuseaux nécessaires sur cet hôte"
elif [ ! -f /etc/timezone ]; then
    RAISON_4TER="/etc/timezone est absent de cet hôte — les deux lectures ne sont jamais atteintes"
fi

if [ "$RAISON_4TER" != "oui" ]; then
    saute "configure-timezone.sh : le chemin nominal, deux fois de suite" "$RAISON_4TER"
    saute "configure-timezone.sh : /etc/timezone lisible mais VIDE part au repli" "$RAISON_4TER"
    saute "configure-timezone.sh : la lecture du fuseau courant en échec" "$RAISON_4TER"
    saute "configure-timezone.sh : aucune source lisible, les deux traitements de l'échec" "$RAISON_4TER"
else
    TZ_ORIGINE="$(cat /etc/timezone)"

    # --- a. Le chemin nominal, deux fois de suite --------------------------
    # Le groupe 4 a laissé le système sur FUSEAU_CIBLE : demander un AUTRE
    # fuseau est le seul moyen de rouvrir le chemin d'application. Sans cela le
    # script sortirait sur « Rien à faire » et ni fuseau_actuel ni les deux
    # lectures ne seraient éprouvées — le cas passerait sans rien prouver.
    lancer bash "$TIMEZONE_SH" "$FUSEAU_INTERMEDIAIRE" -y
    assert_code 0 "$CODE" \
        "configure-timezone.sh $FUSEAU_INTERMEDIAIRE : sort en 0"
    assert_egal "0" "$(nb_lignes_contenant '[ERROR]')" \
        "configure-timezone.sh $FUSEAU_INTERMEDIAIRE : aucune ligne [ERROR]"
    # La VALEUR, et pas seulement l'absence d'erreur. fuseau_actuel rend ici la
    # valeur d'AVANT le changement : c'est la seule assertion qui verrait une
    # source mal lue — « inconnu » ou une chaîne vide passeraient toutes les
    # autres.
    assert_contient "$(erreur)" "[INFO] Fuseau actuel  : $FUSEAU_CIBLE  (" \
        "configure-timezone.sh $FUSEAU_INTERMEDIAIRE : fuseau_actuel rend la valeur courante, et non « inconnu »"
    assert_contient "$(erreur)" "[INFO] Fuseau défini via /etc/localtime." \
        "configure-timezone.sh $FUSEAU_INTERMEDIAIRE : le repli /etc/localtime est bien emprunté, faute de systemd"
    assert_contient "$(erreur)" "/etc/timezone mis en cohérence (était « $FUSEAU_CIBLE »)" \
        "configure-timezone.sh $FUSEAU_INTERMEDIAIRE : la lecture de /etc/timezone rend l'ANCIENNE valeur, et pas une chaîne vide"
    # Le WARN attendu est celui des tâches planifiées, et LUI SEUL : le nouvel
    # avertissement de repli n'a rien à faire sur un chemin nominal. Deux
    # assertions plutôt qu'une, parce que le décompte seul ne dirait pas LEQUEL.
    assert_egal "1" "$(nb_lignes_contenant '[WARN]')" \
        "configure-timezone.sh $FUSEAU_INTERMEDIAIRE : un seul avertissement sur stderr"
    assert_absent "$(erreur)" "/etc/timezone est illisible ou vide" \
        "configure-timezone.sh $FUSEAU_INTERMEDIAIRE : le repli de lecture n'est PAS emprunté quand /etc/timezone répond"
    assert_egal "9" "$(nb_lignes_erreur)" \
        "configure-timezone.sh $FUSEAU_INTERMEDIAIRE : stderr porte neuf lignes, mesurées — aucune ne s'ajoute en silence"
    assert_egal "$FUSEAU_INTERMEDIAIRE" "$(cat /etc/timezone)" \
        "configure-timezone.sh $FUSEAU_INTERMEDIAIRE : /etc/timezone porte le nouveau fuseau"
    assert_egal "/usr/share/zoneinfo/$FUSEAU_INTERMEDIAIRE" "$(readlink -f /etc/localtime)" \
        "configure-timezone.sh $FUSEAU_INTERMEDIAIRE : /etc/localtime pointe sur le nouveau fuseau"

    # Le second passage. C'est ici que fuseau_actuel est le SEUL juge : le script
    # ne fait plus rien, et ce qu'il annonce vient entièrement d'elle.
    lancer bash "$TIMEZONE_SH" "$FUSEAU_INTERMEDIAIRE" -y
    assert_code 0 "$CODE" \
        "configure-timezone.sh $FUSEAU_INTERMEDIAIRE, second passage : sort en 0"
    assert_contient "$(erreur)" "Rien à faire : le fuseau est déjà « $FUSEAU_INTERMEDIAIRE »." \
        "configure-timezone.sh $FUSEAU_INTERMEDIAIRE, second passage : rien à faire"
    assert_contient "$(erreur)" "[INFO] Fuseau actuel  : $FUSEAU_INTERMEDIAIRE  (" \
        "configure-timezone.sh $FUSEAU_INTERMEDIAIRE, second passage : fuseau_actuel relit bien la valeur qui vient d'être posée"
    assert_egal "0" "$(nb_lignes_contenant '[ERROR]')" \
        "configure-timezone.sh $FUSEAU_INTERMEDIAIRE, second passage : aucune ligne [ERROR]"
    assert_egal "0" "$(nb_lignes_contenant '[WARN]')" \
        "configure-timezone.sh $FUSEAU_INTERMEDIAIRE, second passage : aucun avertissement"
    assert_egal "3" "$(nb_lignes_erreur)" \
        "configure-timezone.sh $FUSEAU_INTERMEDIAIRE, second passage : stderr porte trois lignes, mesurées"

    # --- b. /etc/timezone lisible mais VIDE ---------------------------------
    # Le seul cas qui emprunte le repli de lecture sans faux « tr ». Avant
    # TASK-018, la lecture rendait la chaîne vide et le script la prenait pour le
    # fuseau courant ; elle passe désormais à /etc/localtime, en le disant. Le
    # « && [ -n "$valeur" ] » de fuseau_actuel n'a aucune autre preuve.
    printf '' > /etc/timezone
    lancer bash "$TIMEZONE_SH" "$FUSEAU_CIBLE" -y
    assert_code 0 "$CODE" \
        "configure-timezone.sh, /etc/timezone vide : sort en 0"
    assert_contient "$(erreur)" "[WARN] /etc/timezone est illisible ou vide : lecture du fuseau par /etc/localtime." \
        "configure-timezone.sh, /etc/timezone vide : le repli est annoncé, pas silencieux"
    assert_contient "$(erreur)" "[INFO] Fuseau actuel  : $FUSEAU_INTERMEDIAIRE  (" \
        "configure-timezone.sh, /etc/timezone vide : la valeur vient de /etc/localtime, et n'est ni vide ni « inconnu »"
    assert_absent "$(erreur)" "Fuseau actuel  : inconnu" \
        "configure-timezone.sh, /etc/timezone vide : une source a répondu — « inconnu » serait un aveu d'échec"
    assert_egal "0" "$(nb_lignes_contenant '[ERROR]')" \
        "configure-timezone.sh, /etc/timezone vide : aucune ligne [ERROR] — un fichier vide n'est pas une erreur fatale"
    assert_egal "2" "$(nb_lignes_contenant '[WARN]')" \
        "configure-timezone.sh, /etc/timezone vide : deux avertissements mesurés — le repli, et les tâches planifiées"
    assert_egal "$FUSEAU_CIBLE" "$(cat /etc/timezone)" \
        "configure-timezone.sh, /etc/timezone vide : le fichier est remis en cohérence"

    # --- c. La lecture du fuseau courant en échec, par un faux « tr » -------
    # Le faux « tr » atteint DEUX sites à la fois : fuseau_actuel, qui bascule
    # sur /etc/localtime en avertissant, puis la lecture corrigée de la mise en
    # cohérence, qui n'a pas de repli et diagnostique.
    #
    # Les deux assertions marquées ci-dessous — absence de ligne de trap, valeur
    # non vide — sont restées ROUGES un tour entier, jamais neutralisées. C'est
    # ce qui a fait réécrire fuseau_actuel. Elles sont le seul endroit du dépôt
    # qui l'ait signalé, et leur passage au vert est la preuve de la correction.
    #
    # Le système est remis sur FUSEAU_INTERMEDIAIRE d'abord : le cas doit avoir
    # un changement à appliquer, sinon le script sort sur « Rien à faire » avant
    # d'atteindre quoi que ce soit.
    lancer bash "$TIMEZONE_SH" "$FUSEAU_INTERMEDIAIRE" -y
    assert_code 0 "$CODE" "garde : le système est ramené sur $FUSEAU_INTERMEDIAIRE avant le cas au faux « tr »"

    mkdir -p "$REP_STUB_TR"
    printf '#!/bin/sh\nexit 1\n' > "$REP_STUB_TR/tr"
    chmod +x "$REP_STUB_TR/tr"
    if "$REP_STUB_TR/tr" -d '[:space:]' < /etc/timezone >/dev/null 2>&1; then
        ko "garde : le faux « tr » échoue bien" "le stub a rendu 0"
    else
        ok "garde : le faux « tr » échoue bien"
    fi

    lancer env "PATH=$REP_STUB_TR:$PATH" bash "$TIMEZONE_SH" "$FUSEAU_CIBLE" -y

    assert_code 1 "$CODE" \
        "configure-timezone.sh, « tr » en échec : échec d'exécution, code 1"
    assert_contient "$(erreur)" "[ERROR] /etc/timezone illisible : sa mise en cohérence est impossible." \
        "configure-timezone.sh, « tr » en échec : la lecture corrigée nomme la cause"
    assert_contient "$(erreur)" "[ERROR] Le fuseau vient d'être appliqué ; ce fichier seul reste en arrière." \
        "configure-timezone.sh, « tr » en échec : le diagnostic dit ce qui a déjà été fait"
    assert_egal "3" "$(nb_lignes_contenant '[ERROR]')" \
        "configure-timezone.sh, « tr » en échec : trois lignes [ERROR] mesurées, celles du diagnostic"
    assert_absent "$(erreur)" "configure-timezone.sh: line" \
        "configure-timezone.sh, « tr » en échec : aucun message brut de bash sur stderr"
    assert_absent "$(erreur)" "Échec (code" \
        "configure-timezone.sh, « tr » en échec : le trap ERR n'ajoute aucune ligne"
    # La valeur, mesurée et non seulement non vide : c'est /etc/localtime qui
    # répond, et il pointe sur FUSEAU_INTERMEDIAIRE.
    assert_contient "$(erreur)" "[INFO] Fuseau actuel  : $FUSEAU_INTERMEDIAIRE  (" \
        "configure-timezone.sh, « tr » en échec : fuseau_actuel bascule sur /etc/localtime et rend la BONNE valeur"
    assert_absent "$(erreur)" "Fuseau actuel  : inconnu" \
        "configure-timezone.sh, « tr » en échec : /etc/localtime a répondu — « inconnu » serait un repli manqué"
    assert_absent "$(erreur)" "Fuseau actuel  :   (" \
        "configure-timezone.sh, « tr » en échec : fuseau_actuel ne rend pas une valeur vide en silence"
    # Le nouvel avertissement de repli, et lui seul : le script meurt avant
    # celui des tâches planifiées. Le décompte le fige — c'est l'assertion qui
    # verrait un avertissement s'ajouter là où on ne l'attend pas.
    assert_contient "$(erreur)" "[WARN] /etc/timezone est illisible ou vide : lecture du fuseau par /etc/localtime." \
        "configure-timezone.sh, « tr » en échec : le repli de lecture est annoncé"
    assert_egal "1" "$(nb_lignes_contenant '[WARN]')" \
        "configure-timezone.sh, « tr » en échec : un seul avertissement mesuré"
    assert_egal "9" "$(nb_lignes_erreur)" \
        "configure-timezone.sh, « tr » en échec : stderr porte neuf lignes, mesurées — le warn de repli y est compté, rien d'autre ne s'ajoute"

    rm -rf "$REP_STUB_TR"

    # --- d. AUCUNE source lisible : les deux traitements de l'échec ---------
    # fuseau_actuel rend 1 quand aucune source n'a répondu, et ses deux appels
    # n'en font PAS la même chose. C'est l'asymétrie que TASK-018 a introduite, et
    # ce cas est le seul à la montrer, parce qu'il est le seul à faire échouer
    # TOUTES les sources à la fois :
    #
    #   avant l'application  échec NON fatal — rien n'a encore été modifié, et un
    #                        fuseau courant indéterminable n'empêche pas de poser
    #                        le fuseau demandé. FUSEAU_ACTUEL vaut « inconnu »,
    #                        JAMAIS la chaîne vide de l'ancienne forme ;
    #   à la vérification    échec FATAL — une vérification qui ne peut pas lire
    #                        l'état courant ne prouve rien. Elle le dit, en 1.
    #
    # Trois sources, trois neutralisations : timedatectl est absent du profil
    # debian, /etc/timezone est mis de côté le temps du cas — son absence ferme
    # aussi la mise en cohérence, qui sinon tuerait le script avant la
    # vérification — et readlink est remplacé par un stub en échec.
    mkdir -p "$REP_STUB_RL"
    printf '#!/bin/sh\nexit 1\n' > "$REP_STUB_RL/readlink"
    chmod +x "$REP_STUB_RL/readlink"
    if "$REP_STUB_RL/readlink" -f /etc/localtime >/dev/null 2>&1; then
        ko "garde : le faux « readlink » échoue bien" "le stub a rendu 0"
    else
        ok "garde : le faux « readlink » échoue bien"
    fi
    if command -v timedatectl >/dev/null 2>&1; then
        saute "configure-timezone.sh : aucune source lisible" \
            "timedatectl est présent sur cet hôte et répondrait — les trois sources ne peuvent pas échouer ensemble"
    else
        mv /etc/timezone "$REP_TMP/timezone.mis-de-cote"
        lancer env "PATH=$REP_STUB_RL:$PATH" bash "$TIMEZONE_SH" "$FUSEAU_CIBLE" -y
        mv "$REP_TMP/timezone.mis-de-cote" /etc/timezone

        assert_code 1 "$CODE" \
            "configure-timezone.sh, aucune source lisible : échec d'exécution, code 1"
        assert_contient "$(erreur)" "[WARN] /etc/localtime est illisible : le fuseau courant reste indéterminé." \
            "configure-timezone.sh, aucune source lisible : l'échec de la dernière source est dit"
        assert_contient "$(erreur)" "[WARN] Fuseau actuel indéterminable : aucune source lisible." \
            "configure-timezone.sh, aucune source lisible : le premier appel traite l'échec sans être fatal"
        assert_contient "$(erreur)" "[INFO] Fuseau actuel  : inconnu  (" \
            "configure-timezone.sh, aucune source lisible : FUSEAU_ACTUEL vaut « inconnu », jamais la chaîne vide"
        assert_absent "$(erreur)" "Fuseau actuel  :   (" \
            "configure-timezone.sh, aucune source lisible : la chaîne vide de l'ancienne forme ne revient pas"
        assert_contient "$(erreur)" "[INFO] Fuseau défini via /etc/localtime." \
            "configure-timezone.sh, aucune source lisible : le premier échec n'a PAS empêché l'application"
        assert_contient "$(erreur)" "[ERROR] Fuseau courant illisible : la vérification ne peut pas aboutir." \
            "configure-timezone.sh, aucune source lisible : le second appel, lui, est fatal"
        assert_absent "$(erreur)" "Échec (code" \
            "configure-timezone.sh, aucune source lisible : le trap ERR n'ajoute aucune ligne"
        assert_absent "$(erreur)" "configure-timezone.sh: line" \
            "configure-timezone.sh, aucune source lisible : aucun message brut de bash sur stderr"
        assert_egal "2" "$(nb_lignes_contenant '[ERROR]')" \
            "configure-timezone.sh, aucune source lisible : deux lignes [ERROR] mesurées"
        assert_egal "3" "$(nb_lignes_contenant '[WARN]')" \
            "configure-timezone.sh, aucune source lisible : trois avertissements mesurés — deux au premier appel, un au second"
        assert_egal "10" "$(nb_lignes_erreur)" \
            "configure-timezone.sh, aucune source lisible : stderr porte dix lignes, mesurées"

        if [ -f /etc/timezone ]; then
            ok "garde : /etc/timezone a été remis en place après le cas d"
        else
            ko "garde : /etc/timezone a été remis en place après le cas d" "le fichier est absent"
        fi
    fi

    rm -rf "$REP_STUB_RL"

    # --- Restitution --------------------------------------------------------
    # Le cas c a réellement appliqué FUSEAU_CIBLE à /etc/localtime avant de
    # mourir, et laissé /etc/timezone en arrière. Une exécution nominale remet
    # les deux d'accord ; l'état rendu est celui que le groupe 4 avait laissé, et
    # c'est vérifié plutôt que supposé.
    lancer bash "$TIMEZONE_SH" "$FUSEAU_CIBLE" -y
    assert_code 0 "$CODE" "restitution : configure-timezone.sh $FUSEAU_CIBLE sort en 0"
    assert_egal "0" "$(nb_lignes_contenant '[ERROR]')" \
        "restitution : aucune ligne [ERROR]"
    assert_egal "$FUSEAU_CIBLE" "$(cat /etc/timezone)" \
        "restitution : /etc/timezone est revenu à $FUSEAU_CIBLE"
    assert_egal "/usr/share/zoneinfo/$FUSEAU_CIBLE" "$(readlink -f /etc/localtime)" \
        "restitution : /etc/localtime est revenu à $FUSEAU_CIBLE"
    assert_egal "$TZ_ORIGINE" "$(cat /etc/timezone)" \
        "restitution : /etc/timezone porte exactement ce qu'il portait à l'entrée du groupe"
fi

# ===================================================================
# 4 quater. « hostname » en échec — configure-hostname.sh, TASK-018
# ===================================================================
# Deux sites, et une erreur de raisonnement que trois tours de relecture ont
# répétée : « require_cmd hostname » a servi d'argument pour ne pas les traiter.
# Il prouve que la commande EXISTE, pas qu'elle RÉUSSIT. Un binaire homonyme en
# tête de PATH la met en échec — la mutation la moins coûteuse du dépôt — et sous
# la forme nue « NOM_ACTUEL="$(hostname)" » le trap ERR parlait alors deux fois,
# puis errexit arrêtait le script.
#
# Les DEUX sites sont atteints par le même appel, et c'est délibéré : le faux
# hostname fait rendre « inconnu » au premier, donc demander « inconnu » comme
# nom d'hôte laisse CHANGEMENT_NOM à false. Le script n'essaie alors pas
# d'appliquer un nom — « hostname <nom> » exige CAP_SYS_ADMIN, refusé au
# conteneur, et le cas mourrait là — mais il réécrit /etc/hosts et atteint la
# vérification finale, second site.
#
# Aucun des deux échecs n'est fatal, et pour deux raisons distinctes :
#
#   au préflight      rien n'a encore été modifié, et un nom courant
#                     indéterminable n'empêche pas de poser celui qui est
#                     demandé. La valeur porte « inconnu », jamais la chaîne
#                     vide — c'est ce que fait déjà fuseau_actuel ;
#   à la vérification l'écart que cette vérification cherche n'est lui-même
#                     qu'un « warn » — certains systèmes n'appliquent le nom
#                     qu'au redémarrage. Une lecture impossible ne peut pas être
#                     punie plus sévèrement que l'écart qu'elle sert à détecter.
#
# CE GROUPE ÉCRIT /etc/hosts et y laisse une sauvegarde. Il est placé APRÈS le
# groupe 4 — dont la garde d'état compare l'empreinte à celle du groupe 2 — et
# rend l'état où il l'a trouvé, ce qu'il vérifie plutôt que de le supposer.
titre "4 quater. « hostname » en échec — configure-hostname.sh"

REP_STUB_HOST="$REP_TMP/stub-hostname"

RAISON_4QUATER="oui"
if [ "$EST_ROOT" != "true" ]; then
    RAISON_4QUATER="require_root arrête le script avant toute écriture"
elif [ "$JETABLE" != "true" ]; then
    RAISON_4QUATER="ce groupe réécrit /etc/hosts — réservé à un système jetable"
fi

if [ "$RAISON_4QUATER" != "oui" ]; then
    saute "configure-hostname.sh : « hostname » en échec aux deux sites" "$RAISON_4QUATER"
    saute "configure-hostname.sh : non-régression, « Rien à faire » quand le nom est déjà bon" "$RAISON_4QUATER"
else
    cp -p /etc/hosts "$REP_TMP/hosts.avant-4quater"
    SAUVEGARDES_AVANT_4QUATER="$(find /etc -maxdepth 1 -name 'hosts.bak-*' | wc -l | tr -d ' ')"

    mkdir -p "$REP_STUB_HOST"
    printf '#!/bin/sh\nexit 1\n' > "$REP_STUB_HOST/hostname"
    chmod +x "$REP_STUB_HOST/hostname"
    if "$REP_STUB_HOST/hostname" >/dev/null 2>&1; then
        ko "garde : le faux « hostname » échoue bien" "le stub a rendu 0"
    else
        ok "garde : le faux « hostname » échoue bien"
    fi
    # Le stub doit rester TROUVABLE : c'est tout le propos du site. Si
    # « require_cmd hostname » refusait le script, le cas mourrait en 1 sans
    # rien prouver.
    if PATH="$REP_STUB_HOST:$PATH" command -v hostname >/dev/null 2>&1; then
        ok "garde : « command -v hostname » trouve le stub — require_cmd ne refusera pas"
    else
        ko "garde : « command -v hostname » trouve le stub" "le stub n'est pas dans le PATH construit"
    fi
    # Le nom courant N'EST PAS « inconnu » : sans cela CHANGEMENT_HOSTS serait
    # peut-être déjà false et le cas ne traverserait pas /etc/hosts.
    if [ "$(hostname)" != "inconnu" ]; then
        ok "garde : le nom d'hôte de la machine n'est pas déjà « inconnu »"
    else
        ko "garde : le nom d'hôte de la machine n'est pas déjà « inconnu »" \
            "le cas ne prouverait plus que la valeur de repli a été employée"
    fi

    lancer env "PATH=$REP_STUB_HOST:$PATH" bash "$HOSTNAME_SH" inconnu -y

    # Le chemin de la sauvegarde est LU dans la trace, et non retrouvé par
    # « find -newer » : le script la produit par « cp -p », qui recopie la date
    # de /etc/hosts. Les deux fichiers ont alors le même âge, aucun n'est plus
    # récent que l'autre — c'est ce qui a fait échouer la première écriture de ce
    # nettoyage, et l'assertion de restitution l'a vu.
    CHEMIN_SAUVEGARDE_4QUATER="$(sed -n 's/^.*\[INFO\] Sauvegarde : \(.*\)$/\1/p' "$F_ERR" | tail -n 1)"

    # L'assertion décisive : sous la forme nue, ce code valait 1 et le script
    # s'arrêtait avant d'avoir rien fait.
    assert_code 0 "$CODE" \
        "configure-hostname.sh, « hostname » en échec : sort en 0 — aucun des deux échecs n'est fatal"
    # Site 1, au préflight.
    assert_contient "$(erreur)" "[WARN] « hostname » a échoué : le nom d'hôte courant reste indéterminé." \
        "configure-hostname.sh, site 1 : la cause est nommée"
    assert_contient "$(erreur)" "[WARN] Le nom demandé sera appliqué malgré tout — l'opération est sans risque." \
        "configure-hostname.sh, site 1 : l'échec est explicitement déclaré non fatal"
    assert_contient "$(erreur)" "[INFO] Nom d'hôte actuel  : inconnu" \
        "configure-hostname.sh, site 1 : la valeur de repli est « inconnu », jamais la chaîne vide"
    # Site 2, à la vérification.
    assert_contient "$(erreur)" "[WARN] « hostname » a échoué : la vérification n'a pas pu aboutir." \
        "configure-hostname.sh, site 2 : la cause est nommée"
    assert_contient "$(erreur)" "[WARN] Contrôler à la main que le nom d'hôte est « inconnu »." \
        "configure-hostname.sh, site 2 : l'appelant est renvoyé vers un contrôle manuel"
    # Le script est allé jusqu'au bout : /etc/hosts réécrit, succès annoncé.
    assert_contient "$(erreur)" "[SUCCESS] /etc/hosts mis à jour." \
        "configure-hostname.sh, « hostname » en échec : le travail utile est fait malgré tout"
    assert_contient "$(erreur)" "[SUCCESS] Nom d'hôte configuré : inconnu" \
        "configure-hostname.sh, « hostname » en échec : le script va jusqu'au bout de son chemin"
    assert_absent "$(erreur)" "Échec (code" \
        "configure-hostname.sh, « hostname » en échec : le trap ERR n'ajoute aucune ligne"
    assert_absent "$(erreur)" "configure-hostname.sh: line" \
        "configure-hostname.sh, « hostname » en échec : aucun message brut de bash sur stderr"
    assert_egal "0" "$(nb_lignes_contenant '[ERROR]')" \
        "configure-hostname.sh, « hostname » en échec : aucune ligne [ERROR] — ce sont des lacunes, pas des erreurs"
    assert_egal "4" "$(nb_lignes_contenant '[WARN]')" \
        "configure-hostname.sh, « hostname » en échec : quatre avertissements mesurés, deux par site"

    # /etc/hosts porte bien la ligne demandée : le repli n'a pas dégradé le
    # travail, il n'a dégradé que la connaissance de l'état d'avant.
    lignes_inconnu="$(grep -cE '^[[:space:]]*127\.0\.1\.1[[:space:]]+inconnu$' /etc/hosts)" || lignes_inconnu="0"
    assert_egal "1" "$lignes_inconnu" \
        "configure-hostname.sh, « hostname » en échec : /etc/hosts porte exactement une ligne « 127.0.1.1 inconnu »"

    # --- Non-régression : idempotence quand le nom est déjà bon -------------
    # Le stub est retiré. Le nom demandé est celui de la machine, /etc/hosts est
    # remis dans son état d'origine : le script doit conclure « Rien à faire »,
    # sans avertissement et sans écrire.
    rm -rf "$REP_STUB_HOST"
    cat "$REP_TMP/hosts.avant-4quater" > /etc/hosts

    empreinte "$REP_TMP/hn-avant"
    lancer bash "$HOSTNAME_SH" "$(hostname)" -y
    assert_code 0 "$CODE" \
        "non-régression : configure-hostname.sh <nom courant> sort en 0"
    assert_contient "$(erreur)" "Rien à faire : le nom d'hôte et /etc/hosts sont déjà conformes." \
        "non-régression : le script reconnaît un système déjà conforme"
    assert_egal "0" "$(nb_lignes_contenant '[ERROR]')" \
        "non-régression : aucune ligne [ERROR]"
    assert_egal "0" "$(nb_lignes_contenant '[WARN]')" \
        "non-régression : aucun avertissement — la lecture de « hostname » a réussi"
    empreinte "$REP_TMP/hn-apres"
    assert_empreinte_egale "$REP_TMP/hn-avant" "$REP_TMP/hn-apres" \
        "non-régression : un système déjà conforme n'est pas modifié"

    # --- Restitution --------------------------------------------------------
    # /etc/hosts a déjà été remis ci-dessus ; reste la sauvegarde déposée par le
    # cas au stub, et son retrait est vérifié.
    SAUVEGARDES_APRES_4QUATER="$(find /etc -maxdepth 1 -name 'hosts.bak-*' | wc -l | tr -d ' ')"
    assert_egal "$(( SAUVEGARDES_AVANT_4QUATER + 1 ))" "$SAUVEGARDES_APRES_4QUATER" \
        "configure-hostname.sh, « hostname » en échec : une sauvegarde de /etc/hosts a bien été déposée"
    if [ -z "$CHEMIN_SAUVEGARDE_4QUATER" ]; then
        ko "restitution : la sauvegarde déposée par ce groupe est retirée" \
            "aucun chemin de sauvegarde n'a pu être lu dans la trace"
    else
        rm -f "$CHEMIN_SAUVEGARDE_4QUATER"
        assert_egal "$SAUVEGARDES_AVANT_4QUATER" "$(find /etc -maxdepth 1 -name 'hosts.bak-*' | wc -l | tr -d ' ')" \
            "restitution : la sauvegarde déposée par ce groupe est retirée"
    fi
    if cmp -s "$REP_TMP/hosts.avant-4quater" /etc/hosts; then
        ok "restitution : /etc/hosts porte exactement ce qu'il portait à l'entrée du groupe"
    else
        ko "restitution : /etc/hosts porte exactement ce qu'il portait à l'entrée du groupe" \
            "le fichier diffère de l'état relevé à l'entrée"
    fi
fi

# ===================================================================
# 4 quinquies. Les trois derniers sites — « date » et la boucle de suffixe
# ===================================================================
# Les trois sites du cinquième tour qui ne se prouvent pas sans écrire, ou sans
# aller jusqu'à l'activation du swap.
#
# Les deux « date » sont des substitutions NOYÉES DANS UNE CHAÎNE —
# « base="/etc/hosts.bak-$(date …)" ». Elles ne se trouvent pas en cherchant
# « ="$( » ; c'est pour cela que le recensement impose un relevé manuel, et
# c'est pour cela qu'elles avaient été manquées. L'affectation échoue pourtant
# tout autant, et le trap parle deux fois.
#
# Leur traitement diffère, et c'est délibéré :
#
#   configure-hostname.sh  fatal, et rien n'est écrit. Sans horodatage il n'y a
#                          pas de nom de sauvegarde, donc pas de sauvegarde — et
#                          /etc/hosts ne se modifie pas sans copie préalable ;
#   configure-swap.sh      fatal aussi, mais APRÈS l'activation. Le swap reste
#                          actif pour cette session, le fichier n'est pas
#                          nettoyé — « trap - EXIT » a déjà été exécuté — et la
#                          ligne à inscrire à la main est donnée.
#
# Le troisième n'est pas une mise en condition mais une SUPPRESSION : la boucle
# de désambiguïsation rappelait « date », si bien qu'une collision de nom
# produisait « …-<nouvel horodatage>-1 » alors que « …-<nouvel horodatage> »
# était libre. L'horodatage est désormais lu une fois et réutilisé.
#
# CE GROUPE ÉCRIT /etc/fstab et /etc/hosts, et active un swap — par un faux
# swapon, le vrai exigeant CAP_SYS_ADMIN. Il est placé APRÈS le groupe 4 et rend
# l'état où il l'a trouvé, ce qu'il vérifie plutôt que de le supposer.
titre "4 quinquies. « date » et la boucle de suffixe"

REP_STUB_DATE="$REP_TMP/stub-date"
REP_STUB_SWAPON="$REP_TMP/stub-swapon"
REP_STUB_HORO="$REP_TMP/stub-horodatage"

RAISON_4QUINQ="oui"
if [ "$EST_ROOT" != "true" ]; then
    RAISON_4QUINQ="require_root arrête ces scripts avant toute écriture"
elif [ "$JETABLE" != "true" ]; then
    RAISON_4QUINQ="ce groupe réécrit /etc/hosts et /etc/fstab — réservé à un système jetable"
fi

if [ "$RAISON_4QUINQ" != "oui" ]; then
    saute "configure-hostname.sh : « date » en échec, rien n'est écrit" "$RAISON_4QUINQ"
    saute "configure-swap.sh : « date » en échec en phase fstab" "$RAISON_4QUINQ"
    saute "configure-swap.sh : la boucle de suffixe réutilise l'horodatage" "$RAISON_4QUINQ"
else
    mkdir -p "$REP_STUB_DATE" "$REP_STUB_SWAPON"
    printf '#!/bin/sh\nexit 1\n' > "$REP_STUB_DATE/date"
    chmod +x "$REP_STUB_DATE/date"
    if "$REP_STUB_DATE/date" '+%Y%m%d-%H%M%S' >/dev/null 2>&1; then
        ko "garde : le faux « date » échoue bien" "le stub a rendu 0"
    else
        ok "garde : le faux « date » échoue bien"
    fi

    # --- i. configure-hostname.sh : fatal, et /etc/hosts INTACT -------------
    # Le nom demandé est celui de la machine, et /etc/hosts est vidé de sa ligne
    # 127.0.1.1 : le script a donc un changement à appliquer et atteint la
    # sauvegarde. Sans cela il sortirait sur « Rien à faire ».
    #
    # Le faux « date » est TOTAL, et c'est sans danger ici : le « $(date …) » de
    # lib/common.sh est en POSITION D'ARGUMENT dans son printf — il ne double
    # rien et ne tue rien, l'horodatage du journal reste seulement vide. Mesuré.
    cp -p /etc/hosts "$REP_TMP/hosts.avant-4quinq"
    printf '127.0.0.1\tlocalhost\n' > /etc/hosts
    HOSTS_AVANT_DATE="$(empreinte_fichier /etc/hosts)"
    SAUVEGARDES_AVANT_DATE="$(find /etc -maxdepth 1 -name 'hosts.bak-*' | wc -l | tr -d ' ')"

    lancer env "PATH=$REP_STUB_DATE:$PATH" bash "$HOSTNAME_SH" "$(hostname)" -y

    assert_code 1 "$CODE" \
        "configure-hostname.sh, « date » en échec : échec d'exécution, code 1"
    assert_contient "$(erreur)" "[ERROR] Horodatage impossible à produire : « date » a échoué." \
        "configure-hostname.sh, « date » en échec : le diagnostic nomme date"
    assert_contient "$(erreur)" "[ERROR] /etc/hosts n'a pas été modifié, faute de pouvoir le sauvegarder." \
        "configure-hostname.sh, « date » en échec : le diagnostic dit ce qui n'a PAS été fait"
    assert_absent "$(erreur)" "Échec (code" \
        "configure-hostname.sh, « date » en échec : le trap ERR n'ajoute aucune ligne"
    assert_absent "$(erreur)" "configure-hostname.sh: line" \
        "configure-hostname.sh, « date » en échec : aucun message brut de bash sur stderr"
    assert_absent "$(erreur)" "Sauvegarde :" \
        "configure-hostname.sh, « date » en échec : aucune sauvegarde n'est même annoncée"
    assert_egal "3" "$(nb_lignes_contenant '[ERROR]')" \
        "configure-hostname.sh, « date » en échec : trois lignes [ERROR] mesurées"
    assert_egal "0" "$(nb_lignes_contenant '[WARN]')" \
        "configure-hostname.sh, « date » en échec : aucun avertissement — « hostname », lui, a réussi"
    assert_egal "$HOSTS_AVANT_DATE" "$(empreinte_fichier /etc/hosts)" \
        "configure-hostname.sh, « date » en échec : /etc/hosts est resté strictement intact"
    assert_egal "$SAUVEGARDES_AVANT_DATE" "$(find /etc -maxdepth 1 -name 'hosts.bak-*' | wc -l | tr -d ' ')" \
        "configure-hostname.sh, « date » en échec : AUCUNE sauvegarde n'a été déposée"

    cat "$REP_TMP/hosts.avant-4quinq" > /etc/hosts

    # --- j. configure-swap.sh : « date » en échec APRÈS l'activation --------
    # Le seul site du dépôt qui s'atteigne après « trap - EXIT ». Deux
    # conséquences, et les deux sont voulues : le fichier d'échange n'est PAS
    # nettoyé — le trap de nettoyage a été désarmé —, et le swap reste actif pour
    # la session. Seule sa persistance manque, et la ligne à inscrire est donnée.
    #
    # swapon est remplacé par un stub qui rend 0 : le vrai exige CAP_SYS_ADMIN,
    # refusé au conteneur, et sans lui le script mourrait avant la phase fstab.
    # Ce que ce cas éprouve n'est donc pas l'activation — elle reste NON EXÉCUTÉE
    # au groupe 5 — mais tout ce qui la suit.
    printf '#!/bin/sh\nexit 0\n' > "$REP_STUB_SWAPON/swapon"
    chmod +x "$REP_STUB_SWAPON/swapon"

    SWAP_FSTAB="$REP_TMP/swapfile-fstab"
    cp -p /etc/fstab "$REP_TMP/fstab.avant-4quinq"
    SAUVEGARDES_FSTAB_AVANT="$(find /etc -maxdepth 1 -name 'fstab.bak-*' | wc -l | tr -d ' ')"

    if [ -e "$SWAP_FSTAB" ]; then
        ko "garde : le fichier d'échange témoin n'existe pas avant l'appel" "$SWAP_FSTAB existe"
    else
        ok "garde : le fichier d'échange témoin n'existe pas avant l'appel"
    fi

    lancer env "PATH=$REP_STUB_DATE:$REP_STUB_SWAPON:$PATH" \
        bash "$SWAP_SH" 64M --file "$SWAP_FSTAB" -y

    assert_code 1 "$CODE" \
        "configure-swap.sh, « date » en échec en phase fstab : échec d'exécution, code 1"
    assert_contient "$(erreur)" "[SUCCESS] Swap actif : $SWAP_FSTAB (64 Mo)" \
        "configure-swap.sh, « date » en phase fstab : l'activation a bien eu lieu avant l'échec"
    assert_contient "$(erreur)" "[ERROR] Horodatage impossible à produire : « date » a échoué." \
        "configure-swap.sh, « date » en phase fstab : le diagnostic nomme date"
    assert_contient "$(erreur)" "[ERROR] Le swap est actif pour cette session, mais pas au redémarrage." \
        "configure-swap.sh, « date » en phase fstab : l'état réel est dit à l'appelant"
    assert_contient "$(erreur)" "[ERROR] Ligne à ajouter : $SWAP_FSTAB	none	swap	sw	0	0" \
        "configure-swap.sh, « date » en phase fstab : la ligne fstab est donnée telle quelle"
    assert_absent "$(erreur)" "Échec (code" \
        "configure-swap.sh, « date » en phase fstab : le trap ERR n'ajoute aucune ligne"
    assert_absent "$(erreur)" "configure-swap.sh: line" \
        "configure-swap.sh, « date » en phase fstab : aucun message brut de bash sur stderr"
    assert_egal "5" "$(nb_lignes_contenant '[ERROR]')" \
        "configure-swap.sh, « date » en phase fstab : cinq lignes [ERROR] mesurées"

    # Le fichier n'est PAS nettoyé : « trap - EXIT » a précédé l'échec. C'est le
    # seul cas du dépôt à éprouver ce désarmement, et l'inverse — un fichier
    # effacé alors que le swap est actif — serait une perte de swap silencieuse.
    if [ -e "$SWAP_FSTAB" ]; then
        ok "configure-swap.sh, « date » en phase fstab : le fichier d'échange subsiste — le trap de nettoyage est bien désarmé"
    else
        ko "configure-swap.sh, « date » en phase fstab : le fichier d'échange subsiste" \
            "$SWAP_FSTAB a été supprimé alors que le swap était actif"
    fi
    assert_absent "$(erreur)" "a été supprimé" \
        "configure-swap.sh, « date » en phase fstab : aucun nettoyage n'est même annoncé"

    if cmp -s "$REP_TMP/fstab.avant-4quinq" /etc/fstab; then
        ok "configure-swap.sh, « date » en phase fstab : /etc/fstab est resté intact"
    else
        ko "configure-swap.sh, « date » en phase fstab : /etc/fstab est resté intact" \
            "le fichier a été modifié sans sauvegarde préalable"
    fi
    assert_egal "$SAUVEGARDES_FSTAB_AVANT" "$(find /etc -maxdepth 1 -name 'fstab.bak-*' | wc -l | tr -d ' ')" \
        "configure-swap.sh, « date » en phase fstab : aucune sauvegarde de /etc/fstab n'a été déposée"

    rm -f "$SWAP_FSTAB"

    # --- k. La boucle de suffixe réutilise l'horodatage ----------------------
    # La substitution SUPPRIMÉE. La boucle rappelait « date » à chaque tour :
    # quand le nom de base était pris, elle produisait « …-<NOUVEL horodatage>-1 »
    # alors que « …-<nouvel horodatage> » était libre. Deux horodatages mêlés
    # dans un même nom, et un suffixe posé pour rien.
    #
    # Le montage est le seul qui discrimine les deux formes. Un « date » à valeur
    # FIXE ne dirait rien — les deux écriraient le même nom. Le stub compte donc
    # les appels PORTANT LE FORMAT DU SITE, « +%Y%m%d-%H%M%S », et rend « HORO<n> ».
    # Celui de lib/common.sh emploie un autre format et est délégué : il ne fausse
    # pas le compte, ce qui a été mesuré — sans ce filtre, le socle consommait
    # quinze appels et le cas ne prouvait rien.
    #
    #   forme corrigée   un seul appel  -> HORO1, nom pris, suffixe -> HORO1-1
    #   forme nue        deux appels    -> HORO1 pris, la boucle relit -> HORO2-1
    #
    # Les deux assertions — le nom produit ET le nombre d'appels — se contrôlent
    # l'une l'autre.
    mkdir -p "$REP_STUB_HORO"
    # Guillemets simples VOULUS, comme pour les stubs précédents : « $* », « $n »
    # et « $@ » sont développés par le stub, pas par le harnais. SC2016 signale
    # exactement ce qu'on veut ici.
    # shellcheck disable=SC2016
    {
        printf '#!/bin/sh\n'
        printf 'case "$*" in\n'
        printf '  "+%%Y%%m%%d-%%H%%M%%S")\n'
        printf '    n=0\n'
        printf '    [ -f %s ] && n=$(cat %s)\n' "$REP_STUB_HORO/compteur" "$REP_STUB_HORO/compteur"
        printf '    n=$((n + 1))\n'
        printf '    echo "$n" > %s\n' "$REP_STUB_HORO/compteur"
        printf '    echo "HORO$n"\n'
        printf '    exit 0\n'
        printf '    ;;\n'
        printf 'esac\n'
        printf 'exec %s "$@"\n' "$(command -v date)"
    } > "$REP_STUB_HORO/date"
    chmod +x "$REP_STUB_HORO/date"
    rm -f "$REP_STUB_HORO/compteur"

    if [ "$("$REP_STUB_HORO/date" '+%Y%m%d-%H%M%S')" = "HORO1" ] \
        && [ "$("$REP_STUB_HORO/date" '+%Y%m%d-%H%M%S')" = "HORO2" ]; then
        ok "garde : le faux « date » numérote ses appels au format du site"
    else
        ko "garde : le faux « date » numérote ses appels au format du site" \
            "le stub ne rend pas HORO1 puis HORO2"
    fi
    if [ -n "$("$REP_STUB_HORO/date" '+%Y')" ] && [ "$("$REP_STUB_HORO/date" '+%Y')" != "HORO3" ]; then
        ok "garde : le faux « date » délègue les autres formats — le socle ne fausse pas le compte"
    else
        ko "garde : le faux « date » délègue les autres formats" \
            "un format étranger a été numéroté ; le compteur ne dirait plus ce qu'on lui demande"
    fi
    rm -f "$REP_STUB_HORO/compteur"

    # Le nom de base est occupé d'avance : la boucle DOIT s'exécuter.
    : > /etc/fstab.bak-HORO1
    lancer env "PATH=$REP_STUB_HORO:$REP_STUB_SWAPON:$PATH" \
        bash "$SWAP_SH" 64M --file "$SWAP_FSTAB" -y

    # Le code est 1 : le faux swapon n'a rien activé, et la vérification finale
    # le voit. C'est le contrat de cet environnement, pas un défaut — l'assertion
    # le fige plutôt que de le taire.
    assert_code 1 "$CODE" \
        "boucle de suffixe : le script sort en 1 — le faux swapon n'inscrit rien dans /proc/swaps"
    assert_contient "$(erreur)" "[ERROR] $SWAP_FSTAB n'apparaît pas dans /proc/swaps après activation." \
        "boucle de suffixe : c'est bien la vérification finale qui refuse, et rien d'autre"
    assert_contient "$(erreur)" "[SUCCESS] /etc/fstab complété : le swap sera actif au redémarrage." \
        "boucle de suffixe : la phase fstab est allée à son terme"
    assert_absent "$(erreur)" "Échec (code" \
        "boucle de suffixe : le trap ERR n'ajoute aucune ligne"

    # LES DEUX ASSERTIONS QUI DISCRIMINENT.
    assert_contient "$(erreur)" "[INFO] Sauvegarde : /etc/fstab.bak-HORO1-1" \
        "boucle de suffixe : le nom suffixé réutilise l'horodatage déjà lu, et n'en produit pas un second"
    assert_egal "1" "$(cat "$REP_STUB_HORO/compteur" 2>/dev/null || printf '0')" \
        "boucle de suffixe : « date » n'a été appelé QU'UNE FOIS au format du site"

    if [ -f /etc/fstab.bak-HORO1-1 ]; then
        ok "boucle de suffixe : la sauvegarde suffixée existe bien sur le disque"
    else
        ko "boucle de suffixe : la sauvegarde suffixée existe bien sur le disque" \
            "/etc/fstab.bak-HORO1-1 est absent"
    fi

    # --- Restitution --------------------------------------------------------
    # Le motif est large — « HORO* » et non les deux noms littéraux : sous la
    # mutation qui rétablit l'appel à « date » dans la boucle, le nom produit
    # porte un autre horodatage, et un nettoyage littéral le laisserait derrière
    # lui. La restitution doit rester vraie même quand le script est fautif.
    rm -f /etc/fstab.bak-HORO* "$SWAP_FSTAB"
    cat "$REP_TMP/fstab.avant-4quinq" > /etc/fstab
    rm -rf "$REP_STUB_DATE" "$REP_STUB_SWAPON" "$REP_STUB_HORO"

    if cmp -s "$REP_TMP/fstab.avant-4quinq" /etc/fstab; then
        ok "restitution : /etc/fstab porte exactement ce qu'il portait à l'entrée du groupe"
    else
        ko "restitution : /etc/fstab porte exactement ce qu'il portait à l'entrée du groupe" \
            "le fichier diffère de l'état relevé à l'entrée"
    fi
    assert_egal "$SAUVEGARDES_FSTAB_AVANT" "$(find /etc -maxdepth 1 -name 'fstab.bak-*' | wc -l | tr -d ' ')" \
        "restitution : les sauvegardes de /etc/fstab déposées par ce groupe sont retirées"
    if cmp -s "$REP_TMP/hosts.avant-4quinq" /etc/hosts; then
        ok "restitution : /etc/hosts porte exactement ce qu'il portait à l'entrée du groupe"
    else
        ko "restitution : /etc/hosts porte exactement ce qu'il portait à l'entrée du groupe" \
            "le fichier diffère de l'état relevé à l'entrée"
    fi
    if [ -e "$SWAP_FSTAB" ]; then
        ko "restitution : le fichier d'échange témoin est supprimé" "$SWAP_FSTAB subsiste"
    else
        ok "restitution : le fichier d'échange témoin est supprimé"
    fi
fi

# ===================================================================
# 5. Hors de portée de cet environnement
# ===================================================================
# Ces lignes ne sont pas des cas manqués : ce sont des cas dont on sait qu'ils
# ne peuvent pas être joués ici. Les taire ferait croire à une couverture
# complète.
titre "5. Hors de portée de cet environnement"

# DEUX SAUTS ONT DISPARU D'ICI, ET C'EST UNE PREUVE QUI A PRIS LEUR PLACE.
#
# « configure-timezone.sh appliquant le fuseau par timedatectl » et
# « configure-hostname.sh changeant réellement le nom de la machine »
# attendaient le profil « systemd » depuis ADR-0001. TASK-020 l'a construit —
# tests/env/Dockerfile.systemd — et les deux cas sont désormais EXÉCUTÉS, aux
# groupes 3 et 4 de tests/environment/systemd.test.sh :
#
#   tests/env/run-in-container.sh --profil systemd -- tests/run.sh environment
#
# Ils ne sont pas rejoués ici, et ne doivent pas l'être : ce niveau reste
# l'affaire du profil « debian », où plusieurs assertions tiennent PRÉCISÉMENT
# parce que systemd est absent — le repli /etc/localtime du groupe 4 ter, les
# décomptes de lignes de stderr, la garde « timedatectl répondrait » du même
# groupe. Les lancer sous un init les rendrait rouges sans qu'aucun défaut
# n'existe.
saute "configure-swap.sh créant, activant et inscrivant un fichier d'échange" \
    "swapon exige CAP_SYS_ADMIN, refusé au conteneur non privilégié"
saute "update-system.sh appliquant réellement apt-get upgrade" \
    "exclu par TASK-004 : l'image n'a aucun paquet obsolète, la mise à jour n'apprendrait rien"
saute "configure-logging.sh sur un système sans le groupe « adm »" \
    "l'image Debian le fournit toujours — la branche GROUPE_LOGS=root reste sans preuve"

# Les sites de TASK-018 dont la CAUSE D'ÉCHEC n'est pas atteignable depuis une
# ligne de commande ni depuis l'environnement de l'appel. Le groupe 3 quater, le
# groupe 4 bis et tests/integration/configure-cron.test.sh prouvent les autres ;
# ceux-ci restent des corrections que rien n'a exécutées, et les taire laisserait
# croire tout le lot vérifié.
#
# Chacun a été REMIS EN FORME NUE, et le fichier de cas est resté intégralement
# vert : c'est la mesure qui justifie ces lignes, et non une lecture du code.
#
# « saute » NEUTRE, et non « saute_par_nature ». La distinction n'est pas
# cosmétique : « par nature » est une SIGNATURE, elle affirme qu'aucune exécution
# ne rendra jamais ce cas atteignable. Or la raison invoquée pour df -T et df -BM
# — « le contrôle de répertoire les précède » — est une propriété du code que
# CETTE MÊME TÂCHE vient d'ajouter, pas une limite de l'environnement de test.
# Une correction rendue invérifiable par une autre correction du même diff ne
# peut pas s'auto-certifier hors d'atteinte. Le saut neutre dit ce qu'on sait :
# le cas n'a pas tourné, et il n'est pas compté comme réussi.
saute "configure-swap.sh : df -T en échec sur un répertoire EXISTANT" \
    "le contrôle de répertoire ajouté par TASK-018 intercepte le seul cas atteignable — les cas a, b et b bis du groupe 3 quater éprouvent ce contrôle, pas la mise en condition de df ; faire échouer df sur un répertoire existant demanderait de démonter un système de fichiers sous les pieds du script"
saute "configure-swap.sh : df -BM en échec sur le calcul d'espace libre" \
    "le même contrôle le précède, et le répertoire a déjà servi à df -T quelques lignes plus haut — aucune ligne de commande n'atteint cet échec"
saute_par_nature "configure-swap.sh : /proc/swaps illisible avant swapoff" \
    "ce chemin exige un swap ACTIF sur la cible — swapon exige CAP_SYS_ADMIN, refusé au conteneur — et un /proc rendu illisible en cours d'exécution"
saute_par_nature "configure-swap.sh : /proc/meminfo illisible avant swapoff" \
    "même chemin et même condition que /proc/swaps ci-dessus"
saute "configure-timezone.sh : la seconde lecture de /etc/timezone, à la vérification" \
    "l'atteindre demanderait un tr qui échoue à la vérification seulement, après avoir réussi à la mise en cohérence — le stub du groupe 4 ter échoue aux deux et le script meurt à la première"

# Le cinquième tour a FERMÉ les six sites que le quatrième laissait en forme nue,
# plus le « dirname ». Il ne reste ici qu'une réserve, et elle n'est pas un
# doublement : sa nature est différente, et la nommer parmi les autres serait la
# noyer.
# --- Ce que le groupe 2 bis n'a PAS pu prouver, et pourquoi ----------------
# TASK-021. Ces quatre lignes valent autant que les assertions vertes : elles
# disent où la couverture de check-disk.sh s'arrête.
saute "check-disk.sh : la surcharge par un config/server.env RÉELLEMENT ÉCRIT" \
    "le groupe 2 bis transmet SRV_DISK_SEUIL et SRV_DISK_REPERTOIRE par l'environnement — même variable, même « set -a » de lib/common.sh, mais le CHARGEMENT du fichier n'est pas emprunté. L'écrire imposerait de créer config/server.env dans le dépôt monté, qui n'est pas un système jetable"
saute "check-disk.sh : /proc/partitions ILLISIBLE, lsblk absent" \
    "la seule branche du script qu'aucun montage n'atteint ici — il faudrait remonter /proc, ce qu'un conteneur non privilégié ne permet pas ; « lsblk absent » et « awk en échec » couvrent les deux autres sorties de cette section"
saute_par_nature "check-disk.sh : « df » suspendu sur un montage réseau injoignable" \
    "explicitement hors périmètre de TASK-021 (out_of_scope) — le sujet demande « df -l » ou une borne de temps, et l'image de test ne monte ni NFS ni CIFS"
saute "check-disk.sh : le comportement sur un système de fichiers RÉELLEMENT au-delà du seuil" \
    "l'occupation de la racine du conteneur est celle de l'hôte et n'est pas pilotable — le franchissement du seuil est éprouvé par un faux « df » à 90 %, jamais sur un disque réellement plein"

saute "update-system.sh:133 — « restant » vide passé à un test arithmétique" \
    "le « || true » empêche le doublement mais laisse une chaîne vide au « -gt 0 » qui suit — réserve d'une autre nature, versée aux points en suspens"

# ===================================================================
# Nettoyage
# ===================================================================
# Le répertoire jetable est supprimé, et son absence vérifiée : le trap EXIT
# n'est qu'un filet, il ne rend compte de rien.
titre "6. Nettoyage"

diff_final="$REP_TMP"
rm -rf "$REP_TMP"
rm -rf "$LOG_DIR_NOBODY"

if [ -e "$diff_final" ]; then
    ko "le répertoire de travail jetable est supprimé" "$diff_final subsiste"
else
    ok "le répertoire de travail jetable est supprimé"
fi

# Les cibles du groupe 1 bis §6 f et g vivent hors de REP_TMP — elles doivent
# être traversables par un utilisateur non privilégié, ce qu'un « mktemp -d » en
# mode 700 interdit. Elles sont donc retirées ici, et leur retrait vérifié : un
# répertoire en 755 laissé dans /tmp est un résidu, fût-il jetable.
if [ -n "${REP_CIBLES:-}" ]; then
    rm -rf "$REP_CIBLES"
    if [ -e "$REP_CIBLES" ]; then
        ko "le répertoire des cibles de refus est supprimé" "$REP_CIBLES subsiste"
    else
        ok "le répertoire des cibles de refus est supprimé"
    fi
else
    saute "le retrait du répertoire des cibles de refus" \
        "le groupe 1 bis §6 n'a pas été atteint sur cet hôte"
fi

bilan "TASK-004 / Linux/System"
