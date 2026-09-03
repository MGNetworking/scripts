---
id: TASK-021
title: "Écrire Linux/System/check-disk.sh"
status: completed
priority: medium
depends_on: []
environment: container-debian
human_approval_required: false
objective: |
  Livrer le diagnostic de stockage du domaine — occupation des systèmes de
  fichiers, inodes, périphériques et répertoires consommateurs — en lecture
  seule stricte, sans privilège, et sans jamais mourir parce qu'une information
  manque.
scope:
  - Linux/System/check-disk.sh
  - tests/integration/check-disk.test.sh
  - config/server.env.example — le seuil d'occupation et le répertoire analysé
  - Linux/System/README.md — ligne du tableau, utilisation, risques
  - README.md — ligne du tableau des scripts
out_of_scope:
  - toute action corrective — suppression de fichier, purge de journaux, apt-get clean, nettoyage Docker
  - la santé matérielle des disques — smartctl, badblocks, températures
  - le diagnostic mémoire, qui est l'objet de TASK-022
  - la notification d'un seuil dépassé, qui est l'objet de TASK-024
  - un seuil différent par système de fichiers — un seuil global suffit et se surcharge
  - la lecture d'un système de fichiers distant monté par NFS ou CIFS, qu'un df peut suspendre indéfiniment
acceptance_criteria:
  - le script s'exécute sans aucun privilège et rend 0
  - il n'écrit rien en dehors du journal ouvert par lib/common.sh — aucun fichier créé, modifié ni supprimé ailleurs
  - il affiche l'occupation de chaque système de fichiers réel avec taille, utilisé, disponible, pourcentage et point de montage
  - les pseudo-systèmes de fichiers sont écartés de l'affichage par défaut, mais overlay ne l'est pas — sans quoi un conteneur n'afficherait aucune ligne
  - il affiche l'occupation des inodes, et dit « non disponible » pour un système de fichiers qui n'en déclare pas plutôt que d'afficher un pourcentage faux
  - il affiche les périphériques et partitions, et se replie sur /proc/partitions quand lsblk est absent
  - il affiche les répertoires les plus consommateurs sous un répertoire donné, sans franchir les points de montage, à une profondeur bornée et pour un nombre d'entrées borné
  - une commande absente ou en échec — lsblk, du, df — produit un avertissement nommant la cause et « non disponible » à l'affichage, jamais l'arrêt du script
  - un système de fichiers dont l'occupation dépasse le seuil est signalé par un WARN, sans que le code de retour en soit changé
  - le seuil et le répertoire analysé se surchargent par config/server.env puis par la ligne de commande, la ligne de commande primant
  - une option inconnue rend 2, et une valeur de seuil non numérique ou hors de 1 à 100 rend 2, sans que rien n'ait été lu
  - --help documente les options, les valeurs par défaut, leur origine et les codes de retour
  - une seconde exécution consécutive produit le même diagnostic et laisse le système inchangé
validation:
  - "tests/run.sh lint"
  - "tests/env/run-in-container.sh -- tests/run.sh lint"
  - "tests/env/run-in-container.sh -- tests/run.sh integration"
  - "tests/env/run-in-container.sh -- bash Linux/System/check-disk.sh"
  - "tests/env/run-in-container.sh -- bash Linux/System/check-disk.sh --help"
implementation_notes:
  - system-info.sh est le modèle — mise en page par « ligne », dégradation en « non disponible », aucune dépendance exigée
  - toute affectation var="$(…)" se place en contexte de condition, motif tranché par TASK-018 et documenté dans Linux/System/recensement-substitutions.md
  - la racine du conteneur de test est un overlay et son occupation est celle de l'hôte — aucune assertion ne peut porter sur une valeur absolue
  - ADR-0003 décision 24 — un seuil est une valeur de machine, il passe par config/
---

# TASK-021 — Diagnostic de stockage

## Ce que le plan demande

[docs/refactorisation-plan.md](../../docs/refactorisation-plan.md) §1,
`check-disk.sh` : *diagnostic de `df`, partitions, inodes et répertoires
consommateurs*. Quatre sections, et rien de plus.

## Lecture seule stricte — ce que cela veut dire ici

Trois exigences distinctes, à ne pas confondre :

- **aucune écriture** hors du journal que `lib/common.sh` ouvre au chargement.
  Le fichier de cas d'intégration le prouve par un `find -newer`, comme il le
  fait déjà pour `system-info.sh` ;
