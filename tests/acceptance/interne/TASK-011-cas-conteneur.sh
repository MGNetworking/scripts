#!/usr/bin/env bash
# tests/acceptance/interne/TASK-011-cas-conteneur.sh — cas exécutés DANS le conteneur.
#
# Ce fichier n'est jamais lancé directement : tests/acceptance/TASK-011-*.sh
# l'invoque, groupe par groupe, à travers tests/env/run-in-container.sh. Chaque
# groupe part donc d'un conteneur neuf — condition sans laquelle une preuve
# d'idempotence ne vaut rien.
#
# Il se trouve dans interne/ et non à la racine de tests/acceptance/ pour que
# run-acceptance.sh, qui cherche « TASK-*.sh » en maxdepth 1, ne l'exécute pas
# sur l'hôte Windows, où aucun de ces scripts ne peut tourner.
#
# Protocole de sortie, sur stdout, une ligne par vérification :
#
#   RESULTAT|PASS|libellé
#   RESULTAT|FAIL|libellé — détail
#   RESULTAT|SKIP|libellé — raison        non applicable PAR NATURE
#   RESULTAT|INDISPO|libellé — raison     ENVIRONNEMENT INDISPONIBLE
#   FIN|groupe|nombre-de-vérifications
#
# Les deux dernières lignes ne se confondent pas, et c'est l'objet de TASK-013.
# SKIP dit « ce conteneur n'aura jamais systemd ni CAP_SYS_ADMIN » : la limite
# est assumée, le fichier appelant peut sortir en 4. INDISPO dit « l'index apt
# n'a pas pu être rafraîchi » : la preuve existe, elle n'a pas été produite, et
# l'appelant sort alors en 3. Un verdict inconnu de l'appelant est compté en
# échec — ajouter une nature ici impose donc de la traiter là-bas.
#
# La ligne FIN est le témoin de bonne fin : sans elle, l'appelant sait que le
# groupe s'est interrompu et le compte pour un échec. Le code de retour, lui,
# reste 0 tant que le fichier va au bout : c'est l'appelant qui juge.

set -Eeuo pipefail

_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_dir/lib/common.sh" ] && [ "$_dir" != "/" ]; do _dir="$(dirname "$_dir")"; done
source "$_dir/lib/common.sh"

SYS="$SCRIPTS_ROOT/Linux/System"

HOSTNAME_SH="$SYS/configure-hostname.sh"
LOGGING_SH="$SYS/configure-logging.sh"
SWAP_SH="$SYS/configure-swap.sh"
TIMEZONE_SH="$SYS/configure-timezone.sh"
UPDATE_SH="$SYS/update-system.sh"

CINQ_SCRIPTS="$HOSTNAME_SH $LOGGING_SH $SWAP_SH $TIMEZONE_SH $UPDATE_SH"

REP_TMP="$(mktemp -d)"
F_OUT="$REP_TMP/stdout"
F_ERR="$REP_TMP/stderr"
CODE=0
VERIFICATIONS=0

trap 'rm -rf "$REP_TMP"' EXIT

# -------------------------------------------------------------------
# Compte rendu
# -------------------------------------------------------------------
pass() {
    printf 'RESULTAT|PASS|%s\n' "$1"
    VERIFICATIONS=$((VERIFICATIONS + 1))
}

fail() {
    printf 'RESULTAT|FAIL|%s\n' "$1"
    VERIFICATIONS=$((VERIFICATIONS + 1))
    if [ -s "$F_ERR" ]; then
        printf '        dernières lignes de la sortie :\n' >&2
        tail -n 6 "$F_ERR" | sed 's/^/        /' >&2
    fi
}

# skip <libellé> — cas NON APPLICABLE PAR NATURE dans ce conteneur : systemd
# absent, CAP_SYS_ADMIN refusé, outil volontairement hors de l'image minimale.
skip() {
    printf 'RESULTAT|SKIP|%s\n' "$1"
    VERIFICATIONS=$((VERIFICATIONS + 1))
}

# skip_indisponible <libellé> — ENVIRONNEMENT INDISPONIBLE : le conteneur est
# conforme, c'est une ressource extérieure qui a manqué — le réseau, le miroir
# apt. La preuve existe et serait produite ailleurs ; l'appelant sort en 3.
skip_indisponible() {
    printf 'RESULTAT|INDISPO|%s\n' "$1"
    VERIFICATIONS=$((VERIFICATIONS + 1))
}

# Échec dont le diagnostic est un fichier produit par le test lui-même — liste
# de fichiers touchés, différence d'empreintes — et non la sortie du script.
fail_avec_fichier() {
    printf 'RESULTAT|FAIL|%s\n' "$1"
    VERIFICATIONS=$((VERIFICATIONS + 1))
    head -n 12 "$2" | sed 's/^/        /' >&2
}

verdict() {
    # verdict <condition-déjà-évaluée> <libellé> <détail-si-échec>
    if [ "$1" = "0" ]; then
        pass "$2"
    else
        fail "$2 — $3"
    fi
}

# -------------------------------------------------------------------
# Exécution isolée
# -------------------------------------------------------------------
# Le sous-shell est indispensable : lib/common.sh pose un trap ERR et ce
# fichier tourne sous set -Eeuo pipefail. Sans lui, le premier cas qui attend
# un échec ferait tomber tout le groupe.
#
# stdin est fermé pour tous les cas : confirm() qui n'a pas ASSUME_YES=true
# lit alors une réponse vide et répond « non ». C'est ce qui rend le chemin
# « sans -y » observable sans interaction.
lancer() {
    CODE=0
    ( "$@" ) >"$F_OUT" 2>"$F_ERR" </dev/null || CODE=$?
}

contient() { grep -qF -- "$2" "$1"; }

