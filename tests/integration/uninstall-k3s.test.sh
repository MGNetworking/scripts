#!/usr/bin/env bash
# tests/integration/uninstall-k3s.test.sh — Linux/K3s/uninstall-k3s.sh.
# TASK-054. AUCUNE SUPPRESSION RÉELLE : le désinstallateur est un faux, et tout
# ce qu'il détruit vit sous un répertoire temporaire. La garde de conteneur
# passe avant tout trap, écriture ou suppression.
#
# Le faux suit la source officielle — install.sh, fonctions create_killall et
# create_uninstall, https://raw.githubusercontent.com/k3s-io/k3s/master/install.sh
# — et non la liste annoncée par le script. C'est ce qui prouve que le verdict
# relu ne réclame pas la disparition de /var/log/pods, que ni l'un ni l'autre des
# deux scripts officiels ne supprime.
_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_dir/lib/common.sh" ] && [ "$_dir" != "/" ]; do _dir="$(dirname "$_dir")"; done
source "$_dir/lib/common.sh"
source "$SCRIPTS_ROOT/tests/lib/assert.sh"

CIBLE="$SCRIPTS_ROOT/Linux/K3s/uninstall-k3s.sh"
JOURNAL="/var/log/mgnetworking/uninstall-k3s.log"
CHEMINS="etc/rancher/k3s var/lib/rancher/k3s var/lib/kubelet var/lib/cni run/k3s
         run/flannel usr/local/bin/k3s-killall.sh etc/systemd/system/k3s.service.env"
if [ ! -e /.dockerenv ]; then
    saute_indisponible "uninstall-k3s.sh" "hors conteneur : aucune suppression réelle n'est permise"
    bilan "TASK-054 / uninstall-k3s.sh"
fi
BAC="$(mktemp -d)"
export BAC
RACINE="$BAC/racine"
trap 'rm -rf "$BAC"' EXIT

faux() { cat > "$BAC/$1"; chmod +x "$BAC/$1"; }
faux k3s <<'EOF'
#!/bin/sh
case "$*" in --version) echo "k3s version v1.30.5+k3s1 (aaaaaaa)" ;; *) exit 1 ;; esac
EOF
# Faux du : consigne les chemins interrogés, puis délègue au vrai. Le résumé doit
# annoncer des tailles réellement mesurées, pas des constantes du test.
faux du <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$BAC/du-appels"
exec /usr/bin/du "$@"
EOF
# Faux systemctl, aux codes du vrai : 3 pour un service inactif, 1 pour une unité
# que systemd ne connaît pas. unite-connue simule une unité encore chargée alors
# que son fichier a disparu.
faux systemctl <<'EOF'
#!/bin/sh
unite="$BAC/racine/etc/systemd/system/k3s.service"
case "$*" in
  "is-active k3s")  [ -f "$unite" ] || { echo inactive; exit 3; }; echo active ;;
  "is-enabled k3s") [ -f "$unite" ] || [ -f "$BAC/unite-connue" ] || exit 1; echo enabled ;;
  *) exit 1 ;;
esac
EOF

