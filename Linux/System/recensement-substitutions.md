# Recensement des substitutions de commande — `Linux/System`

Relevé exhaustif des affectations de la forme `var="$(…)"` des sept scripts du
domaine, avec pour chacune un verdict et sa raison — **y compris celles qui ne
sont pas traitées**.

Ce document existe parce que trois tours de relecture ont manqué trois fichiers
l'un après l'autre, faute d'un relevé écrit. Une correction au cas par cas ne
prouve rien ; ce tableau, si.

Établi le 2026-09-02, pendant TASK-018, quatrième tour.
Complété le 2026-09-03, cinquième tour : les six sites que le quatrième avait
laissés ouverts sont fermés, et le `dirname` de `configure-swap.sh` est tranché.
**Plus aucun site du domaine n'est en forme nue avec une cause atteignable.**

Les numéros de ligne sont ceux du 2026-09-03 et **dérivent** à chaque édition :
les vérifier avant de s'y fier, la commande de relevé est donnée plus bas.

---

## 1. Ce qui borne le périmètre

**Seules les affectations doublent.** C'est une mesure, pas une déduction — elle
a été faite par le relecteur de TASK-018, troisième tour.

```bash
var="$(cmd)"        # cmd échoue -> le trap ERR parle, puis errexit arrête
ligne "x" "$(cmd)"  # cmd échoue -> le script continue, « ligne » a rendu 0
```

Le code de retour d'une commande simple est celui de la commande, **pas** celui
des substitutions qui composent ses arguments. Une affectation, elle, n'a pas
d'autre code que celui de sa substitution : l'échec remonte donc au shell
principal, `errexit` s'en saisit, et le `trap ERR` de `lib/common.sh` écrit sa
ligne — après l'avoir déjà écrite dans le sous-shell de la substitution.

Conséquence pratique : **le motif se cherche sur `var="$(…)"`, et nulle part
ailleurs.** Sans cette borne, on relève aussi les vingt substitutions en position
d'argument de `system-info.sh`, on ratisse trois fois trop large, et on manque
les six qui comptent. C'est exactement ce qui s'est produit.

Une affectation compte même quand la substitution est **noyée dans une chaîne** :

```bash
sauvegarde="/etc/fstab.bak-$(date '+%Y%m%d-%H%M%S')"
```

Un `date` en échec fait échouer l'affectation tout autant. Ces sites-là ne se
trouvent pas en cherchant `="$(` — d'où la commande de relevé donnée plus bas.

**La réserve a été levée par la mesure, le 2026-09-02.** Elle portait sur le
reste de l'énoncé — « aucun trap » — qui n'était pas évident : si le sous-shell
hérite du `trap ERR` par `set -E`, une substitution en échec en position
d'argument aurait dû produire une ligne orpheline. Trois sondes, en conteneur :

```bash
set -Eeuo pipefail
trap 'echo "TRAP ligne $LINENO" >&2' ERR
g() { /bin/false; }

f "$(false)"        # position d'argument : AUCUNE ligne, script poursuivi, code 0
v="$(g)"            # affectation        : TROIS lignes, code 1
```

Position d'argument : **aucune ligne de trap**, le script continue, code 0.
L'énoncé est donc exact en entier, et le périmètre `var="$(…)"` est confirmé.

Affectation appelant une fonction : **trois** lignes — une dans le sous-shell,
au numéro de ligne du corps de la fonction, puis deux au numéro de
l'affectation.

**Et voici pourquoi les décomptes se contredisaient d'un tour à l'autre.** Le
nombre de lignes visibles dépend du flux sur lequel le `trap ERR` écrit. Avec un
trap écrivant sur `stdout`, la même affectation n'en montre qu'**une** : les
autres sont produites dans le sous-shell, donc **capturées par la substitution
elle-même** et rangées dans la variable. Le `trap` de `lib/common.sh` écrit sur
`stderr` — rien n'est capturé, tout se voit.

Un décompte de lignes `[ERROR]` n'est donc jamais un invariant du motif : il
dépend de la profondeur d'appel et du flux. C'est ce qui explique qu'un chiffre
annoncé se soit révélé faux à trois reprises dans ce chantier. **Mesurer, à
chaque site.**

**Ce qui ne dispense de rien.**

- `[ -f "$f" ]` établit que le fichier existait à l'instant du test, pas que le
  `stat` qui suit aboutira ;
- `require_cmd hostname` prouve que la commande **existe**, pas qu'elle
  **réussit**. Un faux `hostname` en tête de `PATH` la met en échec — c'est la
  mutation qui a mis en défaut les deux sites de `configure-hostname.sh`, restés
  sans garde pendant trois tours au motif que `require_cmd` les protégeait.

