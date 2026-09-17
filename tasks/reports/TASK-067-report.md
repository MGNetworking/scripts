# TASK-067 — Rapport d'exécution

## Compte rendu
TASK-067 (`configure-namespaces.sh`) est terminée et fusionnée. C'est le troisième script de `Kubernetes/Configuration/`. La décision 48 demande de créer les namespaces communs du cluster listés dans `SRV_K8S_NAMESPACES` (`config/server.env`, noms séparés par des virgules), sans root et sans jamais rien supprimer. Un namespace est un espace de noms qui cloisonne les ressources d'un cluster. Le script **écrit** dans le cluster par `kubectl apply`, mais seulement pour les namespaces absents : ceux qui existent déjà ne sont ni modifiés ni réappliqués. `SRV_K8S_NAMESPACES` servira aussi à TASK-071 (registry).

À l'activation, le conducteur a complété la fiche avec les faits Kubernetes :
- un nom de namespace suit la règle DNS-1123 (minuscules, chiffres, « - », 63 caractères au plus) ;
- `kubectl create namespace` échoue en « AlreadyExists » si le namespace existe ;
- `default` et tout préfixe `kube-` sont réservés ;
- chaque appel doit être borné par un délai, et un échec partiel ne doit jamais finir en `[SUCCESS]` (A78).

L'agent DeepSeek a livré 148 lignes de script et 150 lignes de cas en deux passages. Le conducteur a sondé le script en conteneur avec son propre faux `kubectl`, qui journalise :
- quinze listes piégées (`a,`, `a,a`, `A`, `-a`, `kube-x`, `default`, 64 caractères, `a$(id)`…) rendent 2 sans aucun appel ;
- une seconde exécution ne crée rien, et `--dry-run` n'écrit rien ;
- un échec partiel rend 1 avec le bilan, sans `[SUCCESS]` ;
- un `ASSUME_YES` hérité confirme sous pseudo-terminal, conformément à la décision 45 ;
- sur onze mutations du script, dix font échouer la suite.

Il a aussi trouvé trois défauts. Une liste avec un retour à la ligne (`web⏎kube-x`) était acceptée : le script créait `web` et ignorait le reste sans rien dire. Une création interrompue par le délai n'était pas nommée comme telle. Et la mutation qui reconnaît un namespace existant par sous-chaîne survivait.

La relecture Opus a confirmé ces trois points et en a ajouté un : l'idempotence n'était prouvée que par un état pré-rempli, pas par deux exécutions enchaînées. La relance unique a tout corrigé. Les lignes d'assertion passent de 60 à 76 sans qu'aucune ne disparaisse, et chaque changement de test est justifié dans le commit.

Sans seconde relecture, le conducteur a relu les corrections et rejoué ses sondes sur la version finale. Dix-huit listes piégées, dont `web⏎kube-x`, `web⏎` et une tabulation, rendent 2 sans appel. La seconde de deux exécutions enchaînées ne fait aucun apply. `web` est bien créé face à un existant `web-prod`. Un apply expiré affiche « Création de « t1 » interrompue : délai dépassé ». Enfin, les neuf mutations, dont `grep -qF`, sont toutes détectées.

Réserves :
- la version corrigée n'a pas été relue et n'a jamais touché un vrai cluster (A116) ;
- le fichier de cas dépasse les ~150 lignes (A117).

Coût agent : 0,179 $ en deux lancements ; relecture : 30 624 jetons.

## Statut
COMPLETED

