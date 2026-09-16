# Kubernetes/Installation

Outils et composants de l'écosystème Kubernetes. Sur K3s, `kubectl`, Traefik et
metrics-server sont posés par la distribution : les scripts de ce dossier
**vérifient** ce qui est déjà là, sans rien installer (décision 48).

## Prérequis

- `kubectl` dans le `PATH` (K3s le pose : [Linux/K3s/install-k3s.sh](../../Linux/K3s/install-k3s.sh)) et `timeout` ;
- un kubeconfig résolu par `kubectl` lui-même : `KUBECONFIG`, sinon `~/.kube/config` ;
- root non requis.

Sur un nœud K3s, le kubeconfig du cluster est `/etc/rancher/k3s/k3s.yaml`, en 0600
et propriété de root. Le compte d'administration le copie une fois, à son nom :

```bash
install -d -m 0700 ~/.kube && sudo install -o "$(id -u)" -g "$(id -g)" -m 0600 /etc/rancher/k3s/k3s.yaml ~/.kube/config
```

Ce fichier vise `127.0.0.1` : il ne vaut que sur le nœud. Depuis un poste distant, y
remplacer l'adresse par celle du serveur.

## Scripts

| Script | Rôle | Privilèges | Modifie le système |
|---|---|---|---|
| `install-kubectl.sh` | vérification seule, rubriques dans l'ordre : présence de `kubectl` (absent : renvoi vers `Linux/K3s/install-k3s.sh`) ; architecture de la machine (hors amd64 et arm64 : `[WARN]`) ; version du client (`kubectl version --client -o json`) ; kubeconfig, dont il vérifie seulement qu'il existe et se lit, sans jamais l'ouvrir. Avec `KUBECONFIG` (plusieurs chemins admis, le premier lisible suffit), un chemin absent ou illisible est nommé, valeur entière citée. Sans `KUBECONFIG` ni `~/.kube/config`, le script affiche la commande de copie ci-dessus. Suivent l'accès au cluster (`kubectl get nodes`, aucun nœud : échec, A78) et les versions client et serveur ; au-delà d'une version mineure d'écart, `[WARN]` sans changer le code, et une version hors forme `vX.Y.Z` (suffixes `+…` et `-…` retirés) donne un `[WARN]` « écart non vérifié ». Causes distinguées : délai dépassé (124), droits insuffisants (`Forbidden`), kubeconfig invalide ou périmé (`Unauthorized`, `x509`, `error loading config file`), apiserver injoignable ; la sortie d'erreur de `kubectl` n'est affichée qu'en cas d'échec. Chaque appel est borné par `--request-timeout` (5 s) et `timeout` (7 s). Aucun contenu de kubeconfig ni certificat affiché ; rien installé, copié ni écrit hors journal et un dossier temporaire effacé à la sortie. Codes : 0 `kubectl` présent et cluster joignable, avertissements compris ; 1 `kubectl` ou `timeout` absent, kubeconfig absent, illisible ou invalide, apiserver injoignable, droits insuffisants, délai dépassé ; 2 option inconnue | utilisateur | non |

## Utilisation

```bash
./Kubernetes/Installation/install-kubectl.sh          # kubectl, architecture, kubeconfig, accès, versions
KUBECONFIG=~/.kube/autre ./Kubernetes/Installation/install-kubectl.sh
./Kubernetes/Installation/install-kubectl.sh --help   # rubriques et codes de retour
```

## Risques

Aucun : lecture seule. La sortie liste les nœuds et les versions du cluster, à ne pas
publier telle quelle. Un refus `Forbidden` sur `kubectl get nodes` rend 1 même si
l'apiserver répond : un compte aux droits limités à un namespace échoue donc (A100).

## Systèmes supportés

Tout système où `kubectl` tourne ; validé en conteneur Debian avec un faux `kubectl`,
jamais contre un vrai cluster (A98).
