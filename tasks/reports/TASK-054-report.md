# TASK-054 — Rapport d'exécution

## Compte rendu
TASK-054 (`uninstall-k3s.sh`) est terminée et fusionnée : c'est le cinquième et dernier script de `Linux/K3s`. Il désinstalle K3s et **détruit** le cluster, sa configuration et les volumes des pods. Suivant la décision 47, il n'appelle que le désinstallateur officiel `/usr/local/bin/k3s-uninstall.sh`, et seulement après avoir affiché ce qui sera détruit, avec les tailles. Il ne fait aucune archive : la sauvegarde relève d'un autre script. Il demande confirmation (`--yes` obligatoire hors terminal, `ASSUME_YES` hérité ignoré), puis relit l'état de la machine : s'il reste quelque chose, il rend 1 en le nommant.

À l'activation, la fiche portait déjà la décision 47 en partie. Le conducteur y a ajouté « aucune archive », ainsi que les défauts vus sur les trois scripts K3s voisins, en notes d'implémentation : garde conteneur avant tout trap ou écriture dans le test, faux `systemctl` fidèle, variables `INSTALL_K3S_*`/`K3S_*` neutralisées, décision 45 prouvée sous pseudo-terminal, jeton jamais affiché, pas de consigne de retour arrière inopérante (A74).

L'agent DeepSeek a livré en deux passages : 136 lignes de script, 214 lignes de cas, 75 vérifications. Son second passage corrigeait un cas mal construit : « K3s absent » laissait le désinstallateur en place, contrairement au critère. Le conducteur a vérifié dans le code que le test ne peut jamais lancer un vrai désinstallateur : la garde `/.dockerenv` passe avant tout, et chaque appel vise une racine temporaire.

La relecture Opus a jugé le travail fusionnable après corrections. Défaut majeur : la liste des chemins détruits avait été supposée, pas relevée. `/var/log/pods` et `/var/log/containers` n'étant supprimés par aucun script officiel, toute vraie désinstallation réussie aurait rendu 1. La session a relevé la source (`install.sh` de k3s, fonctions `create_killall` et `create_uninstall`) et l'a transmise telle quelle. Les autres défauts :
- mineurs : chemins réellement détruits non annoncés (`/run/k3s`, `/run/flannel`, `k3s.service.env`, `k3s-killall.sh`) ; arrêt anticipé du désinstallateur (sortie en 0 sans rien supprimer s'il existe d'autres services k3s) non expliqué ; nœud agent non traité ; taille pouvant afficher « 12Gillisible » ; racine de test silencieuse ; `cut` absent de `require_cmd` ;
- tests creux : la taille des volumes, le chemin absent, et la branche « unité encore connue de systemd ».

Une relance a tout traité : 149 + 272 lignes, 95 vérifications, 65 → 83 lignes d'assertion. Les assertions remplacées l'ont été par des vérifications plus fortes, comme le demandaient les retours. Sans seconde relecture, le conducteur a lu dans le code le majeur (liste annoncée et relue identique à la source, faux désinstallateur qui la suit et la cite), l'arrêt anticipé et la garde conteneur : tout tient. Coût agent : 0,214 $ en deux lancements ; relecture : 34 618 jetons.

En relisant les sorties, le conducteur a remarqué un faux `[ERROR]` après le bilan d'un autre fichier de cas (TASK-009) : A77.

Réserves : A75 à A77, et A66 qui se répète (ci-dessous).

## Statut
COMPLETED

## Travail réalisé
- `Linux/K3s/uninstall-k3s.sh` — 149 lignes
- `tests/integration/uninstall-k3s.test.sh` — 272 lignes, 95 vérifications ; garde `/.dockerenv` avant `mktemp` et `trap` ; faux `k3s`, `k3s-uninstall.sh` (calqué sur `install.sh` officiel), `systemctl` (3 inactif, 1 unité inconnue), `du` et `id` en tête de PATH
- par l'orchestrateur : fiche (décision 47 complétée, notes), `Linux/K3s/README.md`, `Linux/README.md`, README racine, backlog, journal, registre (A75 à A77, A66 complété)

## Déroulé
| Étape | Qui | Résultat |
|---|---|---|
| activation | conducteur | commit ea7f51e |
| lancement 1 | agent `deepseek` | 2 passages, 44 tours, 261 s, 0,108 $ ; 136 + 214 lignes, 75 vérifications ; commits 40c035e, 290143e |
| vérification | conducteur | juge 0 ; périmètre : 2 fichiers du scope ; 65 → 67 lignes d'assertion (290143e : correction de construction justifiée) |
| relecture | Opus, 10 appels, 34 618 jetons, 106 s | FUSIONNABLE APRÈS CORRECTIONS — 1 majeur, 5 mineurs, tests creux |
| lancement 2 | agent `deepseek` | 1 passage, 47 tours, 274 s, 0,106 $ ; 149 + 272 lignes, 95 vérifications ; commit 1526060 |
| vérification | conducteur | juge 0 ; 67 → 83 lignes d'assertion ; D1, D5 et garde conteneur lus dans le code |

## Validations (relancées par le conducteur dans la copie de l'agent, après la relance)
| Commande | Code |
|---|---|
| `bash orchestration/outils/juger.sh tasks/active/TASK-054.md` | 0 — PASSE ; shellcheck 0, cas 0, règles du dépôt 3 (indisponibilités d'environnement de TASK-011) ; longueur 272 signalée |
| `tests/env/run-in-container.sh -- tests/run.sh lint` | 0 — 86 fichiers, 0 erreur, 2 avertissements (scripts Synology hérités) |
| `tests/env/run-in-container.sh -- tests/run.sh integration` | 0 — uninstall-k3s : 95 vérifications, 0 échec, 0 NON EXÉCUTÉ, cas sous pseudo-terminal exécuté |
| `tests/env/run-in-container.sh -- bash Linux/K3s/uninstall-k3s.sh --help` | 0 |

Périmètre : `git diff --name-only master...agent/TASK-054` ne contient que les deux fichiers du `scope`.

## Git
Activation ea7f51e ; branche `agent/TASK-054` (40c035e, 290143e, 1526060) fusionnée `--no-ff` (3eabf97), copie retirée, branche supprimée. Pas de push depuis le conducteur : domaine `Linux/K3s` achevé, push laissé à la session.

## Réserves
- A75 — version corrigée non relue par Opus, fichier de cas à 272 lignes, jamais éprouvée sur un vrai nœud.
- A76 — racine de test `RACINE_TEST` dans le script de production (gardée par `/.dockerenv`, annoncée en `[WARN]`).
- A77 — faux `[ERROR] Échec (code 4)` après le bilan de `configure-cron.test.sh`.
- A66 — commit de relance titré `(RETOURS-TASK-054)`, attribution `Claude Code`.
