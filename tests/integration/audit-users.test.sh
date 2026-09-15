#!/usr/bin/env bash
set -Eeuo pipefail
# tests/integration/audit-users.test.sh — Linux/Security/audit-users.sh (TASK-041).
# getent est remplacé par un faux binaire en tête de PATH, /etc/shadow et /etc/shells
# par des fixtures : aucun compte réel n'est touché.
_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_dir/lib/common.sh" ] && [ "$_dir" != "/" ]; do _dir="$(dirname "$_dir")"; done
# shellcheck source=/dev/null
source "$_dir/lib/common.sh"
# shellcheck source=/dev/null
source "$SCRIPTS_ROOT/tests/lib/assert.sh"
CIBLE="$SCRIPTS_ROOT/Linux/Security/audit-users.sh"
REP_TMP="$(mktemp -d)"; chmod 755 "$REP_TMP"
F_OUT="$REP_TMP/stdout"; F_ERR="$REP_TMP/stderr"; CODE=0
trap 'rm -rf "$REP_TMP"' EXIT
lancer() { CODE=0; ( "$@" ) >"$F_OUT" 2>"$F_ERR" </dev/null || CODE=$?; }
sortie() { cat "$F_OUT"; }
erreur() { cat "$F_ERR"; }
# rubrique <n> — les lignes de la rubrique n, sans son titre : « root » doit être
# cherché dans la rubrique des UID 0, pas n'importe où dans le rapport.
rubrique() { awk -v n="$1" '$0 ~ "^" n "[.] " {on=1; next} /^[0-9]+[.] / {on=0} on && NF' "$F_OUT"; }
# sablonner <dest> <binaire exclu> — un PATH de liens SANS ce binaire : le rendre
# fautif ne suffirait pas, « command -v » le trouverait encore.
sablonner() { local d b; mkdir -p "$1"
    for d in /usr/local/sbin /usr/local/bin /usr/sbin /usr/bin /sbin /bin; do
        for b in "$d"/*; do [ "${b##*/}" = "$2" ] || [ -e "$1/${b##*/}" ] || ln -s "$b" "$1/${b##*/}" 2>/dev/null || true; done
    done; }
if [ ! -f "$CIBLE" ]; then
    ko "Linux/Security/audit-users.sh existe" "fichier introuvable : $CIBLE"
    bilan "TASK-041 / audit-users.sh"
fi
if [ "$(uname -s 2>/dev/null || true)" != "Linux" ]; then
    saute_par_nature "l'ensemble des cas d'audit-users.sh" "cet hôte n'est pas un Linux"
    bilan "TASK-041 / audit-users.sh"
fi

titre "1. Aide et refus d'usage"
lancer bash "$CIBLE" --help
assert_code 0 "$CODE" "--help sort en 0"
AIDE="$(sortie)"
for motif in "1. comptes à UID 0" "2. comptes dotés d'un shell de connexion" "3. membres des groupes privilégiés" "4. comptes au mot de passe vide" "Codes de retour" "getent" "FICHIER_SHADOW" "FICHIER_SHELLS" "groupe principal"; do
    assert_contient "$AIDE" "$motif" "--help documente « $motif »"
done
lancer bash "$CIBLE" --nawak
assert_code 2 "$CODE" "une option inconnue sort en 2"
assert_contient "$(erreur)" "Option inconnue : --nawak" "le refus nomme l'option"
assert_egal "" "$(sortie)" "aucun audit n'est produit avant le refus"

titre "2. getent absent — code 1"
SANS_GETENT="$REP_TMP/sans-getent"
sablonner "$SANS_GETENT" getent
if PATH="$SANS_GETENT" command -v getent >/dev/null 2>&1; then ko "garde : getent est masqué dans le bac à sable" "il y reste visible"
else ok "garde : getent est masqué dans le bac à sable"; fi
lancer env "PATH=$SANS_GETENT" bash "$CIBLE"
assert_code 1 "$CODE" "sans getent, le script sort en 1"
assert_contient "$(erreur)" "getent" "le refus nomme la commande manquante"
assert_egal "" "$(sortie)" "sans getent, aucun audit n'est produit"

