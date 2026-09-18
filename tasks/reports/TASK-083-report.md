# TASK-083 — Essai DeepSeek sur une tâche documentaire

## Compte rendu

Objectif : mesurer ce que vaut un agent DeepSeek sur une tâche purement
documentaire — ajouter aux contrats de `Docker/CADRAGE.md` (3 scripts de
Diagnostics/) et `Kubernetes/CADRAGE.md` (7 scripts de Maintenance/) une ligne
« Prouvé par : <fichier de cas> — niveau <preuve> » — face aux conducteurs Opus
qui avaient écrit ces mêmes cadrages (TASK-074 à 077, 114 000 à 260 000 jetons).

L'agent a rendu VERDICT ECHEC, mais la cause tient au juge automatique, pas au
travail : `orchestration/outils/juger.sh` ne reconnaît qu'un périmètre `.sh` ou
Ansible (rôle + scénario Molecule) ; un `scope` réduit à deux `CADRAGE.md`
tombe dans la même ligne « aucun fichier de cas dans le périmètre » qu'une
fiche mal formée. Anomalie versée au registre en A172.

Vérification faite à la main, en reprenant l'étape 5 : le périmètre du diff
(`git diff --name-only master...agent/TASK-083`) ne touche que les deux
`CADRAGE.md` prévus, 20 lignes ajoutées, 0 supprimée. Les 10 lignes « Prouvé
par » sont exactement celles attendues, niveau « simulé » partout — juste, la
décision 50 l'impose tant qu'aucun démon Docker ni cluster K8s réel n'est
engagé sur l'hôte. Les 10 fichiers de cas cités existent tous et portent
chacun de 28 à 123 assertions liées à leur script.

La relecture Opus a rendu FUSIONNABLE, avec deux défauts MINEURS : la section
« Historique du cadrage » des deux fichiers n'avait reçu aucune ligne, alors
qu'`Ansible/CADRAGE.md` en portait déjà une pour un ajout comparable ; ce
rapport manquait. Les deux ont été corrigés par le conducteur avant clôture,
une passe, comme le prévoit `regles.md` §6.

**Bilan de l'essai** — DeepSeek : 34 tours, 16 356 jetons de sortie, 145 s,
0,057 $, contre 114 000 à 260 000 jetons pour les conducteurs Opus des
cadrages eux-mêmes (TASK-074 à 077, tâches plus larges mais de même nature
documentaire). Aucun défaut MAJEUR relevé par la relecture, deux MINEURS
seulement, tous deux hors des critères d'acceptation de la fiche. Recomman-
dation : basculer les tâches documentaires comparables (ajout de lignes à un
contrat déjà structuré, sans décision d'architecture) sur DeepSeek ; réserver
Opus aux tâches qui créent la structure elle-même (premier jet d'un cadrage,
choix de contrat). Réserve : corriger d'abord A172, pour que le juge conclue
seul sur ce type de périmètre au lieu d'exiger une vérification manuelle.

## Statut

COMPLETED

## Objectif

Ajouter aux contrats de `Docker/CADRAGE.md` et `Kubernetes/CADRAGE.md` une
ligne « Prouvé par » par script, avec le fichier de cas et le niveau de preuve
définis par la décision 50, sur un périmètre confié à un agent DeepSeek.

## Travail réalisé

- 10 lignes « Prouvé par » ajoutées : 3 dans `Docker/CADRAGE.md` (ensemble
  « Moteur Docker », scripts de Diagnostics/), 7 dans `Kubernetes/CADRAGE.md`
  (ensemble « Gestion de Kubernetes », scripts de Maintenance/), toutes de
  niveau simulé.
- Ligne ajoutée à la section « Historique du cadrage » des deux fichiers
  (correction du conducteur après relecture).
- Rapport écrit (correction du conducteur après relecture).

## Fichiers modifiés

| Fichier | Nature |
|---|---|
| `Docker/CADRAGE.md` | +4 lignes : 3 « Prouvé par » (agent), 1 ligne d'historique (conducteur) |
| `Kubernetes/CADRAGE.md` | +8 lignes : 7 « Prouvé par » (agent), 1 ligne d'historique (conducteur) |
| `tasks/pending/TASK-039.md` | +1 ligne, A172 : branche documentaire manquante de `juger.sh` |
| `orchestration/mesures/agents.tsv` | +1 ligne `deepseek` (premier jet), +1 ligne `relecteur` |

## Commandes et codes réels

Niveau de preuve : **hôte** — lecture de fichiers, comptage de lignes, pas
d'exécution de script.

| Commande | Code | Sortie |
|---|---|---|
| `bash orchestration/outils/lancer-agent.sh deepseek TASK-083` | 0 | agent DeepSeek, VERDICT ECHEC de `juger.sh` (A172), livrable complet |
| `git diff --name-only master...agent/TASK-083` | — | `Docker/CADRAGE.md`, `Kubernetes/CADRAGE.md` seuls |
| `git diff master...agent/TASK-083 -- Docker/CADRAGE.md Kubernetes/CADRAGE.md` | — | 20 ajouts, 0 suppression, 10 lignes « Prouvé par » |
| boucle `grep -cE 'assert_\|ok \|ko \|saute'` sur les 10 fichiers de cas cités | — | 28 à 123 assertions par fichier, tous existants, tous liés à leur script |
| `bash orchestration/outils/verifier-liens.sh` | 0 | aucun lien mort |

## Validations de la fiche

| Validation | Code |
|---|---|
| `bash orchestration/outils/verifier-liens.sh` | 0 |

## Relecture

Relecteur `opus`, une lecture, 16 appels d'outils, 37 665 jetons, 89 s.
Verdict : FUSIONNABLE. Deux MINEURS, tous deux corrigés avant clôture :
« Historique du cadrage » sans ligne pour l'ajout, rapport absent. Aucun test
creux (la fiche n'en livre pas, tâche documentaire).

## Git

- branche `agent/TASK-083`, un commit `feat: premier jet (TASK-083)` (agent), un
  commit du conducteur pour les deux corrections mineures ;
- fusion `--no-ff` dans `master`, copie et branche supprimées ;
- périmètre du diff `master...agent/TASK-083` : `Docker/CADRAGE.md`,
  `Kubernetes/CADRAGE.md` — conforme au `scope` ;
- aucun fichier de `tests/` touché : le nombre d'assertions du dépôt est
  inchangé, conforme à `out_of_scope`.

## Réserves

- `juger.sh` n'a pas de branche pour un périmètre purement documentaire
  (ni `.sh` ni rôle Ansible) : il rend FAIL au lieu d'un verdict « sans
  objet » ou d'un contrôle propre (A172).
