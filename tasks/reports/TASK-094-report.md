## Compte rendu

`orchestration/architecture.md` répond maintenant aux quatre questions que tu posais : d'où les agents sont lancés,
ce qui relève du modèle, du harnais, des scripts et des consignes, quels agents existent avec quel modèle et quels
droits, et quels outils sont génériques ou propres au projet. Quatre sections (11 à 14) ont été ajoutées, avec des
schémas Mermaid, sans toucher aux dix sections existantes.

**C'est la première tâche conduite entièrement sur ton API Anthropic**, et elle a montré la valeur de la relecture.
Haiku 4.5 a écrit un premier jet en 139 secondes pour 0,147 $. Le relecteur, lancé hors du harnais sur Opus 5, l'a
jugé **NON FUSIONNABLE** pour 0,602 $ : des chiffres de coût étaient inventés dans un fichier qui se déclare « de
référence », et les sept scripts étaient tous classés « génériques » sans justification. Aucun test automatique ne
l'aurait vu. Sonnet 5 a corrigé en 227 secondes pour 0,514 $, en s'appuyant sur `agents.tsv` : « non mesuré » là où
le fichier ne dit rien, et la moyenne DeepSeek (0,120 $ sur 82 lignes) recoupe le calcul indépendant fait par la session.

Coût total : **1,263 $** d'API. Les tours de la session qui a orchestré ne sont pas mesurés en dollars : ils sont sur
l'abonnement.

## Statut

Terminée, fusionnée sur `master`, non poussée.

## Objectif

Ajouter à `architecture.md` la vue d'exécution, les quatre couches, le registre des agents et l'inventaire des capacités.

## Travail réalisé

- §11 Vue d'exécution : trois cas (session, sous-agent dans le même processus, agent externe lancé par `lancer-agent.sh`),
  avec dossier de travail et API contactée, en schéma Mermaid.
- §12 Les quatre couches : modèle, harnais, scripts, consignes, et le contrat minimal d'un harnais.
- §13 Registre des agents : où chacun est défini, son modèle, ses droits, son coût lu dans `agents.tsv`.
- §14 Inventaire des capacités : les sept outils de `orchestration/outils/`, chacun classé générique, propre au projet
  ou mixte, avec sa justification (`lancer-agent.sh` est mixte : copie isolée et plafond de durée génériques).

## Fichiers modifiés

`orchestration/architecture.md` (+106 lignes, sections 1 à 10 intactes), `tasks/`, registre A185 à A187.

## Commandes exécutées

| Commande | Résultat |
|---|---|
| `lancer-agent.sh anthropic TASK-094 --modele haiku` | 0 — 18 tours, 11 192 jetons de sortie, 0,147 $ |
| relecteur : `claude -p --agent relecteur --model claude-opus-5 --tools Read,Grep,Glob` | 0 — 13 tours, 9 113 jetons de sortie, 0,602 $, NON FUSIONNABLE |
| `lancer-agent.sh anthropic TASK-094 <retours> --modele sonnet` | 0 — 32 tours, 20 690 jetons de sortie, 0,514 $ |
| `bash orchestration/outils/verifier-travail.sh TASK-094` (avant et après) | 0 — périmètre PASSE, validations 1/1 |
| contrôle ciblé des six points de la relecture | tous corrigés (recherches dans le fichier) |

## Validations

`verifier-liens.sh` : 0. Aucune seconde relecture, conformément à la règle du dépôt ; les défauts ont été recontrôlés un à un.

## Erreurs rencontrées

- Haiku : chiffres de coût fabriqués, classement « générique » non justifié, sous-agent confondu avec l'agent externe,
  URLs fausses, un mot espagnol. Tout a été relevé par la relecture et corrigé par Sonnet.
- Les agents n'ont pas pu lancer `verifier-liens.sh` ni `juger.sh` (hors de l'allow-list), d'où deux `VERDICT ECHEC`
  qui n'en étaient pas (A186).

## Réserves

- A185 : tableaux aux lignes très longues dans les sections 11 à 14.
- A186 : `verifier-liens.sh` et `juger.sh` non exécutables par un agent lancé.
- A187 : coût de la relecture par l'API saisi à la main ; TASK-099 l'automatisera.

## Git

Commits `92f1650` (correction), fusion `ee0f22c`. Branche `agent/TASK-094` supprimée, copie retirée.
