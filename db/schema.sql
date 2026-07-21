-- Parplaneraren – SQLite-schema v1
-- Körs mot en fil per miljö: dev.db / prod.db (styrs via env, se .env.example)

PRAGMA foreign_keys = ON;
PRAGMA journal_mode = WAL;

-- ============================================================
-- Användare & sessioner
-- ============================================================

CREATE TABLE users (
  id                   TEXT PRIMARY KEY,          -- 'anna', 'erik' – korta, stabila id:n
  name                 TEXT NOT NULL,
  color                TEXT NOT NULL,             -- hex, används för färgkodning i UI
  password_hash        TEXT NOT NULL,             -- argon2/bcrypt
  caldav_username      TEXT,                      -- Apple-ID (sätts i onboarding)
  caldav_password_enc  BLOB,                      -- app-specifikt lösenord, krypterat i vila
  caldav_calendar_href TEXT,                      -- URL till kalendern "Gemensamt"
  created_at           TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE sessions (
  token_hash   TEXT PRIMARY KEY,                  -- hash av session-token, aldrig råvärdet
  user_id      TEXT NOT NULL REFERENCES users(id),
  created_at   TEXT NOT NULL DEFAULT (datetime('now')),
  expires_at   TEXT NOT NULL,                     -- långlivad, t.ex. +180 dagar
  last_seen_at TEXT
);

-- ============================================================
-- Kalender-cache (iCloud är master – detta är en spegel)
-- ============================================================
-- Tidsatta event: start_ts/end_ts i UTC (ISO-8601). Flerdagars tidsatta
--   event spänner naturligt över dygnsgränser via start/slut.
-- Heldagsevent: start_date/end_date som rena datum (YYYY-MM-DD), ALDRIG
--   som midnatt-UTC. end_date är EXKLUSIVT enligt iCal-konvention:
--   en heldag 24/12 har start_date=2026-12-24, end_date=2026-12-25.
--   Flerdagars heldagsevent = datumintervall.
-- Överlapp mot en dag D (lokal tid, konverterad i frontend/API):
--   tidsatta:  start_ts < D_slut_utc AND end_ts > D_start_utc
--   heldagar:  start_date <= D       AND end_date > D
-- Återkommande event expanderas till en rad per förekomst vid synk
--   (närmaste ~3 mån), identifierade av (caldav_uid, recurrence_id).

CREATE TABLE events (
  id            TEXT PRIMARY KEY,                 -- klientgenererat uuid (offline-säkert)
  caldav_uid    TEXT NOT NULL,
  recurrence_id TEXT NOT NULL DEFAULT '',         -- '' = enkelt event, annars förekomst-id
  caldav_href   TEXT,                             -- resursens URL i iCloud
  etag          TEXT,                             -- skickas som If-Match vid skrivning
  title         TEXT NOT NULL,
  location      TEXT,
  notes         TEXT,
  all_day       INTEGER NOT NULL DEFAULT 0,
  start_ts      TEXT,                             -- UTC, endast tidsatta event
  end_ts        TEXT,
  start_date    TEXT,                             -- endast heldagsevent
  end_date      TEXT,                             -- exklusivt slutdatum
  created_by    TEXT REFERENCES users(id),        -- NULL om skapat direkt i Apple Kalender
  raw_ics       TEXT,                             -- originalet: trogen återskrivning + ångra
  synced_at     TEXT,
  updated_at    TEXT NOT NULL DEFAULT (datetime('now')),
  deleted_at    TEXT,                             -- soft delete → ångra-toast
  deleted_by    TEXT REFERENCES users(id),
  CHECK (
    (all_day = 0 AND start_ts   IS NOT NULL AND end_ts   IS NOT NULL
                 AND start_date IS NULL     AND end_date IS NULL)
    OR
    (all_day = 1 AND start_date IS NOT NULL AND end_date IS NOT NULL
                 AND start_ts   IS NULL     AND end_ts   IS NULL)
  ),
  UNIQUE (caldav_uid, recurrence_id)
);

CREATE INDEX idx_events_timed  ON events(start_ts)   WHERE deleted_at IS NULL AND all_day = 0;
CREATE INDEX idx_events_allday ON events(start_date) WHERE deleted_at IS NULL AND all_day = 1;

-- ============================================================
-- Inköpslista
-- ============================================================
-- Dubblettskydd: name_norm = lower(trim(name)), sätts av API:t.
-- Partiellt unikt index nedan gör att två aktiva, oavbockade "mjölk"
-- inte kan existera. API:t fångar konflikten och returnerar den
-- befintliga varan istället för fel ("finns redan" / tyst merge).
-- Avbockade/arkiverade rader berörs inte – de utgör historiken
-- som driver autocomplete.

CREATE TABLE shopping_items (
  id          TEXT PRIMARY KEY,                   -- klientgenererat uuid (offline-kö)
  name        TEXT NOT NULL,
  name_norm   TEXT NOT NULL,
  qty         TEXT,                               -- fritext: "2 l", "3 st"
  checked     INTEGER NOT NULL DEFAULT 0,
  checked_by  TEXT REFERENCES users(id),
  checked_at  TEXT,
  created_by  TEXT NOT NULL REFERENCES users(id),
  created_at  TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at  TEXT NOT NULL DEFAULT (datetime('now')),
  version     INTEGER NOT NULL DEFAULT 1,         -- optimistisk låsning, se API-kontrakt
  archived_at TEXT,                               -- "Töm avklarade" → arkiv, ej radering
  deleted_at  TEXT,                               -- soft delete → ångra-toast
  deleted_by  TEXT REFERENCES users(id)
);

CREATE UNIQUE INDEX idx_shopping_active_name ON shopping_items(name_norm)
  WHERE checked = 0 AND archived_at IS NULL AND deleted_at IS NULL;

CREATE INDEX idx_shopping_autocomplete ON shopping_items(name_norm, created_at);

-- ============================================================
-- Att göra
-- ============================================================

CREATE TABLE todos (
  id          TEXT PRIMARY KEY,                   -- klientgenererat uuid
  title       TEXT NOT NULL,
  notes       TEXT,
  assignee    TEXT,                               -- users.id, 'both', eller NULL (otilldelad)
  due_date    TEXT,                               -- YYYY-MM-DD, valfri
  done        INTEGER NOT NULL DEFAULT 0,
  done_by     TEXT REFERENCES users(id),
  done_at     TEXT,
  created_by  TEXT NOT NULL REFERENCES users(id),
  created_at  TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at  TEXT NOT NULL DEFAULT (datetime('now')),
  version     INTEGER NOT NULL DEFAULT 1,
  deleted_at  TEXT,
  deleted_by  TEXT REFERENCES users(id)
);

CREATE INDEX idx_todos_open ON todos(due_date, created_at)
  WHERE done = 0 AND deleted_at IS NULL;

-- ============================================================
-- Aktivitetslogg (append-only – driver hemskärmen och notiser)
-- ============================================================
-- type-exempel: 'shopping.added', 'shopping.checked', 'shopping.restored',
--               'todo.created', 'todo.done', 'todo.deleted',
--               'event.created', 'event.updated', 'event.deleted'
-- Ångra loggas som '*.restored' så flödet blir ärligt utan att skämma ut någon.

CREATE TABLE activity_log (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  type        TEXT NOT NULL,
  actor       TEXT NOT NULL REFERENCES users(id),
  entity_type TEXT NOT NULL,                      -- 'shopping' | 'todo' | 'event'
  entity_id   TEXT NOT NULL,
  payload     TEXT,                               -- JSON-snapshot, t.ex. {"name":"Mjölk"}
  created_at  TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX idx_activity_recent ON activity_log(created_at DESC);

-- ============================================================
-- Notiser (web push med tysta timmar + digest)
-- ============================================================
-- Flöde: varje mutation loggas i activity_log → en rad per MOTTAGARE
-- (dvs. den andra personen) läggs i notification_queue med
-- send_after = now + digest_minutes. En worker plockar förfallna,
-- ogrupperade rader per mottagare, slår ihop till EN notis
-- ("Anna la till 3 varor och bockade av 1 todo") och skickar.
-- Ligger klockan inom tysta timmar flyttas send_after till quiet_to.

CREATE TABLE push_subscriptions (
  id         INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id    TEXT NOT NULL REFERENCES users(id),
  endpoint   TEXT NOT NULL UNIQUE,
  p256dh     TEXT NOT NULL,
  auth       TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  failed_at  TEXT                                 -- prenumerationer som failar rensas
);

CREATE TABLE notification_prefs (
  user_id        TEXT PRIMARY KEY REFERENCES users(id),
  enabled        INTEGER NOT NULL DEFAULT 1,
  quiet_from     TEXT NOT NULL DEFAULT '21:00',   -- lokal tid
  quiet_to       TEXT NOT NULL DEFAULT '07:30',
  digest_minutes INTEGER NOT NULL DEFAULT 10
);

CREATE TABLE notification_queue (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  recipient   TEXT NOT NULL REFERENCES users(id),
  activity_id INTEGER NOT NULL REFERENCES activity_log(id),
  created_at  TEXT NOT NULL DEFAULT (datetime('now')),
  send_after  TEXT NOT NULL,
  sent_at     TEXT
);

CREATE INDEX idx_queue_unsent ON notification_queue(recipient, send_after)
  WHERE sent_at IS NULL;

-- ============================================================
-- CalDAV-synkstatus (driver "senast synkad" + felbanner)
-- ============================================================

CREATE TABLE sync_state (
  user_id        TEXT PRIMARY KEY REFERENCES users(id),
  sync_token     TEXT,
  last_synced_at TEXT,
  last_error     TEXT,
  failing_since  TEXT                             -- > 1 h gammal → banner i UI + notis
);

-- ============================================================
-- Städjobb (körs som cron, t.ex. nattligen)
-- ============================================================
-- 1. Hård radering av soft-deletes äldre än 30 dagar:
--      DELETE FROM shopping_items WHERE deleted_at < datetime('now','-30 days');
--      DELETE FROM todos          WHERE deleted_at < datetime('now','-30 days');
--      DELETE FROM events         WHERE deleted_at < datetime('now','-30 days');
-- 2. Klara todos äldre än 30 dagar: DELETE ... WHERE done=1 AND done_at < ...
-- 3. Skickade notiser äldre än 7 dagar ur notification_queue.
-- 4. Push-prenumerationer med failed_at äldre än 7 dagar.
-- OBS: shopping_items med archived_at raderas ALDRIG automatiskt – de är
-- autocomplete-historiken.
