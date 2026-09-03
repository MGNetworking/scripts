---
id: TASK-026
title: "Écrire Linux/System/reboot-system.sh"
status: ready
priority: medium
depends_on: []
environment: container-debian
human_approval_required: true
objective: |
  Livrer le redémarrage explicite et confirmé du serveur — le script le plus
  destructif du domaine. Il vérifie avant d'agir, ne redémarre jamais sans une
  confirmation ou un --yes délibéré, et sa preuve s'établit sans qu'aucun
  redémarrage n'ait lieu.
scope:
  - Linux/System/reboot-system.sh
  - tests/integration/reboot-system.test.sh
  - config/server.env.example — le mode par défaut, si une valeur de machine s'avère nécessaire
  - Linux/System/README.md — ligne du tableau, utilisation, risques
  - README.md — ligne du tableau des scripts
out_of_scope:
  - l'extinction de la machine — poweroff, halt, shutdown -h
  - le redémarrage différé, sa programmation et son annulation
  - la diffusion d'un message aux sessions ouvertes par wall
  - l'arrêt ordonné préalable des charges applicatives — conteneurs Docker, nœud K3s, drain Kubernetes
  - toute exécution du script sous le profil systemd, où un redémarrage réel détruirait la suite en cours
  - un repli sur shutdown, reboot ou telinit lorsque systemctl est absent — ADR-0003 décision 14 pose systemd partout
  - la remise en service et la vérification d'état après redémarrage
acceptance_criteria:
  - sans --yes, le script demande une confirmation et n'entreprend rien si la réponse n'est pas affirmative
  - avec --yes, il ne demande rien — c'est le mode destiné à une tâche planifiée, qui n'a pas de terminal
  - avant toute chose il affiche un résumé de ce qui va se passer, la machine, la date et le temps de fonctionnement écoulé
  - il indique si le système déclare un redémarrage nécessaire, en le lisant sur le disque et non en le supposant
  - avec --si-necessaire, il ne redémarre pas lorsque le système ne déclare aucun redémarrage nécessaire, et rend 0 en le disant
  - il liste les sessions ouvertes et les nomme dans le résumé, sans que leur présence empêche à elle seule le redémarrage
  - il refuse en 1 lorsqu'une opération de gestion de paquets est en cours, en nommant le processus trouvé
  - il refuse en 1 lorsque systemctl est absent, sans se replier sur une autre commande
  - sans privilège, il rend 1, et une ligne de commande à la fois fautive et sans privilège rend 2
  - une option inconnue rend 2 avant toute lecture d'état
  - --dry-run parcourt tous les contrôles, affiche la commande exacte qui serait lancée, et ne la lance pas
  - --help documente les options, l'ordre des contrôles, ce qui empêche le redémarrage et les codes de retour
  - le fichier de cas prouve que la commande de redémarrage est bien atteinte, par une commande de substitution qui enregistre ses arguments — aucun redémarrage réel n'a lieu pendant les validations
validation:
  - "tests/run.sh lint"
  - "tests/env/run-in-container.sh -- tests/run.sh lint"
  - "tests/env/run-in-container.sh -- tests/run.sh integration"
  - "tests/env/run-in-container.sh -- bash Linux/System/reboot-system.sh --help"
  - "tests/env/run-in-container.sh -- bash Linux/System/reboot-system.sh --dry-run --yes"
implementation_notes:
  - ADR-0003 décision 2 — un script destructif s'écrit et s'exécute quand même, parce qu'il ne s'exécute que dans un conteneur jetable ; AGENTS.md §7 ne change pas
  - le profil debian n'a pas systemctl — le chemin nominal y est inatteignable par accident, et c'est une propriété à conserver
  - le fichier de cas ne doit jamais être lancé sous le profil systemd, où un redémarrage réel tuerait le conteneur en pleine suite
  - /run/reboot-required est posé par apt et needrestart sur Debian et Ubuntu ; /var/run en est un lien symbolique
  - « who » ne rend rien dans un conteneur, faute d'utmp renseigné — c'est un cas nominal, pas une indisponibilité
  - toute affectation var="$(…)" se place en contexte de condition, motif tranché par TASK-018
---

# TASK-026 — Redémarrer, une fois qu'on a vérifié

## Ce que le plan demande

[docs/refactorisation-plan.md](../../docs/refactorisation-plan.md) §1,
`reboot-system.sh` : *redémarrage explicite et confirmé du serveur. `--yes`
possible pour l'automatisation.*

C'est le script le plus destructif du domaine : il n'efface rien, mais il coupe
tout. La question utile n'est donc pas *comment redémarrer* — une ligne suffit —
mais **ce qu'il faut avoir vérifié avant**, et **comment le prouver sans
redémarrer**.

## Ce qui doit être vérifié avant de redémarrer

Dans l'ordre du préflight imposé par `CLAUDE.md` — arguments, privilèges, OS,
état, conflits, résumé, confirmation, exécution :

| Contrôle | Ce qu'il évite | Verdict |
|---|---|---|
| arguments | une option mal comprise qui ferait redémarrer sans qu'on l'ait demandé | **2**, avant toute lecture d'état |
| privilèges | un échec à mi-chemin | **1** |
| système supporté | agir sur une distribution non ciblée | **1** |
| `systemctl` disponible | un repli hasardeux sur une autre commande | **1** |
| **gestion de paquets en cours** | redémarrer pendant un `dpkg` laisse un système à moitié configuré, parfois non amorçable | **1**, refus net |
| redémarrage réellement nécessaire | redémarrer pour rien | informatif, ou **0 sans rien faire** avec `--si-necessaire` |
| sessions ouvertes | couper le travail d'un tiers sans le dire | avertissement nommant les sessions |
| confirmation | le geste irréversible fait par inadvertance | refus poli si la réponse n'est pas affirmative |

