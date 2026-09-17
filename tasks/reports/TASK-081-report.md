# TASK-081 — Rapport d'exécution

## Compte rendu

La décision 50 a ouvert un pilote : Ansible prend-il la place des scripts Bash d'installation
et de configuration ? Cette tâche écrit le premier rôle, `securite_base`, qui doit garantir
ce que garantissent ensemble `configure-ssh.sh`, `configure-firewall.sh` et
`configure-fail2ban.sh` — et le prouver dans des conteneurs, pas sur le papier. Le bilan
chiffré qui clôt ce rapport est ce qui doit te permettre de décider de poursuivre ou non.

**Ce que le rôle fait.** Il dépose dans `sshd_config.d/` un fragment qui refuse le mot de
passe et le clavier interactif et garde la clé publique, sans jamais toucher au port ; il
installe ufw, ouvre le port SSH **avant** toute politique, refuse l'entrant, autorise le
sortant, active le pare-feu ; il installe fail2ban, dépose la prison `sshd` avec les valeurs
de la distribution, active le service et vérifie auprès du démon que la prison est chargée.
Les gardes des décisions 20 et 21 sont reprises une à une : compte non-root avec sudo et clé,
`Include sshd_config.d/*.conf` exigé, `sshd -T` confrontant le port déclaré au port écouté,
`sshd -t` avant tout rechargement — et, s'il refuse, la version antérieure est remise en place
et le play s'arrête **sans recharger**, donc sans couper l'accès.

**Ce qui le prouve.** Un scénario Molecule lance deux conteneurs jetables — Debian 12 et
Ubuntu 24.04 — où systemd tourne en PID 1, comme sur un serveur : sans cela, ni le
rechargement de `ssh`, ni le redémarrage de `fail2ban`, ni l'activation d'ufw ne seraient
exécutés. `molecule test` enchaîne création, préparation, application, **second passage sans
changement** (idempotence) et vérification. La vérification n'interroge pas les fichiers que
le rôle vient d'écrire, mais les programmes eux-mêmes : `sshd -T`, `ufw status verbose`,
`fail2ban-client status sshd`, et l'état du service `ssh`, pour s'assurer que le durcissement
n'a pas laissé le démon à terre.

**Quatre pièges rencontrés**, tous dans l'outillage, aucun dans le rôle :

1. Molecule vit dans son propre environnement Python, qui ne porte qu'`ansible-core` : ni son
   pilote Docker ni le module `ufw` ne lui étaient visibles. Un fichier `collections.yml`
   versionné, aux versions épinglées, et une installation dans `~/.ansible/collections` — là
   où Molecule regarde en premier — règlent le point, sur le poste comme en CI.
2. Les modules Docker s'exécutent avec le python d'`ansible`, pas celui de Molecule : la
   bibliothèque `docker` devait être ajoutée aux deux (`pipx inject ansible docker`).
3. Sur ce poste, `~/.docker/config.json` de WSL renvoie à l'assistant d'identification de
   Docker Desktop, un `.exe` que WSL ne peut pas exécuter : la construction des images mourait
   sur « Exec format error ». Le scénario pointe désormais `DOCKER_CONFIG` vers un répertoire
   vide — il ne tire que des images publiques.
4. `ansible-lint` ne trouvait pas le rôle appelé par les playbooks : nos rôles ne sont pas à la
   racine du dépôt, et `ansible.cfg`, qui porte `roles_path`, n'est lu que depuis `Ansible/`.
   La commande porte maintenant `ANSIBLE_ROLES_PATH`, dans la CI comme dans le README.

**Ce que cette tâche ne prouve pas.** Le niveau de preuve est **conteneur**. Les gardes
anti-verrouillage — compte absent, sans clé, hors de sudo, `sshd -t` en échec, règle `deny`
sur le port SSH — ne sont pas éprouvées par un scénario : seul le chemin nominal l'est (A157).
Le niveau **machine** te revient : un `--check --diff` sur un VPS, que ce rapport te demande
en fin de texte.

## Statut

