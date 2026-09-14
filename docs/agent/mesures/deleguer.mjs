// deleguer.mjs — demande à DeepSeek d'écrire un script à partir d'une fiche.
// Usage : node deleguer.mjs <depot> <modele|--liste> <sortie.sh> [erreurs.txt]
// La clé est lue dans DEEPSEEK_API_KEY et n'est jamais affichée ni écrite.
import { readFileSync, writeFileSync, appendFileSync, existsSync } from "node:fs";
import { join } from "node:path";

const [depot, modele, sortie, erreurs] = process.argv.slice(2);
const cle = process.env.DEEPSEEK_API_KEY;
if (!cle) { console.error("DEEPSEEK_API_KEY absente."); process.exit(1); }
const BASE = "https://api.deepseek.com";
const entetes = { Authorization: `Bearer ${cle}`, "Content-Type": "application/json" };

if (modele === "--liste") {
  const r = await fetch(`${BASE}/models`, { headers: entetes });
  const j = await r.json();
  console.log(r.status, (j.data || []).map(m => m.id).join(" ") || JSON.stringify(j));
  process.exit(r.ok ? 0 : 1);
}

// N'envoyer que des fichiers déjà publics : jamais config/*.env.
const lire = p => readFileSync(join(depot, p), "utf8");
const fiche = lire("tasks/pending/TASK-031.md");
const regles = lire("CLAUDE.md");
const socle = lire("lib/common.sh");

const systeme = `Tu écris un script Bash pour un dépôt d'administration système.
Respecte strictement les conventions fournies (CLAUDE.md) et réutilise lib/common.sh.
Vise environ 150 lignes : les commentaires n'expliquent que ce que le code ne dit pas seul.
Le script doit passer shellcheck sans avertissement, y compris de niveau info.
Réponds UNIQUEMENT par le contenu du fichier, dans un seul bloc \`\`\`bash, sans texte autour.`;

let utilisateur = `# Conventions du dépôt (CLAUDE.md)\n${regles}\n\n# lib/common.sh\n${socle}\n\n# Fiche de tâche\n${fiche}\n\nÉcris le fichier Docker/Diagnostics/check-docker.sh. Le fichier de cas n'est pas demandé.`;
if (erreurs && existsSync(erreurs)) {
  utilisateur += `\n\n# Ta version précédente a échoué à ces vérifications. Corrige-la.\n${readFileSync(erreurs, "utf8")}\n\n# Ta version précédente\n${readFileSync(sortie, "utf8")}`;
}

const debut = Date.now();
const r = await fetch(`${BASE}/chat/completions`, {
  method: "POST", headers: entetes,
  body: JSON.stringify({ model: modele, messages: [
    { role: "system", content: systeme }, { role: "user", content: utilisateur }] }),
});
const j = await r.json();
if (!r.ok) { console.error(`HTTP ${r.status} :`, JSON.stringify(j.error || j)); process.exit(1); }

const texte = j.choices?.[0]?.message?.content ?? "";
const bloc = texte.match(/```(?:bash|sh)?\n([\s\S]*?)```/);
writeFileSync(sortie, (bloc ? bloc[1] : texte).replace(/\r\n/g, "\n"));

const u = j.usage || {};
const ligne = [new Date().toISOString(), modele, u.prompt_tokens ?? "?", u.completion_tokens ?? "?",
  u.prompt_cache_hit_tokens ?? "?", ((Date.now() - debut) / 1000).toFixed(1)].join("\t");
appendFileSync(join(sortie, "..", "consommation.tsv"), ligne + "\n");
console.log(`écrit ${sortie} — entrée ${u.prompt_tokens ?? "?"}, sortie ${u.completion_tokens ?? "?"}, ${((Date.now() - debut) / 1000).toFixed(1)} s`);
