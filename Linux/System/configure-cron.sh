#!/usr/bin/env bash
# configure-cron.sh — installe la planification des scripts automatiques.
#
# À lancer une fois par serveur. Dépose /etc/cron.d/mgnetworking : les variables
# d'environnement de cron (SHELL, PATH) et une ligne par tâche planifiée.
#
# Trois contraintes propres à cron gouvernent le contenu déposé :
#   1. cron n'utilise pas sudo — le champ « root » suit l'horaire ;
#   2. cron n'a pas de terminal — les scripts sont appelés avec --yes, sans quoi
#      ils attendraient indéfiniment une réponse à leur confirmation ;
#   3. cron expédie par courriel tout ce qu'un travail écrit — la sortie
#      standard est jetée, la sortie d'erreur ne l'est pas : c'est aujourd'hui
#      la seule alerte disponible en cas d'échec.
#
# Deux contraintes propres à /etc/cron.d gouvernent le fichier lui-même :
# un nom comportant un point est ignoré silencieusement, et un fichier qui
# n'appartient pas à root ou qui est exécutable est rejeté. Le script vérifie
# les deux plutôt que de les supposer.
#
# La ligne déposée invoque « /bin/bash <chemin> » et non le chemin seul : Git ne
# conserve le bit d'exécution que si l'index le porte, et les fichiers de ce
# dépôt étaient enregistrés en 100644 quand ce script a été écrit. Sur un serveur
# issu d'un « git clone », un appel direct rendait alors 126 à chaque passage, en
# silence. Ils sont en 100755 depuis le 2026-09-02 (ADR-0003, décision 11), mais
# la forme est conservée : elle vaut aussi pour un dépôt déployé par copie ou par
# archive, où le bit se perd.
#
# Idempotent : relançable sans effet de bord.

set -Eeuo pipefail

_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_dir/lib/common.sh" ] && [ "$_dir" != "/" ]; do _dir="$(dirname "$_dir")"; done
source "$_dir/lib/common.sh"

DRY_RUN="false"
HORAIRE=""

# Nom volontairement sans point : cron ignore tout fichier de /etc/cron.d dont
# le nom en comporte un, et le fait sans rien dire.
NOM_TACHE="mgnetworking"
REPERTOIRE_CRON="/etc/cron.d"
FICHIER_CRON="$REPERTOIRE_CRON/$NOM_TACHE"

# Tous les lundis à 4 h. Voir le README du domaine pour le raisonnement.
HORAIRE_DEFAUT="0 4 * * 1"

# Le chemin du dépôt n'est jamais écrit en dur : SCRIPTS_ROOT est résolu par
# lib/common.sh depuis l'emplacement réel des fichiers. Le même script produit
# donc la bonne ligne, que le dépôt soit dans /opt/mgnetworking ou ailleurs.
SCRIPT_PLANIFIE="$SCRIPTS_ROOT/Linux/System/update-system.sh"

# Le répertoire des journaux, cité dans le fichier déposé pour dire où retrouver
# la trace de ce que cron a jeté.
REPERTOIRE_LOGS="$LOG_DIR"

# Renseigné au moment de l'écriture, relu par le nettoyage sur EXIT.
FICHIER_TEMPORAIRE=""

