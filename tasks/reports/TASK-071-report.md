# TASK-071 — Rapport d'exécution

## Compte rendu
TASK-071 (`configure-registry.sh`) est terminée et fusionnée. C'est le cinquième script de `Kubernetes/Configuration/`. Pour tirer une image d'un registry privé, un Pod a besoin d'un Secret qui porte l'adresse du registry, un compte et un jeton. La décision 48 demande de poser ce Secret dans chaque namespace de `SRV_K8S_NAMESPACES`, à partir de `config/registry.env` : un fichier ignoré par Git, en droits 0600. Les identifiants ne doivent jamais être affichés, journalisés ni passés en argument. Le script **manipule un secret et écrit dans le cluster**.

À l'activation, le conducteur a complété la fiche :
- les faits Kubernetes vérifiés par la session : la documentation déconseille `kubectl create secret docker-registry --docker-password`, qui laisse le mot de passe dans l'historique et le montre aux autres utilisateurs ; elle donne aussi le type `kubernetes.io/dockerconfigjson` et la forme du JSON ;
- les exigences qui en découlent : JSON et base64 construits localement, manifeste passé à `kubectl apply -f -` par l'entrée standard, empreinte en annotation pour ne jamais relire le Secret ;
- les défauts connus du domaine.

L'agent DeepSeek a livré 220 lignes de script et 412 lignes de cas. Le conducteur a sondé le script en conteneur avec son propre faux `kubectl`. Ce faux relève ses arguments, la table des processus et l'environnement de tous les processus pendant chaque appel, et cherche le contenu du Secret sur le disque. Aucune fuite dans les cas ordinaires. Mais avec une trace bash héritée (`SHELLOPTS=xtrace`), le jeton sortait 12 fois à l'écran.

Opus a demandé des corrections. Entre-temps, la session a trouvé deux conteneurs de l'agent bloqués depuis plus de 30 minutes. Le premier jet du fichier de cas écrivait son faux `timeout` à travers un lien symbolique : il remplaçait ainsi le vrai `/usr/bin/timeout` du conteneur, et le faux s'appelait ensuite lui-même sans fin. C'est sans doute pourquoi le premier lancement a duré 2 269 s, et le relevé de ses jetons est manifestement faux (A122).

La relance unique a tout corrigé :
- `set +xv +o allexport` dès la 2e ligne du script ;
- un faux `timeout` en fichier ordinaire ;
- des validations plus strictes (serveur, namespaces de 63 caractères au plus) ;
- l'annotation entre guillemets ;
- deux cas de trace héritée, et une copie mutée sans la ligne de protection.

Sans seconde relecture, le conducteur a rejoué la suite trois fois, toutes réussies. Il a rejoué sa sonde, y compris sous `bash -xv` et `SHELLOPTS=xtrace:verbose:allexport` : aucune fuite. La copie mutée fait bien échouer la suite. Un petit défaut reste : l'adresse `a..b` est acceptée (A120).

Réserves :
- la version corrigée n'a pas été relue, et le script n'a jamais touché un vrai cluster ; `a..b` est accepté (A120) ;
- script et fichier de cas dépassent les ~150 lignes (A121) ;
- relevé de jetons du premier lancement faux, piège du faux binaire écrit à travers un lien (A122, fiche TASK-072) ;
- les commits de l'agent n'ont pas la ligne `Tâche :` (A66).

Coût agent : 0,199 $ en deux lancements (le premier relevé est faux) ; relecture : 53 140 jetons.

## Statut
COMPLETED

## Travail réalisé
- `Kubernetes/Configuration/configure-registry.sh` — 228 lignes
- `tests/integration/configure-registry.test.sh` — 466 lignes, 188 vérifications. Faux `kubectl` à état : il relève argv, `ps -eo args` et l'environnement des processus parents, garde et décode le manifeste reçu sur STDIN. Faux `timeout` en 124. Pseudo-terminal, idempotence par deux exécutions, traces héritées, section Mutations (témoin et 4 mutants).
- `config/registry.env.example` — 47 lignes, trois variables commentées, sans valeur réelle
- par le conducteur : fiche (faits Kubernetes, exigences), `Kubernetes/Configuration/README.md` (prérequis, ligne du script, utilisation, `imagePullSecrets`, interdiction de `--docker-password`, risques), `Kubernetes/README.md`, README racine (`Configuration` : 5 scripts), backlog, journal, registre (A120, A121, A122, occurrence A66), fiche TASK-072

