# Points en suspens

Sujets identifiés pendant le développement et écartés pour ne pas interrompre la
production des scripts. À traiter avant la fin du chantier.

---

## 1. Mise en place de `update-system.sh` en tâche planifiée — traité

**Soulevé le** 2026-08-26.
**Converti en tâche le** 2026-08-27 : [TASK-009](../tasks/completed/TASK-009.md).
**Traité le** 2026-08-31 par TASK-009 : `Linux/System/configure-cron.sh`.
Le texte ci-dessous est conservé tel quel — il reste la référence du contenu
déposé. Les décisions prises sont consignées à la fin de la section.

Le script est destiné à tourner par `cron`. Trois éléments conditionnent son
fonctionnement dans ce cadre.

### Cron n'utilise pas `sudo`

Il lance directement sous l'utilisateur indiqué. Deux façons de faire :

```bash
sudo crontab -e     # crontab de root : tout y tourne en root
```

ou, préférable car explicite et versionnable, un fichier dédié :

```
# /etc/cron.d/mgnetworking
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

0 4 * * 1 root /opt/mgnetworking/Linux/System/update-system.sh --yes >/dev/null 2>&1
```

Le champ `root` placé après l'horaire remplace le `sudo`.

### `--yes` est obligatoire

Cron n'a pas de terminal. Sans cette option, le script attendrait une réponse à
la confirmation, indéfiniment.

### La sortie doit être redirigée

Cron envoie par courriel tout ce qu'un travail écrit. Sans `>/dev/null 2>&1`, la
sortie complète d'`apt` serait expédiée à chaque exécution — ou produirait des
erreurs si aucun serveur de messagerie n'est configuré. La trace est déjà dans
`/var/log/mgnetworking/update-system.log`.

**Reste à faire** : décider de l'emplacement de déploiement et de l'horaire,
puis écrire le fichier `/etc/cron.d/`. Éventuellement un script
`Linux/System/configure-cron.sh` qui l'installe, sur le modèle de
`configure-logging.sh`.

### Ce qui a été fait, et ce qui a été décidé

`Linux/System/configure-cron.sh` dépose `/etc/cron.d/mgnetworking` sur le modèle
de `configure-logging.sh` : lecture de l'état, comparaison, écriture seulement
si nécessaire, `--dry-run`, confirmation avant tout remplacement.

Les deux décisions que le point laissait ouvertes :

| Décision | Valeur retenue | Pourquoi |
|---|---|---|
| emplacement de déploiement | aucun — le chemin est résolu à l'exécution par `SCRIPTS_ROOT` | `/opt/mgnetworking` n'est qu'un exemple du README ; l'écrire en dur casserait tout autre déploiement |
| horaire | `0 4 * * 1`, tous les lundis à 4 h, surchargeable par `SRV_CRON_UPDATE_SYSTEM` puis par `--horaire` | hebdomadaire comme la rotation des journaux, hors des heures d'activité, et en début de semaine : cinq jours ouvrés pour réagir à ce qui a cassé |

Deux pièges de `/etc/cron.d`, vérifiés par le script plutôt que supposés : un nom
de fichier comportant un point est ignoré en silence, et un fichier qui
n'appartient pas à root ou qui porte le bit d'exécution est rejeté.

La redirection retenue est `>/dev/null` **sans** `2>&1` : c'est précisément ce
qui laisse ouverte la première piste du point n° 2 ci-dessous.

---

## 2. Un échec en tâche planifiée passe inaperçu

**Soulevé le** 2026-08-26, conséquence directe du point 1.
**Indexé au backlog le** 2026-08-27 : [tasks/backlog.md](../tasks/backlog.md) §3.
Les trois pistes ci-dessous s'excluent mutuellement — le choix est une décision
d'architecture, elle vous revient avant toute atomisation en tâche.

**Le problème.** Avec la sortie jetée vers `/dev/null`, une mise à jour qui
échoue ne prévient personne. Le code de retour est correct et le journal
contient l'erreur, mais rien ne remonte. Un serveur peut rester sans mise à jour
pendant des mois sans que cela se voie.

**État au 2026-08-31.** La ligne déposée par TASK-009 ne redirige que la sortie
standard : la première piste ci-dessous est donc en place à titre conservatoire,
sans avoir été choisie. Elle ne suffit pas — elle suppose un serveur de
messagerie configuré et un courriel effectivement lu. Le choix entre les trois
pistes reste entier.

**Pistes.**

- Ne rediriger que la sortie standard (`>/dev/null`) et laisser cron transmettre
  les erreurs par courriel.
- Un script de notification appelé en cas d'échec — courriel, webhook, ntfy.
- Un script de contrôle exécuté séparément, vérifiant la fraîcheur du dernier
  journal.

**Concerne** tous les scripts destinés à `cron` : `update-system.sh`,
`security-check.sh`, `backup-resources.sh`, `docker-cleanup.sh`.

---

## 3. Le harnais confond « non applicable » et « indisponible » — traité

**Soulevé le** 2026-08-29, pendant [TASK-012](../tasks/completed/TASK-012.md).
**Traité le** 2026-09-01 par TASK-013. Le texte ci-dessous est conservé tel
quel — il reste la mesure de référence du défaut. Ce qui a été fait est consigné
à la fin de la section.

