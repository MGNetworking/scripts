# Kubernetes

Tout ce qui s'adresse à un cluster Kubernetes quelle que soit son origine : ces
scripts n'utilisent que `kubectl` et survivraient au remplacement de K3s par un
cluster managé. Ce qui dépend de K3s lui-même vit dans `Linux/K3s/`.

| Dossier | Rôle | État |
|---|---|---|
| `Installation/` | outils et composants de l'écosystème (Helm, cert-manager…) | à venir |
| `Configuration/` | namespaces, registry, ressources de configuration | à venir |
| [Maintenance/](Maintenance/README.md) | exploitation et diagnostic du cluster | 2 scripts |

Prérequis communs : `kubectl` installé et un kubeconfig que `kubectl` résout
lui-même (`KUBECONFIG`, sinon `~/.kube/config`). Les workloads gérés par
Kubernetes ne s'administrent jamais par `docker restart` ou équivalent.
