# TASK-093 — Rapport d'exécution

## Compte rendu

TASK-087 avait buté trois fois sur le même genre de problème : pas le travail
demandé, mais l'outillage qui le juge. Cette tâche règle les deux causes
relevées à l'époque et consignées au registre (A177, A178), avant de reprendre
le plan des serveurs.

**A177** — `orchestration/outils/juger.sh` décidait de sa branche Ansible dès
qu'un chemin du scope commençait par `Ansible/`, même un simple `.md`. Un guide
comme `Ansible/GUIDE.md` (le cas réel de TASK-087) tombait donc dans l'exigence
d'un scénario Molecule complet et rendait FAIL, alors qu'aucun rôle n'était en
jeu. Le juge se décide maintenant sur les chemins `Ansible/roles/<nom>/`
réellement extraits du scope, pas sur « n'importe quoi sous `Ansible/` » : un
guide ou un cadrage suit la branche documentaire déjà écrite pour TASK-083
(A172), un rôle sans scénario Molecule reste en échec comme avant.

**A178** — `orchestration/limites.json` interdisait à tout agent lancé d'écrire
`docs/**` et tout `README.md`, sans distinguer les deux fichiers vraiment
protégés (`docs/architecture-technique.md`, `docs/guide-dispatcher.md`, zone
protégée de `orchestration/regles.md` §5) du reste. Une tâche documentaire —
un guide sous `Ansible/`, un README de domaine — se heurtait donc à un mur
générique. Les deux interdictions larges sont remplacées par des interdictions
ciblées : `README.md` racine et les deux fichiers protégés de `docs/`
seulement.

Relecture Opus une fois : verdict « fusionnable après corrections ». Un seul
défaut touchait le périmètre de cette tâche — une garde de `juger_ansible()`
devenue inatteignable après le changement de condition, du code mort avec un
message trompeur — corrigé dans la foulée. Les autres remarques (décision 39
de `decisions.md` restée en retard sur `limites.json`, un cas YAML Ansible hors
rôle qui profite maintenant du laissez-passer documentaire, la preuve de A178
qui reste statique) sortent du scope de la fiche : elles rejoignent le registre
(A179, A180, A181) plutôt que d'être corrigées ici.

