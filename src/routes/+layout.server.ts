import { redirect } from '@sveltejs/kit';
import type { LayoutServerLoad } from './$types';

export const load: LayoutServerLoad = ({ locals, url }) => {
  const path = url.pathname;
  const onLogin = path === '/login';

  if (!locals.user && !onLogin) throw redirect(302, '/login');
  if (locals.user && onLogin) throw redirect(302, '/');

  return { user: locals.user };
};
