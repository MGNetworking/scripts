---
id: TASK-025
title: "Écrire Linux/System/manage-users.sh"
status: ready
priority: medium
depends_on: []
environment: container-debian
human_approval_required: true
objective: |
  Livrer le script qui crée un compte d'administration utilisable — utilisateur,
  groupes, appartenance à sudo et clé SSH publique — sans qu'aucun mot de passe
  n'existe dans le script ni dans le dépôt. C'est ce compte que configure-ssh.sh
  exigera de trouver avant de couper l'accès par mot de passe.
scope:
  - Linux/System/manage-users.sh
  - tests/integration/manage-users.test.sh
  - config/server.env.example — nom du compte d'administration et chemin de sa clé publique
  - Linux/System/README.md — ligne du tableau, utilisation, risques, ordre avec Linux/Security
  - README.md — ligne du tableau des scripts
out_of_scope:
  - la suppression d'un utilisateur, userdel et la destruction d'un répertoire personnel — tâche distincte, réellement destructive
  - le verrouillage, le déverrouillage et l'expiration d'un compte
  - la définition, la lecture, la génération ou la modification d'un mot de passe
  - la génération d'une paire de clés SSH — le script dépose une clé publique fournie, il n'en fabrique pas
  - le retrait d'une clé de authorized_keys ou d'un utilisateur d'un groupe
  - la configuration du démon SSH, qui appartient à Linux/Security/configure-ssh.sh
  - l'installation du paquet sudo et la création du groupe sudo
  - les utilisateurs système, les comptes de service et les utilisateurs LDAP ou annuaire
acceptance_criteria:
  - le script crée un utilisateur avec son répertoire personnel et un shell de connexion, et ne fait rien si l'utilisateur existe déjà
  - aucun mot de passe n'est défini, lu, généré ni demandé, et le script le dit à l'écran
  - il ajoute l'utilisateur aux groupes demandés sans jamais retirer une appartenance existante
  - l'appartenance au groupe sudo est demandée par une option explicite, jamais accordée par défaut
  - lorsque le groupe sudo n'existe pas, le script s'arrête en 1 en nommant ce qui manque, sans créer le groupe ni installer le paquet
  - lorsque le groupe sudo existe mais que la commande sudo est absente, le script avertit et poursuit
  - la clé publique fournie est déposée dans authorized_keys avec un répertoire .ssh en 0700, un fichier en 0600 et l'utilisateur pour propriétaire
  - une clé déjà présente n'est pas dupliquée, et une seconde exécution complète ne modifie rien — vérifié par empreinte
  - une clé mal formée est refusée en 2 avant toute écriture, et la validation ne dépend pas de la présence de ssh-keygen
  - un nom d'utilisateur invalide au regard des règles de useradd est refusé en 2 avant toute action
  - le script refuse en 2 de prendre root pour cible
  - sans privilège, le script rend 1, et une ligne de commande à la fois fautive et sans privilège rend 2
  - --dry-run énumère chaque action qui serait faite, dans l'ordre, et ne modifie rien
  - --help documente les options, ce que le script ne fait pas, et l'avertissement sur sudo sans mot de passe
  - le résumé final indique comment vérifier la connexion et ce qu'il reste à faire avant de durcir SSH
validation:
  - "tests/run.sh lint"
  - "tests/env/run-in-container.sh -- tests/run.sh lint"
  - "tests/env/run-in-container.sh -- tests/run.sh integration"
  - "tests/env/run-in-container.sh -- bash Linux/System/manage-users.sh --help"
  - "tests/env/run-in-container.sh -- bash Linux/System/manage-users.sh --utilisateur essai --dry-run"
implementation_notes:
  - ADR-0003 décision 20 — configure-ssh.sh et disable-root-login.sh refuseront d'agir sans un compte non-root disposant de sudo et d'une clé exploitable ; ce script est celui qui crée ce compte
  - useradd vient du paquet passwd, présent partout ; adduser est un script Debian dont la présence est moins sûre dans une image minimale
  - le groupe sudo n'existe pas dans l'image de test — c'est le cas nominal du refus, et le fichier de cas doit le créer lui-même pour éprouver le chemin nominal
  - ssh-keygen n'est pas dans l'image de test — le contrôle de forme d'une clé ne peut pas en dépendre
  - sudo ignore, sans rien dire, tout fichier de /etc/sudoers.d dont le nom contient un point ou se termine par un tilde — même piège que /etc/cron.d
  - toute affectation var="$(…)" se place en contexte de condition, motif tranché par TASK-018
---

# TASK-025 — Créer le compte d'administration

## Ce que le plan demande

[docs/refactorisation-plan.md](../../docs/refactorisation-plan.md) §1,
`manage-users.sh` : *créer des utilisateurs, gérer les groupes et sudo. Ne jamais
stocker de mots de passe dans le script.*

## Le rôle de ce script dans la chaîne — l'ordre compte

[ADR-0003](../../docs/agent/decisions/ADR-0003-cadrage-execution-autonome.md)
décision 20 pose une garde qu'il faut connaître avant d'écrire une ligne :

> `configure-ssh.sh` et `disable-root-login.sh` **refusent d'agir** tant qu'ils
> n'ont pas trouvé un compte non-root disposant de `sudo` et d'une clé SSH
> exploitable.

`manage-users.sh` est le script qui crée ce compte. Il est donc écrit **avant**
le domaine `Linux/Security` — ordre déjà fixé par la décision 16 — et son
invocation nominale est celle qui satisfait la garde :

