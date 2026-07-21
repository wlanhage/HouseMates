/**
 * Inköpslista – tjänstelager (spec §7.3). Funktionerna tar `db` som argument
 * så de kan testas mot en in-memory-databas (spec §15).
 *
 * Dubblettskydd = partiellt unikt index på aktiva varor. Konflikt fångas och
 * hanteras som normalflöde (merge/duplicate), inte som fel.
 */
import type { Database } from 'better-sqlite3';
import { now, isUniqueViolation, toIso } from './sqlite-util';
import { HttpError } from './http';
import { logActivity } from './activity';
import type { ShoppingItem } from '$lib/types';

interface Row {
  id: string;
  name: string;
  name_norm: string;
  qty: string | null;
  checked: number;
  checked_by: string | null;
  checked_at: string | null;
  created_by: string;
  created_at: string;
  updated_at: string;
  version: number;
  archived_at: string | null;
  deleted_at: string | null;
}

function toItem(r: Row): ShoppingItem {
  return {
    id: r.id,
    name: r.name,
    qty: r.qty,
    checked: r.checked === 1,
    checked_by: r.checked_by,
    checked_at: toIso(r.checked_at),
    created_by: r.created_by,
    created_at: toIso(r.created_at)!,
    updated_at: toIso(r.updated_at)!,
    version: r.version
  };
}

const byId = (db: Database, id: string): Row | undefined =>
  db.prepare('SELECT * FROM shopping_items WHERE id = ?').get(id) as Row | undefined;

const activeByNorm = (db: Database, norm: string): Row | undefined =>
  db
    .prepare(
      'SELECT * FROM shopping_items WHERE name_norm = ? AND checked = 0 AND archived_at IS NULL AND deleted_at IS NULL'
    )
    .get(norm) as Row | undefined;

/** Aktiva varor (ej arkiverade/raderade), avbockade sist. */
export function listActive(db: Database): ShoppingItem[] {
  const rows = db
    .prepare(
      `SELECT * FROM shopping_items
       WHERE deleted_at IS NULL AND archived_at IS NULL
       ORDER BY checked ASC, created_at ASC`
    )
    .all() as Row[];
  return rows.map(toItem);
}

/** Autocomplete ur historiken (spec §7.3). */
export function suggest(db: Database, q: string): { name: string; count: number }[] {
  if (q) {
    return db
      .prepare(
        `SELECT name, COUNT(*) c, MAX(created_at) m
         FROM shopping_items WHERE name_norm LIKE ? || '%'
         GROUP BY name_norm ORDER BY c DESC, m DESC LIMIT 8`
      )
      .all(q.trim().toLowerCase()) as { name: string; count: number }[];
  }
  return db
    .prepare(
      `SELECT name, COUNT(*) c, MAX(created_at) m
       FROM shopping_items GROUP BY name_norm ORDER BY c DESC, m DESC LIMIT 8`
    )
    .all() as { name: string; count: number }[];
}

/** POST – idempotent på id, dubblett → merge (spec §7.3). */
export function add(
  db: Database,
  actor: string,
  input: { id: string; name: string; qty?: string | null }
): { item: ShoppingItem; merged: boolean } {
  const name = input.name.trim();
  if (!name) throw new HttpError('validation', 'Namn krävs.', 400);

  const existingById = byId(db, input.id);
  if (existingById) return { item: toItem(existingById), merged: false };

  const norm = name.toLowerCase();
  try {
    db.prepare(
      'INSERT INTO shopping_items (id, name, name_norm, qty, created_by) VALUES (?, ?, ?, ?, ?)'
    ).run(input.id, name, norm, input.qty ?? null, actor);
  } catch (e) {
    if (isUniqueViolation(e)) {
      const existing = activeByNorm(db, norm);
      if (existing) return { item: toItem(existing), merged: true };
    }
    throw e;
  }
  logActivity(db, {
    type: 'shopping.added',
    actor,
    entityType: 'shopping',
    entityId: input.id,
    payload: { name }
  });
  return { item: toItem(byId(db, input.id)!), merged: false };
}