FAUX="$REP_TMP/bin"; mkdir -p "$FAUX"
# Cas limites : UID 0 autre que root, shells fermés (nologin, false, sync, shutdown, halt),
# un shell hors /etc/shells réel (ksh), deux comptes dont adm est le groupe PRINCIPAL.
cat > "$FAUX/getent" <<'FAUX_GETENT'
#!/bin/sh
case "$1 ${2:-}" in
    "passwd ") printf '%s\n' \
        'root:x:0:0:root:/root:/bin/bash' \
        'daemon:x:1:1:daemon:/usr/sbin:/usr/sbin/nologin' \
        'fauxroot:x:0:0:Faux:/home/fauxroot:/bin/sh' \
        'sync:x:4:65534:sync:/bin:/bin/sync' \
        'service:x:995:995:Service:/var/lib/service:/usr/sbin/nologin' \
        'max:x:1000:4:Max:/home/max:/bin/bash' \
        'ancien:x:1001:1001:Ancien:/home/ancien:/bin/false' \
        'shutdown:x:1002:1002:Arret:/sbin:/sbin/shutdown' \
        'halt:x:1003:4:Arret:/sbin:/sbin/halt' \
        'web:x:1004:1004:Web:/home/web:/bin/ksh' ;;
    "group sudo") printf '%s\n' 'sudo:x:27:max' ;;
    "group adm")  printf '%s\n' 'adm:x:4:root,max' ;;
    "group docker") [ "${PANNE:-}" = oui ] && exit 3; exit 2 ;;
    *) exit 2 ;;
esac
FAUX_GETENT
chmod +x "$FAUX/getent"
F_SHELLS="$REP_TMP/shells"; printf '%s\n' /bin/sh /bin/bash /bin/ksh > "$F_SHELLS"
F_SHADOW="$REP_TMP/shadow"
printf '%s\n' 'root:!!:19000:0:99999:7:::' 'max:!:19000:0:99999:7:::' 'vide::19000:0:99999:7:::' 'service:*:19000:0:99999:7:::' > "$F_SHADOW"

titre "3. L'audit, sur des comptes fixés"
lancer env "PATH=$FAUX:$PATH" FICHIER_SHADOW="$F_SHADOW" FICHIER_SHELLS="$F_SHELLS" bash "$CIBLE"
assert_code 0 "$CODE" "l'audit sort en 0"
S="$(sortie)"; E="$(erreur)"
assert_contient "$E" "[WARN] Compte à UID 0 autre que root : fauxroot" "chaque compte à UID 0 autre que root est signalé en [WARN]"
assert_absent "$E" "autre que root : root" "root n'est pas signalé"
assert_egal "4" "$(rubrique 2 | wc -l | tr -d ' ')" "les quatre comptes à shell de connexion sont listés, un par ligne — dont ksh, hors du /etc/shells réel"
for motif in "root /bin/bash" "fauxroot /bin/sh" "max /bin/bash" "web /bin/ksh" "  sudo : max" "  adm : root" "  adm : max" "  adm : halt" "  docker : groupe absent"; do
    assert_contient "$S" "$motif" "« $motif » est listé"
done
for motif in sync shutdown halt; do assert_absent "$(rubrique 2)" "$motif" "« $motif » n'a pas de shell de connexion : il n'est pas listé"; done
assert_egal "5" "$(printf '%s\n' "$S" | grep -cE '^  (sudo|adm|docker) : ')" "appartenance secondaire, groupe principal, groupe absent : une ligne chacun"
assert_egal "1" "$(printf '%s\n' "$S" | grep -cF '  adm : max')" "un compte à la fois secondaire et principal n'est listé qu'une fois"
for motif in daemon service ancien; do assert_absent "$S" "$motif" "« $motif » n'a pas de shell de connexion : il n'est pas listé"; done
assert_contient "$E" "[WARN] Compte sans mot de passe : vide" "un compte au mot de passe vide est signalé en [WARN]"
assert_contient "$S" "  vide" "le compte sans mot de passe est aussi listé"
for motif in max service; do assert_absent "$E" "sans mot de passe : $motif" "« $motif » n'a pas un champ vide : il n'est pas signalé"; done