# Arborescence imitée : binaire, désinstallateur, unité, données — dont un volume
# local-path de 3 Mio, et 1 Mio hors de lui pour que sa taille se distingue de
# celle du répertoire parent. Les variables DESINSTALLATEUR_* pilotent ce que le
# faux supprime et son code de retour : c'est ainsi qu'on éprouve l'état relu.
monter() {
    rm -rf "$RACINE" "$BAC/k3s" "$BAC/desinstallateur-appele" "$BAC/desinstallateur-env" "$BAC/unite-connue"
    : > "$BAC/du-appels"
    rm -f "$JOURNAL"
    mkdir -p "$RACINE/etc/rancher/k3s" "$RACINE/var/lib/rancher/k3s/storage/pvc-1" \
             "$RACINE/var/lib/kubelet" "$RACINE/var/lib/cni" \
             "$RACINE/run/k3s" "$RACINE/run/flannel" \
             "$RACINE/var/log/pods" "$RACINE/var/log/containers" \
             "$RACINE/usr/local/bin" "$RACINE/etc/systemd/system"
    head -c 3145728 /dev/zero > "$RACINE/var/lib/rancher/k3s/storage/pvc-1/volume"
    head -c 1048576 /dev/zero > "$RACINE/var/lib/rancher/k3s/hors-storage"
    : > "$RACINE/etc/systemd/system/k3s.service"
    : > "$RACINE/etc/systemd/system/k3s.service.env"
    : > "$RACINE/usr/local/bin/k3s-killall.sh"
    printf '#!/bin/sh\necho "k3s version v1.30.5+k3s1 (aaaaaaa)"\n' > "$BAC/k3s"
    chmod +x "$BAC/k3s"
    cat > "$RACINE/usr/local/bin/k3s-uninstall.sh" <<'EOF'
#!/bin/sh
printf '%s\n' "$0" > "$BAC/desinstallateur-appele"
env | grep -E '^(INSTALL_K3S_|K3S_)' > "$BAC/desinstallateur-env" || true
if [ "${DESINSTALLATEUR_RIEN:-0}" = 1 ]; then
    # Arrêt anticipé officiel, devant d'autres services k3s installés : il sort
    # en 0 sans rien supprimer.
    echo "Additional k3s services installed, skipping uninstall of k3s"
    exit 0
fi
rm -rf "$BAC/racine/etc/rancher/k3s" "$BAC/racine/var/lib/rancher/k3s" \
       "$BAC/racine/var/lib/kubelet" "$BAC/racine/var/lib/cni" \
       "$BAC/racine/run/k3s" "$BAC/racine/run/flannel"
rm -f "$BAC/racine/etc/systemd/system/k3s.service" \
      "$BAC/racine/etc/systemd/system/k3s.service.env" \
      "$BAC/racine/usr/local/bin/k3s-killall.sh"
[ "${DESINSTALLATEUR_GARDE_BINAIRE:-0}" = 0 ] && rm -f "$BAC/k3s" && rm -f "$0"
exit "${DESINSTALLATEUR_CODE:-0}"
EOF
    chmod +x "$RACINE/usr/local/bin/k3s-uninstall.sh"
}

lancer() { sortie="$(RACINE_TEST="$RACINE" PATH="$BAC:$PATH" bash "$CIBLE" "$@" 2>&1)" && CODE=0 || CODE=$?; }
sur() { RACINE_TEST="$RACINE" PATH="$BAC:$PATH" "$@"; }
appele() { test -e "$BAC/desinstallateur-appele" && echo présente || echo absente; }
present() { test -e "$1" && echo présente || echo absente; }
absent_partout() {
    for chemin in $CHEMINS; do
        assert_egal "absente" "$(present "$RACINE/$chemin")" "$chemin a disparu"
    done
}

titre "Codes d'usage"
sortie="$(bash "$CIBLE" --help 2>&1)" && code=0 || code=$?
assert_code 0 "$code" "--help rend 0"
assert_contient "$sortie" "k3s-uninstall.sh" "--help nomme le désinstallateur officiel (décision 47)"
assert_contient "$sortie" "2  option" "--help documente les codes de retour"
bash "$CIBLE" --option-inexistante >/dev/null 2>&1 && code=0 || code=$?
assert_code 2 "$code" "une option inconnue rend 2"

titre "Privilège : root requis, --dry-run compris"
monter
faux id <<'EOF'
#!/bin/sh
[ "$*" = "-u" ] && { echo 1000; exit 0; }
exec /usr/bin/id "$@"
EOF
lancer --yes
assert_code 1 "$CODE" "un utilisateur non privilégié est refusé en 1"
assert_contient "$sortie" "root" "le refus nomme le privilège manquant"
lancer --dry-run
assert_code 1 "$CODE" "--dry-run sans root est refusé en 1"
assert_egal "absente" "$(appele)" "et le désinstallateur n'est pas appelé"
rm -f "$BAC/id"

