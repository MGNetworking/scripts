# Cadrage — Kubernetes/

Ce document **engage** : besoin du dossier et contrat de chacun de ses scripts
([décision 49](../orchestration/decisions.md)). Le [README](README.md) et ceux des
sous-dossiers **expliquent** (usage, exemples, risques). Tout ce qui figure au contrat
est réputé utilisé : le modifier est une rupture. Un changement incompatible ne touche
jamais le script existant : nouveau script, l'ancien déprécié avec une date.

État initial : chaque contrat décrit le comportement **actuel** du script, lu dans son
code le 2026-09-17, et non un comportement souhaité.

## Besoin

Administrer un cluster Kubernetes par des commandes rejouables, depuis le compte
d'administration d'un serveur : vérifier les composants livrés par la distribution,
installer ceux qui manquent (Helm, cert-manager), poser la configuration commune du
cluster (namespaces, StorageClass par défaut, Middlewares Traefik, émetteurs Let's
Encrypt, accès au registry privé), puis l'exploiter et le diagnostiquer.

Contexte visé : un VPS Debian ou Ubuntu en K3s mono-nœud (décisions 14, 17 et 23),
Traefik comme Ingress Controller, `local-path` comme stockage. Les scripts parlent au
cluster par `kubectl` et `helm` seuls : ils survivraient au remplacement de K3s par un
cluster managé.

**Hors besoin** : installer, configurer ou désinstaller K3s lui-même (`Linux/K3s/`) ;
déployer une application ou demander un certificat (chaque site le fait dans son
Ingress) ; administrer un workload par `docker restart` ; supprimer des données
(Secrets, PVC, CRD, namespaces) ; plusieurs nœuds ou haute disponibilité.

## Ensembles

### Gestion de Kubernetes

- **Fonction globale** : une fois les scripts d'installation et de configuration
  appliqués, le cluster a un `kubectl` qui le joint, Traefik et metrics-server prêts,
  Helm et cert-manager installés, ses namespaces communs, une seule StorageClass par
  défaut, deux Middlewares Traefik, deux ClusterIssuers Let's Encrypt et le Secret du
  registry privé dans chaque namespace commun. Maintenance/ le relève, le diagnostique,
  le sauvegarde et en retire des objets nommés.
- **Scripts membres et ordre** :
  1. `Installation/` : `install-kubectl.sh`, `install-ingress.sh`,
     `install-metrics.sh`, `install-helm.sh`, puis `install-cert-manager.sh` (exige Helm) ;
  2. `Configuration/` : `configure-namespaces.sh`, `configure-storage.sh`,
     `configure-ingress.sh`, `configure-tls.sh` (exige cert-manager), puis
     `configure-registry.sh` (exige les namespaces) ;
  3. `Maintenance/`, à tout moment : `cluster-status.sh`, `pods-status.sh`,
     `events.sh`, `diagnostics.sh`, `resource-usage.sh`, `backup-resources.sh`, et
     `cleanup-resources.sh` après une sauvegarde.
- **Conventions communes** :
  - accès au cluster (décision 48) : aucun script n'exige root ; `kubectl` et `helm`
    résolvent seuls leur kubeconfig (`KUBECONFIG`, sinon `~/.kube/config`), qu'aucun
    script ne fixe, n'affiche ni ne copie ;
  - codes de retour : `0` succès ou état déjà voulu (avertissements compris), `1` échec
    nommé (outil absent, cluster injoignable, droits, délai dépassé, confirmation
    refusée), `2` option inconnue ; la valeur mal formée rend 2 ou 1 selon le script,
    que dit son contrat ;
  - les appels `kubectl` sont bornés par `--request-timeout` et par `timeout`, sauf
    l'attente `rollout status` de `install-cert-manager.sh` ; le code 124 n'est pas
    traité pareil partout : « délai dépassé » partout, sauf `cluster-status.sh`,
    `pods-status.sh`, `events.sh` et `diagnostics.sh`, qui le disent « apiserver
    injoignable » (A130) ;
  - scripts qui modifient le cluster ou installent sur la machine : résumé ou différence, puis
    confirmation ; `--dry-run` n'écrit rien ; `-y`/`--yes` confirme hors terminal, et
    seul `configure-namespaces.sh` accepte aussi un `ASSUME_YES` hérité ; rien n'est
    jamais supprimé, sauf par `cleanup-resources.sh` ;
  - réglages dans `config/server.env` : `SRV_K8S_NAMESPACES`, `SRV_K8S_STORAGE_CLASS`,
    `SRV_K8S_ACME_EMAIL`, `SRV_K8S_BACKUP_DIR`, plus `SRV_HELM_VERSION` et
    `SRV_CERT_MANAGER_VERSION` ; identifiants du registry dans `config/registry.env` ;
  - **hors contrat** : `DELAI_TEST` et `ATTENTE_TEST`, lues seulement si `/.dockerenv`
    existe (tests en conteneur), le libellé exact des messages et la mise en page des
    rubriques.

