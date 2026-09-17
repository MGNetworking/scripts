# TASK-068 — Rapport d'exécution

## Compte rendu
TASK-068 (`configure-storage.sh`) est terminée et fusionnée. C'est le quatrième script de `Kubernetes/Configuration/`. Une StorageClass décrit une façon de créer des volumes ; celle « par défaut » sert à tout PVC qui n'en nomme aucune. K3s fournit `local-path`, déjà marquée par défaut : dès qu'une seconde classe l'est aussi, le choix n'est plus celui qu'on croit. La décision 48 demande donc exactement une classe par défaut, `local-path` ou `SRV_K8S_STORAGE_CLASS`, sans root, sans créer ni supprimer de classe. Le script **écrit** dans le cluster, mais seulement des annotations, par `kubectl annotate --overwrite`.

À l'activation, le conducteur a complété la fiche :
- les faits Kubernetes : l'annotation `storageclass.kubernetes.io/is-default-class`, sa lecture par jsonpath, et le fait que K3s réapplique peut-être `local-path` au redémarrage ;
- les défauts connus du domaine : l'ordre sûr (marquer la cible avant de démarquer les autres, pour ne jamais passer par zéro classe par défaut), les délais, un échec partiel qui ne finit jamais en `[SUCCESS]`, les mutations.

L'agent DeepSeek a livré 150 lignes de script et 223 lignes de cas. Le conducteur a sondé le script en conteneur avec son propre faux `kubectl`, qui journalise et garde l'état. Tout tenait : l'ordre des annotations, le refus d'une classe absente, les noms invalides rejetés sans appel, l'idempotence, `--dry-run`, `ASSUME_YES` hérité, l'échec partiel. Mais une mutation survivait : quand le script continuait après un annotate refusé, aucun test ne le voyait.

La relecture Opus a trouvé plus grave. Kubernetes tient aussi une classe pour « par défaut » si l'**ancienne clé bêta** `storageclass.beta.kubernetes.io/is-default-class` vaut `"true"`, et la session l'a vérifié sur la source (`pkg/volume/util/storageclass.go`). S'il en reste plusieurs, la plus récemment créée l'emporte. Le script ignorait cette clé : une classe marquée ainsi restait par défaut sans qu'il la voie. S'y ajoutaient un test manquant (annotation de la cible refusée) et quatre défauts mineurs.

La relance unique a tout corrigé. L'agent a même trouvé seul un piège réel : une annotation absente ne s'imprime pas dans le jsonpath, si bien qu'un séparateur espace décalait la clé bêta en clé GA. Il sépare désormais par « | ». Sans seconde relecture, le conducteur a relu les corrections et rejoué sa sonde avec les deux clés. Une mutation survivait encore : le relevé qui oublie la clé bêta, invisible quand la cible n'était pas déjà marquée. Le conducteur a ajouté le cas et le mutant dans la copie, puis tout revalidé. Les lignes d'assertion passent de 70 à 86 sans qu'aucune ne disparaisse, hors « a--b », que la relecture demandait d'accepter.

Réserves :
- la version corrigée n'a pas été relue et n'a jamais touché un vrai cluster, ni un K3s redémarré (A118) ;
- script et fichier de cas dépassent les ~150 lignes (A119) ;
- le premier commit de l'agent n'a pas la ligne `Tâche :` (A66).

Coût agent : 0,437 $ en deux lancements ; relecture : 38 696 jetons.

## Statut
COMPLETED