## Travail réalisé
- `Kubernetes/Configuration/configure-namespaces.sh` — 150 lignes
- `tests/integration/configure-namespaces.test.sh` — 187 lignes, 89 vérifications. Faux `kubectl` (manifeste jugé : `apiVersion: v1`, `kind: Namespace`, `metadata.name` ; verbes create, delete, patch, replace, edit et prune refusés ; Forbidden, injoignable, kubeconfig invalide ; créations mémorisées et relues par `get`), deux faux `timeout` (124 sur le get, 124 sur l'apply), listes piégées, idempotence par deux exécutions
- `config/server.env.example` — bloc `SRV_K8S_NAMESPACES`
- par le conducteur : fiche (faits Kubernetes), `Kubernetes/Configuration/README.md` (prérequis, ligne du script, utilisation, risques), `Kubernetes/README.md`, README racine (`Configuration` : 3 scripts), backlog (TASK-071 débloquée), journal, registre (A116, A117)

## Déroulé
| Étape | Qui | Résultat |
|---|---|---|
| activation | conducteur | 35db3ae (fiche complétée : DNS-1123, AlreadyExists, réservés, délais, A78) |
| lancement 1 | agent `deepseek` | 2 passages, 51 tours, 648 s, 0,115 $ ; 148 + 150 lignes ; commits f3f9b8b, 0314d5b |
| vérification | conducteur | juge 0 (71) ; périmètre : 3 fichiers du scope ; lignes d'assertion 60 = 60 ; sondes, 11 mutations dont 1 survivante |
| relecture | Opus, 9 appels, 30 624 jetons, 50 s | FUSIONNABLE APRÈS CORRECTIONS — 3 majeurs, 1 mineur |
| relance | agent `deepseek` | 1 passage, 42 tours, 559 s, 0,064 $ ; 150 + 187 lignes ; commit fe2b299, changements de test justifiés |
| vérification | conducteur | périmètre : 3 fichiers ; lignes d'assertion 60 → 76, ajouts seuls ; sondes rejouées, 9 mutations détectées |
| fusion | conducteur | b4563a8 |

## Validations (relancées par le conducteur, version finale)
| Commande | Code |
|---|---|
| `bash orchestration/outils/juger.sh tasks/active/TASK-067.md` | 0 — shellcheck 0, fichier de cas 0 (89 réussies), règles du dépôt 3 |
| `tests/env/run-in-container.sh -- tests/run.sh lint` | 0 (0 erreur) |
| `tests/env/run-in-container.sh -- tests/run.sh integration` | 0 (configure-namespaces : 89 réussies, 0 échec, 0 NON EXÉCUTÉ) |
| `tests/env/run-in-container.sh -- bash Kubernetes/Configuration/configure-namespaces.sh --help` | 0 |

## Sondes du conducteur (conteneur `debian`, faux `kubectl` indépendant, version finale)
| Sonde | Résultat |
|---|---|
| `web⏎kube-x`, `web⏎`, `⇥web`, `a,`, `,a`, `a,,b`, `a, b`, `a,a`, `A`, `-a`, `kube-x`, `kube-system`, `default`, 64 caractères, `a$(id)`, `a b`, `a;b`, `é` | 2, aucun appel kubectl |
| deux exécutions enchaînées `web,data` | 0 et 2 apply, puis 0, aucun apply, « existent déjà : aucun changement » |
| `web` face à l'existant `web-prod` | 0, un apply |
| `--dry-run` | 0, aucun apply, rien créé |
| `p,q,s`, apply de `q` refusé (Forbidden) | 1, sans `[SUCCESS]`, « 1 créé(s), 1 échoué (q), 1 non tenté(s) » |
| `ASSUME_YES=true` hérité sous pseudo-terminal, sans `--yes` | 0, namespace créé ; réponse « n » : 1, aucun apply (1er passage) |
| apply coupé par `timeout` (124) | 1, « Création de « t1 » interrompue : délai dépassé », bilan, sans `[SUCCESS]` |
| Forbidden, `i/o timeout`, kubeconfig illisible sur le get | 1, trois messages distincts (1er passage) |
| 9 mutations (`grep -qF`, blancs admis, 124 d'apply non nommé, `kube-` non réservé, doublon admis, sans `--request-timeout`, pas d'arrêt au premier échec, échec partiel en 0, `--dry-run` ignoré) | suite en échec chaque fois |

## Réserves
- version corrigée non relue par Opus ; codes et messages réels de `kubectl get namespaces` et `apply` jamais constatés sur un vrai cluster (A116)
- fichier de cas à 187 lignes, au-delà des ~150 (A117)

## Git
Branche `agent/TASK-067` fusionnée `--no-ff` (b4563a8), copie `../script-agents/TASK-067` retirée, branche supprimée. Pas de push.
