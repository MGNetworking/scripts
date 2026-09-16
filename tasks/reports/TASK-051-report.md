# TASK-051 — Rapport d'exécution

## Compte rendu
TASK-051 (`install-k3s.sh`) est terminée et fusionnée. C'est le deuxième script de `Linux/K3s`. Il installe K3s serveur mono-nœud par l'installateur officiel `get.k3s.io`, après un préflight : root, système et architecture pris en charge, disque, mémoire, ports 6443, 80 et 443 libres, site joignable en HTTPS. Suivant la décision 47, il installe la version du canal stable, ou celle qu'épingle `SRV_K3S_VERSION`. L'installateur est téléchargé en HTTPS seul dans un fichier temporaire, puis exécuté, jamais par `curl | sh`. Le script active ensuite le service et termine par `verify-k3s.sh`. Si K3s est déjà présent, il affiche la version et ne réinstalle rien.

L'agent DeepSeek a livré au premier lancement : 150 lignes de script, 168 lignes de cas, 49 vérifications, dans un seul commit. Il dit avoir réduit le fichier de cas de 224 à 168 lignes avant ce commit ; Git ne permet pas de voir ce qui a été retiré. Le juge et la validation en conteneur passaient. La relecture Opus a pourtant trouvé un défaut bloquant. Le fichier de cas écrit puis efface `/var/lib/rancher/k3s` sans vérifier qu'il tourne dans un conteneur : lancé en root sur un vrai serveur, il aurait détruit le cluster. Elle a aussi trouvé deux défauts majeurs. Une activation ratée du service sortait par une ligne d'erreur anonyme, au code non garanti. Et le faux `systemctl` rendait toujours 0, si bien qu'un service inactif n'était jamais testé. S'y ajoutaient trois mineurs : échec de `ss` silencieux, redirection vers HTTP possible, variables héritées capables de détourner l'installateur. Enfin, cinq critères n'étaient que partiellement prouvés et quatre tests étaient creux.

Une relance a tout traité : 164 + 235 lignes, 78 vérifications, aucune retirée (49 → 71 lignes d'assertion). Sans seconde relecture, le conducteur a lu lui-même le bloquant et les deux majeurs. La garde `/.dockerenv` précède la création du temporaire, le `trap` et toute écriture. Lancé hors conteneur, le fichier de cas saute et rend 3 sans rien toucher, ce qui a été constaté sur l'hôte. L'activation ratée et le service inactif sortent en 1 avec leur cause, et le faux `systemctl` rend 3 comme le vrai. Coût agent : 0,313 $ en deux lancements ; relecture : 41 940 jetons.

Réserves : A64, A65, A66 (ci-dessous).

## Statut
COMPLETED

## Travail réalisé
- `Linux/K3s/install-k3s.sh` — 164 lignes
- `tests/integration/install-k3s.test.sh` — 235 lignes, 78 vérifications ; faux `curl` (qui dépose un installateur traceur), `k3s`, `systemctl`, `ss`, `df`, `awk` et `id` en tête de PATH ; aucun téléchargement réel
- `config/server.env.example` — `SRV_K3S_VERSION` commentée
- par l'orchestrateur : fiche (critère de version de la décision 47 ajouté à l'activation), `Linux/K3s/README.md`, `Linux/README.md`, README racine, backlog (TASK-052, 053 et 054 passées `ready` ; ligne TASK-050 mal placée dans la table des tâches retirée), journal, registre (A64 à A66)

## Déroulé
| Étape | Qui | Résultat |
|---|---|---|
| activation | conducteur | commit bdb1d67 |
| lancement 1 | agent `deepseek` | 1 passage, 85 tours, 697 s, 0,231 $ ; 150 + 168 lignes, 49 vérifications ; commit 9a7ad9c |
| vérification | conducteur | juge 0 ; périmètre : 3 fichiers du scope ; 49 lignes d'assertion |
| relecture | Opus, 12 appels, 41 940 jetons, 101 s | FUSIONNABLE APRÈS CORRECTIONS — 1 bloquant, 2 majeurs, 3 mineurs, 5 critères partiels, 4 tests creux |
| lancement 2 | agent `deepseek` | 27 tours, 233 s, 0,082 $ ; 164 + 235 lignes, 78 vérifications ; commit 3149730 |
| vérification | conducteur | juge 0 ; 49 → 71 lignes d'assertion ; les 5 assertions modifiées sont celles désignées comme creuses ou partielles (mémoire, port 443, « diagnostic », curl-appels) ; bloquant et majeurs lus dans le code |

## Validations (relancées par le conducteur dans la copie de l'agent, après la relance)
| Commande | Code |
|---|---|
| `bash orchestration/outils/juger.sh tasks/active/TASK-051.md` | 0 — PASSE, 78 réussies, 0 échec, 0 NON EXÉCUTÉ ; règles du dépôt 3 (indisponibilités d'environnement de TASK-011) |
| `tests/env/run-in-container.sh -- tests/run.sh lint` | 0 — 0 erreur, 2 avertissements sur des scripts Synology hérités |
| `tests/env/run-in-container.sh -- tests/run.sh integration` | 0 — install-k3s : 78 vérifications |
| `tests/env/run-in-container.sh -- bash Linux/K3s/install-k3s.sh --help` | 0 |
| `bash tests/integration/install-k3s.test.sh` sur l'hôte, hors conteneur | 3 — saute par la garde, rien écrit |

Périmètre : `git diff --name-only master...agent/TASK-051` ne contient que les trois fichiers du `scope`.

## Git
Activation bdb1d67 ; branche `agent/TASK-051` (9a7ad9c, 3149730) fusionnée `--no-ff`, copie retirée, branche supprimée. Pas de push : domaine `Linux/K3s` inachevé.

## Réserves
- A64 — version corrigée non relue par Opus, longueurs au-delà de 150, jamais éprouvée sur une vraie machine.
- A65 — `ss` absent : simple `[WARN]` ; seuils de ressources non vérifiés à la source.
- A66 — commit de relance de l'agent mal formé (titre, ligne `Tâche :` absente).