## Travail réalisé
- `Kubernetes/Configuration/configure-storage.sh` — 170 lignes
- `tests/integration/configure-storage.test.sh` — 296 lignes, 134 vérifications. Faux `kubectl` à deux clés et à état (verbes create, delete, patch, replace, edit, apply et prune refusés ; Forbidden, NotFound, injoignable, kubeconfig invalide ; dérive simulée), faux `timeout` en 124 sur get et sur annotate, pseudo-terminal, idempotence par deux exécutions, section Mutations qui relance la suite contre 5 mutants
- `config/server.env.example` — bloc `SRV_K8S_STORAGE_CLASS`
- par le conducteur : fiche (faits Kubernetes, défauts connus), deux commits de test dans la copie, `Kubernetes/Configuration/README.md` (prérequis, ligne du script, utilisation, risques : deux clés, la plus récente l'emporte, réapplication par K3s), `Kubernetes/README.md`, README racine (`Configuration` : 4 scripts), backlog, journal, registre (A118, A119, occurrence A66)

## Déroulé
| Étape | Qui | Résultat |
|---|---|---|
| activation | conducteur | 03a487a |
| lancement 1 | agent `deepseek` | 3 passages, 85 tours, 1 177 s, 0,181 $ ; 150 + 223 lignes ; commit 11a1ae1 (sans ligne `Tâche :`) |
| vérification | conducteur | juge 0 (104) ; périmètre : 3 fichiers du scope ; sonde 36 ok ; 6 mutations, 1 survivante (« exit 1 » après annotate refusé) |
| relecture | Opus, 8 appels, 38 696 jetons, 65 s | FUSIONNABLE APRÈS CORRECTIONS — 2 majeurs, 4 mineurs |
| relance | agent `deepseek` | 2 passages, 132 tours, 1 943 s, 0,256 $ ; 170 + 290 lignes ; commits 6cdfc46, 30270bc, changements de test justifiés |
| vérification | conducteur | périmètre : 3 fichiers ; lignes d'assertion 70 → 84 ; sonde 44 ok ; mutant « relevé sans clé bêta » survivant |
| fin dans la copie | conducteur | 44f29cb (cas et mutant ajoutés), 39f6c7a (SC2016) ; lignes d'assertion 86 |
| fusion | conducteur | 18f6874 |

## Validations (relancées par le conducteur, version finale)
| Commande | Code |
|---|---|
| `bash orchestration/outils/juger.sh tasks/active/TASK-068.md` | 0 — shellcheck 0, fichier de cas 0 (134 réussies), règles du dépôt 3 |
| `tests/env/run-in-container.sh -- tests/run.sh lint` | 0 (0 erreur, 2 avertis préexistants `Synology/Plex`) |
| `tests/env/run-in-container.sh -- tests/run.sh integration` | 0 (42 bilans, 0 échec) |
| `tests/env/run-in-container.sh -- bash Kubernetes/Configuration/configure-storage.sh --help` | 0 ; signale la réapplication de `local-path` par K3s |

## Sonde du conducteur (conteneur `debian`, faux `kubectl` indépendant, version finale)
46 ok, 0 KO :
- local-path et nfs marquées, cible zfs : 0 ; journal `zfs` GA=true, puis `local-path` GA=false, puis `nfs` GA=false ; seule zfs par défaut ; 3 classes ; 2e exécution sans annotate ;
- classe marquée par la seule clé bêta : bêta posée à false, GA non créée, seule la cible par défaut ; classe marquée par les deux clés : démarquée ; cible déjà marquée face à une autre marquée par la seule bêta : autre démarquée ;
- annotation de la cible refusée (Forbidden) : 1, un seul annotate, les autres restent marquées, pas de `[SUCCESS]`, cause nommée ;
- cible inexistante : 1 sans annotate ; `Bad_Name`, `-x`, `x.`, `--help`, `a b`, `a.-b` : 2 sans appel ; `a--b` accepté ;
- déjà seule par défaut, et `--dry-run` : 0 sans annotate, état intact ; `ASSUME_YES` hérité sans terminal : 1 ;
- démarquage d'une autre refusé : 1, bilan, pas de `[SUCCESS]` ;
- journal cumulé : aucun create, delete, apply, replace ni patch ; `--request-timeout` sur chaque appel ; ni `k3s.yaml` ni `require_root`.

Mutations dans une copie jetable (suite de l'agent / sonde) : témoin 0/0 ; « exit 1 » de la boucle retiré 1/1 ; clé bêta remplacée par la GA 1/1 ; ordre inversé 1/1 ; relevé sans clé bêta 1/1.

## Réserves
- version corrigée non relue par Opus ; jsonpath réel sur une clé absente et réapplication de `local-path` par K3s au redémarrage jamais constatés sur un vrai cluster (A118)
- script à 170 lignes et fichier de cas à 296, au-delà des ~150 (A119)
- premier commit 11a1ae1 sans ligne `Tâche : TASK-068`, attribution `Claude Code` (A66)

## Git
Branche `agent/TASK-068` fusionnée `--no-ff` (18f6874), copie `../script-agents/TASK-068` retirée, branche supprimée. Pas de push.