```bash
sudo ./Linux/System/manage-users.sh --utilisateur max --sudo --cle-fichier /chemin/ma-cle.pub
```

Le README du domaine doit dire cet enchaînement. Un compte créé sans clé, ou
sans `sudo`, ne débloquera rien.

## Le nœud — aucun mot de passe, et pourtant `sudo` doit fonctionner

C'est le point que l'énoncé doit trancher, faute de quoi il sera tranché mal.

Le script ne pose aucun mot de passe : c'est la consigne du plan et c'est la
bonne posture pour un dépôt public. Mais `sudo` demande par défaut le mot de
passe de l'utilisateur — un compte qui n'en a pas ne peut donc pas élever ses
droits de façon interactive.

**Décision retenue**, réversible et locale au sens d'`AGENTS.md` §14 :

- le script **ne dépose aucune règle `NOPASSWD` par défaut** ;
- il **avertit explicitement**, en fin d'exécution, que tant qu'un mot de passe
  n'a pas été défini par `passwd <utilisateur>`, `sudo` refusera l'élévation
  interactive ;
- une option explicite — nommée sans ambiguïté, du genre
  `--sudo-sans-mot-de-passe` — dépose une règle dans `/etc/sudoers.d/`, et
  seulement si elle est demandée. C'est le choix que font les images cloud de
  Debian et d'Ubuntu ; il est légitime pour une machine administrée par clé
  uniquement, il ne peut pas être le défaut silencieux.

Si cette règle est déposée, trois précautions ne sont pas négociables :

| Précaution | Pourquoi |
|---|---|
| nom de fichier **sans point** et sans tilde final | `sudo` ignore ces fichiers **sans rien dire**, exactement comme `cron` dans `/etc/cron.d` |
| mode `0440`, propriétaire `root:root` | `sudo` refuse de lire un fichier trop permissif |
| `visudo -c -f <fichier>` **avant** mise en place | une syntaxe fautive dans `sudoers.d` peut rendre `sudo` inutilisable pour tout le monde |

Le fichier se construit à côté puis se renomme, sur le modèle exact de
`configure-cron.sh`.

## Pièges connus

**Le groupe `sudo` n'existe pas dans l'image de test.** `debian:12` n'embarque
pas le paquet `sudo`. C'est une chance : le chemin de refus est éprouvable
gratuitement. Le chemin nominal, lui, demande que le fichier de cas crée le
groupe lui-même — `groupadd sudo` — puisque le script, par périmètre, ne le crée
pas. Écrire cette fixture explicitement, sinon le cas nominal ne tournera jamais.

**Le contrôle de forme d'une clé ne peut pas reposer sur `ssh-keygen`**, absent
de l'image. Une clé publique se reconnaît sans lui : une seule ligne, un type
connu — `ssh-ed25519`, `ssh-rsa`, `ecdsa-sha2-*`, `sk-*` —, un second champ en
base64, un commentaire facultatif. `ssh-keygen -l -f` peut compléter le contrôle
quand il existe, jamais le porter.

**Les permissions d'`authorized_keys` sont vérifiées par le démon SSH**, qui
refuse silencieusement une clé si `.ssh` ou le fichier sont trop permissifs, ou
si le répertoire personnel est inscriptible par le groupe. Une clé bien déposée
mais mal protégée donne exactement le symptôme le plus difficile à diagnostiquer :
une connexion refusée sans raison visible.

**`useradd` ne crée pas le répertoire personnel sans `-m`**, et le shell par
défaut de `useradd` est `/bin/sh` sur Debian — un compte d'administration créé
sans `-s` se retrouve avec un shell qui n'est pas celui attendu.

**Les règles de nommage sont celles de `useradd`** : commencer par une lettre
minuscule ou un souligné, puis lettres minuscules, chiffres, souligné et tiret,
trente-deux caractères au plus. Un nom refusé par `useradd` doit l'être par le
script, en 2, avant toute action — même logique que le refus d'un fuseau
inexistant par `configure-timezone.sh`.

**Le montage Docker Desktop expose les fichiers du dépôt en 0777.** Un fichier de
cas qui voudrait éprouver le mode d'une clé publique **fournie depuis `/depot`**
mesurerait le montage, pas le script. Les fixtures se créent hors de `/depot`.

## Décisions déjà prises, à ne pas reposer

| Question | Réponse | Source |
|---|---|---|
| cibles | Debian 12 et 13, Ubuntu 22.04 et 24.04 | ADR-0003 décision 14 |
| privilège insuffisant | code 1 | ADR-0003 décision 10 |
| valeur refusée, option inconnue | code 2, avant toute action | TASK-016 |
| valeurs propres à la machine | `config/server.env` | ADR-0003 décision 24 |
| tâche sensible | s'exécute quand même, en conteneur jetable | ADR-0003 décision 2 |

## Codes de retour attendus des validations

| Commande | Code |
|---|---|
| `tests/run.sh lint` | 0 |
| `run-in-container.sh -- tests/run.sh lint` | 0 |
| `run-in-container.sh -- tests/run.sh integration` | 0 |
| `run-in-container.sh -- bash …/manage-users.sh --help` | 0 |
| `run-in-container.sh -- bash …/manage-users.sh --utilisateur essai --dry-run` | 0, aucun utilisateur créé |

Le conteneur tourne en `root` : le cas « sans privilège » se joue comme dans
`tests/unit/common.test.sh`, en abaissant l'UID par `setpriv`, `runuser` ou
`chroot --userspec`, le premier qui y parvient réellement. Si aucun n'y parvient,
le cas est `NON EXÉCUTÉ`, jamais réussi.
