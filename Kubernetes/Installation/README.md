# Kubernetes/Installation

Outils et composants de l'écosystème Kubernetes. Sur K3s, `kubectl`, Traefik et
metrics-server sont posés par la distribution : les scripts de ce dossier
**vérifient** ce qui est déjà là, sans rien installer (décision 48). Helm, absent de K3s, est
installé par le script officiel `get-helm-4` ; cert-manager, par son chart Helm officiel.

## Prérequis

- `kubectl` dans le `PATH` (K3s le pose : [Linux/K3s/install-k3s.sh](../../Linux/K3s/install-k3s.sh)) et `timeout` ; `install-ingress.sh` réclame aussi `ss` (paquet `iproute2`) ;
- un kubeconfig résolu par `kubectl` lui-même : `KUBECONFIG`, sinon `~/.kube/config` ;
- root non requis ; `install-helm.sh` réclame `curl`, `openssl` et `bash`, et le `sudo` de `get-helm-4` demande le mot de passe d'un compte non root ; `install-cert-manager.sh` réclame `helm` (`install-helm.sh`), `kubectl`, `timeout` et un accès au registre OCI `quay.io`.

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
| `install-ingress.sh` | vérification seule de l'Ingress Controller Traefik posé par K3s, rien installé ni arrêté. Rubriques : IngressClass (jsonpath : nom et annotation `ingressclass.kubernetes.io/is-default-class`) — `traefik` absente : 1 ; classes par défaut toutes listées ; autre IngressClass : `[WARN]` la nommant ; déploiement `traefik` de `kube-system` (custom-columns : image, `readyReplicas`, `replicas`) — absent, ou répliques prêtes inférieures aux désirées ou nulles : 1 ; image affichée ; Services LoadBalancer (jsonpath) autres que `kube-system/traefik` exposant 80 ou 443 : `[WARN]` nommant le Service et le port ; écoutes de la machine sur 80/443 par `ss -ltn` (`-ltnp` sous root, qui nomme le processus ; sans root, le port seul) : `[WARN]`. Sans écoute visible, le script dit que ce silence ne prouve pas que les ports sont libres (servicelb). Causes distinguées : délai dépassé (124), droits insuffisants (`Forbidden`), kubeconfig invalide ou périmé (`Unauthorized`, `x509`, `error loading config file`), ressource inconnue de l'API, apiserver injoignable. Chaque appel borné par `--request-timeout` (5 s) et `timeout` (7 s), `ss` compris. Codes : 0 Traefik prêt, avertissements et conflits de ports compris ; 1 `kubectl`, `timeout` ou `ss` absent, IngressClass ou déploiement absent, déploiement non prêt, appel en échec ou délai dépassé ; 2 option inconnue | utilisateur | non |
| `install-metrics.sh` | vérification seule de metrics-server posé par K3s, rien installé ni reconfiguré (décision 48). Rubriques : déploiement `metrics-server` de `kube-system` (custom-columns : image, `availableReplicas`, `replicas`) — absent, ou aucune réplique disponible : 1 ; image et répliques disponibles sur désirées affichées ; APIService `v1beta1.metrics.k8s.io` (jsonpath de la condition `Available` : statut, raison, message) — absente, ou non `True` : 1, raison et message affichés ; relevé `kubectl top nodes` affiché tel quel — refusé ou vide : 1. Un refus « Metrics API not available » est dit API non enregistrée ; « ServiceUnavailable » ou « metrics not available yet », `[WARN]` nommant pour cause probable le démarrage de metrics-server (environ une minute), sans attendre. Causes distinguées : délai dépassé (124), droits insuffisants (`Forbidden`), kubeconfig invalide ou périmé (`Unauthorized`, `x509`, `error loading config file`), ressource inconnue de l'API, apiserver injoignable (motifs réseau seulement : `connection refused`, `was refused`, `Unable to connect`, `no such host`, `i/o timeout`) ; toute autre erreur : « Échec de … », stderr de `kubectl` affiché. Chaque appel borné par `--request-timeout` (5 s) et `timeout` (7 s). Codes : 0 déploiement disponible, APIService Available, relevé rendu ; 1 `kubectl` ou `timeout` absent, déploiement ou APIService absent ou indisponible, relevé refusé ou vide, appel en échec ou délai dépassé ; 2 option inconnue | utilisateur | non |
| `install-helm.sh` | installe Helm 4 par le script officiel `get-helm-4` (`https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-4`). Cibles de la décision 14, amd64 et arm64 seulement. Helm déjà présent : version affichée, rien téléchargé, 0 — jamais de mise à niveau. Version : la dernière publiée, ou `SRV_HELM_VERSION` de `config/server.env` (passée par `--version`), annoncée au résumé. Confirmation : `--yes`, ou réponse sous terminal ; un `ASSUME_YES` hérité ne confirme pas (décision 45) ; sans terminal ni `--yes`, 1. `--dry-run` : préflight et commande prévue, sans réseau. `get-helm-4` est téléchargé en HTTPS seul (`--proto '=https' --tlsv1.2`) dans un temporaire, exécuté par `bash` puis retiré, jamais par un tube ; les variables héritées `VERIFY_CHECKSUM`, `USE_SUDO`, `HELM_INSTALL_DIR`, `BINARY_NAME`, `DESIRED_VERSION`, `DEBUG` sont retirées et `VERIFY_CHECKSUM=true` posée : la sha256 de l'archive est toujours vérifiée. Destination `/usr/local/bin/helm`, par le `sudo` de `get-helm-4` sous un compte non root. Version relue par `helm version --short`, comparée à l'épingle au suffixe `+…` près. Codes : 0 installé et relu, ou déjà présent ; 1 système non supporté, `curl`, `openssl` ou `bash` absent, téléchargement ou `get-helm-4` en échec, version illisible ou différente de l'épingle ; 2 option inconnue | utilisateur, `sudo` de `get-helm-4` | oui : `/usr/local/bin/helm` |
| `install-cert-manager.sh` | installe ou met à jour cert-manager par le chart OCI officiel jetstack `oci://quay.io/jetstack/charts/cert-manager` (sans `helm repo add`), dans le namespace `cert-manager` créé au besoin, CRD posées par le chart (`crds.enabled=true`). Version obligatoire, forme `vX.Y.Z` : `--version`, sinon `SRV_CERT_MANAGER_VERSION` de `config/server.env`. Release lue par `helm list -a -o json` (sans jq) : statut autre que `deployed` (`failed`, `pending-*`…) refusé sans rien toucher ; même version : rien refait, 0 ; version installée plus ancienne : résumé « installée → voulue », rappel de lire les notes de version, confirmation ; version voulue plus ancienne : refus (pas de retour arrière), comparaison numérique champ par champ ; CRD `cert-manager.io` sans release Helm : refus. Confirmation : `--yes`, ou réponse sous terminal ; un `ASSUME_YES` hérité ne confirme pas (décision 45). `--dry-run` : version et commande prévues, sans appel à helm ni kubectl. Commande : `helm upgrade --install … --set crds.enabled=true --timeout 5m`, sous une borne externe de 330 s (`TIMEOUT_HELM`, surchargeable, A107). Puis version relue, déploiements `cert-manager`, `cert-manager-cainjector`, `cert-manager-webhook` attendus 180 s chacun, CRD `certificates`, `issuers`, `clusterissuers` relues. `HELM_NAMESPACE`, `HELM_KUBECONTEXT`, `HELM_KUBETOKEN`, `HELM_KUBEAPISERVER`, `HELM_KUBEASUSER`, `HELM_KUBEASGROUPS`, `HELM_KUBECAFILE`, `HELM_KUBEINSECURE_SKIP_TLS_VERIFY` et `HELM_DRIVER` hérités sont retirés ; `KUBECONFIG` est respecté. Causes distinguées comme `install-kubectl.sh`. Codes : 0 à la version voulue, installée ou déjà là ; 1 helm, kubectl ou timeout absent, cluster injoignable, version absente, invalide ou inférieure, release non `deployed`, CRD orphelines, confirmation refusée, échec ou délai de helm, déploiement non prêt, CRD manquante ; 2 option inconnue | utilisateur (droits cluster-admin sur le cluster) | oui : release Helm, namespace, CRD et déploiements cert-manager |