# -------------------------------------------------------------------
# Empreinte du système
# -------------------------------------------------------------------
# Les fichiers visés par les cinq scripts. /etc/hosts, /etc/hostname et
# /etc/resolv.conf sont des montages liés dans un conteneur Docker : ils
# échappent au balayage par « find -xdev », d'où leur relevé explicite ici.
empreinte() {
    local f
    for f in /etc/hosts /etc/hostname /etc/timezone /etc/fstab /swapfile; do
        if [ -e "$f" ]; then
            printf '%s %s\n' "$f" "$(cksum < "$f")"
        else
            printf '%s absent\n' "$f"
        fi
    done
    printf 'localtime %s\n' "$(readlink -f /etc/localtime 2>/dev/null || echo absent)"
    printf 'hostname %s\n' "$(hostname)"
    printf 'swaps %s\n' "$(cksum < /proc/swaps)"
    printf 'logrotate.d %s\n' \
        "$(find /etc/logrotate.d -maxdepth 1 -type f 2>/dev/null | sort | tr '\n' ' ')"
    printf 'sauvegardes %s\n' \
        "$(find /etc -maxdepth 1 \( -name 'hosts.bak-*' -o -name 'fstab.bak-*' \) 2>/dev/null | sort | tr '\n' ' ')"
    printf 'paquets %s\n' "$(dpkg-query -W -f='${Package} ${Version}\n' 2>/dev/null | sort | cksum)"
}

# Fichiers écrits depuis un fichier témoin, hors répertoire de journaux.
#
# La référence est un fichier et non une date en secondes : « find -newer »
# compare à la précision du système de fichiers, là où « -newermt @secondes »
# arrondit et fait remonter les écritures faites par Docker au démarrage du
# conteneur, dans la même seconde que le relevé.
#
# lib/common.sh crée LOG_DIR et y écrit un journal au seul chargement, avant
# même que le script n'ait analysé ses arguments. Ce n'est pas une modification
# du système au sens de --dry-run, mais il faut l'exclure explicitement, sinon
# aucun --dry-run ne pourrait jamais être déclaré inoffensif.
ecritures_depuis() {
    # « find -xdev » ne descend pas dans les autres systèmes de fichiers mais
    # énumère leurs points de montage, dont l'horodatage n'appartient pas au
    # conteneur : /proc, /sys, /dev, le dépôt monté, et les fichiers que Docker
    # injecte (/etc/hosts, /etc/hostname, /etc/resolv.conf). Ces derniers sont
    # relevés par empreinte(), qui lit leur contenu — ils ne sont pas perdus de
    # vue, ils sont surveillés autrement.
    local point
    local -a exclusions=()
    while IFS= read -r point; do
        [ -n "$point" ] || continue
        exclusions+=(-not -path "$point")
    done < <(awk '{ print $5 }' /proc/self/mountinfo | sort -u)

    find / -xdev -newer "$1" \
        "${exclusions[@]}" \
        -not -path '/var/log' \
        -not -path '/var/log/mgnetworking*' \
        -not -path '/tmp' \
        -not -path '/tmp/*' \
        -not -path '/var/tmp/*' \
        -not -path '/run/*' \
        -not -path '/var/cache/apt/*' \
        -not -path '/var/lib/apt/*' \
        2>/dev/null | sort
}

# Relève, dans la trace d'exécution, tout script du dépôt appelé en position de
# commande. « bash -x » imprime chaque commande après expansion : un appel à un
# autre script y apparaît, une simple mention dans un message d'information non.
trace_appels() {
    local nom="$1"; shift
    local trace="$REP_TMP/trace"

    CODE=0
    ( "$@" ) >/dev/null 2>"$trace" </dev/null || CODE=$?

    # Tout est fait en awk : un « grep » qui ne trouve rien sort en 1, ce qui,
    # sous set -Eeuo pipefail, ferait tomber le groupe entier alors que le cas
    # est justement réussi.
    awk '
        /^\++ / {
            sub(/^\++ /, "")
            mot[1] = $1; mot[2] = $2
            for (i = 1; i <= 2; i++) {
                if (mot[i] ~ /\.sh$/ && mot[i] !~ /\/lib\/common\.sh$/) {
                    print mot[i]
                }
            }
        }
    ' "$trace" | sort -u > "$REP_TMP/appels"

    if [ -s "$REP_TMP/appels" ]; then
        fail_avec_fichier "$nom n'appelle aucun autre script du dépôt" "$REP_TMP/appels"
    else
        pass "$nom n'appelle aucun autre script du dépôt"
    fi
}

# Une empreinte prise, un traitement lancé, l'empreinte reprise : le système
# doit être identique. Sert à prouver qu'un --dry-run ne touche à rien et
# qu'une seconde exécution ne change plus rien.
compare_empreintes() {
    local avant="$1" apres="$2" libelle="$3"
    if diff -u "$avant" "$apres" > "$REP_TMP/diff-empreintes" 2>&1; then
        pass "$libelle"
    else
        fail_avec_fichier "$libelle — différences relevées" "$REP_TMP/diff-empreintes"
    fi
}