## Scripts individuels

Aucun dans `Kubernetes/`.

## Contrats

### install-kubectl.sh — ensemble « Gestion de Kubernetes »

- Besoin : prouver que `kubectl` est là et joint le cluster.
- Fait : constate dans l'ordre `kubectl`, architecture (hors amd64 et arm64 : `[WARN]`),
  version du client, kubeconfig lisible (sans l'ouvrir ; absent : affiche la copie de
  `k3s.yaml`), `kubectl get nodes` (aucun nœud : échec), versions client et serveur
  (plus d'une version mineure d'écart : `[WARN]`). Ne fait pas : installer `kubectl`,
  copier ou afficher un kubeconfig.
- Options et défauts : `--help`.
- Codes de retour : 0 `kubectl` présent et cluster joignable ; 1 `kubectl` ou `timeout`
  absent, kubeconfig absent, illisible ou invalide, apiserver injoignable, droits
  insuffisants, délai dépassé, aucun nœud rendu ; 2 option inconnue.
- Modifie sur la machine ou le cluster : rien (journal seul).
- Lit : `KUBECONFIG`, `~/.kube/config` (existence et droit de lecture).
- État : actif.

### install-ingress.sh — ensemble « Gestion de Kubernetes »

- Besoin : prouver que l'Ingress Controller Traefik de K3s est prêt et seul.
- Fait : IngressClass `traefik` (absente : échec) et classe par défaut ; déploiement
  `traefik` de `kube-system` (absent ou répliques prêtes inférieures aux désirées :
  échec) ; Services LoadBalancer étrangers sur 80/443 et écoutes `ss` : `[WARN]`. Ne
  fait pas : installer, arrêter un occupant, reconfigurer Traefik.
- Options et défauts : `--help`.
- Codes de retour : 0 Traefik prêt, avertissements compris ; 1 `kubectl`, `timeout` ou
  `ss` absent, IngressClass ou déploiement absent ou non prêt, appel en échec ou délai
  dépassé ; 2 option inconnue.
- Modifie sur la machine ou le cluster : rien.
- Lit : IngressClasses, déploiement `kube-system/traefik`, Services, `ss -ltn` (`ss -ltnp` sous root).
- État : actif.

### install-metrics.sh — ensemble « Gestion de Kubernetes »

- Besoin : prouver que metrics-server de K3s sert des métriques.
- Fait : déploiement `kube-system/metrics-server` (aucune réplique disponible : échec),
  APIService `v1beta1.metrics.k8s.io` (non `True` : échec, raison affichée), relevé
  `kubectl top nodes` (refusé ou vide : échec). Ne fait pas : installer, attendre le
  démarrage, reconfigurer.
- Options et défauts : `--help`.
- Codes de retour : 0 déploiement disponible, APIService Available, relevé rendu ; 1
  `kubectl` ou `timeout` absent, déploiement ou APIService absent ou indisponible,
  relevé refusé ou vide, appel en échec ou délai dépassé ; 2 option inconnue.
- Modifie sur la machine ou le cluster : rien.
- Lit : déploiement, APIService, métriques des nœuds.
- État : actif.

### install-helm.sh — ensemble « Gestion de Kubernetes »

- Besoin : installer Helm 4, absent de K3s.
- Fait : Debian 12/13 ou Ubuntu 22.04/24.04, amd64 ou arm64, sinon refus ; Helm présent :
  version affichée, rien téléchargé ; sinon résumé, confirmation, `get-helm-4` officiel
  téléchargé en HTTPS dans un temporaire puis exécuté par `bash`, sha256 toujours vérifiée,
  version relue et comparée à l'épingle. Ne fait pas : mettre à niveau un Helm présent,
  ajouter un dépôt de charts ou un plugin.
- Options et défauts : `--dry-run` (préflight et commande, sans réseau) ; `-y`, `--yes`
  (seuls à confirmer hors terminal ; `ASSUME_YES` hérité ignoré) ; `--help`.
