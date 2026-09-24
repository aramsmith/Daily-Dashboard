// Demo server for README screenshots: serves the real board pages with fictional sample data only
// (Contoso, Fabrikam, made-up people). No sign-in, no Microsoft 365 access, never part of the setup package.
// Run: node docs\demo\demo-server.js   then open http://127.0.0.1:12900/
'use strict';
const http = require('http');
const fs = require('fs');
const path = require('path');

const PORT = 12900;
const APP = path.join(__dirname, '..', '..', 'app');
const VERSION = (() => { try { return fs.readFileSync(path.join(__dirname, '..', '..', 'VERSION'), 'utf8').trim(); } catch { return '0.0.0-dev'; } })();
const TZ = 'Europe/Amsterdam';

const ago = (minutes) => new Date(Date.now() - minutes * 60e3).toISOString();
// A fixed wall-clock time today (day 0) or yesterday (day -1), so screenshots look like a normal working day.
const clock = (day, h, m) => { const d = new Date(); d.setDate(d.getDate() + day); d.setHours(h, m, 0, 0); return d.toISOString(); };
const mail = (id, fromName, fromAddress, subject, minutes, isRead, automated = false) =>
  ({ id, fromName, fromAddress, subject, received: Array.isArray(minutes) ? clock(...minutes) : ago(minutes), isRead, automated, link: '#' });
const at = (h, m) => `${String(h).padStart(2, '0')}:${String(m).padStart(2, '0')}`;

const MAIL = {
  timeZone: 'W. Europe Standard Time', timeZoneIana: TZ, timeZoneFallback: false, hour12: false,
  since: ago(24 * 60), truncated: false,
  summary: { unreadPeople: 3, total24: 27, total24Exact: true, automated: 14, countsExact: true },
  people: [
    mail('p1', 'Priya Natarajan', 'priya.natarajan@contoso.com', 'Re: Landing zone review - updated diagram attached', [0, 8, 42], false),
    mail('p2', 'Tom Verhoeven', 'tom.verhoeven@northwindtraders.com', 'Agenda for Thursday workshop', [0, 8, 15], false),
    mail('p3', 'Lena Fischer', 'lena.fischer@contoso.com', 'Quick question on the networking design', [0, 7, 51], true),
    mail('p4', 'Marco Rossi', 'marco.rossi@adventure-works.com', 'Thanks for the session yesterday', [-1, 17, 36], true),
    mail('p5', 'Sara Lindqvist', 'sara.lindqvist@contoso.com', 'Draft decision log for the steering group', [-1, 15, 4], false),
  ],
  customers: [
    {
      name: 'Contoso', color: 'amber', truncated: false, error: null,
      items: [
        mail('c1', 'Daniel Okafor', 'daniel.okafor@contoso.com', 'Contoso migration wave 2: go/no-go criteria', [0, 8, 30], false),
        mail('c2', 'Emma Janssen', 'emma.janssen@contoso.com', 'Contoso security baseline - comments from the CISO office', [0, 7, 12], true),
        mail('c3', 'Yuki Tanaka', 'yuki.tanaka@contoso.com', 'RE: Contoso cost estimate for the data platform', [-1, 16, 48], true),
        mail('c4', 'Daniel Okafor', 'daniel.okafor@contoso.com', 'Contoso steering committee minutes', [-1, 11, 20], true),
      ],
    },
    {
      name: 'Fabrikam', color: 'blue', truncated: false, error: null,
      items: [
        mail('f1', 'Olivia Brown', 'olivia.brown@fabrikam.com', 'Fabrikam: architecture board follow-up', [0, 7, 58], false),
        mail('f2', 'Noah Williams', 'noah.williams@fabrikam.com', 'Fabrikam pilot - test results week 38', [-1, 14, 5], true),
      ],
    },
  ],
  automated: [
    mail('a1', 'Azure Updates', 'no-reply@azure.example', 'Weekly digest: new regions and services', [0, 6, 30], true, true),
    mail('a2', 'Tech Newsletter', 'newsletter@technews.example', 'The week in cloud architecture', [0, 6, 0], true, true),
    mail('a3', 'Learning Portal', 'notifications@learning.example', 'Your certification renewal is available', [-1, 18, 45], true, true),
    mail('a4', 'Events Team', 'events@conference.example', 'Last chance: register for the summit', [-1, 10, 2], true, true),
  ],
  topSenders: [
    { name: 'Azure Updates', address: 'no-reply@azure.example', count: 5 },
    { name: 'Tech Newsletter', address: 'newsletter@technews.example', count: 4 },
    { name: 'Learning Portal', address: 'notifications@learning.example', count: 3 },
    { name: 'Events Team', address: 'events@conference.example', count: 2 },
  ],
};

