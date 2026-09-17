# Kubernetes/Configuration

Ressources de configuration posées dans le cluster par `kubectl` : elles
survivraient au remplacement de K3s par un cluster managé. Aucun script n'exige
root ; `kubectl` résout seul son kubeconfig (décision 48).

## Prérequis

- `kubectl` et `timeout` dans le `PATH` ; kubeconfig résolu par `kubectl` (`KUBECONFIG`, sinon `~/.kube/config`), voir [Installation/](../Installation/README.md) ;
- `configure-namespaces.sh` : `SRV_K8S_NAMESPACES` dans `config/server.env`, droit de lister et de créer des namespaces ;
- `configure-ingress.sh` : Traefik installé (CRD `middlewares.traefik.io`, vérifiable par `install-ingress.sh`), droit de lire les CRD à l'échelle du cluster et d'écrire des Middlewares dans le namespace visé ;
- `configure-tls.sh` : cert-manager installé (CRD `clusterissuers.cert-manager.io`, webhook prêt, voir `install-cert-manager.sh`), `SRV_K8S_ACME_EMAIL` dans `config/server.env`, le pod cert-manager capable de joindre Let's Encrypt en HTTPS sortant, droit de lire les CRD et d'écrire des ClusterIssuers ;
- `configure-storage.sh` : la classe cible présente dans le cluster (`SRV_K8S_STORAGE_CLASS` dans `config/server.env`, facultative, `local-path` à défaut), droit de lister et d'annoter les StorageClass.

## Scripts