# ===================================================================
# Groupe « preflight » — refus d'exécution, options, privilèges
# ===================================================================
groupe_preflight() {
    local script nom

    for script in $CINQ_SCRIPTS; do
        nom="$(basename "$script")"

        lancer bash "$script" --help
        verdict "$([ "$CODE" -eq 0 ] && echo 0 || echo 1)" \
            "$nom --help sort en 0" "code $CODE"
        verdict "$(contient "$F_OUT" "Usage :" && echo 0 || echo 1)" \
            "$nom --help écrit son usage sur stdout" "aucun « Usage : » sur stdout"

        lancer bash "$script" -h
        verdict "$([ "$CODE" -eq 0 ] && echo 0 || echo 1)" \
            "$nom -h sort en 0" "code $CODE"

        lancer bash "$script" --option-qui-n-existe-pas
        verdict "$([ "$CODE" -eq 2 ] && echo 0 || echo 1)" \
            "$nom refuse une option inconnue avec le code 2" "code $CODE"
        verdict "$(contient "$F_ERR" "Option inconnue" && echo 0 || echo 1)" \
            "$nom nomme l'option inconnue" "message absent"
    done

    # Privilèges. require_root sort en 1, pas en 2 : dans ce dépôt le code 2
    # est réservé à l'erreur d'usage. Voir lib/common.sh.
    if ! command -v setpriv >/dev/null 2>&1; then
        skip "refus sans privilège — setpriv absent de l'image, impossible de perdre root"
        return 0
    fi

    # Deux tableaux plutôt qu'une chaîne découpée : le découpage de mots
    # obligerait à désactiver SC2086, et une directive de complaisance dans le
    # fichier qui éprouve l'analyse statique serait malvenue.
    local -a sans_root=(setpriv --reuid=65534 --regid=65534 --clear-groups)

    # LOG_DIR est déplacé dans /tmp : sans cela lib/common.sh tenterait d'écrire
    # son journal dans le dépôt monté, qui n'appartient pas à « nobody ». C'est
    # le seul aménagement, il ne touche à aucun chemin vérifié par ces cas.
    local -a env_nobody=(env LOG_DIR=/tmp/mgnet-logs-nobody)

    lancer "${env_nobody[@]}" "${sans_root[@]}" bash "$HOSTNAME_SH" essai-mgnet
    verdict "$([ "$CODE" -eq 1 ] && echo 0 || echo 1)" \
        "configure-hostname.sh refuse de s'exécuter sans privilège" "code $CODE"
    verdict "$(contient "$F_ERR" "doit être exécuté en root" && echo 0 || echo 1)" \
        "configure-hostname.sh dit pourquoi il refuse" "message absent"

    lancer "${env_nobody[@]}" "${sans_root[@]}" bash "$TIMEZONE_SH" Europe/Paris
    verdict "$([ "$CODE" -eq 1 ] && echo 0 || echo 1)" \
        "configure-timezone.sh refuse de s'exécuter sans privilège" "code $CODE"

    lancer "${env_nobody[@]}" "${sans_root[@]}" bash "$LOGGING_SH"
    verdict "$([ "$CODE" -eq 1 ] && echo 0 || echo 1)" \
        "configure-logging.sh refuse de s'exécuter sans privilège" "code $CODE"

    lancer "${env_nobody[@]}" "${sans_root[@]}" bash "$SWAP_SH" 512M
    verdict "$([ "$CODE" -eq 1 ] && echo 0 || echo 1)" \
        "configure-swap.sh refuse de s'exécuter sans privilège" "code $CODE"

    lancer "${env_nobody[@]}" "${sans_root[@]}" bash "$UPDATE_SH"
    verdict "$([ "$CODE" -eq 1 ] && echo 0 || echo 1)" \
        "update-system.sh refuse de s'exécuter sans privilège" "code $CODE"

    # L'erreur d'usage doit primer sur le manque de privilège : sinon un appel
    # mal formé serait masqué par un message de permission.
    lancer "${env_nobody[@]}" "${sans_root[@]}" bash "$UPDATE_SH" --option-qui-n-existe-pas
    verdict "$([ "$CODE" -eq 2 ] && echo 0 || echo 1)" \
        "update-system.sh : l'option inconnue prime sur le manque de privilège" "code $CODE"
}