const CALENDAR = {
  timeZone: 'W. Europe Standard Time', timeZoneIana: TZ, timeZoneFallback: false, hour12: false,
  meetingsCount: 5, truncated: false,
  days: [
    {
      key: 'today', label: 'Today', events: [
        { id: 'demo-past', subject: 'Team stand-up', time: `${at(9, 0)} – ${at(9, 15)}`, location: 'Microsoft Teams Meeting', rooms: [], joinUrl: null, response: 'accepted', past: true, link: '#' },
        { id: 'demo-meeting-0001', subject: 'Contoso landing zone design review', time: `${at(14, 0)} – ${at(15, 0)}`, location: 'Microsoft Teams Meeting', rooms: ['AMS-HQ/2241'], joinUrl: 'https://teams.microsoft.com/', response: 'organizer', past: false, link: '#' },
        { id: 'demo-meeting-0002', subject: 'Fabrikam architecture board', time: `${at(16, 0)} – ${at(16, 45)}`, location: 'Webex meeting', rooms: [], joinUrl: 'https://www.webex.com/', response: 'tentativelyAccepted', past: false, link: '#' },
      ],
    },
    {
      key: 'tomorrow', label: 'Tomorrow', events: [
        { id: 'demo-meeting-0003', subject: 'Northwind workshop: data platform options', time: `${at(10, 0)} – ${at(12, 0)}`, location: '', rooms: ['AMS-HQ/1105'], joinUrl: null, response: 'accepted', past: false, link: '#' },
        { id: 'demo-meeting-0004', subject: 'Contoso steering committee', time: `${at(13, 30)} – ${at(14, 30)}`, location: 'Microsoft Teams Meeting', rooms: [], joinUrl: 'https://teams.microsoft.com/', response: 'none', past: false, link: '#' },
        { id: 'demo-meeting-0005', subject: '1:1 with Priya', time: `${at(16, 0)} – ${at(16, 30)}`, location: 'Microsoft Teams Meeting', rooms: [], joinUrl: 'https://teams.microsoft.com/', response: 'accepted', past: false, link: '#' },
      ],
    },
  ],
};

const MEETING = {
  subject: 'Contoso landing zone design review', when: 'Thursday 24 September 2026, 14:00 – 15:00', date: '2026-09-24',
  timeZone: 'W. Europe Standard Time', organizer: 'Alex Morgan',
  attendees: ['Priya Natarajan', 'Daniel Okafor', 'Emma Janssen', 'Lena Fischer', 'Yuki Tanaka', 'Alex Morgan'],
  location: 'Microsoft Teams Meeting', rooms: ['AMS-HQ/2241'], joinUrl: 'https://teams.microsoft.com/', link: '#',
};
const LABEL = { name: 'General', color: '#2e7d32', tooltip: 'Business data that is not meant for the public.' };
const ARTIFACTS = [
  'Updated landing zone decision log with owners and dates',
  'One-page summary of network design options for the CISO office',
];

const BRIEFING = {
  meeting: MEETING, label: LABEL, generatedAt: new Date().toISOString(), conversationId: 'demo-conversation-0001',
  draftCap: 'demo-capability-code-not-signed-0000000000',
  briefing: {
    summary: 'Contoso wants to sign off the landing zone design before migration wave 2 starts. Open points are hub-and-spoke versus Virtual WAN and who owns the firewall rules.',
    topics: [
      'Final choice between hub-and-spoke and Virtual WAN.',
      'Ownership of firewall rules between the platform and security teams.',
      'Go/no-go criteria for migration wave 2.',
    ],
    latestContext: [
      'Priya sent an updated network diagram this morning.',
      'The CISO office asked for private endpoints on all data services.',
      'Last week the steering committee accepted the cost estimate with a 10% margin.',
    ],
    talkingPoints: [
      'Confirm the network topology so the platform team can start building.',
      'Agree who approves firewall rule changes.',
      'Link the wave 2 go/no-go criteria to the security baseline.',
    ],
    risks: [
      'Wave 2 slips if the network decision is not made this week.',
      'Unclear firewall ownership can block application teams.',
    ],
    openDecisions: [
      'Hub-and-spoke or Virtual WAN.',
      'Central or per-team firewall rule approval.',
    ],
    questions: [
      'Which option does the CISO office prefer, and why?',
      'Who signs off the go/no-go criteria?',
      'Is the 10% cost margin enough for private endpoints?',
    ],
    artifacts: ARTIFACTS,
    sources: [
      { title: 'Re: Landing zone review - updated diagram attached', type: 'email', date: '2026-09-24', url: null },
      { title: 'Contoso security baseline - comments from the CISO office', type: 'email', date: '2026-09-23', url: null },
      { title: 'Contoso steering committee - recap', type: 'transcript', date: '2026-09-17', url: null },
      { title: 'Landing zone design v3.vsdx', type: 'file', date: '2026-09-24', url: null },
    ],
  },
};

