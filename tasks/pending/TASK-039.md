---
id: TASK-039
title: "Tenir le registre unique des anomalies et les traiter"
status: ready
priority: high
depends_on: []
environment: container-debian
agent: orchestrateur
human_approval_required: false
objective: |
  Réunir en un seul endroit tout défaut, dette ou point ouvert relevé dans le
  dépôt — orchestration des agents, harnais de tests, socle, scripts — et les
  traiter jusqu'à ce que la liste soit vide. C'est le SEUL lieu d'entrée : aucun
  README, rapport ou document ne tient plus sa propre liste de points ouverts.
scope:
  - ce fichier, tenu à jour à chaque tâche
  - les corrections de chaque ligne, dans les fichiers qu'elle nomme
out_of_scope:
  - les limites assumées recensées en fin de fichier — elles ne sont pas des défauts
  - le chantier des scripts à écrire, qui reste dans tasks/backlog.md
acceptance_criteria:
  - chaque ligne du registre est cochée, avec le commit ou la tâche qui la ferme, ou requalifiée en limite assumée avec sa raison
  - toute réserve d'un rapport écrit après le 2026-09-15 cite l'identifiant Axx qui la porte
validation:
  - "grep -c '^| \\[ \\]' tasks/pending/TASK-039.md — rend 0 à la clôture"
implementation_notes:
  - une ligne se traite directement si elle tient en quelques lignes ; sinon elle devient une tâche atomique qui renvoie à son Axx
  - une ligne touchant lib/common.sh passe par l'orchestrateur, zone protégée
  - une nouvelle anomalie reçoit le prochain Axx libre, jamais un numéro réemployé
  - le registre reste dans tasks/pending/ en statut ready tant qu'il n'est pas vide : CLAUDE.md, /tache et regles.md pointent vers ce chemin (voir A16)
---

# TASK-039 — Registre unique des anomalies

Exception assumée à la règle des 30 lignes : c'est un registre, pas une fiche.

**Registre vidé le 2026-09-15** ([rapport](../reports/TASK-039-report.md)). La fiche
reste ouverte : toute nouvelle anomalie s'inscrit ci-dessous, avec le prochain Axx.

## Règle d'entrée

Tout défaut non corrigé, toute réserve de rapport, toute remarque de relecture
laissée de côté, tout point ouvert d'orchestration **s'inscrit ici**, et nulle
part ailleurs. `/tache` le vérifie à la clôture. Prochain identifiant libre : **A67**.

## Registre

P1 rend une validation fausse ou `master` rouge · P2 fiabilité de l'orchestration
et du harnais · P3 dette du socle et des scripts · P4 documentation et forme.

