# TASK-075 — Rapport d'exécution

## Compte rendu

La décision 49 prévoit un `CADRAGE.md` par grand dossier : un document qui engage, script
par script, ce qui est réputé utilisé sur les serveurs. Après `Kubernetes/`, validé par
toi, voici `Linux/`, le plus gros dossier : 25 scripts répartis entre `System/` (13),
`Security/` (7) et `K3s/` (5).

**Ce qui a été écrit.** `Linux/CADRAGE.md` suit le modèle validé pour `Kubernetes/` :
- le **besoin** du dossier (préparer, sécuriser et exploiter un VPS Debian ou Ubuntu, puis
  y porter K3s) et ce qui est hors besoin ;
- des conventions valables pour tout le dossier, dont la liste de ce qui est **hors
  contrat** (`RACINE_TEST`, libellés, mise en page, commentaires des fichiers déposés) ;
- **trois ensembles**, un par sous-dossier : « Socle du serveur », « Sécurité du
  serveur », « Gestion de K3s », chacun avec sa fonction globale, son ordre et ses
  conventions ; aucun script individuel ;
- **25 contrats**, lus dans le code et non dans les README ;
- l'historique, avec une ligne « état initial » dont la colonne « Validé par user » est vide.

**Ce que le code a montré.** Les trois sous-dossiers n'ont pas été écrits à la même
époque et ne suivent pas les mêmes règles. Dans `System/`, un `ASSUME_YES` hérité
confirme, et une confirmation refusée rend 0. Dans `Security/` et `K3s/`, seul `--yes`
confirme, il est obligatoire hors terminal, et un refus rend 1. Le cadrage décrit ces
différences telles quelles, ensemble par ensemble. Sept écarts entre le code et ce qu'on
en attend sont inscrits au registre (A131 à A137), sans rien corriger.

**Relecture.** Opus a relu les 25 contrats contre le code et rendu « fusionnable après
corrections », sans défaut bloquant. Deux défauts majeurs, corrigés :
- la règle « les diagnostics ne rendent jamais 1 » était fausse pour
  `check-services.sh --service` ;
- la fonction promise par l'ensemble Sécurité allait au-delà du code :
  `configure-ssh.sh` ne relit pas la valeur réellement appliquée, et ufw garde les
  règles `allow` antérieures.

Dix remarques mineures ont été corrigées dans le document :
- une confirmation se lit sur l'entrée standard, même sans terminal ;
- un `LOG_DIR` non absolu ;
- `/etc/cron.d` n'est pas exigé sous `--dry-run` ;
- les répertoires `jail.d` et `K3S_CONFIG_DIR` sont créés s'ils manquent ;
- les variables héritées que K3s laisse passer à son installateur ;
- ce que fait `--sudo` ;
- fail2ban redémarré sans restauration ;
- l'horaire hebdomadaire n'est qu'un défaut.

Les défauts du code qu'elle a relevés sont allés au registre (A135 à A137).

**Coût.** Une relecture Opus, 224 480 jetons.

**Il te reste à valider le cadrage**, avec ceux de `Docker/` et `Synology/`. Au-delà du
texte, tu valides les choix suivants :
- les trois ensembles calqués sur les sous-dossiers, et aucun script individuel ;
  `notify-failure.sh` est rangé dans « Socle du serveur », alors qu'aucun script ne
  l'appelle ;
- l'ordre proposé pour `System/` : journaux, nom d'hôte, fuseau, swap, paquets, compte,
  puis cron. Aucun README ne le fixait ;
- les variables d'environnement lues sans condition entrent au contrat, comme
  `TIMEOUT_HELM` pour Kubernetes : `K3S_CONFIG_DIR`, `FICHIER_SHADOW`,
  `FICHIER_SHELLS`, `SSHD_CONFIG`, `SSHD_CONFIG_D`, `FAIL2BAN_JAIL_D`,
  `FAIL2BAN_ESSAIS`, `FAIL2BAN_DELAI`, `BORNE`, `LOG_DIR`, `NOTIFY_URL`,
  `NOTIFY_FORMAT`, `NOTIFY_JETON`, `NOTIFY_DELAI` ;
- sont **hors contrat** : `RACINE_TEST` (en conteneur seulement), le libellé des messages,
  la mise en page, les commentaires des fichiers déposés (`/etc/cron.d/mgnetworking`,
  règle logrotate, fichiers `sshd_config.d` et `jail.d`) ;
- les écarts que le cadrage décrit au lieu de les corriger : A132 (échecs sortis avec le
  code de la commande), A133 (swap recréé pour une ligne fstab), A134 (`ASSUME_YES`
  hérité honoré par `configure-swap.sh`), A135 et A136.

### Réserves

- Aides inexactes face au code dans six scripts (A131).
- Échecs non interceptés sortant avec le code de la commande au lieu de 1 (A132).
- `configure-swap.sh` recrée un swap actif à la bonne taille absent de fstab (A133).
- Confirmation héritée dans `Linux/System/`, question de la décision 45 pour
  `configure-swap.sh` (A134).
- Simulation apt avalée, taille de swap mal lue, appartenance à un groupe par mot entier (A135).
- Variables héritées transmises à l'installateur K3s (A136).
- `configure-ssh.sh` ne relit pas la valeur effective (A137).

## Statut

`completed`, cadrage en attente de validation par `user`.

## Fichiers

- `Linux/CADRAGE.md` (créé, 655 lignes)

## Validations

| Commande | Code |
|---|---|
| `bash orchestration/outils/verifier-liens.sh` (copie, avant et après corrections) | 0 |
| `git diff --name-only master...agent/TASK-075` | `Linux/CADRAGE.md` seul |
| contrôle par grep, dans le script concerné, des 180 options et variables citées dans les contrats, et des variables des conventions communes dans `Linux/` | aucun manquant |
| `bash orchestration/outils/juger.sh tasks/active/TASK-075.md` | 1 : « aucun fichier de cas dans le périmètre » ; tâche documentaire sans script, juge non applicable |
| `bash orchestration/outils/verifier-liens.sh` (master, après clôture) | 0 |

## Git

- `chore: TASK-075 en cours` (renommage seul : le passage à `in_progress` n'a pas été
  indexé, la fiche est passée directement à `completed` à la clôture)
- `docs(linux): cadrage initial du dossier`
- `fix: retours de relecture (TASK-075)`
- `Merge branch 'agent/TASK-075'`, puis commit de clôture
