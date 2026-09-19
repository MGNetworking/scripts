#!/usr/bin/env bash
# lancer-agent.sh — fait exécuter une tâche par un agent (orchestration/README.md).
#
# L'agent est une instance de Claude Code, sans interface, pilotée par le modèle
# externe décrit dans orchestration/modeles/<nom>.env, ou par un modèle Claude
# (sonnet, opus, haiku) sur l'abonnement. Il travaille dans une copie
# séparée du dépôt (git worktree) sur la branche agent/<TASK>, et n'y fait que
# ce que permet orchestration/limites.json.
#
# Usage : lancer-agent.sh <profil> <TASK-XXX> [fichier] [--modele <alias>] [--relecture] [--dry-run]
#   Le fichier, facultatif, porte les défauts relevés par la relecture : l'agent les
#   corrige au lieu de repartir de zéro. Avec --relecture, il porte au contraire les
#   sorties de vérification, remises telles quelles au relecteur.
#   --modele  choisit un modèle du profil (anthropic : haiku, sonnet, opus) ; défaut MODELE_DEFAUT.
#   --relecture fait relire le travail au lieu de l'écrire : consigne de relecture, agent
#             « relecteur », outils de lecture seule. Le mode et le modèle par défaut se
#             lisent dans orchestration/relecture.json.
#   --dry-run affiche profil, modèle, tarifs et présence de la clé, sans rien lancer ni dépenser.
# Codes : celui de l'agent (0 terminé) — 2 usage ou prérequis manquant.
set -Eeuo pipefail

ici="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
racine="$(cd "$ici/../.." && pwd)"
usage() { echo "Usage : lancer-agent.sh <profil> <TASK-XXX> [fichier] [--modele <alias>] [--relecture] [--dry-run]" >&2; exit 2; }
modele="" dry=0 relecture=0 pos=()
while [ $# -gt 0 ]; do case "$1" in
    --modele) [[ "${2:-}" =~ ^[A-Za-z0-9_-]+$ ]] || usage; modele="$2"; shift 2 ;;
    --relecture) relecture=1; shift ;;
    --dry-run) dry=1; shift ;;
    *) pos+=("$1"); shift ;;
esac; done
profil="${pos[0]:-}" tache="${pos[1]:-}" retours="${pos[2]:-}"

case "$profil" in sonnet|opus|haiku) ;; *) [ -f "$ici/../modeles/$profil.env" ] || usage ;; esac
[[ "$tache" =~ ^TASK-[0-9]{3}$ ]] || [ "$dry" -eq 1 ] || usage
[ "$dry" -eq 1 ] || [ -f "$racine/tasks/active/$tache.md" ] || { echo "tasks/active/$tache.md absent : l'orchestrateur active la fiche avant." >&2; exit 2; }
if [ -n "$retours" ] && [ ! -f "$retours" ]; then
    echo "Fichier de retours introuvable : $retours" >&2; exit 2
fi
[ "$dry" -eq 1 ] || command -v claude >/dev/null || { echo "claude introuvable dans le PATH." >&2; exit 2; }

# --relecture : l'interrupteur orchestration/relecture.json dit qui relit — l'API par ce
# script, ou le sous-agent relecteur sur l'abonnement (tache.md, étape 6). Le réglage porte
# aussi le modèle par défaut de la relecture, que --modele peut encore changer.
colonne="$profil"
if [ "$relecture" -eq 1 ]; then
    reglage="$ici/../relecture.json"
    [ -f "$reglage" ] || { echo "orchestration/relecture.json est absent : rien ne dit qui relit." >&2; exit 2; }
    champ() { sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" "$reglage" | head -1; }
    mode="$(champ mode)"
    case "$mode" in
        api) ;;
        abonnement) echo "relecture.json : mode « abonnement » — la relecture passe par le sous-agent relecteur (.claude/commands/tache.md, étape 6), pas par ce script." >&2; exit 2 ;;
        *) echo "relecture.json : mode « $mode » inconnu ; attendu « api » ou « abonnement »." >&2; exit 2 ;;
    esac
    [ -n "$modele" ] || modele="$(champ modele)"
    colonne="relecteur"
fi