- Codes de retour : 0 installé et relu, ou déjà présent ; 1 système non supporté, `curl`,
  `openssl` ou `bash` absent, confirmation refusée, téléchargement ou `get-helm-4` en
  échec, version illisible ou différente de l'épingle ; 2 option inconnue.
- Modifie sur la machine ou le cluster : `/usr/local/bin/helm`, par le `sudo` de
  `get-helm-4` ; journal du script.
- Lit : `SRV_HELM_VERSION` (absente : dernière version publiée).
- État : actif.

### install-cert-manager.sh — ensemble « Gestion de Kubernetes »

- Besoin : installer ou mettre à jour cert-manager, prérequis de `configure-tls.sh`.
- Fait : chart OCI `oci://quay.io/jetstack/charts/cert-manager`, namespace
  `cert-manager` créé au besoin, CRD posées par le chart ; même version : rien refait ;
  version plus récente : résumé « installée → voulue » et confirmation ; puis version
  relue, trois déploiements attendus 180 s, CRD relues. Refuse sans rien toucher : version
  voulue inférieure, release non `deployed`, CRD `cert-manager.io` sans release. Ne fait
  pas : revenir en arrière, désinstaller, supprimer une CRD.
- Options et défauts : `--version vX.Y.Z` (obligatoire, sinon `SRV_CERT_MANAGER_VERSION`) ;
  `--dry-run` (version et commande, sans appeler `helm` ni `kubectl`, qui doivent pourtant être présents) ; `-y`, `--yes` (seuls à
  confirmer hors terminal ; `ASSUME_YES` hérité ignoré) ; `--help`.
- Codes de retour : 0 à la version voulue, installée ou déjà là ; 1 `helm`, `kubectl` ou
  `timeout` absent, cluster injoignable, version absente, invalide ou inférieure, release
  non `deployed`, CRD orphelines, confirmation refusée, échec ou délai de `helm`,
  déploiement non prêt, CRD manquante ; 2 option inconnue.
- Modifie sur la machine ou le cluster : release Helm, namespace, CRD et déploiements
  cert-manager ; journal du script.
- Lit : `SRV_CERT_MANAGER_VERSION`, `TIMEOUT_HELM` (défaut 330 s, borne externe du
  `helm upgrade`), releases Helm du namespace, CRD `cert-manager.io`.
- État : actif.

### configure-namespaces.sh — ensemble « Gestion de Kubernetes »

- Besoin : créer les namespaces communs déclarés pour la machine.
- Fait : liste jugée entière avant tout appel (DNS-1123, 63 caractères, doublons,
  `default` et `kube-*` refusés) ; namespaces absents créés par `kubectl apply -f -`, label
  `app.kubernetes.io/managed-by=mgnetworking` ; présents ni modifiés ni réappliqués ; le
  premier échec arrête la boucle et donne un bilan. Ne fait pas : supprimer un namespace
  retiré de la liste.
- Options et défauts : `--dry-run` (namespaces à créer) ; `-y`, `--yes` ; un
  `ASSUME_YES` hérité confirme aussi (script non destructif, décision 45) ; `--help`.
- Codes de retour : 0 liste présente ou créée, ou `--dry-run` ; 1 `kubectl` ou `timeout` absent, échec
  nommé ou confirmation refusée ; 2 option inconnue, liste absente ou mal formée.
- Modifie sur la machine ou le cluster : namespaces de la liste absents du cluster.
- Lit : `SRV_K8S_NAMESPACES` (noms séparés par des virgules), namespaces du cluster.
- État : actif.

### configure-storage.sh — ensemble « Gestion de Kubernetes »

- Besoin : une seule StorageClass par défaut.
- Fait : cible validée (sous-domaine RFC 1123, 253 caractères) ; absente du cluster :
  échec ; déjà seule par défaut : rien ; sinon la cible reçoit la clé GA à `true` en
  premier, puis toute autre classe marquée (clé GA ou bêta) est ramenée à `false` par
  `kubectl annotate --overwrite` ; relecture finale. Ne fait pas : créer, supprimer ou
  réappliquer une StorageClass, retirer une annotation.
- Options et défauts : `--dry-run` (plan seul) ; `-y`, `--yes` (seuls à confirmer hors
  terminal ; `ASSUME_YES` hérité ignoré) ; `--help`.
- Codes de retour : 0 cible seule par défaut, déjà ou après annotation, ou `--dry-run` ;
  1 `kubectl` ou `timeout` absent, échec nommé, cible absente, confirmation refusée, relecture en écart ; 2 option
  inconnue ou nom mal formé.
