#!/usr/bin/env bash
# tests/environment/systemd.test.sh — les scripts de Linux/System face à un init réel.
#
# Ce que ce fichier prouve, et que RIEN dans le dépôt ne prouvait avant lui :
#
#   - systemd répond réellement dans le conteneur — PID 1, inventaire des
#     unités, activation d'un service par le bus ;
#   - configure-timezone.sh applique le fuseau PAR TIMEDATECTL, et non par son
#     repli /etc/localtime. Le niveau « integration » n'éprouve que le repli,
#     faute d'init : c'est le cas déclaré NON EXÉCUTÉ dans
#     tests/integration/linux-system.test.sh §5 depuis ADR-0001 ;
#   - configure-hostname.sh change RÉELLEMENT le nom de la machine, par
#     hostname(1) — l'autre cas §5 du même fichier, que le profil debian
#     laissait hors de portée faute de CAP_SYS_ADMIN.
#
# ---------------------------------------------------------------------------
# La garde éprouve systemd, jamais le nom du profil
# ---------------------------------------------------------------------------
#
# Aucun groupe n'est conditionné à « --profil systemd » : le nom d'un profil ne
# prouve rien, et un profil futur qui porterait un init différent doit voir ces
# cas s'exécuter sans qu'on retouche ce fichier. La condition est MESURÉE — le
# PID 1 s'appelle systemd, et « systemctl is-system-running » rend un état de
# marche. « running » et « degraded » valent tous deux : degraded signifie
# qu'une unité a échoué, ce qui est banal en conteneur ; « offline » et
# « unknown » disent que rien ne répond.
#
# ---------------------------------------------------------------------------
# Ce fichier garde des cas exécutables SANS systemd, et c'est délibéré
# ---------------------------------------------------------------------------
#
# « tests/run.sh » sans argument passe par le niveau « environment », y compris
# sous le profil debian où systemd n'est pas. Un fichier qui n'y ferait que
# sauter sortirait en 3 — rien n'est prouvé — et la commande de référence du
# dépôt cesserait d'être verte. Le groupe 1 s'exécute donc partout : il ne
# dépend d'aucun init, et il sert en outre de GARDE DE CONTRASTE aux groupes
# suivants — si les scripts ne démarraient plus du tout, on le saurait ici avant
# de conclure quoi que ce soit sur systemd.
#
# ---------------------------------------------------------------------------
# CE FICHIER MODIFIE LE SYSTÈME
# ---------------------------------------------------------------------------
#
# Il change le fuseau horaire, le nom d'hôte, /etc/hostname et /etc/hosts. Il
# n'écrit rien tant qu'il n'a pas reconnu un système jetable (conteneur Docker,
# ou MGNET_TEST_JETABLE=1) : ailleurs, les groupes modifiants se déclarent NON
# EXÉCUTÉS.
#
#   tests/env/run-in-container.sh --profil systemd -- tests/run.sh environment
#
# Chaque groupe modifiant restitue l'état de départ et VÉRIFIE sa restitution :
# le fuseau d'origine est reposé, le nom d'hôte remis, /etc/hosts restauré et
# les sauvegardes déposées par le script retirées.
#
# ---------------------------------------------------------------------------
# Comment l'idempotence est prouvée ici
# ---------------------------------------------------------------------------
#
#   empreinte P0 -> exécution 1 -> empreinte A -> exécution 2 -> empreinte B
#
# Protocole de tests/integration/, garde comprise : « A == B » ne suffit pas.
# Sur un système déjà conforme, les deux exécutions ne feraient rien, les trois
# empreintes seraient égales, et le test passerait sans rien prouver. Chaque cas
# exige donc AUSSI « P0 != A ». La préparation force l'état de départ à être
# différent de l'état visé, et son échec fait sauter le groupe plutôt que de le
# laisser passer à vide.
#
# L'empreinte est CIBLÉE — fuseau d'un côté, nom d'hôte de l'autre — là où
# tests/integration/ relève tout /etc. Deux raisons : l'état éprouvé ici n'est
# pas seulement un fichier, c'est ce que systemd lui-même rapporte
# (« timedatectl show »), qu'aucun relevé de /etc ne montre ; et systemd écrit
# dans /etc de son propre chef au démarrage, ce qui bruiterait un relevé global.
#
# Ce fichier partage son conteneur avec les autres fichiers du niveau — docker
# n'est pas disponible à l'intérieur pour en créer d'autres. Les deux groupes
# modifiants portent sur des états DISJOINTS : le fuseau (/etc/localtime,
# /etc/timezone) d'un côté, le nom d'hôte (/etc/hostname, /etc/hosts) de
# l'autre. Aucun ne peut fausser l'empreinte de l'autre.
#
# ---------------------------------------------------------------------------
# Ce que ce profil ne permet pas, et qui est déclaré NON EXÉCUTÉ (groupe 5)
# ---------------------------------------------------------------------------
#
#   - hostnamectl set-hostname : /etc/hostname est un bind-mount Docker, et
#     hostnamectl procède par remplacement du fichier — « Device or resource
#     busy ». C'est structurel, aucune option de lancement n'y change rien ;
#   - le rechargement d'une planification par un démon cron : cron n'est pas
#     dans l'image, qui n'embarque aucun service applicatif.

