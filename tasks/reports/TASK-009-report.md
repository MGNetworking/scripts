# TASK-009 — Rapport d'exécution

## Statut

COMPLETED

**Première tâche métier du dépôt.** Toutes les précédentes construisaient
l'outillage : harnais, conteneur, tests, sémantique des codes. Celle-ci produit
un script d'administration destiné à un serveur réel.

## Objectif

Installer la planification des scripts destinés à tourner sans humain, par un
fichier `/etc/cron.d/mgnetworking`. Origine :
[docs/points-en-suspens.md](../../docs/points-en-suspens.md) §1, soulevé le
2026-08-26.

## Travail réalisé

- `Linux/System/configure-cron.sh` — dépose `/etc/cron.d/mgnetworking`, sur le
  modèle de `configure-logging.sh` ;
- `tests/integration/configure-cron.test.sh` — **158 vérifications**, 5 non
  exécutées, 0 échec ;
- `config/server.env.example` — `SRV_CRON_UPDATE_SYSTEM` ;
- `Linux/System/README.md`, `README.md` — documentation ;
- `docs/points-en-suspens.md` — point 1 marqué traité, contenu conservé.

Ligne produite, mesurée dans le conteneur :

```text
0 4 * * 1 root /bin/bash /depot/Linux/System/update-system.sh --yes >/dev/null
```

## Commandes exécutées

| Commande | Code | Résultat |
|---|---|---|
| `tests/run.sh lint` | **0** | 24 fichiers, `shellcheck` NON EXÉCUTÉ sur l'hôte |
| `run-in-container.sh -- tests/run.sh lint` | 0 | `shellcheck` présent, 0 erreur, 2 avertis (Synology hérités) |
| `run-in-container.sh -- tests/run.sh integration` | **0** | 158/0/5 et 104/0/5 |
| `run-in-container.sh -- bash -c '…--dry-run'` | **0** | aperçu produit, rien d'écrit |
| `configure-cron.sh -y` sans démon cron | 1 | `Prérequis manquant.` — fichier non déposé |

## Validations

| Validation | Résultat |
|---|---|
| `tests/run.sh lint` | **PASS** |
| `run-in-container.sh -- tests/run.sh integration` | **PASS** |
| `run-in-container.sh -- bash -c '…configure-cron.sh --dry-run'` | **PASS** |

## Les trois contraintes de cron, tenues

Établies dans le point en suspens §1, épinglées par des assertions :

| Contrainte | Preuve |
|---|---|
| **pas de `sudo`** — champ utilisateur après l'horaire | décomposition champ par champ : `root` en 6ᵉ position, `assert_absent "sudo"` sur la ligne |
| **`--yes` obligatoire** — cron n'a pas de terminal | `assert_egal "--yes >/dev/null" "$reste"` |
| **`stdout` jetée, `stderr` conservée** | trois assertions négatives : `2>&1` sur la ligne, `2>&1` sur tout le fichier, `2>/dev/null` |

La troisième est **la plus importante du fichier**. `stderr` est la seule alerte
en cas d'échec tant que le point en suspens n°2 n'est pas traité : la jeter
rendrait un serveur silencieusement non mis à jour pendant des mois.

Le relecteur l'a éprouvée par mutation, sur un dépôt reconstruit dans `/tmp` du
conteneur : `2>&1` réinjecté → **4 échecs, 145 réussites**. Elle mord.

## Corrections automatiques

**Tentative 1 — trois défauts relevés par le relecteur, tous dans le périmètre.**

*Diagnostic* : le script était fautif, pas les tests. Ceux-ci mesuraient
correctement le comportement d'alors — c'est ainsi qu'on l'a vu.

**1. La garde de dépendance était morte.** Elle testait `[ ! -d /etc/cron.d ]`.
Or `/etc/cron.d` est fourni par **`e2fsprogs`**, pas par `cron` — vérifié par
`dpkg -S` dans le conteneur. Le répertoire existe donc sur toute Debian 12 sans
démon cron, et le script déposait le fichier en annonçant
`[SUCCESS] Planification installée` sur un serveur où rien ne s'exécuterait
jamais.

Verdict du relecteur : *« le choix est défendable dans son intention, mais
appliqué à la mauvaise garde. `configure-logging.sh` teste le binaire ;
`configure-cron.sh` testait le répertoire, c'est-à-dire rien. »*

Corrigé : `chemin_demon_cron()` est branchée sur la décision. Démon absent hors
`--dry-run` → `die`. Démon absent avec `--dry-run` → avertissement et aperçu,
code 0 — la dissymétrie est voulue et documentée.

