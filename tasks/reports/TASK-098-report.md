## Compte rendu

`anthropic.env` donne maintenant accès à trois modèles Claude avec une seule clé : Haiku 4.5, Sonnet 5 et
Opus 5. Le modèle se choisit au lancement, `lancer-agent.sh anthropic TASK-XXX --modele opus`, et sans option
c'est Haiku, le moins cher. Un alias inconnu, ou `--modele` sur un profil qui n'en porte pas (DeepSeek), s'arrête
en code 2. Le lancement de DeepSeek est inchangé, ce que le test démontre.

J'ai ajouté une option que la fiche n'avait pas prévue en tant que telle, `--dry-run` : elle affiche profil,
modèle, tarifs et présence de la clé, sans copie, sans agent et sans dépense. Elle sert à vérifier une
configuration pour zéro dollar.

Les tarifs ont été relevés à la source aujourd'hui, sur la page officielle : Haiku 1 / 0,10 / 5 $, Sonnet 2 / 0,20
/ 10 $, Opus 5 / 0,50 / 25 $ par million de jetons (entrée, lecture du cache, sortie). L'hypothèse « cache en lecture
= 0,1 x l'entrée » est confirmée. Un défaut existant est apparu : l'écriture de cache est facturée 1,25 x mais
comptée au tarif de lecture, donc le coût affiché d'un agent Anthropic est sous-estimé (A184).

**Conduite.** En direct par la session, sans conducteur. Relecture indépendante par Sonnet (abonnement, choix de
user) : FUSIONNABLE APRÈS CORRECTIONS, cinq mineurs, quatre corrigés, un versé au registre. Aucun agent n'a été lancé
sur l'API : les tests emploient de fausses clés.

## Statut

Terminée, fusionnée sur `master`, non poussée.

## Objectif

Un seul `anthropic.env`, une seule clé, plusieurs modèles ; `--modele` les choisit, `--dry-run` montre sans lancer.

## Travail réalisé

- `orchestration/modeles/anthropic.env` : `MODELE_DEFAUT=haiku`, puis `MODELE_<alias>` et `PRIX_<alias>` pour haiku,
  sonnet et opus ; alias de lettres, chiffres, `_` ou `-` ; `ENTREE`, `CACHE` et `SORTIE` réservés.
- `orchestration/outils/lancer-agent.sh` (149 lignes) : options `--modele` et `--dry-run`, lecture des alias, choix du
  modèle, bloc `DRY-RUN`. Les profils à un seul modèle (`MODELE=`, `PRIX_ENTREE=`…) se lisent comme avant.
- `tests/acceptance/TASK-098-modeles.sh` : profils réels en `--dry-run`, puis dépôt jouet avec faux `claude`.
- `orchestration/README.md` : les deux options.

## Fichiers modifiés

`orchestration/modeles/anthropic.env`, `orchestration/outils/lancer-agent.sh`, `orchestration/README.md`,
`tests/acceptance/TASK-098-modeles.sh` (nouveau, 100755), `tasks/`, registre A184.

## Commandes exécutées

| Commande | Code |
|---|---|
| `bash tests/acceptance/TASK-098-modeles.sh` (hôte) | 0 — 29 vérifications |
| `tests/env/run-in-container.sh -- bash tests/acceptance/TASK-098-modeles.sh` | 3 — 22 vérifications, 1 NON EXÉCUTÉ (git et node absents, A182) |
| `bash tests/acceptance/TASK-097-cle.sh` (non-régression) | 0 — 24 vérifications |
| `tests/env/run-in-container.sh -- tests/run.sh lint` | 0 — 129 fichiers, 0 erreur, 2 avertissements hérités |
| `bash orchestration/outils/verifier-liens.sh` | 0 |
| mutant 1 : `--modele` ignoré | 6 échecs détectés |
| mutant 2 : tarifs du défaut conservés | 2 échecs détectés |

## Validations

Les quatre commandes de la fiche sont vertes. Aucune vraie clé n'est lue par les tests ; aucun agent n'est lancé.

## Erreurs rencontrées

- Ma première ligne `--dry-run` affichait l'URL du profil à la place du mot « trouvée » (`${ADRESSE:-…}`), attrapée
  à l'essai manuel avant tout test.
- Deux avertissements SC2015 (`A && B || C`) sur `lancer-agent.sh` et le test, corrigés sans ajouter de ligne.
- Un `node -e` aux guillemets imbriqués a échoué au shell ; je suis passé aux outils d'édition.
- Écart à la fiche, consigné : en `--dry-run`, une clé absente donne le code 2 avec le message habituel, non une ligne
  « clé : absente » ; la fiche a été alignée sur ce comportement.

## Réserves

- A184 : coût Anthropic sous-estimé, l'écriture de cache étant comptée au tarif de lecture.
- A182 : le lancement jouet du test n'est prouvé qu'à l'hôte, `git` et `node` manquant au conteneur.

## Git

Commits `1a93cef` (travail), correctifs de relecture, fusion sur `master`. Branche `agent/TASK-098` supprimée.