set -Eeuo pipefail

_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_dir/lib/common.sh" ] && [ "$_dir" != "/" ]; do _dir="$(dirname "$_dir")"; done
source "$_dir/lib/common.sh"
# shellcheck source=/dev/null
source "$SCRIPTS_ROOT/tests/lib/assert.sh"

TIMEZONE_SH="$SCRIPTS_ROOT/Linux/System/configure-timezone.sh"
HOSTNAME_SH="$SCRIPTS_ROOT/Linux/System/configure-hostname.sh"

REPERTOIRE_FUSEAUX="/usr/share/zoneinfo"

# Fuseau visé par le cas nominal, et fuseau de départ que la préparation force.
# Les deux doivent différer, sans quoi la garde « P0 != A » ne pourrait pas
# tenir : le script n'aurait rien à faire.
FUSEAU_VISE="Europe/Paris"
FUSEAU_DEPART="Etc/UTC"

# Nom d'hôte témoin. Le PID du fichier de cas le rend unique d'une exécution à
# l'autre : lettres, chiffres et tirets uniquement, ce que valider_nom() accepte.
NOM_VISE="mgnet-env-$$"

REP_TMP="$(mktemp -d)"
F_OUT="$REP_TMP/stdout"
F_ERR="$REP_TMP/stderr"
CODE=0

# Renseignées par les groupes modifiants, relues par le filet posé sur EXIT. Un
# test interrompu ne doit pas laisser le conteneur sous un nom d'hôte de test ni
# amputé de son /etc/hosts.
HOSTS_SAUVEGARDE=""
NOM_ORIGINE=""
FUSEAU_ORIGINE=""

filet_de_securite() {
    local code="$?"
    if [ -n "$HOSTS_SAUVEGARDE" ] && [ -f "$HOSTS_SAUVEGARDE" ]; then
        cat "$HOSTS_SAUVEGARDE" > /etc/hosts 2>/dev/null || true
    fi
    if [ -n "$NOM_ORIGINE" ]; then
        hostname "$NOM_ORIGINE" 2>/dev/null || true
        printf '%s\n' "$NOM_ORIGINE" > /etc/hostname 2>/dev/null || true
    fi
    if [ -n "$FUSEAU_ORIGINE" ] && command -v timedatectl >/dev/null 2>&1; then
        timedatectl set-timezone "$FUSEAU_ORIGINE" 2>/dev/null || true
    fi
    rm -rf "$REP_TMP"
    return "$code"
}
trap filet_de_securite EXIT

# ===================================================================
# Outillage
# ===================================================================

# lancer <commande...> — exécute dans un SOUS-SHELL et capture le code.
#
# Le sous-shell est indispensable : les scripts posent « set -Eeuo pipefail » et
# lib/common.sh un « trap ERR ». Un « die … 2 » tuerait le harnais s'il n'était
# pas isolé. L'entrée standard est fermée : confirm() lit alors une réponse vide
# et refuse, ce qui rend observable le chemin « sans -y ».
lancer() {
    CODE=0
    ( "$@" ) >"$F_OUT" 2>"$F_ERR" </dev/null || CODE=$?
}

sortie() { cat "$F_OUT"; }
erreur() { cat "$F_ERR"; }

# Les messages du dépôt partent sur stderr (info, warn, success) ; la sortie
# utile d'un script — la liste des fuseaux — part sur stdout. Les cas qui
# cherchent un message lisent donc les deux, sans supposer lequel le porte.
les_deux_flux() { cat "$F_OUT" "$F_ERR"; }

# empreinte_fuseau <destination> — l'état du fuseau sous ses TROIS formes.
#
# La première ligne est celle qui n'existe pas sans systemd, et c'est tout
# l'objet de ce fichier : ce que le démon lui-même rapporte. Les deux autres
# sont les fichiers, que le repli du script maintient aussi.
empreinte_fuseau() {
    local destination="$1"
    {
        printf 'timedatectl : %s\n' "$(timedatectl show -p Timezone --value 2>/dev/null || true)"
        printf '/etc/timezone : %s\n' "$(tr -d '[:space:]' < /etc/timezone 2>/dev/null || true)"
        printf '/etc/localtime -> %s\n' "$(readlink -f /etc/localtime 2>/dev/null || true)"
    } > "$destination"
}