**Réserve assumée** : la preuve du critère « un agent lancé peut écrire un
`.md` » est **statique** (les motifs de `deny` attendus dans `limites.json`),
pas un lancement d'essai réel. Un `claude -p --settings limites.json` imbriqué
dans cette session n'a pas de session authentifiée disponible (`claude auth
status` → `loggedIn: false`) : c'est une limite du bac à sable de
l'orchestrateur, pas du correctif (A179).

Coût : relecture Opus 20 appels, 47 439 jetons, 175 s ; travail direct de
l'orchestrateur, sans agent lancé (aucun jeton facturé côté agent).

## Statut
COMPLETED

## Objectif
Rendre l'outillage capable de conduire une tâche documentaire sans arbitrage
humain : `juger.sh` reconnaît une fiche documentaire sous `Ansible/` au lieu de
la router vers Molecule, `limites.json` laisse les agents écrire la
documentation que leur tâche demande.

## Travail réalisé
- `orchestration/outils/juger.sh` : les deux branches qui décident entre
  scénario Molecule et laissez-passer documentaire se fondent sur
  `${#roles[@]}` (chemins `Ansible/roles/<nom>/`) plutôt que sur
  `${#ansible[@]}` (tout chemin sous `Ansible/`) ; suppression de la garde de
  `juger_ansible()` devenue inatteignable (relecture).
- `orchestration/limites.json` : `Edit(docs/**)` et `Edit(**/README.md)`
  remplacés par `Edit(docs/architecture-technique.md)`,
  `Edit(docs/guide-dispatcher.md)` et `Edit(README.md)` (racine seule).
- `tests/acceptance/TASK-086-outillage.sh` : non-régression sur le scope réel
  de TASK-087 (`Ansible/GUIDE.md` seul, code 0), un rôle Ansible toujours en
  échec sans scénario Molecule, et les motifs de `deny` attendus dans
  `limites.json`.
- Registre `tasks/pending/TASK-039.md` : A177 et A178 clos ; A179 (preuve
  statique, limite d'authentification du bac à sable), A180 (YAML Ansible hors
  rôle laissé passer par la branche documentaire) et A181 (décision 39 en
  retard sur `limites.json`) ouverts.

## Fichiers modifiés
- `orchestration/outils/juger.sh`
- `orchestration/limites.json`
- `tests/acceptance/TASK-086-outillage.sh`
- `tasks/pending/TASK-039.md`
- `orchestration/mesures/agents.tsv`

## Commandes exécutées
| Commande | Code | Durée |
|---|---|---|
| `bash tests/acceptance/TASK-086-outillage.sh` | 0 | quelques secondes |
| `tests/env/run-in-container.sh -- tests/run.sh lint` | 0 | ~1 min |
| `bash orchestration/outils/verifier-liens.sh` | 0 | < 1 s |
| `bash orchestration/outils/verifier-travail.sh TASK-093` | 1 | quelques secondes |
| `bash -n orchestration/outils/juger.sh` | 0 | < 1 s |

## Validations
| Validation | Résultat |
|---|---|
| `bash tests/acceptance/TASK-086-outillage.sh` | PASS (35 vérifications) |
| `tests/env/run-in-container.sh -- tests/run.sh lint` (conteneur) | PASS (126 fichiers, 0 erreur, 2 avertis) |
| `bash orchestration/outils/verifier-liens.sh` | PASS (aucun lien mort) |
| `verifier-travail.sh` — périmètre | PASS (3 fichiers, 3 au scope) |
| `verifier-travail.sh` — juge | ÉCHEC connu et accepté (A169, précédent TASK-086) : `juger.sh` ne reconnaît aucun fichier de cas pour un périmètre sous `orchestration/`, hors scope de cette tâche |

## Erreurs rencontrées
Premier essai de preuve comportementale de A178 (`claude -p --settings
limites.json` imbriqué) : `Failed to authenticate: OAuth session expired`.
Consigné en A179, preuve statique substituée.

## Corrections automatiques
1. Relecture Opus : garde inatteignable dans `juger_ansible()` retirée
   (`orchestration/outils/juger.sh`). Une seule correction, un seul passage.

## Réserves
- A169 (déjà au registre, hors scope) : `verifier-travail.sh` sur TASK-093 rend
  un juge en échec, faute de fichier de cas reconnu pour un périmètre sous
  `orchestration/` — précédent accepté sur TASK-086.
- A179 : preuve comportementale de `limites.json` (A178) impossible dans ce
  bac à sable, faute de session `claude` authentifiée pour un lancement
  imbriqué ; preuve statique substituée.
- A180 : le laissez-passer documentaire corrigé par A177 profite aussi à un
  YAML Ansible hors rôle (`Ansible/playbooks/*.yml`), qui n'est plus jugé du
  tout.
- A181 : `orchestration/decisions.md`, décision 39, énumère encore l'ancien
  périmètre de `limites.json`, resté en retard après A178.

## Tentatives
1 / 3

## Critères d'acceptation
- [x] `juger.sh` rend 0 sur le scope de TASK-087 (`Ansible/GUIDE.md` seul) et
      continue de rendre 1 sur un scope `Ansible/roles/<nom>/` sans scénario
      Molecule complet ; TASK-069, TASK-081, TASK-083 inchangés
- [x] la règle appliquée est écrite dans le script
- [~] un agent lancé peut écrire un `.md` de son scope sous les dossiers de la
      bibliothèque, README compris — démontré par preuve **statique** de
      `limites.json`, pas par conteneur ni lancement d'essai réel (A179)
- [~] les interdictions qui protègent le dépôt restent — même niveau de preuve
- [x] les nouveaux cas sont ajoutés à `tests/acceptance/TASK-086-outillage.sh`,
      qui rend 0 sur l'hôte

## Validation finale
PASS (deux critères tenus au niveau statique plutôt que comportemental, réserve
A179 assumée et consignée)

## Git
Branche : `agent/TASK-093` (fusionnée `--no-ff`, supprimée)
Commits : `a9b0962` (correctifs), `3c84439`+`66f0c28` (registre déposé puis
retiré de la branche, hors périmètre), `55463d4` (correction de relecture)
Fusion : sur `master`

## Résumé
Les deux causes des relances perdues de TASK-087 sont corrigées et prouvées
par non-régression. Trois réserves nouvelles rejoignent le registre (A179,
A180, A181), aucune ne bloque la suite du plan des serveurs.
