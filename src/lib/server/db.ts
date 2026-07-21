/**
 * better-sqlite3-instans (singleton) + hjälpare för transaktioner.
 *
 * DB-filen skapas/seedas av db/migrate.ts (npm run db:setup). Här öppnar vi
 * bara den befintliga filen. Om schemat saknas (tom fil) körs schema.sql en
 * gång som skyddsnät så att dev-servern inte startar mot en tom databas.
 */
import Database from 'better-sqlite3';
import { readFileSync, existsSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { env } from '$env/dynamic/private';
import { now, isUniqueViolation } from './sqlite-util';

export { now, isUniqueViolation };

const here = dirname(fileURLToPath(import.meta.url));
// db/schema.sql relativt projektroten (src/lib/server -> ../../../db)
const schemaPath = join(here, '..', '..', '..', 'db', 'schema.sql');

const dbPath = env.DATABASE_PATH ?? './dev.db';

// Cacha över HMR i dev så vi inte öppnar flera handtag mot samma fil.
const g = globalThis as unknown as { __planeraren_db?: Database.Database };

function open(): Database.Database {
  const fresh = !existsSync(dbPath);
  const database = new Database(dbPath);
  database.pragma('journal_mode = WAL');
  database.pragma('foreign_keys = ON');

  // Skyddsnät: om filen var ny eller saknar users-tabellen, kör schemat.
  const hasUsers = database
    .prepare("SELECT 1 FROM sqlite_master WHERE type='table' AND name='users'")
    .get();
  if ((fresh || !hasUsers) && existsSync(schemaPath)) {
    database.exec(readFileSync(schemaPath, 'utf8'));
  }

  // Runtime-migrering: todos.start_date (period-uppgifter, "gör inom X–Y").
  // schema.sql är normativ och lämnas orörd; kolumnen läggs till vid öppning.
  const todoCols = database.prepare('PRAGMA table_info(todos)').all() as { name: string }[];
  if (!todoCols.some((c) => c.name === 'start_date')) {
    database.exec('ALTER TABLE todos ADD COLUMN start_date TEXT');
  }
  return database;
}

export const db: Database.Database = g.__planeraren_db ?? (g.__planeraren_db = open());

/**
 * Kör fn i en transaktion. better-sqlite3 är synkront, så detta är säkert:
 * antingen commitas allt eller inget (viktigt för mutation + activity_log).
 */
export function tx<T>(fn: (database: Database.Database) => T): T {
  const run = db.transaction(fn);
  return run(db);
}

