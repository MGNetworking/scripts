# Kubernetes

Tout ce qui s'adresse à un cluster Kubernetes quelle que soit son origine : ces
scripts n'utilisent que `kubectl` et survivraient au remplacement de K3s par un
cluster managé. Ce qui dépend de K3s lui-même vit dans `Linux/K3s/`.

| Dossier | Rôle | État |
|---|---|---|
| [Installation/](Installation/README.md) | vérification de kubectl et de Traefik, installation de Helm et de cert-manager, outils de l'écosystème | 4 scripts |
| [Configuration/](Configuration/README.md) | namespaces communs, Middlewares Traefik, ClusterIssuers Let's Encrypt, StorageClass par défaut, Secret du registry privé | 5 scripts |
| [Maintenance/](Maintenance/README.md) | exploitation et diagnostic du cluster | 7 scripts |

Prérequis communs : `kubectl` installé et un kubeconfig que `kubectl` résout
lui-même (`KUBECONFIG`, sinon `~/.kube/config`). Les workloads gérés par
Kubernetes ne s'administrent jamais par `docker restart` ou équivalent.
