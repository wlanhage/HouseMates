// Adress och nycklar till den lokala databasen, hämtade från CLI:t så att inga nycklar ligger i repot.
import { execSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const status = JSON.parse(
  execSync('supabase status -o json', {
    cwd: fileURLToPath(new URL('..', import.meta.url)),
    stdio: ['ignore', 'pipe', 'ignore']
  }).toString()
);

export const apiUrl = status.API_URL;
export const publishableKey = status.PUBLISHABLE_KEY;
export const secretKey = status.SECRET_KEY;
