---
id: TASK-013
title: "Distinguer un cas non applicable d'un environnement indisponible"
status: ready
priority: medium
depends_on:
  - TASK-012
environment: host
human_approval_required: false
objective: |
  Fermer le faux vert que TASK-012 a laissé ouvert : un fichier de cas dont
  l'environnement est indisponible sort aujourd'hui en 4, donc en 0 au bout de
  la chaîne, alors que rien d'essentiel n'a été prouvé.
scope:
  - tests/acceptance/run-acceptance.sh — compteur des indisponibilités
  - tests/run.sh — traitement du nouveau verdict
  - tests/acceptance/TASK-002-environnement-conteneurise.sh — qualifier ses sauts
  - tests/acceptance/TASK-011-analyse-statique.sh — qualifier ses sauts
  - tests/acceptance/TASK-012-semantique-codes.sh — qualifier ses sauts
  - tests/README.md — la sémantique retenue
  - docs/points-en-suspens.md — marquer le point 3 comme traité
out_of_scope:
  - toute modification des assertions elles-mêmes — seule la nature du saut se qualifie
  - le profil de conteneur systemd
  - lib/common.sh — zone protégée
acceptance_criteria:
  - un saut se déclare avec sa nature — non applicable par nature, ou environnement indisponible
  - un fichier de cas comportant au moins une indisponibilité ne sort jamais en 0 ni en 4
  - un fichier ne comportant que des non-applicables par nature sort toujours en 4
  - le démon Docker coupé fait sortir tests/run.sh acceptance en code non nul
  - les deux natures sont affichées séparément dans le bilan de chaque fichier
  - la sémantique est documentée dans tests/README.md
  - aucun cas existant ne change de verdict lorsque l'environnement est complet
  - le fichier de cas de cette tâche ne compte aucun échec ; son code 4 est admis, comme pour tout fichier comportant des cas non applicables
validation:
  - "tests/run.sh lint"
  - "tests/run.sh acceptance"
  - "tests/acceptance/TASK-013-natures-de-saut.sh"
implementation_notes:
  - le scénario de référence est mesuré dans docs/points-en-suspens.md §3
  - éprouver l'indisponibilité par DOCKER_HOST sur port fermé ou PATH amputé, jamais en arrêtant Docker Desktop
  - la qualification touche chaque appel « saute » — c'est un travail de relecture ligne à ligne, pas une transformation mécanique
  - un saut dont la nature est ambiguë vaut indisponibilité : c'est le choix prudent
  - attention au piège : la règle ci-dessus s'oppose au critère « aucun cas existant ne change de verdict ». Les sauts existants — systemd, swapon, apt sans paquet obsolète, groupe adm — sont non applicables PAR NATURE et doivent le rester, sinon les fichiers passent de 4 à 3 et tests/run.sh acceptance devient rouge
  - le seul cas réellement ambigu est celui des six contrôles de forme du diff de TASK-011, devenus NON EXÉCUTÉ après leur commit. Si les qualifier en indisponibilité fait basculer ce fichier en 3, il faut soit les traiter à part, soit bloquer et le dire — pas les qualifier au jugé pour que le vert tienne
---

# TASK-013 — Nature des sauts

## Origine

[TASK-012](../completed/TASK-012.md) a levé un blocage qui frappait toutes les
tâches : le harnais confondait « rien de prouvé » et « quelques cas non
applicables », et refusait des travaux dont les 156 vérifications passaient.

Elle a résolu ce problème en introduisant le code 4 — preuve partielle — gardé
par la règle « au moins une réussite ». Ce garde ferme le scénario *tout est
sauté, donc tout va bien*.

Il ne ferme pas *presque tout est sauté*. Mesuré, démon Docker coupé :

```text
Bilan TASK-011 : 8 réussite(s), 0 échec(s), 21 NON EXÉCUTÉ(s)   → 4
tests/run.sh acceptance                                          → 0
```

72 % de la preuve évaporée, verdict vert. Quelques cas de préflight, qui n'ont
besoin de rien, suffisent à franchir le seuil.

## La distinction à introduire

| Nature | Exemple | Verdict |
|---|---|---|
| **non applicable par nature** | le profil `debian` n'a pas `systemd` et ne l'aura jamais | 4 légitime |
| **environnement indisponible** | le démon Docker est coupé — la preuve existe, elle n'a pas pu être produite | 3 : rien n'est prouvé |

La première est une limite assumée de l'environnement de test. La seconde est un
accident qui doit interrompre le verdict.

## Le travail réel

Ce n'est pas une transformation mécanique. Chaque appel `saute` des trois
fichiers de cas doit être **relu et qualifié** : ce cas est-il hors d'atteinte
par nature, ou l'environnement a-t-il manqué ?

Règle de prudence pour les cas ambigus : **la nature ambiguë vaut
indisponibilité**. Mieux vaut un verdict rouge à tort qu'un vert à tort — c'est
la logique de tout le harnais depuis TASK-001.

## Pourquoi ce n'est pas urgent

Le défaut ne se manifeste que si l'environnement tombe en cours de campagne.
Quand tout fonctionne, les verdicts sont justes. C'est une protection contre un
accident, pas une correction de comportement courant.

Mais c'est exactement le genre d'accident qui s'est produit deux fois en une
seule journée le 2026-08-29, Docker Desktop s'étant arrêté seul.
