# TASK-080 — Rapport d'exécution

## Compte rendu

La décision 50, prise le 2026-09-17, confie à Ansible l'installation et la configuration
des machines, et impose une CI. Cette tâche pose les trois fondations que le premier rôle
suppose : un **poste de contrôle** outillé, un **squelette `Ansible/`** encore sans rôle,
et une **intégration continue** qui tourne à chaque push.

**Le poste de contrôle.** Tu avais installé `pipx` toi-même (1.4.3, dans WSL Ubuntu 24.04),
puisque c'est la seule étape qui demande `sudo`. Le reste a été installé sans privilège,
par `pipx` : `ansible` 14.4.0 (`ansible-core` 2.21.4), `ansible-lint` 26.8.0, `yamllint`
1.38.0, `molecule` 26.8.0 avec son pilote Docker (`molecule-plugins` 26.7.15). Les quatre
`--version` répondent 0. Ces outils vivent **hors du dépôt**, dans ton WSL : c'est une
modification de ta machine, et elle est rejouable par les commandes du nouveau
`Ansible/README.md`.

**Le squelette.** `Ansible/` porte son cadrage (besoin, conventions, aucun contrat tant
qu'aucun rôle n'existe), son README (installation, commandes, sécurité de l'inventaire),
une configuration `ansible.cfg`, un inventaire d'exemple et un modèle de variables par
machine. Les adresses des exemples appartiennent au bloc de documentation `203.0.113.0/24`
(RFC 5737) : elles ne joignent aucune machine. Le `.gitignore` écarte désormais tout
inventaire réel, tout le contenu de `host_vars/` et `group_vars/` sauf les `*.example.yml`,
et tout fichier Vault — vérifié par `git check-ignore`.

**La CI.** `.github/workflows/ci.yml` lance trois travaux en parallèle sur chaque push de
`master` et chaque pull request : `shellcheck` et les tests unitaires dans un conteneur
Debian jetable, les tests d'intégration dans un autre, `yamllint` et `ansible-lint` sur le
troisième. Elle n'invente rien : elle appelle `tests/env/run-in-container.sh`, le même
point d'entrée qu'à la main. **Premier passage vert**, le 2026-09-17 :
[run 35259777538](https://github.com/MGNetworking/scripts/actions/runs/35259777538) —
2 min 13 s pour le plus long des trois travaux, loin sous les 15 minutes visées. Tu avais
autorisé ce push de `master` pour cette preuve.

**Relecture.** Opus a rendu « fusionnable après corrections ». Le défaut bloquant était
attendu : la CI n'avait pas encore tourné. Deux majeurs ont été corrigés — le workflow
appelait les scripts sans `bash`, ce qui l'aurait fait mourir si le bit d'exécution
manquait, et les versions d'`ansible-lint` et de `yamllint` n'étaient pas épinglées, si
bien qu'une publication amont aurait pu faire rougir la CI sans qu'une ligne du dépôt
change. Quatre mineurs corrigés : absence du niveau `acceptance` non expliquée, sections
manquantes du cadrage, `.gitignore` trop étroit, phrase inexacte sur la lecture
d'`ansible.cfg`.

**Ce que cette tâche ne prouve pas.** `ansible-lint` rend 0 sur un dossier qui ne contient
ni rôle ni playbook : le profil `production` ne sera réellement éprouvé qu'avec
`securite_base`. Molecule est installé mais n'a rien à faire tourner. Le niveau de preuve
est **conteneur** pour les tests Bash, et **aucun** pour Ansible tant qu'aucun rôle n'existe.

### Réserves

- Le niveau `environment` (profil `systemd`) reste hors CI, faute de garantie sur le
  `--privileged` d'un runner GitHub : il n'est prouvé que sur le poste de travail (A153).
- La CI ne lance pas Molecule, que la décision 50 exige sur les rôles modifiés : aucun rôle
  n'existe encore (A154).
- `ansible-lint Ansible/` à 0 n'éprouve rien aujourd'hui (A155).
- Chaque run porte l'annotation « Node.js 20 is deprecated » d'`actions/checkout@v4` —
  avertissement seulement (A156).

## Statut

`completed`. TASK-081 (rôle pilote `securite_base`) passe en `ready`.

## Fichiers

- `Ansible/CADRAGE.md`, `Ansible/README.md`, `Ansible/ansible.cfg`,
  `Ansible/inventory.example.yml`, `Ansible/host_vars/vps1.example.yml`,
  `Ansible/playbooks/.gitkeep`, `Ansible/roles/.gitkeep`
- `.yamllint`, `.ansible-lint`, `.gitignore` (bloc Ansible), `.github/workflows/ci.yml`
- clôture : `README.md` (racine), `tasks/backlog.md`, `tasks/pending/TASK-039.md`,
  `orchestration/mesures/agents.tsv`, `orchestration/mesures/journal.md`

## Validations

| Commande | Code |
|---|---|
| WSL : `ansible --version`, `ansible-lint --version`, `yamllint --version`, `molecule --version` | 0, 0, 0, 0 |
| WSL : `yamllint .` (dépôt entier) | 0 |
| WSL : `ansible-lint Ansible/` | 0 — « Passed: 0 failure(s), 0 warning(s) », profil `production` |
| `git check-ignore Ansible/inventory.yml Ansible/host_vars/vps1.yml` | 0 (ignorés) |
| `git check-ignore Ansible/host_vars/vps1.example.yml` | 1 (versionnable) |
| `tests/env/run-in-container.sh -- tests/run.sh lint unit integration` (poste) | 0 — 3 niveaux réussis, 1 avec cas non applicables |
| `bash orchestration/outils/verifier-liens.sh` | 0 — aucun lien mort |
| `bash orchestration/outils/juger.sh tasks/active/TASK-080.md` | 1 — « aucun fichier de cas dans le périmètre » : sans objet, la tâche ne livre aucun script Bash |
| CI GitHub Actions, run 35259777538 sur `33806ef` | `success` — trois travaux verts (Ansible 13 s, lint+unit 40 s, integration 2 min 13 s) |

Niveaux de preuve : **conteneur** pour les tests Bash (Debian 12 jetable, sur le poste et
sur le runner) ; **poste de contrôle** pour les versions d'outils (WSL, hors dépôt) ;
**aucun** pour la qualité des rôles, qui n'existent pas encore.

## Git

- `4674011` chore: TASK-080 en cours
- `d6733ac` feat(ansible): poste de contrôle, squelette Ansible/ et CI GitHub Actions
- `ce2c7f3` fix: retours de relecture (TASK-080)
- `33806ef` fusion `--no-ff` de `agent/TASK-080` sur `master`, branche supprimée
  (travail mené dans le dépôt principal, aucune copie `script-agents`)
- `git push origin master` → `3a4f3cc..33806ef`, autorisé par `user` pour éprouver la CI
