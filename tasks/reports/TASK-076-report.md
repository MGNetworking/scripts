# TASK-076 — Rapport d'exécution

## Compte rendu

La décision 49 prévoit un `CADRAGE.md` par grand dossier : un document qui engage, script
par script, ce qui est réputé utilisé sur les serveurs. Après `Kubernetes/`, validé par
toi, et `Linux/`, en attente, voici `Docker/` : 9 scripts répartis entre `Installation/`
(1), `Configuration/` (2), `Maintenance/` (2), `Cleanup/` (1) et `Diagnostics/` (3).

**Ce qui a été écrit.** `Docker/CADRAGE.md` suit le modèle de `Linux/CADRAGE.md` :
- le **besoin** du dossier (poser, régler, tenir à jour, nettoyer et diagnostiquer le
  moteur Docker d'un VPS Debian ou Ubuntu) et ce qui est hors besoin (le système, K3s et
  Kubernetes, les applications, le groupe `docker`, Swarm) ;
- des conventions valables pour tout le dossier, dont ce qui est **hors contrat** (libellés,
  mise en page, indentation de `daemon.json` quand `jq` est présent) ;
- **un seul ensemble**, « Moteur Docker », qui regroupe les cinq sous-dossiers, avec
  `Diagnostics/` déclaré en lecture seule ; aucun script individuel ;
- **9 contrats**, lus dans le code et non dans le README ;
- l'historique, avec une ligne « état initial » dont la colonne « Validé par user » est vide.

**Ce que le code a montré.** Les scripts ne confirment pas tous de la même façon. Trois
(`install-docker.sh`, `configure-docker.sh`, `update-docker.sh`) exigent `--yes` hors
terminal, mais acceptent en terminal un `ASSUME_YES` hérité, alors que deux d'entre eux
redémarrent le démon. `update-images.sh` et `docker-cleanup.sh`, lancés sans `--yes` par
une tâche planifiée, ne font rien et rendent 0. Le cadrage décrit ces différences telles
quelles. Cinq écarts sont inscrits au registre (A138 à A142), sans rien corriger.

**Relecture.** Opus a relu les 9 contrats contre le code et rendu « fusionnable après
corrections », sans défaut bloquant ni majeur. Cinq remarques mineures, corrigées dans le
document :
- `df` en échec sur `/var` arrête `install-docker.sh` au lieu d'un simple `[WARN]` ;
- `check-docker.sh` ne borne pas ses appels à `systemctl` ;
- les bornes de temps des autres diagnostics dépendent de la présence de `timeout` ;
- `update-images.sh` borne aussi la lecture des images ;
- dans `docker-cleanup.sh`, les deux `prune` peuvent emporter plus que le relevé, et un
  relevé final en échec rend 1 après les suppressions.

Les défauts du code qu'elle a relevés sont allés au registre (A140 à A142).

**Coût.** Une relecture Opus, 82 250 jetons.

**Il te reste à valider le cadrage**, avec ceux de `Linux/` et `Synology/`. Au-delà du
texte, tu valides :
- un seul ensemble pour tout le dossier, `update-images.sh` et `docker-cleanup.sh` compris,
  alors qu'ils touchent aux images et aux ressources des applications ;
- l'ordre : diagnostics à tout moment, installation, configuration, réseau, puis
  maintenance et nettoyage à la demande ;
- les variables lues sans condition au contrat : `DOCKER_SOCKET`, et `DOCKER_HOST`, que le
  client honore dans tous les scripts ;
- une valeur fautive de `config/server.env` refusée en 2, comme sur la ligne de commande ;
- les écarts décrits tels quels : A138, A139, A141 et A142.

### Réserves

- Échecs non interceptés sortant avec le code de la commande (A138).
- Trois régimes de confirmation, abandon silencieux en 0 hors terminal (A139).
- Aides et README inexacts face au code (A140).
- Bornes de temps inégales, `timeout` appelé sans contrôle dans `check-docker.sh` (A141).
- `docker-cleanup.sh` peut supprimer plus que le relevé confirmé, non vérifié en conteneur (A142).

## Statut

`completed`, cadrage en attente de validation par `user`.

## Fichiers

- `Docker/CADRAGE.md` (créé, 342 lignes)

## Validations

| Commande | Code |
|---|---|
| `bash orchestration/outils/verifier-liens.sh` (copie, avant et après corrections) | 0 |
| `git diff --name-only master...agent/TASK-076` | `Docker/CADRAGE.md` seul |
| contrôle par grep, dans le script de chaque contrat, des options et variables citées (`--*`, `SRV_*`, `DOCKER_*`), et des variables des conventions dans `Docker/` | aucun manquant |
| `bash orchestration/outils/juger.sh tasks/active/TASK-076.md` | 1 : « aucun fichier de cas dans le périmètre » ; tâche documentaire sans script, juge non applicable |
| `bash orchestration/outils/verifier-liens.sh` (master, après clôture) | 0 |

## Git

- `chore: TASK-076 en cours` (déplacement et passage à `in_progress` dans le même commit)
- `docs(docker): cadrage initial du dossier`
- `fix: retours de relecture (TASK-076)`
- `Merge branch 'agent/TASK-076'`, puis commit de clôture
