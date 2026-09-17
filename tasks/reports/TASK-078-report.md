# TASK-078 — Rapport d'exécution

## Compte rendu

`tests/README.md` faisait 1 514 lignes. Ce qui devait être le guide des tests était
devenu un journal : les deux tiers racontaient des défauts passés, déjà consignés dans
les rapports de tâche et dans Git. Tu as validé la refonte le 2026-09-17 (question 4 de
la proposition : « tout de suite »).

**Ce qui a été fait.** Le fichier fait maintenant 200 lignes et suit le plan du §6 de
`docs/proposition-ansible-et-tests.md` : ce que le dossier prouve, avec les trois
niveaux de preuve (simulé, conteneur, machine) ; comment lancer les tests ; comment
écrire un fichier de cas (squelette, `assert.sh`, onze règles d'une ou deux phrases,
faux binaires, qualification des sauts, bilan) ; les codes de retour ; l'environnement
conteneurisé. Seule différence avec le plan : le point 6 devait renvoyer à
`Ansible/README.md`, qui n'existe pas encore. Un paragraphe renvoie donc à TASK-080 et
TASK-081.

**Précaution.** Deux fichiers d'acceptance (TASK-012 et TASK-013) cherchent des phrases
exactes dans ce README. Elles ont été gardées et leurs assertions « README » passent
toutes. La règle des faux binaires, citée par `juger.sh` et `lien-ecrit.awk` (A122), est
conservée en entier. Le tableau ci-dessous montre, règle par règle, où chacune est
passée ou pourquoi elle a été retirée.

**Relecture.** Opus a rendu « fusionnable après corrections » : un défaut majeur et
quatre mineurs.
- Majeur : le README interdisait toute assertion sur `systemctl is-system-running`,
  alors que `systemd.test.sh` en fait une légitime (accepter `running` ou `degraded`).
  La règle porte désormais sur la valeur exacte.
- Mineurs corrigés : la condition pour écrire « par nature » dans un bilan est précisée ;
  la phrase sur l'ajout d'un niveau est rectifiée ; la garde « système jetable » est
  décrite telle qu'elle existe vraiment.
- Mineur non corrigé, hors périmètre : des commentaires de tests renvoient encore aux
  anciens numéros de section (A147).

**Découvert en chemin.** `tests/acceptance/TASK-012-semantique-codes.sh` est rouge sur
l'hôte, sans lien avec cette tâche : trois cas attendent 0 d'un niveau `lint` qui rend 3
sans `shellcheck` (A149). C'est une validation faussée, d'où la fiche urgente TASK-082.

**Coût.** Une relecture Opus, 100 303 jetons.

### Réserves

- Renvois de section devenus faux dans les commentaires des tests (A147).
- Assertions encore définies localement dans trois fichiers d'acceptance, dette sans fiche (A148).
- `TASK-012-semantique-codes.sh` rouge sur l'hôte, fiche TASK-082 (A149).

## Statut

`completed`.

## Fichiers

- `tests/README.md` (réécrit : 1 514 → 200 lignes)

## Validations

| Commande | Code |
|---|---|
| `wc -l tests/README.md` (après corrections) | 200 lignes |
| `bash orchestration/outils/verifier-liens.sh` (branche, avant et après corrections) | 0 |
| `bash tests/run.sh --liste` (branche, avant et après corrections) | 0 |
| `git diff --name-only master...agent/TASK-078` | `tests/README.md` seul |
| existence des chemins cités (`test -e`, 12 chemins) | aucun manquant |
| `grep -F` des 10 motifs du README exigés par TASK-012 et TASK-013 (après corrections) | tous présents |
| `bash tests/acceptance/TASK-012-semantique-codes.sh` (avant corrections) | 1 — 4 assertions README réussies, 3 échecs sans lien (A149) |
| `bash tests/acceptance/TASK-013-natures-de-saut.sh` (avant corrections) | 4 — 6 assertions README réussies, 0 échec |
| `bash orchestration/outils/juger.sh tasks/active/TASK-078.md` | 1 : « aucun fichier de cas dans le périmètre » ; tâche documentaire, le juge ne s'applique pas |
| `bash orchestration/outils/verifier-liens.sh` (master, avant le commit de clôture) | 0 |

## Correspondance des règles

