/**
 * Enkel databas-setup för Parplaneraren.
 *
 *   tsx db/migrate.ts            – skapa DB från schema.sql om filen saknas
 *   tsx db/migrate.ts --seed     – ...och kör seed.dev.sql (endast dev!)
 *   tsx db/migrate.ts --reset    – radera DB-filen först
 *
 * Medvetet minimal: schema.sql är normativt och versioneras inte i v1.
 * Framtida schemaändringar hanteras som numrerade filer i db/migrations/
 * (finns inte ännu) – bygg det först när det behövs.
 */
import Database from 'better-sqlite3';
import * as argon2 from 'argon2';
import { readFileSync, existsSync, rmSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const dbPath = process.env.DATABASE_PATH ?? './dev.db';
const args = new Set(process.argv.slice(2));

if (args.has('--reset')) {
  for (const suffix of ['', '-wal', '-shm']) {
    const p = dbPath + suffix;
    if (existsSync(p)) rmSync(p);
  }
  console.log(`Raderade ${dbPath}`);
}

if (existsSync(dbPath)) {
  console.log(`${dbPath} finns redan – ingen åtgärd. Kör med --reset för att börja om.`);
  process.exit(0);
}

const db = new Database(dbPath);
db.exec(readFileSync(join(here, 'schema.sql'), 'utf8'));
console.log(`Skapade ${dbPath} från db/schema.sql`);

if (args.has('--seed')) {
  db.exec(readFileSync(join(here, 'seed.dev.sql'), 'utf8'));

  // seed.dev.sql levererar en placeholder-hash (bcrypt) som inte matchar det
  // dokumenterade dev-lösenordet. Specen kräver argon2 (§2/§6) och seed-filen
  // uppmanar själv till att "generera egna hashar i er seed-pipeline" – så det
  // gör vi här: sätt argon2-hash av 'devlosen' på testanvändarna.
  const DEV_PASSWORD = 'devlosen';
  const hash = await argon2.hash(DEV_PASSWORD);
  db.prepare("UPDATE users SET password_hash = ? WHERE id IN ('anna','erik')").run(hash);

  console.log('Körde db/seed.dev.sql (testanvändare: anna / erik, lösenord: devlosen)');
}

db.close();
