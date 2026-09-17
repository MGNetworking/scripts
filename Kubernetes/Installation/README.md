# Kubernetes/Installation

Outils et composants de l'écosystème Kubernetes. Sur K3s, `kubectl`, Traefik et
metrics-server sont posés par la distribution : les scripts de ce dossier
**vérifient** ce qui est déjà là, sans rien installer (décision 48). Helm, absent de K3s, est
le seul installé, par le script officiel `get-helm-4`.

## Prérequis

- `kubectl` dans le `PATH` (K3s le pose : [Linux/K3s/install-k3s.sh](../../Linux/K3s/install-k3s.sh)) et `timeout` ;
- un kubeconfig résolu par `kubectl` lui-même : `KUBECONFIG`, sinon `~/.kube/config` ;
- root non requis ; `install-helm.sh` réclame `curl`, `openssl` et `bash`, et le `sudo` de `get-helm-4` demande le mot de passe d'un compte non root.

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
| `install-helm.sh` | installe Helm 4 par le script officiel `get-helm-4` (`https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-4`). Cibles de la décision 14, amd64 et arm64 seulement. Helm déjà présent : version affichée, rien téléchargé, 0 — jamais de mise à niveau. Version : la dernière publiée, ou `SRV_HELM_VERSION` de `config/server.env` (passée par `--version`), annoncée au résumé. Confirmation : `--yes`, ou réponse sous terminal ; un `ASSUME_YES` hérité ne confirme pas (décision 45) ; sans terminal ni `--yes`, 1. `--dry-run` : préflight et commande prévue, sans réseau. `get-helm-4` est téléchargé en HTTPS seul (`--proto '=https' --tlsv1.2`) dans un temporaire, exécuté par `bash` puis retiré, jamais par un tube ; les variables héritées `VERIFY_CHECKSUM`, `USE_SUDO`, `HELM_INSTALL_DIR`, `BINARY_NAME`, `DESIRED_VERSION`, `DEBUG` sont retirées et `VERIFY_CHECKSUM=true` posée : la sha256 de l'archive est toujours vérifiée. Destination `/usr/local/bin/helm`, par le `sudo` de `get-helm-4` sous un compte non root. Version relue par `helm version --short`, comparée à l'épingle au suffixe `+…` près. Codes : 0 installé et relu, ou déjà présent ; 1 système non supporté, `curl`, `openssl` ou `bash` absent, téléchargement ou `get-helm-4` en échec, version illisible ou différente de l'épingle ; 2 option inconnue | utilisateur, `sudo` de `get-helm-4` | oui : `/usr/local/bin/helm` |

## Utilisation

```bash
./Kubernetes/Installation/install-kubectl.sh          # kubectl, architecture, kubeconfig, accès, versions
KUBECONFIG=~/.kube/autre ./Kubernetes/Installation/install-kubectl.sh
./Kubernetes/Installation/install-kubectl.sh --help   # rubriques et codes de retour
./Kubernetes/Installation/install-helm.sh --dry-run      # système, version prévue, commande, sans réseau
./Kubernetes/Installation/install-helm.sh               # résumé, confirmation, installation, version relue
```

## Risques

`install-kubectl.sh` — aucun : lecture seule. La sortie liste les nœuds et les versions du cluster, à ne pas
publier telle quelle. Un refus `Forbidden` sur `kubectl get nodes` rend 1 même si
l'apiserver répond : un compte aux droits limités à un namespace échoue donc (A100).

`install-helm.sh` — exécute avec `sudo` un script tiers pris sur la branche `main` de
helm/helm : la confiance repose sur HTTPS et sur la sha256 que `get-helm-4` vérifie
lui-même. `VERIFY_SIGNATURES` et `GPG_PUBRING` hérités restent transmis (A103). Avec
`--yes`, hors terminal et sans root, le `sudo` ne peut demander de mot de passe :
l'installation échoue (1). Un Helm présent n'est jamais mis à niveau.

## Systèmes supportés

Tout système où `kubectl` tourne ; validé en conteneur Debian avec un faux `kubectl`,
jamais contre un vrai cluster (A98). `install-helm.sh` : Debian 12 et 13, Ubuntu 22.04
et 24.04, amd64 et arm64 ; validé en conteneur avec un faux `get-helm-4`, jamais par un
vrai téléchargement (A101).
