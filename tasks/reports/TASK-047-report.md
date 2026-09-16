# TASK-047 — Rapport d'exécution

## Compte rendu
TASK-047 (`disable-root-login.sh`) est terminée et fusionnée. Ce script interdit la connexion SSH directe de root (décision 19). Il dépose un petit fichier, `/etc/ssh/sshd_config.d/05-mgnetworking-root.conf`, qui contient `PermitRootLogin no`. Le préfixe `05` le fait lire avant les autres, et sshd retient la première valeur qu'il rencontre. Comme `configure-ssh.sh`, ce script **peut couper l'accès à la machine**. Il reprend donc les mêmes verrous. Il refuse d'agir sans un compte non-root, membre de sudo, avec une clé (décision 20), ou si `sshd_config` n'inclut pas `sshd_config.d`. `sshd -t` doit valider la configuration. Nouveauté par rapport à `configure-ssh.sh` : `sshd -T` doit ensuite annoncer `permitrootlogin no`. Si l'une de ces étapes échoue, ou si le rechargement échoue, l'état antérieur est restauré.

C'est la première tâche conduite par un sous-agent `conducteur-tache` (TASK-049, en validation réelle). L'agent DeepSeek l'a écrite en un seul lancement et un seul passage (45 tours, 289 s, 0,116 $). Il a rendu 150 lignes de script et 140 lignes de cas, soit 92 vérifications. J'ai relancé moi-même le juge, le lint et l'intégration dans le conteneur Debian : tous rendent 0.

La relecture Opus a jugé le travail fusionnable dès le premier jet. Les cinq critères de la fiche sont tenus. Aucun défaut déjà corrigé dans `configure-ssh.sh` ne revient, et aucun test du retour arrière n'est creux. Elle a relevé cinq points mineurs, laissés de côté et consignés au registre. Le plus sérieux (A51) : le script dit « déjà conforme » en ne regardant que son propre fichier. Un `PermitRootLogin yes` ajouté plus tard en tête de `sshd_config` échapperait donc à la relance.

Réserves : conformité jugée au seul fichier déposé (A51) ; blocs `Match` non contrôlés (A52) ; un cas de test incomplet (A53) ; deux messages trop longs (A54) ; ordre de priorité jamais éprouvé avec le vrai sshd (A55, qui rejoint A48).

## Statut
COMPLETED

## Travail réalisé
- `Linux/Security/disable-root-login.sh` — 150 lignes
- `tests/integration/disable-root-login.test.sh` — 140 lignes, 40 lignes de vérification, faux `sshd` et `systemctl`
- par l'orchestrateur : `Linux/Security/README.md`, `Linux/README.md`, README racine, backlog, journal, registre (A51 à A55)

## Déroulé
| Étape | Qui | Résultat |
|---|---|---|
| lancement 1 | agent `deepseek` | 1 passage, 45 tours, 289 s, 0,116 $ ; 150 + 140 lignes, 92 vérifications |
| vérification | conducteur | juge 0, périmètre conforme, aucun commit après le premier jet |
| relecture | Opus, 4 appels, 29 930 jetons, 52 s | FUSIONNABLE — 5 mineurs laissés (A51-A55) |

## Validations (relancées par le conducteur dans la copie de l'agent)
| Commande | Code |
|---|---|
| `bash orchestration/outils/juger.sh tasks/active/TASK-047.md` | 0 — PASSE, 92 réussies, 0 échec, 0 NON EXÉCUTÉ |
| `tests/env/run-in-container.sh -- tests/run.sh lint` | 0 — 0 erreur ; 2 avertissements sur des scripts `Synology/Plex` hérités |
| `tests/env/run-in-container.sh -- tests/run.sh integration` | 0 |
| `tests/env/run-in-container.sh -- bash Linux/Security/disable-root-login.sh --help` | 0 |

Périmètre : `git diff --name-only master...agent/TASK-047` ne contient que les deux fichiers du `scope`.

## Réserves
- A51 — conformité jugée au seul contenu du fichier déposé : une directive ajoutée avant l'`Include` passe inaperçue à la relance.
- A52 — `sshd -T` sans `-C` : un bloc `Match` qui rétablit root passe inaperçu.
- A53 — cas `ASSUME_YES` hérité avec terminal : l'absence de dépôt après « n » n'est pas vérifiée.
- A54 — messages trop longs (l. 72 et 141).
- A55 — faux `sshd -T` à valeur imposée : l'ordre de priorité n'est jamais éprouvé ; le cas sans terminal ne prouve pas la décision 45.

## Git
Activation 116ec89 et edc215d (deux commits : le statut manquait au premier). Commit agent c3b26ba, branche `agent/TASK-047` fusionnée (7167302) puis supprimée, copie retirée. Le commit c3b26ba ne porte pas la ligne `Tâche : TASK-047` (message généré par l'agent).
