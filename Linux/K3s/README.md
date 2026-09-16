# Linux/K3s

Distribution K3s mono-nœud (décision 23) : ce qui dépend de K3s lui-même. Ce qui
survivrait à un cluster managé va dans `Kubernetes/`. Cibles : Debian 12 et 13,
Ubuntu 22.04 et 24.04 LTS (décision 14).

## Scripts

| Script | Rôle | Privilèges | Modifie le système |
|---|---|---|---|
| `verify-k3s.sh` | diagnostic en lecture seule, rubriques dans l'ordre : service `k3s` (`systemctl is-active`), version, nœuds, pods de tous les namespaces, namespaces, événements Warning ; tout passe par `k3s kubectl`, chaque appel borné par `--request-timeout` ; un nœud non Ready, un pod ni Running ni Succeeded (« Completed ») ou un service inactif sont nommés en `[WARN]` ; les événements Warning s'affichent sans peser sur le verdict. Codes : 0 cluster sain, 1 K3s absent ou anomalie, 2 option inconnue | root (`/etc/rancher/k3s/k3s.yaml`) | non |

## Ordre d'utilisation

Après `Linux/System` et `Linux/Security`. `verify-k3s.sh` sert de vérification
finale à l'installation et à la mise à niveau, qui lisent son code de retour.

```bash
sudo ./Linux/K3s/verify-k3s.sh          # diagnostic ; code 0 si le cluster est sain
./Linux/K3s/verify-k3s.sh --help        # rubriques et codes de retour
```

## Risques

`verify-k3s.sh` ne modifie rien et n'affiche ni kubeconfig, ni jeton de nœud, ni
Secret. Il n'a été éprouvé qu'avec de faux `k3s` et `systemctl`, jamais contre
un vrai cluster.
