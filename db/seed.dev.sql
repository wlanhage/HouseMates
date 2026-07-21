-- Seed för LOKAL utvecklingsdatabas (dev.db) – körs efter schema.sql.
-- Skapa aldrig konton i prod på annat sätt än ett medvetet seed-script;
-- appen har ingen öppen registrering.
--
-- Setup:   sqlite3 dev.db < schema.sql && sqlite3 dev.db < seed.dev.sql
-- Nollställ: rm dev.db och kör om raden ovan.
--
-- Viktigt: peka dev-miljön mot en SEPARAT testkalender i iCloud
-- (t.ex. "Gemensamt-test"), aldrig er riktiga. Styrs via .env:
--   DATABASE_PATH=./dev.db
--   CALDAV_CALENDAR_NAME=Gemensamt-test
-- I prod:
--   DATABASE_PATH=/data/prod.db
--   CALDAV_CALENDAR_NAME=Gemensamt

-- Lösenordet nedan är 'devlosen' hashat med bcrypt (cost 10) – byt gärna,
-- eller generera egna hashar i er seed-pipeline.
INSERT INTO users (id, name, color, password_hash) VALUES
  ('anna', 'Anna (test)', '#D4537E', '$2b$10$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy'),
  ('erik', 'Erik (test)', '#378ADD', '$2b$10$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy');

INSERT INTO notification_prefs (user_id) VALUES ('anna'), ('erik');

-- Lite testdata så vyerna inte är tomma från start
INSERT INTO shopping_items (id, name, name_norm, created_by) VALUES
  ('seed-shop-1', 'Mjölk',  'mjölk',  'anna'),
  ('seed-shop-2', 'Bröd',   'bröd',   'erik'),
  ('seed-shop-3', 'Kaffe',  'kaffe',  'anna');

INSERT INTO todos (id, title, assignee, due_date, created_by) VALUES
  ('seed-todo-1', 'Boka bilbesiktning', 'erik', date('now', '+7 days'), 'anna'),
  ('seed-todo-2', 'Planera helgen',     'both', NULL,                   'erik');

INSERT INTO activity_log (type, actor, entity_type, entity_id, payload) VALUES
  ('shopping.added', 'anna', 'shopping', 'seed-shop-1', '{"name":"Mjölk"}'),
  ('todo.created',   'anna', 'todo',     'seed-todo-1', '{"title":"Boka bilbesiktning"}');