# ===================================================================
# Groupe « aide » — la commande de validation inscrite dans TASK-011
# ===================================================================
groupe_aide() {
    # Reprise fidèle de la boucle inscrite dans TASK-011 : les scripts sont
    # invoqués directement, sans « bash » devant — le bit exécutable du montage
    # fait donc partie de ce qui est éprouvé.
    local script echecs=0 nom
    for script in "$SYS"/*.sh; do
        nom="$(basename "$script")"
        lancer "$script" --help
        if [ "$CODE" -ne 0 ]; then
            echecs=$((echecs + 1))
            printf '        %s --help sort en %s\n' "$nom" "$CODE" >&2
        fi
    done
    verdict "$([ "$echecs" -eq 0 ] && echo 0 || echo 1)" \
        "tous les Linux/System/*.sh affichent leur aide et sortent en 0" \
        "$echecs script(s) en défaut"
}

# ===================================================================
# Groupe « dry-run » — hostname, timezone, swap
# ===================================================================
# configure-logging.sh et update-system.sh ont leur propre groupe : le premier
# exige logrotate, le second un index de paquets à jour.
groupe_dry_run() {
    dry_run_inoffensif() {
        local libelle="$1"; shift
        empreinte > "$REP_TMP/avant"
        touch "$REP_TMP/marqueur"
        lancer "$@"
        verdict "$([ "$CODE" -eq 0 ] && echo 0 || echo 1)" \
            "$libelle sort en 0" "code $CODE"
        verdict "$(contient "$F_ERR" "aucune modification effectuée" && echo 0 || echo 1)" \
            "$libelle annonce qu'il n'a rien modifié" "message absent"
        empreinte > "$REP_TMP/apres"
        compare_empreintes "$REP_TMP/avant" "$REP_TMP/apres" \
            "$libelle laisse les fichiers visés intacts"

        ecritures_depuis "$REP_TMP/marqueur" > "$REP_TMP/ecritures"
        if [ -s "$REP_TMP/ecritures" ]; then
            fail_avec_fichier "$libelle n'écrit rien hors du répertoire de journaux — fichiers touchés" \
                "$REP_TMP/ecritures"
        else
            pass "$libelle n'écrit rien hors du répertoire de journaux"
        fi
    }

    dry_run_inoffensif "configure-hostname.sh --dry-run" \
        bash "$HOSTNAME_SH" essai-mgnet --dry-run
    dry_run_inoffensif "configure-timezone.sh --dry-run" \
        bash "$TIMEZONE_SH" Europe/Paris --dry-run
    dry_run_inoffensif "configure-swap.sh --dry-run" \
        bash "$SWAP_SH" 512M --dry-run

    # configure-swap.sh sans taille : diagnostic seul, il ne doit rien changer
    # non plus, et il s'arrête avant même require_root.
    empreinte > "$REP_TMP/avant"
    lancer bash "$SWAP_SH"
    verdict "$([ "$CODE" -eq 0 ] && echo 0 || echo 1)" \
        "configure-swap.sh sans taille sort en 0" "code $CODE"
    empreinte > "$REP_TMP/apres"
    compare_empreintes "$REP_TMP/avant" "$REP_TMP/apres" \
        "configure-swap.sh sans taille ne modifie rien"
}

# ===================================================================
# Groupe « regex » — les quatre motifs corrigés par SC1087
# ===================================================================
# Le chemin réel de configure-swap.sh (lignes 211 et 323) exige un swap actif,
# impossible dans un conteneur non privilégié. Ce groupe éprouve donc les motifs
# hors de leur script : d'abord leur sens, ensuite l'équivalence stricte entre
# l'ancienne écriture « $VAR[ » et la nouvelle « ${VAR}[ ».
groupe_regex() {
    local fichier="$REP_TMP/corpus"
    local FICHIER_SWAP="/swapfile"
    local ADRESSE_HOTE="127.0.1.1"

    # Chaque cas : « attendu(0 trouvé, 1 absent)|ligne ».
    motif_swap() {
        local ligne="$1" attendu="$2" libelle="$3"
        printf '%s\n' "$ligne" > "$fichier"

        local ancien=0 nouveau=0
        # L'écriture « $VAR[ » est celle d'AVANT la correction : elle est
        # reproduite ici volontairement, c'est tout l'objet du cas. SC1087 la
        # signale à juste titre dans un script de production ; dans ce test,
        # la supprimer reviendrait à supprimer le témoin de comparaison.
        # shellcheck disable=SC1087
        grep -qE "^[[:space:]]*$FICHIER_SWAP[[:space:]]" "$fichier" || ancien=1
        grep -qE "^[[:space:]]*${FICHIER_SWAP}[[:space:]]" "$fichier" || nouveau=1

        verdict "$([ "$nouveau" -eq "$attendu" ] && echo 0 || echo 1)" \
            "fstab : $libelle" "attendu $attendu, obtenu $nouveau"
        verdict "$([ "$ancien" -eq "$nouveau" ] && echo 0 || echo 1)" \
            "fstab : $libelle — ancienne et nouvelle écriture concordent" \
            "\$VAR[ donne $ancien, \${VAR}[ donne $nouveau"
    }

    motif_hosts() {
        local ligne="$1" attendu="$2" libelle="$3"
        printf '%s\n' "$ligne" > "$fichier"

        local ancien=0 nouveau=0
        # Même remarque que pour motif_swap : « $VAR[ » est le témoin d'avant
        # correction, il doit rester écrit tel quel pour que la comparaison ait
        # un sens.
        # shellcheck disable=SC1087
        grep -qE "^[[:space:]]*$ADRESSE_HOTE[[:space:]]" "$fichier" || ancien=1
        grep -qE "^[[:space:]]*${ADRESSE_HOTE}[[:space:]]" "$fichier" || nouveau=1

        verdict "$([ "$nouveau" -eq "$attendu" ] && echo 0 || echo 1)" \
            "hosts : $libelle" "attendu $attendu, obtenu $nouveau"
        verdict "$([ "$ancien" -eq "$nouveau" ] && echo 0 || echo 1)" \
            "hosts : $libelle — ancienne et nouvelle écriture concordent" \
            "\$VAR[ donne $ancien, \${VAR}[ donne $nouveau"
    }

    motif_swap "/swapfile	none	swap	sw	0	0" 0 "ligne présente, tabulations"
    motif_swap "/swapfile none swap sw 0 0"          0 "ligne présente, espaces"
    motif_swap "   /swapfile none swap sw 0 0"       0 "ligne présente, indentée"
    motif_swap "# UNCONFIGURED FSTAB FOR BASE SYSTEM" 1 "ligne absente"
    motif_swap "#/swapfile none swap sw 0 0"          1 "entrée commentée, non reconnue"
    motif_swap "/swapfile2 none swap sw 0 0"          1 "chemin plus long, non confondu"
    motif_swap "/autre/swapfile none swap sw 0 0"     1 "chemin préfixé, non confondu"

    motif_hosts "127.0.1.1	serveur	srv" 0 "ligne présente, tabulations"
    motif_hosts "127.0.0.1	localhost"    1 "ligne absente"
    motif_hosts "127.0.1.10	autre"        1 "adresse plus longue, non confondue"
    motif_hosts "#127.0.1.1	serveur"      1 "ligne commentée, non reconnue"

    # SC1087 vise une ambiguïté de tableau. La preuve que les variables en cause
    # sont bien des scalaires ferme le sujet.
    local type_swap type_hote
    type_swap="$(declare -p FICHIER_SWAP)"
    type_hote="$(declare -p ADRESSE_HOTE)"
    verdict "$(case "$type_swap" in *-a*|*-A*) echo 1 ;; *) echo 0 ;; esac)" \
        "FICHIER_SWAP est un scalaire, jamais un tableau" "$type_swap"
    verdict "$(case "$type_hote" in *-a*|*-A*) echo 1 ;; *) echo 0 ;; esac)" \
        "ADRESSE_HOTE est un scalaire, jamais un tableau" "$type_hote"

    # Les mêmes motifs éprouvés dans leur script : voir le groupe swap-fstab.
}

# ===================================================================
# Groupe « swap-fstab » — la garde d'idempotence de configure-swap.sh
# ===================================================================
# C'est le chemin que la ligne 211 corrigée protège : « swap déjà actif à la
# bonne taille ET déjà inscrit dans /etc/fstab » vaut « rien à faire ». Une
# expression cassée ferait réécrire /etc/fstab à chaque exécution.
#
# swapon est refusé au conteneur non privilégié : le swap actif ne peut pas
# être créé ici. La garde est donc éprouvée sur le swap que /proc/swaps
# expose déjà — celui de l'hôte, que le conteneur voit sans le contrôler — en
# posant à son chemin un fichier creux de la taille exacte annoncée. Ce n'est
# pas un swap : c'est ce que le script LIT d'un swap, reproduit à l'identique.
# L'activation elle-même reste NON EXÉCUTÉE, plus bas.
groupe_swap_fstab() {
    local nom taille_ko taille_mo

    if [ ! -r /proc/swaps ] || [ "$(wc -l < /proc/swaps)" -le 1 ]; then
        skip "garde d'idempotence de configure-swap.sh — /proc/swaps est vide, aucun swap à imiter"
        return 0
    fi

    nom="$(awk 'NR == 2 { print $1 }' /proc/swaps)"
    taille_ko="$(awk 'NR == 2 { print $3 }' /proc/swaps)"
    taille_mo=$(( taille_ko / 1024 ))

    if [ "$taille_mo" -lt 64 ]; then
        skip "garde d'idempotence de configure-swap.sh — le swap visible fait ${taille_mo} Mo, sous le minimum du script"
        return 0
    fi

    mkdir -p "$(dirname "$nom")"
    truncate -s "${taille_ko}K" "$nom"

    cp /etc/fstab "$REP_TMP/fstab.origine"

    # 1. /etc/fstab ne mentionne pas le fichier : la garde ne doit pas jouer.
    lancer bash "$SWAP_SH" "${taille_mo}M" --file "$nom" --dry-run
    verdict "$([ "$CODE" -eq 0 ] && echo 0 || echo 1)" \
        "configure-swap.sh --dry-run sur swap actif sort en 0" "code $CODE"
    verdict "$(contient "$F_ERR" "absent de /etc/fstab" && echo 0 || echo 1)" \
        "grep corrigé : entrée absente de /etc/fstab, la garde ne joue pas" "message absent"

    # 2. Une entrée au chemin plus long ne doit pas être prise pour la bonne.
    printf '%s none swap sw 0 0\n' "${nom}2" >> /etc/fstab
    lancer bash "$SWAP_SH" "${taille_mo}M" --file "$nom" --dry-run
    verdict "$(contient "$F_ERR" "absent de /etc/fstab" && echo 0 || echo 1)" \
        "grep corrigé : une entrée au chemin plus long n'est pas confondue" "message absent"
    cp "$REP_TMP/fstab.origine" /etc/fstab

    # 3. L'entrée exacte est présente : la garde doit couper court, et le
    #    script ne doit RIEN écrire. Volontairement sans --dry-run : c'est la
    #    garde elle-même qui doit arrêter l'exécution.
    printf '%s	none	swap	sw	0	0\n' "$nom" >> /etc/fstab
    empreinte > "$REP_TMP/avant"
    lancer bash "$SWAP_SH" "${taille_mo}M" --file "$nom"
    verdict "$([ "$CODE" -eq 0 ] && echo 0 || echo 1)" \
        "configure-swap.sh sort en 0 quand tout est déjà en place" "code $CODE"
    verdict "$(contient "$F_ERR" "Rien à faire" && echo 0 || echo 1)" \
        "grep corrigé : entrée trouvée dans /etc/fstab, rien à faire" "message absent"
    empreinte > "$REP_TMP/apres"
    compare_empreintes "$REP_TMP/avant" "$REP_TMP/apres" \
        "configure-swap.sh ne réécrit pas /etc/fstab quand l'entrée y est déjà"

    # Seconde exécution : même verdict, même absence d'écriture.
    lancer bash "$SWAP_SH" "${taille_mo}M" --file "$nom"
    verdict "$(contient "$F_ERR" "Rien à faire" && echo 0 || echo 1)" \
        "configure-swap.sh est idempotent sur la garde" "message absent"
    empreinte > "$REP_TMP/apres2"
    compare_empreintes "$REP_TMP/avant" "$REP_TMP/apres2" \
        "deux exécutions de plus ne changent toujours rien"

    rm -f "$nom"
    cp "$REP_TMP/fstab.origine" /etc/fstab

    skip "configure-swap.sh ligne 323, l'ajout à /etc/fstab — exige un swapon réussi, refusé au conteneur non privilégié"
}

# ===================================================================
# Groupe « timezone » — nominal, -y, idempotence
# ===================================================================
groupe_timezone() {
    local cible="Europe/Paris"

    if [ ! -f "/usr/share/zoneinfo/$cible" ]; then
        skip "configure-timezone.sh nominal — /usr/share/zoneinfo/$cible absent de l'image"
        return 0
    fi

    empreinte > "$REP_TMP/avant"

    # Sans -y et stdin fermé : confirm() lit une réponse vide et refuse.
    lancer bash "$TIMEZONE_SH" "$cible"
    verdict "$([ "$CODE" -eq 0 ] && echo 0 || echo 1)" \
        "configure-timezone.sh sans -y sort en 0" "code $CODE"
    verdict "$(contient "$F_ERR" "Abandon à la demande de l'utilisateur" && echo 0 || echo 1)" \
        "configure-timezone.sh sans -y renonce sur réponse vide" "message absent"
    empreinte > "$REP_TMP/apres"
    compare_empreintes "$REP_TMP/avant" "$REP_TMP/apres" \
        "configure-timezone.sh sans -y ne modifie rien"

    # Avec -y : c'est le seul cas qui prouve que confirm() voit toujours
    # ASSUME_YES après le passage à « export ».
    lancer bash "$TIMEZONE_SH" "$cible" -y
    verdict "$([ "$CODE" -eq 0 ] && echo 0 || echo 1)" \
        "configure-timezone.sh -y sort en 0" "code $CODE"
    verdict "$(contient "$F_ERR" "Confirmation automatique" && echo 0 || echo 1)" \
        "configure-timezone.sh -y : confirm() voit ASSUME_YES malgré export" "message absent"
    verdict "$(contient "$F_ERR" "Fuseau horaire configuré : $cible" && echo 0 || echo 1)" \
        "configure-timezone.sh -y applique le fuseau" "message absent"

    local lien contenu
    lien="$(readlink -f /etc/localtime 2>/dev/null || echo absent)"
    verdict "$([ "$lien" = "/usr/share/zoneinfo/$cible" ] && echo 0 || echo 1)" \
        "/etc/localtime pointe sur $cible" "$lien"
    contenu="$(tr -d '[:space:]' < /etc/timezone)"
    verdict "$([ "$contenu" = "$cible" ] && echo 0 || echo 1)" \
        "/etc/timezone contient $cible" "$contenu"

    # Idempotence : seconde exécution sur un système déjà conforme.
    empreinte > "$REP_TMP/avant2"
    lancer bash "$TIMEZONE_SH" "$cible" -y
    verdict "$([ "$CODE" -eq 0 ] && echo 0 || echo 1)" \
        "configure-timezone.sh seconde exécution sort en 0" "code $CODE"
    verdict "$(contient "$F_ERR" "Rien à faire" && echo 0 || echo 1)" \
        "configure-timezone.sh seconde exécution : rien à faire" "message absent"
    empreinte > "$REP_TMP/apres2"
    compare_empreintes "$REP_TMP/avant2" "$REP_TMP/apres2" \
        "configure-timezone.sh est idempotent"

    skip "configure-timezone.sh via timedatectl — le conteneur n'a pas systemd, seul le repli /etc/localtime a été éprouvé"
}

# ===================================================================
# Groupe « hostname » — /etc/hosts absent au départ
# ===================================================================
# Le nom d'hôte demandé est celui du conteneur : le changement porte alors sur
# le seul /etc/hosts. Changer le nom lui-même exige CAP_SYS_ADMIN, que Docker
# ne donne pas — ce chemin est déclaré NON EXÉCUTÉ plus bas.
groupe_hostname() {
    local nom
    nom="$(hostname)"

    empreinte > "$REP_TMP/avant"

    lancer bash "$HOSTNAME_SH" "$nom"
    verdict "$([ "$CODE" -eq 0 ] && echo 0 || echo 1)" \
        "configure-hostname.sh sans -y sort en 0" "code $CODE"
    verdict "$(contient "$F_ERR" "Abandon à la demande de l'utilisateur" && echo 0 || echo 1)" \
        "configure-hostname.sh sans -y renonce sur réponse vide" "message absent"
    empreinte > "$REP_TMP/apres"
    compare_empreintes "$REP_TMP/avant" "$REP_TMP/apres" \
        "configure-hostname.sh sans -y ne modifie rien"

    # Ligne 141 corrigée, cas « aucune ligne 127.0.1.1 » : le script doit
    # annoncer un ajout, pas un remplacement.
    verdict "$(contient "$F_ERR" "ajout de « 127.0.1.1" && echo 0 || echo 1)" \
        "grep corrigé : aucune ligne 127.0.1.1 trouvée, le script annonce un ajout" "message absent"

    lancer bash "$HOSTNAME_SH" "$nom" -y
    verdict "$([ "$CODE" -eq 0 ] && echo 0 || echo 1)" \
        "configure-hostname.sh -y sort en 0" "code $CODE"
    verdict "$(contient "$F_ERR" "Confirmation automatique" && echo 0 || echo 1)" \
        "configure-hostname.sh -y : confirm() voit ASSUME_YES malgré export" "message absent"
    verdict "$(contient "$F_ERR" "/etc/hosts mis à jour" && echo 0 || echo 1)" \
        "configure-hostname.sh -y met /etc/hosts à jour" "message absent"
    # Ligne 269 corrigée : la vérification finale relit la ligne posée.
    verdict "$(contient "$F_ERR" "Ligne /etc/hosts : 127.0.1.1" && echo 0 || echo 1)" \
        "grep corrigé : la vérification finale relit la ligne 127.0.1.1" "message absent"

    local lignes
    lignes="$(grep -cE '^[[:space:]]*127\.0\.1\.1[[:space:]]' /etc/hosts || true)"
    verdict "$([ "$lignes" = "1" ] && echo 0 || echo 1)" \
        "/etc/hosts porte exactement une ligne 127.0.1.1" "$lignes ligne(s)"
    verdict "$(grep -qE "^[[:space:]]*127\\.0\\.1\\.1[[:space:]]+$nom\$" /etc/hosts && echo 0 || echo 1)" \
        "/etc/hosts associe 127.0.1.1 au nom demandé" "association absente"
    verdict "$(ls -1d /etc/hosts.bak-* >/dev/null 2>&1 && echo 0 || echo 1)" \
        "configure-hostname.sh a sauvegardé /etc/hosts avant de l'écrire" "aucune sauvegarde"

    # Idempotence : la seconde exécution emprunte le chemin « ligne présente »
    # du grep corrigé. Une expression cassée réécrirait /etc/hosts à chaque fois.
    empreinte > "$REP_TMP/avant2"
    lancer bash "$HOSTNAME_SH" "$nom" -y
    verdict "$([ "$CODE" -eq 0 ] && echo 0 || echo 1)" \
        "configure-hostname.sh seconde exécution sort en 0" "code $CODE"
    verdict "$(contient "$F_ERR" "Rien à faire" && echo 0 || echo 1)" \
        "grep corrigé : la ligne 127.0.1.1 est retrouvée, rien à faire" "message absent"
    empreinte > "$REP_TMP/apres2"
    compare_empreintes "$REP_TMP/avant2" "$REP_TMP/apres2" \
        "configure-hostname.sh est idempotent sur /etc/hosts"

    skip "configure-hostname.sh changeant réellement le nom — hostnamectl absent et « hostname » exige CAP_SYS_ADMIN, refusé au conteneur"
}

# ===================================================================
# Groupe « hosts-existant » — une ligne 127.0.1.1 déjà en place
# ===================================================================
# Second cas du grep corrigé de la ligne 141 : la ligne existe mais porte un
# autre nom. Le script doit la remplacer, sans jamais en ajouter une deuxième.
groupe_hosts_existant() {
    local nom
    nom="$(hostname)"

    local temporaire="$REP_TMP/hosts.prepare"
    {
        printf '127.0.0.1\tlocalhost\n'
        printf '127.0.1.1\tancien-nom\tancien\n'
        printf '::1\tlocalhost ip6-localhost ip6-loopback\n'
    } > "$temporaire"
    cat "$temporaire" > /etc/hosts

    lancer bash "$HOSTNAME_SH" "$nom" -y
    verdict "$([ "$CODE" -eq 0 ] && echo 0 || echo 1)" \
        "configure-hostname.sh sur une ligne 127.0.1.1 existante sort en 0" "code $CODE"
    verdict "$(contient "$F_ERR" "ancien-nom" && echo 0 || echo 1)" \
        "grep corrigé : la ligne existante est retrouvée et affichée" "ligne non citée"

    local lignes
    lignes="$(grep -cE '^[[:space:]]*127\.0\.1\.1[[:space:]]' /etc/hosts || true)"
    verdict "$([ "$lignes" = "1" ] && echo 0 || echo 1)" \
        "la ligne 127.0.1.1 est remplacée, pas dupliquée" "$lignes ligne(s)"
    verdict "$(grep -q 'ancien-nom' /etc/hosts && echo 1 || echo 0)" \
        "l'ancien nom a disparu de /etc/hosts" "ancien-nom toujours présent"
    verdict "$(grep -qE "^[[:space:]]*127\\.0\\.0\\.1[[:space:]]+localhost\$" /etc/hosts && echo 0 || echo 1)" \
        "la ligne localhost est préservée" "ligne localhost perdue"

    # Deuxième exécution : plus rien à faire.
    empreinte > "$REP_TMP/avant2"
    lancer bash "$HOSTNAME_SH" "$nom" -y
    verdict "$(contient "$F_ERR" "Rien à faire" && echo 0 || echo 1)" \
        "configure-hostname.sh est idempotent après remplacement" "message absent"
    empreinte > "$REP_TMP/apres2"
    compare_empreintes "$REP_TMP/avant2" "$REP_TMP/apres2" \
        "configure-hostname.sh ne retouche pas /etc/hosts au second passage"
}

# ===================================================================
# Groupe « logging » — nominal, idempotence, refus et acceptation via -y
# ===================================================================
groupe_logging() {
    if ! command -v logrotate >/dev/null 2>&1; then
        if ! apt-get update -qq >/dev/null 2>&1 || ! apt-get install -y -qq logrotate >/dev/null 2>&1; then
            skip_indisponible "configure-logging.sh — logrotate absent de l'image et non installable, apt-get n'a pas abouti"
            return 0
        fi
    fi

    local regle
    regle="/etc/logrotate.d/$(basename "$LOG_DIR")"

    # --dry-run d'abord : la règle ne doit pas apparaître.
    empreinte > "$REP_TMP/avant"
    lancer bash "$LOGGING_SH" --dry-run
    verdict "$([ "$CODE" -eq 0 ] && echo 0 || echo 1)" \
        "configure-logging.sh --dry-run sort en 0" "code $CODE"
    verdict "$([ ! -f "$regle" ] && echo 0 || echo 1)" \
        "configure-logging.sh --dry-run ne dépose pas la règle" "$regle créé"
    empreinte > "$REP_TMP/apres"
    compare_empreintes "$REP_TMP/avant" "$REP_TMP/apres" \
        "configure-logging.sh --dry-run ne modifie rien"

    lancer bash "$LOGGING_SH"
    verdict "$([ "$CODE" -eq 0 ] && echo 0 || echo 1)" \
        "configure-logging.sh sort en 0" "code $CODE"
    verdict "$([ -f "$regle" ] && echo 0 || echo 1)" \
        "configure-logging.sh dépose $regle" "fichier absent"

    # Idempotence.
    empreinte > "$REP_TMP/avant2"
    cp "$regle" "$REP_TMP/regle.reference"
    lancer bash "$LOGGING_SH"
    verdict "$([ "$CODE" -eq 0 ] && echo 0 || echo 1)" \
        "configure-logging.sh seconde exécution sort en 0" "code $CODE"
    verdict "$(contient "$F_ERR" "déjà en place et à jour" && echo 0 || echo 1)" \
        "configure-logging.sh seconde exécution : règle déjà à jour" "message absent"
    empreinte > "$REP_TMP/apres2"
    compare_empreintes "$REP_TMP/avant2" "$REP_TMP/apres2" \
        "configure-logging.sh est idempotent"

    # Règle modifiée à la main : le script propose de la remplacer. C'est le
    # seul chemin de ce script qui atteint confirm().
    printf '# règle modifiée à la main par le test\n' >> "$regle"
    cp "$regle" "$REP_TMP/regle.alteree"

    lancer bash "$LOGGING_SH"
    verdict "$([ "$CODE" -eq 0 ] && echo 0 || echo 1)" \
        "configure-logging.sh sans -y sur règle divergente sort en 0" "code $CODE"
    verdict "$(contient "$F_ERR" "Abandon : la règle en place est conservée" && echo 0 || echo 1)" \
        "configure-logging.sh sans -y conserve la règle en place" "message absent"
    verdict "$(cmp -s "$regle" "$REP_TMP/regle.alteree" && echo 0 || echo 1)" \
        "configure-logging.sh sans -y laisse la règle inchangée" "règle réécrite"

    lancer bash "$LOGGING_SH" -y
    verdict "$([ "$CODE" -eq 0 ] && echo 0 || echo 1)" \
        "configure-logging.sh -y sur règle divergente sort en 0" "code $CODE"
    verdict "$(contient "$F_ERR" "Confirmation automatique" && echo 0 || echo 1)" \
        "configure-logging.sh -y : confirm() voit ASSUME_YES malgré export" "message absent"
    verdict "$(cmp -s "$regle" "$REP_TMP/regle.reference" && echo 0 || echo 1)" \
        "configure-logging.sh -y remet la règle attendue" "règle différente de la référence"
}

# ===================================================================
# Groupe « update » — index de paquets, --dry-run, OS non supporté
# ===================================================================
groupe_update() {
    local empreinte_paquets_avant empreinte_paquets_apres

    empreinte_paquets_avant="$(dpkg-query -W -f='${Package} ${Version}\n' | sort | cksum)"
    touch "$REP_TMP/marqueur"

    lancer bash "$UPDATE_SH" --dry-run
    verdict "$([ "$CODE" -eq 0 ] && echo 0 || echo 1)" \
        "update-system.sh --dry-run sort en 0" "code $CODE"

    empreinte_paquets_apres="$(dpkg-query -W -f='${Package} ${Version}\n' | sort | cksum)"
    verdict "$([ "$empreinte_paquets_avant" = "$empreinte_paquets_apres" ] && echo 0 || echo 1)" \
        "update-system.sh --dry-run n'installe aucun paquet" "la liste des paquets a changé"

    ecritures_depuis "$REP_TMP/marqueur" > "$REP_TMP/ecritures"
    if [ -s "$REP_TMP/ecritures" ]; then
        fail_avec_fichier "update-system.sh --dry-run n'écrit rien hors index de paquets et journaux" \
            "$REP_TMP/ecritures"
    else
        pass "update-system.sh --dry-run n'écrit rien hors index de paquets et journaux"
    fi

    # Le chemin -y de ce script n'existe que s'il reste des paquets à mettre à
    # jour. Sur une image fraîchement publiée, il n'y en a aucun.
    local a_installer
    a_installer="$(apt-get -s upgrade 2>/dev/null | grep -c '^Inst ' || true)"
    if [ "$a_installer" -gt 0 ]; then
        lancer bash "$UPDATE_SH" -y
        verdict "$([ "$CODE" -eq 0 ] && echo 0 || echo 1)" \
            "update-system.sh -y sort en 0" "code $CODE"
        verdict "$(contient "$F_ERR" "Confirmation automatique" && echo 0 || echo 1)" \
            "update-system.sh -y : confirm() voit ASSUME_YES malgré export" "message absent"
    else
        skip "update-system.sh -y — aucun paquet à mettre à jour dans l'image, confirm() n'est jamais atteint"
    fi

    # OS non supporté. /etc/os-release est un fichier ordinaire de l'image :
    # le remplacer le temps d'un appel est le seul moyen d'éprouver require_os
    # sans une seconde image. Le conteneur est détruit ensuite de toute façon.
    cp /etc/os-release "$REP_TMP/os-release.origine"
    printf 'ID=fedora\nVERSION_ID="41"\nPRETTY_NAME="Fedora (simulé pour le test)"\n' > /etc/os-release
    lancer bash "$UPDATE_SH" --dry-run
    cp "$REP_TMP/os-release.origine" /etc/os-release
    verdict "$([ "$CODE" -eq 1 ] && echo 0 || echo 1)" \
        "update-system.sh refuse un OS non supporté" "code $CODE"
    verdict "$(contient "$F_ERR" "Distribution non supportée" && echo 0 || echo 1)" \
        "update-system.sh nomme la distribution refusée" "message absent"
}

# ===================================================================
# Groupe « enfants » — l'export ne perturbe aucun processus fils
# ===================================================================
# « export ASSUME_YES » fait entrer la variable dans l'environnement des
# commandes lancées par les scripts. Aucune ne lit une variable de ce nom ;
# les deux seules qui pourraient en souffrir sont apt-get et logrotate, dont
# la sortie est ici comparée avec et sans la variable.
groupe_enfants() {
    local sans avec

    if ! apt-get update -qq >/dev/null 2>&1; then
        skip_indisponible "apt-get insensible à ASSUME_YES — index de paquets non rafraîchissable"
    else
        sans="$(apt-get -s upgrade 2>/dev/null | cksum)"
        avec="$(ASSUME_YES=true apt-get -s upgrade 2>/dev/null | cksum)"
        verdict "$([ "$sans" = "$avec" ] && echo 0 || echo 1)" \
            "apt-get -s upgrade rend le même résultat avec ASSUME_YES dans l'environnement" \
            "sorties différentes"
    fi

    if ! command -v logrotate >/dev/null 2>&1 \
        && ! apt-get install -y -qq logrotate >/dev/null 2>&1; then
        skip_indisponible "logrotate insensible à ASSUME_YES — logrotate non installable"
    else
        local regle="$REP_TMP/regle-test"
        printf '/var/log/mgnetworking/*.log {\n    weekly\n    rotate 8\n    missingok\n    notifempty\n}\n' > "$regle"
        mkdir -p /var/log/mgnetworking
        sans="$(logrotate -d "$regle" 2>&1 | cksum)"
        avec="$(ASSUME_YES=true logrotate -d "$regle" 2>&1 | cksum)"
        verdict "$([ "$sans" = "$avec" ] && echo 0 || echo 1)" \
            "logrotate -d rend le même résultat avec ASSUME_YES dans l'environnement" \
            "sorties différentes"
    fi

    # Un script du dépôt qui en appellerait un autre lui transmettrait
    # désormais ASSUME_YES. Aucun ne le fait : la trace « bash -x » de chaque
    # exécution ne montre, en position de commande, aucun autre .sh que
    # lib/common.sh. La trace ne couvre que les chemins réellement empruntés,
    # ici les --dry-run ; les chemins d'application n'y figurent pas.
    trace_appels "configure-hostname.sh" bash "$HOSTNAME_SH" essai-mgnet --dry-run
    trace_appels "configure-timezone.sh" bash "$TIMEZONE_SH" Europe/Paris --dry-run
    trace_appels "configure-swap.sh"     bash "$SWAP_SH" 512M --dry-run
    trace_appels "configure-logging.sh"  bash "$LOGGING_SH" --dry-run
    trace_appels "update-system.sh"      bash "$UPDATE_SH" --dry-run

    # Le mécanisme lui-même : confirm(), tel que lib/common.sh le définit, lit
    # bien une ASSUME_YES exportée. Ce cas ne remplace pas les preuves de bout
    # en bout des groupes timezone, hostname et logging — il couvre les deux
    # scripts dont le chemin confirm() est hors d'atteinte dans un conteneur,
    # configure-swap.sh et update-system.sh.
    local reponse=1
    export ASSUME_YES="true"
    confirm "question de test" >/dev/null 2>&1 </dev/null && reponse=0
    unset ASSUME_YES
    verdict "$reponse" "confirm() accepte une ASSUME_YES exportée" "confirm() a répondu non"

    # Et sans elle, il refuse dès que l'entrée standard est fermée : c'est le
    # comportement qui rend les cas « sans -y » observables.
    reponse=0
    confirm "question de test" >/dev/null 2>&1 </dev/null || reponse=1
    verdict "$([ "$reponse" -eq 1 ] && echo 0 || echo 1)" \
        "confirm() refuse sans ASSUME_YES et sans réponse" "confirm() a répondu oui"
}

# ===================================================================
# Aiguillage
# ===================================================================
GROUPE="${1:-}"
[ -n "$GROUPE" ] || die "Usage : TASK-011-cas-conteneur.sh <groupe>" 2

case "$GROUPE" in
    preflight)      groupe_preflight ;;
    aide)           groupe_aide ;;
    dry-run)        groupe_dry_run ;;
    regex)          groupe_regex ;;
    swap-fstab)     groupe_swap_fstab ;;
    timezone)       groupe_timezone ;;
    hostname)       groupe_hostname ;;
    hosts-existant) groupe_hosts_existant ;;
    logging)        groupe_logging ;;
    update)         groupe_update ;;
    enfants)        groupe_enfants ;;
    *)              die "Groupe inconnu : $GROUPE" 2 ;;
esac

printf 'FIN|%s|%s\n' "$GROUPE" "$VERIFICATIONS"