## Utilisation

```bash
./Kubernetes/Installation/install-kubectl.sh          # kubectl, architecture, kubeconfig, accès, versions
KUBECONFIG=~/.kube/autre ./Kubernetes/Installation/install-kubectl.sh
./Kubernetes/Installation/install-kubectl.sh --help   # rubriques et codes de retour
./Kubernetes/Installation/install-ingress.sh          # IngressClass, déploiement traefik, occupants de 80/443
sudo KUBECONFIG=~/.kube/config ./Kubernetes/Installation/install-ingress.sh   # idem, ss nomme en plus le processus à l'écoute
./Kubernetes/Installation/install-metrics.sh          # déploiement metrics-server, APIService v1beta1.metrics.k8s.io, kubectl top nodes
./Kubernetes/Installation/install-helm.sh --dry-run      # système, version prévue, commande, sans réseau
./Kubernetes/Installation/install-helm.sh               # résumé, confirmation, installation, version relue
./Kubernetes/Installation/install-cert-manager.sh --version v1.21.2 --dry-run   # version et commande helm prévues
./Kubernetes/Installation/install-cert-manager.sh --version v1.21.2            # résumé, confirmation, installation ou mise à jour
```

## Risques

`install-kubectl.sh` — aucun : lecture seule. La sortie liste les nœuds et les versions du cluster, à ne pas
publier telle quelle. Un refus `Forbidden` sur `kubectl get nodes` rend 1 même si
l'apiserver répond : un compte aux droits limités à un namespace échoue donc (A100).