/** PATCH – optimistisk låsning + ev. namnbyte (spec §7.3). */
export function patch(
  db: Database,
  actor: string,
  id: string,
  input: { version: number; checked?: boolean; name?: string; qty?: string | null }
): ShoppingItem {
  const row = byId(db, id);
  if (!row || row.deleted_at) throw new HttpError('not_found', 'Varan finns inte.', 404);
  if (input.version !== row.version) {
    throw new HttpError('version_conflict', 'Uppdaterades av någon annan.', 409, {
      current: toItem(row)
    });
  }

  let name = row.name;
  let norm = row.name_norm;
  let qty = row.qty;
  let checked = row.checked;
  let checkedBy = row.checked_by;
  let checkedAt = row.checked_at;
  let toggled: 'checked' | 'unchecked' | null = null;

  if (input.name !== undefined) {
    name = input.name.trim();
    if (!name) throw new HttpError('validation', 'Namn krävs.', 400);
    norm = name.toLowerCase();
  }
  if (input.qty !== undefined) qty = input.qty;
  if (input.checked !== undefined && input.checked !== (row.checked === 1)) {
    if (input.checked) {
      checked = 1;
      checkedBy = actor;
      checkedAt = now();
      toggled = 'checked';
    } else {
      checked = 0;
      checkedBy = null;
      checkedAt = null;
      toggled = 'unchecked';
    }
  }

  try {
    db.prepare(
      `UPDATE shopping_items
       SET name = ?, name_norm = ?, qty = ?, checked = ?, checked_by = ?, checked_at = ?,
           updated_at = ?, version = version + 1
       WHERE id = ?`
    ).run(name, norm, qty, checked, checkedBy, checkedAt, now(), id);
  } catch (e) {
    if (isUniqueViolation(e)) throw new HttpError('duplicate', 'Finns redan på listan.', 409);
    throw e;
  }

  if (toggled) {
    logActivity(db, {
      type: toggled === 'checked' ? 'shopping.checked' : 'shopping.unchecked',
      actor,
      entityType: 'shopping',
      entityId: id,
      payload: { name }
    });
  }
  return toItem(byId(db, id)!);
}

/** Töm avklarade – arkivera alla avbockade, logga EN rad med antal (spec §7.3).
 *  Returnerar arkiverade id:n så klienten kan erbjuda ångra (spec §12.1). */
export function archiveChecked(db: Database, actor: string): { count: number; ids: string[] } {
  const rows = db
    .prepare(
      'SELECT id FROM shopping_items WHERE checked = 1 AND archived_at IS NULL AND deleted_at IS NULL'
    )
    .all() as { id: string }[];
  const ids = rows.map((r) => r.id);
  if (ids.length === 0) return { count: 0, ids: [] };

  db.prepare(
    `UPDATE shopping_items SET archived_at = ?, updated_at = ?
     WHERE checked = 1 AND archived_at IS NULL AND deleted_at IS NULL`
  ).run(now(), now());

  logActivity(db, {
    type: 'shopping.archived',
    actor,
    entityType: 'shopping',
    entityId: '',
    payload: { count: ids.length }
  });
  return { count: ids.length, ids };
}

/** Ångra "Töm avklarade" – återställ archived_at (spec §12.1 kräver ångra).
 *  Kontraktet §7.3 saknar av-arkivering; se DECISIONS.md. Hoppar tyst över
 *  varor som skulle krocka med dubblettskyddet. */
export function unarchive(db: Database, _actor: string, ids: string[]): { restored: number } {
  let restored = 0;
  for (const id of ids) {
    try {
      const info = db
        .prepare('UPDATE shopping_items SET archived_at = NULL, updated_at = ? WHERE id = ? AND archived_at IS NOT NULL')
        .run(now(), id);
      restored += info.changes;
    } catch (e) {
      if (!isUniqueViolation(e)) throw e;
    }
  }
  return { restored };
}

/** Soft delete → ångra-toast. */
export function remove(db: Database, actor: string, id: string): { name: string } {
  const row = byId(db, id);
  if (!row || row.deleted_at) throw new HttpError('not_found', 'Varan finns inte.', 404);
  db.prepare(
    'UPDATE shopping_items SET deleted_at = ?, deleted_by = ?, updated_at = ? WHERE id = ?'
  ).run(now(), actor, now(), id);
  logActivity(db, {
    type: 'shopping.deleted',
    actor,
    entityType: 'shopping',
    entityId: id,
    payload: { name: row.name }
  });
  return { name: row.name };
}

/** Ångra radering – kan ge dubblettkonflikt (varan hann läggas till igen). */
export function restore(db: Database, actor: string, id: string): ShoppingItem {
  const row = byId(db, id);
  if (!row) throw new HttpError('not_found', 'Varan finns inte.', 404);
  try {
    db.prepare(
      'UPDATE shopping_items SET deleted_at = NULL, deleted_by = NULL, updated_at = ? WHERE id = ?'
    ).run(now(), id);
  } catch (e) {
    if (isUniqueViolation(e)) throw new HttpError('duplicate', 'Finns redan på listan.', 409);
    throw e;
  }
  logActivity(db, {
    type: 'shopping.restored',
    actor,
    entityType: 'shopping',
    entityId: id,
    payload: { name: row.name }
  });
  return toItem(byId(db, id)!);
}
