// Plays one Nation Guard battle and sends it to the Chess Battle server.
// Run every 30 minutes by .github/workflows/war.yml (about 48 battles a day).
//
// Needs three environment variables:
//   SB_URL    your Supabase project URL
//   SB_KEY    the publishable (public) key
//   WAR_KEY   from the SQL editor: select v from cb_config where k = 'war_key';
//
// Local test without a server: node server/war-runner.mjs --dry
import {JSDOM} from 'jsdom';
import fs from 'fs';

const dry = process.argv.includes('--dry');
const {SB_URL, SB_KEY, WAR_KEY} = process.env;
if (!dry && (!SB_URL || !SB_KEY || !WAR_KEY)) {
  console.error('Missing SB_URL, SB_KEY or WAR_KEY.');
  process.exit(1);
}

// load the game engine from index.html, the same code the app runs
const html = fs.readFileSync(new URL('../index.html', import.meta.url), 'utf8');
const dom = new JSDOM('<!doctype html><body></body>', {url: 'https://chess.battle/', pretendToBeVisual: true, runScripts: 'outside-only'});
const w = dom.window;
w.CB_SB_URL = ''; w.matchMedia = () => ({matches: false, addListener() {}, addEventListener() {}}); w.scrollTo = () => {};
w.document.body.innerHTML = html.slice(html.indexOf('<body>') + 6, html.lastIndexOf('</body>')).replace(/<script>[\s\S]*<\/script>/, '');
const js = html.match(/<script>([\s\S]*)<\/script>/)[1];
w.eval(js.replace(/\nconst /g, '\nvar ').replace(/\nlet /g, '\nvar '));

async function rpc(fn, args) {
  const r = await fetch(`${SB_URL.replace(/\/rest\/v1\/?$/, '').replace(/\/$/, '')}/rest/v1/rpc/${fn}`, {
    method: 'POST', headers: {apikey: SB_KEY, 'Content-Type': 'application/json'}, body: JSON.stringify(args)});
  const text = await r.text();
  if (!r.ok) throw new Error(`${fn} failed (${r.status}): ${text}`);
  return text ? JSON.parse(text) : null;
}

const pair = dry
  ? {white: {id: 'ember-k1', nation: 'ember', rank: 'K', name: 'Pyrrhus', rating: 1600}, black: {id: 'tide-p1', nation: 'tide', rank: 'P', name: 'Reef', rating: 1090}}
  : await rpc('next_war_pairing', {p_key: WAR_KEY});
const label = g => `${g.nation} ${g.rank} ${g.name} (${g.rating})`;
console.log(`Battle: ${label(pair.white)} vs ${label(pair.black)}`);
const t0 = Date.now();
const res = w.playWar(pair.white, pair.black);
console.log(`Result: ${res.outcome} by ${res.why} after ${res.plies} plies in ${((Date.now() - t0) / 1000).toFixed(1)}s`);
if (dry) { console.log(JSON.stringify({acts: res.acts.length})); process.exit(0); }
const saved = await rpc('record_war_game', {
  p_key: WAR_KEY, p_white: pair.white.id, p_black: pair.black.id, p_outcome: res.outcome, p_why: res.why,
  p_init: res.init, p_acts: res.acts, p_plies: res.plies, p_ply_ms: 6000});
console.log(`Saved battle #${saved.id} in ${saved.region}, worth ${saved.pts}. Plays out live until ${saved.end_at}.`);
process.exit(0);
