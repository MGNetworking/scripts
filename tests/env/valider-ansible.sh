#!/usr/bin/env bash
# tests/env/valider-ansible.sh — l'outillage Ansible, exécuté dans son conteneur.
#
#   tests/env/run-in-container.sh --profil ansible -- tests/env/valider-ansible.sh
#
# Une seule commande, rien à installer sur l'hôte (TASK-085) : les trois
# contrôles que Ansible/README.md prescrit, dans cet ordre — yamllint sur tout le
# dépôt, ansible-lint sur Ansible/, puis molecule test sur securite_base, qui
# crée ses instances, converge, éprouve l'idempotence, vérifie et détruit.
#
# Les collections du scénario s'installent ici, et non dans l'image :
# collections.yml vit dans le dépôt monté sur /depot, et le venv ne porte
# qu'ansible-core — Molecule, lui, ne les installe qu'à sa phase « dependency »,
# trop tard pour le pilote Docker qu'il charge dès le démarrage du scénario.

set -Eeuo pipefail

_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_dir/lib/common.sh" ] && [ "$_dir" != "/" ]; do _dir="$(dirname "$_dir")"; done
source "$_dir/lib/common.sh"

require_cmd ansible-galaxy ansible-lint docker molecule yamllint

SCENARIO="$SCRIPTS_ROOT/Ansible/roles/securite_base"
PREFIXE_INSTANCES="mgnet-test-securite-"

# Le scénario construit ses images avec « pull: false » : les bases doivent être
# là avant lui, sans quoi le pilote s'adresserait au registre à chaque
# construction — et, sur un poste Windows, à l'assistant d'identification de
# Docker Desktop, que le conteneur ne saurait pas exécuter.
for image in debian:12 ubuntu:24.04; do
    docker image inspect "$image" >/dev/null 2>&1 || run_logged docker pull "$image"
done

# Les instances du scénario, quel que soit leur état. Le relevé d'avant sert de
# témoin : ce que molecule test laisse derrière lui se lit dans celui d'après.
instances() {
    docker ps -a --filter "name=$PREFIXE_INSTANCES" --format '{{.Names}}' | tr '\n' ' '
}

avant="$(instances)"
info "Instances ${PREFIXE_INSTANCES}* avant : ${avant:-aucune}"

cd "$SCRIPTS_ROOT"
run_logged yamllint .

export ANSIBLE_ROLES_PATH="$SCRIPTS_ROOT/Ansible/roles"
run_logged ansible-lint Ansible/

cd "$SCENARIO"
run_logged ansible-galaxy collection install --force \
    -r molecule/default/collections.yml -p "$HOME/.ansible/collections"

run_logged molecule test

apres="$(instances)"
[ -z "$apres" ] || die "Instances Molecule survivantes après molecule test : $apres"
success "Instances ${PREFIXE_INSTANCES}* après : aucune — molecule test les a détruites."