titre "K3s absent, et k3s sans désinstallateur"
monter
rm -f "$BAC/k3s" "$RACINE/usr/local/bin/k3s-uninstall.sh"
lancer --yes
assert_code 0 "$CODE" "sans binaire ni désinstallateur, le script rend 0"
assert_contient "$sortie" "n'est pas installé" "et le dit"
assert_egal "absente" "$(appele)" "rien n'a été exécuté"
assert_egal "présente" "$(present "$RACINE/var/lib/rancher/k3s/storage/pvc-1/volume")" "et aucune donnée n'a été touchée"
monter
rm -f "$BAC/k3s"
lancer --yes
assert_code 0 "$CODE" "un binaire absent mais un désinstallateur présent : les restes sont détruits, en 0"
assert_egal "absente" "$(present "$RACINE/var/lib/rancher/k3s")" "et il ne subsiste aucun répertoire de données"
monter
rm -f "$RACINE/usr/local/bin/k3s-uninstall.sh"
lancer --yes
assert_code 1 "$CODE" "un k3s sans désinstallateur est refusé en 1"
assert_contient "$sortie" "k3s-uninstall.sh" "le refus nomme le désinstallateur manquant"
assert_contient "$sortie" "décision 47" "et dit pourquoi il ne supprime pas lui-même"
assert_egal "absente" "$(appele)" "aucun désinstallateur n'a été appelé"
assert_egal "présente" "$(present "$RACINE/var/lib/rancher/k3s/storage/pvc-1/volume")" "et les données sont intactes"

titre "Nœud agent : hors du périmètre de ce script"
monter
rm -f "$RACINE/usr/local/bin/k3s-uninstall.sh"
printf '#!/bin/sh\nexit 0\n' > "$RACINE/usr/local/bin/k3s-agent-uninstall.sh"
chmod +x "$RACINE/usr/local/bin/k3s-agent-uninstall.sh"
lancer --yes
assert_code 1 "$CODE" "un nœud agent est refusé en 1"
assert_contient "$sortie" "agent K3s" "le refus dit que c'est un nœud agent"
assert_contient "$sortie" "hors du périmètre de ce script" "et que cela sort du périmètre de ce script"
assert_contient "$sortie" "Rien n'a été supprimé" "et que rien n'a été supprimé"
assert_egal "absente" "$(appele)" "le désinstallateur d'agent n'a pas été appelé"
assert_egal "présente" "$(present "$RACINE/var/lib/rancher/k3s/storage/pvc-1/volume")" "et les données sont intactes"

titre "--dry-run : le résumé, sans rien détruire"
monter
lancer --dry-run
assert_code 0 "$CODE" "--dry-run rend 0"
assert_contient "$sortie" "[WARN] Racine de test : RACINE_TEST détourne la désinstallation vers $RACINE" \
    "la racine de test détournée est annoncée par un avertissement qui la nomme"
for chemin in $CHEMINS; do
    assert_contient "$sortie" "$RACINE/$chemin" "le résumé liste $chemin"
done
TAILLE_DONNEES="$(du -sh "$RACINE/var/lib/rancher/k3s" | cut -f1)"
TAILLE_STORAGE="$(du -sh "$RACINE/var/lib/rancher/k3s/storage" | cut -f1)"
assert_contient "$sortie" "  $RACINE/var/lib/rancher/k3s $TAILLE_DONNEES" \
    "le résumé chiffre le répertoire de données, taille mesurée par du"
assert_contient "$sortie" "    dont $RACINE/var/lib/rancher/k3s/storage (volumes local-path des pods) $TAILLE_STORAGE" \
    "et la ligne des volumes local-path porte le chemin, le libellé et sa propre taille"
assert_egal "différente" "$([ "$TAILLE_STORAGE" != "$TAILLE_DONNEES" ] && echo différente || echo identique)" \
    "cette taille (3 Mio) se distingue de celle du parent (4 Mio) : elle est bien celle du volume"