**Un site est présumé atteignable tant qu'on n'a pas cherché la mutation qui
l'atteint.** Un binaire homonyme placé en tête de `PATH` atteint n'importe quelle
commande externe : `nproc`, `awk`, `hostname`, `stat`, `sed`, `tr`, `wc`, `date`,
`basename`, `dirname`. C'est la mutation la moins coûteuse du dépôt, et celle qui
a démenti tous les arbitrages de non-traitement rendus jusqu'ici.

## 2. Comment refaire le relevé

```bash
grep -n '\$(' Linux/System/*.sh
```

Puis écarter à la main, dans cet ordre :

1. les lignes de commentaire ;
2. les substitutions arithmétiques `$(( … ))`, qui ne forkent rien ;
3. les substitutions en **position d'argument** — hors périmètre, §1.

Ce qui reste est la colonne « Site » des tableaux ci-dessous. Le filtre est
manuel faute de mieux : `="$(` manque les substitutions noyées dans une chaîne,
et un motif plus large ramène les commentaires.

## 3. Verdicts

| Verdict | Ce qu'il signifie |
|---|---|
| **traité** | affectation en contexte de condition `if ! var="$(…)"`, diagnostic écrit sur place. Ni `errexit` ni le trap n'ont prise |
| **fonction** | la lecture est confiée à une fonction qui renseigne une globale et propage son code ; plus aucune substitution |
| **éteint** | `\|\| true` ou repli : la substitution rend toujours 0, rien ne remonte au shell principal |
| **sans objet** | en-tête de résolution, exécuté **avant** `source lib/common.sh` : aucun `trap ERR` n'est encore posé |
| **nu** | forme nue conservée. **Plus aucun site ne porte ce verdict** — il ne se justifierait que par une cause d'échec inatteignable, démontrée et non simplement supposée |

Le verdict **ouvert** — « forme nue, cause atteignable, non traité, hors du
périmètre du tour » — a été **retiré** au cinquième tour. Un périmètre de tour
n'est pas une raison technique : il dit qui n'a pas fait le travail, pas
pourquoi il n'avait pas à être fait.

**53 sites** au total, un de moins qu'au quatrième tour : la seconde
substitution `date` de `configure-swap.sh` a été supprimée plutôt que mise en
condition. **6 sites fermés au cinquième tour**, après les 6 affectations
traitées au quatrième. **Aucun site ouvert, aucun site nu.**

## 4. `system-info.sh` — 9 sites

| Ligne | Site | Verdict | Raison |
|---|---|---|---|
| 9 | `_dir="$(cd … && pwd)"` | sans objet | avant le chargement du socle |
| 10 | `_dir="$(dirname "$_dir")"` | sans objet | idem |
| 98 | `modele="$(grep … \| cut \| sed \|\| true)"` | éteint | `\|\| true` ; `/proc/cpuinfo` sans ligne « model name » est le cas nominal sur ARM |
| 113 | `coeurs="$(nproc)"` | **traité** | `command -v nproc` prouvait l'existence, pas le succès. Un faux `nproc` en tête de `PATH` produisait le double message — mesuré. Avertissement, valeur vide, « non disponible » |
| 118 | `coeurs="$(grep -c … \|\| true)"` | éteint | `grep -c` rend 1 sans correspondance ; c'est pour cela que le `\|\| true` est là |
| 147 | `total="$(awk … /proc/meminfo)"` | **traité** | branche de repli, atteinte en masquant `free`. Un faux `awk` la met en échec |
| 151 | `dispo="$(awk … /proc/meminfo)"` | **traité** | idem |
| 191 | `adresses="$(ip … \| awk … \|\| true)"` | éteint | `\|\| true` ; l'absence d'adresse globale est un cas nominal |
| 193 | `adresses="$(hostname -I … \|\| true)"` | éteint | idem |

Les substitutions en position d'argument de ce fichier — `uname -r`, `cut` sur
`/proc/loadavg`, les cinq `cellule`, `hostname`, `id`, `uptime`, `date`,
`timedatectl`, `cat /etc/timezone` — sont **hors périmètre** (§1). Elles
n'arrêtent pas le script ; une valeur manquante y devient « non disponible »,
comportement voulu d'un script de diagnostic.

## 5. `update-system.sh` — 6 sites

