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

## Utilisation

```bash
./Kubernetes/Maintenance/cluster-status.sh          # relevé du cluster du kubeconfig courant
KUBECONFIG=~/.kube/autre ./Kubernetes/Maintenance/cluster-status.sh
./Kubernetes/Maintenance/cluster-status.sh --help   # rubriques, kubeconfig, codes de retour
```

## Risques

Aucun sur le cluster : lecture seule. La sortie liste noms de nœuds, adresses IP,
namespaces et services : à ne pas publier telle quelle. Un code 0 dit seulement que
l'apiserver a répondu à la sonde (A78), pas que le cluster est sain.

## Systèmes supportés

Tout système où `kubectl` tourne ; validé en conteneur Debian avec un faux
`kubectl`, jamais contre un vrai cluster.