# Un modèle Claude passe par l'abonnement, sans profil. Un autre modèle a son
# profil : adresse, modèle, variable de clé et tarifs ; lu ligne à ligne, jamais exécuté.
ADRESSE="" MODELE="$profil" VARIABLE_CLE="" PRIX_ENTREE="" PRIX_CACHE="" PRIX_SORTIE="" DEFAUT=""
declare -A alias_modele=() alias_prix=()
if [ -f "$ici/../modeles/$profil.env" ]; then
    while IFS='=' read -r cle valeur; do
        case "$cle" in
            ADRESSE) ADRESSE="$valeur" ;; MODELE) MODELE="$valeur" ;; VARIABLE_CLE) VARIABLE_CLE="$valeur" ;;
            PRIX_ENTREE) PRIX_ENTREE="$valeur" ;; PRIX_CACHE) PRIX_CACHE="$valeur" ;; PRIX_SORTIE) PRIX_SORTIE="$valeur" ;;
            MODELE_DEFAUT) DEFAUT="$valeur" ;; MODELE_*) alias_modele["${cle#MODELE_}"]="$valeur" ;;
            PRIX_*) alias_prix["${cle#PRIX_}"]="$valeur" ;;
        esac
    done < "$ici/../modeles/$profil.env"
fi
# Profil à plusieurs modèles : --modele choisit un alias, sinon MODELE_DEFAUT.
if [ "${#alias_modele[@]}" -gt 0 ]; then
    choix="${modele:-$DEFAUT}"
    [ -n "${alias_modele[${choix:-_}]:-}" ] || {
        echo "Profil $profil : modèle « $choix » inconnu. Disponibles : ${!alias_modele[*]}" >&2; exit 2; }
    MODELE="${alias_modele[$choix]}"; read -r PRIX_ENTREE PRIX_CACHE PRIX_SORTIE <<< "${alias_prix[$choix]:-}"
elif [ -n "$modele" ]; then echo "Profil $profil : pas de choix de modèle (--modele)." >&2; exit 2; fi
[ -n "$MODELE" ] || { echo "Profil $profil : MODELE vide." >&2; exit 2; }

# Environnement de l'agent. Sans adresse : l'abonnement Claude, rien à régler.
env_agent=(env -u ANTHROPIC_BASE_URL -u ANTHROPIC_API_KEY -u ANTHROPIC_AUTH_TOKEN)
if [ -n "$ADRESSE" ]; then
    cle_api="$(bash "$ici/resoudre-cle.sh" "$VARIABLE_CLE")" || {
        echo "Profil $profil : la variable $VARIABLE_CLE est introuvable (environnement, puis variables utilisateur de Windows)." >&2; exit 2; }
    env_agent+=("ANTHROPIC_BASE_URL=$ADRESSE" "ANTHROPIC_API_KEY=$cle_api"
        "ANTHROPIC_MODEL=$MODELE" "ANTHROPIC_DEFAULT_HAIKU_MODEL=$MODELE"
        "ANTHROPIC_DEFAULT_SONNET_MODEL=$MODELE" "ANTHROPIC_DEFAULT_OPUS_MODEL=$MODELE")
fi
# --dry-run : dit ce qui serait lancé, sans copie, sans agent, sans dépense, et sans jamais montrer la clé.
if [ "$dry" -eq 1 ]; then
    echo "DRY-RUN  profil=$profil modèle=$MODELE tarifs=${PRIX_ENTREE:--}/${PRIX_CACHE:--}/${PRIX_SORTIE:--} clé=$([ -n "$ADRESSE" ] && echo trouvée || echo "sans objet")$([ "$relecture" -eq 1 ] && echo " relecture=oui")"; exit 0
fi

# Copie séparée, hors du dépôt pour que le lint ne la parcoure pas.
copie="$(dirname "$racine")/$(basename "$racine")-agents/$tache"
if [ ! -d "$copie" ]; then
    mkdir -p "$(dirname "$copie")"
    if git -C "$racine" rev-parse -q --verify "agent/$tache" >/dev/null; then
        git -C "$racine" worktree add -q "$copie" "agent/$tache"
    else
        git -C "$racine" worktree add -q -b "agent/$tache" "$copie" master
    fi
fi

if [ "$relecture" -eq 1 ]; then
    # Le relecteur n'a que la lecture : il lit les fichiers de l'arbre, il ne rejoue rien.
    consigne="Relis le travail de $tache. Cet arbre est la branche agent/$tache : les fichiers y sont dans leur état final. La fiche est tasks/active/$tache.md — reprends ses critères d'acceptation un par un, lis les fichiers de son scope, et rends ton verdict dans le format de ta consigne."
    if [ -n "$retours" ]; then
        cp "$retours" "$copie/VERIFICATION-$tache.md"
        consigne="$consigne Les validations ont déjà été lancées : leurs codes réels sont dans VERIFICATION-$tache.md, à reprendre tels quels."
    fi
else
    consigne="/executer-tache $tache"
    if [ -n "$retours" ]; then
        cp "$retours" "$copie/RETOURS-$tache.md"
        consigne="$consigne RETOURS-$tache.md"
    fi
fi

