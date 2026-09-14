// deleguer.mjs — confie une fiche de tâche à DeepSeek et écrit les fichiers rendus.
//
// Usage :
//   node deleguer.mjs <depot> --liste
//   node deleguer.mjs <depot> <modele> <fiche> [--exemple chemin]... [--effort low|high|max] [--retours fichier]
//
// DeepSeek écrit le script, son fichier de cas et un *.env.example. Les README
// restent à l'arbitre : ils sont partagés par toutes les tâches.
// La clé est lue dans DEEPSEEK_API_KEY, jamais affichée ni écrite. Seuls des
// fichiers versionnés sont envoyés — jamais un config/*.env.
import { readFileSync, writeFileSync, appendFileSync, mkdirSync, existsSync } from "node:fs";
import { dirname, join } from "node:path";
import { request } from "node:https";

const [depot, modele, fiche, ...reste] = process.argv.slice(2);
const cle = process.env.DEEPSEEK_API_KEY;
if (!cle) { console.error("DEEPSEEK_API_KEY absente."); process.exit(1); }

// node:https plutôt que fetch : fetch abandonne au bout de 300 s sans en-têtes,
// et un modèle qui raisonne longtemps dépasse ce délai.
function appel(methode, chemin, corps) {
  return new Promise((ok, ko) => {
    const r = request({ host: "api.deepseek.com", path: chemin, method: methode,
      headers: { Authorization: `Bearer ${cle}`, "Content-Type": "application/json" } }, rep => {
      let t = ""; rep.on("data", d => (t += d)); rep.on("end", () => ok({ statut: rep.statusCode, json: JSON.parse(t || "{}") }));
    });
    r.on("error", ko); if (corps) r.write(JSON.stringify(corps)); r.end();
  });
}

if (modele === "--liste") {
  const { statut, json } = await appel("GET", "/models");
  console.log(statut, (json.data || []).map(m => m.id).join(" "));
  process.exit(statut === 200 ? 0 : 1);
}

const exemples = [], lire = p => readFileSync(join(depot, p), "utf8");
let retours = null, effort = null;
for (let i = 0; i < reste.length; i++) {
  if (reste[i] === "--exemple") exemples.push(reste[++i]);
  else if (reste[i] === "--retours") retours = reste[++i];
  else if (reste[i] === "--effort") effort = reste[++i];
}

const PERMIS = /^(Docker\/[A-Za-z]+\/[a-z-]+\.sh|tests\/integration\/[a-z-]+\.test\.sh|config\/[a-z-]+\.env\.example)$/;
const bloc = p => `<<<FICHIER ${p}>>>\n${lire(p)}\n<<<FIN>>>`;

const systeme = `Tu réalises une tâche d'un dépôt Bash d'administration système.
Respecte strictement CLAUDE.md, réutilise lib/common.sh, ne redéfinis rien de ce qu'il fournit.
Sobriété : un script vise ~150 lignes, un fichier de cas aussi ; les commentaires n'expliquent que ce que le code ne dit pas seul.
Tout fichier .sh doit passer shellcheck sans aucun avertissement, y compris de niveau info.
Produis le script, son fichier de cas dans tests/integration/, et le config/*.env.example si la fiche le demande. Ne produis AUCUN README.
Le conteneur de test n'a ni Docker, ni systemd, ni jq : éprouve tout par de faux binaires en tête de PATH.
Réponds UNIQUEMENT par des blocs de cette forme, sans texte autour :
<<<FICHIER chemin/relatif>>>
contenu complet
<<<FIN>>>`;

const contexte = ["CLAUDE.md", "lib/common.sh", "tests/lib/assert.sh", ...exemples]
  .map(p => `# ${p}\n${lire(p)}`).join("\n\n");
let demande = `${contexte}\n\n# Fiche de tâche\n${lire(fiche)}`;
if (retours) {
  const produits = [...readFileSync(retours, "utf8").matchAll(/^PRODUIT (.+)$/gm)].map(m => m[1]);
  demande += `\n\n# Ta livraison précédente\n${produits.filter(p => existsSync(join(depot, p))).map(bloc).join("\n")}`
    + `\n\n# Retours à corriger — rends à nouveau les fichiers complets\n${readFileSync(retours, "utf8").replace(/^PRODUIT .+\n/gm, "")}`;
}

const debut = Date.now();
const { statut, json } = await appel("POST", "/chat/completions", {
  model: modele, ...(effort && { reasoning_effort: effort }),
  messages: [{ role: "system", content: systeme }, { role: "user", content: demande }] });
if (statut !== 200) { console.error(`HTTP ${statut} :`, JSON.stringify(json.error || json)); process.exit(1); }

const choix = json.choices?.[0] ?? {}, texte = choix.message?.content ?? "";
const arret = choix.finish_reason ?? "?";
const ecrits = [];
for (const [, chemin, contenu] of texte.matchAll(/<<<FICHIER ([^>]+)>>>\n([\s\S]*?)\n?<<<FIN>>>/g)) {
  const p = chemin.trim();
  if (!PERMIS.test(p)) { console.error(`REFUSÉ, hors liste blanche : ${p}`); continue; }
  mkdirSync(dirname(join(depot, p)), { recursive: true });
  writeFileSync(join(depot, p), contenu.replace(/\r\n/g, "\n").replace(/\n?$/, "\n"));
  ecrits.push(p);
}

const u = json.usage || {}, duree = ((Date.now() - debut) / 1000).toFixed(1);
appendFileSync(join(depot, "docs/agent/mesures/appels.tsv"), [new Date().toISOString(), fiche, modele,
  (retours ? "correction" : "generation") + "/" + (effort ?? "defaut") + "/" + arret, u.prompt_tokens, u.prompt_cache_hit_tokens ?? 0, u.completion_tokens, duree].join("\t") + "\n");
for (const p of ecrits) console.log(`PRODUIT ${p}`);
console.log(`entrée ${u.prompt_tokens}, sortie ${u.completion_tokens}, ${duree} s, arrêt « ${arret} », contenu ${texte.length} car.`);
process.exit(ecrits.length ? 0 : 1);
