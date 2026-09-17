# TASK-074 — Rapport d'exécution

## Compte rendu

La décision 49 prévoit un `CADRAGE.md` par grand dossier : un document qui engage, script
par script, ce qui est réputé utilisé sur les serveurs. `Kubernetes/` est le premier
dossier cadré ; il sert aussi à éprouver le modèle avant `Linux/`, `Docker/` et
`Synology/` (TASK-075 à 077).

**Ce qui a été écrit.** `Kubernetes/CADRAGE.md` suit le modèle de la décision 49 :
- le **besoin** du dossier (administrer un K3s mono-nœud par commandes rejouables) et ce
  qui est hors besoin ;
- un seul ensemble, « Gestion de Kubernetes », avec l'ordre des scripts et leurs
  conventions communes (accès au cluster, codes de retour, confirmation, réglages
  `SRV_*`) ;
- **17 contrats**, un par script, lus dans le code et non dans les README : options et
  défauts, codes de retour, ce que le script modifie et ce qu'il lit, état « actif » ;
- l'historique, avec une ligne « état initial » dont la colonne « Validé par user » est vide.

La fiche annonçait 18 scripts ; le dossier en compte 17 (5 + 5 + 7). Le critère de la
fiche est corrigé en ce sens.

**Relecture.** Opus a rendu « fusionnable après corrections ». Les 17 contrats suivaient
le code, mais trois conventions communes en disaient plus que le code :
- le code 124 n'est pas « délai dépassé » partout : quatre scripts de Maintenance le
  disent « apiserver injoignable » — convention réécrite, écart ouvert en A130 ;
- une version mal formée rend 1, pas 2, dans `install-cert-manager.sh` — convention assouplie ;
- `configure-namespaces.sh` accepte un `ASSUME_YES` hérité, et `backup-resources.sh`
  écrit sans confirmation — convention précisée.

Mineurs corrigés : `TIMEOUT_HELM`, lue sans condition, est entrée au contrat de
`install-cert-manager.sh` au lieu d'être déclarée hors contrat ; `--dry-run` de ce script
exige `helm` et `kubectl` présents ; `timeout`, `base64`, `sha256sum` absents et
`--config` sans valeur ajoutés aux codes ; `ss -ltnp` sous root ; journal écrit par les
deux installateurs.

**Le modèle** convient : aucune rubrique n'a manqué. Une seule chose s'est ajoutée, la
liste de ce qui est **hors contrat** (variables de test `DELAI_TEST`, `ATTENTE_TEST`,
libellé des messages) : sans elle, la règle « tout ce qui figure au contrat est réputé
utilisé » figerait les messages.

**Coût.** Une relecture Opus, 115 353 jetons.

**Il te reste à valider le cadrage.** Tant que la ligne d'historique n'est pas signée,
TASK-075 à 077 restent `pending`.

### Réserves

- Quatre scripts de Maintenance nomment mal un délai dépassé, et `cluster-status.sh`
  n'exige pas `timeout` (A130).

## Statut

`completed`, cadrage en attente de validation par `user`.

## Fichiers

- `Kubernetes/CADRAGE.md` (créé, 368 lignes)

## Validations

| Commande | Code |
|---|---|
| `bash orchestration/outils/verifier-liens.sh` (copie, avant et après corrections) | 0 |
| `git diff --name-only master...agent/TASK-074` | `Kubernetes/CADRAGE.md` seul |
| contrôle par grep de chaque option, variable `SRV_*`, `REGISTRY_*`, `TIMEOUT_HELM` et `ASSUME_YES` citée dans un contrat, dans le script concerné | aucun manquant |
| `bash orchestration/outils/verifier-liens.sh` (master, après clôture) | 0 |

## Git

- `chore: TASK-074 en cours`
- `docs(kubernetes): cadrage initial du dossier`
- `fix: retours de relecture (TASK-074)`
- `Merge branch 'agent/TASK-074'`, puis commit de clôture
