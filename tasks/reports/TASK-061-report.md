# TASK-061 — Rapport d'exécution

## Compte rendu
TASK-061 (`cleanup-resources.sh`) est terminée et fusionnée. C'est le septième et dernier script du lot `Kubernetes/Maintenance/`, et le seul qui **supprime** quelque chose sur le cluster. La décision 48 le borne : aucun root, et seuls les objets nommés un à un en argument sont supprimés. Le script ne cherche jamais de candidats, et ne supprime jamais par label, par `--all` ni un namespace entier. Le danger à surveiller était donc un seul : qu'une suppression parte au-delà des objets nommés.

L'agent DeepSeek a livré 149 lignes de script et 150 lignes de cas en un passage. Le juge et les trois validations de la fiche rendaient 0, et le périmètre était respecté.

Avant la relecture, le conducteur a lancé en conteneur 41 sondes de contournement, avec un faux `kubectl` qui note chaque appel mot pour mot. Les options glissées dans un nom ou un namespace, les sélecteurs, les types sans nom et les namespaces système étaient bien refusés. Mais le script écartait les types dangereux par une **liste noire** comparée à la forme exacte, et plusieurs cibles atteignaient `kubectl delete` :
- `pod,secret/x` : kubectl accepte une liste de types, le Secret partait avec le pod ;
- `Secret/x` et `secrets.v1/x` : autres écritures du même type ;
- `all/x` : la catégorie `all` désigne plusieurs types à la fois ;
- `no/n1` et `crds/x` : noms courts absents de la liste ;
- `ns/production` : kubectl ignore `-n` pour un type à portée cluster, et ce namespace aurait été supprimé **entier**.

La relecture Opus a confirmé le bloquant et ajouté `ns/kube-system`, qui aurait emporté le namespace système. Elle a aussi relevé :
- un majeur : `delete` attendait la disparition de l'objet, et un finalizer pouvait bloquer l'appel jusqu'au délai ;
- des mineurs : le message d'un échec partiel, et un type inconnu présenté comme un apiserver injoignable ;
- des tests creux : un faux kubectl qui lisait ses arguments par position, « aucun appel » vérifié sur le seul dernier lancement, et des `grep` sur le source au lieu de preuves de comportement.

La session a tranché pour une **liste blanche** de dix types, avec leurs noms courts : pods, jobs, cronjobs, deployments, replicasets, statefulsets, daemonsets, services, configmaps, ingresses. Chaque type est comparé exactement, puis transmis à kubectl sous sa forme plurielle officielle. Le nom et le namespace sont validés en forme DNS-1123. Les Secrets sont exclus volontairement, et les PVC aussi : sur K3s, `local-path` est en `reclaimPolicy: Delete`, et supprimer un PVC détruit ses données.

La relance unique a tout corrigé :
- liste blanche en place ;
- `--wait=false` sur `delete`, la relecture finale restant seule juge ;
- un échec n'arrête plus les cibles suivantes ;
- bilan en trois groupes : supprimées, en échec, non tentées ;
- diagnostics distingués ;
- faux kubectl qui analyse tout l'argv ;
- exécution vérifiée en `nobody`, et faux `docker` et `k3s` restés muets.

Aucune vérification n'a été retirée, et le nombre de cas passe de 69 à 146. Chaque changement de test est justifié dans le commit.

Il n'y a pas eu de seconde relecture, conformément à la règle. Le conducteur a relu le code et rejoué ses sondes sur la version finale, avec les nouveaux cas : 51 au total. **Aucune cible hors liste blanche n'appelle `kubectl`**, ni `get` ni `delete`.

Réserves : la version corrigée n'a pas été relue par Opus, et rien n'a été constaté sur un vrai cluster. Restent aussi un point de test, `DELAI_TEST`, et deux diagnostics perfectibles (A96). Le script fait 198 lignes et le fichier de cas 256 (A97).

Coût agent : 0,247 $ en deux lancements ; relecture : 27 753 jetons.

## Statut
COMPLETED

## Travail réalisé
- `Kubernetes/Maintenance/cleanup-resources.sh` — 198 lignes
- `tests/integration/cleanup-resources.test.sh` — 256 lignes, 146 vérifications. Il utilise un faux `kubectl` en tête de PATH, qui analyse verbe, `-n`, type et nom. Toute option inconnue ou tout argv mal ordonné y laisse « FAUX » au journal. Il rend NotFound, Forbidden, le refus de connexion et « doesn't have a resource type » dans les formats réels, sur stderr. Des faux `docker` et `k3s` journalisent leurs appels.
- par le conducteur : `Kubernetes/Maintenance/README.md` (ligne, exemples, risques, exclusion des Secrets et des PVC), `Kubernetes/README.md`, le README racine (7 scripts), le backlog, le journal et le registre (A96, A97)

## Déroulé
| Étape | Qui | Résultat |
|---|---|---|
| activation | conducteur | commit fd61c01 (fiche, statut, backlog) |
| lancement 1 | agent `deepseek` | 1 passage, 58 tours, 303 s, 0,113 $ ; 149 + 150 lignes ; commit efb542b |
| vérification | conducteur | juge 0 (69 vérifications) ; périmètre : 2 fichiers du scope ; 41 sondes, dont 7 contournements de type atteignant `delete` |
| relecture | Opus, 6 appels, 27 753 jetons, 57 s | FUSIONNABLE APRÈS CORRECTIONS — 1 bloquant, 1 majeur, mineurs, tests creux |
| relance | agent `deepseek` | 2 passages, 42 tours, 424 s, 0,134 $ ; 198 + 256 lignes ; commit 33f77de, chaque changement de test justifié |
| vérification | conducteur | périmètre : 2 fichiers ; lignes d'assertion 63 → 87, les lignes retirées sont réécrites avec les helpers `refus` / `refus_motif` ou sous la forme canonique des types ; code relu : liste blanche en `case` exact, seul le type canonique transmis ; 51 sondes rejouées : tenues |

