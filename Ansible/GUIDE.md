# Guide — comment fonctionne l'outil de préparation des serveurs

Ce guide s'adresse à qui n'a jamais employé Ansible. Il raconte le trajet d'une
commande, du clavier jusqu'au serveur, et définit chaque mot technique la première
fois qu'il paraît. Ce que le dossier **engage** est écrit dans [CADRAGE.md](CADRAGE.md) ;
comment **installer** l'outillage sur le poste, dans [README.md](README.md).

## 1. Le trajet, en une image

```text
  Le poste de travail (WSL Ubuntu)              Le serveur
  ────────────────────────────────              ──────────
  le dépôt Git, cloné ici                       rien du dépôt
  Ansible, installé ici                         rien d'Ansible
  les recettes, lues ici                        aucun agent, aucun service
                    │
                    │  SSH : on ouvre une connexion, on commande, on raccroche
                    └──────────────────────────▶  la commande s'exécute
```

**SSH** (« Secure Shell ») est le moyen d'ouvrir une session sur une machine
distante. **Ansible** est un programme qui tourne sur le poste, pas sur le serveur :
il s'y connecte par SSH, y lance des commandes, puis referme la connexion.

Il n'installe donc **rien de durable** sur le serveur : ni lui-même, ni le dépôt, ni
un agent qui resterait à tourner. Le serveur n'a besoin que de SSH et de Python, qu'il
possède déjà.

## 2. Les quatre mots à connaître

**Inventaire** — la liste des machines à préparer, avec de quoi les joindre : adresse,
compte, port. C'est un fichier, [`inventory.example.yml`](inventory.example.yml), dont
chacun copie le modèle chez soi.

**Rôle** — un dossier qui décrit **une** chose à garantir sur une machine, et comment
la garantir : « l'accès SSH ne s'ouvre qu'à une clé », « le pare-feu est fermé en
entrée ». Ansible lit ce dossier et amène la machine à cet état. Le dossier
[`roles/`](roles) en porte un seul pour l'instant, `securite_base`.

**Playbook** (ou **recette**) — un fichier qui dit quels rôles appliquer, à quelles
machines, dans quel ordre. [`playbooks/securite.yml`](playbooks/securite.yml) applique
`securite_base` aux machines du groupe « vps ».

**Idempotence** — la propriété qui fait qu'une seconde exécution ne change plus rien.
Ansible ne rejoue pas des ordres à l'aveugle : il regarde l'état actuel de la machine,
le compare à l'état voulu, et n'agit que sur ce qui diffère. C'est ce qui rend un rôle
rejouable sans risque.

## 3. Ce qui se passe quand on lance une recette

1. Ansible lit l'**inventaire** et retient les machines visées.
2. Il ouvre une connexion **SSH** vers chacune et y pose un petit programme le temps
   de l'exécution, puis le retire.
3. Il parcourt le **rôle** tâche par tâche, compare l'état trouvé à l'état voulu et
   n'écrit que ce qui manque.
4. Il affiche, machine par machine, ce qui a changé — et ce qui n'a pas changé, ce qui
   est le signe que l'**idempotence** tient.

## 4. Prouver, sans avoir de serveur

Deux machines d'essai suffisent, et elles n'existent que le temps du test : ce sont des
**conteneurs**, c'est-à-dire des machines simulées, montées puis détruites par Docker —
le logiciel qui fait tourner de telles machines sur le poste. **Molecule** est l'outil qui
les fabrique, y joue le rôle, vérifie le résultat, rejoue le rôle une seconde fois pour
éprouver l'**idempotence**, puis efface tout.

Les niveaux de preuve se nomment toujours : **simulé** (la logique seule), **conteneur**
(le rôle joué réellement, dans une machine jetable) et **machine** (le constat fait sur
un vrai serveur). Un test vert en conteneur ne prouve rien sur un serveur réel — seule
une exécution sur le serveur le fera.

## 5. Où vivent les informations, et ce qui ne part jamais sur GitHub

Le dépôt est **public**. Ce qui suit vit sur le poste et n'entre jamais dans le dépôt :

| Quoi | Où il vit | Sur GitHub |
|---|---|---|
| l'inventaire réel (`Ansible/inventory.yml`) | dans `Ansible/`, sur le poste | jamais |
| les variables par machine (`Ansible/host_vars/<hôte>.yml`) | dans `Ansible/host_vars/` | jamais |
| la clé SSH privée | dans `~/.ssh/`, **hors du dépôt** | jamais |
| un secret (mot de passe, jeton) | chiffré dans un fichier, ou hors du dépôt | jamais en clair |

Ce qui est versionné, à la place, sont des **modèles** : `inventory.example.yml`,
`host_vars/*.example.yml`. Leurs adresses appartiennent au bloc `203.0.113.0/24`
réservé à la documentation : elles ne joignent aucune machine.

