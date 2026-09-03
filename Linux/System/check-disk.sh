#!/usr/bin/env bash
# check-disk.sh — diagnostic de stockage, en lecture seule.
#
# Quatre sections : systèmes de fichiers, inodes, périphériques et partitions,
# répertoires les plus consommateurs.
#
# N'écrit rien, ne modifie rien, ne nécessite aucun privilège. Une information
# manquante devient « non disponible » : le script rend 0 quoi qu'il constate.
# Usage : ./check-disk.sh [--seuil N] [--repertoire CHEMIN] [--top N] [--help]

set -Eeuo pipefail

_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_dir/lib/common.sh" ] && [ "$_dir" != "/" ]; do _dir="$(dirname "$_dir")"; done
source "$_dir/lib/common.sh"

# -------------------------------------------------------------------
# Valeurs par défaut et origine des valeurs
# -------------------------------------------------------------------
# Trois niveaux, du plus faible au plus fort : la valeur écrite ici,
# config/server.env, la ligne de commande. L'origine est conservée pour être
# affichée et pour nommer le fautif dans un diagnostic de valeur invalide.
#
# POURQUOI 85 %. Le seuil s'applique à l'occupation des blocs comme à celle des
# inodes.
#
#   - il laisse de quoi travailler : 15 % d'une racine de 40 Go font 6 Go, de
#     quoi absorber une mise à jour de paquets, une image de conteneur ou une
#     rafale de journaux avant que le disque soit réellement plein ;
#   - la dégradation commence avant le 100 % de « df » : ext4 réserve 5 % des
#     blocs à root — que « df » ne compte pas comme disponibles pour les autres
#     — et son allocateur se fragmente nettement au-delà de ~85 % d'occupation ;
#   - plus bas, le signal devient du bruit. Un serveur sain vit couramment entre
#     70 et 80 % — un disque vide est un disque payé pour rien —, et une alerte
#     qui se déclenche à chaque passage n'est plus lue au bout de trois fois.
#
# Le même seuil vaut pour les inodes, faute d'une raison de les traiter
# autrement : un système de fichiers dont 85 % des inodes sont consommés est
# aussi près de la panne que celui dont 85 % des blocs le sont — et la panne y
# est plus déroutante, « No space left on device » s'affichant alors qu'il reste
# 60 % d'espace libre.
SEUIL_DEFAUT="85"
SEUIL="$SEUIL_DEFAUT"
ORIGINE_SEUIL="valeur par défaut"
if [ -n "${SRV_DISK_SEUIL:-}" ]; then
    SEUIL="$SRV_DISK_SEUIL"
    ORIGINE_SEUIL="config/server.env"
fi

REPERTOIRE="/"
ORIGINE_REPERTOIRE="valeur par défaut"
if [ -n "${SRV_DISK_REPERTOIRE:-}" ]; then
    REPERTOIRE="$SRV_DISK_REPERTOIRE"
    ORIGINE_REPERTOIRE="config/server.env"
fi

# Nombre de sous-répertoires affichés. Volontairement absent de
# config/server.env : c'est un confort d'affichage, pas une donnée de la machine.
TOP="10"
ORIGINE_TOP="valeur par défaut"

TOUS="false"
SANS_REPERTOIRES="false"