# -------------------------------------------------------------------
# Aide
# -------------------------------------------------------------------
show_help() {
    cat <<AIDE
Usage : configure-cron.sh [options]

Installe la planification des scripts destinés à tourner sans humain, dans
$FICHIER_CRON.

Une seule tâche est planifiée à ce jour :

  update-system.sh --yes    mise à jour des paquets (Debian, Ubuntu)

L'horaire est pris dans cet ordre :
  1. l'option --horaire de la ligne de commande ;
  2. SRV_CRON_UPDATE_SYSTEM dans config/server.env ;
  3. « $HORAIRE_DEFAUT » — tous les lundis à 4 h.

Format de l'horaire : les cinq champs de cron, entre guillemets.

  minute  heure  jour-du-mois  mois  jour-de-semaine

Les raccourcis « @weekly », « @daily » et consorts ne sont pas acceptés ici :
le script attend les cinq champs, plus explicites à la relecture.

Ce que le fichier déposé garantit :
  - l'utilisateur « root » est placé après l'horaire — cron n'utilise pas sudo ;
  - le script est lancé par « /bin/bash <chemin> » et non par le chemin seul :
    les fichiers du dépôt sont enregistrés dans Git sans bit d'exécution, et un
    appel direct rendrait 126 à chaque passage sur un serveur cloné ;
  - le script est appelé avec --yes — cron n'a pas de terminal, une demande de
    confirmation resterait sans réponse ;
  - la sortie standard est jetée, la sortie d'erreur est CONSERVÉE. Cron expédie
    par courriel ce qu'un travail écrit : sans cela, la sortie complète d'apt
    serait envoyée à chaque exécution. La sortie d'erreur, elle, reste la seule
    alerte disponible en cas d'échec.

Le chemin du dépôt n'est pas écrit en dur : il est celui d'où ce script est
lancé, soit $SCRIPTS_ROOT.

Aucun rechargement n'est nécessaire après le dépôt : cron relit $REPERTOIRE_CRON
de lui-même dès que son contenu change.

À lancer une fois par serveur. Relançable sans effet de bord.

Options :
      --horaire <cinq champs>  Horaire de update-system.sh.
                               Exemple : --horaire "30 5 * * 7"
      --dry-run                Afficher le fichier qui serait écrit, sans rien
                               modifier. Dans ce mode seulement, l'absence du
                               démon cron est signalée sans arrêter le script :
                               l'aperçu reste consultable sur une machine où
                               cron n'est pas encore installé. Hors --dry-run,
                               le script s'arrête — il n'installe pas cron.
  -y, --yes                    Ne pas demander de confirmation avant de
                               remplacer un fichier existant différent.
  -h, --help                   Afficher cette aide

Codes de retour :
  0   le fichier est en place et conforme
  1   échec
  2   erreur d'usage — option inconnue, horaire invalide
AIDE
}

# -------------------------------------------------------------------
# Analyse des arguments
# -------------------------------------------------------------------
while [ "${1:-}" != "" ]; do
    case "$1" in
        --horaire)
            shift
            [ -n "${1:-}" ] || die "--horaire attend les cinq champs de cron, entre guillemets." 2
            HORAIRE="$1"; shift
            ;;
        --dry-run)  DRY_RUN="true"; shift ;;
        # ASSUME_YES est lue par confirm(), dans lib/common.sh.
        -y|--yes)   export ASSUME_YES="true"; shift ;;
        -h|--help)  show_help; exit 0 ;;
        *)          die "Option inconnue : $1" 2 ;;
    esac
done

# Ligne de commande d'abord, config/server.env ensuite, valeur par défaut à
# défaut. Le dépôt reste ainsi utilisable sans aucune configuration.
ORIGINE_HORAIRE="argument"
if [ -z "$HORAIRE" ]; then
    HORAIRE="${SRV_CRON_UPDATE_SYSTEM:-}"
    ORIGINE_HORAIRE="config/server.env"
fi
if [ -z "$HORAIRE" ]; then
    HORAIRE="$HORAIRE_DEFAUT"
    ORIGINE_HORAIRE="valeur par défaut"
fi

# -------------------------------------------------------------------
# Validation de l'horaire
# -------------------------------------------------------------------
# Contrôle de forme, pas d'interprétation : cinq champs, et rien d'autre que les
# caractères qu'un champ de cron peut contenir. Un horaire mal formé n'est pas
# refusé par cron au dépôt — il est simplement journalisé et jamais exécuté.
#
# La fonction renseigne HORAIRE plutôt que d'écrire sur stdout : appelée dans une
# substitution de commande, ses « die » ne sortiraient que du sous-shell.
valider_horaire() {
    local horaire="$1"
    local champ
    local -a champs=()

    case "$horaire" in
        @*)
            error "Raccourci non accepté : « $horaire »."
            error "Écrire les cinq champs : « $HORAIRE_DEFAUT » pour tous les lundis à 4 h."
            die "Aucune modification effectuée." 2
            ;;
    esac

    read -r -a champs <<< "$horaire"

    if [ "${#champs[@]}" -ne 5 ]; then
        error "Horaire invalide : « $horaire » — ${#champs[@]} champ(s) au lieu de 5."
        error "Attendu : minute heure jour-du-mois mois jour-de-semaine."
        die "Aucune modification effectuée." 2
    fi

    for champ in "${champs[@]}"; do
        case "$champ" in
            # Le pourcent est proscrit partout dans une ligne de crontab : cron
            # le remplace par un retour à la ligne et coupe la commande.
            *[!0-9A-Za-z*,/-]*)
                error "Champ d'horaire invalide : « $champ » dans « $horaire »."
                error "Caractères acceptés : chiffres, lettres, « * » « , » « - » « / »."
                die "Aucune modification effectuée." 2
                ;;
        esac
    done

    # Forme normalisée : les espaces multiples sont ramenés à un seul, sans quoi
    # deux écritures du même horaire produiraient deux fichiers différents et
    # l'idempotence serait perdue.
    HORAIRE="${champs[*]}"
}

