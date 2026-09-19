## Compte rendu

`lancer-agent.sh` peut maintenant lancer un agent sur l'API Anthropic depuis la session. Ta clé
`ANTHROPIC_API_KEY` est dans le registre utilisateur de Windows (108 caractères), mais le harnais
ne la retransmet pas à ses outils : il définit lui-même `ANTHROPIC_BASE_URL` et laisse la clé de côté.
Rien à ajouter au dépôt : aucun fichier de clés, aucun nouveau nom de variable.

Un petit script, `resoudre-cle.sh`, cherche la variable dans l'environnement, puis dans les variables
utilisateur de Windows par `powershell.exe`, et l'écrit sur la sortie standard. `lancer-agent.sh`
l'appelle à la place de la lecture directe. Si la clé est introuvable, il s'arrête en code 2 avec un
message qui nomme la variable et les deux endroits cherchés, sans jamais afficher de valeur. Le profil
`anthropic.env` (modèle Haiku 4.5) fonctionne donc comme `deepseek.env`.

**Conduite.** Faite en direct par la session, sans sous-agent conducteur, pour économiser les jetons.
Une relecture indépendante par Sonnet : FUSIONNABLE, quatre défauts mineurs, trois corrigés (assertion
creuse retirée, niveaux de preuve nommés, critère 4 précisé), le quatrième existait déjà avant la tâche.

**À savoir.** Le retour chariot que Windows ajoute ne se prouve qu'en conteneur Linux : Git Bash le retire
lui-même, l'hôte ne peut pas le voir. Un mutant qui le conserve est détecté en conteneur par cinq assertions.

## Statut

Terminée, fusionnée sur `master`, non poussée.

## Objectif

`lancer-agent.sh` trouve la clé d'un profil dans l'environnement, sinon dans les variables utilisateur
de Windows, sans fichier de clés ni nouveau nom de variable.

## Travail réalisé

- `orchestration/outils/resoudre-cle.sh` (17 lignes) : environnement, puis registre ; nom validé par
  `^[A-Z][A-Z0-9_]*$` avant tout appel à `powershell.exe` ; retour chariot retiré.
- `orchestration/outils/lancer-agent.sh` : appel de `resoudre-cle.sh` (lignes 45-46), variable `cle_api`.
- `tests/acceptance/TASK-097-cle.sh` : 24 vérifications à l'hôte, avec de fausses valeurs, un faux
  `powershell.exe` et un faux `claude`.

## Fichiers modifiés

`orchestration/outils/resoudre-cle.sh` (nouveau, 100755), `orchestration/outils/lancer-agent.sh`,
`tests/acceptance/TASK-097-cle.sh` (nouveau, 100755), `tasks/`, registre A182 et A183.

## Commandes exécutées

| Commande | Code |
|---|---|
| `bash tests/acceptance/TASK-097-cle.sh` (hôte) | 0 — 24 vérifications |
| `tests/env/run-in-container.sh -- bash tests/acceptance/TASK-097-cle.sh` | 3 — 20 vérifications, 1 NON EXÉCUTÉ (git et node absents, A182) |
| `tests/env/run-in-container.sh -- tests/run.sh lint` | 0 — 128 fichiers, 0 erreur, 2 avertissements hérités |
| `bash orchestration/outils/verifier-liens.sh` | 0 |
| mutant 1 : registre prioritaire sur l'environnement | 3 échecs détectés (hôte) |
| mutant 2 : retour chariot conservé (`tr` remplacé par `cat`), en conteneur | 5 échecs détectés |

## Validations

Les trois commandes de la fiche sont vertes. Les tests n'emploient aucune vraie clé et ne lancent aucun agent.

## Erreurs rencontrées

- Le cas jouet échouait en code 1 : le dépôt jouet n'avait pas de dossier `orchestration/mesures` ; défaut du
  montage du test, corrigé.
- Le mutant du retour chariot survivait à l'hôte : Git Bash retire le CR, le test n'y voit rien ; la preuve
  a été déplacée en conteneur et l'assertion reformulée sur les octets écrits.
- Deux avertissements SC2016 puis SC2015 sur le test, corrigés (faux binaires en heredoc, fonction `pas_appele`).
- Ma réécriture des faux binaires avait perdu la ligne `chmod +x`, invisible à l'hôte ; rattrapée avant la relecture.

## Réserves

- A182 : le cas jouet n'est prouvé qu'à l'hôte, `git` et `node` manquant au conteneur.
- A183 : portée utilisateur seulement, et retour chariot prouvé en conteneur seulement.

## Git

Commits `2e9ba6e` (travail), `ceb78d5` (retours de relecture), fusion `2bc605d`. Branche `agent/TASK-097` supprimée.
