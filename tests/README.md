# tests/ — validations du dépôt

## 1. Ce que ce dossier prouve

Ce répertoire porte la **preuve**. Tant qu'une commande d'ici n'a pas réussi, rien
n'est démontré : ni par la lecture du code, ni par la conviction d'un modèle, ni par
« ça a marché sur le serveur ». Une validation non lancée vaut `NON EXÉCUTÉ`, jamais
`PASS` ([regles.md](../orchestration/regles.md) §10).

Trois niveaux de preuve, toujours nommés ; aucune ne se présente plus forte qu'elle n'est :

| Preuve | Ce qui tourne | Ce qu'elle établit |
|---|---|---|
| **simulé** | faux binaires en tête de `PATH` | la logique du script, pas l'outil réel |
| **conteneur** | l'outil réel dans un conteneur jetable (§5) | le comportement sur un Debian neuf |
| **machine** | constaté sur un VPS par `user` | le comportement en service |

Les niveaux de test, découverts par leur dispatcher en `maxdepth 1` :

| Niveau | Contenu | Où il tourne |
|---|---|---|
| `lint` | `bash -n` sur tous les `.sh`, `shellcheck` si disponible | hôte ou conteneur |
| `unit` | fonctions de `lib/common.sh` — `tests/unit/<sujet>.test.sh` | conteneur `debian` |
| `integration` | exécution, `--dry-run`, idempotence — `tests/integration/<sujet>.test.sh` | conteneur `debian` |
| `environment` | services, `systemctl`, init réel — `tests/environment/<sujet>.test.sh` | conteneur `systemd` |
| `acceptance` | critères d'une tâche — `tests/acceptance/TASK-0xx-<sujet>.sh` | selon la tâche |

Un niveau s'ajoute en déposant son dispatcher au chemin que donne `tests/run.sh --liste`.

## 2. Lancer

```bash
tests/run.sh                  # tous les niveaux implémentés
tests/run.sh lint             # un niveau
tests/run.sh --liste          # ce qui existe et ce qui manque
tests/lint.sh --strict        # les scripts hérités deviennent bloquants
tests/env/run-in-container.sh -- tests/run.sh                                 # référence
tests/env/run-in-container.sh --profil systemd -- tests/run.sh environment
```

Un seul point d'entrée : la validation d'une fiche est la commande qu'un humain tape.
Sur l'hôte, seule l'analyse statique s'exécute ; dans le conteneur, lancer `tests/run.sh`
plutôt qu'un dispatcher de niveau, pour transmettre un verdict global.

- `integration` et `environment` **modifient le système** : jamais hors conteneur.
  Leurs fichiers de cas ne modifient rien tant qu'ils n'ont pas reconnu un système
  jetable (`/.dockerenv`, cgroup de conteneur ou `MGNET_TEST_JETABLE=1`).
- **Jamais `integration` sous le profil `systemd`** : plusieurs de ses assertions
  supposent l'absence d'init et rougiraient sans défaut.
- `shellcheck` est absent de l'hôte : `tests/run.sh lint` y annonce `NON EXÉCUTÉ` ;
  la preuve est `tests/env/run-in-container.sh -- tests/run.sh lint`.
- `SC1090` et `SC1091` sont exclus : le chemin de `lib/common.sh` n'est résolu qu'à
  l'exécution ([architecture-technique.md](../docs/architecture-technique.md)).
- Scripts hérités (`Synology/Plex/organize-series.sh`, `Synology/Plex/update-plex.sh`) :
  tolérance sur le style (`WARN`), jamais sur la syntaxe (`bash -n` reste bloquant).

**CI et Molecule** n'existent pas encore : ils arrivent avec le squelette `Ansible/`
(TASK-080) et le premier rôle (TASK-081), qui documenteront leur lancement.

## 3. Écrire un fichier de cas

Mêmes conventions que le dépôt : en-tête en trois lignes, `lib/common.sh`, messages
préfixés, français. Squelette :

```bash
source "$SCRIPTS_ROOT/tests/lib/assert.sh"

titre "1. Refus d'une option inconnue"
assert_code 2 "$CODE" "option inconnue : code 2"
saute_par_nature "cas systemd" "le profil debian n'a pas systemd"
saute_indisponible "lint conteneurisé" "le démon Docker ne répond pas"
bilan "configure-ssh.sh"
```

`tests/lib/assert.sh` fournit `titre`, `ok`, `ko`, `saute`, `saute_par_nature`,
`saute_indisponible`, `assert_code`, `assert_code_non_nul`, `assert_egal`,
`assert_non_vide`, `assert_contient`, `assert_absent` et `bilan`. Bash pur, sans
framework ; elle ne pose ni `set -Eeuo pipefail` ni `trap`.