**2. La documentation décrivait un comportement que le code n'avait pas.**
`Linux/System/README.md` affirmait « *il s'arrête en indiquant `apt-get install
cron`* ». C'était faux. Corrigé, et le relecteur a revérifié **phrase par
phrase contre le comportement mesuré**, pas contre le code.

**3. La ligne cron n'aurait pas fonctionné sur un vrai serveur.**
`git ls-files -s` donne **`100644`** pour les sept scripts : sur un déploiement
issu d'un `git clone`, `update-system.sh` n'est pas exécutable et la tâche
planifiée rendrait 126 à chaque passage.

**Le conteneur ne pouvait pas le voir** — le montage Docker Desktop force
`0777`. Corollaire relevé par le testeur : la troisième validation de la tâche
ne passait que grâce à ce montage.

Corrigé par `/bin/bash <chemin>` dans la ligne déposée : elle fonctionne quel que
soit le bit d'exécution. L'avertissement subsiste, requalifié — il signale
désormais qu'un lancement à la main échouera, non que la planification est
inopérante.

**Ajustement des tests, après la correction du script et jamais l'inverse.**
Huit assertions épinglaient l'ancien comportement. Le contrat avait changé, pas
la mesure : c'est la seule justification qui autorise à toucher un test.

Le rédacteur des tests a de plus trouvé qu'**une de ses propres assertions
passait pour la mauvaise raison** — le bloc « `/etc/cron.d` absent » affirmait
`Prérequis manquant`, mais la garde du démon parlait avant celle du répertoire.
Il pose désormais un faux `/usr/sbin/cron` le temps du bloc, et **vérifie son
retrait**.

Bilan : **140 → 158 réussites**, aucune assertion supprimée ni affaiblie. Le
relecteur confirme : *« les huit ajustements vont tous dans le sens du
durcissement »*.

## Tentatives

1 / 5

## Critères d'acceptation

Les dix, démontrés par exécution :

- [x] `SHELL`, `PATH`, une entrée par tâche
- [x] `root` après l'horaire, jamais `sudo`
- [x] `--yes` — cron n'a pas de terminal
- [x] `stdout` jetée, `stderr` conservée
- [x] `--dry-run` affiche sans rien modifier — empreinte de tout `/etc` **et** `find -newer` sur sept arborescences
- [x] seconde exécution sans modification — protocole `P0 != A` puis `A == B`
- [x] refus sans privilège root
- [x] horaire configurable, ligne de commande primant
- [x] chemin de déploiement détecté, non écrit en dur — bac à sable prouvant que la ligne suit le dépôt réel
- [x] `--help` documente le tout

## Validation finale

PASS

## Les deux décisions laissées ouvertes par l'énoncé

**Horaire : `0 4 * * 1`** — tous les lundis à 4 h. Valeur déjà écrite dans le
point en suspens, donc rien d'inventé. Hebdomadaire comme la rotation logrotate,
hors heures d'activité, en début de semaine : cinq jours ouvrés pour réagir à ce
qui aurait cassé. Surchargeable par `SRV_CRON_UPDATE_SYSTEM`, puis par
`--horaire`.

**Chemin de déploiement : aucun.** `SCRIPTS_ROOT` est interpolé à l'écriture.
`/opt/mgnetworking` n'est qu'un exemple du README ; l'écrire en dur casserait
tout autre déploiement.

`/bin/bash` en chemin absolu plutôt que `bash` nu : pour ne pas dépendre de la
ligne `PATH=` du même fichier, et parce que `require_os debian ubuntu` verrouille
la cible où le paquet `bash` est `Essential: yes`.

## Réserves

- **`shellcheck` absent de l'hôte** : `tests/run.sh lint` ne vérifie que la
  syntaxe sur cette machine. Le relecteur a comblé la lacune par un passage
  conteneur — 0 erreur, les deux avertissements portant sur les scripts Synology
  hérités ;
- **5 cas non exécutés**, tous déclarés : cron réellement lancé (pas d'init dans
  le profil `debian`), le bit d'exécution réel dans le dépôt (le montage force
  `0777`), le rechargement par cron, le rejet effectif d'un nom pointé ou d'un
  fichier exécutable, un chemin de dépôt contenant une espace ou un `%` ;
- **le faux `/usr/sbin/cron` prouve que `chemin_demon_cron()` accepte un
  exécutable à ce chemin, pas qu'un vrai démon lirait le fichier.** Seul un
  profil `systemd` le permettrait ;
- `demon_cron_present()` du test duplique la logique de `chemin_demon_cron()` —
  assumé et commenté, mais les deux peuvent dériver ;
- **le README ne mentionne pas le contrôle secondaire du répertoire**, qui
  provoque lui aussi un arrêt hors `--dry-run`. Silence, non contradiction ;
- **piège d'usage documenté** : sur une machine sans cron,
  `configure-cron.sh --dry-run && configure-cron.sh -y` donne un vert suivi d'un
  code 1. Dissymétrie voulue, épinglée des deux côtés pour qu'elle ne dérive pas.

## Écarts de périmètre déclarés

- **cinq lignes ajoutées au §2 de `points-en-suspens.md`**, hors périmètre
  littéral. La ligne déposée ne jetant que `stdout`, la première piste du §2 est
  en place *de fait* ; laisser le texte inchangé l'aurait rendu faux. Le choix
  entre les trois pistes reste entier. Le relecteur : *« tolérable, mais c'est
  une bordure »* ;
- l'option s'appelle `--horaire`, en français, par cohérence avec `--profil` et
  `--reconstruire` déjà présents.

## Défauts révélés hors périmètre

**`update-system.sh` et les six autres scripts sont versionnés en `100644`.**
La correction retenue contourne le problème pour la tâche planifiée, elle ne le
résout pas : lancer un script du dépôt à la main après un `git clone` échouera
toujours. La cause racine — les modes Git — est hors du `scope` de cette tâche.

## Git

Branche : `agent/TASK-009`.

## Résumé

Le dépôt sait planifier ses propres scripts. C'est modeste en soi — un fichier
de six lignes dans `/etc/cron.d` — mais c'est la première fois que toute la
chaîne sert à autre chose qu'à se construire elle-même.

Elle a servi. Deux défauts sérieux ont été trouvés avant d'atteindre un serveur :
une garde de dépendance qui ne gardait rien, et une ligne cron qui aurait échoué
à chaque passage sur un déploiement standard. Le second était invisible dans
l'environnement de test, dont le montage masque les permissions — c'est le
testeur qui est allé le chercher hors du montage.

Et une documentation qui promettait un arrêt qui n'avait pas lieu. Trois mois
plus tard, personne n'aurait su que le script mentait.
