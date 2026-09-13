# TASK-031 — Rapport

**Statut** : `completed` — 2026-09-13
**Script** : `Docker/Diagnostics/check-docker.sh`, 150 lignes
**Cas** : `tests/integration/check-docker.test.sh`, 110 lignes — 26 vérifications

## Validations

| Commande | Code attendu | Code réel |
|---|---|---|
| `tests/run.sh lint` | 0 | **0** |
| `run-in-container.sh -- tests/run.sh lint` | 0 | **0** |
| `run-in-container.sh -- tests/run.sh integration` | 0 | **0** |
| `run-in-container.sh -- bash …/check-docker.sh --help` | 0 | **0** |

Le fichier de cas seul rend **4** — preuve partielle, un cas sauté par nature :
un socket présent mais interdit demanderait un vrai socket unix appartenant à un
autre utilisateur, donc un démon ou `CAP_CHOWN`. La branche « socket absent » est
éprouvée par tous les autres cas.

## Ce qui a été produit

`Docker/Diagnostics/check-docker.sh` — cinq rubriques : client et versions
(client, plugin Compose, Buildx), socket du démon, service systemd, démon
(version du moteur, pilote de stockage, répertoire de données), verdict.

Trois codes : `0` client présent et démon qui répond — `1` client absent, démon
injoignable, socket interdit, délai dépassé — `2` option inconnue, seul cas de 2.

`Docker/README.md` créé — README unique du domaine, plan §13. `README.md` racine
complété d'une ligne de tableau et d'un lien vers le nouveau README.

## Deux défauts trouvés et corrigés

**`${REP%% *}` affichait le dépôt, pas la version.** `docker buildx version`
rend `github.com/docker/buildx v0.17.1` ; le script affichait
`github.com/docker/buildx`. Corrigé en `${REP#* }`. **Trouvé par le fichier de
cas**, sur une assertion que la version longue du script n'avait pas.

**`A && B || C` refusé par `shellcheck` (SC2015), trois fois.** Le lint passe sur
l'hôte — `shellcheck` y est absent, `tests/lint.sh` sort alors en 0 avec un
`[WARN]` — et **échoue dans le conteneur**, où il est présent. Remplacé par une
fonction `rubrique`. C'est l'angle mort de l'hôte déjà consigné au backlog : le
lint de l'hôte ne prouve rien tant que `shellcheck` n'y est pas installé.

## Décisions tranchées

**Le verdict ne dépend pas de l'état du service.** Un démon qui répond alors que
`docker.service` est inactif rend **0** avec un `[WARN]` : le service peut être
activé par socket, et `DOCKER_HOST` peut désigner une machine distante. C'est la
réponse du démon qui fait foi.

**Délai de 5 secondes, en dur.** Pas d'option : une borne configurable est une
fonctionnalité non demandée. Mesuré : trois appels bornés rendent la main en 16 s
face à un démon qui ne répond jamais, contre 60 s sans borne. Risque assumé — sur
un hôte portant des milliers de conteneurs, `docker info` peut dépasser 5 s et le
script conclurait à tort « non exploitable ».

**`DOCKER_SOCKET` surchargeable**, pour que le chemin du socket ne soit pas en
dur. Non exigé par la tâche, une ligne, et c'est ce qui rendrait le cas « socket
interdit » éprouvable plus tard.

## Ce qui survit à cette tâche

**Le processus a changé en cours de route.** Maxime a arrêté l'exécution pour
signaler que les scripts produits étaient trop volumineux et le processus trop
coûteux. Mesure : la première version de `check-docker.sh` faisait **706 lignes**
— plus courte que `check-memory.sh`, 815 lignes, déjà dans le dépôt. Le script
réécrit en fait **150** et passe les mêmes validations.

Les quatre décisions qui en découlent sont dans
[ADR-0004](../../docs/agent/decisions/ADR-0004-sobriete.md) : cible de 150 lignes
pour un script et pour un fichier de cas, l'agent écrit lui-même sans déléguer,
30 lignes pour un fichier de tâche.

**`redacteur-script` n'a ni `Bash` ni terminal.** Il ne peut lancer aucune
validation, et l'a dit honnêtement plutôt que de le laisser croire. Toute
consigne qui lui demande de valider son travail lui demande l'impossible.

**`CLAUDE.md` a été modifié par l'agent** ce jour — arborescence `Docker/` et
frontière de `Docker/Diagnostics/`. Zone interdite selon `AGENTS.md` §5. Les
modifications sont justes et conservées, mais elles auraient dû être demandées.

## Reste ouvert

Les huit autres tâches Docker — TASK-029, 030, 032 à 037 — portent des fichiers
de 190 à 295 lignes. Elles restent justes et exécutables ; elles ne servent pas
de modèle de longueur.
