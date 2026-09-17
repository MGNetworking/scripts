# TASK-077 — Rapport d'exécution

## Compte rendu

La décision 49 prévoit un `CADRAGE.md` par grand dossier : un document qui engage, script
par script, ce qui est réputé utilisé. Après `Kubernetes/` (validé), `Linux/` et `Docker/`
(en attente), voici le dernier, `Synology/` : deux scripts hérités dans `Plex/`, jamais
mis au standard, et `Administration/`, vide.

**Ce qui a été écrit.** `Synology/CADRAGE.md` suit le modèle de `Docker/CADRAGE.md` :
- le **besoin** (renommer les épisodes d'une saison, mettre Plex à jour sur le NAS) et ce
  qui est hors besoin ; `Administration/` décrit par son seul besoin, sans contrat ;
- des conventions de dossier : aucun des deux ne charge `lib/common.sh`, aucun privilège,
  aucune confirmation, aucune simulation, codes 0 et 1 seulement ; ce qui est **hors
  contrat** (libellés, lignes de journal, mise en page) ;
- **aucun ensemble**, deux **scripts individuels**, chacun avec son bloc et son contrat ;
- l'historique, avec une ligne « état initial » dont la colonne « Validé par user » est vide.

**Ce que le code a montré.** Ces scripts ne peuvent pas tourner en conteneur : tout est lu
dans le code. `organize-series.sh` renomme sans simulation ; un conflit de nom fige la
numérotation, une relance ne renomme rien, et le décompte d'erreurs mélange toutes les
exécutions du jour. `update-plex.sh` n'a aucune option : `--help` lance une vraie mise à
jour ; il nettoie les images sans étiquette de tout le NAS. Surtout, la « mise au
standard » prévue par la décision 18 changerait ces comportements, désormais contractuels.

**Relecture.** Opus a rendu « fusionnable après corrections » : un défaut majeur (les
effets de `docker compose up -d` étaient incomplets : il crée le conteneur s'il manque et
redémarre un Plex arrêté exprès) et sept mineurs (conteneur recréé donc supprimé, `.env`
de la pile lu, sens du code 0, ordre des contrôles, comparaison des chemins en texte,
portée du décompte d'erreurs). Tous corrigés dans le document ; les six défauts du code
qu'elle a ajoutés sont au registre.

**Coût.** Une relecture Opus, 31 786 jetons.

**Il te reste à valider le cadrage**, avec ceux de `Linux/` et `Docker/`. Au-delà du texte :
- aucun ensemble : les deux scripts sont individuels ;
- les constantes du code entrent au contrat : chemins de journal, `STACK_DIR`,
  `COMPOSE_FILE`, `SERVICE_NAME`, `IMAGE` ;
- aucune variable d'environnement propre ; l'environnement hérité (locale de `sort`,
  client `docker`) honoré ;
- codes de retour tels quels : usage refusé en 1, jamais 2 ;
- les écarts décrits tels quels, et le choix à faire sur la mise au standard (A145).

### Réserves

- Défauts d'`organize-series.sh` : extension, numérotation figée, relance, décomptes (A143).
- Défauts d'`update-plex.sh` : arguments ignorés, image tirée, `prune` global, délais (A144).
- Mise au standard (décision 18) contre contrat (décision 49), à trancher (A145).
- Documentation de `Synology/` inexacte face au code (A146).

## Statut

`completed`, cadrage en attente de validation par `user`.

## Fichiers

- `Synology/CADRAGE.md` (créé, 139 lignes)

## Validations

| Commande | Code |
|---|---|
| `bash orchestration/outils/verifier-liens.sh` (branche, avant et après corrections) | 0 |
| `git diff --name-only master...agent/TASK-077` | `Synology/CADRAGE.md` seul |
| contrôle par grep, dans le script de chaque contrat, des options et variables citées (`-*`, majuscules, `$0`) | aucun manquant (hors mots « NAS » et « GNU ») |
| `bash orchestration/outils/juger.sh tasks/active/TASK-077.md` | 1 : « aucun fichier de cas dans le périmètre » ; tâche documentaire, juge non applicable |
| `bash orchestration/outils/verifier-liens.sh` (master, après clôture) | 0 |

## Git

- `chore: TASK-077 en cours`
- `docs(synology): cadrage initial du dossier`
- `fix: retours de relecture (TASK-077)`
- `Merge branch 'agent/TASK-077'`, puis commit de clôture
