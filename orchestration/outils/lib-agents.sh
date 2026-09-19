#!/usr/bin/env bash
# lib-agents.sh — les gestes d'un lanceur d'agent qui ne doivent rien à un dépôt.
#
# Ce fichier est une BIBLIOTHÈQUE : il se charge par « source », ne s'exécute
# jamais seul, et ne pose ni « set -Eeuo pipefail » ni trap — les deux
# s'appliqueraient au shell appelant sans qu'il les ait demandés.
#
# Les gestes qu'il offre, tous paramétrés par leurs arguments et sans état
# partagé :
#
#   copie_isolee   <racine> <branche> <copie> [base]
#       crée la copie de travail isolée si elle manque, par « git worktree »
#   plafond_duree  <secondes>
#       écrit le préfixe de commande qui borne la durée d'un agent ; rien s'il
#       n'existe pas de « timeout » sur la machine
#   profil_lire    <fichier>
#       écrit les couples CLÉ<TAB>VALEUR d'un profil, sans jamais l'exécuter
#   releve_jetons  <sortie> <tache> <profil> <modele> <duree_s> <code> <prix_entree> <prix_cache> <prix_sortie>
#       écrit la ligne de mesure — tours, jetons, coût — lue dans le transcript
#       de la session, et non dans la sortie rendue par l'agent, qui ne porte
#       que sa dernière boucle
#   journal_agents <fichier> <en-tete> <ligne>
#       ajoute une ligne à un journal tabulé, en posant l'en-tête s'il est neuf
#   resultat_agent <sortie> <flux> <texte de repli>
#       écrit la réponse lisible de l'agent sur stdout, sur stderr, ou nulle part
#
# Rien ici ne connaît un dépôt, un chemin de projet ni un nom de tâche : ce qui
# dépend d'un projet est un argument, ou reste chez l'appelant.

if [ -n "${_LIB_AGENTS_CHARGE:-}" ]; then
    return 0
fi
_LIB_AGENTS_CHARGE=1

# copie_isolee <racine> <branche> <copie> [base] — crée <copie> si elle manque :
# sur <branche> si elle existe déjà, sinon sur une branche neuve tirée de <base>.
# Idempotent : une copie déjà en place n'est jamais refaite, ce qui laisse intact
# le travail qu'un agent y a commencé.
copie_isolee() {
    local racine="$1" branche="$2" copie="$3" base="${4:-master}"
    [ -d "$copie" ] && return 0
    mkdir -p "$(dirname "$copie")"
    if git -C "$racine" rev-parse -q --verify "$branche" >/dev/null; then
        git -C "$racine" worktree add -q "$copie" "$branche"
    else
        git -C "$racine" worktree add -q -b "$branche" "$copie" "$base"
    fi
}

# plafond_duree <secondes> — écrit sur stdout le préfixe de commande qui borne la
# durée, un mot par ligne, prêt pour « mapfile ». Un agent qui tourne en rond
# doit être arrêté ; sans « timeout », rien n'est écrit et l'appelant lance sans
# plafond plutôt que d'échouer.
plafond_duree() {
    if command -v timeout >/dev/null 2>&1; then
        printf 'timeout\n%s\n' "$1"
    fi
}

# profil_lire <fichier> — écrit les couples du profil, un par ligne, sous la forme
# « CLÉ<TAB>VALEUR » ; le premier « = » sépare les deux. Les lignes vides et
# commentées sont ignorées. Le fichier est LU, jamais exécuté : aucune de ses
# lignes n'est évaluée comme du shell. Un fichier absent n'écrit rien.
profil_lire() {
    local cle valeur
    [ -f "$1" ] || return 0
    while IFS='=' read -r cle valeur; do
        case "$cle" in '' | '#'*) continue ;; esac
        printf '%s\t%s\n' "$cle" "$valeur"
    done < "$1"
}

# releve_jetons <sortie> <tache> <profil> <modele> <duree_s> <code> <prix_entree> <prix_cache> <prix_sortie>
# — écrit la ligne de mesure, onglets compris, prête à verser au journal.
#
# Les jetons sont sommés depuis le transcript de la session, pas depuis la sortie
# JSON de l'agent : celle-ci ne rend que la dernière boucle, qu'une notification
# de tâche de fond relance. Transcript introuvable — agent tué par le plafond de
# durée, session inconnue — : la ligne porte « incomplet ».
#
# Le coût se calcule aux tarifs donnés, en dollars par million de jetons ; il
# reste vide quand ils manquent, faute de tarif connu.
releve_jetons() {
    node -e '
        const fs = require("fs"), path = require("path"), os = require("os");
        const [sortie, date, tache, profil, modele, duree, code, pe, pc, ps] = process.argv.slice(1);
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
    ' "$1" "$(date '+%F %T')" "$2" "$3" "$4" "$5" "$6" "$7" "$8" "$9"
}

# journal_agents <fichier> <en-tete> <ligne> — ajoute <ligne> au journal, et pose
# <en-tete> si le fichier n'existe pas encore. Ni le nombre ni l'ordre des colonnes
# ne sont connus ici : ils appartiennent à l'appelant, qui les passe en clair.
journal_agents() {
    [ -f "$1" ] || printf '%s\n' "$2" > "$1"
    printf '%s\n' "$3" >> "$1"
}

# resultat_agent <sortie> <flux> <texte de repli> — écrit la réponse lisible de
# l'agent sur le flux demandé : « stdout », « stderr », ou rien pour tout autre
# mot. <texte de repli> prend sa place quand la sortie n'en porte aucune.
resultat_agent() {
    node -e 'let j = {}; try { j = JSON.parse(process.argv[1]); } catch {}
        const r = j.result || process.argv[3];
        if (process.argv[2] === "stdout") console.log(r);
        else if (process.argv[2] === "stderr") console.error(r);' "$1" "$2" "$3"
}
