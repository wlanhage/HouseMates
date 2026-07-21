import Database from 'better-sqlite3';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const here = dirname(fileURLToPath(import.meta.url));

/** In-memory-databas med schemat + två testanvändare (spec §15). */
export function makeDb(): Database.Database {
  const db = new Database(':memory:');
  db.pragma('foreign_keys = ON');
  db.exec(readFileSync(join(here, '..', 'db', 'schema.sql'), 'utf8'));
  db.prepare(
    `INSERT INTO users (id, name, color, password_hash) VALUES
       ('anna', 'Anna', '#D4537E', 'x'),
       ('erik', 'Erik', '#378ADD', 'x')`
  ).run();
  db.prepare("INSERT INTO notification_prefs (user_id) VALUES ('anna'), ('erik')").run();
  return db;
}
