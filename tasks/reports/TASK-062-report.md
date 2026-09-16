# TASK-062 — Rapport d'exécution

## Compte rendu
TASK-062 (`install-kubectl.sh`) est terminée et fusionnée. C'est le premier script de `Kubernetes/Installation/`. Malgré son nom, la décision 48 lui interdit d'installer quoi que ce soit : K3s pose déjà `kubectl` et `/etc/rancher/k3s/k3s.yaml`. Le script **vérifie** donc seulement, sans root :
- que `kubectl` est présent ;
- l'architecture de la machine et la version du client ;
- que le kubeconfig existe et se lit ;
- l'accès au cluster et la version du serveur.

S'il ne trouve aucun kubeconfig, il explique la copie à faire et rend 1, sans rien copier lui-même.

L'agent DeepSeek a livré en deux passages 150 lignes de script et 173 lignes de cas. Le juge et les trois validations de la fiche rendaient 0, et le périmètre était respecté. Les notes de la fiche lui donnaient d'avance les défauts connus du domaine : faux `kubectl` aux vrais formats, garde `/.dockerenv`, `--request-timeout` sur chaque appel, `timeout` externe et code 124, causes distinguées, pas de `[SUCCESS]` après une rubrique en échec.

La relecture Opus a jugé le travail fusionnable après corrections et relevé deux majeurs :
- **la commande de copie conseillée était fausse** : `sudo install -m 0600 … ~/.kube/config` crée un fichier appartenant à root, que le compte ne peut pas lire ;
- **un kubeconfig invalide était mal nommé** : `Unauthorized`, une erreur de certificat `x509` ou un fichier mal formé étaient présentés comme un apiserver injoignable ou muet.

Elle a aussi relevé :
- des mineurs : versions de forme inattendue, valeur de `KUBECONFIG` tronquée au dernier chemin, faux Forbidden et faux `version` incomplets ;
- des tests creux : des recherches dans le code source au lieu de preuves de comportement, et le cas « illisible » éprouvé par un dossier plutôt que par un fichier sans droits.

La relance unique a tout corrigé. La commande affichée est désormais `install -d -m 0700 ~/.kube && sudo install -o "$(id -u)" -g "$(id -g)" -m 0600 /etc/rancher/k3s/k3s.yaml ~/.kube/config`, écrite telle quelle, avec une ligne sur `127.0.0.1` pour un poste distant. Les trois erreurs donnent « kubeconfig invalide ou périmé », le cas x509 étant testé avant « Unable to connect ». Enfin, deux cas s'exécutent sous le compte `nobody` : un kubeconfig en 0000, puis un cas sain. Aucune vérification n'a disparu sans remplacement justifié dans le commit : les lignes d'assertion passent de 59 à 86, et le nombre de vérifications de 66 à 101.

Il n'y a pas eu de seconde relecture. Le conducteur a relu les deux majeurs dans le code, puis lancé le script en conteneur avec un faux `kubectl` rendant chacun des trois messages. Les trois donnent la bonne cause avec le code 1, et la commande de copie sort sans que `$(id -u)` soit évalué.

Réserves : la version corrigée n'a pas été relue par Opus, et rien n'a été constaté contre un vrai cluster (A98). Le fichier de cas fait 244 lignes (A99). Enfin, un refus `Forbidden` sur `get nodes` rend 1 alors que l'apiserver répond (A100).

Coût agent : 0,308 $ en deux lancements ; relecture : 30 849 jetons.

## Statut
COMPLETED

## Travail réalisé
- `Kubernetes/Installation/install-kubectl.sh` — 150 lignes
- `tests/integration/install-kubectl.test.sh` — 244 lignes, 101 vérifications. Faux `kubectl` en tête de PATH qui journalise chaque appel ; messages réels sur stderr (refus de connexion, Forbidden complet, Unauthorized, x509, error loading config file) ; faux `timeout` rendant 124 ; faux `uname` ; exécutions en `nobody` par `setpriv`.
- par le conducteur : `Kubernetes/Installation/README.md` (créé, avec la commande de copie correcte), `Kubernetes/README.md`, README racine (`Installation` : 1 script), backlog (TASK-064 et TASK-066 débloquées), journal, registre (A98, A99, A100)

