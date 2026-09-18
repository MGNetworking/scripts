# TASK-087 — Rapport d'exécution

## Compte rendu
User a demandé de documenter, à hauteur fonctionnelle, l'outil de préparation des
serveurs par Ansible : comprendre sans avoir jamais employé Ansible. L'agent DeepSeek a
écrit ce guide. En cours de tâche, `limites.json` — qui interdit à tout agent
d'écrire dans `README.md` ou `docs/` — a empêché le livrable prévu, `Ansible/README.md` :
le conducteur a déplacé la cible vers `Ansible/GUIDE.md`, remis à jour la fiche dans
`master` et dans la copie de l'agent, et ajouté lui-même, à la clôture, le renvoi vers
ce guide dans `README.md` (geste explicitement réservé au conducteur par le champ
`out_of_scope` de la fiche). `docs/plan-outil-preparation-serveurs.md`, qui citait
encore l'ancien livrable, a été corrigé de même.

Premier appel à DeepSeek en échec : les outils Artifact, proposés par défaut à tout
sous-agent, faisaient échouer l'appel à l'API DeepSeek — corrigé une fois pour toutes
dans `lancer-agent.sh` (`--disallowed-tools`). Le juge automatique (`juger.sh`) a ensuite
rendu ÉCHEC à deux reprises sur un travail par ailleurs conforme : un bug déjà présent,
qui route tout périmètre sous `Ansible/` vers le contrôle « scénario Molecule », même
quand ce périmètre ne vise ni rôle ni script — le cas de ce guide, purement documentaire.
Vérifié à la main : schéma poste → SSH → serveur présent, vocabulaire (rôle, playbook,
inventaire, idempotence, Molecule, coffre) expliqué à sa première apparition, section
secrets conforme au `.gitignore` réel, commandes du quotidien réelles et non inventées,
section finale « le jour où vous aurez un serveur » complète, 184 lignes.