- **aucun privilège requis.** Le script ne contient pas de `require_root`. Il
  rend 0 lancé par un compte ordinaire — `system-info.sh` fait exception au 1 du
  domaine pour cette raison exacte, et `Linux/System/README.md` l'écrit déjà ;
- **la dégradation plutôt que la mort.** C'est le comportement établi du domaine
  et il a été payé cher : sous un binaire homonyme en tête de `PATH`,
  `system-info.sh` avertit, affiche « non disponible » et **sort en 0**. Voir
  `tests/README.md`, « Les échecs qui ne sont pas fatals ».

## Décisions déjà prises, à ne pas reposer

| Question | Réponse | Source |
|---|---|---|
| cibles | Debian 12 et 13, Ubuntu 22.04 et 24.04 | ADR-0003 décision 14 |
| code d'une option inconnue | 2 | ADR-0003 décision 10, `docs/architecture-technique.md` |
| où vit un seuil | `config/server.env`, surchargeable en ligne de commande | ADR-0003 décision 24 |
| forme des affectations | contexte de condition | TASK-018 |

## Décisions que cette tâche tranche, pour qu'elles ne le soient pas à l'exécution

**Un seuil dépassé ne change pas le code de retour.** Le script rend 0 quoi
qu'il constate ; seule une erreur d'usage rend 2. Un diagnostic est une lecture,
pas un verdict : faire rendre 1 à un disque plein transformerait chaque passage
en tâche planifiée en échec, et c'est le rôle de `security-check.sh` — plan §2 —
que de produire des statuts `PASS` / `WARNING` / `FAIL`.

**Le seuil par défaut est 85 %**, surchargeable par `SRV_DISK_SEUIL` puis par
`--seuil`. Valeur simple, réversible et locale, au sens d'`AGENTS.md` §14 ; à
documenter dans le rapport.

**L'analyse des répertoires est bornée et contournable.** `du` sur une racine de
plusieurs téraoctets prend des minutes. Trois bornes, toutes explicites dans
l'aide : le répertoire de départ (`--repertoire`, `SRV_DISK_REPERTOIRE`, défaut
`/`), l'absence de franchissement des points de montage (`-x`), la profondeur 1
et un nombre d'entrées affichées (`--top`, défaut 10). Une option
`--sans-repertoires` saute la section entière.

## Pièges connus

**Le conteneur de test n'a qu'un `overlay`.** Un filtre écrit naïvement — « ne
garder que `ext4`, `xfs`, `btrfs` » — n'afficherait **rien** dans le conteneur,
et le fichier de cas passerait au vert sur un écran vide. Écarter les
pseudo-systèmes (`tmpfs`, `devtmpfs`, `proc`, `sysfs`, `cgroup`…) est le bon
sens ; écarter `overlay` rendrait le script invérifiable ici et inutile sur un
hôte de conteneurs. Un `--tous` peut lever le filtre.

**Les inodes n'existent pas partout.** `df -i` rend `0` ou `-` sur btrfs, ZFS et
sur certains overlay. Une division ou un `%` calculé dessus produirait une
valeur fausse ; il faut afficher « non disponible ».

**`df` peut suspendre l'exécution** sur un montage réseau injoignable. C'est la
raison de l'exclusion portée en `out_of_scope` : le sujet mérite un traitement
propre — `df -l`, ou une borne de temps — et pas une demi-mesure glissée ici.
Le noter dans le rapport, et le verser à `docs/points-en-suspens.md` si le
travail le confirme.

**Le décompte de lignes d'un fichier de cas se mesure**, il ne se déduit pas.
Trois chiffres annoncés se sont révélés faux dans ce dépôt. Si le fichier de cas
compte des lignes de sortie, le chiffre vient d'une exécution.

## Codes de retour attendus des validations

| Commande | Code |
|---|---|
| `tests/run.sh lint` | 0 |
| `run-in-container.sh -- tests/run.sh lint` | 0 |
| `run-in-container.sh -- tests/run.sh integration` | 0 |
| `run-in-container.sh -- bash Linux/System/check-disk.sh` | 0 |
| `run-in-container.sh -- bash Linux/System/check-disk.sh --help` | 0 |

Le niveau `integration` est lancé **entier** : `run-integration.sh` découvre
tout `*.test.sh` du répertoire, le nouveau fichier est pris sans branchement.
`tests/run.sh` n'accepte que des niveaux, jamais un filtre par fichier — c'est
l'erreur d'énoncé qui a dû être corrigée sur TASK-003, TASK-004 et TASK-009.