| État | Id | P | Anomalie | Source | Traitement |
|---|---|---|---|---|---|
| [x] | A01 | P1 | Acceptance TASK-011 rouge : 4 directives `shellcheck` sans justification au-dessus (`configure-docker.sh` l.91, 141 ; `install-docker.sh` l.145 ; `configure-docker.test.sh` l.107) et `ASSUME_YES` lue hors `lib/common.sh` | TASK-028, ex-TASK-038 | fait — directives justifiées au-dessus, garde sur `OUI` au lieu d'`ASSUME_YES` ; acceptance TASK-011 : 0 échec |
| [x] | A02 | P1 | `juger.sh` ne lance pas les règles transverses de l'acceptance : agents et relecteur n'ont pas vu A01 | TASK-028 | fait — `juger.sh` lance `TASK-011-analyse-statique.sh`, un 1 fait échouer le juge |
| [x] | A03 | P1 | `tests/lint.sh` sort en 0 sur l'hôte en annonçant NON EXÉCUTÉ (pas de `shellcheck`) : un validateur conclut PASS | TASK-002, 012, 018, backlog | fait — `tests/lint.sh` rend 3 sans `shellcheck` ; `/tache` le lit comme NON EXÉCUTÉ |
| [x] | A04 | P1 | `docker info` sans borne de temps dans trois fichiers d'acceptance (`TASK-002:181`, `TASK-011:145`, `TASK-012:589`) : un démon qui démarre suspend le niveau | TASK-013 | fait — `timeout 30` sur les trois sondes |
| [x] | A05 | P2 | ~70 sauts non qualifiés (`saute` nu) dans `unit` et `integration` : leur nature n'est pas établie | TASK-013 | fait — les 14 sauts qui se déclenchent en conteneur sont qualifiés « par nature » ; les autres ne tournent que hors conteneur, où leur nature dépend de l'hôte : le saut neutre y est le bon verdict |
| [x] | A06 | P2 | Exécutions concurrentes non maîtrisées (conteneur tué en 137, assertions « aucun conteneur résiduel » fausses en parallèle) — préalable au parallélisme des agents | TASK-002, 012, 014 | reporté sous condition — inscrit comme prérequis du parallélisme dans la décision 40 ; sans parallélisme, aucune exécution concurrente n'a lieu |
| [x] | A07 | P2 | Tâches hors script (README, schéma, documentation) non couvertes par le circuit d'agent : `limites.json` et `juger.sh` ne le permettent pas | orchestration | décision 41 — la documentation reste à l'orchestrateur |
| [x] | A08 | P2 | Premier jet de TASK-034 : 2 728 s et 80 tours, contre 315 s pour TASK-033 ; cause non identifiée | TASK-034 | atténué — `lancer-agent.sh` borne l'agent à une heure (`DUREE_MAX`) ; la cause de TASK-034 n'est plus établissable, la durée reste journalisée |
| [x] | A09 | P2 | Coût réel des agents non calculé : `lancer-agent.sh` relève les jetons, pas le prix ; estimations à confirmer sur le tableau de bord DeepSeek | TASK-033, 034 | fait — tarifs dans `modeles/deepseek.env`, colonne `cout_usd` dans `agents.tsv` (TASK-033 : 0,244 $, TASK-034 : 0,357 $) |
| [x] | A10 | P2 | `.claude/agents/relecteur.md` : `model: sonnet` et « lance les validations », alors que `/tache` impose Opus en lecture seule — Opus confirmé par l'essai de TASK-034 | TASK-034 | fait — `relecteur.md` : `model: opus`, outils de lecture seuls, plus aucune commande |
| [x] | A11 | P2 | Docker Desktop tombé en cours de session : aucune reprise possible sans humain ; `DELAI_DISPONIBILITE` (300 s) jamais mesuré | points en suspens §11, TASK-027 | décision 42 — arrêt signalé, limite assumée |
| [x] | A12 | P2 | `run-in-container.sh` : message de démon injoignable tronqué, `--profil --dry-run` mal analysé | TASK-002, backlog | fait pour `--profil --dry-run` (refus clair) ; message tronqué non reproductible sans couper le démon, ce que la décision 42 exclut |
| [x] | A13 | P2 | Profil `systemd` en `--privileged` sans preuve qu'il soit indispensable ; plafond de 30 s du lancement détaché jugé, non mesuré | points en suspens §9, §10, TASK-020 | fait — mesuré : sans `--privileged` (SYS_ADMIN, seccomp et apparmor levés, cgroupns privé) le conteneur s'arrête avant systemd ; justification écrite dans `run-in-container.sh`. Le plafond de 30 s reste un jugement, faute de cas défavorable mesurable |
| [x] | A14 | P2 | Aucune garde contre la récursion du niveau `acceptance` : un fichier de cas qui l'appelle boucle sans fin | TASK-012 | fait — `run-acceptance.sh` refuse en 2 une relance sur le même répertoire, les bacs à sable restent permis |
| [x] | A15 | P2 | Les gardes de `run-unit.sh` ne sont vérifiées par aucune suite en continu | TASK-003 | fait — `tests/acceptance/TASK-039-gardes-dispatchers.sh`, 10 vérifications |
| [x] | A16 | P2 | Les liens entre tâches cassent à chaque changement de statut (le répertoire fait partie du chemin) | backlog | fait — `orchestration/outils/verifier-liens.sh`, lancé à la clôture par `/tache` |
| [x] | A17 | P2 | Piège du commentaire commençant par `shellcheck` : seul `tests/lint.sh` en est protégé | TASK-011, backlog | fait — contrôle ajouté à `TASK-011-analyse-statique.sh`, contre-épreuve détectée |
| [x] | A18 | P2 | Aucune intégration continue | backlog | décision 43 — pas de CI pendant le chantier |
| [x] | A19 | P3 | `LOG_DIR` validé par personne : une valeur commençant par un tiret traverse le socle | points en suspens §6 | fait — `lib/common.sh` refuse un `LOG_DIR` non absolu, avertit et prend la valeur par défaut ; testé |
| [x] | A20 | P3 | Asymétrie de chargement : `server.env` par `source` nu, `load_config` avec `set -a` — même écriture, effets différents | TASK-015, backlog | fait — `server.env` chargé sous `set -a`, comme `load_config` ; testé |
| [x] | A21 | P3 | `set +a` non rétabli quand le `source` d'un `.env` tue le shell sous `set -u` | TASK-015, backlog | fait — lecture d'essai en sous-shell pour `server.env` et `load_config` : arrêt propre, `allexport` jamais armé ; testé |
| [x] | A22 | P3 | `lib/common.sh` crée et écrit `LOG_DIR` dès le `source` : `--help` et `--dry-run` ne sont jamais sans effet de bord | TASK-004, 011 | requalifié limite assumée — journaliser un `--dry-run` est voulu, et créer `LOG_DIR` au chargement est le contrat du socle (`docs/architecture-technique.md`) |
| [x] | A23 | P3 | `enable_full_logging` sans aucune couverture de test | TASK-003, 015 | fait — `tests/unit/journalisation-complete.test.sh`, 19 vérifications |
| [x] | A24 | P3 | Trois commentaires de `lib/common.sh` (l.87, 229, 294) citent « ADR-0003 », retiré | refonte orchestration | fait — renvois vers `orchestration/decisions.md` |
| [x] | A25 | P3 | `check-disk.sh` : `df` se fige sur un montage réseau injoignable | points en suspens §10 | fait — `df` borné à 15 s par `timeout` dans `check-disk.sh` |
| [x] | A26 | P3 | `configure-swap.sh` : `FICHIER_SWAP` jamais contrôlé non vide après validation | TASK-017 | fait — garde « chemin vide » après validation dans `configure-swap.sh` |
| [x] | A27 | P3 | `swap_actif()` ne déséchappe pas `/proc/swaps` (`\040`) : un chemin avec espace n'est pas reconnu | TASK-019 | fait — déséchappement de `\040` par `index`, identique sous gawk et mawk (vérifié dans les deux) |
| [x] | A28 | P3 | Groupe `swap-fstab` fragile : dépend de l'absence de `/dev/sdc` dans le conteneur | TASK-019 | requalifié limite assumée — dépend du `/proc/swaps` du noyau hôte, non maîtrisable depuis le test ; le groupe rougirait bruyamment, jamais à tort |
| [x] | A29 | P3 | Branche morte dans `configure-logging.sh` : `[dry-run] Créerait …` inatteignable | TASK-011, backlog | vérifié sans objet — la branche est atteignable quand le socle n'a pas pu créer le répertoire (`mkdir` en échec), ce que A19 rend possible |
| [x] | A30 | P3 | `update-system.sh:133` : `\|\| true` laisse une chaîne vide au `[ -gt 0 ]` — vérifier si le §8 des points en suspens l'a bien fermé | TASK-018 | vérifié sans objet — `grep -c` imprime 0 même en échec, `restant` n'est jamais vide |
| [x] | A31 | P3 | Septième issue de `check-services.sh` (« unité non chargée ») documentée, jamais éprouvée | points en suspens §12 | fait — groupe 7 bis de `check-services.test.sh` : unité invalide, LoadState=bad-setting, code 1, retrait vérifié |
| [x] | A32 | P3 | `create-network.sh` : règle de nom à deux caractères empruntée aux conteneurs, non vérifiée pour les réseaux | TASK-032 | fait — Docker accepte un nom d'un caractère : motif `[a-zA-Z0-9][a-zA-Z0-9_.-]*` |
| [x] | A33 | P3 | Test de `configure-cron.sh` : `demon_cron_present()` duplique `chemin_demon_cron()`, les deux peuvent dériver | TASK-009 | requalifié limite assumée — duplication voulue et commentée : le test ne doit pas dépendre de la fonction qu'il éprouve |
| [x] | A34 | P4 | `tests/README.md` fait 84 Ko : à scinder par niveau | points en suspens §14 | décision 44 — non scindé |
| [x] | A35 | P4 | `tests/README.md` en retard sur la couverture de `configure-swap.sh` (section 5, groupe 3 bis) | TASK-017 | vérifié sans objet — `tests/README.md` décrit déjà les sections 5 et 6 et les groupes « 3 bis » et « 3 ter » |
| [x] | A36 | P4 | `recensement-substitutions.md` ignore `check-disk.sh`, `check-memory.sh`, `check-services.sh` | points en suspens §13, TASK-021 | fait — §10 bis du recensement : 23 sites des trois diagnostics, aucun nu ; README du domaine à jour |
| [x] | A37 | P4 | README de `configure-cron.sh` muet sur le contrôle secondaire du répertoire | TASK-009 | fait — le README décrit le contrôle de `/etc/cron.d` et son exception `--dry-run` |
| [x] | A38 | P4 | En-têtes de colonnes sans accents : `ETAT`, `RESEAUX` (`list-containers.sh`), `CATEGORIE`, `RECUPERABLE` (`docker-disk-usage.sh`) | relectures TASK-033, 034 | fait — ÉTAT, RÉSEAUX, CATÉGORIE, RÉCUPÉRABLE, « Monté sur » ; test mis à jour |
| [x] | A39 | P4 | Commit d'activation `chore: TASK-XXX en cours` fait sur `master`, alors que `regles.md` §9 interdit tout commit de travail sur `master` : règle à préciser | TASK-033, 034 | fait — `regles.md` §9 : activation et clôture sur `master`, jamais le code |
| [x] | A40 | P3 | Sous `enable_full_logging`, chaque message et chaque sortie de `run_logged` sont écrits deux fois dans le journal (par `_journaliser` ou `tee`, et par la capture complète) | test de A23 | fait — `_journaliser` et `run_logged` n'écrivent plus sous capture complète ; testé |
| [ ] | A41 | P2 | L’agent `sonnet` lancé sans interface échoue : « OAuth session expired and could not be refreshed » ; le Claude Code de `user` doit être reconnecté, ce que l’orchestrateur n’a pas le droit de faire | TASK-037 | `user` : relancer `claude` et se reconnecter ; en attendant, les tâches `sonnet` passent à `deepseek` |
| [x] | A42 | P2 | Le figement du fichier de cas dès le premier commit bloque l’agent quand son propre test est mal construit (TASK-035, TASK-036 : arrêts sur des erreurs de test) | TASK-035, 036 | fait — le test reste corrigeable jusqu’au premier PASSE, sans retrait d’assertion ; `/tache` compte les assertions |
| [x] | A43 | P2 | Aucun contrôle automatique ne vérifie `set -Eeuo pipefail` en ligne 2 ni la longueur des fichiers : seule la relecture Opus les voit (TASK-025 : 266 + 465 lignes, `set` en ligne 11) | TASK-025 | fait — TASK-011 vérifie que `set -Eeuo pipefail` est la première commande (commentaires admis au-dessus, norme des scripts existants) ; `juger.sh` signale toute longueur au-delà de 150 |
| [x] | A44 | P4 | `manage-users.sh` (179 lignes) et surtout son fichier de cas (419 lignes) dépassent la sobriété visée malgré une relance : factoriser la reconnaissance d’environnement dans `tests/lib`, fusionner les blocs if/ok/ko | TASK-025 | fait — TASK-040 : script 179 → 150 lignes, comportement identique (relu) ; fichier de cas 419 → 296 lignes, vérifications 125 → 138 |
| [x] | A45 | P1 | `ASSUME_YES` héritée de l’environnement : un script lancé par un parent qui l’exporte confirme tout seul (`confirm` de `lib/common.sh` la lit sans qu’elle ait été posée par `--yes`) — vu sur `reboot-system.sh`, probable sur tous les scripts à confirmation | relecture TASK-026 | décision 45 — le socle garde l'héritage (contrat testé) ; les scripts destructifs posent `ASSUME_YES=false` avant leurs options : fait pour `docker-cleanup.sh`, demandé à TASK-026 pour `reboot-system.sh` |
| [ ] | A46 | P3 | `configure-firewall.sh` n'est prouvé qu'avec un faux `ufw` : jamais exécuté sur une machine réelle avec ufw actif, ni avec sshd écoutant sur plusieurs ports ; la seconde version et le correctif IPv6 de l'orchestrateur n'ont pas été relus par Opus | TASK-045 | à éprouver sur une VM jetable, session SSH ouverte, avant usage en production |
| [x] | A47 | P2 | Jetons de relecture perdus quand la session s'interrompt entre la relecture et la clôture : `/tache` ne les consigne qu'à l'étape 8 (TASK-045 : « non relevé ») | TASK-045 | fait — [TASK-048](../completed/TASK-048.md) : l’étape 6 de `/tache` écrit une ligne `relecteur` dans `agents.tsv` dès le retour du sous-agent ; l’étape 8 la relit |
| [ ] | A48 | P2 | `configure-ssh.sh` n'est prouvé qu'avec de faux `sshd` et `systemctl` : jamais exécuté sur une machine réelle ; l'effet réel n'est pas relu par `sshd -T` — un `PasswordAuthentication yes` placé dans `sshd_config` avant la ligne `Include`, ou un fichier `sshd_config.d/0x-*.conf` lu avant `10-mgnetworking.conf`, l'emporterait sans signal ; la version corrigée n'a pas été relue par Opus | TASK-046 | à éprouver sur une VM jetable, session SSH ouverte ; envisager le contrôle `sshd -T` que TASK-047 prévoit pour `permitrootlogin` |
| [ ] | A49 | P3 | `configure-ssh.sh --dry-run` lancé sans root ne peut pas lire `~compte/.ssh/authorized_keys` et répond « Aucune clé publique », ce qui est faux | relecture TASK-046 | distinguer « illisible » d'« absent » en dry-run |
| [ ] | A50 | P3 | `configure-ssh.test.sh` : 274 lignes (cible 150) ; deux cas redondants — `ASSUME_YES` hérité sans terminal (bloqué par `[ -t 0 ]` quoi qu'il arrive) et « Port absent » (couvert par l'égalité exacte du dépôt) — et rien ne vérifie que `sshd_config` reste intact | relecture TASK-046 | resserrer lors d'une passe de sobriété |
| [ ] | A51 | P2 | `disable-root-login.sh` juge la conformité au seul contenu de `05-mgnetworking-root.conf` (l. 100, 113) : si un `PermitRootLogin yes` est ajouté plus tard dans `sshd_config` avant la ligne `Include`, la relance rend 0 « déjà conforme » sans repasser par `sshd -T`, alors que root peut se connecter | relecture TASK-047 | contrôler `sshd -T` aussi quand le fichier est déjà conforme |
| [ ] | A52 | P3 | `disable-root-login.sh` appelle `sshd -T` sans `-C` (l. 138) : un bloc `Match` qui rétablit `PermitRootLogin yes` pour une adresse ou un utilisateur passe inaperçu | relecture TASK-047 | vérifier aussi les blocs `Match` présents, ou le signaler |
| [ ] | A53 | P4 | `disable-root-login.test.sh` (l. 125-128) : le cas `ASSUME_YES` hérité avec terminal ne vérifie pas qu'aucun fichier n'est déposé après la réponse « n » | relecture TASK-047 | ajouter l'assertion d'absence du dépôt |
| [ ] | A54 | P4 | `disable-root-login.sh` : messages trop longs aux l. 72 et 141 | relecture TASK-047 | raccourcir lors d'une passe de sobriété |
| [ ] | A55 | P2 | `disable-root-login.test.sh` : le faux `sshd -T` rend une valeur imposée sans lire le fichier déposé, donc l'ordre de priorité (préfixe 05, directive placée avant l'`Include`) n'est jamais éprouvé — rejoint A48 ; le cas sans terminal (l. 123) ne prouve pas la décision 45, seul le cas « script » la prouve | relecture TASK-047 | éprouver sur une VM jetable avec le vrai sshd, session SSH ouverte (comme A48) |
| [ ] | A56 | P3 | `configure-fail2ban.sh` (l. 83-87) redémarre un service simplement arrêté alors que ni paquet, ni fichier, ni activation n'ont changé : défendable (la prison doit être chargée), mais écart à la lettre du critère « redémarré seulement si quelque chose a changé » de TASK-044 | relecture TASK-044 | trancher : amender le critère ou n'agir que sur changement |
| [ ] | A57 | P2 | `configure-fail2ban.sh` : la version corrigée après relecture (attente du démon, rattrapage après `enable` raté, `require_cmd fail2ban-client`, fichier de cas passé de 146 à 219 lignes) n'a pas été relue par Opus ; prouvée seulement avec de faux `apt-get`, `systemctl` et `fail2ban-client`, jamais avec le vrai démon | TASK-044 | relire le diff 6906255..6807391 lors d'une passe de sobriété ; éprouver sur une VM jetable (profil `systemd`) |
| [ ] | A58 | P4 | `configure-fail2ban.test.sh` : 219 lignes (cible 150), justifiées par les huit retours de relecture | TASK-044 | resserrer lors d'une passe de sobriété |
| [ ] | A59 | P2 | Claude Code garde en cache la définition d'un sous-agent lue la première fois dans une session : la révision de `conducteur-tache.md` (relecture lancée par le conducteur, outil `Agent`) n'a pas été prise en compte pendant TASK-047 et TASK-044, où la session a lancé le relecteur | TASK-049 | à constater dans une session neuve : le conducteur doit rendre `RELANCER` ou `CLOSE` après sa propre relecture, et écrire lui-même la ligne `relecteur` |
| [ ] | A60 | P2 | La boucle sans surveillance suppose un mode de permissions qui laisse passer `git commit`, `juger.sh` et les tests en conteneur ; `.claude/settings.json` ne les autorise pas. Dans un mode plus strict, une demande de permission du conducteur arrête la boucle sans le signaler | relecture TASK-049 | décider avec `user` : compléter la liste `allow`, ou limiter la boucle au mode automatique de Claude Code |
| [ ] | A61 | P3 | Écarts du conducteur observés sur ses deux premières tâches : activation en deux commits (TASK-047), « prochain identifiant libre » du registre non avancé après A56-A58 (TASK-044, rattrapé à la clôture de TASK-049), TASK-047 annoncée à tort comme dernière de `Linux/Security` | TASK-049 | surveiller sur les tâches suivantes ; préciser `conducteur-tache.md` si l'écart se répète |
| [ ] | A62 | P2 | `verify-k3s.sh` : la version corrigée après relecture (état du service sur une ligne malgré le code 3 de `systemctl is-active`, rubrique « aucun événement Warning » distincte de l'API muette, fichier de cas passé de 34 à 38 vérifications) n'a pas été relue par Opus ; prouvée seulement avec de faux `k3s` et `systemctl`, jamais contre un vrai cluster | TASK-050 | relire le diff fea10ba..c9abdc9 lors d'une passe de sobriété ; éprouver après `install-k3s.sh` (TASK-051) sur une VM jetable |
| [ ] | A63 | P4 | `orchestration/schema/orchestration.svg` (et son PNG) ne montre pas le sous-agent `conducteur-tache` introduit par TASK-049 | session, clôture TASK-050 | mettre le schéma et son export PNG à jour |
| [ ] | A64 | P2 | `install-k3s.sh` : la version corrigée après relecture (garde `/.dockerenv` du fichier de cas, activation ratée et service inactif nommés en 1, faux `systemctl` fidèle, échec de `ss` bloquant, `--proto '=https'`, variables `INSTALL_K3S_*`, `K3S_URL` et `K3S_TOKEN` héritées neutralisées, 49 → 78 vérifications) n'a pas été relue par Opus, seulement lue par le conducteur sur le bloquant et les deux majeurs ; longueurs 164 + 235, au-delà de la cible de 150 ; prouvée seulement avec de faux `curl`, installateur, `k3s`, `systemctl` et `ss`, jamais sur une vraie machine | TASK-051 | relire le diff 9a7ad9c..3149730 lors d'une passe de sobriété ; éprouver sur une VM jetable avec `verify-k3s.sh` (A62) |
| [ ] | A65 | P3 | `install-k3s.sh` : `ss` absent n'émet qu'un `[WARN]` et saute le contrôle des ports 6443, 80 et 443, alors qu'un `ss` en échec bloque ; seuils de 5 120 Mo de disque et 512 Mo de mémoire repris de la documentation K3s sans vérification dans le dépôt | TASK-051 | décider si `ss` passe dans `require_cmd` ; vérifier les seuils à la source |
| [ ] | A66 | P3 | Commit de relance de l'agent DeepSeek mal formé : titre `fix: retours de relecture (RETOURS-TASK-051.md)` au lieu de `(TASK-051)`, sans ligne `Tâche : TASK-051`, attribution `Claude Code` ; l'étape 5 de `/tache` repère ce commit par son titre | TASK-051 | préciser dans la consigne de relance de `lancer-agent.sh` le titre et la ligne `Tâche :` attendus |

## Suivi, pas des défauts

- **Parallélisme des agents** : ouvert après trois tâches sans incident — 2 sur 3 (TASK-033, TASK-034) ; dépend de A06.
- **`git push`** : groupé en fin de domaine Docker ; rien n'est poussé depuis le 2026-09-13.

## Méthode du recensement du 2026-09-15

Pour vérifier que rien n'a été oublié sans relire chaque problème : sources lues
intégralement, et ce qui en est sorti.

| Source | Lu | Versé ici | Écarté (tranché ou limite assumée) |
|---|---|---|---|
| `docs/points-en-suspens.md` | 14 points | 7 ouverts (§6, 9, 10, 11, 12, 13, 14) | 7 traités ou tranchés |
| `tasks/backlog.md` §3 | 16 entrées | 10 | 6 tranchées ou décidées |
| sections « Réserves » des rapports | 19 rapports (TASK-002 à 034) | 19 lignes | voir ci-dessous |
| `orchestration/README.md`, points ouverts | 7 points | 5 | 2 passés en suivi |
| `orchestration/mesures/journal.md` | constats | 1 (A08) | mesures, pas des défauts |
| relectures TASK-033 et 034 non corrigées | 2 | 1 (A38) | — |
| `TODO` / `FIXME` dans le code | 0 | — | — |

Une même anomalie citée par plusieurs sources ne compte qu'une ligne.

**Limites assumées, non versées** — des faits vrais, mais sans correction possible
ou utile : `swapon` exige `CAP_SYS_ADMIN` (TASK-017 à 019) ; portabilité hôte
Linux ou macOS, `SIGINT`, `--reconstruire` manuel, arrêt du démon pendant un
`docker run` (TASK-002) ; relecteurs n'ayant pas relancé toutes les suites
(TASK-003, 004, 013) ; idempotence réelle de `configure-swap.sh` et
`update-system.sh` hors conteneur (TASK-004) ; `find -newer` hors `/depot`
(TASK-004) ; `tests/run.sh` rend 3 sur l'hôte Windows (TASK-004) ; preuves de
forme périssables de TASK-011 (décision 13) ; `export ASSUME_YES` hors neutralité
stricte, validé (TASK-011) ; décompte des sauts par convention, nom `saute`,
`saute_par_nature` de TASK-011:224, branche `INDISPO)` jamais empruntée
(TASK-012, 013) ; détails de construction de TASK-014 ; mutations et bornes
d'aide de TASK-016 ; cas non couverts de TASK-017 et 019 ; `hostnamectl`
non applicable (TASK-020) ; `server.env` réel et seuil réel non atteignables en
conteneur, erreur arithmétique rattrapée par l'invariant (TASK-021) ; sursis de
60 s (TASK-027) ; conformité sans `jq` jugée au texte, taille de TASK-030 ;
témoin temporaire dans `logs/` (TASK-002).

Si `user` voit un problème absent de ce registre et de cette liste, il manque une
ligne : l'ajouter avec le prochain Axx.