# -------------------------------------------------------------------
# Aide
# -------------------------------------------------------------------
show_help() {
    cat <<'AIDE'
Usage : check-disk.sh [options]

Diagnostic de stockage, en quatre sections : occupation des systèmes de
fichiers, occupation des inodes, périphériques et partitions, répertoires les
plus consommateurs.

Script en lecture seule : aucune modification, aucun privilège requis. Une
commande absente ou en échec produit un avertissement et « non disponible »,
jamais un arrêt. Un seuil dépassé ne change pas non plus le code de retour :
ce script constate, il ne juge pas.

Options :
      --seuil <1-100>       Seuil d'alerte, en pourcentage d'occupation. Tout
                            système de fichiers dont l'occupation — blocs ou
                            inodes — atteint ce seuil est signalé par un [WARN].
                            Défaut : 85, ou SRV_DISK_SEUIL de config/server.env.
      --repertoire <chemin> Répertoire dont l'occupation par sous-répertoire est
                            analysée, à la profondeur 1 et sans franchir les
                            points de montage.
                            Défaut : /, ou SRV_DISK_REPERTOIRE de
                            config/server.env.
      --top <1-100>         Nombre de sous-répertoires affichés. Défaut : 10.
      --sans-repertoires    Sauter la section des répertoires consommateurs,
                            dont le coût croît avec la taille de l'arborescence.
      --tous                Ne pas écarter les pseudo-systèmes de fichiers
                            (tmpfs, devtmpfs, squashfs, proc…), filtrés par
                            défaut. « overlay » n'est jamais écarté : c'est le
                            seul système de fichiers de la racine d'un conteneur.
  -h, --help                Afficher cette aide

La ligne de commande prime sur config/server.env, qui prime sur les valeurs
par défaut écrites dans le script. L'origine de chaque valeur est rappelée en
tête de la sortie.

Codes de retour :
  0  diagnostic produit — y compris lorsqu'un seuil est dépassé, qu'une
     information manque ou qu'une valeur de config/server.env est refusée
  2  erreur d'usage sur la LIGNE DE COMMANDE : option inconnue, valeur de
     --seuil, --top ou --repertoire invalide

Une valeur fautive venue de config/server.env ne rend jamais 2 : la ligne de
commande étant juste, elle vaut un [WARN] nommant la variable, la valeur
refusée et ce qui est retenu à la place — le seuil par défaut pour
SRV_DISK_SEUIL, la section des répertoires sautée pour SRV_DISK_REPERTOIRE.

Aucun échec d'exécution (code 1) n'est prévu : ce script n'exige aucune
dépendance et ne modifie rien.
AIDE
}

# -------------------------------------------------------------------
# Arguments
# -------------------------------------------------------------------
while [ "${1:-}" != "" ]; do
    case "$1" in
        --seuil)
            shift
            [ -n "${1:-}" ] || die "--seuil attend un entier de 1 à 100." 2
            SEUIL="$1"; ORIGINE_SEUIL="ligne de commande"; shift ;;
        --repertoire)
            shift
            [ -n "${1:-}" ] || die "--repertoire attend un chemin." 2
            REPERTOIRE="$1"; ORIGINE_REPERTOIRE="ligne de commande"; shift ;;
        --top)
            shift
            [ -n "${1:-}" ] || die "--top attend un entier de 1 à 100." 2
            TOP="$1"; ORIGINE_TOP="ligne de commande"; shift ;;
        --tous)             TOUS="true"; shift ;;
        --sans-repertoires) SANS_REPERTOIRES="true"; shift ;;
        -h|--help)          show_help; exit 0 ;;
        *)                  die "Option inconnue : $1" 2 ;;
    esac
done

# -------------------------------------------------------------------
# Préflight
# -------------------------------------------------------------------
# Ni privilège, ni distribution, ni dépendance à exiger : ce script lit ce qu'il
# trouve et dégrade le reste. Le préflight se réduit donc à la validation des
# valeurs, faite avant toute lecture pour qu'une ligne de commande fautive soit
# reprochée avant qu'un seul chiffre ne soit affiché.
#
# UNE SEULE RÈGLE, POUR TOUTES LES VALEURS. Le traitement d'une valeur fautive
# dépend de son ORIGINE, jamais de la valeur elle-même, et c'est la convention
# des codes de retour du dépôt qui le dicte : le 2 reproche quelque chose à
# l'appelant.
#
#   - tapée sur la ligne de commande, elle vaut un refus en 2. L'appelant s'est
#     trompé en tapant, et le reproche lui est utile ;
#   - héritée de config/server.env, elle ne reproche rien à la commande tapée.
#     Un diagnostic en lecture seule doit diagnostiquer : priver l'appelant de
#     tout son tableau de disques parce qu'une variable qu'il n'a peut-être pas
#     écrite lui-même est mal saisie serait disproportionné. Elle vaut donc un
#     [WARN] qui nomme la variable, la valeur refusée et ce qui est retenu à la
#     place, puis le diagnostic se poursuit.
#
# Ce qui est « retenu à la place » diffère d'une valeur à l'autre, et c'est le
# seul écart : le seuil retombe sur sa valeur par défaut, qui reste une
# comparaison utile ; le répertoire, lui, ne retombe PAS sur « / » — ce serait
# parcourir des minutes durant une arborescence que personne n'a demandée, et
# afficher le classement d'un autre répertoire que celui configuré. Sa section
# est sautée.