# empreinte_nom <destination> — l'état du nom d'hôte sous ses trois formes.
empreinte_nom() {
    local destination="$1"
    {
        printf 'hostname(1) : %s\n' "$(hostname 2>/dev/null || true)"
        printf '/etc/hostname : %s\n' "$(tr -d '[:space:]' < /etc/hostname 2>/dev/null || true)"
        printf '/etc/hosts 127.0.1.1 : %s\n' \
            "$(grep -E '^[[:space:]]*127\.0\.1\.1[[:space:]]' /etc/hosts 2>/dev/null || true)"
    } > "$destination"
}

# assert_empreinte_egale <avant> <après> <libellé>
assert_empreinte_egale() {
    local avant="$1" apres="$2" libelle="$3"
    if diff -u "$avant" "$apres" > "$REP_TMP/diff" 2>&1; then
        ok "$libelle"
    else
        ko "$libelle" "$(tr '\n' '|' < "$REP_TMP/diff")"
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

# assert_l_un_des_deux <texte> <motif A> <motif B> <libellé>
# Pour un chemin d'exécution dont on exige qu'il soit ANNONCÉ, sans figer lequel
# des deux replis du script a été emprunté : le fait — le nom a changé — est
# éprouvé séparément, par une lecture indépendante du script.
assert_l_un_des_deux() {
    local texte="$1" motif_a="$2" motif_b="$3" libelle="$4"
    if contient "$texte" "$motif_a" || contient "$texte" "$motif_b"; then
        ok "$libelle"
    else
        ko "$libelle" "aucun des deux motifs : « $motif_a » ni « $motif_b »"
    fi
}

# ===================================================================
# 0. Reconnaissance de l'environnement
# ===================================================================
titre "0. Environnement"

EST_LINUX="false"
if [ "$(uname -s 2>/dev/null)" = "Linux" ]; then
    EST_LINUX="true"
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

# La MESURE de systemd, jamais le nom du profil. Deux sources indépendantes : ce
# que le noyau dit du PID 1, et ce que le manager dit de lui-même. La seconde
# seule ne suffirait pas — un systemctl présent sans init répond « offline ».
INIT_PID1="$(cat /proc/1/comm 2>/dev/null || true)"

ETAT_SYSTEME=""
if command -v systemctl >/dev/null 2>&1; then
    ETAT_SYSTEME="$(systemctl is-system-running 2>/dev/null || true)"
fi

SYSTEMD="non"
case "$ETAT_SYSTEME" in
    running|degraded|starting|maintenance)
        if [ "$INIT_PID1" = "systemd" ]; then
            SYSTEMD="oui"
        fi
        ;;
esac

info "Linux : $EST_LINUX — root : $EST_ROOT — jetable : $JETABLE"
info "PID 1 : « ${INIT_PID1:-inconnu} » — is-system-running : « ${ETAT_SYSTEME:-aucune réponse} » — systemd : $SYSTEMD"

if [ "$EST_LINUX" != "true" ]; then
    saute "l'ensemble des cas du niveau environment" \
        "cet hôte n'est pas un Linux — ces scripts ne s'y exécutent pas"
    bilan "environment / systemd"
    exit 0
fi

for script in "$TIMEZONE_SH" "$HOSTNAME_SH"; do
    if [ ! -f "$script" ]; then
        saute "l'ensemble des cas du niveau environment" "$script est introuvable"
        bilan "environment / systemd"
        exit 0
    fi
done

# Raison unique des sauts liés à l'absence d'init, calculée une fois : un NON
# EXÉCUTÉ sans motif ne renseigne personne. Elle nomme ce qui a été MESURÉ, et
# non le profil — c'est la même phrase qui vaudra pour tout environnement sans
# init.
SANS_SYSTEMD="aucun init : le PID 1 est « ${INIT_PID1:-inconnu} » et « systemctl is-system-running » rend « ${ETAT_SYSTEME:-aucune réponse} » — ce n'est pas une lacune de l'image, un init tient au mode de lancement du conteneur"

# Les groupes modifiants exigent en plus le privilège et un système jetable.
MODIFIANT="oui"
if [ "$SYSTEMD" != "oui" ]; then
    MODIFIANT="$SANS_SYSTEMD"
elif [ "$EST_ROOT" != "true" ]; then
    MODIFIANT="require_root arrête ces scripts avant toute écriture"
elif [ "$JETABLE" != "true" ]; then
    MODIFIANT="cet hôte n'est pas un système jetable — ni le fuseau ni le nom d'hôte ne seront touchés"
fi

