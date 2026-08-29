# Comprendre le fonctionnement de l'agent

Ce document explique **comment ça marche**. Il ne dit pas quoi taper — c'est
l'objet du [mode d'emploi](mode-emploi.md) — mais pourquoi le système est bâti
ainsi, et sur quoi repose la confiance qu'on peut lui accorder.

À lire une fois, puis à relire le jour où quelque chose paraît absurde.

---

## 1. Un modèle de langage ne fait rien

C'est le point de départ, et il est contre-intuitif.

Un LLM ne lit pas un fichier, n'exécute pas une commande, ne modifie rien. Il
reçoit du texte et produit du texte. C'est tout ce qu'il sait faire.

Ce qui le transforme en agent, c'est **une boucle** :

```text
   ┌──────────────────────────────────────────────┐
   │                                              │
   ▼                                              │
1. on lui envoie : la tâche, l'état du projet,    │
   la liste des outils dont il dispose            │
   │                                              │
   ▼                                              │
2. il répond : « exécute l'outil X                │
   avec ces arguments »                           │
   │                                              │
   ▼                                              │
3. LE PROGRAMME exécute l'outil                   │
   (le modèle, lui, n'a rien fait)                │
   │                                              │
   ▼                                              │
4. on lui renvoie le résultat ───────────────────┘

5. quand il annonce avoir terminé :
   LE PROGRAMME lance les validations
   → réussite : la tâche est finie
   → échec : retour en 1, avec l'erreur
```

**Le modèle propose, le programme dispose.**

C'est de là que découle tout le reste. Si l'on autorise le modèle à déclarer
lui-même qu'il a réussi, on n'a plus un agent : on a un générateur de texte
optimiste.

## 2. Ce que fournit Claude Code, ce que fournit le dépôt

Cette boucle, nous ne l'avons pas écrite. Claude Code la fournit, avec les
outils qui vont avec — lire, écrire, chercher, exécuter une commande — et leurs
garde-fous.

C'était l'objet de la décision
[ADR-0002](decisions/ADR-0002-claude-code-comme-moteur.md) : ne pas reconstruire
ce qui existe.

| | Qui le fournit | Où |
|---|---|---|
| la boucle, les outils, les limites | **le moteur** | Claude Code |
| les rôles délégués | le dépôt | `.claude/agents/` |
| le déclenchement d'une tâche | le dépôt | `.claude/commands/` |
| les règles de travail | le dépôt | `AGENTS.md` |
| le travail à faire | le dépôt | `tasks/` |
| **la preuve** | le dépôt | `tests/run.sh` |

La ligne de partage est nette : le moteur sait *agir*, le dépôt sait *ce qu'il
faut faire, comment, et comment le prouver*. Le second ne dépend pas du premier.

## 3. Pourquoi déléguer à des sous-agents

Un agent unique qui écrit le script, ses tests, puis juge son propre travail
se trouve en conflit d'intérêts. Il a écrit le test, il sait pourquoi il
échoue, et le corriger est plus rapide que corriger le script.

D'où trois rôles séparés :

```text
        agent principal (lit la tâche, répartit)
                      │
      ┌───────────────┼───────────────┐
      ▼               ▼               ▼
redacteur-script  redacteur-tests  relecteur
  écrit le          écrit les       vérifie
  script            tests           LECTURE SEULE
```

### Ils ne se souviennent de rien

Chaque sous-agent démarre **sans aucune connaissance de la conversation**. Il ne
sait pas ce qui a été dit, ni ce que les autres ont fait.

Ce n'est pas une limitation à contourner, c'est ce qui rend le système fiable :
tout ce qui compte doit être **écrit** — dans la tâche, dans `AGENTS.md`, dans
la consigne qu'on lui passe. Rien ne peut reposer sur un sous-entendu.

Conséquence pratique : **une tâche mal écrite produit un travail à côté.** Le
champ `out_of_scope` n'est pas une formalité, c'est la seule chose qui empêche
le travail de déborder.

## 4. Pourquoi le relecteur ne peut pas écrire

C'est la décision de conception la plus importante du dispositif.

Le relecteur ne dispose que d'outils de lecture et d'exécution. Il n'a **aucun
moyen de modifier un fichier**.

Un relecteur capable d'écrire finit toujours par réparer ce qu'il constate.
C'est humain, et c'est encore plus vrai d'un modèle : face à un test qui échoue,
la correction la plus rapide est toujours de modifier le test.

Or un test « réparé » ne prouve plus rien. Le verdict passe au vert, le défaut
reste, et le rapport annonce une réussite.

En privant le relecteur d'outil d'écriture, ce scénario devient
**structurellement impossible**, au lieu d'être seulement déconseillé. C'est la
différence entre une règle et une garantie.

Il constate, il rapporte, il n'a pas le pouvoir de faire disparaître ce qu'il a
trouvé.

