# Points en suspens

Sujets identifiés pendant le développement, volontairement écartés pour ne pas
interrompre la production des scripts. À traiter avant la fin du chantier.

Chaque entrée indique le contexte, l'impact réel et une piste. Retirer l'entrée
une fois le point traité, en renvoyant vers le commit correspondant.

---

## 1. Un échec en tâche planifiée passe inaperçu

**Soulevé le** 2026-08-26, à propos de `update-system.sh`.

**Contexte.** Une ligne de cron s'écrit avec `>/dev/null 2>&1`, faute de quoi la
sortie complète d'`apt` est envoyée par mail à chaque exécution — ou produit des
erreurs si aucun serveur mail n'est configuré.

**Impact.** Avec la sortie jetée, une mise à jour qui échoue ne prévient
personne. Le code de retour est correct et le journal contient l'erreur, mais
rien ne remonte. Un serveur peut rester sans mise à jour pendant des mois.

**Pistes.**
- Ne rediriger que la sortie standard et laisser cron transmettre les erreurs.
- Un script `notify.sh` dans `lib/` ou `Linux/System/`, appelé sur échec
  (webhook, courriel, ntfy…).
- Un `check-updates.sh` de contrôle, exécuté séparément, qui vérifie la
  fraîcheur du dernier journal.

**Concerne** tous les scripts destinés à `cron` : `update-system.sh`,
`security-check.sh`, `backup-resources.sh`, `docker-cleanup.sh`.

---

## 2. `confirm()` n'a jamais été exécutée dans un terminal

**Soulevé le** 2026-08-26.

**Contexte.** `confirm()` utilise `read`, qui exige un terminal. Les tests
automatisés passent tous par `--yes`.

**Impact.** Le chemin interactif — celui qu'utilisera un humain — n'est vérifié
sur aucun script. Une erreur y resterait invisible jusqu'au premier usage réel.

**Piste.** Vérification manuelle dans un terminal, une fois, sur un script qui
l'utilise. Les réponses acceptées sont `o`, `oui`, `y`, `yes` ; toute autre
saisie annule.

---

## 3. Chemin « paquets retenus » non vérifié

**Soulevé le** 2026-08-26, à propos de `update-system.sh`.

**Contexte.** Après `apt-get upgrade`, les paquets nécessitant une installation
ou une suppression supplémentaire restent en attente. Le script les signale en
`[WARN]`.

**Impact.** Faible — le message est cosmétique. Mais le comptage n'a jamais été
exercé : aucune machine de test n'avait de paquet retenu.

**Piste.** Vérifier sur un serveur réel présentant le cas, ou provoquer la
situation avec un paquet épinglé.

---

## 4. `enable_full_logging` peut tronquer les dernières lignes

**Soulevé le** 2026-08-26.

**Contexte.** La fonction redirige la sortie via `exec > >(tee -a "$LOG_FILE")`.
Ce mécanisme lance `tee` en arrière-plan ; si le script se termine avant que
`tee` ait fini d'écrire, les dernières lignes peuvent manquer dans le journal.

**Impact.** Un script qui échoue en fin d'exécution risque de perdre du journal
précisément le message d'erreur.

**Statut.** Jamais reproduit — aucun script n'utilise encore
`enable_full_logging`. À vérifier avant le premier usage.

**Piste.** Retenir le PID du processus `tee` et l'attendre dans un `trap EXIT`,
ou remplacer la redirection par un tube nommé.

---

## 5. Aucun linter n'a été exécuté

**Soulevé le** 2026-08-26.

**Contexte.** `shellcheck` n'est installé ni sous Git Bash ni dans l'Ubuntu WSL
de développement. La vérification s'est limitée à `bash -n`, qui ne contrôle que
la syntaxe.

**Impact.** Les défauts classiques du Bash — variables non protégées, tests
fragiles, codes de retour ignorés — ne sont détectés que par relecture.

**Piste.**

```bash
sudo apt-get install shellcheck
shellcheck lib/common.sh Linux/**/*.sh
```

Envisager un contrôle automatique (`pre-commit` ou GitHub Actions) une fois
plusieurs scripts écrits.

---

## 6. Nom du dépôt

**Soulevé le** 2026-08-26.

**Contexte.** Le dépôt distant s'appelle `MGNetworking/script`, au singulier. Le
plan d'origine parlait de `MGNetworking/scripts`. La documentation a été alignée
sur le nom réel.

**Impact.** Cosmétique.

**Piste.** Renommer le dépôt sur GitHub si le pluriel est préféré — l'URL
distante devra alors être mise à jour sur chaque machine.
