#!/usr/bin/env bash
# configure-hostname.sh — définit le nom d'hôte du serveur.
#
# Met également à jour /etc/hosts : sur Debian et Ubuntu, le nom d'hôte doit y
# être résolvable, faute de quoi sudo et de nombreux services subissent une
# temporisation de résolution à chaque appel.
#
# Idempotent : relançable sans effet de bord.

set -Eeuo pipefail

_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_dir/lib/common.sh" ] && [ "$_dir" != "/" ]; do _dir="$(dirname "$_dir")"; done
source "$_dir/lib/common.sh"

DRY_RUN="false"
NOUVEAU_NOM=""

# Adresse de bouclage dédiée au nom d'hôte sur Debian et Ubuntu.
# 127.0.0.1 reste réservée à « localhost ».
ADRESSE_HOTE="127.0.1.1"

# -------------------------------------------------------------------
# Aide
# -------------------------------------------------------------------
show_help() {
    cat <<'AIDE'
Usage : configure-hostname.sh [nom] [options]

Définit le nom d'hôte du serveur et met /etc/hosts en cohérence.

Le nom est pris dans cet ordre :
  1. l'argument de la ligne de commande ;
  2. SRV_HOSTNAME dans config/server.env.

Il est validé avant toute modification : lettres, chiffres et tirets, un tiret
ne pouvant ni commencer ni terminer un segment. Les noms pleinement qualifiés
(serveur.domaine.tld) sont acceptés.

/etc/hosts est sauvegardé avant modification.

Exemples :
  configure-hostname.sh                            # SRV_HOSTNAME
  configure-hostname.sh mon-serveur
  configure-hostname.sh mon-serveur.exemple.fr --dry-run

Options :
      --dry-run   Afficher les changements sans les appliquer.
  -y, --yes       Ne pas demander de confirmation.
  -h, --help      Afficher cette aide

Attention : sur un nœud K3s ou Kubernetes, le nom d'hôte identifie le nœud dans
le cluster. Le changer après installation rend le nœud existant inutilisable.
AIDE
}

while [ "${1:-}" != "" ]; do
    case "$1" in
        --dry-run)  DRY_RUN="true"; shift ;;
        -y|--yes)   ASSUME_YES="true"; shift ;;
        -h|--help)  show_help; exit 0 ;;
        -*)         die "Option inconnue : $1" 2 ;;
        *)
            if [ -n "$NOUVEAU_NOM" ]; then
                die "Un seul nom d'hôte attendu (reçu « $NOUVEAU_NOM » puis « $1 »)." 2
            fi
            NOUVEAU_NOM="$1"
            shift
            ;;
    esac
done

# Ligne de commande d'abord, config/server.env à défaut.
ORIGINE_NOM="argument"
if [ -z "$NOUVEAU_NOM" ]; then
    NOUVEAU_NOM="${SRV_HOSTNAME:-}"
    ORIGINE_NOM="config/server.env"
fi

if [ -z "$NOUVEAU_NOM" ]; then
    error "Nom d'hôte manquant."
    error "Le passer en argument, ou définir SRV_HOSTNAME dans config/server.env."
    show_help >&2
    exit 2
fi

# -------------------------------------------------------------------
# Validation du nom
# -------------------------------------------------------------------
# Un nom invalide accepté ici se paierait par des services qui refusent de
# démarrer : la validation précède donc toute modification.
valider_nom() {
    local nom="$1"

    if [ "${#nom}" -gt 253 ]; then
        die "Nom trop long : ${#nom} caractères (253 au maximum)."
    fi

    local segment
    local IFS='.'
    for segment in $nom; do
        if [ -z "$segment" ]; then
            die "Nom invalide : segment vide (point en trop dans « $nom »)."
        fi
        if [ "${#segment}" -gt 63 ]; then
            die "Segment trop long : « $segment » (63 caractères au maximum)."
        fi
        case "$segment" in
            -*|*-)      die "Segment invalide : « $segment » commence ou finit par un tiret." ;;
            *[!a-zA-Z0-9-]*) die "Segment invalide : « $segment » — lettres, chiffres et tirets uniquement." ;;
        esac
    done
}

valider_nom "$NOUVEAU_NOM"

# -------------------------------------------------------------------
# Préflight
# -------------------------------------------------------------------
require_root
require_cmd hostname

NOM_ACTUEL="$(hostname)"
# Le nom court sert dans /etc/hosts, aux côtés du nom complet.
NOM_COURT="${NOUVEAU_NOM%%.*}"

info "Nom d'hôte actuel  : $NOM_ACTUEL"
info "Nom d'hôte demandé : $NOUVEAU_NOM ($ORIGINE_NOM)"

# -------------------------------------------------------------------
# Ligne /etc/hosts attendue
# -------------------------------------------------------------------
if [ "$NOM_COURT" = "$NOUVEAU_NOM" ]; then
    LIGNE_HOTE="$ADRESSE_HOTE	$NOUVEAU_NOM"
else
    # Nom pleinement qualifié : le complet d'abord, l'alias court ensuite.
    LIGNE_HOTE="$ADRESSE_HOTE	$NOUVEAU_NOM	$NOM_COURT"
fi

LIGNE_EXISTANTE="$(grep -E "^[[:space:]]*$ADRESSE_HOTE[[:space:]]" /etc/hosts || true)"