La relecture Opus a trouvé un défaut majeur (une commande de vérification présentée
comme lancée depuis `Ansible/` alors qu'elle part de la racine du dépôt) et trois
mineurs (ordre des étapes Molecule inversé, terme « simulé » employé à contresens du
niveau de preuve qu'il désigne plus loin, sigle WSL non expliqué). Une relance corrige
les quatre. Coût cumulé de l'agent, essais ratés compris : 0,215 $, 149 tours,
81 391 jetons de sortie, 594 s sur 6 lancements.

Deux défauts d'outillage versés au registre, non corrigés ici : A177 (l'ordre des
branches de `juger.sh` masque la branche documentaire pour tout périmètre sous
`Ansible/` sans rôle), A178 (`limites.json` ferme toute écriture documentaire aux
agents sans distinguer un guide neuf d'un README technique protégé, ce qui a coûté un
aller-retour de fiche et un faux positif de périmètre dans `verifier-travail.sh`).

## Statut
COMPLETED

## Objectif
`Ansible/GUIDE.md` explique le fonctionnement de l'outil à quelqu'un qui n'a jamais
employé Ansible : le trajet du poste vers le serveur, ce qu'est un rôle, ce qu'est une
recette, où vivent les informations confidentielles, et ce qui se passe le jour où un
serveur existe.

## Travail réalisé
- `Ansible/GUIDE.md` (184 lignes) : trajet poste → SSH → serveur, quatre mots-clés
  (inventaire, rôle, playbook, idempotence), déroulé d'une recette, preuve sans
  serveur (conteneur, Molecule), secrets et `.gitignore`, commandes du quotidien,
  section « le jour où vous aurez un serveur », ce que l'outil ne fait pas.
- `Ansible/README.md` : renvoi vers `GUIDE.md` ajouté par le conducteur.
- `docs/plan-outil-preparation-serveurs.md` : entrée TASK-087 alignée sur le livrable
  réel.
- `tasks/pending/TASK-039.md` : A177 (bug de routage de `juger.sh`), A178 (`limites.json`
  ferme toute écriture documentaire aux agents).

## Fichiers modifiés
- `Ansible/GUIDE.md` (ajouté)
- `Ansible/README.md`
- `docs/plan-outil-preparation-serveurs.md`
- `tasks/pending/TASK-039.md`
- `orchestration/mesures/agents.tsv`

## Commandes exécutées
| Commande | Code | Durée |
|---|---|---|
| `bash orchestration/outils/verifier-liens.sh` (avant relance) | 0 | — |
| `bash orchestration/outils/verifier-travail.sh TASK-087` (avant relance) | 1 (JUGE et PERIMETRE, voir Réserves) | — |
| `bash orchestration/outils/verifier-travail.sh TASK-087` (après relance) | 1 (JUGE et PERIMETRE, voir Réserves) | — |
| `git diff --name-status master agent/TASK-087` (contrôle manuel du périmètre) | — | — |

## Validations
| Validation | Résultat |
|---|---|
| `verifier-liens.sh` | PASS (0, aucun lien mort) |
| `juger.sh` (via `verifier-travail.sh`) | ÉCHEC — bug de routage sur périmètre `Ansible/` documentaire, A177 ; sans rapport avec le contenu du guide |
| Périmètre (`verifier-travail.sh`, diff à trois points) | ÉCHEC signalé — `tasks/active/TASK-087.md` (contenu identique à `master`, resynchronisation de fiche), `Ansible/README.md` et `docs/plan-outil-preparation-serveurs.md` (gestes du conducteur, anticipés par `out_of_scope`) ; le diff à deux points entre les pointes de `master` et `agent/TASK-087` confirme que seul `Ansible/GUIDE.md` est un ajout de l'agent |
| Relecture Opus (une passe) | FUSIONNABLE APRÈS CORRECTIONS — 1 majeur, 3 mineurs, tous corrigés par la relance |
| Critères d'acceptation (vérifiés à la main) | tous tenus — voir ci-dessous |

## Erreurs rencontrées
- Appel à DeepSeek en échec (outils Artifact) — corrigé dans `lancer-agent.sh`.
- `limites.json` refuse `Edit(**/README.md)` et `Edit(docs/**)` aux agents — livrable
  déplacé vers `Ansible/GUIDE.md`.
- `juger.sh` ÉCHEC à deux reprises sur un périmètre documentaire sous `Ansible/`
  (A177).

## Corrections automatiques
Relance unique (retours D1 à D4 de la relecture) : commande de vérification recadrée
sur la racine du dépôt, ordre Molecule corrigé, « machines simulées » remplacé,
sigle WSL glosé. Tout dans `Ansible/GUIDE.md`, seul fichier du périmètre de l'agent.

## Réserves
- A177 : `juger.sh` route tout périmètre sous `Ansible/` sans rôle vers le contrôle
  Molecule, y compris documentaire — branche à réordonner.
- A178 : `limites.json` ferme toute écriture documentaire (`README.md`, `docs/**`) aux
  agents, sans distinction — a coûté un déplacement de livrable et un faux positif de
  périmètre.

## Tentatives
1 / 3 (relance de relecture comprise)

## Critères d'acceptation
- [x] schéma texte du trajet poste → SSH → serveur, absence d'agent et de dépôt sur le serveur
- [x] aucun terme technique non expliqué à sa première apparition
- [x] secrets conformes au `.gitignore` réel
- [x] commandes du quotidien réelles, non inventées
- [x] section « le jour où vous aurez un serveur »
- [x] 200 lignes au plus (184)

## Validation finale
PASS (validations réelles ; JUGE et PERIMETRE automatiques en défaut pour des raisons
d'outillage identifiées et versées au registre, A177 et A178 ; contenu vérifié à la
main contre chaque critère)

## Git
Branche : `agent/TASK-087` (fusionnée, supprimée)
Commits : `de3cf50` (premier jet), `017146c` (retours de relecture), `6b68b5b` (fusion)

## Résumé
Guide fonctionnel d'Ansible livré et fusionné. Deux défauts d'outillage découverts et
versés au registre (A177, A178) plutôt que corrigés dans cette tâche, hors périmètre.