## Déroulé
| Étape | Qui | Résultat |
|---|---|---|
| activation | conducteur | commit 72300ba (fiche, statut, backlog, défauts connus du domaine en notes) |
| lancement 1 | agent `deepseek` | 2 passages, 71 tours, 484 s, 0,175 $ ; 150 + 173 lignes ; commits ca9fda0, c911862 |
| vérification | conducteur | juge 0 (66 vérifications) ; périmètre : 2 fichiers du scope ; lignes d'assertion 59 → 59, test modifié au passage 1 pour shellcheck seulement |
| relecture | Opus, 7 appels, 30 849 jetons, 78 s | FUSIONNABLE APRÈS CORRECTIONS — 2 majeurs, mineurs, tests creux |
| relance | agent `deepseek` | 58 tours, 400 s, 0,133 $ ; 150 + 244 lignes ; commit d9a3b40, chaque changement de test justifié |
| vérification | conducteur | périmètre : 2 fichiers ; lignes d'assertion 59 → 86 : une assertion de copie remplacée par trois plus une, deux greps sur le source remplacés par le journal d'appels et deux exécutions en `nobody` ; majeurs relus et rejoués en conteneur |

## Validations (relancées par le conducteur dans la copie de l'agent, version finale)
| Commande | Code |
|---|---|
| `bash orchestration/outils/juger.sh tasks/active/TASK-062.md` | 0 — shellcheck 0, fichier de cas 0, règles du dépôt 3 (NON EXÉCUTÉ d'environnement) ; LONGUEUR signalée 244 |
| `tests/env/run-in-container.sh -- tests/run.sh lint` | 0 — 102 fichiers, 0 erreur, 2 avertissements (scripts Synology hérités) |
| `tests/env/run-in-container.sh -- tests/run.sh integration` | 0 — install-kubectl.sh 101 réussies, 0 échec, 0 NON EXÉCUTÉ |
| `tests/env/run-in-container.sh -- bash Kubernetes/Installation/install-kubectl.sh --help` | 0 |

## Sondes du conducteur (conteneur `debian`, version finale)
Faux `kubectl` : `version --client` rend un JSON réel, tout autre appel écrit le message sur stderr et rend 1 ; `KUBECONFIG` vide, `~/.kube/config` présent.

| Message de kubectl | Sortie | Code |
|---|---|---|
| `error: You must be logged in to the server (Unauthorized)` | « Kubeconfig invalide ou périmé : « kubectl get nodes » a été refusé. » | 1 |
| `Unable to connect to the server: tls: failed to verify certificate: x509: certificate signed by unknown authority` | idem | 1 |
| `error: error loading config file "/root/.kube/config": yaml: line 3: …` | idem | 1 |
| aucun kubeconfig (`HOME` vide) | commande de copie affichée littéralement, `$(id -u)` non évalué, ligne `127.0.0.1` | 1 |

Lecture du code : aucun `kubectl config`, aucune lecture du kubeconfig ni de `k3s.yaml`, rien copié ni installé ; seule écriture, un `mktemp -d` effacé par `trap`.

## Git
Activation 72300ba ; branche `agent/TASK-062` (ca9fda0, c911862, d9a3b40) fusionnée `--no-ff` (355bb36), copie retirée, branche supprimée. Pas de push.

## Réserves
- A98 — version corrigée non relue par Opus ; aucun essai contre un vrai kubectl ni un vrai K3s ; expiration de `--request-timeout` côté kubectl non nommée ; stderr de kubectl réaffiché sans preuve qu'il ne cite jamais le kubeconfig.
- A99 — fichier de cas à 244 lignes, au-delà des ~150.
- A100 — un `Forbidden` sur `kubectl get nodes` rend 1 alors que l'apiserver répond.