# saute_modifiant <libellé> — saut d'un cas des groupes 3 et 4, QUALIFIÉ selon
# ce qui manque.
#
# L'absence d'init est une limite PAR NATURE : un profil sans PID 1 systemd ne
# rendra jamais ces cas atteignables, et c'est l'exemple canonique que
# tests/README.md §2 donne de cette qualification. Le manque de privilège ou un
# système non jetable, eux, sont des propriétés de la MACHINE courante — ils
# tombent ailleurs sur une autre machine — et n'autorisent que le saut neutre.
saute_modifiant() {
    if [ "$MODIFIANT" = "$SANS_SYSTEMD" ]; then
        saute_par_nature "$1" "$MODIFIANT"
    else
        saute "$1" "$MODIFIANT"
    fi
}

# ===================================================================
# 1. Ce qui ne dépend d'aucun init
# ===================================================================
# Ce groupe s'exécute sous TOUS les profils. Il tient le niveau à flot sous le
# profil debian — sans au moins une réussite, le fichier sortirait en 3 — et il
# sert de garde de contraste : si les deux scripts ne démarraient plus, les
# sauts des groupes suivants ne pourraient plus être lus comme « seul systemd
# manque ».
titre "1. Ce qui ne dépend d'aucun init"

lancer bash "$TIMEZONE_SH" --help
assert_code 0 "$CODE" "configure-timezone.sh --help"
assert_contient "$(les_deux_flux)" "Usage : configure-timezone.sh" \
    "configure-timezone.sh --help affiche son usage"

lancer bash "$TIMEZONE_SH" --option-inconnue
assert_code 2 "$CODE" "configure-timezone.sh --option-inconnue"
assert_contient "$(erreur)" "[ERROR] Option inconnue : --option-inconnue" \
    "configure-timezone.sh nomme l'option refusée"

lancer bash "$HOSTNAME_SH" --help
assert_code 0 "$CODE" "configure-hostname.sh --help"
assert_contient "$(les_deux_flux)" "Usage : configure-hostname.sh" \
    "configure-hostname.sh --help affiche son usage"

lancer bash "$HOSTNAME_SH" --option-inconnue
assert_code 2 "$CODE" "configure-hostname.sh --option-inconnue"
assert_contient "$(erreur)" "[ERROR] Option inconnue : --option-inconnue" \
    "configure-hostname.sh nomme l'option refusée"

# --list emprunte timedatectl quand il répond, et le parcours de zoneinfo sinon.
# Les deux chemins doivent rendre la même chose de l'appelant : une liste utile.
# Ce cas ne discrimine PAS lequel a servi — les deux listes se ressemblent trop
# pour qu'une assertion honnête le prétende. Ce qu'il verrouille est le contrat
# de sortie, sous l'un comme sous l'autre.
if [ "$SYSTEMD" != "oui" ] && [ ! -d "$REPERTOIRE_FUSEAUX" ]; then
    saute_par_nature "configure-timezone.sh --list rend une liste utilisable" \
        "ni timedatectl ni $REPERTOIRE_FUSEAUX — aucune des deux sources n'existe ici"
else
    lancer bash "$TIMEZONE_SH" --list
    assert_code 0 "$CODE" "configure-timezone.sh --list"
    assert_contient "$(sortie)" "Europe/Paris" \
        "configure-timezone.sh --list contient un fuseau connu"
    assert_absent "$(sortie)" "posix/" \
        "configure-timezone.sh --list écarte les répertoires techniques de zoneinfo"
    assert_absent "$(sortie)" ".tab" \
        "configure-timezone.sh --list écarte les tables de zoneinfo"
fi

# ===================================================================
# 2. systemd répond réellement
# ===================================================================
# Le profil n'apporte rien tant que ceci n'est pas vrai. Ces cas ne portent sur
# aucun script du dépôt : ils établissent la prémisse sur laquelle les groupes 3
# et 4 s'appuient. Sans eux, un groupe 3 vert sur un système à demi démarré ne
# voudrait rien dire.
titre "2. systemd répond réellement"

if [ "$SYSTEMD" != "oui" ]; then
    saute_par_nature "le PID 1 est systemd" "$SANS_SYSTEMD"
    saute_par_nature "systemctl inventorie les unités" "$SANS_SYSTEMD"
    saute_par_nature "timedatectl lit le fuseau courant" "$SANS_SYSTEMD"
    saute_par_nature "hostnamectl lit le nom statique" "$SANS_SYSTEMD"
    saute_par_nature "le bus active un service à la demande" "$SANS_SYSTEMD"
