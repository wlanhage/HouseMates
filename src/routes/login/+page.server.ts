import type { PageServerLoad } from './$types';
import { db } from '$lib/server/db';
import type { User } from '$lib/types';

export const load: PageServerLoad = () => {
  const users = db.prepare('SELECT id, name, color FROM users ORDER BY name').all() as User[];
  return { users };
};