**Règles durables**

1. Un test qui ne peut pas s'exécuter le dit : jamais de réussite silencieuse.
2. On ne corrige jamais un test pour le faire passer : neutraliser une assertion,
   ajouter `|| true` ou retirer `set -e` vaut échec ([regles.md](../orchestration/regles.md) §12).
3. Une idempotence se prouve sur un état neuf, par deux exécutions : empreinte
   `P0 → A → B`, en exigeant `A == B` **et** `P0 != A` — sinon elle est mesurée à vide.
4. Chaque assertion d'absence est encadrée d'une garde qui prouve que le flux capturé
   contient ce qu'on y attend ; chaque stub, d'une garde de contraste sans lui.
5. Un décompte de lignes se mesure sur son site, jamais repris d'un autre ni déduit.
6. Une correction se prouve par mutation : le script muté doit faire rougir une assertion.
7. « Inatteignable » ne s'écrit pas : « je n'ai pas trouvé comment l'atteindre », en
   `NON EXÉCUTÉ`. Un binaire homonyme en tête de `PATH` met en échec toute commande
   externe : `require_cmd` prouve qu'elle existe, pas qu'elle réussit.
8. Un fichier de cas qui modifie un service restitue l'état, vérifie la restitution et
   pose son filet avant la première modification.
9. **Ne jamais créer `tests/lib/common.sh`** : la résolution en trois lignes le
   trouverait avant le socle, et tous les scripts de `tests/` le chargeraient.
10. Un fichier de cas destiné à tourner **dans** le conteneur va dans
    `tests/acceptance/interne/` ; seul son pilote, au premier niveau, le lance.
11. Une fonction qui appelle `exit` (`die`, `require_root`, `load_config`…) se teste dans
    un processus `bash` neuf : un sous-shell hérite de la garde anti-double-chargement.

**Faux binaires.** Un faux binaire est un **fichier ordinaire**, créé par `cat >` dans
un répertoire du bac (`$BAC/...`) où **aucun lien symbolique** ne porte déjà son nom :
écrire à travers un lien écrit dans sa cible et remplace le vrai binaire du conteneur.
Un bac de liens et un répertoire de faux sont donc deux répertoires distincts. Le faux
n'appelle **jamais le vrai par son nom**, qui se résoudrait vers lui-même : le vrai se
relève avant toute retouche du `PATH` (`REEL="$(command -v timeout)"`) et s'appelle par
ce chemin absolu. `orchestration/outils/juger.sh` refuse un fichier de cas qui crée un
lien puis écrit par `>` au même chemin (`orchestration/outils/lien-ecrit.awk`, prouvé
par `tests/acceptance/TASK-072-faux-binaires.sh`).

**Qualifier un saut** — la qualification se relit, elle ne s'obtient pas par défaut :

| Fonction | Affiche | Compteur | Verdict |
|---|---|---|---|
| `saute` | `NON EXÉCUTÉ : …` (neutre, non relu) | `non_applicables` | 4 |
| `saute_par_nature` | `NON EXÉCUTÉ (non applicable par nature) : …` | `non_applicables` | 4 |
| `saute_indisponible` | `NON EXÉCUTÉ (environnement indisponible) : …` | `indisponibilites` | 3 |

- **non applicable par nature** : limite permanente et assumée — pas de systemd au
  profil `debian`, `swapon` sans `CAP_SYS_ADMIN`, outil absent d'une image minimale ;
- **environnement indisponible** : accident — démon Docker muet, `git` absent, outil
  installable non installé faute de réseau. **Une seule indisponibilité fait sortir le
  fichier en 3**, quel que soit le nombre de réussites.

Règle de prudence : dans le doute, indisponibilité. Un rouge à tort se voit, un vert à
tort non. Sous-affirmer ne produit jamais de faux vert : `assert.sh` décompte donc
« sans indisponibilité déclarée » ; seul un fichier dont tous les sauts sont qualifiés
peut écrire « non applicable(s) par nature » dans son propre bilan.

**Le bilan**, ordre fixe — échec, aucune réussite, indisponibilité, non exécutés ; `info` obligatoire :

```bash
info "Bilan TASK-0xx : $reussites réussie(s), $echecs échec(s), $non_executes NON EXÉCUTÉ(s) — dont $non_applicables non applicable(s) par nature et $indisponibilites indisponibilité(s)"
if [ "$echecs" -gt 0 ]; then die "TASK-0xx : $echecs critère(s) en défaut." 1; fi
if [ "$reussites" -eq 0 ]; then warn "aucune vérification exécutée — rien n'est prouvé."; exit 3; fi
if [ "$indisponibilites" -gt 0 ]; then warn "cas non produits faute d'environnement."; exit 3; fi
if [ "$non_executes" -gt 0 ]; then warn "vérification(s) NON EXÉCUTÉE(s)."; exit 4; fi
success "TASK-0xx : tous les critères vérifiés ($reussites)."
```