else
    assert_egal "systemd" "$INIT_PID1" "le PID 1 du conteneur est systemd"

    # « running » et « degraded » valent tous deux — voir l'en-tête. Ce qui est
    # refusé est « offline » et « unknown » : là, rien ne répond.
    case "$ETAT_SYSTEME" in
        running|degraded)
            ok "systemctl is-system-running rend un état de marche — « $ETAT_SYSTEME »" ;;
        *)
            ko "systemctl is-system-running rend un état de marche" \
                "état « ${ETAT_SYSTEME:-aucune réponse} »" ;;
    esac

    lancer systemctl list-units --type=service --no-pager
    assert_code 0 "$CODE" "systemctl list-units --type=service"
    assert_contient "$(sortie)" ".service" \
        "l'inventaire des unités nomme au moins un service"

    # L'inventaire des unités en échec doit ABOUTIR ; son contenu n'est pas
    # contraint. Une unité échouée en conteneur est banale — c'est ce que
    # « degraded » signifie — et l'exiger vide rendrait le profil inutilisable.
    lancer systemctl list-units --failed --no-legend --no-pager
    assert_code 0 "$CODE" "systemctl list-units --failed aboutit"

    lancer timedatectl show -p Timezone --value
    assert_code 0 "$CODE" "timedatectl lit le fuseau courant"
    assert_non_vide "$(sortie)" "timedatectl rend un fuseau"

    lancer hostnamectl --static
    assert_code 0 "$CODE" "hostnamectl lit le nom statique"
    assert_non_vide "$(sortie)" "hostnamectl rend un nom statique"

    # systemd-timedated n'est pas lancé au démarrage : il est activé PAR LE BUS
    # au premier appel de timedatectl. Le constater prouve la chaîne complète —
    # dbus, l'activation à la demande, le service — et non la seule présence
    # d'un binaire. C'est précisément ce que le profil debian ne peut pas avoir.
    lancer systemctl is-active systemd-timedated.service
    assert_egal "active" "$(sortie | tr -d '[:space:]')" \
        "le bus a activé systemd-timedated au premier appel de timedatectl"
fi

# ===================================================================
# 3. configure-timezone.sh applique le fuseau PAR TIMEDATECTL
# ===================================================================
# Le cas que tests/integration/linux-system.test.sh §5 déclarait NON EXÉCUTÉ.
# Sous le profil debian, seul le repli /etc/localtime est emprunté ; ici, la
# branche timedatectl l'est, et l'assertion d'ABSENCE du message de repli est ce
# qui distingue les deux.
titre "3. configure-timezone.sh par timedatectl"

if [ "$MODIFIANT" != "oui" ]; then
    saute_modifiant "configure-timezone.sh applique le fuseau par timedatectl"
    saute_modifiant "configure-timezone.sh : le fuseau est réellement appliqué, les trois sources concordent"
    saute_modifiant "configure-timezone.sh exécuté deux fois de suite ne change rien la seconde"
elif [ ! -f "$REPERTOIRE_FUSEAUX/$FUSEAU_VISE" ] || [ ! -f "$REPERTOIRE_FUSEAUX/$FUSEAU_DEPART" ]; then
    saute_par_nature "les trois cas de fuseau" \
        "« $FUSEAU_VISE » ou « $FUSEAU_DEPART » manque à $REPERTOIRE_FUSEAUX — l'image n'embarque pas ces données"
