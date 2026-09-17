#!/usr/bin/env bash
# lancer-agent.sh — fait exécuter une tâche par un agent (orchestration/README.md).
#
# L'agent est une instance de Claude Code, sans interface, pilotée par le modèle
# externe décrit dans orchestration/modeles/<nom>.env, ou par un modèle Claude
# (sonnet, opus, haiku) sur l'abonnement. Il travaille dans une copie
# séparée du dépôt (git worktree) sur la branche agent/<TASK>, et n'y fait que
# ce que permet orchestration/limites.json.
#
# Usage : lancer-agent.sh <profil> <TASK-XXX> [fichier de retours]
#   Le fichier de retours, facultatif, porte les défauts relevés par la
#   relecture : l'agent les corrige au lieu de repartir de zéro.
# Codes : celui de l'agent (0 terminé) — 2 usage ou prérequis manquant.
set -Eeuo pipefail

ici="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
racine="$(cd "$ici/../.." && pwd)"
profil="${1:-}" tache="${2:-}" retours="${3:-}"

usage() { echo "Usage : lancer-agent.sh <profil> <TASK-XXX> [fichier de retours]" >&2; exit 2; }
case "$profil" in sonnet|opus|haiku) ;; *) [ -f "$ici/../modeles/$profil.env" ] || usage ;; esac
[[ "$tache" =~ ^TASK-[0-9]{3}$ ]] || usage
[ -f "$racine/tasks/active/$tache.md" ] || { echo "tasks/active/$tache.md absent : l'orchestrateur active la fiche avant." >&2; exit 2; }
if [ -n "$retours" ] && [ ! -f "$retours" ]; then
    echo "Fichier de retours introuvable : $retours" >&2; exit 2
fi
command -v claude >/dev/null || { echo "claude introuvable dans le PATH." >&2; exit 2; }

# Un modèle Claude passe par l'abonnement, sans profil. Un autre modèle a son
# profil : adresse, modèle, variable de clé et tarifs ; lu ligne à ligne, jamais exécuté.
ADRESSE="" MODELE="$profil" VARIABLE_CLE="" PRIX_ENTREE="" PRIX_CACHE="" PRIX_SORTIE=""
if [ -f "$ici/../modeles/$profil.env" ]; then
    while IFS='=' read -r cle valeur; do
        case "$cle" in
            ADRESSE) ADRESSE="$valeur" ;; MODELE) MODELE="$valeur" ;; VARIABLE_CLE) VARIABLE_CLE="$valeur" ;;
            PRIX_ENTREE) PRIX_ENTREE="$valeur" ;; PRIX_CACHE) PRIX_CACHE="$valeur" ;; PRIX_SORTIE) PRIX_SORTIE="$valeur" ;;
        esac
    done < "$ici/../modeles/$profil.env"
fi
[ -n "$MODELE" ] || { echo "Profil $profil : MODELE vide." >&2; exit 2; }

# Environnement de l'agent. Sans adresse : l'abonnement Claude, rien à régler.
env_agent=(env -u ANTHROPIC_BASE_URL -u ANTHROPIC_API_KEY -u ANTHROPIC_AUTH_TOKEN)
if [ -n "$ADRESSE" ]; then
    [ -n "${!VARIABLE_CLE:-}" ] || { echo "Profil $profil : la variable $VARIABLE_CLE est vide." >&2; exit 2; }
    env_agent+=("ANTHROPIC_BASE_URL=$ADRESSE" "ANTHROPIC_API_KEY=${!VARIABLE_CLE}"
        "ANTHROPIC_MODEL=$MODELE" "ANTHROPIC_DEFAULT_HAIKU_MODEL=$MODELE"
        "ANTHROPIC_DEFAULT_SONNET_MODEL=$MODELE" "ANTHROPIC_DEFAULT_OPUS_MODEL=$MODELE")
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

consigne="/executer-tache $tache"
if [ -n "$retours" ]; then
    cp "$retours" "$copie/RETOURS-$tache.md"
    consigne="$consigne RETOURS-$tache.md"
fi

echo "AGENT  $profil ($MODELE) sur $tache, dans $copie"
debut=$(date +%s)
code=0
# Plafond de durée (A08) : un agent qui tourne en rond est arrêté au bout d'une heure.
DUREE_MAX="${DUREE_MAX:-3600}"
borne=(); command -v timeout >/dev/null 2>&1 && borne=(timeout "$DUREE_MAX")
sortie="$(cd "$copie" && "${env_agent[@]}" "${borne[@]}" claude -p "$consigne" \
    --model "$MODELE" \
    --setting-sources project \
    --settings "$ici/../limites.json" \
    --strict-mcp-config \
    --permission-mode acceptEdits \
    --output-format json)" || code=$?
rm -f "$copie/RETOURS-$tache.md"

# Relevé : une ligne par lancement. Le coût se calcule au tarif du profil,
# pas au total_cost_usd de Claude Code, qui applique les prix Anthropic.
journal="$racine/orchestration/mesures/agents.tsv"
[ -f "$journal" ] || printf 'date\ttache\tprofil\tmodele\ttours\tentree\tentree_cache\tsortie\tduree_s\tcode\tcout_usd\n' > "$journal"
# Coût au tarif du profil (A09) ; vide pour un modèle Claude, facturé à l'abonnement.
node -e '
    const [sortie, ...champs] = process.argv.slice(1);
    let j = {}; try { j = JSON.parse(sortie); } catch {}
    const u = j.usage || {};
    const cache = (u.cache_read_input_tokens || 0) + (u.cache_creation_input_tokens || 0);
    const [date, tache, profil, modele, duree, code, pe, pc, ps] = champs;
    // Relevé incomplet (A122). claude -p ne rend que la dernière boucle de la
    // session : une notification de tâche de fond (Monitor, commande passée en
    // arrière-plan) arrivée après la réponse en relance une d’un tour, seule
    // comptée (TASK-071 : 1 tour, 243 jetons, pour 81 appels au modèle en 2269 s).
    // Une sortie vide ou illisible (agent tué par DUREE_MAX) ne se compte pas non plus.
    if (!j.usage || !(j.num_turns > 1 || (j.num_turns === 1 && +duree <= 600))) {
        console.log([date, tache, profil, modele, "incomplet", "?", "?", "?", duree, code, "?"].join("\t"));
        console.error(`RELEVÉ INCOMPLET : ${j.num_turns ?? "?"} tour(s) pour ${duree} s ; jetons réels dans ` +
            `~/.claude/projects/<copie>/${j.session_id ?? "<session>"}.jsonl`);
    } else {
        const cout = pe ? ((u.input_tokens * pe + cache * pc + u.output_tokens * ps) / 1e6).toFixed(3) : "";
        console.log([date, tache, profil, modele, j.num_turns, u.input_tokens, cache,
                     u.output_tokens, duree, code, cout].join("\t"));
    }
    console.error(j.result || "(aucune réponse lisible de cet agent)");
' "$sortie" "$(date '+%F %T')" "$tache" "$profil" "$MODELE" "$(( $(date +%s) - debut ))" "$code" \
    "$PRIX_ENTREE" "$PRIX_CACHE" "$PRIX_SORTIE" >> "$journal"

tail -1 "$journal"
exit "$code"
