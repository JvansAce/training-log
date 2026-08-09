/* Days ill or away, and the numbers that used to judge them.
 *
 * Illness and holidays were counted as adherence failures by every derived
 * figure in the app. A week of flu ended a sixteen-week green streak. Red
 * WHOOP recovery from a fever prescribed a deload, spending the 28-day
 * cooldown on fatigue that was viral. And the scale: glycogen carries about
 * three grams of water per gram, so a few days without eating takes a
 * kilo or two off that is not fat, and the 28-day trend read it as real
 * and offered a one-tap +200 kcal — then read the refill as real too and
 * said to hold.
 *
 * `off` is a per-day map, `{'2026-08-11': 'ill'}`, deliberately shaped like
 * the other dated collections so it merges, tombstones and syncs with the
 * machinery that already exists. This file guards the two halves that are
 * invisible until they break: the sync round trip, and the set of derived
 * numbers that have to know about it. The arithmetic itself is verified
 * against hand-worked fixtures in the browser suites.
 */
import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { mergeState } from '../functions/api/state.js';

const app = readFileSync(new URL('../app.js', import.meta.url), 'utf8');
const daysAgo = n => { const d = new Date(); d.setDate(d.getDate() - n); return d.toISOString().slice(0, 10); };
const OLD = daysAgo(30);
const NOW = Date.now();

const base = (o = {}) => ({
  updatedAt: 1000, startDate: daysAgo(120), pyramidCap: 6, calAdjust: 0,
  weights: [], waist: [], logs: {}, lifts: {}, whoop: {},
  pyramidLog: {}, deloadLog: {}, off: {}, tombs: {},
  mind: { startDate: null, unlocked: 1, logs: {}, targets: {}, ladderLog: {}, ladderCap: 1,
          charismaIx: 0, charismaSince: null },
  ...o
});

describe('off days survive the sync', () => {
  test('a holiday marked on the phone reaches the server', () => {
    const server = base({ updatedAt: 1000 });
    const client = base({ updatedAt: NOW, off: { [OLD]: 'away', [daysAgo(29)]: 'away' } });
    const m = mergeState(server, client);
    assert.deepEqual(m.off, { [OLD]: 'away', [daysAgo(29)]: 'away' });
  });

  test('a device that slept through the holiday does not erase it', () => {
    /* The whole reason these collections merge additively. The tablet has a
       later updatedAt and no idea the week happened; without the union it
       would win the spread and blank the record. */
    const server = base({ updatedAt: 1000, off: { [OLD]: 'ill' } });
    const tablet = base({ updatedAt: NOW, off: {} });
    assert.equal(mergeState(server, tablet).off[OLD], 'ill');
  });

  test('two devices marking different days keep both', () => {
    const a = base({ updatedAt: 1000, off: { [OLD]: 'ill' } });
    const b = base({ updatedAt: NOW, off: { [daysAgo(3)]: 'away' } });
    const m = mergeState(a, b);
    assert.equal(m.off[OLD], 'ill');
    assert.equal(m.off[daysAgo(3)], 'away');
  });

  test('unmarking a day sticks instead of coming straight back', () => {
    /* Without a tombstone the server hands its copy back on the next pull
       and the day you just un-marked returns — the bug this whole mechanism
       exists for, and it applies to a new collection the moment it is
       added, not just to the ones that had it originally. */
    const server = base({ updatedAt: 1000, off: { [OLD]: 'ill' } });
    const client = base({ updatedAt: NOW, off: {}, tombs: { [`off:${OLD}`]: NOW } });
    assert.equal(mergeState(server, client).off[OLD], undefined,
      'the cleared day came back from the server');
  });

  test('re-marking a day beats an older tombstone', () => {
    /* The other half of the rule: a tombstone only wins while no side that
       still holds the record has written since. Getting this wrong eats the
       value the person just re-entered. */
    const deletedAt = NOW - 60_000;
    const server = base({ updatedAt: 1000, tombs: { [`off:${OLD}`]: deletedAt } });
    const client = base({ updatedAt: NOW, off: { [OLD]: 'away' } });
    assert.equal(mergeState(server, client).off[OLD], 'away',
      'marking the day again should overrule the earlier delete');
  });

  test('clearing one day leaves the rest of the trip alone', () => {
    const server = base({ updatedAt: 1000,
      off: { [daysAgo(10)]: 'away', [daysAgo(9)]: 'away', [daysAgo(8)]: 'away' } });
    const client = base({ updatedAt: NOW, tombs: { [`off:${daysAgo(9)}`]: NOW } });
    const m = mergeState(server, client);
    assert.deepEqual(Object.keys(m.off).sort(), [daysAgo(10), daysAgo(8)].sort());
  });

  test('a state with no off field at all still merges', () => {
    /* Every account that existed before this shipped. An absent container
       has to read as empty, not throw halfway through the merge and take
       the whole sync down with it. */
    const legacy = { ...base({ updatedAt: 1000 }) };
    delete legacy.off;
    const client = base({ updatedAt: NOW, off: { [OLD]: 'ill' } });
    assert.doesNotThrow(() => mergeState(legacy, client));
    assert.equal(mergeState(legacy, client).off[OLD], 'ill');
    assert.deepEqual(mergeState(client, legacy).off, { [OLD]: 'ill' });
  });
});

