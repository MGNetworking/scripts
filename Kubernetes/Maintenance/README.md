# Kubernetes/Maintenance

Exploitation et diagnostic d'un cluster Kubernetes quelconque, par `kubectl` seul
(jamais `k3s kubectl`). Lecture seule d'abord (décision 16).

## Prérequis

- `kubectl` dans le `PATH` ;
- un kubeconfig résolu par `kubectl` lui-même : `KUBECONFIG`, sinon `~/.kube/config` ;
- root non requis.

## Scripts

| Script | Rôle | Privilèges | Modifie le système |
|---|---|---|---|
| `cluster-status.sh` | relevé en lecture seule, rubriques dans l'ordre : nœuds (`-o wide`), versions client et serveur, namespaces, pods, deployments et services de tous les namespaces ; chaque appel borné par `--request-timeout` (5 s) et `timeout`. La rubrique des nœuds sert de sonde : si elle échoue, `[ERROR]` et arrêt. Une rubrique suivante en échec affiche l'erreur de `kubectl` sans interrompre le relevé ; une rubrique vide affiche « aucun élément ». Aucun kubeconfig, Secret ni manifeste affiché ; aucun verdict de santé (`diagnostics.sh`). Codes : 0 apiserver joignable, quel que soit l'état des pods, 1 `kubectl` absent ou apiserver injoignable, 2 option inconnue | utilisateur | non |
| `pods-status.sh` | pods en lecture seule par `kubectl get pods -o wide`, intitulés de colonnes compris : tous les namespaces (`-A`) sans option, un seul avec `--namespace <ns>`. Le namespace est d'abord vérifié par `kubectl get namespace` : `get pods -n <inconnu>` rend 0 avec « No resources found », et une faute de frappe passerait pour un namespace vide. Namespace absent (`NotFound`) et apiserver injoignable ont chacun leur message ; un droit RBAC limité au namespace peut toutefois faire échouer cette vérification (A82). Chaque appel borné par `--request-timeout` (5 s) et `timeout` ; la sortie d'erreur de `kubectl` n'est affichée qu'en cas d'échec. Aucun verdict de santé. Codes : 0 liste affichée, vide comprise, quel que soit l'état des pods, 1 `kubectl` ou `timeout` absent, apiserver injoignable ou namespace inconnu, 2 option inconnue, `--namespace` sans valeur ou commençant par « - » | utilisateur | non |
| `events.sh` | événements en lecture seule par `kubectl get events`, tous les namespaces (`-A`) sans option, un seul avec `--namespace <ns>`, vérifié d'abord par `kubectl get namespace` (`NotFound` : namespace inconnu ; `Forbidden` : droits insuffisants ; sinon apiserver injoignable). Tri par `--sort-by=.metadata.creationTimestamp`, le plus ancien en tête : `.lastTimestamp` placerait en tête les événements de l'API events.k8s.io, qui n'en ont pas ; un événement répété garde sa date de création. `--warnings` ajoute `--field-selector type=Warning`, filtré côté serveur. Chaque appel borné par `--request-timeout` (5 s) et `timeout` (7 s) ; la sortie d'erreur de `kubectl` n'est affichée qu'en cas d'échec. Les événements expirent (une heure par défaut) : liste vide annoncée en `[INFO]`, pas une panne. Aucun verdict. Codes : 0 liste affichée, vide comprise, Warning compris, 1 `kubectl` ou `timeout` absent, apiserver injoignable, droits insuffisants ou namespace inconnu, 2 option inconnue, `--namespace` sans valeur ou commençant par « - » | utilisateur | non |
| `diagnostics.sh` | recherche en lecture seule des anomalies du cluster, avec un verdict par le code de retour : nœuds non `Ready` (un nœud cordonné `Ready,SchedulingDisabled` est prêt) ; pods dont la colonne STATUS porte Pending, Failed, Unknown, Error, Evicted, OOMKilled, CrashLoopBackOff, ImagePullBackOff, ErrImagePull, CreateContainerConfigError ou ContainerStatusUnknown, préfixe `Init:` compris (Completed et Succeeded ne sont pas des anomalies) ; Deployments, StatefulSets et DaemonSets dont les répliques prêtes sont inférieures aux désirées, lues en `-o custom-columns` (la sortie par défaut d'un DaemonSet n'a pas de « x/y ») ; événements Warning triés par `--sort-by=.metadata.creationTimestamp`, affichés pour information sans effet sur le code. La rubrique des nœuds sert de sonde : `Forbidden` → droits insuffisants, sinon apiserver injoignable, et arrêt. Une rubrique suivante illisible, événements compris, compte comme anomalie sans interrompre le diagnostic : jamais de `[SUCCESS]` sur un diagnostic amputé (A78). Chaque appel borné par `--request-timeout` (5 s) et `timeout` (7 s). Ni `logs`, ni `describe`, ni manifeste. Codes : 0 aucune anomalie, 1 au moins une anomalie, relevé impossible, `kubectl` ou `timeout` absent, droits insuffisants ou apiserver injoignable, 2 option inconnue | utilisateur | non |
| `resource-usage.sh` | CPU et mémoire en lecture seule : sonde `kubectl get nodes` (`Forbidden` → droits insuffisants, sinon apiserver injoignable, et arrêt) ; avec `--namespace <ns>`, namespace vérifié par `kubectl get namespace` (`NotFound` : inconnu ; `Forbidden` : droits insuffisants ; sinon apiserver injoignable). API metrics disponible : `kubectl top nodes` puis `kubectl top pods -A` (ou `-n <ns>`), intitulés de colonnes compris. API metrics absente (« Metrics API not available ») ou installée mais en panne (`ServiceUnavailable`) : `[WARN]` qui nomme la cause, puis capacité et allocatable (CPU, mémoire) de chaque nœud extraits de `kubectl describe nodes`, code 0 (décision 48). `Forbidden` sur `top` ou `describe` : échec, sans repli. `top nodes` sans tableau : rubrique vide, code 1, jamais `[SUCCESS]` (A78) ; aucun pod : `[INFO]`, code 0. Appels bornés par `--request-timeout` (5 s, 30 s pour `describe nodes`) et `timeout` (délai + 2 s) ; code 124 → « délai dépassé ». Codes : 0 relevé affiché, métriques ou capacité à défaut, 1 `kubectl` ou `timeout` absent, apiserver injoignable, droits insuffisants, namespace inconnu, délai dépassé ou rubrique vide, 2 option inconnue, `--namespace` sans valeur ou commençant par « - » | utilisateur | non |
| `backup-resources.sh` | export YAML sans aucune écriture sur le cluster, liste fixe de types : `namespaces` et `storageclasses` une fois ; `deployments`, `statefulsets`, `daemonsets`, `cronjobs`, `services`, `ingresses`, `configmaps` et `persistentvolumeclaims` par namespace. Jamais de Secrets, jamais `get all`. Destination : `--output`, sinon `SRV_K8S_BACKUP_DIR` (`config/server.env`), sinon `/var/backups/kubernetes`, non inscriptible sans root (`[ERROR]` qui nomme les deux remèdes, code 1). Chemin résolu par `realpath -m` (liens, chemin relatif, `..`) et refusé s'il est dans le dépôt, avant toute écriture. Sonde `kubectl get namespaces` avant d'écrire quoi que ce soit. Puis un sous-dossier `AAAAMMJJ-HHMMSS-XXXXXX` par exécution (`mktemp -d`, aucun écrasement) et un fichier `<type>.yaml` ou `<type>.<namespace>.yaml` ; dossiers 0700, fichiers 0600 (`umask 077`). Retirés de chaque objet : `status`, et dans son `metadata` `uid`, `resourceVersion` et `managedFields` ; le reste est gardé tel quel (données, labels, `ownerReferences`). Appels bornés par `--request-timeout` (30 s) et `timeout` (délai + 2 s) ; 124 → « délai dépassé » ; `Forbidden` → droits insuffisants ; type inconnu de l'apiserver nommé. Échec en cours d'export : code 1, dossier incomplet nommé, jamais `[SUCCESS]`. `--dry-run` : destination, namespaces et types, rien écrit. Codes : 0 export terminé, chemin affiché ; 1 destination refusée ou non inscriptible, `kubectl`, `timeout` ou `realpath` absent, apiserver injoignable, droits insuffisants, délai dépassé, export incomplet ; 2 option inconnue ou `--output` sans valeur | utilisateur | fichiers locaux seulement |