| Ligne | Site | Verdict | Raison |
|---|---|---|---|
| 10 | `_dir="$(cd … && pwd)"` | sans objet | avant le chargement du socle |
| 11 | `_dir="$(dirname "$_dir")"` | sans objet | idem |
| 84 | `simulation="$(apt-get -s upgrade … \|\| true)"` | éteint | `\|\| true` |
| 85 | `a_installer="$(printf \| grep \|\| true)"` | éteint | `grep` rend 1 quand rien n'est à installer : cas nominal |
| 103 | `nombre="$(printf \| wc \| tr)"` | **traité** | aucune extinction, et `pipefail` : un faux `wc` ou `tr` fait échouer l'affectation. Le décompte ne sert qu'à l'affichage — avertissement et `?` |
| 133 | `restant="$(apt-get … \| grep -c … \|\| true)"` | éteint | `\|\| true` ; `grep -c` rend 1 quand plus rien n'est retenu |

**Réserve sur la ligne 133**, d'une autre nature que le doublement : si le
pipeline échoue réellement — `grep` masqué —, `restant` vaut la chaîne vide et le
`[ "$restant" -gt 0 ]` de la ligne suivante meurt sur « integer expression
expected ». Le `|| true` empêche le doublement, il ne garantit pas une valeur
exploitable. Ce n'est pas le motif de TASK-018 : le défaut est consigné au point
n° 8 des [points en suspens](../../docs/points-en-suspens.md), et relève d'une
autre tâche.

## 6. `configure-hostname.sh` — 7 sites

| Ligne | Site | Verdict | Raison |
|---|---|---|---|
| 12 | `_dir="$(cd … && pwd)"` | sans objet | avant le chargement du socle |
| 13 | `_dir="$(dirname "$_dir")"` | sans objet | idem |
| 142 | `NOM_ACTUEL="$(hostname)"` | **traité** | `require_cmd hostname` ne protégeait de rien — double message mesuré sous un faux `hostname`. Avertissement, valeur `inconnu`, le nom demandé est appliqué malgré tout |
| 164 | `LIGNE_EXISTANTE="$(grep … \|\| true)"` | éteint | l'absence de ligne `127.0.1.1` est le cas nominal |
| 257 | `if ! horodatage="$(date …)"` | **traité** | fermé au cinquième tour. La substitution était noyée dans une chaîne — `base="/etc/hosts.bak-$(date …)"` — ce qui ne change rien : un faux `date` faisait échouer l'affectation. L'horodatage est lu à part, en condition ; son échec est fatal, faute de nom de sauvegarde, et `/etc/hosts` reste intact |
| 284 | `temporaire="$(mktemp 2>/dev/null)"` | traité | en condition depuis le premier tour de TASK-018 |
| 321 | `nom_verifie="$(hostname)"` | **traité** | même cause qu'en 142. L'échec n'y est pas fatal : l'écart que cette vérification cherche n'est lui-même qu'un avertissement — certains systèmes n'appliquent le nom qu'au redémarrage — et une lecture impossible ne peut pas être punie plus sévèrement que l'écart qu'elle sert à détecter |

La substitution de la ligne 329, `$(grep … || echo 'absente')`, est en position
d'argument **et** éteinte : hors périmètre deux fois.

## 7. `configure-timezone.sh` — 8 sites

| Ligne | Site | Verdict | Raison |
|---|---|---|---|
| 11 | `_dir="$(cd … && pwd)"` | sans objet | avant le chargement du socle |
| 12 | `_dir="$(dirname "$_dir")"` | sans objet | idem |
| 61 | `if liste="$(timedatectl list-timezones …)"` | traité | en condition ; l'échec fait passer au repli `find` |
| 171 | `if valeur="$(timedatectl show …)"` | fonction | dans `fuseau_actuel`, qui renseigne `FUSEAU_ACTUEL` et propage son code (troisième tour) |
| 178 | `if valeur="$(tr … < /etc/timezone)"` | fonction | idem |
| 187 | `if valeur="$(readlink \| sed)"` | fonction | idem |
| 252 | `if ! ancien_fichier="$(tr … )"` | traité | mise en cohérence de `/etc/timezone` après application |
| 291 | `if ! fichier_timezone="$(tr … )"` | traité | même lecture, à la vérification |

Aucun site ouvert. Les substitutions en position d'argument — trois appels à
`date`, dont un sous `TZ=` — sont hors périmètre.

## 8. `configure-cron.sh` — 7 sites