**Le problème.** Depuis TASK-012, un fichier de cas qui réussit tout ce qu'il a
pu exécuter, en déclarant quelques cas non applicables, sort en 4 — preuve
partielle — et `tests/run.sh` traduit ce 4 en 0. Le garde qui empêche le faux
vert est qu'un 4 exige **au moins une réussite**.

Cette garantie est plus faible qu'elle n'en a l'air. Mesuré avec le démon Docker
coupé, Docker Desktop jamais arrêté :

```text
DOCKER_HOST=tcp://127.0.0.1:1 bash tests/acceptance/TASK-011-analyse-statique.sh
Bilan TASK-011 : 8 réussite(s), 0 échec(s), 21 NON EXÉCUTÉ(s)   → 4
tests/run.sh acceptance                                          → 0
```

72 % de la preuve avait disparu, le verdict restait vert. Sur `master` avant
TASK-012, ce même scénario rendait 3, donc 1 : c'est donc une régression sur
l'axe de l'honnêteté, consentie en échange de la levée d'un blocage qui frappait
toutes les tâches.

**La cause.** Les compteurs ne distinguent pas deux natures de saut :

| Nature | Exemple | Ce que ça devrait valoir |
|---|---|---|
| non applicable par nature | le profil `debian` n'a pas `systemd`, il ne l'aura jamais | 4 légitime |
| environnement indisponible | le démon Docker est coupé, la preuve existe mais n'a pas pu être produite | 3 — rien n'est prouvé |

Tout tombe aujourd'hui dans le même compteur, et quelques cas de préflight — qui
n'ont besoin de rien — suffisent à franchir le seuil.

**Le remède connu.** Un compteur `indisponibles` distinct de `non_executes`,
avec la règle `indisponibles > 0 → 3`. Il impose de revoir chaque appel `saute`
de chaque fichier de cas pour qualifier la nature du saut — ce que le périmètre
de TASK-012 excluait nommément.

**Concerne** tout le niveau `acceptance`, et les niveaux `unit`, `integration`
et `environment` le jour où ils existeront.

### Ce que TASK-013 a fait

Le remède connu a été appliqué tel quel : un compteur `indisponibilites`
distinct, alimenté par une seconde fonction de saut, avec la règle
`indisponibilites > 0 → 3`. Les vingt-cinq appels `saute` des trois fichiers de
cas ont été relus un par un et qualifiés ; le fichier de cas conteneurisé de
TASK-011 a reçu un verdict `INDISPO` en plus de son `SKIP`, faute de quoi ses
sauts arrivaient sans leur nature.

Le scénario mesuré ci-dessus donne désormais :

```text
DOCKER_HOST=tcp://127.0.0.1:1 bash tests/acceptance/TASK-011-analyse-statique.sh
Bilan TASK-011 : 8 réussite(s), 0 échec(s), 21 NON EXÉCUTÉ(s)
                 — dont 9 non applicable(s) par nature et 12 indisponibilité(s)  → 3
DOCKER_HOST=tcp://127.0.0.1:1 tests/run.sh acceptance                            → 3
```

Ni `tests/run.sh` ni `run-acceptance.sh` n'ont eu à changer de logique : ils
lisaient déjà le 3 sans le maquiller. Seuls leurs messages ont été précisés.

---

## 4. Les six contrôles de forme de TASK-011 n'ont plus d'objet

**Soulevé le** 2026-09-01, pendant TASK-013.

`tests/acceptance/TASK-011-analyse-statique.sh` §1 compare le diff de six
fichiers avec `REF_AVANT`, qui vaut `HEAD` par défaut. Les corrections de
TASK-011 étant commitées depuis le 2026-08-29, `git diff HEAD` est vide sur un
arbre propre : les six contrôles sortent en `NON EXÉCUTÉ` à chaque exécution, et
ne reviendront jamais d'eux-mêmes.

TASK-013 les a qualifiés **non applicables par nature** — rien n'a manqué, c'est
l'objet de la comparaison qui a disparu, par construction et tant que la
référence reste `HEAD` sur un arbre propre. La justification longue est écrite
sur place, dans le fichier de cas.

**La réserve.** C'est le seul saut du harnais dont la nature ait demandé à être
tranchée, et l'argument contraire s'entend : la preuve reste *rejouable* ici, en
fixant `TASK011_REF` sur le commit antérieur. Ce qui manque n'est pas une pièce
de l'environnement mais un paramètre du test — d'où la qualification retenue,
qui ne dépend pas du verdict qu'elle produit.

**Ce qu'il faudrait décider.** Trois voies, aucune ne relevant de TASK-013 :

- inscrire dans le fichier de cas le commit de référence réel, ce qui rendrait
  les six contrôles exécutables à nouveau — mais gèlerait un identifiant de
  commit dans un test ;
- retirer le §1, dont `tests/README.md` §1 annonce déjà qu'il disparaîtra avec
  TASK-011, le niveau `integration` étant le domicile durable de ces preuves ;
- le laisser tel quel, six `NON EXÉCUTÉ` visibles à chaque exécution.

**Concerne** `tests/acceptance/TASK-011-analyse-statique.sh` §1, et tout futur
fichier de cas qui prétendrait contrôler un diff après son commit.