## Utilisation

```bash
./Kubernetes/Maintenance/cluster-status.sh          # relevé du cluster du kubeconfig courant
KUBECONFIG=~/.kube/autre ./Kubernetes/Maintenance/cluster-status.sh
./Kubernetes/Maintenance/cluster-status.sh --help   # rubriques, kubeconfig, codes de retour
./Kubernetes/Maintenance/pods-status.sh             # pods de tous les namespaces
./Kubernetes/Maintenance/pods-status.sh --namespace kube-system
./Kubernetes/Maintenance/events.sh                  # événements de tous les namespaces, du plus ancien au plus récent
./Kubernetes/Maintenance/events.sh --namespace kube-system --warnings
./Kubernetes/Maintenance/diagnostics.sh             # anomalies du cluster : 0 aucune, 1 au moins une
./Kubernetes/Maintenance/resource-usage.sh          # CPU et mémoire ; sans API metrics, capacité des nœuds
./Kubernetes/Maintenance/resource-usage.sh --namespace kube-system
./Kubernetes/Maintenance/backup-resources.sh --dry-run --output ~/sauvegardes/k8s   # destination, namespaces, types
./Kubernetes/Maintenance/backup-resources.sh --output ~/sauvegardes/k8s             # export horodaté, hors dépôt
```

## Risques

Aucun sur le cluster : lecture seule, `diagnostics.sh` compris, qui ne corrige rien. La
sortie liste noms de nœuds, adresses IP, namespaces, pods et services : à ne pas publier
telle quelle. Un code 0 dit seulement que l'apiserver a répondu à la sonde (A78), pas que
le cluster est sain — sauf pour `diagnostics.sh`, dont le code porte le verdict, dans la
limite de ses rubriques.

`backup-resources.sh` n'écrit rien sur le cluster, mais écrit des fichiers locaux : les
ConfigMaps exportées peuvent porter des données sensibles. D'où les droits 0700 et 0600,
et le refus de toute destination dans le dépôt, qui est public. Les Secrets ne sont jamais
exportés : la sauvegarde ne suffit donc pas à reconstruire un cluster.

## Systèmes supportés

Tout système où `kubectl` tourne ; validé en conteneur Debian avec un faux
`kubectl`, jamais contre un vrai cluster.