# Entier de 1 à 100, sans zéro initial. Les deux « case » distinguent les deux
# reproches — pas un entier, hors bornes — et n'utilisent aucune arithmétique :
# « 010 » y serait lu en octal, et une valeur de trente chiffres déborderait.
#
# La fonction NE MEURT PAS : elle rend 1 et renseigne le motif du refus. C'est
# à l'appelante de trancher entre le refus et le repli, selon l'origine de la
# valeur — un « die » posé ici lui ôterait ce choix.
MOTIF_INVALIDE=""
PRECISION_INVALIDE=""
valider_entier() {
    local valeur="$1"

    MOTIF_INVALIDE=""
    PRECISION_INVALIDE=""
    case "$valeur" in
        ''|*[!0-9]*)
            MOTIF_INVALIDE="n'est pas un entier"
            return 1 ;;
    esac
    case "$valeur" in
        [1-9]|[1-9][0-9]|100) return 0 ;;
    esac
    MOTIF_INVALIDE="est hors bornes"
    PRECISION_INVALIDE=" — attendu un entier de 1 à 100, sans zéro initial"
    return 1
}

if ! valider_entier "$SEUIL"; then
    if [ "$ORIGINE_SEUIL" = "ligne de commande" ]; then
        die "--seuil : « $SEUIL » $MOTIF_INVALIDE ($ORIGINE_SEUIL)$PRECISION_INVALIDE." 2
    fi
    warn "« $SEUIL » ($ORIGINE_SEUIL, SRV_DISK_SEUIL) $MOTIF_INVALIDE$PRECISION_INVALIDE :"
    warn "repli sur le seuil par défaut, $SEUIL_DEFAUT %."
    SEUIL="$SEUIL_DEFAUT"
    ORIGINE_SEUIL="valeur par défaut, SRV_DISK_SEUIL refusé"
fi

# --top ne se surcharge pas par config/server.env : son origine est toujours la
# ligne de commande, ou la valeur par défaut écrite plus haut — valide par
# construction. Il n'y a donc rien à replier ici.
if ! valider_entier "$TOP"; then
    die "--top : « $TOP » $MOTIF_INVALIDE ($ORIGINE_TOP)$PRECISION_INVALIDE." 2
fi

# Une valeur commençant par un tiret est une option du script, pas un chemin :
# « --repertoire --tous » ferait autrement de « --tous » le répertoire analysé,
# et l'option demandée serait perdue en silence. Ce piège-là n'existe que sur la
# ligne de commande ; venu de config/server.env, un tel chemin n'est qu'un chemin
# introuvable de plus, et le contrôle suivant s'en charge — sans rendre 2, la
# règle ci-dessus valant pour lui comme pour les autres.
if [ "$ORIGINE_REPERTOIRE" = "ligne de commande" ]; then
    case "$REPERTOIRE" in
        -*) die "--repertoire : « $REPERTOIRE » commence par un tiret ($ORIGINE_REPERTOIRE) — c'est une option, pas un chemin." 2 ;;
    esac
fi

# Le cas d'un chemin inutilisable hérité de la configuration : un répertoire
# devenu non traversable pour un compte ordinaire, /var/lib/docker par exemple,
# ne doit pas priver ce compte de tout le reste du diagnostic.
REPERTOIRE_UTILISABLE="oui"
if [ ! -d "$REPERTOIRE" ]; then
    if [ "$ORIGINE_REPERTOIRE" = "ligne de commande" ]; then
        die "--repertoire : « $REPERTOIRE » n'est pas un répertoire, ou n'est pas accessible." 2
    fi
    warn "« $REPERTOIRE » ($ORIGINE_REPERTOIRE) n'est pas un répertoire, ou n'est pas accessible :"
    warn "la section des répertoires consommateurs est sautée."
    REPERTOIRE_UTILISABLE="non"
fi

# -------------------------------------------------------------------
# Filtre des systèmes de fichiers
# -------------------------------------------------------------------
# Les pseudo-systèmes n'ont rien à dire sur le stockage : leur occupation est
# celle de la mémoire, et les images de paquets snap sont montées en lecture
# seule à 100 %.
#
# « overlay » n'est PAS de la liste, et c'est délibéré : c'est le système de
# fichiers de la racine d'un conteneur. L'écarter afficherait un tableau vide
# dans un conteneur, et rendrait le script inutile sur un hôte de conteneurs.
TYPES_PSEUDO=(
    tmpfs devtmpfs devpts proc sysfs squashfs cgroup cgroup2 ramfs debugfs
    tracefs securityfs pstore bpf configfs fusectl mqueue hugetlbfs autofs
    binfmt_misc efivarfs nsfs
)