else
    FUSEAU_ORIGINE="$(timedatectl show -p Timezone --value 2>/dev/null || true)"

    # Préparation : partir d'un fuseau DIFFÉRENT de celui qu'on va demander.
    # Sans elle, un système déjà à l'heure de Paris rendrait « Rien à faire » et
    # la garde « P0 != A » tomberait — pour la mauvaise raison.
    PREPARATION="ok"
    if ! timedatectl set-timezone "$FUSEAU_DEPART" 2>"$REP_TMP/preparation"; then
        PREPARATION="échec"
    elif [ "$(timedatectl show -p Timezone --value 2>/dev/null || true)" != "$FUSEAU_DEPART" ]; then
        PREPARATION="échec"
    fi

    if [ "$PREPARATION" != "ok" ]; then
        # L'environnement a manqué : la preuve existe et serait produite
        # ailleurs. Une indisponibilité, donc, et le fichier sortira en 3.
        RAISON_PREP="timedatectl set-timezone $FUSEAU_DEPART n'a pas abouti : $(tr '\n' ' ' < "$REP_TMP/preparation")"
        saute_indisponible "configure-timezone.sh applique le fuseau par timedatectl" "$RAISON_PREP"
        saute_indisponible "configure-timezone.sh : le fuseau est réellement appliqué, les trois sources concordent" "$RAISON_PREP"
        saute_indisponible "configure-timezone.sh exécuté deux fois de suite ne change rien la seconde" "$RAISON_PREP"
    else
        empreinte_fuseau "$REP_TMP/fuseau.P0"

        lancer bash "$TIMEZONE_SH" "$FUSEAU_VISE" -y
        assert_code 0 "$CODE" "configure-timezone.sh $FUSEAU_VISE -y"
        assert_contient "$(erreur)" "[INFO] Fuseau défini via timedatectl." \
            "le fuseau est posé par timedatectl, la branche que le profil debian n'atteint pas"
        assert_absent "$(erreur)" "[INFO] Fuseau défini via /etc/localtime." \
            "le repli /etc/localtime n'est PAS emprunté quand timedatectl répond"
        assert_contient "$(erreur)" "[SUCCESS] Fuseau horaire configuré : $FUSEAU_VISE" \
            "le script conclut sur le fuseau demandé"

        # Preuve INDÉPENDANTE du script : c'est systemd qu'on interroge, pas le
        # message que le script a bien voulu écrire.
        assert_egal "$FUSEAU_VISE" "$(timedatectl show -p Timezone --value 2>/dev/null || true)" \
            "systemd rapporte le fuseau demandé"
        assert_egal "$FUSEAU_VISE" "$(tr -d '[:space:]' < /etc/timezone 2>/dev/null || true)" \
            "/etc/timezone est mis en cohérence — timedatectl ne le maintient pas"
        if cmp -s /etc/localtime "$REPERTOIRE_FUSEAUX/$FUSEAU_VISE"; then
            ok "/etc/localtime porte bien les données de « $FUSEAU_VISE »"
        else
            ko "/etc/localtime porte bien les données de « $FUSEAU_VISE »" \
                "le contenu diffère de $REPERTOIRE_FUSEAUX/$FUSEAU_VISE"
        fi

        empreinte_fuseau "$REP_TMP/fuseau.A"
        assert_empreinte_differente "$REP_TMP/fuseau.P0" "$REP_TMP/fuseau.A" \
            "la première exécution a réellement changé le fuseau (garde P0 != A)"

        lancer bash "$TIMEZONE_SH" "$FUSEAU_VISE" -y
        assert_code 0 "$CODE" "configure-timezone.sh $FUSEAU_VISE -y, seconde exécution"
        assert_contient "$(erreur)" "[SUCCESS] Rien à faire : le fuseau est déjà « $FUSEAU_VISE »." \
            "la seconde exécution constate que le fuseau est déjà en place"

        empreinte_fuseau "$REP_TMP/fuseau.B"
        assert_empreinte_egale "$REP_TMP/fuseau.A" "$REP_TMP/fuseau.B" \
            "la seconde exécution ne change rien (A == B)"

        # Restitution, et vérification de la restitution : le trap EXIT n'est
        # qu'un filet, il ne rend compte de rien.
        if [ -n "$FUSEAU_ORIGINE" ]; then
            timedatectl set-timezone "$FUSEAU_ORIGINE" 2>/dev/null || true
            assert_egal "$FUSEAU_ORIGINE" "$(timedatectl show -p Timezone --value 2>/dev/null || true)" \
                "restitution : le fuseau d'origine est reposé"
            FUSEAU_ORIGINE=""
        fi
    fi
fi

# ===================================================================
# 4. configure-hostname.sh change RÉELLEMENT le nom de la machine
# ===================================================================
# L'autre cas §5 de tests/integration/linux-system.test.sh. Le chemin emprunté
# ici est hostname(1) : hostnamectl échoue dans ce conteneur, et la raison est
# déclarée au groupe 5. Ce que ce groupe prouve n'en est pas amoindri — le nom
# d'hôte change pour de bon, ce qu'aucune exécution du niveau integration ne
# pouvait montrer, CAP_SYS_ADMIN y étant refusé.
titre "4. configure-hostname.sh change réellement le nom"

if [ "$MODIFIANT" != "oui" ]; then
    saute_modifiant "configure-hostname.sh change réellement le nom de la machine"
    saute_modifiant "configure-hostname.sh : /etc/hostname et /etc/hosts suivent"
    saute_modifiant "configure-hostname.sh exécuté deux fois de suite ne change rien la seconde"