| Ligne | Site | Verdict | Raison |
|---|---|---|---|
| 32 | `_dir="$(cd … && pwd)"` | sans objet | avant le chargement du socle |
| 33 | `_dir="$(dirname "$_dir")"` | sans objet | idem |
| 279 | `if DEMON_CRON="$(chemin_demon_cron)"` | traité | affectation **dans la condition d'un `if`** ; le `return 1` de la fonction est le cas que l'appelante traite |
| 389 | `if ! proprietaire="$(stat -c '%U:%G' …)"` | traité | `[ -f ]` préalable ne prouve pas que `stat` aboutira |
| 402 | `if ! mode="$(stat -c '%a' …)"` | traité | idem |
| 487 | `if ! proprietaire="$(stat …)"` | traité | même lecture, à la vérification |
| 495 | `if ! mode="$(stat …)"` | traité | idem |

Aucun site ouvert. À retenir de ce fichier, hors substitutions : son `trap … EXIT`
rend **toujours 0**. Un trap `EXIT` qui rend un code non nul est pour Bash une
commande en échec de plus, et doublait ici tout diagnostic postérieur à sa pose.

## 9. `configure-swap.sh` — 13 sites

| Ligne | Site | Verdict | Raison |
|---|---|---|---|
| 14 | `_dir="$(cd … && pwd)"` | sans objet | avant le chargement du socle |
| 15 | `_dir="$(dirname "$_dir")"` | sans objet | idem |
| 113 | `signature="$(dd … \| tr … \|\| true)"` | éteint | `dd` échoue sur tout fichier plus court que la page examinée : cas nominal de la boucle |
| 445 | `if ! nombre="$(printf \| sed)"` | **traité** | fermé au cinquième tour, dans `en_megaoctets`. Un faux `sed` fait échouer l'affectation. Code 1 : la taille n'a pas pu être analysée, ce qui est un échec d'exécution, quand une taille réellement invalide vaut 2 |
| 450 | `if ! unite="$(printf \| sed \| tr)"` | **traité** | idem, avec `sed` et `tr` |
| 502 | `virtualisation="$(systemd-detect-virt … \|\| true)"` | éteint | `systemd-detect-virt` rend 1 hors conteneur : cas nominal |
| 556 | `if ! repertoire_swap="$(dirname -- …)"` | **traité** | tranché au cinquième tour — voir §11.1. La forme nue était conservée au motif que `dirname` ne peut pas échouer ici ; l'argument couvrait son absence, pas son échec |
| 567 | `if ! type_fs="$(df -P -T … \| awk …)"` | traité | sous `pipefail`, l'échec de `df` emporte le pipeline |
| 619 | `if ! octets="$(stat -c %s …)"` | traité | le site d'origine du motif ; mis en défaut par un faux `stat` |
| 646 | `if ! espace_libre_mo="$(df -P -BM … \| awk …)"` | traité | idem 567 |
| 695 | `if ! swap_utilise_ko="$(awk … /proc/swaps)"` | traité | la mesure conditionne une décision de sûreté : sans elle, le script s'arrête |
| 700 | `if ! ram_libre_ko="$(awk … /proc/meminfo)"` | traité | idem |
| 780 | `if ! horodatage="$(date …)"` | **traité** | fermé au cinquième tour. L'échec est fatal : `/etc/fstab` ne se modifie pas sans sauvegarde. Le swap reste actif pour la session, seule sa persistance manque — le diagnostic donne la ligne à ajouter à la main |

La quatorzième affectation du quatrième tour, `sauvegarde="/etc/fstab.bak-$(date
…)-$suffixe"` dans la boucle de désambiguïsation, **n'existe plus** : `date` est
désormais lu une seule fois, et la boucle se contente de suffixer cet
horodatage — la forme de `configure-hostname.sh`. Aucun verdict du §3 ne s'y
applique, et c'est voulu : la substitution n'est pas gardée, elle a disparu.
Effet de bord assumé, et c'est une correction : l'ancienne boucle rappelait
`date`, si bien qu'un passage de seconde produisait `…-<nouvel horodatage>-1`
alors que `…-<nouvel horodatage>` était libre.

## 10. `configure-logging.sh` — 3 sites

| Ligne | Site | Verdict | Raison |
|---|---|---|---|
| 12 | `_dir="$(cd … && pwd)"` | sans objet | avant le chargement du socle |
| 13 | `_dir="$(dirname "$_dir")"` | sans objet | idem |
| 38 | `if ! NOM_REGLE="$(basename …)"` | **traité** | fermé au cinquième tour, **pour le seul doublement**. Deux causes l'atteignent : un faux `basename` en tête de `PATH`, et un `LOG_DIR` commençant par un tiret, que `basename` prend pour une option. La seconde n'est pas tranchée ici : personne ne valide `LOG_DIR`, et `basename --` accepterait le chemin fautif pour déposer une règle logrotate qui n'a pas de sens. Ce sujet-là reste au point n° 6 des [points en suspens](../../docs/points-en-suspens.md) |