## Déroulé
| Étape | Qui | Résultat |
|---|---|---|
| activation | conducteur | 27d305b |
| lancement 1 | agent `deepseek` | 1 passage, 2 269 s, relevé faux (1 tour, 243 jetons), 0,001 $ ; 220 + 412 lignes ; commits 6ad93f8, 4944c05 |
| vérification | conducteur | juge 0 (156) ; périmètre : 3 fichiers du scope ; lignes d'assertion 142 → 142 ; sonde : 9 cas sans fuite, fuite du jeton sous `SHELLOPTS=xtrace` |
| relecture | Opus, 10 appels, 53 140 jetons, 107 s | FUSIONNABLE APRÈS CORRECTIONS — 1 majeur, mineurs ; bloquant ajouté par la session (conteneurs bloqués) |
| relance | agent `deepseek` | 1 passage, 97 tours, 1 025 s, 0,198 $ ; 228 + 466 lignes ; commit c13d3b8, chaque modification de test justifiée ; suite 5 fois 0 (29,9 à 31,7 s) |
| vérification | conducteur | périmètre : 3 fichiers ; lignes d'assertion 142 → 158, une assertion remplacée par une par forme d'adresse ; suite 3 fois 0 ; sonde rejouée ; mutant détecté |
| fusion | conducteur | 31b6a07 |

## Validations (relancées par le conducteur)
| Commande | Code |
|---|---|
| `bash orchestration/outils/juger.sh tasks/active/TASK-071.md` (4944c05) | 0 — shellcheck 0, fichier de cas 0 (156), règles du dépôt 3 |
| `tests/env/run-in-container.sh -- tests/run.sh lint` (4944c05) | 0 (118 fichiers, 0 erreur) |
| `tests/env/run-in-container.sh -- tests/run.sh integration` (4944c05) | 0 |
| `tests/env/run-in-container.sh -- bash Kubernetes/Configuration/configure-registry.sh --help` (4944c05) | 0 |
| `tests/env/run-in-container.sh -- bash tests/integration/configure-registry.test.sh`, 3 fois (c13d3b8) | 0, 0, 0 — 34, 31, 31 s — 188 vérifications, 0 échec |

Lint, intégration complète et juge sur c13d3b8 : lancés par l'agent (juge PASSE, 188 ; intégration 0), non relancés par le conducteur.

## Sonde du conducteur (conteneur `debian`, utilisateur non root, faux `kubectl` indépendant, version finale)
- nominal : 0 ; JSON décodé du base64 reçu identique au JSON attendu ; annotation = sha256 du JSON ; `apiVersion`, `kind`, `type` présents ;
- 2e exécution : 0, aucun apply ; `--dry-run` après changement de jeton : 0, aucun apply, « à mettre à jour (2) », ni base64 ni `auths` affichés ;
- `registry.env` en 0644 : 1 ; propriétaire root pour un script lancé sous uid 1000 : 1 ; aucun appel kubectl dans les deux cas ;
- identifiant `a"b\c`, jeton `d\\"e` : JSON correctement échappé ; retour ligne, tabulation : 2 ; serveur `https://…` ou avec guillemet : 2 ; `r.ex:` : 2 ; `a..b` : 0 (A120) ;
- namespace absent : 1, nommé, aucun apply ; apply refusé dont le stderr recopie le manifeste : 1, cause résumée, manifeste non recopié, bilan sans `[SUCCESS]` ;
- aucune sentinelle (identifiant, jeton, base64 de `auth`) dans : sorties, argv, `ps`, cmdline et environ de `/proc`, fichiers du disque pendant l'apply, journal (0600), fichiers créés pendant la sonde ; TMPDIR vide après exécution ;
- `SHELLOPTS=xtrace:verbose:allexport`, `bash -xv`, `bash -x --dry-run` : 0, aucune sentinelle dans la sortie, le journal, `/proc` ni `ps` ;
- `/usr/bin/timeout` du conteneur intact (ELF).

Mutation dans une copie jetable : `set +xv +o allexport` retiré → suite en code 1, 8 ÉCHEC (trace, environnement, sorties).

## Réserves
- version corrigée non relue par Opus ; jamais lancée contre un vrai cluster ; `REGISTRY_SERVEUR="a..b"` accepté (A120)
- script à 228 lignes et fichier de cas à 466, au-delà des ~150 (A121)
- relevé `agents.tsv` du premier lancement faux ; piège du faux binaire écrit à travers un lien symbolique (A122, TASK-072)
- commits 6ad93f8, 4944c05, c13d3b8 sans ligne `Tâche : TASK-071`, attribution `Claude Code` (A66)

## Git
Branche `agent/TASK-071` fusionnée `--no-ff` (31b6a07), copie `../script-agents/TASK-071` retirée, branche supprimée. Pas de push.