valider_horaire "$HORAIRE"

# -------------------------------------------------------------------
# Préflight
# -------------------------------------------------------------------
require_root

# La seule tâche planifiée à ce jour est une mise à jour apt : la planifier
# ailleurs déposerait un travail voué à échouer à chaque exécution.
require_os debian ubuntu

# Garde contre une modification malheureuse du nom : cron ignore, sans rien
# dire, tout fichier de /etc/cron.d dont le nom comporte un point.
case "$NOM_TACHE" in
    *.*) die "Le nom « $NOM_TACHE » contient un point : cron ignorerait ce fichier." ;;
esac

if [ ! -f "$SCRIPT_PLANIFIE" ]; then
    die "Script à planifier introuvable : $SCRIPT_PLANIFIE"
fi

# Le bit d'exécution est posé dans Git depuis le 2026-09-02 : un dépôt cloné le
# porte désormais. Le contrôle reste utile — il attrape un déploiement par copie
# ou par archive, où le bit se perd. La ligne déposée s'en accommode de toute
# façon, elle invoque « /bin/bash <chemin> » ; mais sans ce bit, le script ne se
# lance pas à la main par « ./update-system.sh ».
if [ ! -x "$SCRIPT_PLANIFIE" ]; then
    warn "$SCRIPT_PLANIFIE n'est pas exécutable."
    warn "La tâche planifiée fonctionnera : la ligne déposée passe par /bin/bash."
    warn "Pour le lancer à la main : chmod +x $SCRIPT_PLANIFIE"
fi

# Un chemin de déploiement contenant un espace ou un pourcent casserait la ligne
# de crontab : cron passe tout ce qui suit l'utilisateur au shell, et traite le
# pourcent comme un retour à la ligne.
case "$SCRIPT_PLANIFIE" in
    *[[:space:]]*)
        error "Le chemin du dépôt contient une espace : $SCRIPT_PLANIFIE"
        die "cron ne saurait exécuter cette ligne — déplacer le dépôt dans un chemin sans espace."
        ;;
    *%*)
        error "Le chemin du dépôt contient un « % » : $SCRIPT_PLANIFIE"
        die "cron remplace le « % » par un retour à la ligne — déplacer le dépôt."
        ;;
esac

# --- Dépendance : cron lui-même --------------------------------------------
# La dépendance se mesure sur le démon, jamais sur /etc/cron.d : ce répertoire
# n'est pas fourni par le paquet cron. Sur Debian 12, « dpkg -S /etc/cron.d »
# répond « e2fsprogs » — il existe donc sur toute installation, y compris
# lorsque cron n'est pas installé. Le tester ne prouverait rien.
#
# Le démon ne se cherche pas non plus par « command -v » seul : il vit dans
# /usr/sbin, absent du PATH de certains environnements même en root.
chemin_demon_cron() {
    local candidat
    for candidat in cron crond; do
        if command -v "$candidat" >/dev/null 2>&1; then
            command -v "$candidat"
            return 0
        fi
    done
    # Repli hors PATH, pour la raison dite plus haut.
    for candidat in /usr/sbin/cron /usr/sbin/crond; do
        if [ -x "$candidat" ]; then
            printf '%s\n' "$candidat"
            return 0
        fi
    done
    return 1
}

# Le script n'installe pas cron : déposer un fichier que rien ne lira donnerait
# une planification imaginaire. Seul --dry-run tolère l'absence, puisqu'il
# n'écrit rien et sert justement à consulter le contenu avant installation.
if DEMON_CRON="$(chemin_demon_cron)"; then
    info "Démon cron : $DEMON_CRON"
