# Journal de comparaison — délégation à d'autres LLM

Une ligne par tâche **réellement livrée**. Chaque tâche déléguée est appariée à
une tâche de même nature faite par Claude. Méthode : le modèle délégué produit,
Opus relit une fois dans un sous-agent (jetons mesurés), le modèle délégué corrige
une fois, l'arbitre termine si nécessaire.

| Tâche | Nature | Exécutant | Validations | Vérif. | Lignes script + cas | Coût délégué | Relecture Opus | Rattrapage |
|---|---|---|---|---|---|---|---|---|
| TASK-029 `install-docker.sh` | modifie le système | Claude seul | 5/5 | 26 | 176 + 105 | — | aucune | — |
| TASK-030 `configure-docker.sh` | modifie le système | `deepseek-flash` | 5/5 après rattrapage | 68 | 228 + 294 | 0,22 $ pointe | 35 960 jetons | 3 lignes, arbitre |

Aucun coût Claude en jetons n'est encore mesuré pour les travaux faits dans la
session principale — ni TASK-029, ni les rattrapages.

---

## TASK-030 — `deepseek-flash`, 2026-09-14

### Déroulé

| Étape | Résultat |
|---|---|
| Génération, effort par défaut | **plafond de 65 536 jetons atteint, rien livré** — 0,084 $ perdus |
| Génération, effort `low` | livré : 207 + 183 lignes. 4 validations sur 5 : lint conteneur à 1 (5 × SC2016). 48 vérifications réussies |
| Relecture Opus | *fusionnable après corrections* : 0 bloquant, 3 majeurs, 4 mineurs, tests partiellement creux |
| Correction DeepSeek | 224 + 293 lignes. Majeurs 1 et 3 corrigés. Mais lint toujours à 1 (2 × SC2016 déplacés dans le script) et **3 échecs nouveaux** dans le fichier de cas |
| Rattrapage par l'arbitre | 2 directives `shellcheck` justifiées, 1 `mkdir -p` dans le test. 5/5 validations, 68 vérifications |

### Défauts relevés par Opus

1. **MAJEUR** — après un échec du démon, le fichier était restauré mais le démon
   pas relancé : machine laissée sans Docker. *Corrigé par DeepSeek.*
2. **MAJEUR** — README non modifiés. *Faux positif du protocole* : l'écriture des
   README était interdite à DeepSeek et réservée à l'arbitre.
3. **MAJEUR** — conformité jugée au texte exact. *Corrigé avec jq* ; sans jq la
   comparaison reste textuelle, limite acceptée puisque la fiche exige jq pour
   toute fusion.
4. MINEUR — temporaire dans `/etc/docker`, validé seulement avec jq. *Accepté* :
   le même répertoire rend le `mv` atomique, et sans jq seul le contenu construit
   par le script peut être écrit.
5. MINEUR — `--dry-run` peu informatif. *Corrigé.*
6. MINEUR — `daemon.json` invalide sortait par le piège ERR. *Corrigé.*
7. MINEUR — taille. *Aggravée* : 390 → 522 lignes.

Tests creux signalés : « sans root » testé en root, faux `jq empty` toujours à 0.
*Tous deux corrigés* : `setpriv` pour le non-root, `JQ_EMPTY` pour le JSON invalide.

### Ce qu'on en retient

- **Au-delà du diagnostic, DeepSeek livre du « fusionnable après corrections »,
  pas du fusionnable en l'état.** Les défauts sont réels mais aucun n'est bloquant,
  et la relecture les a tous attrapés.
- **La relecture Opus coûte autant ou plus que toute la production DeepSeek.**
  C'est le vrai poste de coût de la méthode.
- **La correction sur liste est imparfaite** : elle règle les défauts nommés,
  en introduit de nouveaux, et fait grossir les fichiers malgré la consigne.
- **L'effort de raisonnement par défaut est inutilisable sur une tâche riche** :
  il consomme tout le plafond de sortie. Utiliser `--effort low`.
- **La consommation de sortie reste haute même en `low`** : 52 000 à 56 000
  jetons pour ~500 lignes de code.
- **Les fichiers dépassent nettement la cible de 150 lignes** de l'ADR-0004.

### Limites de la comparaison

La TASK-029 de Claude n'a pas été relue par Opus : le nombre de défauts n'est
pas comparable à égalité. Les deux tâches sont de même nature, pas identiques.
