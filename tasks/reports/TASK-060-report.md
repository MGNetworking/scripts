# TASK-060 — Rapport d'exécution

## Compte rendu
TASK-060 (`backup-resources.sh`) est terminée et fusionnée. C'est le sixième script de `Kubernetes/Maintenance/`, et le premier qui écrit quelque chose : il n'écrit rien sur le cluster, mais exporte en YAML une liste fixe de types de ressources dans un dossier local (décision 48). Trois dangers propres à ce script ont guidé la vérification :
- écrire un Secret ;
- écrire l'export dans le dépôt, qui est public ;
- abîmer les données sauvegardées.

L'agent DeepSeek a livré 150 lignes de script et 260 lignes de cas en un passage. Le juge et les trois validations de la fiche rendaient 0, et le périmètre était respecté.

Avant la relecture, le conducteur a lu le code et lancé deux sondes en conteneur. Elles ont prouvé deux défauts graves que les tests ne voyaient pas :
- `--output /nexiste/../<dépôt>/fuite` rendait 0 : l'export était écrit **dans le dépôt**, et `/nexiste` était créé à la racine. Le contrôle portait sur un chemin mal résolu, et la création sur le chemin brut ;
- le filtre qui retire les champs volatiles supprimait toute ligne `status:` ou `uid:`, à n'importe quelle profondeur. Une ConfigMap perdait ainsi ses propres données, y compris à l'intérieur d'un bloc `|`.

La relecture Opus les a confirmés comme bloquants, avec des mineurs : une branche NotFound qui ne pouvait jamais être atteinte, le dossier non inscriptible sans root non testé, et des tests creux.

La relance unique a tout corrigé :
- résolution par `realpath -m`, puis contrôle et création sur le même chemin résolu ;
- filtre structurel, qui ne retire que le `status` d'un objet et l'`uid`, le `resourceVersion` et le `managedFields` de son `metadata` ;
- vrai message d'un type inconnu de l'apiserver ;
- cas sans droit d'écriture, joué par l'utilisateur `nobody` ;
- aucune assertion retirée (97 → 123 lignes d'assertion).

Il n'y a pas eu de seconde relecture : le conducteur a rejoué lui-même ses deux sondes sur la version finale, et elles tiennent (voir « Sondes »).

Pour les Secrets, les types sont écrits en dur, sans option pour élargir la liste et sans `get all` : aucun chemin d'export n'a été trouvé.

Réserves : la version corrigée n'a pas été relue par Opus et le format du YAML n'a jamais été constaté sur un vrai cluster (A94) ; le fichier de cas fait 356 lignes (A95).

Coût agent : 0,263 $ en deux lancements ; relecture : 38 415 jetons.

## Statut
COMPLETED

## Travail réalisé
- `Kubernetes/Maintenance/backup-resources.sh` — 150 lignes
- `tests/integration/backup-resources.test.sh` — 356 lignes, 131 vérifications. Il utilise un faux `kubectl` en tête de PATH, qui rend « No resources found » sur stderr, `Forbidden`, le refus de connexion et « doesn't have a resource type » comme le vrai, compte un Secret et note ses arguments ; il utilise aussi un faux `timeout` qui rend 124.
- `config/server.env.example` — `SRV_K8S_BACKUP_DIR`, facultative
- par le conducteur : `Kubernetes/Maintenance/README.md`, `Kubernetes/README.md`, le README racine, le backlog, le journal et le registre (A94, A95)

## Déroulé
| Étape | Qui | Résultat |
|---|---|---|
| activation | conducteur | commit a4b6529 (fiche, statut, backlog, défauts connus du lot en notes) |
| lancement 1 | agent `deepseek` | 1 passage, 66 tours, 389 s, 0,152 $ ; 150 + 260 lignes ; commits a5c50b3, 7d97fec |
| vérification | conducteur | juge 0 (105 vérifications) ; périmètre : 3 fichiers du scope ; 97 lignes d'assertion aux deux commits ; 2 sondes en échec (dépôt, filtre) |
| relecture | Opus, 9 appels, 38 415 jetons, 112 s | FUSIONNABLE APRÈS CORRECTIONS — 2 bloquants, mineurs, tests creux |
| relance | agent `deepseek` | 1 passage, 42 tours, 316 s, 0,111 $ ; 150 + 356 lignes ; commit b26bb5e, chaque changement de test justifié |
| vérification | conducteur | périmètre : 3 fichiers ; 97 → 123 lignes d'assertion, lignes retirées remplacées comme demandé ; sondes rejouées : tenues |

## Validations (relancées par le conducteur dans la copie de l'agent, version finale)
| Commande | Code |
|---|---|
| `bash orchestration/outils/juger.sh tasks/active/TASK-060.md` | 0 — shellcheck 0, fichier de cas 0 (131 réussies, 0 échec), règles du dépôt 3 (NON EXÉCUTÉ d'environnement) |
| `tests/env/run-in-container.sh -- tests/run.sh lint` | 0 |
| `tests/env/run-in-container.sh -- tests/run.sh integration` | 0 — aucun bilan en échec ; backup-resources.sh 131 réussies, 0 échec |
| `tests/env/run-in-container.sh -- bash Kubernetes/Maintenance/backup-resources.sh --help` | 0 |

## Sondes du conducteur (conteneur `debian`, dépôt monté sur `/depot`, nettoyage en fin de commande)
| Sonde | Premier jet | Version finale |
|---|---|---|
| `--output /nexiste-<pid>/../depot/fuite` | 0, export écrit dans `/depot/fuite`, `/nexiste` créé | 1, « Destination refusée », ni `/depot/fuite` ni `/nexiste-<pid>` |
| `--output absent/../../../fuite-rel` depuis `tests/<sous-dossier>` | non sondé | 1, refus, rien créé |
| `--output <tmp>/lien/fuite-lien`, lien vers le dépôt | refusé | 1, refus, rien créé |
| ConfigMap : `status:` et `uid: "1000"` dans `data` ; `status: garde` et `uid: 1000` dans un bloc `|` ; label `status: actif` ; `ownerReferences[].uid` | les deux lignes du bloc `|` supprimées | les six conservés |
| même objet : `status` de l'item, `uid` et `resourceVersion` de son metadata, `resourceVersion` de la List | retirés | retirés |

## Git
Activation a4b6529 ; branche `agent/TASK-060` (a5c50b3, 7d97fec, b26bb5e) fusionnée `--no-ff` (f7533a7), copie retirée, branche supprimée. Pas de push.

## Réserves
- A94 — version corrigée non relue par Opus ; filtre fondé sur le format de `kubectl get -o yaml` jamais constaté sur un vrai cluster ; `metadata:` racine vide ; le test « aucun kind: Secret » ne prouve que l'absence de demande du type `secrets`.
- A95 — fichier de cas à 356 lignes, au-delà des ~150.
