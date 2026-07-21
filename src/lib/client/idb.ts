/** Gemensam IndexedDB: spegel (cache) + mutationskö (outbox). */
import { openDB, type IDBPDatabase } from 'idb';

interface Schema {
  cache: { key: string; value: unknown };
  outbox: {
    key: number;
    value: {
      seq?: number;
      method: 'POST' | 'PATCH' | 'DELETE';
      path: string;
      body?: unknown;
      entity: 'shopping' | 'todos';
    };
  };
}

let dbPromise: Promise<IDBPDatabase<Schema>> | null = null;

export function getDB(): Promise<IDBPDatabase<Schema>> {
  if (!dbPromise) {
    dbPromise = openDB<Schema>('planeraren', 1, {
      upgrade(db) {
        db.createObjectStore('cache');
        db.createObjectStore('outbox', { keyPath: 'seq', autoIncrement: true });
      }
    });
  }
  return dbPromise;
}

export type { Schema };
