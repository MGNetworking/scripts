# TASK-064 — Rapport d'exécution

## Compte rendu
TASK-064 (`install-ingress.sh`) est terminée et fusionnée. C'est le quatrième script de `Kubernetes/Installation/`. Sur K3s, l'Ingress Controller Traefik est posé par la distribution : la décision 48 veut que ce script le **vérifie** seulement, sans rien installer ni exiger root, et qu'il signale un conflit sur les ports 80/443. TASK-069 (`configure-ingress.sh`), qui en dépendait, passe en `ready`.

À l'activation, le conducteur a ajouté des notes à la fiche. Les noms K3s (IngressClass, déploiement et Service `traefik` dans `kube-system`) et la publication des ports par servicelb y sont marqués « non vérifiés, à ne pas inventer au-delà ». Les défauts connus du domaine y sont rappelés : délais bornés, colonnes lues par nom, causes d'échec distinguées, faux `kubectl` réaliste, aucune écriture sur le cluster.

L'agent DeepSeek a livré 150 lignes de script et 170 lignes de cas, en deux passages. Le second a seulement retiré un `"$@"` inutile des fonctions de test (avertissement shellcheck), sans toucher aux assertions. Juge et validations à 0. En lisant le code, le conducteur a constaté : aucune écriture sur le cluster, lecture par jsonpath et custom-columns. Pour le conflit de ports, le script croise deux relevés : les Services LoadBalancer étrangers exposant 80 ou 443, et les écoutes de la machine vues par `ss`. Sur K3s, seul le premier est un vrai signal. servicelb publie les ports sans socket, si bien que le silence de `ss` ne prouve rien.

La relecture Opus a jugé le script sain et tous les critères tenus, mais les preuves incomplètes. Elle a relevé deux majeurs. Le faux `kubectl` rendait ses données quelle que soit l'expression `-o` demandée, donc rien ne prouvait les lectures. Le code 124 (délai dépassé) n'était jamais provoqué. S'y ajoutaient des mineurs : messages d'erreur plus réalistes, une phrase affirmant un fait non vérifié sur servicelb, « ressource inconnue de l'API » confondue avec « apiserver injoignable », une seule classe par défaut affichée, une vérification de `ss -ltn` par simple préfixe. La relance unique a tout corrigé : 65 → 90 lignes d'assertion, chaque changement de test justifié dans le commit.

Sans seconde relecture, le conducteur a vérifié les deux majeurs par des sondes en conteneur. Il a cassé volontairement une copie du script cinq fois : clé d'annotation non échappée, `nodePort` au lieu de `port`, `availableReplicas` au lieu de `readyReplicas`, 124 non nommé pour kubectl, puis pour `ss`. Les tests ont échoué à chaque fois (40, 22, 28, 2 et 1 échecs). Il a restauré le script, puis tout revalidé.

Réserves : la version corrigée n'a pas été relue par Opus et n'a jamais touché un vrai K3s (A108). Le fichier de cas dépasse les ~150 lignes (A109). « Prêt » exige toutes les répliques prêtes, ce qui est plus strict que la condition Available pendant une mise à jour progressive (A110).

Coût agent : 0,280 $ en deux lancements ; relecture : 31 001 jetons.

## Statut
COMPLETED

## Travail réalisé
- `Kubernetes/Installation/install-ingress.sh` — 150 lignes
- `tests/integration/install-ingress.test.sh` — 241 lignes, 89 vérifications. Faux `kubectl` (donnée rendue pour la seule expression `-o` attendue, journal d'appels), faux `ss` (colonne des processus avec `-p` seulement), faux `timeout` (124 ciblé sur kubectl ou ss) ; cas sans root par `setpriv` ; garde `/.dockerenv` avant tout `mktemp` et trap.
- par le conducteur : fiche (notes d'implémentation), `Kubernetes/Installation/README.md`, `Kubernetes/README.md`, README racine (`Installation` : 4 scripts), backlog (TASK-069 débloquée), journal, registre (A108 à A110)

## Déroulé
| Étape | Qui | Résultat |
|---|---|---|
| activation | conducteur | 48bf61b (fiche, statut, backlog, notes « non vérifiées ») |
| lancement 1 | agent `deepseek` | 2 passages, 105 tours, 640 s, 0,199 $ ; 150 + 170 lignes ; commits cf84720, fa7e670 |
| vérification | conducteur | juge 0 (64) ; périmètre : 2 fichiers du scope ; lignes d'assertion 65 → 65 (fa7e670 : `"$@"` retiré, SC2120) |
| relecture | Opus, 6 appels, 31 001 jetons, 86 s | FUSIONNABLE APRÈS CORRECTIONS — 2 majeurs, mineurs |
| relance | agent `deepseek` | 40 tours, 236 s, 0,081 $ ; 150 + 241 lignes ; commit 34235fd, chaque changement de test justifié |
| vérification | conducteur | périmètre : 2 fichiers ; lignes d'assertion 65 → 90 ; lignes retirées remplacées par des vérifications plus strictes ; sondes de mutation |
| fusion | conducteur | 2976596 |

## Validations (relancées par le conducteur dans la copie, version finale)
| Commande | Code |
|---|---|
| `bash orchestration/outils/juger.sh tasks/active/TASK-064.md` | 0 — shellcheck 0, fichier de cas 0 (89 réussies), règles du dépôt 3 |
| `tests/env/run-in-container.sh -- tests/run.sh lint` | 0 |
| `tests/env/run-in-container.sh -- tests/run.sh integration` | 0 — install-ingress.sh 89 vérifications, 0 échec |
| `tests/env/run-in-container.sh -- bash Kubernetes/Installation/install-ingress.sh --help` | 0 |

## Sondes de mutation du conducteur (conteneur `debian`, copie du script modifiée puis restaurée)
| Mutation | Fichier de cas | Code |
|---|---|---|
| clé `ingressclass\.kubernetes\.io` non échappée | 40 échecs | 1 |
| `.spec.ports[*].port` → `nodePort` | 22 échecs | 1 |
| `.status.readyReplicas` → `availableReplicas` | 28 échecs | 1 |
| `124:*)` de `echec()` → `125` (kubectl) | 2 échecs | 1 |
| `!= 124` du relevé `ss` → `125` | 1 échec | 1 |

## Réserves
- version corrigée non relue par Opus ; noms K3s, servicelb et messages `kubectl` jamais constatés sur un vrai cluster (A108)
- fichier de cas à 241 lignes, au-delà des ~150 (A109)
- `readyReplicas` ≥ `replicas` plus strict qu'Available pendant une mise à jour progressive (A110)

## Git
Branche `agent/TASK-064` fusionnée `--no-ff` (2976596), copie `../script-agents/TASK-064` retirée, branche supprimée. Pas de push.