# La ligne existante suffit dès lors qu'elle mentionne déjà le nom demandé, que
# ce soit comme nom principal ou comme alias. La réécrire à l'identique du
# modèle ferait perdre les alias déjà en place — un « serveur.localdomain »
# posé par l'installateur, par exemple.
hosts_deja_conforme() {
    if [ -z "$LIGNE_EXISTANTE" ]; then
        return 1
    fi
    local champ
    for champ in $LIGNE_EXISTANTE; do
        if [ "$champ" = "$NOUVEAU_NOM" ]; then
            return 0
        fi
    done
    return 1
}

# -------------------------------------------------------------------
# Résumé des changements
# -------------------------------------------------------------------
CHANGEMENT_NOM="false"
CHANGEMENT_HOSTS="false"

if [ "$NOM_ACTUEL" != "$NOUVEAU_NOM" ]; then
    CHANGEMENT_NOM="true"
fi
if ! hosts_deja_conforme; then
    CHANGEMENT_HOSTS="true"
fi

if [ "$CHANGEMENT_NOM" = "false" ] && [ "$CHANGEMENT_HOSTS" = "false" ]; then
    success "Rien à faire : le nom d'hôte et /etc/hosts sont déjà conformes."
    exit 0
fi

info "Changements à appliquer :"
if [ "$CHANGEMENT_NOM" = "true" ]; then
    printf '    nom d'\''hôte : %s -> %s\n' "$NOM_ACTUEL" "$NOUVEAU_NOM" >&2
fi
if [ "$CHANGEMENT_HOSTS" = "true" ]; then
    if [ -n "$LIGNE_EXISTANTE" ]; then
        printf '    /etc/hosts  : %s\n' "$LIGNE_EXISTANTE" >&2
        printf '              -> %s\n' "$LIGNE_HOTE" >&2
    else
        printf '    /etc/hosts  : ajout de « %s »\n' "$LIGNE_HOTE" >&2
    fi
fi

if [ "$DRY_RUN" = "true" ]; then
    info "Mode --dry-run : aucune modification effectuée."
    exit 0
fi

if ! confirm "Appliquer ces changements ?"; then
    info "Abandon à la demande de l'utilisateur."
    exit 0
fi

# -------------------------------------------------------------------
# Nom d'hôte
# -------------------------------------------------------------------
if [ "$CHANGEMENT_NOM" = "true" ]; then
    if command -v hostnamectl >/dev/null 2>&1 && hostnamectl set-hostname "$NOUVEAU_NOM" 2>/dev/null; then
        info "Nom d'hôte défini via hostnamectl."
    else
        # Repli pour les systèmes sans systemd, ou lorsque hostnamectl échoue
        # faute de bus (conteneur, chroot).
        hostname "$NOUVEAU_NOM"
        printf '%s\n' "$NOUVEAU_NOM" > /etc/hostname
        info "Nom d'hôte défini via hostname et /etc/hostname."
    fi
fi

# -------------------------------------------------------------------
# /etc/hosts
# -------------------------------------------------------------------
if [ "$CHANGEMENT_HOSTS" = "true" ]; then
    # Deux exécutions dans la même seconde produiraient le même nom : la
    # seconde sauvegarde écraserait la première, et l'état d'origine serait
    # perdu. Un suffixe numérique est ajouté tant que le nom est pris.
    base="/etc/hosts.bak-$(date '+%Y%m%d-%H%M%S')"
    sauvegarde="$base"
    suffixe=1
    while [ -e "$sauvegarde" ]; do
        sauvegarde="$base-$suffixe"
        suffixe=$(( suffixe + 1 ))
    done

    cp -p /etc/hosts "$sauvegarde"
    info "Sauvegarde : $sauvegarde"

    # Réécriture ligne à ligne plutôt qu'un ajout en fin de fichier : la ligne
    # 127.0.1.1 doit rester unique, sinon la résolution devient imprévisible.
    temporaire="$(mktemp)"
    if [ -n "$LIGNE_EXISTANTE" ]; then
        awk -v adresse="$ADRESSE_HOTE" -v remplacement="$LIGNE_HOTE" '
            $1 == adresse && !remplace { print remplacement; remplace = 1; next }
            $1 == adresse { next }
            { print }
        ' /etc/hosts > "$temporaire"
    else
        # Insertion juste après la ligne localhost, à sa place habituelle.
        awk -v remplacement="$LIGNE_HOTE" '
            { print }
            $1 == "127.0.0.1" && !insere { print remplacement; insere = 1 }
        ' /etc/hosts > "$temporaire"

        if ! grep -qF "$LIGNE_HOTE" "$temporaire"; then
            printf '%s\n' "$LIGNE_HOTE" >> "$temporaire"
        fi
    fi

    cat "$temporaire" > /etc/hosts
    rm -f "$temporaire"
    success "/etc/hosts mis à jour."
fi

# -------------------------------------------------------------------
# Vérification
# -------------------------------------------------------------------
nom_verifie="$(hostname)"
if [ "$nom_verifie" != "$NOUVEAU_NOM" ]; then
    warn "Le nom d'hôte courant est « $nom_verifie » et non « $NOUVEAU_NOM »."
    warn "Certains systèmes ne l'appliquent qu'après redémarrage."
fi

info "Ligne /etc/hosts : $(grep -E "^[[:space:]]*$ADRESSE_HOTE[[:space:]]" /etc/hosts || echo 'absente')"
success "Nom d'hôte configuré : $NOUVEAU_NOM"