## 4. Codes de retour

**Un niveau ou un fichier de cas :**

| Code | Sens |
|---|---|
| 0 | tous les cas exécutés et réussis |
| 1 | au moins un cas en défaut |
| 2 | erreur d'usage |
| 3 | **rien n'est prouvé** : aucun cas n'a pu être exécuté, ou l'un n'a pu l'être faute d'environnement |
| 4 | cas exécutés réussis, d'autres non applicables **par nature** — la preuve est partielle, elle existe |

Le 4 n'ouvre pas de faux vert : il exige **au moins une réussite** et aucune
indisponibilité ; une suite intégralement sautée retombe sur 3.

**`tests/run.sh`** : 0 validation acquise (les 4 y sont traduits en réussite et
décomptés à l'écran), 1 un niveau a échoué, 2 erreur d'usage, 3 rien n'est prouvé —
niveau demandé non implémenté, niveau sans rien de vérifié, ou indisponibilité.
`tests/run.sh` **ne rend jamais 4** : autre chose que 0, la validation n'est pas acquise.

**`tests/env/run-in-container.sh`** : code de la commande transmis tel quel ; 2 usage ; 3
environnement indisponible (Docker, `timeout` en mode `systemd`, systemd qui ne démarre
pas) ; 4 échec de construction. Rien n'est alors exécuté ; `[ERROR]` lève l'ambiguïté.

**`tests/env/assurer-docker.sh`** : 0 le démon répond (en `--dry-run` : l'annonce est
faite, rien de plus), 2 usage, 3 démon indisponible.

## 5. Environnement conteneurisé

L'hôte Windows n'a ni `apt` ni `systemctl` : **aucun script d'administration ne s'y
exécute**. `tests/env/run-in-container.sh [--profil <nom>] [--reconstruire] [--dry-run] -- <commande>`
lance la commande telle quelle dans un conteneur neuf, dépôt monté en lecture-écriture
sur `/depot`, puis le détruit : aucun état ne survit. Un nettoyage manqué est signalé
en `[WARN]` sans changer le code.

| Profil | Image | Porte |
|---|---|---|
| `debian` | `tests/env/Dockerfile.debian`, `debian:12` minimale | `lint`, `unit`, `integration`, `acceptance` |
| `systemd` | `tests/env/Dockerfile.systemd`, `/sbin/init`, `--privileged`, `--tmpfs /run` | `environment` |

- Un profil `<nom>` est le fichier `tests/env/Dockerfile.<nom>` ; le label
  `mgnet.test.init="systemd"` choisit le lancement détaché avec attente du démarrage.
- Tout paquet ajouté porte sa justification dans le `Dockerfile` ; le dépôt n'est jamais
  copié dans l'image ; listes `apt` vidées : un script qui installe fait son `apt-get update`.
- Images et conteneurs sont préfixés `mgnet-test-` sans exception (regles.md §8) ;
  vérifier qu'il ne reste rien : `docker ps -a --filter 'name=mgnet-test-'`.
- Profil `systemd` : aucune assertion sur `systemctl is-system-running` ni sur le
  nombre d'unités en échec, l'état n'est pas déterministe ; un cas qui a besoin d'une
  unité en échec la fabrique. Témoin modifiable : `systemd-logind.service`. La garde
  mesure systemd (`/proc/1/comm`), jamais le nom du profil, et chaque fichier garde des
  cas exécutables sans systemd pour ne pas sortir en 3 sous `debian`.
- Jamais `reboot` ni `systemctl poweroff` dans le conteneur. Hors de portée, déclarés
  `NON EXÉCUTÉ` : `hostnamectl set-hostname` (`/etc/hostname` monté par Docker), `cron`.
- `tests/env/assurer-docker.sh`, appelé quand le démon ne répond pas, **attend** Docker
  Desktop, borné, sans l'arrêter ni le démarrer (`--demarrer` échoue depuis la session d'un
  agent) ; trace `$LOG_DIR/assurer-docker.log`. Docker Desktop tombé : relance à la main.
- Git Bash : conversion de chemins MSYS neutralisée ; CRLF dans `lib/common.sh` →
  `bad interpreter` (`git add --renormalize .`) ; `Permission denied` → `-- bash <script>`.