titre "4. /etc/shadow illisible — l'audit se poursuit"
lancer env "PATH=$FAUX:$PATH" FICHIER_SHADOW="$REP_TMP/absent" FICHIER_SHELLS="$F_SHELLS" bash "$CIBLE"
assert_code 0 "$CODE" "sans /etc/shadow lisible, le script sort quand même en 0"
assert_contient "$(erreur)" "illisible" "le script dit que le fichier est illisible"
for motif in "1. Comptes à UID 0" "2. Comptes à shell de connexion" "3. Membres des groupes privilégiés"; do assert_contient "$(sortie)" "$motif" "la rubrique « $motif » est produite malgré tout"; done
assert_contient "$(sortie)" "  non vérifié" "la rubrique des mots de passe dit qu'elle ne l'a pas été"

titre "5. Panne de la source de comptes, distincte d'un groupe absent"
lancer env "PATH=$FAUX:$PATH" FICHIER_SHADOW="$F_SHADOW" FICHIER_SHELLS="$F_SHELLS" PANNE=oui bash "$CIBLE"
assert_code 0 "$CODE" "une panne de getent group n'arrête pas l'audit"
assert_contient "$(erreur)" "[WARN] getent group docker" "la panne est signalée en [WARN]"
assert_contient "$(sortie)" "  docker : non vérifié" "le groupe dont la lecture a échoué est dit non vérifié"
assert_absent "$(sortie)" "docker : groupe absent" "une panne n'est pas prise pour un groupe absent"

titre "6. Les comptes réels de la machine, et la lecture seule"
touch "$REP_TMP/temoin"
AVANT="$(cksum /etc/passwd /etc/group /etc/shadow /etc/gshadow 2>/dev/null | cksum)"
lancer bash "$CIBLE"
assert_code 0 "$CODE" "l'audit des comptes réels sort en 0"
assert_contient "$(sortie)" "1. Comptes à UID 0" "la rubrique des UID 0 est produite"
assert_contient "$(rubrique 1)" "  root" "root figure dans la seule rubrique des UID 0"
assert_absent "$(erreur)" "Échec (code" "le trap ERR n'ajoute aucune ligne"
assert_egal "$AVANT" "$(cksum /etc/passwd /etc/group /etc/shadow /etc/gshadow 2>/dev/null | cksum)" "les fichiers de comptes sont inchangés"
ECRITURES="$(find /etc /home /root -newer "$REP_TMP/temoin" -not -path "$LOG_DIR/*" 2>/dev/null || true)"
assert_egal "" "$ECRITURES" "aucun fichier n'est modifié hors du répertoire de journaux"

titre "7. Sans privilège, devant un /etc/shadow existant mais illisible"
abaisse() { [ "$("$@" id -u 2>/dev/null)" = "65534" ]; }
SANS_ROOT=()
if abaisse setpriv --reuid=65534 --regid=65534 --clear-groups; then SANS_ROOT=(setpriv --reuid=65534 --regid=65534 --clear-groups)
elif abaisse runuser -u nobody --; then SANS_ROOT=(runuser -u nobody --)
fi
if [ "${#SANS_ROOT[@]}" -eq 0 ] && [ "$(id -u)" = "0" ]; then
    saute_indisponible "l'exécution sans privilège" "aucun lanceur ne parvient à abaisser l'UID"
else
    F_MUET="$REP_TMP/muet"; printf 'root::19000:0:99999:7:::\n' > "$F_MUET"; chmod 000 "$F_MUET"
    lancer "${SANS_ROOT[@]}" env "PATH=$FAUX:$PATH" FICHIER_SHADOW="$F_SHADOW" FICHIER_SHELLS="$F_SHELLS" bash "$CIBLE"
    assert_code 0 "$CODE" "le script s'exécute sans privilège et sort en 0"
    assert_contient "$(sortie)" "1. Comptes à UID 0" "l'audit est produit sans privilège"
    lancer "${SANS_ROOT[@]}" env "PATH=$FAUX:$PATH" FICHIER_SHADOW="$F_MUET" FICHIER_SHELLS="$F_SHELLS" bash "$CIBLE"
    assert_code 0 "$CODE" "un /etc/shadow existant mais illisible n'arrête pas l'audit"
    assert_contient "$(erreur)" "$F_MUET est illisible" "le fichier existant mais illisible est annoncé"
    assert_contient "$(sortie)" "  non vérifié" "la rubrique des mots de passe dit ne pas avoir été vérifiée"
fi

bilan "TASK-041 / audit-users.sh"