## 5. La boucle de correction

Un verdict négatif ne termine pas la tâche : il ouvre une tentative.

```text
verdict NON CONFORME
        ↓
diagnostic : le script ou le test ?
        ↓
redélégation au sous-agent concerné
        ↓
relecteur           tentative += 1
        ↓
  conforme ? → rapport      sinon → on reboucle
        ↓
  5 tentatives → BLOCKED, et on vous demande
```

### La présomption

Un test qui échoue a deux causes possibles : le script est faux, ou le test est
faux. **La présomption est que le script est fautif** — c'est lui qu'on teste.

Modifier un test exige un diagnostic écrit : en quoi ce test est faux. Sans
cette règle, la seconde branche est toujours choisie, parce qu'elle est plus
rapide et qu'elle fait passer le verdict au vert.

### La limite

Cinq tentatives. Au-delà, la tâche est bloquée et un rapport détaillé est
produit.

Une limite n'est pas un aveu de faiblesse : sans elle, un agent qui n'a pas
compris le problème peut boucler indéfiniment en produisant des variations de la
même correction. Deux tentatives donnant la même erreur signalent d'ailleurs un
diagnostic faux — c'est l'hypothèse qu'il faut changer, pas le code.

## 6. La preuve

Le système considère comme vrai ce qui vient des outils :

```text
codes de retour · sorties de commandes · état de Git · fichiers produits
```

Et non :

```text
« le modèle estime que ça fonctionne »
```

Un modèle peut interpréter un résultat. Il ne peut pas le **produire**.

C'est pourquoi `tests/run.sh` existe, et pourquoi il distingue trois issues au
lieu de deux :

| Code | Sens |
|---|---|
| 0 | les validations exécutées ont réussi |
| 1 | au moins une a échoué |
| 3 | **rien n'a été exécuté** |

Le code 3 est la traduction technique d'une règle simple : *« rien à exécuter »
n'est pas *« tout va bien »*. Sans lui, `tests/run.sh unit` sortirait en 0 alors
qu'aucun test unitaire n'existe, et un rapport annoncerait fièrement que les
tests passent.

La même règle vaut partout : **une validation non exécutée vaut `NON EXÉCUTÉ`,
jamais `PASS`.**

## 7. Ce que ça donne, bout à bout

```text
vous : /tache TASK-002
   │
   ├── lecture de AGENTS.md et de la tâche
   ├── vérification : statut, dépendances, Git propre, environnement
   ├── branche agent/TASK-002
   ├── plan annoncé
   │
   ├──→ redacteur-script    → script + documentation
   ├──→ redacteur-tests     → tests
   ├──→ relecteur           → verdict
   │         │
   │    non conforme → correction → relecteur   (5 fois au plus)
   │
   ├── rapport dans .agent/reports/
   ├── mise à jour du backlog
   └── commit sur la branche
   │
vous : lecture du rapport, du diff, puis fusion — ou non
```

Vous n'êtes pas dans la boucle pendant. Vous l'êtes avant — en décidant qu'une
tâche est prête — et après, en jugeant sur pièces.

## 8. Deux erreurs à ne pas commettre

**« Un bon agent, c'est un bon prompt. »**

Le prompt ne compte que pour une petite part. L'essentiel est ailleurs : la
boucle, les rôles séparés, la validation objective, les limites. Un prompt
médiocre avec une bonne structure donne un agent utilisable ; l'inverse donne un
bavard convaincant.

**« Le modèle dit que ça marche, donc ça marche. »**

C'est le piège central, et il est permanent. Un modèle annoncera sans ciller que
les tests passent alors qu'il ne les a jamais lancés — non par malveillance,
mais parce qu'il produit le texte le plus plausible, et qu'un rapport de
réussite est plus plausible qu'un rapport d'échec.

Tout le dispositif — le relecteur en lecture seule, le code de retour 3, la
présomption en faveur du script, la limite de tentatives — existe pour cette
seule raison.

## 9. Ce qui reste fragile

Un système comme celui-ci ne devient fiable qu'à l'usage. Trois points méritent
votre vigilance :

**Une tâche mal écrite produit un travail à côté**, et personne ne le
rattrapera : les sous-agents n'ont que ce qui est écrit.

**Le relecteur ne voit que ce qu'on lui demande de voir.** Sa grille est dans
`.claude/agents/relecteur.md`. Ce qui n'y figure pas ne sera pas vérifié.

**Une règle mal formulée se répète à chaque tâche.** Quand un résultat ne
convient pas, corriger le travail produit ne sert qu'une fois ; corriger la
règle dans `.claude/agents/` sert à toutes les tâches suivantes.

---

Pour l'usage quotidien : [mode-emploi.md](mode-emploi.md).
Pour les règles imposées aux agents : [AGENTS.md](../../AGENTS.md).
