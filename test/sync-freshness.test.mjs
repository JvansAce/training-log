/* Guard for the worst bug this project has had.
 *
 * Sync decides push-vs-pull with isFresh(): a device with no real history
 * should GET rather than PUT, so its empty defaults never dilute the stored
 * record. That was written when the app had one half, and it counted only
 * body data — logs, lifts, weights.
 *
 * When Mind arrived, a device could accumulate a fortnight of journal
 * entries, minutes and ladder rungs while still looking "fresh", because
 * none of that lives in the fields isFresh() reads. So it never PUT
 * anything, and every pull replaced the local record with the server's copy
 * — which had never received the entries. Two weeks of writing, gone
 * silently, on a device that had been displaying them the whole time.
 *
 * Any future field that can hold work the user did has to be counted here.
 * The reflective test below fails when a new top-level container appears in
 * DEFAULTS that isFresh() has never been taught about, so this cannot
 * quietly rot the next time the state shape grows.
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

const root = new URL('..', import.meta.url);
const syncSrc = readFileSync(new URL('sync.js', root), 'utf8');
const appSrc = readFileSync(new URL('app.js', root), 'utf8');

/* sync.js is an IIFE assigned to a bare `const Sync`, with no module
   system. Run it in a sandbox and reach isFresh through the closure by
   re-evaluating the source with the guard exposed. */
function loadIsFresh(){
  const src = syncSrc.replace(
    'return {\n    run, schedule, label, state,',
    'return {\n    isFresh, run, schedule, label, state,');
  assert.notEqual(src, syncSrc, 'could not expose isFresh — has the return block changed shape?');
  const ctx = vm.createContext({ navigator: { onLine: true }, localStorage: null, fetch: null, setTimeout, clearTimeout });
  vm.runInContext(src + '\nglobalThis.__isFresh = Sync.isFresh;', ctx);
  return ctx.__isFresh;
}

const emptyBody = () => ({ logs: {}, lifts: {}, weights: [{ d: '2026-01-01', kg: 79 }] });
const emptyMind = () => ({ startDate: null, unlocked: 1, logs: {}, targets: {}, ladderLog: {},
  ladderCap: 1, charismaIx: 0, charismaSince: null });

test('a genuinely untouched device is fresh', () => {
  assert.equal(loadIsFresh()({ ...emptyBody(), mind: emptyMind() }), true);
});

test('a device with body history is not fresh', () => {
  const isFresh = loadIsFresh();
  assert.equal(isFresh({ ...emptyBody(), logs: { '2026-01-02': { done: ['x'] } }, mind: emptyMind() }), false);
  assert.equal(isFresh({ ...emptyBody(), lifts: { squat: [{ d: '2026-01-02', sets: [] }] }, mind: emptyMind() }), false);
  assert.equal(isFresh({ ...emptyBody(), weights: [{ d: 'a', kg: 1 }, { d: 'b', kg: 2 }], mind: emptyMind() }), false);
});

/* Each of these on its own is enough. A device could plausibly have any one
   of them and nothing else — starting the programme and writing for a week
   touches only startDate and logs. */
for (const [label, patch] of [
  ['the programme has been started', { startDate: '2026-01-01' }],
  ['there are journal or practice entries', { logs: { '2026-01-02': { done: [], mins: {}, journal: 'wrote' } } }],
  ['a ladder Saturday was cleared', { ladderLog: { '2026-01-03': { cap: 2 } } }],
  ['a practice has been unlocked', { unlocked: 2 }],
  ['a charisma drill has been completed', { charismaIx: 1 }],
]){
  test(`not fresh when ${label}`, () => {
    assert.equal(loadIsFresh()({ ...emptyBody(), mind: { ...emptyMind(), ...patch } }), false,
      'this device holds work that has never been pushed — pulling would destroy it');
  });
}

test('isFresh accounts for every top-level container in DEFAULTS', () => {
  // Pull the DEFAULTS literal out of app.js and check that isFresh's source
  // mentions each field that can hold user work. A new one added without
  // teaching isFresh about it is the exact shape of the original bug.
  const m = /const DEFAULTS = \{([\s\S]*?)\n *updatedAt:\s*0\};/.exec(appSrc);
  assert.ok(m, 'could not find the DEFAULTS literal');
  // Comments first. The literal is annotated, and a comment containing an
  // ordinary English colon ("one key per day: ...") reads as a field named
  // `day` — a phantom that can never be satisfied, and which would push
  // whoever hit it towards silencing this test rather than fixing it.
  const body = m[1].replace(/\/\/[^\n]*/g, '').replace(/\/\*[\s\S]*?\*\//g, '');
  const fields = [...body.matchAll(/(?:^|[\s{,])([a-zA-Z]+)\s*:/g)].map(x => x[1]);
  assert.ok(fields.includes('off'), 'the field scan should still see real fields');

  // Scalars and settings cannot hold work; only containers and progress
  // counters can. Anything genuinely new will not be on this list and will
  // therefore have to be considered.
  const cannotHoldWork = new Set([
    'startDate', 'pyramidCap', 'vestKg', 'vestPhase', 'barKg', 'calAdjust',
    'heightCm', 'birthYear', 'updatedAt', 'whoop', 'waist', 'pyramidLog',
    // The date a deload suggestion was last dismissed. Pure UI quieting —
    // losing it costs one redundant prompt, not any record of training.
    // (deloadLog, the weeks actually taken, IS counted by isFresh.)
    'deloadSnooze',
    // mind's own sub-fields appear in the same literal; they are covered
    // by the explicit checks inside isFresh.
    'unlocked', 'logs', 'targets', 'ladderLog', 'ladderCap', 'charismaIx', 'charismaSince'
  ]);
  const isFreshSrc = /const isFresh = [\s\S]*?\n  \};/.exec(syncSrc)?.[0] || '';
  assert.ok(isFreshSrc, 'could not find isFresh');

  const unaccounted = fields.filter(f =>
    !cannotHoldWork.has(f) && !isFreshSrc.includes(f));
  assert.deepEqual(unaccounted, [],
    `isFresh() does not mention ${unaccounted.join(', ')} — if that field can hold work the user did, ` +
    `a device holding only it will pull and lose everything. Add it to isFresh, or to the ` +
    `cannotHoldWork list in this test with a reason.`);
});

test('every wholesale replacement of S goes through normalise()', () => {
  /* load(), import and adoptMerged all rebuild S from an outside object.
     Only load() used to run the shape guards, so importing a backup with a
     half-shaped mind block left the app one tap from a crash. */
  const raw = [...appSrc.matchAll(/\bS\s*=\s*(?!=)([^;\n]+)/g)].map(x => x[1].trim());
  const bad = raw.filter(expr =>
    /Object\.assign\(\s*structuredClone\(DEFAULTS\)/.test(expr));
  assert.deepEqual(bad, [],
    `these assignments rebuild S without the shape guards: ${bad.join(' | ')} — use normalise()`);
  assert.ok(appSrc.includes('function normalise('), 'normalise() should exist');
});