- Modifie sur la machine ou le cluster : annotations « par défaut » des StorageClass.
- Lit : `SRV_K8S_STORAGE_CLASS` (défaut `local-path`), StorageClasses du cluster.
- État : actif.

### configure-ingress.sh — ensemble « Gestion de Kubernetes »

- Besoin : Middlewares Traefik réutilisables par chaque site.
- Fait : pose `redirect-https` (redirection permanente vers HTTPS) et `security-headers`
  (HSTS de 3600 s, nosniff, frameDeny, browserXssFilter, referrerPolicy
  `strict-origin-when-cross-origin`), `traefik.io/v1alpha1`, label
  `app.kubernetes.io/managed-by=mgnetworking` ; `kubectl diff` juge, `kubectl apply`
  après confirmation, relecture des deux. Ne fait pas : activer un Middleware sur un
  Ingress, supprimer un objet, même retiré du manifeste.
- Options et défauts : `--namespace <ns>` (défaut `default`) ; `--dry-run` (différence
  seule) ; `-y`, `--yes` (seuls à confirmer hors terminal) ; `--help`.
- Codes de retour : 0 à l'état voulu, appliqué ou déjà là, ou `--dry-run` ; 1 `kubectl`
  ou `timeout` absent, CRD ou namespace absent, échec d'appel, confirmation refusée, relecture
  incomplète ; 2 option inconnue, `--namespace` sans valeur ou mal formé.
- Modifie sur la machine ou le cluster : deux Middlewares du namespace.
- Lit : CRD Middleware, namespace cible, Middlewares existants.
- État : actif.

### configure-tls.sh — ensemble « Gestion de Kubernetes »

- Besoin : émetteurs Let's Encrypt prêts pour les certificats des sites.
- Fait : ClusterIssuers `letsencrypt-staging` et `letsencrypt-production`, HTTP-01 sur
  l'IngressClass `traefik`, label `app.kubernetes.io/managed-by=mgnetworking` ;
  `kubectl diff` juge, `kubectl apply` après confirmation, relecture, attente Ready de
  120 s par issuer. Ne fait pas : demander un certificat, lire le Secret de clé ACME,
  supprimer.
- Options et défauts : `--dry-run` (différence seule, ni apply ni attente) ; `-y`,
  `--yes` (seuls à confirmer hors terminal) ; `--help`.
- Codes de retour : 0 à l'état voulu ou `--dry-run` ; 1 `kubectl` ou `timeout` absent, CRD absente,
  webhook cert-manager non prêt, échec d'appel, issuer non Ready après le délai,
  confirmation refusée ; 2 option inconnue, e-mail absent ou mal formé.
- Modifie sur la machine ou le cluster : deux ClusterIssuers ; cert-manager crée en
  conséquence deux comptes ACME chez Let's Encrypt.
- Lit : `SRV_K8S_ACME_EMAIL` (forme `local@domaine.tld`), CRD ClusterIssuer.
- État : actif.

### configure-registry.sh — ensemble « Gestion de Kubernetes »

- Besoin : permettre aux pods de tirer les images du registry privé.
- Fait : fichier de contexte exigé en 600 et à l'utilisateur courant **avant** d'être lu ;
  Secret `registry-credentials` de type `kubernetes.io/dockerconfigjson` posé par
  `kubectl apply -f -` (entrée standard) dans chaque namespace de la liste ; annotation
  `mgnetworking/empreinte` (sha256) pour juger l'idempotence sans relire le Secret ;
  namespace absent : échec, rien appliqué. Ne fait pas : afficher, journaliser ou passer
  en argument un identifiant ; poser `imagePullSecrets` ; supprimer.
- Options et défauts : `--config <nom>` (défaut `registry`) ; `--dry-run` (Secrets à
  créer ou à mettre à jour, sans contenu) ; `-y`, `--yes` (seuls à confirmer hors
  terminal) ; `--help`.
- Codes de retour : 0 Secrets à jour ou `--dry-run` ; 1 fichier absent, droits ou
  propriétaire refusés, namespace absent, `kubectl`, `timeout`, `base64` ou `sha256sum` absent, échec nommé, confirmation
  refusée ; 2 option inconnue, `--config` sans valeur, `REGISTRY_SERVEUR`, `REGISTRY_IDENTIFIANT` ou
  `REGISTRY_JETON` absent ou mal formé, liste des namespaces absente ou mal formée.
