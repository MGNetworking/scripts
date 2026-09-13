# Docker

Installation, configuration, maintenance, nettoyage et diagnostic du **moteur
Docker** sur une machine Linux — Engine, client, `containerd`, plugins Compose
et Buildx.

`Docker/` s'arrête au moteur. Les workloads gérés par Kubernetes ne
s'administrent jamais d'ici : cela relève de `Kubernetes/`. Le domaine ne
connaît aucune application déployée — ni son nom, ni son fichier Compose.

## Arborescence

```text
Docker/
├── Installation/   poser le moteur, vérifier ce qu'on vient de poser
├── Configuration/  daemon.json, réseaux partagés entre projets
├── Maintenance/    mise à jour du moteur et des images
├── Cleanup/        récupération des ressources inutilisées
└── Diagnostics/    LECTURE SEULE, sans exception
```

**`Diagnostics/` est en lecture seule, sans exception** — frontière posée par
[CLAUDE.md](../CLAUDE.md). Elle exclut le lancement d'un conteneur de test, fût-il
`hello-world` : tirer une image écrit dans `/var/lib/docker`.

## Prérequis

Debian 12 ou 13, Ubuntu 22.04 ou 24.04 LTS. Les scripts de diagnostic
s'exécutent sans privilège ; ceux qui modifient le système demandent root.

## Scripts

| Script | Rôle | Privilège | Modifie |
|---|---|---|---|
| [`Diagnostics/check-docker.sh`](Diagnostics/check-docker.sh) | diagnostique une machine qu'on découvre : client, socket, service, démon, versions, stockage | aucun | non |

```bash
./Docker/Diagnostics/check-docker.sh
```

Codes : `0` le client est présent et le démon répond — `1` client absent, démon
injoignable, socket interdit ou délai dépassé — `2` option inconnue.

L'absence de Docker n'est pas une erreur du script mais un constat, ce qui
permet d'enchaîner `check-docker.sh || install-docker.sh`.

Un démon qui répond alors que `docker.service` est inactif vaut `0`, assorti
d'un `[WARN]` : le service peut être activé par socket, et `DOCKER_HOST` peut
désigner une machine distante. C'est la réponse du démon qui fait foi.

Chaque interrogation est bornée à 5 secondes, pour qu'un démon qui ne répond
plus ne fige pas le diagnostic.

## Risques

Aucun script de ce domaine n'est encore destructif. Quand `Cleanup/` arrivera,
les volumes seront exclus du nettoyage général par défaut : ils portent les
données.