describe('the derived numbers know about it', () => {
  /* Static, because each of these is a one-line omission that changes no
     behaviour on a normal account and is therefore invisible until the
     week someone is actually ill. */
  const fnBody = name => {
    const start = app.indexOf(`function ${name}(`);
    assert.notEqual(start, -1, `${name} should exist`);
    let depth = 0;
    for (let j = app.indexOf('{', start); j < app.length; j++){
      if (app[j] === '{') depth++;
      else if (app[j] === '}' && --depth === 0) return app.slice(start, j + 1);
    }
    throw new Error(`could not find the end of ${name}`);
  };

  test('the weight trend leaves out mornings around time off', () => {
    /* Anchored on the exclusion itself, not on the identifier: trend() also
       counts how many it left out, and matching the bare name let the
       counter satisfy a test whose subject is the filter. Deleting the
       filter and keeping the count has to come back red. */
    assert.match(fnBody('trend'), /sortW\(\)\.filter\(\s*\w+\s*=>\s*!offSkipsWeighIn\(/,
      'a fever takes a kilo of water off; drawing a least-squares line through it '
      + 'is what produced the "add 200 kcal" prompt');
  });

  test('the green streak asks for fewer sessions in a week you were away', () => {
    assert.match(fnBody('greenStreak'), /greenNeed\(/);
    assert.match(fnBody('greenNeed'), /offBetween\(/);
  });

  test('the weekly session target comes down too', () => {
    assert.match(fnBody('weeklyReview'), /offBetween\(/);
  });

  test('the deload signal stays quiet while ill and on the way back', () => {
    const body = fnBody('deloadSignal');
    assert.match(body, /offToday\(\)/);
    assert.match(body, /returnRamp\(\)/);
    assert.match(fnBody('recoveryDays'), /isOffDay\(/,
      'off days in the recovery window would prescribe a deload for a fever');
  });

  test('the adherence chart can tell a holiday from falling off', () => {
    assert.match(fnBody('adherence'), /offBetween\(/);
  });

  test('lift progression does not add load after a layoff', () => {
    /* The gap has to be measured and branched on, not merely mentioned:
       naming the constants inside a branch that can no longer be reached
       satisfies a looser check while the app happily tells you to add
       2.5 kg to a lift your body has not seen in three weeks. */
    assert.match(fnBody('nextTarget'),
      /const gap\s*=[\s\S]{0,160}last\.d[\s\S]{0,120}if\s*\(\s*gap\s*>=\s*LIFT_LAYOFF\b/,
      'nextTarget should compare the days since that lift was last done');
  });

  test('Mind adherence drops off days from the denominator, not into the misses', () => {
    const body = fnBody('mindAdherence');
    assert.match(body, /isOffDay\(/);
    // `continue` before days++ is the difference between "not counted" and
    // "counted as a zero" — the second is what held unlocks for a month
    // after a fortnight away.
    const at = body.indexOf('isOffDay(');
    assert.match(body.slice(at, at + 120), /continue/);
  });

  test('the ramp thresholds still match the detraining evidence', () => {
    /* Strength is close to unchanged across two weeks off and only declines
       meaningfully after three to four. So a short break earns a lighter
       first session, and only a long one earns a lighter bar. If these
       numbers move, the copy in offPanel() is making a claim about the
       research that the code no longer implements. */
    assert.match(app, /const OFF_LONG\s*=\s*14\b/);
    assert.match(app, /const OFF_RAMP_MIN\s*=\s*4\b/);
    // Olsson & Saltin's carbohydrate-loading window: the days over which the
    // water actually comes back.
    assert.match(app, /const OFF_WEIGH_HOLD\s*=\s*4\b/);
  });

  test('the layoff threshold clears one normal week of the programme', () => {
    /* The bug this exists for: the first version keyed the layoff at 7 days.
       Every lift here comes round once or twice a week, so a 7-day gap is
       the ordinary cadence — the app told you to repeat the weight instead
       of adding to it after a perfectly normal week, on every weekly lift,
       forever. The threshold has to sit above one scheduled cycle with room
       for a session that slipped a few days. */
    const m = /const LIFT_LAYOFF = (\d+), LIFT_LAYOFF_LONG = (\d+)/.exec(app);
    assert.ok(m, 'the lift-gap thresholds should be named constants');
    const [, short_, long_] = m.map(Number);
    assert.ok(short_ > 7, `${short_} days would fire on an ordinary weekly lift`);
    assert.ok(short_ >= 10, `${short_} days leaves no room for a session that slipped`);
    assert.ok(long_ >= 21, `${long_} days is inside the window where strength is still resilient`);
    assert.ok(long_ > short_);
  });

  test('a range cannot write an unbounded number of days', () => {
    const body = fnBody('setOffRange');
    assert.match(body, /OFF_MAX_SPAN/,
      'a mistyped year would otherwise push thousands of keys into a record that syncs on every change');
  });
});