Règles prescriptives de `tests/README.md` au commit 2c1e965 (numéros de ligne de
l'ancien fichier) → sort dans le nouveau (§ du nouveau fichier). « Retirée » donne la
raison ; « récit » = constat daté ou histoire d'un défaut, conservé dans le rapport de
la tâche citée et dans Git.

| Anc. l. | Règle | Nouveau README, ou raison du retrait |
|---|---|---|
| 3-5 | rien n'est démontré tant qu'une commande n'a pas réussi | §1, 1er paragraphe |
| 7-16 | un seul point d'entrée, `tests/run.sh` | §2, bloc et phrase « Un seul point d'entrée » |
| 18-23 | hors analyse statique, tout passe par le conteneur | §2 « Sur l'hôte, seule l'analyse statique » ; §5 1er paragraphe |
| 37-38 | un niveau s'ajoute en déposant son script, rien d'autre à modifier | §1, dernière ligne, corrigée : les cinq niveaux sont fixés dans `tests/run.sh`, seul le dispatcher manque |
| 42-43, 150, 541, 663 | découverte en `maxdepth 1` | §1 « découverts par leur dispatcher en `maxdepth 1` » |
| 56-62 | fonctions qui font `exit` : `bash` neuf, pas un sous-shell | §3 règle 11 |
| 63-71 | bac à sable de `common.sh`, `LOG_DIR` redirigé | retirée : construction interne de `tests/unit/common.test.sh`, décrite en tête de ce fichier |
| 78-82 | lanceurs non privilégiés éprouvés ; sinon `NON EXÉCUTÉ`, jamais réussis | règle générale gardée (§3 règle 1) ; détail retiré, propre à `common.test.sh` |
| 84-86 | ne jamais retirer `set -Eeuo pipefail` pour faire passer un cas | §3 règle 2 |
| 88-145 | écarts TASK-015, mutations, régression `run_logged` | retirée : récit (TASK-015, décisions 7-9) ; la méthode « mutation » survit en §3 règle 6 |
| 161-165 | pourquoi `check-memory.sh` a son fichier | retirée : récit de placement |
| 167-177 | `integration` modifie le système, conteneur seul, garde jetable | §2 1re puce (« au moins `/.dockerenv` » : les trois formes ne sont pas dans tous les fichiers) |
| 179-183 | sur l'hôte `integration` rend 3, ce n'est pas un échec | §4 code 3 « rien n'est prouvé » et §2 (conteneur comme référence) ; le cas particulier de l'hôte n'est plus écrit en toutes lettres |
| 185-201 | idempotence : `A == B` et `P0 != A` | §3 règle 3 |
| 203-215 | empreinte de tout `/etc`, dispositions à conteneur unique | retirée : construction de `linux-system.test.sh`, commentée sur place |
| 217-237 | recouvrement avec TASK-011 | retirée : récit |
| 239-266 | verrou des codes TASK-016 ; décompte et assertion d'absence gardée | §3 règles 4 et 5 ; tableau retiré (récit TASK-016) |
| 268-302 | `--file` TASK-017/019 ; décompte mesuré ; mutation utile | §3 règles 5 et 6 ; tableau retiré (récit) |
| 304-403 | trap ERR TASK-018, tableau des 54 sites | retirée : récit, relevé vivant dans `Linux/System/recensement-substitutions.md` ; méthode en §3 règles 5-7 |
| 338-342 | décompte mesuré sur son site, jamais repris | §3 règle 5 |
| 381-388 | site sans cause atteignable : `NON EXÉCUTÉ`, pas `saute_par_nature` s'il dépend du même diff | §3 règle 7 (NON EXÉCUTÉ) ; nuance du même diff retirée, propre à TASK-018 |
| 405-432 | échecs non fataux ; stub sélectif ; garde de contraste | §3 règle 4 (garde de contraste) ; stubs : §3 « Faux binaires » ; reste récit |
| 434-452 | faux binaire : fichier ordinaire, jamais à travers un lien, jamais le vrai par son nom (A122) | §3 « Faux binaires », intégral sauf le récit daté de TASK-071 |
| 454-488 | défauts corrigés de `configure-cron.sh`, `configure-timezone.sh` | retirée : récit |
| 490-536 | cinq enseignements | §3 règles 5, 6, 7 ; « toute fonction qui rend sa valeur sur `stdout` » retirée : règle d'écriture de script, déjà dans `docs/architecture-technique.md` (l. 427) |
| 551-556 | ordre `find \| sort` ; restituer, vérifier, filet avant | §3 règle 8 ; ordre des fichiers retiré (constat) |
| 566-570 | `environment` modifie le système, gardes, restitution vérifiée | §2 1re puce ; §3 règle 8 |
| 585-590 | la garde éprouve systemd, jamais le nom du profil | §5 puce « Profil `systemd` » |
| 592-599 | le niveau garde des cas exécutables sans systemd | §5 même puce |
| 601-608 | tableau des décomptes mesurés | retirée : mesure datée |
| 617-621 | aucune assertion sur la valeur exacte de `is-system-running` ni sur les unités en échec de l'image ; fabriquer l'unité | §5 puce « Profil `systemd` » (formulation corrigée en relecture : `running` et `degraded` restent acceptés tous deux) |
| 623-632 | témoins de services | §5 « Témoin modifiable : `systemd-logind.service` » ; témoins immobiles retirés (constat) |
| 636-649 | hors de portée : `hostnamectl`, `cron`, reboot | §5 puce « Jamais `reboot` » |
| 651-658 | jamais `integration` sous `systemd` | §2 2e puce |
| 677-682 | cas destiné au conteneur dans `interne/` | §3 règle 10 |
| 692-698 | table des codes d'un niveau | §4 |
| 708-710 | le 4 exige au moins une réussite ; tester « aucune réussite » avant | §4 ; ordre du bilan §3 |
| 714-729 | mesure du faux vert TASK-011 | retirée : récit |
| 734-744 | deux natures ; une seule indisponibilité → 3 ; ordre des gardes | §3 « Qualifier un saut » et « Le bilan » |
| 746-754 | dans le doute, indisponibilité ; outil absent de l'image vs non installé | §3 « Règle de prudence » et puces |
| 755-764 | retrait des contrôles de forme TASK-011 | retirée : récit (décision 13) |
| 766-771 | décompte des deux natures toujours affiché | §3 « `info` obligatoire » |
| 777-786 | codes de `tests/run.sh`, ne rend jamais 4 | §4 |
| 788-794 | 3 distinct de 0 et 1 ; NON EXÉCUTÉ jamais PASS | §4 ; §1 |
| 796-801 | codes du lanceur distincts ; lancer `tests/run.sh` dans le conteneur | §4 ; §2 |
| 813-832 | `bash -n` ne suffit pas ; `shellcheck` absent → NON EXÉCUTÉ ; référence en conteneur | §2 3e puce ; installation `winget`/`apt` retirée (hors dépôt) |
| 836-840 | SC1090/SC1091 exclus | §2 4e puce |
| 844-864 | hérités : style toléré, syntaxe jamais ; `--strict` | §2 5e puce et bloc |
| 868-871 | aucun script d'administration sur l'hôte | §5 1er paragraphe |
| 880-883 | commande exécutée telle quelle, code transmis | §5 ; §4 |
| 887-903 | préflight, conteneur neuf, aucun état ne survit ; nettoyage manqué n'altère pas le code | §5 1er paragraphe |
| 907-926 | options et codes du lanceur | §5 synopsis ; §4 |
| 930-1091 | `assurer-docker.sh` : attend, ne démarre pas, jamais l'arrêt, plafond, délais, trace, `--dry-run` 0 ≠ disponible | §5 puce `assurer-docker.sh` ; §4 ; plafonds, délais et récit du 2026-09-04 retirés : commentés dans le script, décision `user` du 2026-09-04 |
| 1093-1102 | profils ; un `Dockerfile.<nom>` suffit | §5 tableau et 1re puce |
| 1115-1118 | mode déclaré par le label | §5 1re puce |
| 1128-1289 | options `--privileged`/`--tmpfs`, sans `--rm`, bornes, pire cas 165 s, paquets | retirée : construction de `run-in-container.sh`, commentée dans le script (paquets : dans `Dockerfile.systemd`) ; options gardées au tableau §5 |
| 1291-1297 | jamais `reboot` ni `poweroff` ; limites `NON EXÉCUTÉ` | §5 |
| 1311-1323 | locale ; listes `apt` supprimées ; dépôt non copié ; paquet justifié | §5 2e puce ; locale retirée (commentée dans `Dockerfile.debian`) |
| 1327-1341 | préfixe `mgnet-test-` sans exception ; vérifier qu'il ne reste rien | §5 3e puce |
| 1345-1362 | MSYS, CRLF, `Permission denied` | §5 dernière puce |
| 1366-1377 | trois règles propres aux tests | §3 préambule, règles 1, 2, 3 |
| 1381-1395 | fonctions d'`assert.sh`, squelette | §3 |
| 1397-1423 | trois fonctions de saut ; `saute_par_nature` est une signature ; compteur partagé | §3 tableau et « la qualification se relit » |
| 1425-1432 | bilan neutre ; sous-affirmer jamais faux vert | §3 « Règle de prudence » |
| 1434-1437 | Bash pur ; `assert.sh` ne pose ni `set` ni `trap` | §3 |
| 1439-1444 | ne jamais créer `tests/lib/common.sh` | §3 règle 9 |
| 1446-1456 | assertions locales des trois premiers fichiers d'acceptance | retirée : constat d'état ; la dette est versée au registre (A148) |
| 1460-1500 | modèle et ordre du bilan ; ligne `info` non facultative | §3 « Le bilan » |
| 1502-1514 | règle de qualification du libellé du bilan | §3 « seul un fichier dont tous les sauts sont qualifiés » |

## Git

- `chore: TASK-078 en cours`
- `docs(tests): refondre tests/README.md en guide`
- `docs(tests): garder la règle des fonctions qui appellent exit`
- `fix: retours de relecture (TASK-078)`
- `Merge branch 'agent/TASK-078'`, puis commit de clôture