`install-ingress.sh` — aucun : lecture seule. `ss` ne voit que les sockets des processus
de la machine : avec servicelb (klipper-lb), les ports 80/443 de Traefik sont publiés
sans socket visible, si bien qu'une écoute signalée n'est pas la preuve que Traefik est
inaccessible, et un silence pas la preuve que les ports sont libres ; le signal fiable
est un Service LoadBalancer étranger. Le déploiement est jugé prêt seulement si toutes
ses répliques le sont, ce qui peut rendre 1 pendant une mise à jour progressive (A110).

`install-metrics.sh` — aucun : lecture seule. Juste après un démarrage de metrics-server, le script rend 1 tant que
l'API ne sert pas de métriques : le relancer environ une minute plus tard. Noms K3s (`metrics-server`,
`kube-system`, `v1beta1.metrics.k8s.io`) et délai de démarrage non constatés sur un vrai K3s (A125).

`install-helm.sh` — exécute avec `sudo` un script tiers pris sur la branche `main` de
helm/helm : la confiance repose sur HTTPS et sur la sha256 que `get-helm-4` vérifie
lui-même. `VERIFY_SIGNATURES` et `GPG_PUBRING` hérités restent transmis (A103). Avec
`--yes`, hors terminal et sans root, le `sudo` ne peut demander de mot de passe :
l'installation échoue (1). Un Helm présent n'est jamais mis à niveau.

`install-cert-manager.sh` — installe dans le cluster des CRD, des webhooks et des
droits étendus. Une mise à jour peut changer le comportement des Issuers et
Certificates : lire les notes de version avant de confirmer. Un `helm` interrompu
par son délai peut laisser la release en `pending-*` : le script le signale et refuse
ensuite d'y toucher ; examen manuel par `helm -n cert-manager history cert-manager`.
Rien n'est jamais désinstallé : supprimer les CRD effacerait tous les Issuers,
ClusterIssuers et Certificates.

## Systèmes supportés

Tout système où `kubectl` tourne ; validé en conteneur Debian avec un faux `kubectl`,
jamais contre un vrai cluster (A98). `install-ingress.sh` : idem, avec de faux `kubectl`,
`ss` et `timeout` ; noms K3s (`traefik`, `kube-system`) et comportement de servicelb
non constatés sur un vrai K3s (A108). `install-helm.sh` : Debian 12 et 13, Ubuntu 22.04
et 24.04, amd64 et arm64 ; validé en conteneur avec un faux `get-helm-4`, jamais par un
vrai téléchargement (A101). `install-cert-manager.sh` : tout système où `helm` et
`kubectl` tournent ; validé en conteneur avec de faux `helm` et `kubectl`, jamais
contre un vrai cluster ni le vrai chart (A104, A106). `install-metrics.sh` : idem, avec de faux `kubectl` et `timeout`, jamais contre un vrai cluster (A125).
