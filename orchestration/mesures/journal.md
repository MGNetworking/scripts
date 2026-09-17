# Journal de comparaison — délégation à d'autres LLM

Une ligne par tâche **réellement livrée**. Chaque tâche déléguée est appariée à
une tâche de même nature faite par Claude. Méthode : le modèle délégué produit,
Opus relit une fois dans un sous-agent (jetons mesurés), le modèle délégué corrige
une fois, l'arbitre termine si nécessaire.

Depuis TASK-048, la colonne « Relecture Opus » se lit dans `agents.tsv`, lignes
`relecteur`, écrites dès le retour du sous-agent. Avant, le chiffre ne vivait que
dans la conversation : TASK-045 l'a perdu.

| Tâche | Nature | Exécutant | Validations | Vérif. | Lignes script + cas | Coût délégué | Relecture Opus | Rattrapage |
|---|---|---|---|---|---|---|---|---|
| TASK-029 `install-docker.sh` | modifie le système | Claude seul | 5/5 | 26 → 43 | 176 + 105 → 199 + 149 | — | 33 991 jetons | 7 défauts corrigés par Claude |
| TASK-030 `configure-docker.sh` | modifie le système | `deepseek-flash` | 5/5 après rattrapage | 68 | 228 + 294 | 0,22 $ pointe | 35 960 jetons | 3 lignes, arbitre |
| TASK-032 `create-network.sh` | modifie le système | Sonnet, sous-agent | 5/5 après correction | 36 | 148 + 147 | 270 602 jetons | 30 729 jetons | aucun |
| TASK-033 `list-containers.sh` | lecture seule | agent `deepseek` (Claude Code) | 4/4 | 57 | 364 + 252 → 168 + 219 | ≈ 0,25 $ pointe, 2 lancements | 45 011 jetons | relance agent, 2 majeurs corrigés |
| TASK-034 `docker-disk-usage.sh` | lecture seule | agent `deepseek` (Claude Code) | 4/4 | 52 | 150 + 149 → 150 + 150 | 2 lancements, 14,7 M cache | Opus 37 957 / Sonnet 47 098 | relance agent, 1 majeur corrigé |
| TASK-037 `docker-cleanup.sh` | destructif | agent `deepseek` (sonnet non authentifié, A41) | 4/4 | 68 | 150 + 140 → 150 + 150 | 0,464 $, 2 lancements | Opus 41 816 | relance agent, 4 majeurs corrigés |
| TASK-035 `update-images.sh` | un effet | agent `deepseek` | 4/4 | 65 | 150 + 150 → 149 + 149 | 0,218 $, 2 lancements | Opus 36 207 | 2 cas de test corrigés par l'orchestrateur, 5 mineurs par l'agent |
| TASK-036 `update-docker.sh` | effets enchaînés | agent `deepseek` (sonnet non authentifié, A41) | 5/5 | 76 | 148 + 150 → 150 + 148 | 0,409 $, 2 lancements | Opus 36 518 | 3 erreurs de test corrigées par l'orchestrateur (A42), 1 majeur et 6 mineurs par l'agent |
| TASK-024 `notify-failure.sh` | un effet, secret | agent `deepseek` | 5/5 | 87 | 150 + 197 → 150 + 254 | 0,225 $, 2 lancements | Opus 29 609 | 1 majeur (URL en argument de curl) et 5 mineurs corrigés par l'agent |
| TASK-025 `manage-users.sh` | effets enchaînés, sécurité | agent `deepseek` (sonnet non authentifié, A41) | 5/5 | 125 | 266 + 465 → 179 + 419 | 0,360 $, 2 lancements | Opus 40 226 | 3 majeurs (dont 2 de sécurité) corrigés ; sobriété non atteinte (A44) |
| TASK-026 `reboot-system.sh` | destructif | agent `deepseek` (sonnet non authentifié, A41) | 5/5 | 63 | 133 + 150 → 145 + 149 | 0,300 $, 2 lancements | Opus 28 939 | 3 majeurs corrigés, dont la confirmation héritée (A45) ; validation de la fiche corrigée |
| TASK-041 `audit-users.sh` | lecture seule | agent `deepseek` | 4/4 | 63 | 115 + 149 → 143 + 150 | 0,233 $, 2 lancements | Opus 21 409 | 3 mineurs et 2 tests creux corrigés |
| TASK-042 `audit-ports.sh` | lecture seule | agent `deepseek` | 4/4 | 107 | 96 + 150 → 102 + 149 | 0,197 $, 2 lancements | Opus 20 074 | FUSIONNABLE ; 4 mineurs et 3 tests creux corrigés |
| TASK-046 `configure-ssh.sh` | peut couper SSH | agent `deepseek` | 3/3 | 104 | 149 + 214 → 151 + 274 | 0,193 $, 2 lancements | Opus 34 881 | 1 majeur (rechargement raté laissé « conforme ») et 3 mineurs corrigés, 4 tests creux resserrés ; réserves A48-A50 |
| TASK-049 boucle sans vidage | consigne `/tache`, sous-agent | orchestrateur | 2/2 | — | — | — | Opus 33 559 | 1 bloquant (mesure du conducteur salissant `master`), 3 majeurs, 6 mineurs corrigés ; hypothèse « sous-agent sans outil Agent » réfutée par essai ; preuve : TASK-047 puis TASK-044 conduites par deux conducteurs (64 075 et 67 741 jetons) ; réserves A59-A61 |
| TASK-048 jetons de relecture | consigne `/tache` | orchestrateur | 1/1 | — | — | — | Opus 20 488 | 4 mineurs corrigés |
| TASK-045 `configure-firewall.sh` | peut couper SSH | agent `deepseek` + orchestrateur | 3/3 | 84 | 183 + 220 → 168 + 285 | 0,255 $, 2 lancements | Opus, non relevé | 1 bloquant (ufw inactif muet sur ses règles), 3 majeurs, 2 mineurs corrigés ; exigence IPv6 erronée retirée après mesure sur le vrai ufw |
| TASK-043 `security-check.sh` | lecture seule, cron | agent `deepseek` | 3/3 | 86 | 150 + 150 → 150 + 168 | 0,323 $, 2 lancements | Opus 24 942 | 1 majeur (sortie ufw traduite) et 5 mineurs corrigés |
| TASK-040 sobriété `manage-users` | refonte sans changement | agent `deepseek` | 3/3 | 138 | 179 + 419 → 150 + 296 | 0,276 $, 2 lancements | Opus 35 683 | 2 messages rétablis, 5 trous de test comblés |
| TASK-047 `disable-root-login.sh` | peut couper SSH | agent `deepseek` | 3/3 | 92 | 150 + 140 | 0,116 $, 1 lancement | Opus 29 930 | fusionnable au premier jet, aucun défaut corrigé ; 5 mineurs laissés : réserves A51-A55 ; premier conducteur-tache (TASK-049) |
| TASK-044 `configure-fail2ban.sh` | un effet borné | agent `deepseek` | 3/3 | 100 | 146 + 146 → 150 + 219 | 0,182 $, 2 lancements | Opus 37 561 | 1 majeur (vérification avant que le démon réponde), 3 mineurs et 5 tests creux corrigés ; version corrigée non relue (A57) ; réserves A56-A58 |
| TASK-050 `verify-k3s.sh` | lecture seule | agent `deepseek` | 3/3 | 38 | 136 + 150 → 149 + 150 | 0,201 $, 2 lancements | Opus 24 826 | 4 mineurs et 1 test creux corrigés (état du service doublé, Warning absents pris pour API muette, `ok` inconditionnel, message « non installé » non vérifié) ; version corrigée non relue (A62) |
| TASK-051 `install-k3s.sh` | installe en root, télécharge | agent `deepseek` | 3/3 | 78 | 150 + 168 → 164 + 235 | 0,313 $, 2 lancements | Opus 41 940 | 1 bloquant (fichier de cas effaçant `/var/lib/rancher/k3s` hors conteneur), 2 majeurs (activation ratée sortie en ERR anonyme, faux `systemctl` toujours à 0), 3 mineurs, 5 tests manquants et 4 creux corrigés ; version corrigée non relue (A64) |
| TASK-052 `configure-k3s.sh` | redémarre k3s en root | agent `deepseek` | 3/3 | 89 | 150 + 161 → 182 + 211 | 0,212 $, 2 lancements | Opus 34 611 | 1 majeur (validation de `SRV_K3S_TLS_SAN` laissant passer « - », « 10.0.0.999 »), 1 test creux (décision 45 sans terminal), 3 tests manquants et 2 mineurs corrigés ; version corrigée non relue (A67) ; réserves A67-A71 |
| TASK-053 `upgrade-k3s.sh` | remplace le binaire k3s en root, télécharge | agent `deepseek` | 3/3 | 112 | 150 + 213 → 171 + 281 | 0,219 $, 2 lancements | Opus 41 620 | 3 majeurs (version non relue après l'installateur, `INSTALL_K3S_*` héritées en partie seulement, échec à mi-chemin plus couvert — test affaibli au passage 1), 1 test creux (décision 45 sans terminal), 3 mineurs et 3 tests manquants corrigés ; version corrigée non relue (A72) ; réserves A72-A74, A66 |
| TASK-054 `uninstall-k3s.sh` | détruit le cluster et les volumes en root | agent `deepseek` | 3/3 | 95 | 136 + 214 → 149 + 272 | 0,214 $, 2 lancements | Opus 34 618 | 1 majeur (chemins supposés : `/var/log/pods` et `/var/log/containers`, que le désinstallateur officiel ne supprime pas, auraient fait rendre 1 à toute vraie désinstallation), 3 tests creux ou manquants (taille, chemin absent, unité connue de systemd), 5 mineurs corrigés (chemins annoncés, arrêt anticipé en 0 et nœud agent, `taille()`, `[WARN]` de racine de test, `cut`) ; version corrigée non relue (A75) ; réserves A75-A77, A66 |
| TASK-055 `cluster-status.sh` | lecture seule | agent `deepseek` | 3/3 | 39 | 90 + 146 | 0,057 $, 1 lancement | Opus 25 609 | aucun rattrapage : FUSIONNABLE du premier coup ; 2 mineurs et tests partiels laissés au registre (A78, A79) |
| TASK-056 `pods-status.sh` | lecture seule | agent `deepseek` | 3/3 | 68 | 94 + 150 → 117 + 206 | 0,119 $, 2 lancements | Opus 26 222 | 1 majeur (stderr de kubectl mêlé à la liste : avertissement compté comme pod, liste vide masquée), 1 test creux (`--request-timeout` prouvé sur le dernier cas seul), 3 mineurs — tous corrigés par la relance, version corrigée non relue (A80) ; A81 à A83 au registre |
| TASK-057 `events.sh` | lecture seule | agent `deepseek` | 3/3 | 80 | 134 + 225 → 141 + 208 | 0,168 $, 2 lancements | Opus 28 424 | 1 majeur (tri par `.lastTimestamp` : événements events.k8s.io en tête), 3 mineurs (Forbidden imputé à l'apiserver, faux kubectl infidèle sur liste filtrée vide, `timeout` égal au `--request-timeout`), tests creux et redondances — tous corrigés par la relance, version corrigée non relue (A84) ; A85 à A87 au registre |
| TASK-058 `diagnostics.sh` | lecture seule | agent `deepseek` | 3/3 | 88 | 148 + 150 → 161 + 203 | 0,239 $, 2 lancements | Opus 27 650 | 3 majeurs (DaemonSets jamais signalés, la sortie par défaut n'ayant pas de « x/y » ; raisons réelles de pods incomplètes : Evicted, OOMKilled, ErrImagePull, Init:Error… ; `Forbidden` sur `get nodes` imputé à l'apiserver), 4 mineurs (`timeout` égal au `--request-timeout`, relevé d'événements illisible suivi de `[SUCCESS]`, événements non triés, faux kubectl muet) — tous corrigés par la relance, version corrigée non relue (A88) ; A89 et A90 au registre |
| TASK-059 `resource-usage.sh` | lecture seule | agent `deepseek` | 3/3 | 114 | 150 + 150 → 167 + 303 | 0,356 $, 2 lancements | Opus 34 557 | 1 majeur (`--namespace` non vérifié : `top pods -n inconnu` rend 0), mineurs (intitulés de colonnes retirés par `--no-headers`, délai de `describe nodes` trop court et 124 imputé à l'apiserver, fixture `describe nodes` jouet, `Forbidden` sur `top` et `describe` non testés, commit du passage 1 sans justification des tests) — tous corrigés par la relance ; metrics-server en panne traité comme absent (tranché par la session) ; refus sur `get namespace` testé par le conducteur ; version corrigée non relue (A91) ; A92 et A93 au registre |
| TASK-060 `backup-resources.sh` | écrit des fichiers locaux, lecture seule du cluster | agent `deepseek` | 3/3 | 131 | 150 + 260 → 150 + 356 | 0,263 $, 2 lancements | Opus 38 415 | 2 bloquants prouvés par sonde du conducteur puis confirmés (refus du dépôt contourné par `..` derrière un composant absent : export écrit dans le dépôt ; filtre awk qui supprimait `status:`/`uid:` dans les données des ConfigMaps), mineurs (branche NotFound inatteignable, dossier non inscriptible non testé, tests creux) — tous corrigés par la relance ; sondes rejouées par le conducteur sur la version finale : tenues ; version corrigée non relue (A94) ; A95 au registre |
| TASK-061 `cleanup-resources.sh` | **destructif** sur le cluster, objets nommés | agent `deepseek` | 3/3 | 146 | 149 + 150 → 198 + 256 | 0,247 $, 2 lancements | Opus 27 753 | 1 bloquant prouvé par sonde du conducteur puis confirmé (liste noire de types comparée à la forme exacte : `pod,secret/x`, `Secret/x`, `all/x`, `ns/production` et `ns/kube-system` atteignaient `delete`, `-n` ignoré pour un type à portée cluster), 1 majeur (`delete` sans `--wait=false`), mineurs (échec partiel, type inconnu pris pour apiserver injoignable), tests creux — tous corrigés par la relance : liste blanche décidée par la session ; 51 sondes rejouées sur la version finale : aucune cible hors liste n'appelle `kubectl` ; version corrigée non relue (A96) ; longueurs A97 |
| TASK-062 `install-kubectl.sh` | lecture seule, vérification de kubectl | agent `deepseek` | 3/3 | 101 | 150 + 173 → 150 + 244 | 0,308 $, 2 lancements | Opus 30 849 | 2 majeurs (copie conseillée de `k3s.yaml` créant un fichier root illisible par le compte ; `Unauthorized`, `x509` et `error loading config file` pris pour un apiserver muet), mineurs (versions hors forme, valeur de `KUBECONFIG` tronquée, faux Forbidden et faux `version` incomplets), tests creux (grep sur le source, illisible prouvé par un dossier) — tous corrigés par la relance ; les deux majeurs relus et rejoués en conteneur par le conducteur ; version corrigée non relue (A98) ; longueur A99 ; Forbidden sur `get nodes` A100 |
| TASK-063 `install-helm.sh` | installe Helm par `get-helm-4`, écrit `/usr/local/bin/helm` | agent `deepseek` | 3/3 | 64 | 125 + 188 → 130 + 203 | 0,201 $, 2 lancements | Opus 29 108 | 1 bloquant (`get-helm-4`, script bash, lancé par `sh` : sous dash `$EUID` vide, `sudo` jamais utilisé), 1 majeur (décision 45 éprouvée hors terminal, où le refus était acquis d'office), mineurs (assertion openssl ne prouvant que le faux, « jamais sudo » vrai d'office, `timeout` manquants, trap inutile, `--help` muet sur le sudo hors terminal) — tous corrigés par la relance ; bloquant rejoué par le conducteur sous `nobody` avec un faux installateur bash ; version corrigée non relue (A101) ; longueur A102 ; `VERIFY_SIGNATURES`/`GPG_PUBRING` hérités A103 |
| TASK-065 `install-cert-manager.sh` | installe ou met à jour cert-manager dans le cluster (release Helm, CRD) | agent `deepseek` | 3/3 | 130 | 188 + 241 → 228 + 335 | 0,222 $, 2 lancements | Opus 35 611 | 3 majeurs (release `pending-*` invisible sans `helm list -a`, délai de helm trop court pour le hook startupapicheck, `--request-timeout` coupant le watch de `rollout status`), tests manquants (comparaison v1.9.0/v1.10.0, `HELM_*` hérités, échec de `helm list`, 124, « aucun uninstall » sur le dernier cas seulement), 2 mineurs — corrigés par la relance ; parseur JSON lisant le champ du dernier objet corrigé par le conducteur (feaaa3f, test ajouté) |
| TASK-064 `install-ingress.sh` | lecture seule, vérification de Traefik et des ports 80/443 | agent `deepseek` | 3/3 | 89 | 150 + 170 → 150 + 241 | 0,280 $, 2 lancements | Opus 31 001 | 2 majeurs (faux `kubectl` ignorant l'expression `-o` : jsonpath et custom-columns non prouvés ; code 124 jamais provoqué), 3 mineurs (messages kubeconfig et Unauthorized, ligne servicelb affirmant un fait non vérifié, ressource inconnue de l'API prise pour un apiserver injoignable, une seule classe par défaut, `ss -ltn` vérifié par préfixe) — corrigés par la relance ; sondes de mutation du conducteur (5 mutations, toutes détectées) |
| TASK-069 `configure-ingress.sh` | écrit deux Middlewares Traefik dans le cluster (`kubectl apply`) | agent `deepseek` | 3/3 | 89 | 158 + 179 → 162 + 223 | 0,248 $, 2 lancements | Opus 35 835 | 1 majeur (`echec()` rangeant toute erreur inconnue, dont « no matches for kind » de la CRD absente, sous « apiserver injoignable »), 1 mineur (`--namespace` sans valeur en 1), tests creux (manifeste jugé tous documents confondus sans clé parente, `get middlewares` ignorant `-l`) — corrigés par la relance ; sondes du conducteur (diff 0 ou --dry-run sans apply, namespace invalide sans appel, 11 + 7 mutations toutes détectées) ; version corrigée non relue (A111) ; longueurs A112 ; `get crd` à portée cluster A113 |
| TASK-070 `configure-tls.sh` | écrit deux ClusterIssuers dans le cluster (`kubectl apply`) ; cert-manager enregistre deux comptes ACME | agent `deepseek` | 3/3 | 101 | 173 + 238 → 172 + 270 | 0,196 $, 2 lancements | Opus 36 900 | 2 majeurs (commentaire faux : compte ACME enregistré « au premier certificat » ; `server.env.example` promettant des e-mails d'expiration que Let's Encrypt n'envoie plus), 1 mineur (`wait` expiré sous le message neutre « le cluster a refusé »), tests incomplets (e-mails piégés, webhook sur apply, 124 sur wait, journal absent accepté) — corrigés par la relance ; sondes du conducteur (8 e-mails piégés en 2 sans appel, diff 0 et --dry-run sans apply ni wait, 9 + 10 mutations toutes détectées) ; version corrigée non relue (A114) ; longueurs A115 |
| TASK-067 `configure-namespaces.sh` | crée les namespaces de `SRV_K8S_NAMESPACES` dans le cluster (`kubectl apply`) | agent `deepseek` | 3/3 | 89 | 148 + 150 → 150 + 187 | 0,179 $, 2 lancements | Opus 30 624 | 3 majeurs (liste à retour ligne acceptée : `read` ne lisait que la 1re ligne, `web⏎kube-x` créait `web` et taisait le reste ; apply expiré en 124 jamais nommé ; idempotence non démontrée par deux exécutions), 1 mineur (existant reconnu par sous-chaîne non éprouvé, mutation `grep -qF` survivante) — corrigés par la relance ; sondes du conducteur (18 listes piégées en 2 sans appel, 2e exécution sans apply, pseudo-terminal, 11 + 9 mutations, une seule survivante avant relance) ; version corrigée non relue (A116) ; longueur A117 |
| TASK-068 `configure-storage.sh` | laisse une seule StorageClass par défaut, la cible (`kubectl annotate`) | agent `deepseek` | 3/3 | 134 | 150 + 223 → 170 + 296 | 0,437 $, 2 lancements | Opus 38 696 | 2 majeurs (clé bêta `storageclass.beta.kubernetes.io/is-default-class` ignorée : une classe qu'elle seule marquait restait par défaut ; aucun test de refus de l'annotation de la cible, mutation « exit 1 retiré » survivante), 4 mineurs (« a--b » refusé, cause d'un annotate refusé non nommée, section Mutations qui ne relançait pas la suite, commentaire « imprévisible » de `server.env.example`) — corrigés par la relance ; l'agent a trouvé lui-même le décalage de colonnes du jsonpath (séparateur « \| ») ; ajout du conducteur : cas et mutant « clé bêta ignorée au relevé », qui survivait ; sonde du conducteur 46 ok, 4 mutations détectées ; version corrigée non relue (A118) ; longueurs A119 ; premier commit sans ligne Tâche (A66) |
| TASK-071 `configure-registry.sh` | Secret `kubernetes.io/dockerconfigjson` par namespace de `SRV_K8S_NAMESPACES`, identifiants de `config/registry.env` (0600) sur STDIN de `kubectl apply -f -` | agent `deepseek` | 3/3 | 188 | 220 + 412 → 228 + 466 | 0,199 $, 2 lancements (relevé du premier faux : 1 tour, 243 jetons, 2 269 s, A122) | Opus 53 140 | 1 bloquant (fichier de cas du premier jet : faux `timeout` écrit à travers un lien, `/usr/bin/timeout` du conteneur remplacé, auto-appel sans fin, deux conteneurs bloqués), 1 majeur (trace héritée non coupée : `SHELLOPTS=xtrace` affichait le jeton, sonde du conducteur), mineurs (annotation non guillemetée, serveur et namespaces mal bornés, `DELAI_TEST`, longueurs) — corrigés par la relance ; sonde du conducteur sans fuite (argv, `ps`, `/proc` environ, journal, fichiers), rejouée sous `bash -xv` et `SHELLOPTS` ; suite 3 fois 0 ; mutant sans `set +xv` détecté ; version corrigée non relue (A120), « a..b » accepté (A120), longueurs (A121) |
| TASK-072 faux binaires et relevé d'agent | `juger.sh`, `lien-ecrit.awk`, `lancer-agent.sh`, `tests/README.md`, `/tache` 8.5 | orchestrateur (conducteur) | 2/2 | 8 (fichier d'acceptance) | — | — | Opus 29 540 | FUSIONNABLE ; 1 majeur (seuil 1 tour / 600 s aveugle à une boucle de plus d'un tour : remplacé par la somme du transcript de session), 2 mineurs (faux positif après `rm` du lien, lisibilité) et 2 demandes (preuve conservée, consigne 8.5) corrigés ; lacunes au registre (A123, A124) |

Le coût de production par Claude n'est mesuré que pour TASK-032, écrite par un
sous-agent. TASK-029 et les rattrapages de la session principale ne le sont pas.

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
- **Les fichiers dépassent nettement la cible de 150 lignes** de decisions.md.

### Limites de la comparaison

La TASK-029 de Claude n'a pas été relue par Opus : le nombre de défauts n'est
pas comparable à égalité. Les deux tâches sont de même nature, pas identiques.

---

## TASK-029 relue par Opus — la comparaison à égalité, 2026-09-14

Même sous-agent, même grille, même consigne que pour TASK-030. Relue sur sa
version livrée.

### Défauts relevés dans le travail de Claude

1. **MAJEUR** — le noyau est affiché mais jamais contrôlé : aucune version
   minimale, aucun refus. Critère de la fiche non tenu.
2. **MAJEUR** — le fichier de cas ne teste ni le retrait des conflits, ni l'échec
   d'`apt-get update` avec retrait de `docker.list`, ni l'activation du service.
   Les faux binaires le permettaient ; le saut « par nature » couvre ces chemins
   à tort.
3. MINEUR — `MIN_MEMOIRE_MO=1024`, alors que la fiche fixe 512 Mio.
4. MINEUR — `apt-get remove` passe avant `DEBIAN_FRONTEND=noninteractive`.
5. MINEUR — la clé est écrite par `curl` directement dans le fichier final : un
   échec laisse une clé tronquée.
6. MINEUR — si `df` ne rend rien, le contrôle disque est sauté sans avertissement.
7. MINEUR — tout échec d'`apt-get update` est attribué à une suite non publiée,
   et la clé déposée reste en place.

Tests creux : un faux `os-release` que rien ne lit, un `grep -c` comparé à « 1 »
qui laisserait passer un compte de 2, des faux binaires jamais appelés.

**Corrigés le même jour par Claude**, en une passe : 43 vérifications, 0 sautée,
cinq validations à 0. Aucun n'était bloquant.

### Comparaison

| | TASK-029 — Claude | TASK-030 — DeepSeek, 1re livraison |
|---|---|---|
| Verdict Opus | fusionnable après corrections | fusionnable après corrections |
| Bloquants | 0 | 0 |
| Majeurs | 2 | 2 (3 relevés, dont 1 faux positif : les README lui étaient interdits) |
| Mineurs | 5 | 4 |
| Validations à la livraison | **5/5** | 4/5 (lint conteneur) |
| Tests creux signalés | 3 | 2 |
| Lignes script + cas | 176 + 105 | 207 + 183 |
| Relecture Opus | 33 991 jetons | 35 960 jetons |
| Coût de production | non mesuré | 0,22 $ pointe, dont 0,08 $ perdus |

### Ce que la comparaison établit

- **À la livraison, la qualité est du même ordre.** Même verdict, autant de
  défauts majeurs, aucun bloquant de part et d'autre. Le travail de Claude n'est
  pas meilleur selon cette grille.
- **Claude livre une version qui passe toutes les validations**, DeepSeek non.
  C'est l'écart le plus net, et il se rattrape en quelques lignes.
- **La gravité des majeurs diffère** : chez DeepSeek, le démon laissé arrêté
  après un échec est un risque d'exploitation ; chez Claude, ce sont un contrôle
  absent et des tests manquants.
- **La relecture coûte le même prix quel que soit l'auteur** : ~34 000 à 36 000
  jetons. Elle n'est donc pas un surcoût propre à la délégation — elle aurait dû
  exister aussi pour le travail de Claude, qui en avait besoin.
- **Là où DeepSeek perd, c'est à la correction** : une passe sur liste a réglé les
  défauts nommés mais introduit trois échecs et fait grossir les fichiers.

### Limite restante

Le coût en jetons de la production par Claude n'est toujours pas mesuré. Tant
qu'il ne l'est pas, on sait que la qualité est comparable, pas lequel coûte le
moins cher à qualité égale.

---

## TASK-032 — Sonnet en sous-agent, 2026-09-14

Protocole identique à TASK-030 : mêmes fichiers d'entrée, mêmes consignes,
**interdiction de lancer la moindre commande** — l'arbitre valide après.
Correction unique par un nouveau sous-agent, avec la grille d'Opus.

### Déroulé

| Étape | Résultat | Jetons |
|---|---|---|
| Génération Sonnet | 132 + 138 lignes. 4/5 : lint conteneur à 1 (2 × SC2015, 1 × SC1007). 34 vérifications réussies | 155 297 — 14 appels d'outils, 7 min 47 s |
| Relecture Opus | *fusionnable après corrections* : 0 bloquant, **1 majeur (le lint)**, 5 mineurs. Tous les critères conformes, sauf un partiel (CIDR IPv6 refusé) | 30 729 |
| Correction Sonnet | 148 + 147 lignes. `shellcheck` à 0, **36 vérifications, 0 échec, du premier coup** | 115 305 — 17 appels, 3 min 57 s |
| Rattrapage | **aucun** | — |
| Validations finales | **5/5** | — |

### Coût

Claude Code ne rapporte pour un sous-agent qu'un **total** de jetons, sans
séparer entrée et sortie. D'où une fourchette, au tarif Sonnet 5 (2 $ / 10 $ par
million) :

| | Jetons | Si tout est entrée | Si tout est sortie |
|---|---|---|---|
| Génération + correction Sonnet | 270 602 | 0,54 $ | 2,71 $ |
| Relecture Opus (5 $ / 25 $) | 30 729 | 0,15 $ | 0,77 $ |

Une boucle agentique renvoie tout son contexte à chaque appel d'outil : la
consommation est dominée par l'entrée, et une partie est lue en cache à prix
réduit. Le coût réel est donc **plus proche du bas de la fourchette** — sans
chiffre exact tant que la répartition n'est pas relevée dans la console Anthropic.

### Comparaison

| | TASK-030 — DeepSeek | TASK-032 — Sonnet |
|---|---|---|
| Défauts majeurs à la 1re livraison | 2 réels (dont démon laissé arrêté) | 1, le lint seul |
| Critères non tenus | 5 partiels | 1 partiel |
| Correction | **introduit 3 échecs** | **propre du premier coup** |
| Rattrapage par l'arbitre | 3 lignes | aucun |
| Taille finale | 228 + 294 | **148 + 147**, dans la cible |
| Coût de production | **0,22 $** exact, pointe | **0,54 à 2,71 $**, probablement bas de fourchette |
| Jetons pour produire | 3 appels, sortie 52 000 à 66 000 chacun | 2 sous-agents, 270 602 au total |

### Ce qu'on en retient

- **Sonnet livre mieux** : moins de défauts, aucun comportement faux, une
  correction sans régression, et la sobriété de decisions.md respectée sans effort.
- **DeepSeek coûte nettement moins cher par appel**, probablement 3 à 10 fois
  moins, mais son travail demande une relecture qui coûte le même prix et un
  rattrapage que Sonnet n'a pas demandé.
- **Une boucle agentique est chère en jetons** : 14 à 17 appels d'outils, chacun
  renvoyant le contexte. Un appel direct à l'API avec les fichiers joints —
  la façon dont DeepSeek a été appelé — serait bien plus économe pour Sonnet aussi.

### Limites

- **TASK-032 est plus simple que TASK-030** : ni fusion JSON, ni sauvegarde, ni
  redémarrage, ni restauration. Une part de l'écart de qualité tient à la tâche.
- **Mode d'appel différent** : DeepSeek par un appel d'API unique, Sonnet par un
  sous-agent qui lit lui-même les fichiers. Les jetons ne se comparent pas à
  structure égale.
- **Répartition entrée/sortie inconnue** pour Claude.

---

## TASK-033 — agent `deepseek` dans Claude Code, 2026-09-14

Premier passage dans le circuit d'orchestration (agents = Claude Code + modèle).

| Lancement | Tours | Entrée | Cache relu | Sortie | Durée | Résultat |
|---|---|---|---|---|---|---|
| 1, premier jet | 35 | 90 450 | 2 690 944 | 61 000 | 315 s | juge PASSE, 364 + 252 lignes |
| 2, retours de relecture | 52 | 77 978 | 4 533 760 | 64 615 | 564 s | juge PASSE, 168 + 219 lignes |

- Qualité du premier jet comparable à TASK-030 : validations vertes, mais 2 majeurs
  que seule la relecture Opus a vus (pas de `timeout`, test dépendant de l'image).
- **Contrairement à TASK-030, la correction par DeepSeek n'a pas régressé** : en
  mode agent, il relance lui-même le juge et corrige sur les lignes FAIL.
- Le mode agent relit tout son contexte à chaque tour : 7,2 M de jetons en cache.
  Au tarif du cache DeepSeek, cela reste le plus petit poste du coût.

---

## TASK-034 — essai comparatif de relecture, 2026-09-14

Même consigne, mêmes cinq fichiers, aucune commande, lancés en parallèle.

| | Opus | Sonnet |
|---|---|---|
| Verdict | FUSIONNABLE APRÈS CORRECTIONS | CONFORME AVEC RÉSERVES |
| Majeur : borne de 5 s sur `system df`, faux diagnostic | trouvé | **manqué** |
| Titre imprimé deux fois (`printf`), confirmé à la lecture | trouvé | **manqué** |
| Mineurs | 6 | 3, tous vus par Opus |
| Tests creux | 7 | 1 |
| Erreurs de constat | aucune | « français accentué intégral » (faux) ; 48 vérifications attribuées à l'intégration |
| Jetons | **37 957** | 47 098 |

**Conclusion : Opus reste le relecteur.** Il trouve davantage, et consomme moins
que Sonnet sur la même lecture. Une seule mesure ; DeepSeek relecteur non essayé.

Agent : la limite de 150 lignes, ajoutée après TASK-033, est tenue dès le premier
jet (150 + 149). Le premier lancement a duré 2 728 s pour 80 tours — trois fois
TASK-033 —, sans cause identifiée.