assert_contient "$(cat "$BAC/du-appels")" "$RACINE/var/lib/rancher/k3s/storage" "du a bien été interrogé sur ce chemin"
assert_contient "$sortie" "Binaire à supprimer  : $BAC/k3s" "le résumé nomme le binaire"
assert_contient "$sortie" "Unité à supprimer    : $RACINE/etc/systemd/system/k3s.service" "et l'unité"
assert_contient "$sortie" "État du service k3s  : active" "et l'état du service, relevé avant"
assert_contient "$sortie" "Sauvegarde préalable : aucune" "le résumé dit qu'aucune sauvegarde n'est faite"
assert_contient "$sortie" "[dry-run]" "le mode simulation est annoncé"
assert_egal "absente" "$(appele)" "le désinstallateur n'a pas été appelé"
assert_egal "présente" "$(present "$RACINE/var/lib/rancher/k3s/storage/pvc-1/volume")" "et rien n'a été supprimé"
assert_egal "présente" "$(present "$RACINE/etc/systemd/system/k3s.service")" "l'unité est intacte"
monter
rm -rf "$RACINE/var/lib/cni"
lancer --dry-run
assert_contient "$sortie" "$RACINE/var/lib/cni absente" "un chemin absent est annoncé absent sur sa propre ligne, sans taille inventée"
assert_egal "absente" "$(appele)" "et le désinstallateur n'est toujours pas appelé"

titre "Confirmation : --yes seul, ASSUME_YES hérité ignoré (décision 45)"
monter
sortie="$(RACINE_TEST="$RACINE" PATH="$BAC:$PATH" bash "$CIBLE" </dev/null 2>&1)" && CODE=0 || CODE=$?
assert_code 1 "$CODE" "sans terminal et sans --yes, le script rend 1"
assert_contient "$sortie" "--yes" "le message nomme l'option qui débloque la situation"
assert_absent "$sortie" "Échec (code" "aucune ligne du trap ERR : le refus est délibéré"
assert_egal "absente" "$(appele)" "et rien n'est supprimé"
monter
sortie="$(RACINE_TEST="$RACINE" PATH="$BAC:$PATH" ASSUME_YES=true bash "$CIBLE" </dev/null 2>&1)" && CODE=0 || CODE=$?
assert_code 1 "$CODE" "un ASSUME_YES hérité, sans --yes, rend 1"
assert_egal "absente" "$(appele)" "et rien n'est supprimé non plus"
monter
if command -v script >/dev/null 2>&1; then
    # Avec un terminal, c'est confirm qui décide : ce cas seul prouve que
    # l'ASSUME_YES du parent est réellement remis à false (décision 45).
    code=0
    sortie="$(printf 'n\n' | RACINE_TEST="$RACINE" PATH="$BAC:$PATH" ASSUME_YES=true \
        script -qec "bash $CIBLE" /dev/null 2>&1)" || code=$?
    assert_code 1 "$code" "un ASSUME_YES hérité, avec un terminal, rend 1"
    assert_absent "$sortie" "Confirmation automatique" "l'ASSUME_YES du parent est ignoré"
    assert_contient "$sortie" "abandonnée" "la question est posée et « n » l'écarte"
    assert_egal "absente" "$(appele)" "le désinstallateur n'a pas été appelé"
else
    saute_indisponible "ASSUME_YES hérité avec un terminal" "script (util-linux) absent"
fi

titre "Désinstallation complète — faux désinstallateur"
JETON="jeton-2f4b8c"
monter
sur env INSTALL_K3S_VERSION=v9.9.9+k3s9 INSTALL_K3S_CHANNEL=old K3S_URL=https://ailleurs:6443 K3S_TOKEN="$JETON" \
    bash "$CIBLE" --yes >"$BAC/sortie" 2>&1 && code=0 || code=$?