else
    NOM_ORIGINE="$(hostname 2>/dev/null || true)"
    HOSTS_SAUVEGARDE="$REP_TMP/hosts.origine"
    cat /etc/hosts > "$HOSTS_SAUVEGARDE"
    find /etc -maxdepth 1 -name 'hosts.bak-*' 2>/dev/null | sort > "$REP_TMP/bak.avant"

    if [ -z "$NOM_ORIGINE" ] || [ "$NOM_ORIGINE" = "$NOM_VISE" ]; then
        RAISON_NOM="le nom courant est « ${NOM_ORIGINE:-illisible} » — impossible d'établir un départ distinct du nom visé"
        saute_indisponible "configure-hostname.sh change réellement le nom de la machine" "$RAISON_NOM"
        saute_indisponible "configure-hostname.sh : /etc/hostname et /etc/hosts suivent" "$RAISON_NOM"
        saute_indisponible "configure-hostname.sh exécuté deux fois de suite ne change rien la seconde" "$RAISON_NOM"
    else
        empreinte_nom "$REP_TMP/nom.P0"

        lancer bash "$HOSTNAME_SH" "$NOM_VISE" -y
        assert_code 0 "$CODE" "configure-hostname.sh $NOM_VISE -y"

        # Le FAIT — le nom a changé — est éprouvé par une lecture indépendante
        # du script. Le CHEMIN emprunté est éprouvé à part, et sans exiger
        # lequel des deux : hostnamectl échoue ici (groupe 5), mais un
        # environnement où il aboutirait resterait conforme au contrat.
        assert_egal "$NOM_VISE" "$(hostname 2>/dev/null || true)" \
            "le nom d'hôte de la machine est réellement devenu « $NOM_VISE »"
        assert_l_un_des_deux "$(erreur)" \
            "[INFO] Nom d'hôte défini via hostnamectl." \
            "[INFO] Nom d'hôte défini via hostname et /etc/hostname." \
            "le script annonce par quel chemin le nom a été posé"
        assert_contient "$(erreur)" "[SUCCESS] Nom d'hôte configuré : $NOM_VISE" \
            "le script conclut sur le nom demandé"

        assert_egal "$NOM_VISE" "$(tr -d '[:space:]' < /etc/hostname 2>/dev/null || true)" \
            "/etc/hostname porte le nom demandé"
        assert_contient "$(grep -E '^[[:space:]]*127\.0\.1\.1[[:space:]]' /etc/hosts || true)" \
            "$NOM_VISE" "/etc/hosts résout le nom sur 127.0.1.1"

        empreinte_nom "$REP_TMP/nom.A"
        assert_empreinte_differente "$REP_TMP/nom.P0" "$REP_TMP/nom.A" \
            "la première exécution a réellement changé le nom (garde P0 != A)"

        lancer bash "$HOSTNAME_SH" "$NOM_VISE" -y
        assert_code 0 "$CODE" "configure-hostname.sh $NOM_VISE -y, seconde exécution"
        assert_contient "$(erreur)" "[SUCCESS] Rien à faire : le nom d'hôte et /etc/hosts sont déjà conformes." \
            "la seconde exécution constate que tout est déjà conforme"

        empreinte_nom "$REP_TMP/nom.B"
        assert_empreinte_egale "$REP_TMP/nom.A" "$REP_TMP/nom.B" \
            "la seconde exécution ne change rien (A == B)"

        # Restitution : nom d'hôte, /etc/hostname, /etc/hosts, et les
        # sauvegardes que le script a déposées.
        hostname "$NOM_ORIGINE" 2>/dev/null || true
        printf '%s\n' "$NOM_ORIGINE" > /etc/hostname
        cat "$HOSTS_SAUVEGARDE" > /etc/hosts
        find /etc -maxdepth 1 -name 'hosts.bak-*' 2>/dev/null | sort > "$REP_TMP/bak.apres"
        while IFS= read -r fichier; do
            [ -n "$fichier" ] || continue
            rm -f "$fichier"
        done < <(comm -13 "$REP_TMP/bak.avant" "$REP_TMP/bak.apres")

        assert_egal "$NOM_ORIGINE" "$(hostname 2>/dev/null || true)" \
            "restitution : le nom d'hôte d'origine est remis"
        if cmp -s "$HOSTS_SAUVEGARDE" /etc/hosts; then
            ok "restitution : /etc/hosts porte exactement ce qu'il portait à l'entrée du groupe"
        else
            ko "restitution : /etc/hosts porte exactement ce qu'il portait à l'entrée du groupe" \
                "le fichier diffère de l'état relevé à l'entrée"
        fi
        assert_egal "$(wc -l < "$REP_TMP/bak.avant" | tr -d ' ')" \
            "$(find /etc -maxdepth 1 -name 'hosts.bak-*' 2>/dev/null | wc -l | tr -d ' ')" \
            "restitution : les sauvegardes de /etc/hosts déposées par ce groupe sont retirées"

        HOSTS_SAUVEGARDE=""
        NOM_ORIGINE=""
    fi
fi

# ===================================================================
# 5. Hors de portée de cet environnement
# ===================================================================
# Ces lignes ne sont pas des cas manqués : ce sont des cas dont on sait qu'ils
# ne peuvent pas être joués ici. Les taire ferait croire à une couverture
# complète.
titre "5. Hors de portée de cet environnement"

