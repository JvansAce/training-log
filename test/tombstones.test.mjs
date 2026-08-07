/* Deletion never worked.
 *
 * Every dated collection merges additively, because absence on one side
 * normally means "that device hasn't seen it yet". A real deletion looks
 * exactly the same, so the server kept its copy and handed it straight
 * back: confirming "Delete the weigh-in for the 5th?" removed it locally
 * and the next sync restored it, within seconds, on a single device. The
 * same was true of lift entries, pyramid sessions, ladder weeks and
 * deload weeks — every delete gesture in the app.
 *
 * Tombstones record the deletion instead of inferring it. The rule that
 * matters, and the one worth guarding: a tombstone kills the record UNLESS
 * a side that still holds it wrote more recently than the tombstone. That
 * is what makes re-creating something work, and it is the half that is
 * easy to get wrong — a naive "tombstone always wins" silently eats the
 * value you just re-entered.
 */
import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { mergeState } from '../functions/api/state.js';

const daysAgo = n => { const d = new Date(); d.setDate(d.getDate() - n); return d.toISOString().slice(0, 10); };
const OLD = daysAgo(30);
const NOW = Date.now();

const base = (o = {}) => ({
  updatedAt: 1000, startDate: OLD, pyramidCap: 6, calAdjust: 0,
  weights: [], waist: [], logs: {}, lifts: {}, whoop: {},
  pyramidLog: {}, deloadLog: {}, tombs: {},
  mind: { startDate: null, unlocked: 1, logs: {}, targets: {}, ladderLog: {}, ladderCap: 1,
          charismaIx: 0, charismaSince: null },
  ...o
});

describe('tombstones — a delete has to survive the round trip', () => {
  test('a deleted weigh-in is not handed back by the server', () => {
    const server = base({ updatedAt: 1000, weights: [{ d: OLD, kg: 99.9 }, { d: daysAgo(1), kg: 78 }] });
    const client = base({ updatedAt: NOW, weights: [{ d: daysAgo(1), kg: 78 }],
      tombs: { [`w:${OLD}`]: NOW } });
    const m = mergeState(server, client);
    assert.deepEqual(m.weights.map(w => w.kg), [78], 'the mistyped morning came back');
  });

  test('the same for a lift entry, a pyramid session, a ladder week and a deload', () => {
    const server = base({ updatedAt: 1000,
      lifts: { squat: [{ d: OLD, sets: [{ kg: 100, reps: 5 }] }] },
      pyramidLog: { [OLD]: { cap: 5, vest: 0 } },
      deloadLog:  { [OLD]: { mean: 44 } },
      mind: { ...base().mind, ladderLog: { [OLD]: { cap: 3 } } } });
    const client = base({ updatedAt: NOW, tombs: {
      [`lift:squat:${OLD}`]: NOW, [`pyr:${OLD}`]: NOW, [`dl:${OLD}`]: NOW, [`mladder:${OLD}`]: NOW } });
    const m = mergeState(server, client);
    assert.equal(m.lifts.squat, undefined, 'an emptied lift entry came back');
    assert.equal(m.pyramidLog[OLD], undefined);
    assert.equal(m.deloadLog[OLD], undefined);
    assert.equal(m.mind.ladderLog[OLD], undefined);
  });

  test('deleting one entry does not take its neighbours with it', () => {
    const server = base({ updatedAt: 1000,
      lifts: { squat: [{ d: OLD, sets: [{ kg: 100, reps: 5 }] },
                       { d: daysAgo(20), sets: [{ kg: 102.5, reps: 5 }] }],
               row:   [{ d: OLD, sets: [{ kg: 60, reps: 10 }] }] } });
    const client = base({ updatedAt: NOW, tombs: { [`lift:squat:${OLD}`]: NOW } });
    const m = mergeState(server, client);
    assert.equal(m.lifts.squat.length, 1);
    assert.equal(m.lifts.squat[0].d, daysAgo(20));
    assert.equal(m.lifts.row.length, 1, 'a different lift on the same date was hit');
  });
});

