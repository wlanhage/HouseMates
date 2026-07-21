/**
 * Skapar/uppdaterar appens två användare i produktionsdatabasen.
 * (Appen har ingen öppen registrering – detta är det medvetna seed-steget.)
 *
 * Kör på servern, från appkatalogen:
 *   cd /opt/planeraren
 *   sudo -u planeraren node --env-file=.env deploy/create-users.mjs \
 *     william William hemligt1 partner Partner hemligt2
 *
 * Argument: <id1> <Namn1> <lösenord1> <id2> <Namn2> <lösenord2>
 * Färger sätts automatiskt (rosa + blå). Körs igen = lösenord uppdateras.
 */
import { createRequire } from 'node:module';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { readFileSync, existsSync } from 'node:fs';

const appDir = join(dirname(fileURLToPath(import.meta.url)), '..');
const require = createRequire(join(appDir, 'package.json'));
const Database = require('better-sqlite3');
const argon2 = require('argon2');

const args = process.argv.slice(2);
if (args.length !== 6) {
  console.error(
    'Användning: node --env-file=.env deploy/create-users.mjs <id1> <Namn1> <lösen1> <id2> <Namn2> <lösen2>'
  );
  process.exit(1);
}

const dbPath = process.env.DATABASE_PATH;
if (!dbPath) {
  console.error('DATABASE_PATH saknas – kör med --env-file=.env');
  process.exit(1);
}

const db = new Database(dbPath);
db.pragma('foreign_keys = ON');

// Skapa schemat om appen inte hunnit starta ännu.
const hasUsers = db.prepare("SELECT 1 FROM sqlite_master WHERE type='table' AND name='users'").get();
if (!hasUsers) {
  const schemaPath = join(appDir, 'db', 'schema.sql');
  if (!existsSync(schemaPath)) {
    console.error('Hittar varken users-tabell eller db/schema.sql.');
    process.exit(1);
  }
  db.exec(readFileSync(schemaPath, 'utf8'));
}

const COLORS = ['#D4537E', '#378ADD'];
const users = [
  { id: args[0], name: args[1], password: args[2], color: COLORS[0] },
  { id: args[3], name: args[4], password: args[5], color: COLORS[1] }
];

for (const u of users) {
  if (!/^[a-z0-9_-]{2,20}$/.test(u.id)) {
    console.error(`Ogiltigt id "${u.id}" – använd 2–20 tecken a-z, 0-9, -, _`);
    process.exit(1);
  }
  if (u.password.length < 8) {
    console.error(`Lösenordet för "${u.id}" är för kort (minst 8 tecken).`);
    process.exit(1);
  }
  const hash = await argon2.hash(u.password);
  db.prepare(
    `INSERT INTO users (id, name, color, password_hash) VALUES (?, ?, ?, ?)
     ON CONFLICT(id) DO UPDATE SET name = excluded.name, password_hash = excluded.password_hash`
  ).run(u.id, u.name, u.color, hash);
  db.prepare('INSERT OR IGNORE INTO notification_prefs (user_id) VALUES (?)').run(u.id);
  console.log(`✓ ${u.id} (${u.name})`);
}

db.close();
console.log('Klart – logga in i appen med användarnamn + lösenord ovan.');