# La cause est MESURÉE et non supposée : si /etc/hostname est un point de
# montage, hostnamectl ne peut pas le remplacer, et c'est structurel — Docker
# monte ce fichier depuis l'hôte pour tout conteneur, quelles que soient les
# options de lancement. La raison affichée dit ce qui a été relevé, et ne
# prétend rien de plus si le montage n'y est pas.
MONTAGE_HOSTNAME="$(grep ' /etc/hostname ' /proc/mounts 2>/dev/null || true)"
if ! command -v hostnamectl >/dev/null 2>&1; then
    CAUSE_HOSTNAMECTL="hostnamectl est absent de cet environnement — la commande n'y existe pas, le script emprunte son repli sans jamais l'essayer"
    QUALIFICATION_HOSTNAMECTL="par_nature"
elif [ -n "$MONTAGE_HOSTNAME" ]; then
    CAUSE_HOSTNAMECTL="/etc/hostname est un bind-mount Docker — /proc/mounts : « $MONTAGE_HOSTNAME ». hostnamectl procède par remplacement du fichier et échoue sur « Device or resource busy » ; c'est structurel, aucune option de lancement n'y change rien. Le chemin hostname(1) est éprouvé au groupe 4"
    QUALIFICATION_HOSTNAMECTL="par_nature"
else
    CAUSE_HOSTNAMECTL="hostnamectl set-hostname n'aboutit pas dans ce conteneur ; aucun montage sur /etc/hostname n'a été relevé dans /proc/mounts — la cause reste à établir. Le chemin hostname(1) est éprouvé au groupe 4"
    QUALIFICATION_HOSTNAMECTL="neutre"
fi

# Le saut n'est déclaré NON APPLICABLE PAR NATURE que là où la cause est
# établie : commande absente, ou fichier tenu par un montage. Sur la troisième
# branche, on constate l'échec sans en connaître la raison — qualifier cette
# ignorance de « limite structurelle » affirmerait précisément ce qu'on
# reconnaît ne pas savoir. Un saut neutre y dit le vrai.
if [ "$QUALIFICATION_HOSTNAMECTL" = "par_nature" ]; then
    saute_par_nature "configure-hostname.sh posant le nom PAR HOSTNAMECTL" "$CAUSE_HOSTNAMECTL"
else
    saute "configure-hostname.sh posant le nom PAR HOSTNAMECTL" "$CAUSE_HOSTNAMECTL"
fi

# cron n'est pas dans l'image du profil : celle-ci n'embarque aucun service
# applicatif, par construction. C'est le pendant, pour ce niveau, du saut resté
# dans tests/integration/configure-cron.test.sh §9.
if command -v cron >/dev/null 2>&1 || [ -x /usr/sbin/cron ]; then
    # Le binaire peut être là sans qu'aucun démon ne tourne — le niveau
    # integration installe le paquet dans le conteneur qu'il partage. Ce qui
    # manque au cas n'est pas la commande, c'est le SERVICE.
    if [ "$SYSTEMD" = "oui" ] \
       && [ "$(systemctl is-active cron.service 2>/dev/null || true)" = "active" ]; then
        saute "le rechargement d'une planification par un démon cron en service" \
            "un démon cron tourne ici : le cas est devenu atteignable, la preuve reste à écrire"
    else
        saute "le rechargement d'une planification par un démon cron en service" \
            "le binaire cron est présent, mais aucun démon ne tourne dans cet environnement — c'est le service, pas la commande, qui manque au cas"
    fi
else
    saute_par_nature "le rechargement d'une planification par un démon cron en service" \
        "cron est absent de l'image de ce profil, qui n'embarque aucun service applicatif — l'y ajouter est une décision d'image, pas une lacune de ce fichier de cas"
fi

# AVERTISSEMENT, et non saut : aucun script du dépôt ne redémarre la machine
# aujourd'hui, donc aucun cas ne manque ici. Le jour où l'un le fera, il ne
# pourra pas être éprouvé dans ce profil — « reboot » et « systemctl poweroff »
# arrêtent le PID 1, donc le conteneur, et décapitent la suite en cours. Un
# NON EXÉCUTÉ affiché à chaque exécution pour un cas que personne n'attend
# serait du bruit, et le bruit finit par masquer les sauts qui comptent
# (tests/README.md §2).

# ===================================================================
# 6. Nettoyage
# ===================================================================
titre "6. Nettoyage"

rm -rf "$REP_TMP"
if [ -e "$REP_TMP" ]; then
    ko "le répertoire jetable du fichier de cas est supprimé" "$REP_TMP subsiste"
else
    ok "le répertoire jetable du fichier de cas est supprimé"
fi

bilan "environment / systemd"