describe('tombstones — re-creating beats the tombstone', () => {
  /* The half that is easy to get wrong. Delete a weigh-in, then type it
     again: a "tombstone always wins" merge eats the value you just entered
     and there is no error to explain it. */
  test('a value written after the tombstone survives', () => {
    const tombAt = NOW - 60_000;
    const server = base({ updatedAt: tombAt, tombs: { [`w:${OLD}`]: tombAt } });
    const client = base({ updatedAt: NOW, weights: [{ d: OLD, kg: 77.4 }],
      tombs: {} });                                   // re-creating cleared it locally
    const m = mergeState(server, client);
    assert.deepEqual(m.weights.map(w => w.kg), [77.4], 'the re-entered weigh-in was eaten');
    assert.equal(m.tombs[`w:${OLD}`], undefined, 'the overruled tombstone should be dropped');
  });

  test('but a stale device holding the old copy does not resurrect it', () => {
    // The device still has the record, but has not written since the delete.
    const stale  = base({ updatedAt: NOW - 120_000, weights: [{ d: OLD, kg: 99.9 }] });
    const fresh  = base({ updatedAt: NOW, tombs: { [`w:${OLD}`]: NOW - 60_000 } });
    assert.deepEqual(mergeState(stale, fresh).weights, []);
    assert.deepEqual(mergeState(fresh, stale).weights, [], 'order should not matter');
  });
});

describe('tombstones — housekeeping', () => {
  test('they expire, so the record does not grow forever', () => {
    const ancient = Date.now() - 200 * 24 * 3600 * 1000;
    const m = mergeState(
      base({ tombs: { [`w:${OLD}`]: ancient } }),
      base({ updatedAt: 2000 }));
    assert.equal(m.tombs[`w:${OLD}`], undefined, 'a 200-day-old tombstone is still being carried');
  });

  test('an expired tombstone stops deleting', () => {
    const ancient = Date.now() - 200 * 24 * 3600 * 1000;
    const m = mergeState(
      base({ updatedAt: 1000, weights: [{ d: OLD, kg: 78 }] }),
      base({ updatedAt: 2000, tombs: { [`w:${OLD}`]: ancient } }));
    assert.deepEqual(m.weights.map(w => w.kg), [78]);
  });

  test('the newest timestamp wins when both sides have the same tombstone', () => {
    const m = mergeState(
      base({ tombs: { [`w:${OLD}`]: NOW - 5000 } }),
      base({ updatedAt: 2000, tombs: { [`w:${OLD}`]: NOW } }));
    assert.equal(m.tombs[`w:${OLD}`], NOW);
  });

  test('a record with no tombs field at all still merges', () => {
    const a = base({ updatedAt: 1000, weights: [{ d: OLD, kg: 78 }] });
    delete a.tombs;
    const b = base({ updatedAt: 2000 });
    delete b.tombs;
    const m = mergeState(a, b);
    assert.deepEqual(m.tombs, {});
    assert.equal(m.weights.length, 1, 'a pre-tombstone record lost data');
  });

  test('garbage in the tombs map is ignored rather than throwing', () => {
    const m = mergeState(
      base({ updatedAt: 1000, weights: [{ d: OLD, kg: 78 }] }),
      base({ updatedAt: 2000, tombs: { [`w:${OLD}`]: 'yesterday', 'junk': null } }));
    assert.equal(m.weights.length, 1, 'a non-numeric timestamp deleted a real record');
  });
});

describe('the client records a tombstone wherever it deletes', () => {
  /* A delete path that forgets to call tomb() is silently the old bug
     again, for that one collection. */
  const src = readFileSync(new URL('../app.js', import.meta.url), 'utf8');

  test('every delete site is paired with a tombstone', () => {
    for (const [what, near] of [
      ['a weigh-in',       /S\.weights=S\.weights\.filter\(x=>x\.d!==d\);[\s\S]{0,120}?tomb\(tombKey\.weight\(d\)\)/],
      ['a lift entry',     /else tomb\(tombKey\.lift\(id,activeDate\)\)/],
      ['a pyramid record', /delete S\.pyramidLog\[activeDate\]; tomb\(tombKey\.pyr\(activeDate\)\)/],
      ['a ladder week',    /delete M\(\)\.ladderLog\[todayISO\]; tomb\(tombKey\.ladder\(todayISO\)\)/],
      ['a deload week',    /delete S\.deloadLog\[d\]; tomb\(tombKey\.deload\(d\)\)/],
    ]) assert.match(src, near, `deleting ${what} does not record a tombstone`);
  });

  test('and every re-create site clears one', () => {
    for (const key of ['weight', 'waist', 'lift', 'pyr', 'ladder', 'deload'])
      assert.match(src, new RegExp(`untomb\\(tombKey\\.${key}\\(`),
        `re-creating via tombKey.${key} does not clear its tombstone`);
  });

  test('tombstones are pruned on the client too, not only in the merge', () => {
    assert.match(src, /function pruneTombs\(\)/);
    assert.match(src, /const tombsPruned\s*=\s*pruneTombs\(\)/,
      'pruneTombs should run at boot, or the local map grows forever');
  });
});
