#!/usr/bin/env bash
# tests/integration/ansible-profil.test.sh — tests/env/Dockerfile.ansible, et le
# profil « ansible » de tests/env/run-in-container.sh.
#
# TASK-085. Le conteneur de cas n'a pas Docker : le lanceur est éprouvé avec un
# faux docker en tête de PATH, qui répond ce que chaque cas lui demande. Ce qui
# se prouve ici est donc la RÉSOLUTION du profil — le socket qu'il réclame et
# que les autres ne reçoivent pas, l'image qu'il nomme, les versions qu'il
# épingle —, et non l'exécution de Molecule : celle-ci demande le démon réel et
# se conduit par la commande unique que ce fichier vérifie, sans la lancer.

_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_dir/lib/common.sh" ] && [ "$_dir" != "/" ]; do _dir="$(dirname "$_dir")"; done
source "$_dir/lib/common.sh"
source "$SCRIPTS_ROOT/tests/lib/assert.sh"

LANCEUR="$SCRIPTS_ROOT/tests/env/run-in-container.sh"
IMAGE="$SCRIPTS_ROOT/tests/env/Dockerfile.ansible"
COMMANDE="$SCRIPTS_ROOT/tests/env/valider-ansible.sh"
SCENARIO="$SCRIPTS_ROOT/Ansible/roles/securite_base/molecule/default/molecule.yml"
CI="$SCRIPTS_ROOT/.github/workflows/ci.yml"

BAC="$(mktemp -d)"
trap 'rm -rf "$BAC"' EXIT

cat >"$BAC/docker" <<'EOF'
#!/bin/sh
case "$1 $2" in
    "info --format") echo "28.5.2" ;;
    "image inspect") : ;;
esac
exit 0
EOF
chmod +x "$BAC/docker"

# Le lanceur, dans le conteneur : son code et sa sortie, les deux flux mêlés.
lancer() {
    PATH="$BAC:$PATH" bash "$LANCEUR" "$@" 2>&1
}

titre "Le profil est décrit, ses outils sont épinglés"

assert_egal 0 "$([ -f "$IMAGE" ] && echo 0 || echo 1)" "tests/env/Dockerfile.ansible existe"
image_texte="$(cat "$IMAGE")"
# Le socle Python officiel, et non debian:12 : ansible 14.4.0 exige Python 3.12,
# dont Debian 12 ne dispose pas (construction refusée par pip, mesuré le
# 2026-09-18). L'assertion porte sur la balise exacte, base et version comprises.
assert_contient "$image_texte" "FROM python:3.12-slim-bookworm" \
    "l'image de base est épinglée, Python 3.12 sur Debian 12"
for outil in 'ansible==14.4.0' 'ansible-lint==26.8.0' 'docker==7.2.0' \
             'molecule==26.8.0' 'molecule-plugins[docker]==26.7.15' 'yamllint==1.38.0'; do
    assert_contient "$image_texte" "$outil" "l'outil est épinglé : $outil"
done
# rsync n'est pas un outil du dépôt mais une dépendance du pilote Docker de
# Molecule (phase « create ») : son absence n'échoue qu'à l'exécution réelle du
# scénario, jamais à la lecture — d'où cette assertion.
assert_contient "$image_texte" "rsync" "l'image porte rsync, exigé par la phase create de Molecule"

titre "Le lanceur monte le socket que le profil réclame"

sortie="$(lancer --profil ansible --dry-run -- bash -c true)" && code=0 || code=$?
assert_code 0 "$code" "--profil ansible en --dry-run rend 0"
assert_contient "$sortie" "-v /var/run/docker.sock:/var/run/docker.sock" \
    "le socket de l'hôte est monté — Molecule pilote le démon, sans Docker imbriqué"
assert_contient "$sortie" "mgnet-test-ansible:latest" "l'image du profil est mgnet-test-ansible:latest"
assert_contient "$sortie" "Socket     : /var/run/docker.sock" "le résumé annonce le socket monté"

titre "Aucun autre profil ne reçoit le socket"

sortie="$(lancer --profil debian --dry-run -- bash -c true)" && code=0 || code=$?
assert_code 0 "$code" "--profil debian en --dry-run rend 0"
assert_contient "$sortie" "Profil     : debian" "le profil debian est bien celui qui a été résolu"
assert_absent "$sortie" "docker.sock" "le profil debian ne reçoit pas le socket"

sortie="$(lancer --profil systemd --dry-run -- bash -c true)" && code=0 || code=$?
assert_code 0 "$code" "--profil systemd en --dry-run rend 0"
assert_contient "$sortie" "--privileged" "le profil systemd reste privilégié"
assert_absent "$sortie" "docker.sock" "le profil systemd ne reçoit pas le socket"

sortie="$(lancer --profil inexistant -- bash -c true)" && code=0 || code=$?
assert_code 2 "$code" "un profil sans Dockerfile rend 2"
assert_contient "$sortie" "Profil inconnu" "le refus nomme le profil inconnu"

titre "La commande unique enchaîne les trois contrôles"

commande_texte="$(cat "$COMMANDE")"
assert_contient "$commande_texte" "run_logged yamllint ." "yamllint passe sur tout le dépôt"
assert_contient "$commande_texte" "run_logged ansible-lint Ansible/" "ansible-lint passe sur Ansible/"
assert_contient "$commande_texte" "run_logged molecule test" "molecule test ferme la marche"

titre "Les instances Molecule portent le préfixe mgnet-test-"

scenario_texte="$(cat "$SCENARIO")"
assert_contient "$scenario_texte" "name: mgnet-test-securite-debian12" \
    "l'instance Debian 12 est préfixée mgnet-test-"
assert_contient "$scenario_texte" "name: mgnet-test-securite-ubuntu2404" \
    "l'instance Ubuntu 24.04 est préfixée mgnet-test-"
assert_contient "$commande_texte" 'PREFIXE_INSTANCES="mgnet-test-securite-"' \
    "le relevé d'instances d'avant et d'après porte sur ces deux-là"

titre "La CI passe par le profil, sans rien installer sur le runner"

ci_texte="$(cat "$CI")"
assert_contient "$ci_texte" "run-in-container.sh --profil ansible -- tests/env/valider-ansible.sh" \
    "le travail Ansible de la CI appelle le profil"
assert_absent "$ci_texte" "pipx install" "la CI n'installe plus l'outillage sur le runner"
assert_absent "$ci_texte" "uses: docker" "la CI n'a pas d'action Docker en plus du profil"

bilan "TASK-085 / profil ansible"