assert_code 0 "$code" "désinstallation complète : rend 0"
assert_contient "$(cat "$BAC/desinstallateur-appele" 2>/dev/null)" "k3s-uninstall.sh" "c'est le désinstallateur officiel qui a été exécuté"
assert_egal "présente" "$(present "$BAC/desinstallateur-env")" "le faux désinstallateur a relevé son environnement"
assert_egal "" "$(cat "$BAC/desinstallateur-env")" "aucune INSTALL_K3S_* ni K3S_* héritée ne l'atteint"
assert_contient "$(cat "$BAC/sortie")" "K3s désinstallé" "le script annonce la désinstallation"
assert_egal "absente" "$(present "$BAC/k3s")" "le binaire a disparu"
assert_egal "absente" "$(present "$RACINE/etc/systemd/system/k3s.service")" "l'unité a disparu"
absent_partout
assert_egal "présente" "$(present "$RACINE/var/log/pods")" "/var/log/pods survit : le désinstallateur officiel ne le supprime pas, le script ne l'exige donc pas absent"
assert_contient "$(cat "$JOURNAL" 2>/dev/null)" "Exécution :" "le journal a capté le passage du désinstallateur"
assert_absent "$(cat "$BAC/sortie")" "$JETON" "le jeton du nœud n'apparaît pas dans la sortie"
assert_absent "$(cat "$JOURNAL" 2>/dev/null)" "$JETON" "ni dans le journal"
assert_absent "$(cat "$BAC/sortie")" "Retour arrière" "aucune consigne de retour arrière inopérante (A74)"

titre "État final relu : ce qui subsiste est nommé"
monter
sur env DESINSTALLATEUR_GARDE_BINAIRE=1 bash "$CIBLE" --yes >"$BAC/sortie" 2>&1 && code=0 || code=$?
assert_code 1 "$code" "un binaire qui subsiste rend 1"
assert_contient "$(cat "$BAC/sortie")" "$BAC/k3s" "et le message nomme le binaire"
assert_contient "$(cat "$BAC/sortie")" "Reprendre à la main" "sans promettre un retour arrière (A74)"
monter
: > "$BAC/unite-connue"
sur env bash "$CIBLE" --yes >"$BAC/sortie" 2>&1 && code=0 || code=$?
assert_code 1 "$code" "un fichier d'unité disparu mais une unité que systemd connaît encore rend 1"
assert_contient "$(cat "$BAC/sortie")" "unité k3s, que systemd connaît encore" "et le message la nomme"
assert_egal "absente" "$(present "$RACINE/etc/systemd/system/k3s.service")" "le fichier d'unité, lui, a bien disparu"
monter
sur env DESINSTALLATEUR_CODE=7 bash "$CIBLE" --yes >"$BAC/sortie" 2>&1 && code=0 || code=$?
assert_code 1 "$code" "un désinstallateur en échec rend 1"
assert_contient "$(cat "$BAC/sortie")" "code 7" "le message donne le code du désinstallateur"
assert_contient "$(cat "$BAC/sortie")" "subsiste : rien" "et constate que tout a disparu malgré l'échec"

titre "Désinstallateur en arrêt anticipé : rien supprimé, la cause est nommée"
monter
sur env DESINSTALLATEUR_RIEN=1 bash "$CIBLE" --yes >"$BAC/sortie" 2>&1 && code=0 || code=$?
sortie="$(cat "$BAC/sortie")"
assert_code 1 "$code" "un désinstallateur qui sort en 0 sans rien supprimer rend 1"
assert_contient "$sortie" "etc/rancher/k3s" "le message nomme les chemins qui restent"
assert_contient "$sortie" "etc/systemd/system/k3s.service" "et l'unité qui reste"
assert_contient "$sortie" "Il n'a rien supprimé" "et constate qu'il n'a rien supprimé"
assert_contient "$sortie" "cause probable" "en nommant la cause probable de ce 0"
assert_contient "$sortie" "k3s*.service" "les autres unités k3s*.service"
assert_contient "$sortie" "init.d/k3s" "ou les scripts /etc/init.d/k3s*"

bilan "TASK-054 / uninstall-k3s.sh"
