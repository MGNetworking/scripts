# Kubernetes/Configuration

Ressources de configuration posées dans le cluster par `kubectl` : elles
survivraient au remplacement de K3s par un cluster managé. Aucun script n'exige
root ; `kubectl` résout seul son kubeconfig (décision 48).

## Prérequis

- `kubectl` et `timeout` dans le `PATH` ; kubeconfig résolu par `kubectl` (`KUBECONFIG`, sinon `~/.kube/config`), voir [Installation/](../Installation/README.md) ;
- `configure-ingress.sh` : Traefik installé (CRD `middlewares.traefik.io`, vérifiable par `install-ingress.sh`), droit de lire les CRD à l'échelle du cluster et d'écrire des Middlewares dans le namespace visé.

## Scripts

| Script | Rôle | Privilèges | Modifie le système |
|---|---|---|---|
| `configure-ingress.sh` | pose deux Middlewares Traefik réutilisables (`apiVersion: traefik.io/v1alpha1`), label `app.kubernetes.io/managed-by=mgnetworking`, dans le namespace `--namespace` (défaut `default`) : `redirect-https` (`redirectScheme`, `scheme: https`, `permanent: true`) et `security-headers` (`headers` : `stsSeconds: 3600`, `stsIncludeSubdomains: false`, `stsPreload: false`, `contentTypeNosniff`, `frameDeny` et `browserXssFilter` à true, `referrerPolicy: strict-origin-when-cross-origin`). Namespace validé DNS-1123 avant tout appel ; puis CRD et namespace lus ; `kubectl diff -f -` juge : 0, rien appliqué ; 1, différence affichée, confirmation, `kubectl apply -f -`, relecture par le label (exactement deux). `--dry-run` : différence seule, jamais d'apply. Confirmation : `--yes` ou réponse sous terminal ; un `ASSUME_YES` hérité ne confirme pas (décision 45) ; sans terminal ni `--yes`, 1. Rien n'est jamais supprimé (ni `delete` ni `--prune`). Causes distinguées : délai dépassé (124), droits insuffisants, kubeconfig invalide, ressource inconnue de l'API, CRD Middleware absente ou non servie (`no matches for kind`), apiserver injoignable (erreurs réseau seules), sinon refus du cluster avec son message (validation, webhook). Chaque appel borné par `--request-timeout` (5 s) et `timeout` (7 s). Codes : 0 à l'état voulu, appliqué ou déjà là, ou `--dry-run` ; 1 kubectl absent, CRD ou namespace absent, échec d'appel, confirmation refusée, relecture incomplète ; 2 option inconnue, `--namespace` sans valeur ou mal formé | utilisateur (droits sur les Middlewares du namespace) | oui : deux Middlewares |

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
./Kubernetes/Configuration/configure-ingress.sh --dry-run            # différence avec le cluster, rien appliqué
./Kubernetes/Configuration/configure-ingress.sh                      # différence, confirmation, apply, relecture
./Kubernetes/Configuration/configure-ingress.sh --namespace site --yes
```

## Risques

`configure-ingress.sh` — un Middleware activé s'applique à tout le trafic du site.
HSTS est volontairement court (1 h) : un `max-age` long, mal posé, rend le site
injoignable en HTTP pour toute sa durée ; l'allonger se décide site par site, une
fois HTTPS éprouvé. Un Middleware existant de même nom est aligné sur le manifeste.
La lecture de la CRD exige un droit à l'échelle du cluster : un compte limité au
namespace est refusé (A113). Jamais lancé contre un vrai cluster (A111).

## Systèmes supportés

Tout cluster Kubernetes servant Traefik v3 (groupe `traefik.io`) ; testé avec un
faux `kubectl` en conteneur `debian` seulement.
