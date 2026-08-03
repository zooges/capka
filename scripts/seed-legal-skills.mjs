import { readFile, readdir } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { randomUUID } from "node:crypto";
import pg from "pg";

const { Pool } = pg;
const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const SKILLS_DIR = join(ROOT, "skills-pack", "legal");
const DATABASE_URL = process.env.DATABASE_URL
  ?? "postgresql://Capka:Capka@127.0.0.1:5432/Capka";
const NAME_PATTERN = /^[a-z0-9]+(?:-[a-z0-9]+)*$/;

function parseSkill(source, filePath) {
  const lines = source.replace(/^\uFEFF/, "").split(/\r?\n/);
  if (lines[0] !== "---") {
    throw new Error(`${filePath}: 缺少 YAML frontmatter 起始分隔符。`);
  }

  const end = lines.indexOf("---", 1);
  if (end === -1) {
    throw new Error(`${filePath}: 缺少 YAML frontmatter 结束分隔符。`);
  }

  const frontmatter = {};
  for (const line of lines.slice(1, end)) {
    if (!line.trim() || line.trimStart().startsWith("#")) continue;
    const match = line.match(/^([A-Za-z0-9_-]+):\s*(.*)$/);
    if (!match) throw new Error(`${filePath}: 无法解析 frontmatter 行：${line}`);

    const [, key, rawValue] = match;
    const value = rawValue.replace(/^(["'])(.*)\1$/, "$2").trim();
    frontmatter[key] = value;
  }

  if (typeof frontmatter.name !== "string" || !NAME_PATTERN.test(frontmatter.name)) {
    throw new Error(`${filePath}: name 必须为 kebab-case。`);
  }
  if (typeof frontmatter.description !== "string" || !frontmatter.description) {
    throw new Error(`${filePath}: description 必须为非空字符串。`);
  }

  return {
    name: frontmatter.name,
    description: frontmatter.description,
    body: lines.slice(end + 1).join("\n").replace(/^\n/, ""),
    frontmatter,
  };
}

async function loadSkills() {
  const entries = await readdir(SKILLS_DIR, { withFileTypes: true });
  const skills = await Promise.all(entries
    .filter((entry) => entry.isDirectory())
    .map(async (entry) => {
      const filePath = join(SKILLS_DIR, entry.name, "SKILL.md");
      return parseSkill(await readFile(filePath, "utf8"), filePath);
    }));

  if (skills.length === 0) throw new Error(`未找到 ${SKILLS_DIR} 中的 SKILL.md。`);
  return skills.sort((a, b) => a.name.localeCompare(b.name));
}

async function seedSkill(client, skill) {
  // The schema has no unique index for (scope, name, source). An advisory lock
  // keeps this update-then-insert sequence idempotent across concurrent runs.
  await client.query("SELECT pg_advisory_xact_lock(hashtext($1))", [
    `skills:system:${skill.name}:manual`,
  ]);

  const existing = await client.query(
    `UPDATE skills
     SET description = $1, body = $2, frontmatter = $3::jsonb, enabled = true, updated_at = now()
     WHERE scope = 'system' AND name = $4 AND source = 'manual'
     RETURNING id`,
    [skill.description, skill.body, JSON.stringify(skill.frontmatter), skill.name],
  );

  if (existing.rowCount > 0) return "updated";

  await client.query(
    `INSERT INTO skills (
       id, scope, user_id, project_id, name, description, body, frontmatter, source, enabled
     ) VALUES ($1, 'system', NULL, NULL, $2, $3, $4, $5::jsonb, 'manual', true)`,
    [
      randomUUID(),
      skill.name,
      skill.description,
      skill.body,
      JSON.stringify(skill.frontmatter),
    ],
  );
  return "inserted";
}

const pool = new Pool({ connectionString: DATABASE_URL });

try {
  const skills = await loadSkills();
  const client = await pool.connect();
  try {
    for (const skill of skills) {
      await client.query("BEGIN");
      try {
        const action = await seedSkill(client, skill);
        await client.query("COMMIT");
        console.log(`${action}: ${skill.name}`);
      } catch (error) {
        await client.query("ROLLBACK");
        throw error;
      }
    }
  } finally {
    client.release();
  }
} finally {
  await pool.end();
}