- Modifie sur la machine ou le cluster : un Secret par namespace de la liste.
- Lit : `config/<nom>.env`, `SRV_K8S_NAMESPACES`, annotations des Secrets existants.
- État : actif.

### cluster-status.sh — ensemble « Gestion de Kubernetes »

- Besoin : un relevé d'ensemble du cluster.
- Fait : nœuds (`-o wide`, sonde : échec arrête), versions, namespaces, pods, deployments
  et services de tous les namespaces ; rubrique suivante en échec : erreur affichée, relevé
  poursuivi. Ne fait pas : juger la santé, afficher un kubeconfig ou un Secret.
- Options et défauts : `--help`.
- Codes de retour : 0 apiserver joignable, quel que soit l'état des pods ; 1 `kubectl`
  absent ou apiserver injoignable ; 2 option inconnue.
- Modifie sur la machine ou le cluster : rien.
- Lit : nœuds, versions, namespaces, pods, deployments, services.
- Prouvé par : `tests/integration/cluster-status.test.sh` — niveau simulé (faux
  « kubectl » en tête de PATH, sans cluster).
- État : actif.

### pods-status.sh — ensemble « Gestion de Kubernetes »

- Besoin : l'état des pods.
- Fait : `kubectl get pods -o wide`, tous les namespaces, ou un seul après vérification
  de son existence. Ne fait pas : juger la santé.
- Options et défauts : `--namespace <ns>` (défaut : tous) ; `--help`.
- Codes de retour : 0 liste affichée, vide comprise ; 1 `kubectl` ou `timeout` absent,
  apiserver injoignable, namespace inconnu ; 2 option inconnue, `--namespace` sans valeur
  ou commençant par « - ».
- Modifie sur la machine ou le cluster : rien.
- Lit : pods, namespace demandé.
- Prouvé par : `tests/integration/pods-status.test.sh` — niveau simulé (faux « kubectl »
  en tête de PATH, sans cluster).
- État : actif.

### events.sh — ensemble « Gestion de Kubernetes »

- Besoin : les événements du cluster, du plus ancien au plus récent.
- Fait : `kubectl get events`, tous les namespaces ou un seul vérifié d'abord, triés par
  `.metadata.creationTimestamp` ; liste vide annoncée, pas une panne. Ne fait pas : juger.