ARGS_DF=()
LIBELLE_FILTRE="pseudo-systèmes écartés, overlay conservé"
if [ "$TOUS" = "true" ]; then
    LIBELLE_FILTRE="aucun — tous les systèmes de fichiers (--tous)"
else
    for _type in "${TYPES_PSEUDO[@]}"; do
        ARGS_DF+=(-x "$_type")
    done
fi

# -------------------------------------------------------------------
# Présentation
# -------------------------------------------------------------------
# Trois fonctions reprises de system-info.sh, dont ce script est le modèle de
# mise en page : même titre, même ligne « libellé : valeur », même cellule.

# Titre de section
titre() {
    printf '\n%s\n' "$1"
    printf '%s\n' "------------------------------------------------------------"
}

# Ligne « libellé : valeur ». Une valeur vide devient « non disponible ».
#
# Le remplissage est calculé sur le nombre de caractères et non d'octets :
# « %-22s » de printf compte les octets, ce qui décale les libellés accentués.
ligne() {
    local libelle="$1"
    local valeur="${2:-non disponible}"
    local remplissage=$(( 23 - ${#libelle} ))

    if [ "$remplissage" -lt 1 ]; then
        remplissage=1
    fi
    printf '  %s%*s%s\n' "$libelle" "$remplissage" "" "$valeur"
}

# Cellule de largeur fixe, comptée en caractères.
# Usage : cellule <texte> <largeur> <gauche|droite>
cellule() {
    local texte="$1" largeur="$2" cote="$3"
    local remplissage=$(( largeur - ${#texte} ))

    if [ "$remplissage" -lt 0 ]; then
        remplissage=0
    fi
    if [ "$cote" = "droite" ]; then
        printf '%*s%s' "$remplissage" "" "$texte"
    else
        printf '%s%*s' "$texte" "$remplissage" ""
    fi
}

# En-tête commun aux deux tableaux d'occupation.
entete_occupation() {
    printf '  %s%s%s%s%s%s\n' \
        "$(cellule "Monté sur" 24 gauche)" \
        "$(cellule "Type" 9 gauche)" \
        "$(cellule "$1" 9 droite)" \
        "$(cellule "$2" 9 droite)" \
        "$(cellule "$3" 9 droite)" \
        "$(cellule "Occup." 7 droite)"
}

# Un pourcentage de « df » — « 87% », ou « - » quand il n'est pas déclaré.
# Renseigne POURCENTAGE_NUMERIQUE : la valeur sans « % », ou vide.
POURCENTAGE_NUMERIQUE=""
lire_pourcentage() {
    POURCENTAGE_NUMERIQUE="${1%\%}"
    case "$POURCENTAGE_NUMERIQUE" in
        ''|*[!0-9]*) POURCENTAGE_NUMERIQUE="" ;;
    esac
}

# -------------------------------------------------------------------
# Sections
# -------------------------------------------------------------------

section_parametres() {
    titre "Diagnostic de stockage"
    ligne "Seuil d'alerte" "$SEUIL % ($ORIGINE_SEUIL)"
    ligne "Filtre" "$LIBELLE_FILTRE"

    if [ "$SANS_REPERTOIRES" = "true" ]; then
        ligne "Répertoire analysé" "aucun (--sans-repertoires)"
    else
        ligne "Répertoire analysé" "$REPERTOIRE ($ORIGINE_REPERTOIRE)"
        ligne "Entrées affichées" "$TOP ($ORIGINE_TOP)"
    fi
}

section_systemes_de_fichiers() {
    titre "Systèmes de fichiers"

    if ! command -v df >/dev/null 2>&1; then
        warn "« df » est introuvable : occupation des systèmes de fichiers non disponible."
        ligne "Occupation" ""
        return 0
    fi

    # Affectation en CONTEXTE DE CONDITION (TASK-018) : sous la forme nue, un
    # « df » en échec fait échouer l'affectation, et le trap ERR de
    # lib/common.sh parle deux fois sans nommer la cause. En condition, ni
    # errexit ni le trap n'ont prise.
    #
    # L'échec n'est pas fatal, et il n'est pas toujours total : « df » rend 1
    # dès qu'un seul point de montage lui résiste, après avoir écrit toutes les
    # lignes qu'il a pu produire. La substitution affecte cette sortie partielle
    # quel que soit le code — c'est le vide, et non le code, qui décide ici du
    # « non disponible ».
    local sortie="" partiel="non"
    if ! sortie="$(df -P -T -h "${ARGS_DF[@]}" 2>/dev/null)"; then
        partiel="oui"
    fi

    if [ -z "$sortie" ]; then
        warn "« df » a échoué : occupation des systèmes de fichiers non disponible."
        ligne "Occupation" ""
        return 0
    fi
    if [ "$partiel" = "oui" ]; then
        warn "« df » n'a pas pu interroger tous les points de montage : le tableau ci-dessous est partiel."
    fi

    entete_occupation "Taille" "Utilisé" "Libre"

    local premiere="oui" affichees=0
    local enregistrement peripherique type_fs taille utilise libre pourcentage montage
    local depassements=()

    while IFS= read -r enregistrement; do
        # La première ligne est l'en-tête de « df ». Elle est écartée par sa
        # position et non par son texte : il est traduit selon la locale.
        if [ "$premiere" = "oui" ]; then
            premiere="non"
            continue
        fi
        [ -n "$enregistrement" ] || continue

        # « -P » garantit un enregistrement par ligne et sept champs, le point de
        # montage en dernier — d'où sa lecture dans la dernière variable, qui
        # récupère aussi les espaces qu'il contiendrait.
        read -r peripherique type_fs taille utilise libre pourcentage montage <<< "$enregistrement"
        [ -n "$montage" ] || continue
        affichees=$(( affichees + 1 ))

        printf '  %s%s%s%s%s%s\n' \
            "$(cellule "$montage" 24 gauche)" \
            "$(cellule "$type_fs" 9 gauche)" \
            "$(cellule "$taille" 9 droite)" \
            "$(cellule "$utilise" 9 droite)" \
            "$(cellule "$libre" 9 droite)" \
            "$(cellule "$pourcentage" 7 droite)"

        lire_pourcentage "$pourcentage"
        if [ -n "$POURCENTAGE_NUMERIQUE" ] && [ "$POURCENTAGE_NUMERIQUE" -ge "$SEUIL" ]; then
            depassements+=("$montage ($peripherique) : $POURCENTAGE_NUMERIQUE % occupés")
        fi
    done <<< "$sortie"

    if [ "$affichees" -eq 0 ]; then
        ligne "Occupation" "aucun système de fichiers retenu par le filtre"
        return 0
    fi

    # Les avertissements sont émis après le tableau, et non pendant : ils partent
    # sur stderr quand le tableau part sur stdout, et s'y intercaleraient.
    local depassement
    for depassement in "${depassements[@]}"; do
        warn "Seuil de $SEUIL % atteint — $depassement"
    done
}

section_inodes() {
    titre "Inodes"

    if ! command -v df >/dev/null 2>&1; then
        warn "« df » est introuvable : occupation des inodes non disponible."
        ligne "Occupation" ""
        return 0
    fi

    local sortie="" partiel="non"
    if ! sortie="$(df -P -T -i -h "${ARGS_DF[@]}" 2>/dev/null)"; then
        partiel="oui"
    fi

    if [ -z "$sortie" ]; then
        warn "« df -i » a échoué : occupation des inodes non disponible."
        ligne "Occupation" ""
        return 0
    fi
    if [ "$partiel" = "oui" ]; then
        warn "« df -i » n'a pas pu interroger tous les points de montage : le tableau ci-dessous est partiel."
    fi

    entete_occupation "Total" "Utilisés" "Libres"

    local premiere="oui" affichees=0
    local enregistrement peripherique type_fs total utilises libres pourcentage montage
    local depassements=()

    while IFS= read -r enregistrement; do
        if [ "$premiere" = "oui" ]; then
            premiere="non"
            continue
        fi
        [ -n "$enregistrement" ] || continue

        read -r peripherique type_fs total utilises libres pourcentage montage <<< "$enregistrement"
        [ -n "$montage" ] || continue
        affichees=$(( affichees + 1 ))

        lire_pourcentage "$pourcentage"

        # btrfs, ZFS et certains overlay ne déclarent pas d'inodes : « df » écrit
        # alors « - », ou un total nul. Afficher un pourcentage calculé là-dessus
        # donnerait un chiffre faux — 0 %, ou 100 % — sur un système de fichiers
        # qui, par construction, ne peut pas en manquer.
        if [ "$total" = "-" ] || [ "$total" = "0" ] || [ -z "$POURCENTAGE_NUMERIQUE" ]; then
            printf '  %s%s%s\n' \
                "$(cellule "$montage" 24 gauche)" \
                "$(cellule "$type_fs" 9 gauche)" \
                "non disponible (ce système de fichiers ne déclare pas d'inodes)"
            continue
        fi

        printf '  %s%s%s%s%s%s\n' \
            "$(cellule "$montage" 24 gauche)" \
            "$(cellule "$type_fs" 9 gauche)" \
            "$(cellule "$total" 9 droite)" \
            "$(cellule "$utilises" 9 droite)" \
            "$(cellule "$libres" 9 droite)" \
            "$(cellule "$pourcentage" 7 droite)"

        if [ "$POURCENTAGE_NUMERIQUE" -ge "$SEUIL" ]; then
            depassements+=("$montage ($peripherique) : $POURCENTAGE_NUMERIQUE % des inodes consommés")
        fi
    done <<< "$sortie"

    if [ "$affichees" -eq 0 ]; then
        ligne "Occupation" "aucun système de fichiers retenu par le filtre"
        return 0
    fi

    local depassement
    for depassement in "${depassements[@]}"; do
        warn "Seuil de $SEUIL % atteint — $depassement"
    done
}

section_peripheriques() {
    titre "Périphériques et partitions"

    local sortie=""
    if command -v lsblk >/dev/null 2>&1; then
        # MOUNTPOINT — au singulier — est reconnu par toutes les versions
        # d'util-linux des distributions cibles ; MOUNTPOINTS ne l'est que
        # depuis la 2.37.
        if ! sortie="$(lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT 2>/dev/null)"; then
            warn "« lsblk » a échoué : repli sur /proc/partitions."
            sortie=""
        fi
    else
        warn "« lsblk » est introuvable : repli sur /proc/partitions."
    fi

    # Une sortie réduite à son en-tête vaut une sortie vide : c'est le cas d'un
    # conteneur qui ne voit aucun périphérique bloc. Le repli est tenté sans
    # avertissement — rien n'a échoué.
    local enregistrement lignes=0
    while IFS= read -r enregistrement; do
        [ -n "$enregistrement" ] || continue
        lignes=$(( lignes + 1 ))
    done <<< "$sortie"

    if [ "$lignes" -gt 1 ]; then
        while IFS= read -r enregistrement; do
            printf '  %s\n' "$enregistrement"
        done <<< "$sortie"
        return 0
    fi

    if [ ! -r /proc/partitions ]; then
        warn "/proc/partitions est illisible : périphériques et partitions non disponibles."
        ligne "Périphériques" ""
        return 0
    fi

    # Les tailles de /proc/partitions sont en blocs de 1 Kio.
    #
    # « lue » sépare deux issues que la table vide, à elle seule, confond : un
    # « awk » en échec est une IGNORANCE — la table n'a pas pu être lue —, une
    # table vide après une lecture réussie est un CONSTAT. Les faire aboutir au
    # même « aucun périphérique bloc visible » revenait à affirmer une absence
    # qu'on n'avait pas établie, et à contredire le [WARN] émis juste au-dessus.
    local table="" lue="oui"
    if ! table="$(awk 'NR > 2 && NF >= 4 {
            ko = $3
            if (ko >= 1048576) { t = sprintf("%.1f Go", ko / 1048576) }
            else               { t = sprintf("%.0f Mo", ko / 1024) }
            printf "  %-16s%12s\n", $4, t
        }' /proc/partitions)"; then
        warn "« awk » a échoué sur /proc/partitions : périphériques et partitions non disponibles."
        lue="non"
    fi

    # « non disponible » quand on n'a pas pu lire — même mot que partout ailleurs
    # dans ce script pour une information hors d'atteinte.
    if [ "$lue" = "non" ]; then
        ligne "Périphériques" ""
        return 0
    fi
    if [ -z "$table" ]; then
        ligne "Périphériques" "aucun périphérique bloc visible"
        return 0
    fi

    printf '  %s%s\n' "$(cellule "Nom" 16 gauche)" "$(cellule "Taille" 12 droite)"
    printf '%s\n' "$table"
}

section_repertoires() {
    titre "Répertoires les plus consommateurs"

    if [ "$SANS_REPERTOIRES" = "true" ]; then
        ligne "Analyse" "désactivée (--sans-repertoires)"
        return 0
    fi
    if [ "$REPERTOIRE_UTILISABLE" != "oui" ]; then
        ligne "Analyse" ""
        return 0
    fi
    if ! command -v du >/dev/null 2>&1; then
        warn "« du » est introuvable : répertoires consommateurs non disponibles."
        ligne "Analyse" ""
        return 0
    fi

    # L'analyse est bornée par trois choix, tous contournables : le répertoire de
    # départ, « -x » qui interdit de franchir un point de montage, et la
    # profondeur 1. Sans eux, un « du » sur une racine de plusieurs téraoctets
    # occuperait le terminal pendant des minutes.
    info "Analyse de « $REPERTOIRE » en cours (sans franchir les points de montage)…"

    # Comme pour « df » : « du » rend 1 dès qu'un sous-répertoire lui résiste —
    # cas ordinaire d'une exécution sans privilège sur « / » — après avoir écrit
    # tous les totaux qu'il a pu calculer. Cette sortie-là est exploitable, et
    # la jeter au motif du code de retour priverait un compte ordinaire de toute
    # la section.
    local sortie="" partiel="non"
    if ! sortie="$(du -x -h --max-depth=1 -- "$REPERTOIRE" 2>/dev/null)"; then
        partiel="oui"
    fi

    if [ -z "$sortie" ]; then
        warn "« du » n'a rien pu lire sous « $REPERTOIRE » : répertoires consommateurs non disponibles."
        ligne "Analyse" ""
        return 0
    fi
    if [ "$partiel" = "oui" ]; then
        warn "« du » n'a pas pu lire tous les sous-répertoires de « $REPERTOIRE » (droits insuffisants, ou arborescence modifiée pendant la lecture) : les totaux ci-dessous sont partiels."
    fi

    # « du -h » écrit « taille<TAB>chemin ». Le total du répertoire de départ est
    # la ligne dont le chemin est ce répertoire lui-même ; elle est extraite ici
    # et retirée du classement, où elle occuperait sinon la première place.
    local total=""
    if ! total="$(printf '%s\n' "$sortie" \
            | awk -F'\t' -v racine="$REPERTOIRE" '$2 == racine { valeur = $1 } END { print valeur }')"; then
        warn "« awk » a échoué : total de « $REPERTOIRE » non disponible."
        total=""
    fi

    # « sort -h » comprend les suffixes de « du -h ». Le nombre d'entrées est
    # borné par awk et non par « head » : head refermerait le tuyau avant la fin
    # de sort, dont le SIGPIPE ferait échouer le pipeline sous « pipefail ».
    local classement=""
    if ! classement="$(printf '%s\n' "$sortie" \
            | awk -F'\t' -v racine="$REPERTOIRE" 'NF == 2 && $2 != racine' \
            | sort -h -r \
            | awk -v n="$TOP" 'NR <= n')"; then
        warn "Classement des répertoires non disponible : « awk » ou « sort » a échoué."
        classement=""
    fi

    ligne "Répertoire" "$REPERTOIRE"
    ligne "Total (ce montage)" "$total"

    if [ -z "$classement" ]; then
        ligne "Sous-répertoires" "aucun"
        return 0
    fi

    printf '\n'
    printf '  %s  %s\n' "$(cellule "Taille" 10 droite)" "Répertoire"

    local taille chemin
    while IFS=$'\t' read -r taille chemin; do
        [ -n "$chemin" ] || continue
        printf '  %s  %s\n' "$(cellule "$taille" 10 droite)" "$chemin"
    done <<< "$classement"
}

# -------------------------------------------------------------------
# Exécution
# -------------------------------------------------------------------
section_parametres
section_systemes_de_fichiers
section_inodes
section_peripheriques
section_repertoires
printf '\n'

# Un seuil dépassé ne change pas le code de retour : ce script est une lecture,
# pas un verdict. Le rendre non nul ferait échouer chaque passage en tâche
# planifiée sur un disque simplement bien rempli.
exit 0
