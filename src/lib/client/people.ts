/** Uppslag id → namn/färg för färgkodning (spec §12.1). */
import { derived } from 'svelte/store';
import { user, me } from './stores';
import type { User } from '$lib/types';

export const people = derived([user, me], ([$user, $me]) => {
  const map = new Map<string, User>();
  if ($user) map.set($user.id, $user);
  if ($me?.user) map.set($me.user.id, $me.user);
  if ($me?.partner) map.set($me.partner.id, $me.partner);
  return map;
});

const strip = (name: string) => name.replace(/\s*\(test\)\s*/i, '').trim();

export function nameOf(map: Map<string, User>, id: string | null, selfId?: string): string {
  if (!id) return 'Ingen';
  if (id === 'both') return 'Gemensamt';
  if (selfId && id === selfId) return 'Du';
  const u = map.get(id);
  return u ? strip(u.name) : id;
}

export function colorOf(map: Map<string, User>, id: string | null): string {
  if (!id || id === 'both') return '#6b7280';
  return map.get(id)?.color ?? '#6b7280';
}

export function initialOf(map: Map<string, User>, id: string | null): string {
  if (!id) return '?';
  if (id === 'both') return '·';
  const u = map.get(id);
  return u ? strip(u.name).charAt(0).toUpperCase() : '?';
}
