// Load test for the API: many signed-in users searching, browsing nearby places and suggestions, and
// managing bookmarks at once. Runs with k6 (https://grafana.com/docs/k6/) against the E2E stack (the
// production image, with TomTom stubbed), since there's no staging backend yet. See "Performance" in
// TESTING.md.
//
//   make load                                     # starts the stack, runs this, stops the stack
//   BASE_URL=... VUS=... DURATION=... k6 run perf/load.js
//
// A budget a run misses fails it (k6 exits 99). The budgets are for regressions, measured against
// the Firestore emulator on a CI runner, not production latency.

import http from 'k6/http';
import { check, fail, sleep } from 'k6';

const BASE_URL = __ENV.BASE_URL || 'http://localhost:18000/api';
const VUS = Number(__ENV.VUS || 20);
const DURATION = __ENV.DURATION || '2m';
// Places created around Manhattan before the run, so nearby and search read a realistic amount.
const PLACES = Number(__ENV.PLACES || 200);

// p95 latency budget per endpoint, in milliseconds.
const BUDGETS = {
  search: 500,
  nearby: 500,
  suggestions: 500,
  'save place': 600,
  bookmark: 600,
  bookmarks: 500,
  pin: 600,
  unbookmark: 500,
};

// Queries the stub's TomTom search answers (e2e/stub/server.py), plus one only local places match.
const QUERIES = ['pizza', "joe's", 'diner', 'bakery', 'load test cafe'];
const CENTER = { lat: 40.7306, lng: -74.0021 };

export const options = {
  scenarios: {
    users: {
      executor: 'ramping-vus',
      stages: [
        { duration: '20s', target: VUS },
        { duration: DURATION, target: VUS },
        { duration: '10s', target: 0 },
      ],
      gracefulRampDown: '10s',
    },
  },
  thresholds: {
    http_req_failed: ['rate<0.01'],
    checks: ['rate>0.99'],
    ...Object.fromEntries(
      Object.entries(BUDGETS).map(([name, ms]) => [`http_req_duration{name:${name}}`, [`p(95)<${ms}`]]),
    ),
  },
  // Setup's own requests aren't part of the budgets.
  setupTimeout: '5m',
  summaryTrendStats: ['avg', 'med', 'p(95)', 'p(99)', 'max'],
};

function request(method, path, { token, body, name, params } = {}) {
  const headers = { 'Content-Type': 'application/json' };
  if (token) headers.Authorization = `Bearer ${token}`;
  const query = params ? '?' + Object.entries(params).map(([k, v]) => `${k}=${encodeURIComponent(v)}`).join('&') : '';
  return http.request(method, `${BASE_URL}${path}${query}`, body === undefined ? null : JSON.stringify(body), {
    headers,
    tags: name ? { name } : { name: `setup ${method} ${path.split('/').slice(0, 3).join('/')}` },
  });
}

function jitter(degrees) {
  return (Math.random() - 0.5) * 2 * degrees;
}

function pick(items) {
  return items[Math.floor(Math.random() * items.length)];
}

// One account per virtual user, so bookmarks don't contend, and the places to work with.
export function setup() {
  const run = Date.now().toString(36);
  const tokens = [];
  for (let i = 0; i < VUS; i++) {
    const res = request('POST', '/auth/register', { body: { username: `load-${run}-${i}`, password: 'load-test-password' } });
    if (res.status !== 200) fail(`register: ${res.status} ${res.body}`);
    tokens.push(res.json('token'));
  }

  const places = [];
  for (const query of QUERIES) {
    const res = request('GET', '/places/search', { token: tokens[0], params: { query } });
    if (res.status !== 200) fail(`search: ${res.status} ${res.body}`);
    places.push(...res.json());
  }
  for (let i = 0; i < PLACES; i++) {
    places.push({
      tomtom_id: `load-${run}-place-${i}`,
      name: `Load Test Cafe ${i}`,
      address: `${i} Load Test St, New York, NY`,
      location: { lat: CENTER.lat + jitter(0.05), lng: CENTER.lng + jitter(0.05) },
      categories: ['cafe'],
      hours: [0, 1, 2, 3, 4, 5, 6].map((day) => ({ day_of_week: day, open_time: '08:00', close_time: '18:00' })),
    });
  }
  for (const place of places) {
    const res = request('POST', '/places/', { token: tokens[0], body: place });
    if (res.status !== 200) fail(`save place: ${res.status} ${res.body}`);
  }
  return { tokens, places };
}

// One user session: look around, then bookmark a place, pin it, and remove it again.
export default function ({ tokens, places }) {
  const token = tokens[(__VU - 1) % tokens.length];
  const ok = (res, name) => check(res, { [`${name} succeeded`]: (r) => r.status >= 200 && r.status < 300 });

  ok(request('GET', '/places/search', { token, name: 'search', params: { query: pick(QUERIES) } }), 'search');
  sleep(0.5);

  const here = { lat: CENTER.lat + jitter(0.02), lng: CENTER.lng + jitter(0.02) };
  ok(request('GET', '/places/nearby', { token, name: 'nearby', params: { ...here, radius_km: 5 } }), 'nearby');
  ok(request('GET', '/places/suggestions', { token, name: 'suggestions', params: here }), 'suggestions');
  sleep(0.5);

  const place = pick(places);
  ok(request('POST', '/places/', { token, name: 'save place', body: place }), 'save place');
  ok(request('POST', '/places/bookmark', { token, name: 'bookmark', body: { tomtom_id: place.tomtom_id } }), 'bookmark');
  ok(request('GET', '/places/bookmarks', { token, name: 'bookmarks' }), 'bookmarks');
  const id = encodeURIComponent(place.tomtom_id);
  ok(request('PATCH', `/places/bookmarks/${id}/pin`, { token, name: 'pin', body: { is_pinned: true } }), 'pin');
  ok(request('DELETE', `/places/bookmarks/${id}`, { token, name: 'unbookmark' }), 'unbookmark');
  sleep(1);
}

// A Markdown table for the CI job summary, and the full results as JSON.
export function handleSummary(data) {
  const ms = (v) => (v === undefined ? '–' : `${Math.round(v)} ms`);
  const rows = Object.entries(BUDGETS).map(([name, budget]) => {
    const metric = data.metrics[`http_req_duration{name:${name}}`];
    const values = metric ? metric.values : {};
    const passed = metric && metric.thresholds ? Object.values(metric.thresholds).every((t) => t.ok) : false;
    return `| ${name} | ${ms(values.med)} | ${ms(values['p(95)'])} | ${ms(budget)} | ${passed ? '✅' : '❌'} |`;
  });
  const failed = data.metrics.http_req_failed.values.rate;
  const requests = data.metrics.http_reqs.values;
  const markdown = [
    `## API load test`,
    '',
    `${VUS} users for ${DURATION}: ${requests.count} requests (${requests.rate.toFixed(1)}/s), ${(failed * 100).toFixed(2)}% failed (budget: under 1%).`,
    '',
    '| Endpoint | Median | p95 | p95 budget | |',
    '| --- | --- | --- | --- | --- |',
    ...rows,
    '',
  ].join('\n');
  return {
    stdout: markdown,
    [__ENV.SUMMARY_DIR ? `${__ENV.SUMMARY_DIR}/load-summary.md` : 'load-summary.md']: markdown,
    [__ENV.SUMMARY_DIR ? `${__ENV.SUMMARY_DIR}/load-summary.json` : 'load-summary.json']: JSON.stringify(data, null, 2),
  };
}