- Options et défauts : `--namespace <ns>` (défaut : tous) ; `--warnings` (type Warning
  seul, filtré par l'apiserver) ; `--help`.
- Codes de retour : 0 liste affichée, vide comprise ; 1 `kubectl` ou `timeout` absent,
  apiserver injoignable, droits insuffisants, namespace inconnu ; 2 option inconnue,
  `--namespace` sans valeur ou commençant par « - ».
- Modifie sur la machine ou le cluster : rien.
- Lit : événements, namespace demandé.
- Prouvé par : `tests/integration/events.test.sh` — niveau simulé (faux « kubectl » en
  tête de PATH, sans cluster).
- État : actif.

### diagnostics.sh — ensemble « Gestion de Kubernetes »

- Besoin : un verdict d'anomalies porté par le code de retour.
- Fait : nœuds non `Ready`, pods en état anormal (Pending, Failed, CrashLoopBackOff,
  ImagePullBackOff, OOMKilled…, `Init:` compris ; Completed et Succeeded exclus),
  Deployments, StatefulSets et DaemonSets aux répliques prêtes insuffisantes ; événements
  Warning affichés sans effet sur le code ; rubrique illisible comptée comme anomalie. Ne
  fait pas : corriger, `logs`, `describe`.
- Options et défauts : `--help`.
- Codes de retour : 0 aucune anomalie ; 1 au moins une anomalie, relevé impossible,
  `kubectl` ou `timeout` absent, droits insuffisants, apiserver injoignable ; 2 option
  inconnue.
- Modifie sur la machine ou le cluster : rien.
- Lit : nœuds, pods, Deployments, StatefulSets, DaemonSets, événements Warning.
- Prouvé par : `tests/integration/diagnostics.test.sh` — niveau simulé (faux « kubectl »
  en tête de PATH, sans cluster).
- État : actif.

### resource-usage.sh — ensemble « Gestion de Kubernetes »

- Besoin : CPU et mémoire des nœuds et des pods.
- Fait : sonde des nœuds ; `kubectl top nodes` puis `kubectl top pods` ; API metrics
  absente ou en panne : `[WARN]` et capacité/allocatable des nœuds par
  `kubectl describe nodes`, code 0 (décision 48). Ne fait pas : installer metrics-server.
- Options et défauts : `--namespace <ns>` (pods de ce namespace ; défaut : tous) ; `--help`.
- Codes de retour : 0 relevé affiché, métriques ou capacité à défaut ; 1 `kubectl` ou
  `timeout` absent, apiserver injoignable, droits insuffisants, namespace inconnu, délai
  dépassé, rubrique vide ; 2 option inconnue, `--namespace` sans valeur ou commençant
  par « - ».
- Modifie sur la machine ou le cluster : rien.
- Lit : nœuds, métriques, namespace demandé.
- Prouvé par : `tests/integration/resource-usage.test.sh` — niveau simulé (faux
  « kubectl » en tête de PATH, sans cluster).
- État : actif.

### backup-resources.sh — ensemble « Gestion de Kubernetes »

- Besoin : garder hors du cluster les manifests de sa configuration.
- Fait : exporte en YAML namespaces, storageclasses, et par namespace deployments,
  statefulsets, daemonsets, cronjobs, services, ingresses, configmaps,
  persistentvolumeclaims ; `status`, `uid`, `resourceVersion`, `managedFields` retirés ;
  un sous-dossier horodaté par exécution, dossiers 0700, fichiers 0600 ; destination
  refusée si elle est dans le dépôt. Ne fait pas : exporter les Secrets, écrire sur le
  cluster, écraser une sauvegarde.
- Options et défauts : `--output <dossier>` (défaut `SRV_K8S_BACKUP_DIR`, sinon
  `/var/backups/kubernetes`) ; `--dry-run` (destination, namespaces et types) ; `--help`.
- Codes de retour : 0 export terminé, chemin affiché ; 1 destination refusée ou non
  inscriptible, `kubectl`, `timeout` ou `realpath` absent, apiserver injoignable, droits
  insuffisants, délai dépassé, export incomplet ; 2 option inconnue, `--output` sans valeur.
- Modifie sur la machine ou le cluster : fichiers locaux sous la destination seulement.
- Lit : `SRV_K8S_BACKUP_DIR`, objets des types listés.
- Prouvé par : `tests/integration/backup-resources.test.sh` — niveau simulé (faux
  « kubectl » en tête de PATH, sans cluster).
- État : actif.

### cleanup-resources.sh — ensemble « Gestion de Kubernetes »

- Besoin : retirer du cluster des objets désignés un à un.
- Fait : cibles `-n <ns> <type>/<nom>`, types de la liste blanche (pods, jobs, cronjobs,
  deployments, replicasets, statefulsets, daemonsets, services, configmaps, ingresses,
  et leurs abréviations kubectl) ; chaque cible relue avant confirmation ; `kubectl delete
  --wait=false`, sans forcer ni raccourcir le délai de grâce ; un échec n'arrête pas les suivantes ; relecture finale.
  Ne fait pas : chercher des candidats, supprimer par label, motif, `--all` ou namespace
  entier ; accepter Secrets, PVC ou types à portée cluster ; toucher `kube-system`,
  `kube-public`, `kube-node-lease`.
- Options et défauts : `-n <ns>` (un par cible, aucun défaut) ; `--dry-run` (liste seule,
  sans `kubectl`) ; `-y`, `--yes` (seuls à confirmer hors terminal ; `ASSUME_YES` hérité
  ignoré) ; `--help`.
- Codes de retour : 0 chaque cible relue absente, ou `--dry-run` ; 1 cible inexistante ou
  protégée, `kubectl` ou `timeout` absent, apiserver injoignable, droits insuffisants,
  délai dépassé, confirmation refusée, cible restante ; 2 option inconnue, cible mal
  formée, type hors liste, nom ou namespace invalide, aucune cible.
- Modifie sur la machine ou le cluster : **supprime** les objets nommés.
- Lit : chaque objet nommé.
- Prouvé par : `tests/integration/cleanup-resources.test.sh` — niveau simulé (faux
  « kubectl » en tête de PATH, sans cluster).
- État : actif.

## Historique du cadrage

| Date | Changement | Nature (correction, ajout compatible, nouveau script, dépréciation) | Validé par user |
|---|---|---|---|
| 2026-09-17 | État initial : besoin, ensemble « Gestion de Kubernetes », contrats des 17 scripts tels qu'écrits (TASK-074) | état initial | oui, 2026-09-17 |
| 2026-09-18 | Ligne « Prouvé par » sur les contrats des 7 scripts de Maintenance/ (TASK-083) | ajout compatible | fiche TASK-083, décision 50 |
