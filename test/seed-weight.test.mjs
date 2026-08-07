/* The starting bodyweight is a placeholder, and the app has to keep saying so.
 *
 * An account with no weigh-ins still renders a chart, a 28-day trend and a
 * calorie target, all of which read a bodyweight — so load() seeds one at
 * 79 kg rather than let those paths meet an empty array. That was invisible
 * while the weigh-in input lived halfway down the Body weight panel. Moving
 * the input to the top of Today put the placeholder in the first thing a new
 * user sees, under a label reading "logged 79 kg" — a morning weigh-in they
 * had never done, on their first launch.
 *
 * The fix is a `seed: true` flag on the record, which the weigh-in row reads
 * so it offers "Log" instead of "Update". These are static assertions: the
 * behaviour is verified in a real browser, but the two halves of it live in
 * different functions 1500 lines apart and either one can be edited alone.
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const app = readFileSync(new URL('../app.js', import.meta.url), 'utf8');

test('every place that seeds a starting weight marks it as one', () => {
  const seeds = [...app.matchAll(/\{\s*d\s*:\s*todayISO\s*,\s*kg\s*:\s*79[^}]*\}/g)].map(m => m[0]);
  assert.ok(seeds.length >= 2,
    'expected the load() seed and the delete-all-data seed; found ' + seeds.length);
  for (const s of seeds)
    assert.match(s, /seed\s*:\s*true/,
      'an unmarked seed reads as a real weigh-in everywhere downstream: ' + s);
});

test('the weigh-in row does not count a seed as this morning\'s weigh-in', () => {
  const at = app.indexOf('const weighedToday');
  assert.notEqual(at, -1, 'the weigh-in row should still decide whether today is done');
  assert.match(app.slice(at, at + 200), /!\s*\w+\.seed/,
    'weighedToday must exclude the seeded placeholder, or a fresh account is '
    + 'told it logged 79 kg before it has logged anything');
});

test('logging for real writes a record with no seed flag', () => {
  /* The save handler filters today out and pushes a fresh object, so the
     flag disappears by construction. If someone ever rewrites this to mutate
     the existing record in place, the flag survives and the row goes back to
     claiming nothing was logged. */
  const at = app.indexOf('S.weights.push(');
  assert.notEqual(at, -1);
  const push = app.slice(at, app.indexOf('\n', at));
  assert.doesNotMatch(push, /seed/, 'a real weigh-in must never carry the seed flag');
  assert.match(app.slice(at - 200, at), /S\.weights\s*=\s*S\.weights\.filter\(/,
    'the day\'s existing record — seed or not — should be replaced, not edited');
});