`completed`. Le rôle est livré ; la décision de poursuivre ou non la migration reste ouverte
(voir « Bilan » et « Ce qui t'est demandé »).

## Fichiers

- `Ansible/roles/securite_base/` : `defaults/main.yml`, `meta/main.yml`,
  `meta/argument_specs.yml`, `tasks/main.yml`, `tasks/ssh.yml`, `tasks/pare-feu.yml`,
  `tasks/fail2ban.yml`, `handlers/main.yml`, `templates/10-mgnetworking.conf.j2`,
  `templates/mgnetworking-sshd.conf.j2`
- `Ansible/roles/securite_base/molecule/default/` : `molecule.yml`, `Dockerfile.j2`,
  `collections.yml`, `prepare.yml`, `converge.yml`, `verify.yml`
- `Ansible/playbooks/securite.yml`, `Ansible/CADRAGE.md` (contrat du rôle),
  `Ansible/README.md` (installation, commandes Molecule), `.github/workflows/ci.yml`
  (travail `ansible-molecule`, `ANSIBLE_ROLES_PATH` sur `ansible-lint`)

## Correspondance clause par clause

Contrats de `Linux/CADRAGE.md`. « Reprise » signifie que le rôle garantit la même chose, pas
qu'il l'écrit de la même façon.

### configure-ssh.sh

| Clause du contrat Bash | Dans le rôle |
|---|---|
| Garde de la décision 20 : compte non-root, membre de sudo, avec clé | reprise — `getent` passwd et group, `slurp` d'`authorized_keys`, trois `assert` |
| Exige `Include sshd_config.d/*.conf` | reprise — `slurp` puis `assert` avec la même expression rationnelle, casse comprise |
| Exige que le répertoire `sshd_config.d` existe | **écartée** — le dépôt du fragment échoue de lui-même en nommant le répertoire ; une garde de plus n'ajouterait qu'un message |
| Dépose `10-mgnetworking.conf` : trois directives | reprise — `template`, 0644, root |
| Identique : rien réécrit ni rechargé | reprise — `template` idempotent, le handler n'est notifié que sur changement |
| `sshd -t -f` puis `systemctl reload ssh` | reprise — `command` puis handler `service: reloaded`, dans cet ordre (`flush_handlers` explicite) |
| Échec : fichier précédent restauré (ou retiré) | reprise — `block`/`rescue`, `backup: true`, puis `fail` qui laisse les handlers en attente |
| Ne relit pas `sshd -T` pour SSH | reprise — le rôle ne s'en sert que pour le port ; `sshd -T` complet est dans `verify` |
| `--utilisateur <nom>` | reprise — `securite_base_compte_admin`, requise sans défaut |
| `--dry-run` | reprise autrement — `--check --diff`, natif et plus riche (le diff montre le fichier) |
| `-y`/`--yes`, `confirm`, neutralisation d'`ASSUME_YES` (décision 45) | **écartée** — un playbook n'est pas interactif : la confirmation, c'est `--check --diff` lu par `user` avant de relancer sans `--check` |
| Nom de compte validé (forme `useradd`, 32 caractères) | **écartée** — `getent` tranche sur l'existence réelle, qui est la seule chose qui compte ici |
| Codes de retour 0 / 1 / 2 distincts | **écartée** — `ansible-playbook` rend 0, 2 (échec de tâche) ou 4 (hôte injoignable) ; la distinction « option mal formée » revient à `argument_specs` |

### configure-firewall.sh

| Clause du contrat Bash | Dans le rôle |
|---|---|
| Ports validés avant les privilèges | reprise — `assert` de forme `n/tcp\|n/udp`, en tête du rôle |
| Refus si le port de sshd diffère de celui déclaré | reprise — `sshd -T` puis `assert` |
| Repli sur `ss -tlnp` si `sshd -T` est muet, `[WARN]` si invérifiable | **écartée** — sur Debian et Ubuntu `sshd -T` répond ; un port invérifiable arrête le rôle au lieu de l'avertir, ce qui est plus sûr |
| ufw installé par `apt-get` s'il manque | reprise — `apt: state=present` |
| Plan des seules commandes manquantes (`ufw show added`) | reprise autrement — chaque module ufw ne change que ce qui diffère, et `--check --diff` montre le plan |
| Ordre : `allow` SSH, `allow` autres, `deny incoming`, `allow outgoing`, `enable` | reprise — même ordre, tâche par tâche |
| Refus si une règle `deny` porte déjà sur le port SSH | reprise — lecture d'`ufw show added` avant d'agir, `assert` sur les deux formes qu'ufw enregistre |
| Règle SSH relue avant l'activation ; absente : refus | reprise — seconde lecture d'`ufw show added` puis `assert`, juste avant les politiques |
| Ne supprime jamais une règle | reprise — aucun `delete` |
| `--port` répétable | reprise — `securite_base_ports_autorises` |

### configure-fail2ban.sh

| Clause du contrat Bash | Dans le rôle |
|---|---|
| Installé par `apt-get` si `dpkg-query` le dit absent | reprise — `apt: state=present` |
| Dépose `<jail.d>/mgnetworking-sshd.conf` : `[sshd]`, `enabled = true` | reprise — `template`, 0644 |
| `<jail.d>` créé s'il manque, 0755 | reprise — `file: state=directory` |
| `systemctl enable` s'il n'est pas activé | reprise — `service: enabled=true, state=started` |
| `restart` seulement si quelque chose a changé | reprise — handler notifié par le seul dépôt |
| Rien à faire : vérification seule | reprise — les deux vérifications tournent à chaque passage |
| Démon attendu par `ping`, puis `status sshd` | reprise — `until`/`retries`/`delay`, mêmes variables (10 essais, 1 s) |
| Ne touche ni `jail.conf` ni `jail.local`, ne fixe aucune valeur (décision 22) | reprise — le gabarit ne porte que `[sshd]` et `enabled = true` |

**Hors périmètre, assumé** : `disable-root-login.sh` (`PermitRootLogin no`) n'est pas repris —
la fiche l'excluait. Tant que le rôle ne le porte pas, il reste nécessaire.

## Validations

Toutes lancées depuis la WSL Ubuntu 24.04 du poste de contrôle, sauf mention contraire.

| Commande | Code |
|---|---|
| `yamllint .` (dépôt entier) | 0 |
| `ANSIBLE_ROLES_PATH="$PWD/Ansible/roles" ansible-lint Ansible/` | 0 — « Passed: 0 failure(s), 0 warning(s) in 20 files processed », profil `production` |
| `molecule test` (rôle `securite_base`, Debian 12 et Ubuntu 24.04) | **0** — 12 actions, 8 réussies, 4 sans objet (`cleanup`, `side_effect`, deux `requirements`), 0 échec, **328 s** |
| — étape `converge` | 0 — `ok=38 changed=10` sur chaque instance |
| — étape `idempotence` | 0 — `ok=36 changed=0` sur chaque instance |
| — étape `verify` | 0 — `sshd -T`, `ufw status verbose`, `fail2ban-client status sshd`, service `ssh` actif, droits du fragment |
| Mutant (dépôt du fragment sshd rendu non idempotent) : `molecule create`, `prepare`, `converge` | 0, 0, 0 — le mutant s'applique sans se signaler |
| Mutant : `molecule idempotence` | **1** — voir la sortie ci-dessous |
| `bash orchestration/outils/verifier-liens.sh` | 0 — aucun lien mort |
| `bash orchestration/outils/juger.sh tasks/active/TASK-081.md` | 1 — « aucun fichier de cas dans le périmètre » : sans objet, la tâche ne livre aucun script Bash (A158) |
| CI GitHub Actions sur le push de `master` | (à compléter) |

Niveau de preuve : **conteneur**. Aucune machine réelle n'a été touchée ; aucun
`ansible-playbook` n'a tourné hors conteneur, avec ou sans `--check`.

### Le mutant : la preuve que l'étape d'idempotence n'est pas décorative

Le dépôt du fragment sshd a été remplacé, le temps d'un essai, par la traduction littérale
du Bash — un `ansible.builtin.shell` qui réécrit le fichier à chaque passage. Le rôle
continue de produire le bon état ; seule l'idempotence se perd. Sortie de
`molecule idempotence`, citée telle quelle :

```text
CRITICAL Idempotence test failed because of the following tasks:
*  => securite_base : Déposer le fragment de configuration sshd
*  => securite_base : Déposer le fragment de configuration sshd
*  => securite_base : Recharger ssh maintenant, avant de toucher au pare-feu
*  => securite_base : Recharger ssh maintenant, avant de toucher au pare-feu
ERROR    default ➜ idempotence: Executed: Failed
```

Deux lignes par tâche : une par instance. Le rechargement de `ssh` est cité lui aussi,
puisqu'un dépôt qui se déclare modifié notifie le handler à chaque passage — exactement le
défaut qu'on veut voir échouer. Le rôle a été restauré (`git checkout`) et les instances
détruites juste après.

### Ce qu'il a fallu régler pour que Molecule tourne, et qui n'est pas dans le rôle

| Symptôme | Cause | Remède, versionné |
|---|---|---|
| `Collection 'community.docker' not found` au démarrage du scénario | l'environnement de Molecule ne porte qu'`ansible-core` | `molecule/default/collections.yml` + installation dans `~/.ansible/collections` |
| `Failed to import the required Python library (requests)` à la destruction | les modules docker s'exécutent avec le python d'`ansible`, pas celui de Molecule | `pipx inject ansible docker` |
| `The role 'securite_base' was not found` (lint et scénario) | `ansible.cfg` n'est lu ni depuis la racine, ni depuis `/mnt/d` (A159) | `ANSIBLE_ROLES_PATH` explicite, dans le scénario et dans la CI |
| `Exec format error: docker-credential-desktop.exe` à la construction des images | le pilote interroge le registre et réclame l'assistant d'identification de Docker Desktop, un `.exe` inexécutable depuis WSL | `pull: false` et `DOCKER_CONFIG` vers un `config.json` sans authentification (A160) |

## Bilan comparatif

### Volume

Lignes **utiles** — ni vides, ni commentaires — et lignes totales entre parenthèses.

| | Bash | Ansible | Écart |
|---|---|---|---|
| Ce qui agit | 368 (469) — 3 scripts | 336 (450) — rôle + playbook | −9 % |
| Ce qui prouve | 672 (778) — 3 fichiers de cas | 190 (277) — scénario Molecule | −72 % |
| **Total** | **1 040 (1 247)** | **526 (727)** | **−49 %** |

Le code qui agit ne rétrécit pas : Ansible remplace du Bash ligne pour ligne, parce que
l'essentiel de ces scripts n'est pas la modification — que les modules font en une ligne —
mais les **gardes**, qui restent à écrire dans les deux mondes. Ce qui s'effondre, c'est le
coût de la preuve : les fichiers de cas Bash doivent construire un bac à sable, simuler
`sshd`, `ufw` et `fail2ban`, rejouer chaque scénario deux fois pour l'idempotence et vérifier
les codes de retour un à un ; Molecule fournit tout cela, l'idempotence comprise, en une
étape déclarée.

### Ce que le rôle apporte que le Bash n'a pas

- **La simulation est native et lisible** : `--check --diff` montre le contenu exact des
  fichiers avant écriture, là où `--dry-run` n'affiche qu'un plan rédigé à la main.
- **L'inventaire** : une machine, un groupe, une variable — sans copier un `server.env` par
  serveur.
- **L'idempotence est constatée par l'outil**, pas plaidée : l'étape `idempotence` échoue si
  une seule tâche se déclare modifiée au second passage.
- **Deux distributions éprouvées** dans la même commande.

### Ce que le Bash garde pour lui

- **Aucune dépendance** : `git clone` et c'est prêt ; Ansible demande un poste de contrôle,
  cinq outils, trois collections.
- **Des codes de retour parlants** : 0, 1, 2 selon la nature de l'échec, sur lesquels
  `tests/run.sh` s'appuie ; `ansible-playbook` n'en distingue que trois, tous « échec ».
- **Une confirmation interactive** avant un geste qui peut couper l'accès (décision 45) ;
  côté Ansible, la sécurité repose sur la discipline du `--check --diff` préalable.
- **Un message d'erreur par cause**, écrit pour être lu ; Ansible rend un `fail_msg` noyé
  dans sa propre sortie.

### Défauts du registre évités, ou non

| Défaut connu du Bash | Dans le rôle |
|---|---|
| A132 — codes de retour d'`ufw`/`apt-get` remontés tels quels, difficiles à documenter | évité : les modules rendent un échec unique, avec le message de la commande |
| Fichiers de cas longs et coûteux à relire (mémoire « sobriété », ~150 lignes visées) | évité : 190 lignes utiles de scénario pour trois domaines, là où le Bash en demande 672 |
| Idempotence « démontrée en exécutant deux fois » à la main dans chaque cas | évité : étape `idempotence` de Molecule |
| Gardes anti-verrouillage non éprouvées par leurs chemins d'échec | **non évité** : le scénario n'éprouve que le chemin nominal (A157) |
| Preuve limitée à Debian 12 (profil des tests Bash) | évité : Debian 12 **et** Ubuntu 24.04 |

### Durée

| | Durée mesurée |
|---|---|
| `molecule test` complet, deux distributions, poste de travail | **328 s** (5 min 28 s), images de base déjà tirées |
| `tests/run.sh integration`, tout le niveau, poste de travail | ~12 min (TASK-080), une seule distribution |

Le rôle est donc éprouvé sur **deux** distributions en moins de la moitié du temps que le
niveau `integration` demande sur une seule — mais la comparaison est indicative : ce niveau
couvre bien plus que les trois scripts de sécurité.

## Réserves

- Les gardes anti-verrouillage du rôle ne sont éprouvées par aucun scénario : Molecule ne
  joue que le chemin nominal. Compte absent, sans clé ou hors de sudo, `Include` manquant,
  port d'écoute différent, règle `deny` préexistante, `sshd -t` en échec et la restauration
  qui s'ensuit : tout cela est écrit, relu, jamais exécuté (A157).
- `juger.sh` ne sait pas juger une tâche sans script Bash : son 1 est ici « sans objet »
  (A158).
- `Ansible/ansible.cfg` n'est jamais lu depuis le dépôt sur `/mnt/d`, qu'Ansible juge
  « world writable » : `roles_path`, `host_key_checking`, `forks` et `pipelining` ne
  s'appliquent pas aux commandes lancées de là — ce qui vaudra aussi pour le
  `--check --diff` sur un VPS (A159).
- Les images de base du scénario sont figées jusqu'à un `docker pull` manuel, conséquence
  de `pull: false` (A160).
- `PermitRootLogin no` (`disable-root-login.sh`) n'a pas d'équivalent dans le rôle : la
  fiche l'excluait, et un serveur configuré par le seul rôle garde la connexion directe de
  root telle que la distribution la laisse (A161).
- `ansible-lint` émet cinq avertissements « Invalid value (None) for resolved_fqcn attribute
  of community.general.ufw module » : bruit de l'outil, sans effet sur le verdict, non
  versé au registre faute d'action possible de notre côté.

## Ce qui t'est demandé

1. **Le niveau machine.** Depuis `Ansible/`, sur un VPS et un seul :

   ```bash
   ansible-playbook playbooks/securite.yml --check --diff --limit vps1
   ```

   Il faut d'abord déclarer `securite_base_compte_admin` dans `host_vars/vps1.yml` — le
   compte non-root, membre de sudo, dont la clé est déjà dans `authorized_keys`. Sans lui,
   le rôle refuse de démarrer, et c'est voulu. Si `ansible.cfg` semble ignoré, voir A159.

2. **La décision du pilote.** Poursuivre la migration — les rôles suivants, et le sort des
   scripts Bash correspondants — ou s'arrêter là et garder Ansible pour ce seul usage. Le
   bilan ci-dessus est la matière ; la question reste tienne.

## Git

(à compléter)