## Validations (relancées par le conducteur dans la copie de l'agent, version finale)
| Commande | Code |
|---|---|
| `bash orchestration/outils/juger.sh tasks/active/TASK-061.md` | 0 — shellcheck 0, fichier de cas 0 (146 réussies, 0 échec), règles du dépôt 3 (NON EXÉCUTÉ d'environnement) ; LONGUEUR signalée 198 et 256 |
| `tests/env/run-in-container.sh -- tests/run.sh lint` | 0 |
| `tests/env/run-in-container.sh -- tests/run.sh integration` | 0 — cleanup-resources.sh 146 réussies, 0 échec, 0 NON EXÉCUTÉ |
| `tests/env/run-in-container.sh -- bash Kubernetes/Maintenance/cleanup-resources.sh --help` | 0 |
| `bash tests/integration/cleanup-resources.test.sh` sur l'hôte (premier jet) | 3 — NON EXÉCUTÉ, garde `/.dockerenv` avant `mktemp` et `trap` |

## Sondes du conducteur (conteneur `mgnet-test-debian`, dépôt monté en lecture seule, `--rm`)
Faux `kubectl` qui journalise chaque argv ; « appels » = nombre d'appels `kubectl`, tous verbes confondus.

| Cible | Premier jet | Version finale |
|---|---|---|
| `-n default pod,secret/x` | `delete [pod,secret] [x]` | 2, 0 appel |
| `Secret/x`, `secrets.v1/x`, `deployments.apps/x` | `delete` émis (sauf `deployments.apps`, non sondé) | 2, 0 appel |
| `all/x` | `delete [all] [x]` | 2, 0 appel |
| `ns/production` | `delete [ns] [production] -n default` | 2, 0 appel |
| `ns/kube-system` | non sondé (relevé par Opus) | 2, 0 appel |
| `no/noeud1`, `crds/x` | `delete` émis | 2, 0 appel |
| `pv/x`, `secret/x` | 1, 0 appel | 2, 0 appel |
| `pvc/x`, `clusterrole/x` | non sondé | 2, 0 appel |
| `pod/X`, `pod/x..`, `-n Default pod/x` | non sondé | 2, 0 appel |
| `pod/x --all`, `pod/-l`, `pod/--all=true`, `-l/x`, `--all/x` | 2, 0 appel | 2, 0 appel |
| nom avec tabulation (`pod/x<TAB>--all`) | `delete` émis, un seul argv | 2, 0 appel |
| `-n --all-namespaces pod/x`, `-n -kube-system pod/x` | 2, 0 appel | 2, 0 appel |
| `-n "kube-system " pod/x` (espace final) | `delete` émis | 2, 0 appel |
| `-n default -l app=x` ; `-n default pods` | 2, 0 appel | 2, 0 appel |
| `-n kube-system`, `kube-public`, `kube-node-lease` ; namespace protégé en 2e cible | 1, 0 appel | 1, 0 appel |
| `-n default deploy/nginx`, `cm/x` | non sondé | 0, `delete [deployments] [nginx]`, `delete [configmaps] [x]`, `--wait=false` |
| `-n a pod/x -n b pod/y` | `delete` sur les deux | 0, deux `delete [pods]` dans leur namespace |
| `--dry-run` | 0, aucun `delete` | 0, 0 appel |
| sans terminal ni `--yes` ; `ASSUME_YES=true` hérité sans terminal | 1, aucun `delete` | 1, aucun `delete` |
| pseudo-terminal (`script -qec`) : `ASSUME_YES=true` hérité et réponse « n » / réponse « o » / `--yes` | 1 sans `delete` / 0, 1 `delete` / 0, 1 `delete` | 1 sans `delete`, question posée / 0, 1 `delete` / 0, 1 `delete` |
| cible inexistante parmi deux | 1 « Cible inexistante », aucun `delete` | 1, aucun `delete` |
| apiserver injoignable | 1, aucun `delete` | 1 « Apiserver injoignable », aucun `delete` |
| Forbidden sur `delete` | 1 « Droits insuffisants » | 1, bilan « 1 en échec » |
| échec partiel : Forbidden sur la 2e de 3 cibles | 1, 3e cible non tentée | 1, 3 `delete` tentés, « 2 supprimée(s), 1 en échec » |
| objet encore présent après `delete` | 1 « Suppression incomplète » | 1 « Nettoyage inachevé » |
| faux kubectl qui dort 40 s | 1 « délai dépassé (30 s) » (124) | 1 « Délai dépassé (30 s) » |
| `timeout` absent du PATH | 1, message de `require_cmd` | non rejoué (code inchangé, `require_cmd kubectl timeout`) |
| `--request-timeout` sur les appels journalisés | 100 % | 100 % |

## Git
Activation fd61c01 ; branche `agent/TASK-061` (efb542b, 33f77de) fusionnée `--no-ff` (3077948), copie retirée, branche supprimée. Pas de push : dernière tâche du lot Maintenance, la session s'en charge.

## Réserves
- A96 — version corrigée non relue par Opus ; aucun effet constaté contre un vrai cluster ; `DELAI_TEST` lu dans tout conteneur et évalué sans contrôle ; expiration de `--request-timeout` côté kubectl non nommée ; groupe « non tentées » devenu impossible à remplir.
- A97 — script à 198 lignes et fichier de cas à 256 lignes, au-delà des ~150.