Le contrôle de la gestion de paquets est celui qui justifie à lui seul le script.
`update-system.sh` ne redémarre jamais de lui-même — c'est écrit dans le plan et
dans le README du domaine — et signale seulement qu'un redémarrage est
nécessaire. Un opérateur qui enchaîne les deux trop vite est exactement le
scénario à intercepter.

## Comment le prouver sans redémarrer le conteneur de test

Trois couches, et aucune ne redémarre quoi que ce soit.

**1. Le `--dry-run` parcourt tout.** Tous les contrôles sont exécutés, le résumé
est produit, la commande exacte est affichée, et rien n'est lancé. C'est la
preuve du préflight complet.

**2. Les refus se prouvent d'eux-mêmes.** Sans privilège, avec une option
inconnue, avec un faux `dpkg` en cours, sans `systemctl` : le script s'arrête
**avant** le point de non-retour. Le cas « gestion de paquets en cours » se
fabrique sans installer quoi que ce soit — un processus dormant portant le bon
nom suffit, et le fichier de cas doit le tuer ensuite.

**3. Le point de non-retour lui-même se prouve par substitution.** Un faux
`systemctl` placé en tête de `PATH` enregistre ses arguments et rend 0. Le
fichier de cas constate alors que le script a bien appelé `systemctl reboot`, au
bon moment, avec les bons arguments — et le conteneur ne bouge pas.

C'est la technique la mieux établie du dépôt : *un binaire homonyme en tête de
`PATH`*, la mutation la moins coûteuse, celle qui a démenti quatre arbitrages de
non-traitement pendant TASK-018. Elle est décrite dans `tests/README.md`, « Les
échecs qui ne sont pas fatals ».

Chaque cas de ce genre demande une **garde de contraste** : sans le faux
`systemctl`, le même appel doit échouer en 1 pour dépendance absente. Sans elle,
le cas serait vert sur un environnement où le script n'arrive jamais jusque-là.

## L'interdit qui accompagne cette tâche

**Ce script ne s'exécute jamais sous le profil `systemd`.** Là, `systemctl
reboot` fonctionnerait pour de bon : PID 1 recevrait l'ordre, le conteneur
mourrait, et la suite en cours avec lui — la validation ne rendrait même pas un
verdict interprétable.

L'environnement de la tâche est donc `container-debian`, où `systemctl` est
absent : le chemin nominal y est inatteignable par accident, et c'est une
propriété à **conserver**, pas un manque à combler.

## Décisions que cette tâche tranche

**`systemctl reboot`, et rien d'autre.** ADR-0003 décision 14 pose `systemd`
partout sur les cibles supportées. Un repli sur `shutdown -r now` doublerait la
surface de test pour un cas qui ne se présente pas ; l'absence de `systemctl`
est traitée comme n'importe quelle dépendance manquante, en 1.

**Aucun délai, aucune programmation.** Le script redémarre maintenant, après
confirmation. Un redémarrage différé appelle son annulation, donc un second mode,
donc un état à suivre : c'est un autre script, et le domaine ne le réclame pas.

**`--si-necessaire` rend 0 quand il ne fait rien.** C'est le mode qu'une tâche
planifiée utiliserait, derrière `update-system.sh`. Ne rien avoir à faire n'est
pas un échec.

Ces choix sont réversibles et locaux au sens d'`AGENTS.md` §14 ; ils sont fixés
ici pour ne pas être rediscutés à l'exécution, et à consigner dans le rapport.

## Pièges connus

**`--yes` est un mot chargé dans ce dépôt.** `configure-cron.sh` dépose des
lignes qui invoquent les scripts planifiés avec `--yes`, parce que `cron` n'a pas
de terminal. Le jour où `reboot-system.sh` serait planifié, `--yes` signifierait
« redémarre sans demander ». Le README doit le dire sans détour, et cette tâche
n'ajoute **aucune** ligne à `/etc/cron.d/mgnetworking`.

**`who` ne rend rien dans un conteneur** : `utmp` n'y est pas renseigné. Une
liste de sessions vide est le cas nominal, pas une indisponibilité. Un fichier de
cas qui déclarerait ce cas indisponible ferait sortir son niveau en 3 pour rien.

**Le fichier témoin est `/run/reboot-required`.** Il est posé par `apt` et
`needrestart` sur Debian et Ubuntu ; `/var/run` est un lien symbolique vers
`/run`. Le compagnon `/run/reboot-required.pkgs` liste les paquets qui l'ont
demandé — utile au résumé, jamais obligatoire.

**Le `trap EXIT` ne doit jamais rendre un code non nul.** Le défaut a coûté un
tour complet à `configure-cron.sh` : un `trap EXIT` qui rend autre chose que 0
arme le `trap ERR` du socle, qui écrit alors une ligne `Échec (code 1) à la ligne
1 de common.sh` désignant l'endroit où le trap est défini, et doublant tout
diagnostic postérieur. Voir `Linux/System/README.md`, « Codes de retour ».

## Codes de retour attendus des validations

| Commande | Code |
|---|---|
| `tests/run.sh lint` | 0 |
| `run-in-container.sh -- tests/run.sh lint` | 0 |
| `run-in-container.sh -- tests/run.sh integration` | 0 |
| `run-in-container.sh -- bash …/reboot-system.sh --help` | 0 |
| `run-in-container.sh -- bash …/reboot-system.sh --dry-run --yes` | 0, aucun redémarrage |

La dernière est volontairement la combinaison la plus dangereuse en apparence —
`--yes` et `--dry-run` ensemble. `--dry-run` doit primer sans ambiguïté : c'est
le contrat que `configure-swap.sh` et `configure-cron.sh` tiennent déjà.