const DRAFTS = {
  [ARTIFACTS[0]]: {
    title: 'Contoso landing zone - decision log', purpose: 'Record the open design decisions, their owners and due dates before migration wave 2.',
    audience: 'Contoso platform team, CISO office and the steering committee',
    sections: [
      {
        heading: 'Decisions', text: 'Status after the design review of 24 September.', bullets: [],
        table: {
          columns: ['Decision', 'Options', 'Owner', 'Due', 'Status'],
          rows: [
            ['Network topology', 'Hub-and-spoke / Virtual WAN', 'Priya Natarajan', '1 Oct', 'Open'],
            ['Firewall rule approval', 'Central / per team', 'Emma Janssen', '1 Oct', 'Open'],
            ['Private endpoints for data services', 'Required / optional', 'CISO office', '24 Sep', 'Agreed'],
            ['Wave 2 go/no-go criteria', 'Draft v2', 'Daniel Okafor', '[to confirm]', 'In review'],
          ],
        },
      },
      { heading: 'Next steps', text: '', bullets: ['Share this log with the steering committee.', 'Book a 30-minute decision call before 1 October.'], table: null },
    ],
    openQuestions: ['Who has the final say on the network topology: the platform lead or the steering committee?'],
    sources: BRIEFING.briefing.sources.slice(0, 3),
  },
  [ARTIFACTS[1]]: {
    title: 'Network design options - one-page summary', purpose: 'Help the CISO office choose between the two network designs.',
    audience: 'CISO office',
    sections: [
      { heading: 'The question', text: 'Contoso must choose a network topology for the landing zone before migration wave 2.', bullets: [], table: null },
      {
        heading: 'Options compared', text: '', bullets: [],
        table: {
          columns: ['', 'Hub-and-spoke', 'Virtual WAN'],
          rows: [
            ['Control', 'Full control of routing', 'Microsoft manages routing'],
            ['Effort to run', 'Higher', 'Lower'],
            ['Fits the security baseline', 'Yes', 'Yes, with secured hubs'],
            ['Cost estimate', '[to confirm]', '[to confirm]'],
          ],
        },
      },
      { heading: 'Recommendation', text: 'Choose Virtual WAN with secured hubs if the cost stays within the 10% margin.', bullets: [], table: null },
    ],
    openQuestions: ['Does the CISO office accept Microsoft-managed routing?'],
    sources: BRIEFING.briefing.sources.slice(1, 4),
  },
};

const STATIC = { '/': 'index.html', '/briefing': 'briefing.html', '/artifacts': 'artifacts.html', '/settings': 'settings.html' };
const MIME = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.css': 'text/css; charset=utf-8', '.ico': 'image/x-icon', '.woff2': 'font/woff2' };

function json(res, obj) { res.writeHead(200, { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store' }); res.end(JSON.stringify(obj)); }

http.createServer((req, res) => {
  const url = new URL(req.url, `http://127.0.0.1:${PORT}`);
  const p = url.pathname;
  if (p === '/api/config') return json(res, { userName: 'Alex', customers: ['Contoso', 'Fabrikam'], colors: ['amber', 'blue'], title: "Alex's Daily Board", maxCustomers: 3, colorChoices: ['amber', 'blue', 'violet', 'pink', 'cyan', 'slate'], version: VERSION });
  if (p === '/api/status') return json(res, { connector: true, signedIn: true, account: { name: 'Alex Morgan', username: 'alex.morgan@contoso.com' }, message: null });
  if (p === '/api/mail') return json(res, MAIL);
  if (p === '/api/calendar') return json(res, CALENDAR);
  if (p === '/api/briefing') return setTimeout(() => json(res, BRIEFING), 300);
  if (p === '/api/artifact') {
    const item = url.searchParams.get('item') || '';
    return setTimeout(() => json(res, { item, meeting: MEETING, label: LABEL, generatedAt: new Date().toISOString(), artifact: DRAFTS[item] || null, rawText: 'No sample draft for this item.' }), 400);
  }
  const rel = STATIC[p] || p.replace(/^\/+/, '');
  const full = path.join(APP, rel);
  if (!full.startsWith(APP) || !fs.existsSync(full) || fs.statSync(full).isDirectory()) { res.writeHead(404); return res.end(); }
  res.writeHead(200, { 'Content-Type': MIME[path.extname(full)] || 'application/octet-stream' });
  fs.createReadStream(full).pipe(res);
}).listen(PORT, '127.0.0.1', () => console.log(`Demo board with sample data: http://127.0.0.1:${PORT}/`));
