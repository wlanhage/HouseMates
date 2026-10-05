// Kör notis-workern lokalt (torrt, utan APNs-nyckel) och visar vilka notiser som skulle skickas.
// Förutsätter: smoke.mjs har körts och `supabase functions serve` är igång i native/.
import { createClient } from '@supabase/supabase-js';
import { apiUrl, secretKey } from './local.mjs';

const CRON_SECRET = process.env.CRON_SECRET ?? 'lokal-hemlighet';

const service = createClient(apiUrl, secretKey, { auth: { persistSession: false } });

// Låtsas att det glidande fönstret har löpt ut, och ge alla en enhet att skicka till.
const { data: pending } = await service.from('notification_queue').select('recipient').is('sent_at', null);
for (const recipient of new Set(pending.map((p) => p.recipient))) {
  await service.from('device_tokens').upsert({ token: `simulator-${recipient}`, user_id: recipient });
}
await service.from('notification_queue').update({ send_after: new Date().toISOString() }).is('sent_at', null);

const response = await fetch(`${apiUrl}/functions/v1/notify`, { method: 'POST', headers: { 'x-cron-secret': CRON_SECRET } });
console.log(response.status, JSON.stringify(await response.json(), null, 2));