elif [ "$DRY_RUN" = "true" ]; then
    warn "Aucun démon cron trouvé : cron n'est pas installé sur ce serveur."
    warn "L'installer avec : apt-get install cron"
    warn "Mode --dry-run : l'aperçu est produit malgré tout, rien ne sera écrit."
else
    error "Aucun démon cron trouvé : cron n'est pas installé sur ce serveur."
    error "L'installer avec : apt-get install cron"
    die "Prérequis manquant."
fi

# Contrôle secondaire, une fois le démon trouvé : une installation incomplète
# laisserait le script écrire dans un répertoire inexistant.
if [ ! -d "$REPERTOIRE_CRON" ] && [ "$DRY_RUN" != "true" ]; then
    die "$REPERTOIRE_CRON est absent : installation de cron incomplète."
fi

# --- Conflits : la même tâche planifiée ailleurs ----------------------------
# Une planification en double exécuterait deux mises à jour concurrentes, dont
# la seconde échouerait sur le verrou d'apt. On avertit sans rien toucher : ces
# fichiers appartiennent à l'administrateur, pas à ce script.
signaler_doublons() {
    local fichier
    local trouves=""

    if [ -d "$REPERTOIRE_CRON" ]; then
        for fichier in "$REPERTOIRE_CRON"/*; do
            [ -f "$fichier" ] || continue
            [ "$fichier" != "$FICHIER_CRON" ] || continue
            if grep -q 'update-system\.sh' "$fichier" 2>/dev/null; then
                trouves="$trouves $fichier"
            fi
        done
    fi

    if [ -f /etc/crontab ] && grep -q 'update-system\.sh' /etc/crontab 2>/dev/null; then
        trouves="$trouves /etc/crontab"
    fi

    if [ -n "$trouves" ]; then
        warn "update-system.sh est déjà planifié ailleurs :$trouves"
        warn "Deux planifications concurrentes se bloqueraient sur le verrou d'apt."
    fi
}

signaler_doublons

# -------------------------------------------------------------------
# Contenu attendu
# -------------------------------------------------------------------
# Le fichier se termine par un retour à la ligne — le heredoc s'en charge :
# cron ignore une dernière ligne qui n'en aurait pas.
fichier_attendu() {
    cat <<CRON
# Tâches planifiées de MGNetworking/script.
# Déposé par Linux/System/configure-cron.sh — ne pas modifier à la main :
# une prochaine exécution du script signalerait la différence.
#
# Format d'une ligne : horaire, UTILISATEUR, commande. C'est le champ
# utilisateur qui remplace sudo — cron n'en utilise pas.

SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

# Mise à jour des paquets.
#   /bin/bash   le script est invoqué par bash plutôt que par son chemin seul :
#               les fichiers du dépôt sont enregistrés dans Git sans bit
#               d'exécution, et un appel direct rendrait 126 à chaque passage.
#   --yes       cron n'a pas de terminal : sans cette option, la confirmation
#               resterait sans réponse et le script attendrait indéfiniment.
#   >/dev/null  la sortie standard est jetée : cron l'expédierait par courriel
#               à chaque exécution. La trace complète est écrite dans
#               $REPERTOIRE_LOGS/update-system.log.
#   La sortie d'erreur n'est PAS redirigée : cron la transmet, et c'est
#   aujourd'hui la seule alerte en cas d'échec.
$HORAIRE root /bin/bash $SCRIPT_PLANIFIE --yes >/dev/null
CRON
}

# -------------------------------------------------------------------
# Résumé
# -------------------------------------------------------------------
info "Fichier     : $FICHIER_CRON"
info "Horaire     : $HORAIRE ($ORIGINE_HORAIRE)"
info "Utilisateur : root"
info "Commande    : /bin/bash $SCRIPT_PLANIFIE --yes"

# -------------------------------------------------------------------
# Permissions et écriture
# -------------------------------------------------------------------
# Cron rejette un fichier de /etc/cron.d qui n'appartient pas à root ou qui
# porte le bit d'exécution. L'état est lu et comparé avant d'être appliqué :
# une seconde exécution ne touche donc à rien.
#
# Les deux lectures sont en CONTEXTE DE CONDITION. Sous la forme nue
# « proprietaire="$(stat …)" », un stat en échec — fichier disparu entre le test
# d'existence et la lecture, stat absent du PATH — fait parler le trap ERR de
# lib/common.sh deux fois : une fois dans le sous-shell de la substitution, une
# fois dans le shell principal pour l'affectation. Deux lignes « Échec (code …)
# à la ligne … », et pas un mot sur la cause.
#
# Le « [ -f "$FICHIER_CRON" ] » qui précède l'appel n'y change rien : il établit
# que le fichier existait à l'instant du test, pas que stat aboutira. C'est la
# garde exacte que lire_taille_actuelle, dans configure-swap.sh, portait déjà
# quand un faux stat en tête de PATH l'a mise en défaut. Même motif, même
# traitement (TASK-018).
appliquer_permissions() {
    local proprietaire mode

    if ! proprietaire="$(stat -c '%U:%G' "$FICHIER_CRON" 2>/dev/null)"; then
        error "Propriétaire de $FICHIER_CRON illisible : « stat » a échoué."
        die "Vérifier que ce fichier est toujours en place, puis relancer."
    fi
    if [ "$proprietaire" != "root:root" ]; then
        if [ "$DRY_RUN" = "true" ]; then
            info "[dry-run] Rendrait $FICHIER_CRON à root:root (actuellement $proprietaire)."
        else
            chown root:root "$FICHIER_CRON"
            info "Propriétaire corrigé : root:root (était $proprietaire)."
        fi
    fi

    if ! mode="$(stat -c '%a' "$FICHIER_CRON" 2>/dev/null)"; then
        error "Mode de $FICHIER_CRON illisible : « stat » a échoué."
        die "Vérifier que ce fichier est toujours en place, puis relancer."
    fi
    if [ "$mode" != "644" ]; then
        if [ "$DRY_RUN" = "true" ]; then
            info "[dry-run] Appliquerait le mode 0644 sur $FICHIER_CRON (actuellement $mode)."
        else
            chmod 0644 "$FICHIER_CRON"
            info "Mode corrigé : 0644 (était $mode)."
        fi
    fi
}

# Le fichier est construit à côté puis renommé : cron parcourt /etc/cron.d à
# chaque minute et pourrait lire un fichier à demi écrit. Le nom temporaire
# comporte des points, ce qui le rend invisible pour cron le temps de sa vie.
#
# La fonction n'est pas morte : elle est appelée par le « trap … EXIT » posé
# juste en dessous. shellcheck ne suit pas les trap et la croit inatteignable —
# d'où la directive, placée au plus près de la fonction pour qu'elle s'y
# rattache.
#
# ELLE REND TOUJOURS 0, et ce n'est pas une négligence. Un trap EXIT qui rend un
# code non nul est, pour bash, une commande en échec de plus : errexit s'en
# saisit et le « trap ERR » de lib/common.sh écrit une ligne supplémentaire.
# Tout « die » postérieur à ce trap s'en trouvait doublé — les quatre lectures de
# stat comme les die préexistants de verifier() :
#
#   [ERROR] Propriétaire de /etc/cron.d/mgnetworking illisible : « stat » a échoué.
#   [ERROR] Vérifier que ce fichier est toujours en place, puis relancer.
#   [ERROR] Échec (code 1) à la ligne 1 de common.sh.
#
# La troisième ligne ne désigne rien : « ligne 1 de common.sh » est l'endroit où
# le trap est défini, pas celui où quoi que ce soit a échoué.
#
# Le code de sortie du script n'en souffre pas. Bash rend le code passé à
# « exit » — celui de die — indépendamment de ce que rend le trap EXIT ; seul un
# « exit » exécuté DANS le trap le remplacerait. L'ancien « return "$code" »
# n'était donc pas ce qui préservait le code de sortie : il ne faisait qu'armer
# le trap ERR.
#
# Le « rm » est pour la même raison placé en condition : son échec, sinon,
# rejouerait la scène. Un temporaire laissé en place est sans danger — son nom
# comporte des points, cron l'ignore — mais il doit être nommé.
# shellcheck disable=SC2317
nettoyer_temporaire() {
    if [ -n "$FICHIER_TEMPORAIRE" ] && [ -e "$FICHIER_TEMPORAIRE" ]; then
        if ! rm -f "$FICHIER_TEMPORAIRE"; then
            warn "Fichier temporaire non supprimé : $FICHIER_TEMPORAIRE"
            warn "Son nom comporte des points, cron l'ignore. Le retirer à la main."
        fi
    fi
    return 0
}
trap nettoyer_temporaire EXIT

ecrire_fichier() {
    FICHIER_TEMPORAIRE="$FICHIER_CRON.tmp.$$"
    fichier_attendu > "$FICHIER_TEMPORAIRE"
    chown root:root "$FICHIER_TEMPORAIRE"
    chmod 0644 "$FICHIER_TEMPORAIRE"
    mv -f "$FICHIER_TEMPORAIRE" "$FICHIER_CRON"
    FICHIER_TEMPORAIRE=""
    success "Fichier écrit : $FICHIER_CRON"
}

# -------------------------------------------------------------------
# Vérification
# -------------------------------------------------------------------
# Contrôle de ce qui est réellement sur le disque, et des deux règles que cron
# applique sans jamais s'en expliquer.
verifier() {
    local proprietaire mode

    [ -f "$FICHIER_CRON" ] || die "$FICHIER_CRON est absent après écriture."

    if ! fichier_attendu | diff -q - "$FICHIER_CRON" >/dev/null 2>&1; then
        die "Le contenu de $FICHIER_CRON ne correspond pas à ce qui était attendu."
    fi

    # Mêmes lectures qu'au-dessus, en condition pour la même raison : le
    # « [ -f ] » posé à l'entrée de cette fonction ne garantit pas davantage que
    # stat aboutira, et une vérification qui échoue doit dire pourquoi plutôt que
    # de rendre deux lignes de trap.
    if ! proprietaire="$(stat -c '%U:%G' "$FICHIER_CRON" 2>/dev/null)"; then
        error "Propriétaire de $FICHIER_CRON illisible après écriture : « stat » a échoué."
        die "Vérifier l'état de ce fichier : cron rejette ce qui n'appartient pas à root."
    fi
    if [ "$proprietaire" != "root:root" ]; then
        die "cron rejette un fichier qui n'appartient pas à root (propriétaire : $proprietaire)."
    fi

    if ! mode="$(stat -c '%a' "$FICHIER_CRON" 2>/dev/null)"; then
        error "Mode de $FICHIER_CRON illisible après écriture : « stat » a échoué."
        die "Vérifier l'état de ce fichier : cron rejette un fichier exécutable."
    fi
    if [ "$mode" != "644" ]; then
        die "Mode inattendu sur $FICHIER_CRON : $mode (attendu 644)."
    fi

    if [ -x "$FICHIER_CRON" ]; then
        die "cron rejette un fichier exécutable : $FICHIER_CRON"
    fi
}

# -------------------------------------------------------------------
# Exécution
# -------------------------------------------------------------------
if [ -f "$FICHIER_CRON" ]; then
    if fichier_attendu | diff -q - "$FICHIER_CRON" >/dev/null 2>&1; then
        info "Le contenu de $FICHIER_CRON est déjà celui attendu."
        appliquer_permissions

        if [ "$DRY_RUN" = "true" ]; then
            info "Mode --dry-run : aucune modification effectuée."
            exit 0
        fi

        verifier
        success "La planification est déjà en place et à jour : $FICHIER_CRON"
        exit 0
    fi

    warn "$FICHIER_CRON existe et diffère du contenu attendu."
    warn "Différences (- attendu, + en place) :"
    fichier_attendu | diff -u - "$FICHIER_CRON" | tail -n +3 >&2 || true

    if [ "$DRY_RUN" = "true" ]; then
        info "[dry-run] Remplacerait $FICHIER_CRON par :"
        fichier_attendu | sed 's/^/    /' >&2
        info "Mode --dry-run : aucune modification effectuée."
        exit 0
    fi

    if ! confirm "Remplacer $FICHIER_CRON ?"; then
        info "Abandon : le fichier en place est conservé."
        exit 0
    fi
elif [ "$DRY_RUN" = "true" ]; then
    info "[dry-run] Créerait $FICHIER_CRON :"
    fichier_attendu | sed 's/^/    /' >&2
    info "Mode --dry-run : aucune modification effectuée."
    exit 0
fi

ecrire_fichier
verifier

success "Planification installée : update-system.sh, « $HORAIRE », en root."
info "Aucun rechargement n'est nécessaire : cron relit $REPERTOIRE_CRON de lui-même."
info "Le passage suivant se lit dans le journal du système (journalctl -u cron,"
info "ou /var/log/syslog selon la journalisation en place)."