| Script | Rôle | Privilèges | Modifie le système |
|---|---|---|---|
| `configure-namespaces.sh` | crée les namespaces communs listés dans `SRV_K8S_NAMESPACES` (noms séparés par des virgules), label `app.kubernetes.io/managed-by=mgnetworking`, un manifeste par namespace absent envoyé à `kubectl apply -f -`. Liste jugée entière avant tout appel : absente, vide, virgule en tête, en trop ou doublée, blanc ou retour à la ligne, nom hors DNS-1123 ou de plus de 63 caractères, doublon, namespace réservé (`default`, tout préfixe `kube-`) : 2. Puis `kubectl get namespaces -o name` : les présents ne sont ni modifiés ni réappliqués ; tous présents, 0 et « aucun changement ». `--dry-run` : namespaces à créer, jamais d'apply. Confirmation : `--yes`, réponse sous terminal, ou `ASSUME_YES` hérité (script non destructif, décision 45) ; sans terminal ni `--yes`, 1. Le premier apply refusé arrête la boucle : bilan créés, échoué, non tentés, 1, sans `[SUCCESS]`. Rien n'est jamais supprimé. Causes distinguées : délai dépassé (124, sur le get ou sur l'apply, namespace nommé), droits insuffisants, kubeconfig invalide, apiserver injoignable, sinon refus du cluster. Appels bornés par `--request-timeout` (10 s) et `timeout` (12 s). Codes : 0 liste présente ou créée, ou `--dry-run` ; 1 échec nommé ou confirmation refusée ; 2 option inconnue, liste absente ou mal formée | utilisateur (droits sur les namespaces) | oui : namespaces de la liste absents du cluster |
| `configure-ingress.sh` | pose deux Middlewares Traefik réutilisables (`apiVersion: traefik.io/v1alpha1`), label `app.kubernetes.io/managed-by=mgnetworking`, dans le namespace `--namespace` (défaut `default`) : `redirect-https` (`redirectScheme`, `scheme: https`, `permanent: true`) et `security-headers` (`headers` : `stsSeconds: 3600`, `stsIncludeSubdomains: false`, `stsPreload: false`, `contentTypeNosniff`, `frameDeny` et `browserXssFilter` à true, `referrerPolicy: strict-origin-when-cross-origin`). Namespace validé DNS-1123 avant tout appel ; puis CRD et namespace lus ; `kubectl diff -f -` juge : 0, rien appliqué ; 1, différence affichée, confirmation, `kubectl apply -f -`, relecture par le label (exactement deux). `--dry-run` : différence seule, jamais d'apply. Confirmation : `--yes` ou réponse sous terminal ; un `ASSUME_YES` hérité ne confirme pas (décision 45) ; sans terminal ni `--yes`, 1. Rien n'est jamais supprimé (ni `delete` ni `--prune`). Causes distinguées : délai dépassé (124), droits insuffisants, kubeconfig invalide, ressource inconnue de l'API, CRD Middleware absente ou non servie (`no matches for kind`), apiserver injoignable (erreurs réseau seules), sinon refus du cluster avec son message (validation, webhook). Chaque appel borné par `--request-timeout` (5 s) et `timeout` (7 s). Codes : 0 à l'état voulu, appliqué ou déjà là, ou `--dry-run` ; 1 kubectl absent, CRD ou namespace absent, échec d'appel, confirmation refusée, relecture incomplète ; 2 option inconnue, `--namespace` sans valeur ou mal formé | utilisateur (droits sur les Middlewares du namespace) | oui : deux Middlewares |
| `configure-tls.sh` | pose deux ClusterIssuers (`cert-manager.io/v1`, ressources de cluster), label `app.kubernetes.io/managed-by=mgnetworking` : `letsencrypt-staging` (`https://acme-staging-v02.api.letsencrypt.org/directory`) et `letsencrypt-production` (`https://acme-v02.api.letsencrypt.org/directory`), e-mail `SRV_K8S_ACME_EMAIL` entre guillemets, clé de compte `letsencrypt-<nom>-account-key`, solveur HTTP-01 `ingressClassName: traefik`. E-mail absent ou hors de la forme `local@domaine.tld` : 2 avant tout appel (garde contre l'injection YAML). Puis CRD lue ; `kubectl diff -f -` juge : 0, rien appliqué ; 1, différence, confirmation, `kubectl apply -f -`, relecture par le label (exactement deux), puis `kubectl wait --for=condition=Ready` de chaque issuer, 120 s par ClusterIssuer. `--dry-run` : différence seule, ni apply ni wait. Confirmation comme `configure-ingress.sh` (décision 45). Aucun certificat demandé, rien supprimé, Secret de clé jamais lu. Causes distinguées : délai dépassé (124), webhook cert-manager non prêt (`failed calling webhook`), droits, kubeconfig, CRD absente, ressource inconnue, apiserver injoignable, issuer non prêt après le délai (compte ACME non enregistré), sinon refus du cluster. Appels bornés par `--request-timeout` (10 s) et `timeout` (12 s), l'attente par 120 s et 122 s. Codes : 0 à l'état voulu ou `--dry-run` ; 1 échec nommé ci-dessus ou confirmation refusée ; 2 option inconnue, e-mail absent ou mal formé | utilisateur (droits sur les ClusterIssuers) | oui : deux ClusterIssuers, et deux comptes ACME chez Let's Encrypt créés par cert-manager |
| `configure-storage.sh` | laisse une seule StorageClass par défaut : la cible, `SRV_K8S_STORAGE_CLASS` ou `local-path`. Nom validé en sous-domaine RFC 1123 (253 caractères au plus) avant tout appel, sinon 2. Un seul relevé `kubectl get storageclass -o jsonpath` lit les deux clés, GA `storageclass.kubernetes.io/is-default-class` et bêta `storageclass.beta.kubernetes.io/is-default-class` : une classe est par défaut si l'une vaut `"true"`. Cible absente : 1, rien modifié. Déjà seule par défaut : 0, « aucun changement », aucun annotate. Sinon plan affiché — la cible reçoit la clé GA à `true` **en premier**, puis chaque clé à `true` d'une autre classe est posée à `false` par `kubectl annotate --overwrite` (jamais supprimée) : le cluster ne passe jamais par zéro classe par défaut. `--dry-run` : plan seul, aucun annotate. Confirmation : `--yes` ou réponse sous terminal ; un `ASSUME_YES` hérité ne confirme pas (décision 45) ; sans terminal ni `--yes`, 1. Le premier annotate refusé arrête la boucle : cause nommée, bilan appliquées et restantes, 1, sans `[SUCCESS]`. Relecture finale : même nombre de classes, exactement une par défaut, la cible, sinon 1. Aucune StorageClass créée, supprimée ni réappliquée. Causes distinguées : délai dépassé (124), droits insuffisants, kubeconfig invalide, ressource absente, apiserver injoignable, sinon refus du cluster. Appels bornés par `--request-timeout` (10 s) et `timeout` (12 s). Codes : 0 cible seule par défaut, déjà ou après annotation, ou `--dry-run` ; 1 échec nommé, cible absente, confirmation refusée, relecture en écart ; 2 option inconnue ou nom mal formé | utilisateur (droits sur les StorageClass) | oui : annotations par défaut des StorageClass |

## Émettre les certificats

`configure-tls.sh` ne demande **aucun** certificat : il n'appelle jamais Let's
Encrypt lui-même. Mais dès que les ClusterIssuers existent, cert-manager enregistre,
depuis son pod, **un compte ACME staging et un compte production** (condition Ready,
raison `ACMEAccountRegistered`) : le cluster doit joindre Let's Encrypt en HTTPS.
Chaque site demande ensuite son certificat dans son propre Ingress, en commençant
par `letsencrypt-staging` : ses limites de débit sont larges, et un échec HTTP-01
n'y consomme pas le quota de production. Passer à `letsencrypt-production` une fois
le certificat de test émis. Let's Encrypt n'envoie plus d'e-mails d'expiration
depuis le 4 juin 2025 : la surveillance des échéances revient au cluster.

## Activer les Middlewares sur un site

Chaque Ingress les active par une annotation, au format `<namespace>-<nom>@kubernetescrd`,
plusieurs séparés par des virgules :

```yaml
metadata:
  annotations:
    traefik.ingress.kubernetes.io/router.middlewares: default-redirect-https@kubernetescrd,default-security-headers@kubernetescrd
```

**Non vérifié** : la documentation de Traefik ne décrit `allowCrossNamespace`
(provider kubernetesCRD, défaut `false`) que pour les IngressRoutes ; elle ne dit
pas si l'annotation d'un Ingress peut viser un Middleware d'un autre namespace, ni
ce que K3s configure. Si la référence est refusée, poser les Middlewares dans le
namespace du site : `--namespace <ns-du-site>`.

## Utilisation

```bash
./Kubernetes/Configuration/configure-namespaces.sh --dry-run         # namespaces à créer, rien appliqué
./Kubernetes/Configuration/configure-namespaces.sh --yes             # crée les absents de SRV_K8S_NAMESPACES
./Kubernetes/Configuration/configure-ingress.sh --dry-run            # différence avec le cluster, rien appliqué
./Kubernetes/Configuration/configure-ingress.sh                      # différence, confirmation, apply, relecture
./Kubernetes/Configuration/configure-ingress.sh --namespace site --yes
./Kubernetes/Configuration/configure-tls.sh --dry-run                # ClusterIssuers : différence, rien appliqué
./Kubernetes/Configuration/configure-tls.sh                          # différence, confirmation, apply, attente Ready
./Kubernetes/Configuration/configure-storage.sh --dry-run            # annotations qui changeraient, rien annoté
./Kubernetes/Configuration/configure-storage.sh --yes                # cible seule StorageClass par défaut
```

## Risques

`configure-namespaces.sh` — n'ajoute que des namespaces : en retirer un de la liste
ne le supprime pas du cluster. Un échec en cours de liste laisse créés ceux qui
précèdent ; relancer reprend là où il s'est arrêté. Version corrigée non relue et
jamais lancée contre un vrai cluster (A116) ; longueur du fichier de cas (A117).

`configure-ingress.sh` — un Middleware activé s'applique à tout le trafic du site.
HSTS est volontairement court (1 h) : un `max-age` long, mal posé, rend le site
injoignable en HTTP pour toute sa durée ; l'allonger se décide site par site, une
fois HTTPS éprouvé. Un Middleware existant de même nom est aligné sur le manifeste.
La lecture de la CRD exige un droit à l'échelle du cluster : un compte limité au
namespace est refusé (A113). Jamais lancé contre un vrai cluster (A111).

`configure-tls.sh` — dès la première exécution, cert-manager crée chez Let's
Encrypt deux comptes ACME liés à `SRV_K8S_ACME_EMAIL`. Un ClusterIssuer existant de
même nom est aligné sur le manifeste. Sans réseau sortant, Ready n'arrive pas : 1
après 120 s par issuer, les issuers restant posés. Version corrigée non relue et
jamais lancée contre un vrai cluster (A114) ; longueurs (A115).

`configure-storage.sh` — Kubernetes tient une classe pour « par défaut » si la
clé GA **ou** la clé bêta vaut `"true"` ; s'il en reste plusieurs, la plus
récemment créée l'emporte (puis l'ordre alphabétique), avec un simple avertissement
journalisé (`pkg/volume/util/storageclass.go`) : un PVC sans
`storageClassName` peut atterrir ailleurs qu'attendu. K3s réapplique ses manifestes
intégrés au démarrage, dont `local-path` et sa marque par défaut : ce que le script
retire à `local-path` peut revenir au redémarrage de K3s (non constaté). Le script
n'y remédie pas ; relancé, il le signale et le corrige. Un annotate refusé en cours
de plan laisse la cible marquée et une partie des autres encore par défaut : relancer.
Version corrigée non relue et jamais lancée contre un vrai cluster (A118) ;
longueurs (A119).

## Systèmes supportés

Tout cluster Kubernetes (StorageClass `storage.k8s.io/v1` pour `configure-storage.sh`) servant Traefik v3 (groupe `traefik.io`) et, pour
`configure-tls.sh`, cert-manager (`cert-manager.io/v1`) ; testé avec un
faux `kubectl` en conteneur `debian` seulement.