**Réserve de placement**, sans rapport avec le doublement : cette affectation est
faite **avant** l'analyse des arguments, contrairement à l'ordre de préflight du
dépôt. Son échec préempte donc `--help`. C'était déjà vrai sous la forme nue —
`errexit` arrêtait le script au même endroit — et le déplacer relève d'un autre
sujet que celui-ci.

## 11. Ce qui reste ouvert

**Plus rien, au sens du motif.** Les six sites que le quatrième tour laissait en
forme nue avec une cause atteignable sont fermés :
`configure-hostname.sh:246`, `configure-swap.sh:435`, `:436`, `:743`, `:746`,
`configure-logging.sh:26` — numéros du 2026-09-02, devenus 257, 445, 450, 780,
supprimé, et 38.

La raison inscrite en face de chacun était « hors des cinq sites bornés pour ce
tour ». C'est un périmètre auto-décrété, pas une raison technique : il dit qui
n'a pas fait le travail, pas pourquoi il n'avait pas à l'être. Aucun des six
n'entrait dans la seule dispense que la tâche reconnaît — « une substitution dont
l'échec est attendu et géré » — et le §1 de ce document pose l'inverse : un site
est présumé atteignable tant qu'on n'a pas cherché la mutation qui l'atteint.

### 11.1 `configure-swap.sh:556` — le `dirname` nu, tranché

Deux issues se présentaient : passer le site en condition comme les autres, ou
acter par écrit que la forme nue est admise pour les commandes appelées avant le
chargement du socle. **La première est retenue.** Trois raisons :

1. **L'argument écrit ne couvrait pas ce qu'il prétendait couvrir.** « L'absence
   de `dirname` est exclue par le fait que le script démarre » exclut l'absence,
   pas l'échec. C'est mot pour mot l'argument de `require_cmd hostname`, que la
   mutation par binaire homonyme a démenti au tour précédent.
2. **Il ne tient même pas pour l'absence.** Les trois lignes de résolution
   s'exécutent **avant** que `lib/common.sh` ne charge `config/server.env`, qui
   peut redéfinir `PATH`. Le `dirname` résolu à la ligne 556 n'est pas
   nécessairement celui qui a résolu l'en-tête.
3. **La seconde issue n'avait pas de champ cohérent.** Acter que « la forme nue
   est admise pour les commandes appelées avant le chargement du socle » ne
   dispenserait que `cd`, `pwd` et `dirname` — et les seules lignes qui les
   appellent *avant* le socle portent déjà le verdict `sans objet`, pour une
   raison autrement plus solide : aucun `trap ERR` n'y est encore posé. À la
   ligne 556, il l'est depuis longtemps. La règle aurait donc dû s'énoncer
   « commande dont un exemplaire a réussi plus tôt », ce qui est mot pour mot la
   confusion entre l'absence et l'échec écartée au point 1.

Ce qui est perdu en le fermant se dit aussi : la branche `if !` est du code
qu'aucun scénario ordinaire n'emprunte. Elle s'atteint par mutation — un binaire
homonyme en tête de `PATH` —, comme toutes les autres gardes de ce domaine, et
c'est le niveau de preuve que ce chantier s'est donné.

### 11.2 Ce qui reste, et qui n'est pas un doublement

- `update-system.sh:133` — `|| true` empêche le doublement, mais laisse une
  chaîne vide au `[ "$restant" -gt 0 ]` de la ligne suivante, qui meurt alors sur
  « integer expression expected ». Autre défaut, autre tâche.
- `configure-logging.sh:38` — la validation de `LOG_DIR` elle-même, point n° 6
  des [points en suspens](../../docs/points-en-suspens.md). Le doublement est
  traité ; la question de savoir qui refuse un `LOG_DIR` absurde ne l'est pas.
- `configure-logging.sh:38` encore — l'affectation précède l'analyse des
  arguments, contre l'ordre de préflight du dépôt (§10).

### 11.3 L'arbitrage de fond, pour mémoire

Le point n° 7 des points en suspens posait le choix : appliquer le motif partout
où la forme apparaît, ou seulement là où une cause s'atteint. **Ce recensement
n'a pas eu à trancher**, et c'est son principal résultat : après relevé
exhaustif, aucun site du domaine ne se trouve dans le cas litigieux. Les sites où
une cause s'atteint sont traités, les autres portent un verdict qui dit pourquoi
— `éteint` par `|| true`, ou `sans objet` faute de `trap ERR` posé.

La question ne se reposera qu'au premier site dont l'inatteignabilité serait
démontrée. Le §1 dit à quelle condition : avoir cherché la mutation, et ne pas
l'avoir trouvée.
