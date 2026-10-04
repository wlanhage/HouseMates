// Spike server: ICS feed (path B) and CalDAV configuration profile (path C).
// No dependencies. Every feed fetch is logged, so we can see how often iOS refreshes.
import { createServer } from 'node:http';
import { randomUUID } from 'node:crypto';

const BIND = process.env.BIND ?? '127.0.0.1';
const PORT = 8787;
const CALDAV_PORT = 5232;
const CALDAV_USER = 'hushall';
const CALDAV_PASSWORD = 'spike-losen'; // local Radicale only

const hoursFromNow = (hours) => new Date(Date.now() + hours * 3_600_000);
const daysFromToday = (days) => {
  const date = new Date();
  date.setDate(date.getDate() + days);
  return date.toISOString().slice(0, 10);
};

const events = [
  { uid: randomUUID(), title: 'Middag hos Anna', allDay: false, start: hoursFromNow(24), end: hoursFromNow(26) },
  { uid: randomUUID(), title: 'Städdag', allDay: true, start: daysFromToday(2), end: daysFromToday(3) }
];

const icsText = (text) => text.replace(/\\/g, '\\\\').replace(/;/g, '\\;').replace(/,/g, '\\,').replace(/\n/g, '\\n');
const icsUtc = (date) => date.toISOString().replace(/[-:]/g, '').replace(/\.\d{3}/, '');
const icsDate = (ymd) => ymd.replace(/-/g, '');

function feed() {
  const lines = [
    'BEGIN:VCALENDAR',
    'VERSION:2.0',
    'PRODID:-//HouseMates//Spike//SV',
    'X-WR-CALNAME:HouseMates',
    'X-PUBLISHED-TTL:PT5M',
    'REFRESH-INTERVAL;VALUE=DURATION:PT5M'
  ];
  for (const event of events) {
    lines.push('BEGIN:VEVENT', `UID:${event.uid}`, `DTSTAMP:${icsUtc(new Date())}`, `SUMMARY:${icsText(event.title)}`);
    if (event.url) lines.push(`URL:${event.url}`);
    if (event.allDay) {
      lines.push(`DTSTART;VALUE=DATE:${icsDate(event.start)}`, `DTEND;VALUE=DATE:${icsDate(event.end)}`);
    } else {
      lines.push(`DTSTART:${icsUtc(event.start)}`, `DTEND:${icsUtc(event.end)}`);
    }
    lines.push('END:VEVENT');
  }
  lines.push('END:VCALENDAR');
  return lines.join('\r\n') + '\r\n';
}

function profile(host) {
  return `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>PayloadContent</key>
  <array>
    <dict>
      <key>CalDAVAccountDescription</key><string>HouseMates</string>
      <key>CalDAVHostName</key><string>${host}</string>
      <key>CalDAVPort</key><integer>${CALDAV_PORT}</integer>
      <key>CalDAVPrincipalURL</key><string>/${CALDAV_USER}/</string>
      <key>CalDAVUseSSL</key><false/>
      <key>CalDAVUsername</key><string>${CALDAV_USER}</string>
      <key>CalDAVPassword</key><string>${CALDAV_PASSWORD}</string>
      <key>PayloadDisplayName</key><string>HouseMates-kalender</string>
      <key>PayloadIdentifier</key><string>se.housemates.spike.caldav</string>
      <key>PayloadType</key><string>com.apple.caldav.account</string>
      <key>PayloadUUID</key><string>6C1A9E52-3F0B-4C63-9D7E-2B8F4A1C5D10</string>
      <key>PayloadVersion</key><integer>1</integer>
    </dict>
  </array>
  <key>PayloadDescription</key><string>Lägger till er gemensamma HouseMates-kalender i Kalender.</string>
  <key>PayloadDisplayName</key><string>HouseMates</string>
  <key>PayloadIdentifier</key><string>se.housemates.spike</string>
  <key>PayloadOrganization</key><string>HouseMates</string>
  <key>PayloadType</key><string>Configuration</string>
  <key>PayloadUUID</key><string>0F3B7C2A-8E41-4D9B-A6C5-71E2D3B4F9A8</string>
  <key>PayloadVersion</key><integer>1</integer>
</dict>
</plist>
`;
}

async function readJson(req) {
  let body = '';
  for await (const chunk of req) body += chunk;
  return body ? JSON.parse(body) : {};
}

async function handle(req, res) {
  const { pathname } = new URL(req.url, 'http://spike');
  console.log(`${new Date().toISOString()} ${req.method} ${pathname} ${req.headers['user-agent'] ?? ''}`);

  if (req.method === 'GET' && pathname === '/feed.ics') {
    res.writeHead(200, { 'content-type': 'text/calendar; charset=utf-8' }).end(feed());
  } else if (req.method === 'POST' && pathname === '/events') {
    const { title = 'Ny händelse', inHours = 1, url } = await readJson(req);
    const uid = randomUUID();
    events.push({ uid, title, url, allDay: false, start: hoursFromNow(inHours), end: hoursFromNow(inHours + 1) });
    res.writeHead(201, { 'content-type': 'application/json' }).end(JSON.stringify({ uid }));
  } else if (req.method === 'GET' && pathname === '/profile.mobileconfig') {
    const host = (req.headers.host ?? 'localhost').split(':')[0];
    res.writeHead(200, { 'content-type': 'application/x-apple-aspen-config' }).end(profile(host));
  } else {
    res.writeHead(404).end();
  }
}

// iOS resolves "localhost" to ::1 first, so listen on IPv6 loopback too.
const hosts = BIND === '127.0.0.1' ? ['127.0.0.1', '::1'] : [BIND];
for (const host of hosts) {
  createServer(handle).listen(PORT, host, () => console.log(`Spike-server på http://[${host}]:${PORT}`));
}
