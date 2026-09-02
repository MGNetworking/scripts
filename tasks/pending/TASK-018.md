---
id: TASK-018
title: "Supprimer le doublement du trap ERR sur les substitutions de commande"
status: pending
priority: medium
depends_on:
  - TASK-017
environment: container-debian
human_approval_required: false
objective: |
  TASK-016 a supprimé le doublement du diagnostic sur en_megaoctets, mais le
  motif de fond subsiste : toute commande qui échoue à l'intérieur d'une
  substitution déclenche le trap ERR deux fois, dans le sous-shell puis dans le
  shell principal.
scope:
  - Linux/System/configure-swap.sh — les substitutions de commande restantes
  - les autres scripts de Linux/System où le même motif apparaît
  - tests/integration/linux-system.test.sh — assertions de non-doublement
out_of_scope:
  - lib/common.sh — le trap ERR y est défini, zone protégée. La correction vient des appelants
  - la validation de --file, traitée par TASK-017
  - toute évolution fonctionnelle des scripts
  - les scripts Synology hérités
acceptance_criteria:
  - aucun échec survenant dans une substitution de commande ne produit deux fois le message du trap ERR
  - le motif est corrigé partout où il apparaît dans Linux/System, pas seulement sur le cas connu de la ligne 195
  - le code de retour de ces échecs respecte la convention - 2 pour une erreur d'usage, 1 pour un échec d'exécution
  - aucun comportement fonctionnel n'est modifié
  - le non-doublement est verrouillé par des assertions qui rougissent sous mutation
validation:
  - "tests/run.sh lint"
  - "tests/env/run-in-container.sh -- tests/run.sh integration"
  - "tests/env/run-in-container.sh -- tests/run.sh unit"
implementation_notes:
  - relevé par le relecteur de TASK-016 — voir tasks/reports/TASK-016-report.md, réserve 1
  - cas connu - configure-swap.sh ligne 195, repertoire_swap="$(dirname "$FICHIER_SWAP")". Chercher les autres - df, stat, awk
  - la correction éprouvée est celle d'en_megaoctets et de valider_horaire - une fonction qui affecte une variable globale plutôt que d'écrire sur stdout, appelée hors substitution
  - commencer par recenser les substitutions de commande de Linux/System avant d'en corriger une seule - une correction au cas par cas manquerait le motif
  - TASK-017 touche le même fichier - la faire passer d'abord évite un conflit
---

# TASK-018 — Le motif, pas le cas

## Origine

Réserve n° 1 du relecteur de [TASK-016](../completed/TASK-016.md).

TASK-016 a corrigé le doublement du diagnostic **métier** : `en_megaoctets`
appelait `die` depuis une substitution de commande, son `die` ne quittait que le
sous-shell, et le code remonté déclenchait le `trap ERR` du socle.

Le critère d'acceptation visait ce diagnostic-là, et il est tenu. Mais la tâche
nommait `en_megaoctets`, et le motif de fond est resté.

## Ce qui subsiste

```text
$ configure-swap.sh 512M --file --dry-run
dirname: unrecognized option '--dry-run'
[ERROR] Échec (code 1) à la ligne 195 de configure-swap.sh.
[ERROR] Échec (code 1) à la ligne 195 de configure-swap.sh.
```

Ligne 195, `repertoire_swap="$(dirname "$FICHIER_SWAP")"`. Le trap se déclenche
**deux fois sur la même ligne** : une fois dans le sous-shell de la
substitution, une fois dans le shell principal pour l'affectation en échec. Et
le code est 1 là où la convention demande 2.

Ce n'est pas propre à cette ligne. Toute substitution de commande dont le
contenu peut échouer produit le même effet.

## La correction connue

Elle est déjà appliquée deux fois dans le dépôt, et elle marche : une fonction
qui **affecte une variable globale** au lieu d'écrire sur `stdout`, appelée hors
substitution. C'est ce que fait `valider_horaire` dans `configure-cron.sh`, et
ce que `en_megaoctets` fait depuis TASK-016.

## Le piège de cette tâche

**Ne pas corriger cas par cas.** Le défaut de TASK-016 n'est pas d'avoir mal
corrigé `en_megaoctets` — c'est d'avoir corrigé un cas là où il y avait un
motif. Recenser d'abord toutes les substitutions de commande de `Linux/System`
dont le contenu peut échouer, puis décider lesquelles relèvent du même
traitement.

Certaines n'en relèveront pas : une substitution dont l'échec est attendu et
géré n'a pas besoin d'être défaite. Le recensement doit dire pourquoi, pour
chacune.