Le fichier [`.gitignore`](../.gitignore) met ces règles à exécution. Il écarte
`Ansible/inventory*` (sauf les modèles `*.example.yml`), `Ansible/hosts*`, tout
`Ansible/host_vars/` et `Ansible/group_vars/` sauf les `*.example.yml`, et tout fichier
`vault*` ou `*.vault.yml`. La clé privée, elle, n'a pas besoin d'une règle : elle n'est
pas dans le dépôt — c'est `host_vars/<hôte>.yml` qui indique à Ansible où la prendre,
par `ansible_ssh_private_key_file`.

Un **coffre** (Ansible Vault) répond au cas où un secret doit voyager avec le dépôt :
le fichier reste chiffré, Git ne voit que des caractères illisibles, et Ansible le
déchiffre au moment de l'emploi. On l'ouvre avec une phrase de passe, jamais versionnée.

Pour vérifier avant un commit qu'un fichier réel est bien écarté :

```bash
git check-ignore -v Ansible/inventory.yml Ansible/host_vars/vps1.yml
```

## 6. Les commandes du quotidien

Toutes se lancent **depuis `Ansible/`** : Ansible ne lit son fichier de configuration
`ansible.cfg` que dans le dossier courant.

```bash
cp inventory.example.yml inventory.yml                  # une fois, puis compléter
cp host_vars/vps1.example.yml host_vars/vps1.yml        # une fois par machine

ansible-inventory --graph                               # ce qu'Ansible a compris
ansible all -m ansible.builtin.ping                     # les machines répondent-elles
```

La vérification qui ne touche à rien — elle tourne dans un conteneur jetable, et
n'installe rien sur le poste :

```bash
tests/env/run-in-container.sh --profil ansible -- tests/env/valider-ansible.sh
```

`yamllint` y relit la mise en forme des fichiers, `ansible-lint` la qualité des rôles,
puis Molecule les éprouve. C'est la commande de référence, celle que l'intégration
continue exécute — la vérification automatique lancée à chaque envoi sur GitHub.

Puis, pour appliquer un rôle à une machine — **la simulation d'abord** :

```bash
ansible-playbook playbooks/securite.yml --check --diff --limit vps1
```

`--check` demande ce qui serait fait sans le faire, `--diff` montre le détail des
changements, `--limit vps1` restreint à une seule machine. Rien n'est modifié.

Quand le rapport est celui qu'on attend, **la même commande sans `--check`** applique
réellement :

```bash
ansible-playbook playbooks/securite.yml --limit vps1
```

L'application réelle est **votre** geste, jamais celui d'un agent — l'assistant
automatique qui travaille sur le dépôt : un agent ne lance `ansible-playbook` qu'avec
`--check`, ou dans un conteneur de test.

## 7. Le jour où vous aurez un serveur

Dans l'ordre :

1. **Avoir la machine** et son adresse, ainsi que le compte qui y donne accès.
2. **Vérifier qu'on s'y connecte** en SSH par clé depuis le poste — la clé publique
   déposée sur le serveur, la clé privée dans `~/.ssh/`. Sans cela, rien ne suivra.
3. **Écrire l'inventaire réel** : `cp inventory.example.yml inventory.yml`, puis y
   mettre l'adresse, le compte et le port de la machine. Ce fichier ne part pas sur
   GitHub.
4. **Écrire ses variables** : `cp host_vars/vps1.example.yml host_vars/vps1.yml`, puis
   y indiquer la clé privée à employer et le compte administrateur de la machine
   (`securite_base_compte_admin`). Pas de secret en clair : un coffre ou un fichier
   hors du dépôt.
5. **Vérifier que Git l'ignore** — `git check-ignore -v Ansible/inventory.yml
   Ansible/host_vars/vps1.yml` doit citer chaque fichier.
6. **Simuler** : `ansible-playbook playbooks/securite.yml --check --diff --limit vps1`,
   puis lire le rapport. Si une garde refuse — compte administrateur introuvable, ou
   aucune clé déclarée —, c'est le signe qu'il manque une étape : corriger la machine,
   pas le rôle.
7. **Appliquer**, une fois le rapport conforme : la même commande sans `--check`.
8. **Rejouer** la même commande : au second passage, plus rien ne doit changer. C'est
   l'idempotence, et c'est la preuve que la machine est à l'état voulu.
9. **Recommencer** pour la machine suivante — un serveur à la fois, avec `--limit`.

Ce que le rôle garantit exactement, et ce qu'il refuse de faire, est au
[cadrage](CADRAGE.md) : c'est le contrat, pas le mode d'emploi.

## 8. Ce que l'outil ne fait pas

Préparer une machine relève d'Ansible ; **observer** une machine déjà préparée et
**l'exploiter** ponctuellement (diagnostic en lecture seule, sauvegarde, nettoyage,
redémarrage) restent des scripts Bash, dans les dossiers `Linux/`, `Docker/`,
`Kubernetes/` et `Synology/`. La répartition est fixée par la
[décision 50](../orchestration/decisions.md). Ansible est en **pilote** : tant que le
bilan n'a pas eu lieu, les scripts Bash restent la référence.