echo "$([ "$relecture" -eq 1 ] && echo RELECTURE || echo AGENT)  $profil ($MODELE) sur $tache, dans $copie"
debut=$(date +%s)
code=0
# Plafond de durée (A08) : un agent qui tourne en rond est arrêté au bout d'une heure.
DUREE_MAX="${DUREE_MAX:-3600}"
borne=(); command -v timeout >/dev/null 2>&1 && borne=(timeout "$DUREE_MAX")
options=(--model "$MODELE" --setting-sources project --strict-mcp-config --output-format json)
if [ "$relecture" -eq 1 ]; then
    # Lecture seule : ni Bash, ni Edit, ni Write. Le relecteur est défini une seule fois,
    # dans .claude/agents/relecteur.md, que --setting-sources project rend visible.
    options+=(--agent relecteur --tools "Read,Grep,Glob")
else
    options+=(--settings "$ici/../limites.json" --permission-mode acceptEdits
        --disallowed-tools Artifact ArtifactComments ArtifactData)
fi
sortie="$(cd "$copie" && "${env_agent[@]}" "${borne[@]}" claude -p "$consigne" "${options[@]}")" || code=$?
rm -f "$copie/RETOURS-$tache.md" "$copie/VERIFICATION-$tache.md"

# Relevé : une ligne par lancement. Le coût se calcule au tarif du profil,
# pas au total_cost_usd de Claude Code, qui applique les prix Anthropic.
journal="$racine/orchestration/mesures/agents.tsv"
[ -f "$journal" ] || printf 'date\ttache\tprofil\tmodele\ttours\tentree\tentree_cache\tsortie\tduree_s\tcode\tcout_usd\n' > "$journal"
# Coût au tarif du profil (A09) ; vide pour un modèle Claude, facturé à l'abonnement.
# Jetons lus dans le transcript de la session, pas dans la sortie JSON de claude -p
# (A122) : celle-ci ne rend que la dernière boucle. Une notification de tâche de fond
# (Monitor, commande passée en arrière-plan) arrivée après la réponse en relance une,
# seule comptée : TASK-071, 1 tour et 243 jetons pour 81 appels au modèle en 2269 s.
# Transcript introuvable (sortie vide d'un agent tué par DUREE_MAX, session inconnue) :
# relevé « incomplet ». Tours : appels distincts au modèle.
node -e '
    const fs = require("fs"), path = require("path"), os = require("os");
    const [sortie, date, tache, profil, modele, duree, code, pe, pc, ps, rel] = process.argv.slice(1);
    let j = {}; try { j = JSON.parse(sortie); } catch {}
    const ids = [...sortie.matchAll(/"session_id"\s*:\s*"([^"]+)"/g)].map(m => m[1]);
    const projets = path.join(process.env.CLAUDE_CONFIG_DIR || path.join(os.homedir(), ".claude"), "projects");
    const appels = new Map();
    for (const d of ids.length && fs.existsSync(projets) ? fs.readdirSync(projets) : []) {
        const f = path.join(projets, d, ids[ids.length - 1] + ".jsonl");
        if (!fs.existsSync(f)) continue;
        for (const l of fs.readFileSync(f, "utf8").split("\n")) {
            try { const m = JSON.parse(l).message; if (m.role === "assistant" && m.id && m.usage) appels.set(m.id, m.usage); } catch {}
        }
    }
    let entree = 0, cache = 0, produits = 0;
    for (const u of appels.values()) {
        entree += u.input_tokens || 0; produits += u.output_tokens || 0;
        cache += (u.cache_read_input_tokens || 0) + (u.cache_creation_input_tokens || 0);
    }
    if (appels.size === 0) {
        console.log([date, tache, profil, modele, "incomplet", "?", "?", "?", duree, code, "?"].join("\t"));
        console.error("RELEVÉ INCOMPLET : transcript de session introuvable (" + (ids.pop() || "aucune session") + ")");
    } else {
        const cout = pe ? ((entree * pe + cache * pc + produits * ps) / 1e6).toFixed(3) : "";
        console.log([date, tache, profil, modele, appels.size, entree, cache, produits, duree, code, cout].join("\t"));
    }
    if (rel !== "1") console.error(j.result || "(aucune réponse lisible de cet agent)");
' "$sortie" "$(date '+%F %T')" "$tache" "$colonne" "$MODELE" "$(( $(date +%s) - debut ))" "$code" \
    "$PRIX_ENTREE" "$PRIX_CACHE" "$PRIX_SORTIE" "$relecture" >> "$journal"

# Relecture : le verdict est la sortie utile du lancement ; il part sur stdout, tel quel.
if [ "$relecture" -eq 1 ]; then
    node -e 'let j = {}; try { j = JSON.parse(process.argv[1]); } catch {}
        console.log(j.result || "(aucune réponse lisible du relecteur)");' "$sortie"
fi

tail -1 "$journal"
exit "$code"
