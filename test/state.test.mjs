// Committed regression suite for mergeState — the piece of this project most
// likely to silently corrupt someone's training history if it regresses.
// Run with `npm test` or `node --test test/`. Zero dependencies: node:test
// and node:assert are both built into Node, matching this project's
// no-npm-dependencies philosophy for the rest of the codebase.
import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import { mergeState } from '../functions/api/state.js';

// Mirrors the cutoff computed inside mergeState (functions/api/state.js),
// so fixtures land unambiguously on the "old" or "recent" side regardless
// of what day the suite actually runs on.
const daysAgo = n => { const d = new Date(); d.setDate(d.getDate() - n); return d.toISOString().slice(0, 10); };
const TODAY = daysAgo(0);
const YESTERDAY = daysAgo(1);
const OLD = daysAgo(30);      // well past RECENT_DAYS in either direction

const base = (overrides = {}) => ({
  updatedAt: 0, startDate: OLD, pyramidCap: 6, calAdjust: 0,
  weights: [], logs: {}, lifts: {},
  ...overrides
});

describe('mergeState — old days are additive, never overwritten', () => {
  test('done/mob ticks from both sides union on an old day', () => {
    const a = base({ updatedAt: 1000, logs: { [OLD]: { done: [0, 1], mob: [0], fuel: false } } });
    const b = base({ updatedAt: 2000, logs: { [OLD]: { done: [2, 3], mob: [1], fuel: true } } });
    const m = mergeState(a, b);
    assert.deepEqual(m.logs[OLD].done, [0, 1, 2, 3]);
    assert.deepEqual(m.logs[OLD].mob, [0, 1]);
    assert.equal(m.logs[OLD].fuel, true, 'fuel is OR-ed on old days, never lost');
  });

  test('a stale push cannot erase an old-day tick the server already has', () => {
    const server = base({ updatedAt: 5000, logs: { [OLD]: { done: [0, 1, 2, 3, 4], mob: [0], fuel: true } } });
    const stalePush = base({ updatedAt: 1, logs: { [OLD]: { done: [], mob: [], fuel: false } } });
    const m = mergeState(server, stalePush);
    assert.deepEqual(m.logs[OLD].done, [0, 1, 2, 3, 4], 'nothing dropped even though the push is older');
  });

  test('done indices come back sorted and de-duplicated', () => {
    const a = base({ updatedAt: 1, logs: { [OLD]: { done: [3, 1], mob: [], fuel: false } } });
    const b = base({ updatedAt: 2, logs: { [OLD]: { done: [1, 0], mob: [], fuel: false } } });
    const m = mergeState(a, b);
    assert.deepEqual(m.logs[OLD].done, [0, 1, 3]);
  });

  test('old-day note picks whichever side is non-empty', () => {
    const a = base({ updatedAt: 1, logs: { [OLD]: { done: [], mob: [], fuel: false, note: 'sore shoulder' } } });
    const b = base({ updatedAt: 2, logs: { [OLD]: { done: [], mob: [], fuel: false, note: '' } } });
    assert.equal(mergeState(a, b).logs[OLD].note, 'sore shoulder');
    assert.equal(mergeState(b, a).logs[OLD].note, 'sore shoulder');
  });
});

describe('mergeState — recent days (today/yesterday) take the newer write wholesale', () => {
  test('newer updatedAt fully replaces the recent day, not a union', () => {
    const older = base({ updatedAt: 1000, logs: { [TODAY]: { done: [0, 1, 2], mob: [0], fuel: true } } });
    const newer = base({ updatedAt: 2000, logs: { [TODAY]: { done: [0], mob: [], fuel: false } } });
    const m = mergeState(older, newer);
    assert.deepEqual(m.logs[TODAY].done, [0], 'this is what lets unticking something actually stick');
  });

  test('yesterday is also last-write-wins, not additive', () => {
    const older = base({ updatedAt: 1000, logs: { [YESTERDAY]: { done: [0, 1, 2], mob: [], fuel: false } } });
    const newer = base({ updatedAt: 2000, logs: { [YESTERDAY]: { done: [1], mob: [], fuel: false } } });
    assert.deepEqual(mergeState(older, newer).logs[YESTERDAY].done, [1]);
  });

  test('a null log value for a recent day does not crash the merge', () => {
    // Regression: a corrupt write can leave logs[date] literally null rather
    // than absent. Before the ?? {} guard this threw and broke sync for the
    // whole account until the row was hand-edited.
    const a = base({ updatedAt: 1, logs: { [TODAY]: null } });
    const b = base({ updatedAt: 2, logs: {} });
    assert.doesNotThrow(() => mergeState(a, b));
    assert.deepEqual(mergeState(a, b).logs[TODAY], { done: [], mob: [], fuel: false, note: '' });
  });
});

describe('mergeState — weights merge by date across both records', () => {
  test('weigh-ins from two devices union by date', () => {
    const a = base({ updatedAt: 1, weights: [{ d: OLD, kg: 80 }] });
    const b = base({ updatedAt: 2, weights: [{ d: YESTERDAY, kg: 79.5 }] });
    const m = mergeState(a, b);
    assert.deepEqual(m.weights, [{ d: OLD, kg: 80 }, { d: YESTERDAY, kg: 79.5 }]);
  });

  test('same-morning weigh-in from both sides: newest push wins, not a union', () => {
    const a = base({ updatedAt: 1, weights: [{ d: TODAY, kg: 80 }] });
    const b = base({ updatedAt: 2, weights: [{ d: TODAY, kg: 79.4 }] });
    assert.deepEqual(mergeState(a, b).weights, [{ d: TODAY, kg: 79.4 }]);
  });

  test('weights come back sorted by date', () => {
    const a = base({ updatedAt: 1, weights: [{ d: TODAY, kg: 79 }, { d: OLD, kg: 82 }] });
    const m = mergeState(a, base({ updatedAt: 0 }));
    assert.deepEqual(m.weights.map(w => w.d), [OLD, TODAY]);
  });
});

describe('mergeState — lift entries merge per id, per date', () => {
  test('two different lift ids both survive independently', () => {
    const a = base({ updatedAt: 1, lifts: { squat: [{ d: OLD, sets: [{ kg: 100, reps: 5 }] }] } });
    const b = base({ updatedAt: 2, lifts: { ohp: [{ d: OLD, sets: [{ kg: 40, reps: 8 }] }] } });
    const m = mergeState(a, b);
    assert.ok(m.lifts.squat && m.lifts.ohp);
  });

  test('two entries for the same id on different dates both survive', () => {
    const a = base({ updatedAt: 1, lifts: { squat: [{ d: OLD, sets: [{ kg: 100, reps: 5 }] }] } });
    const b = base({ updatedAt: 2, lifts: { squat: [{ d: TODAY, sets: [{ kg: 105, reps: 5 }] }] } });
    const m = mergeState(a, b);
    assert.equal(m.lifts.squat.length, 2);
    assert.deepEqual(m.lifts.squat.map(e => e.d), [OLD, TODAY]);
  });

  test('same id, same date, from both sides: incoming wins (last bound wins)', () => {
    const a = base({ updatedAt: 1, lifts: { squat: [{ d: TODAY, sets: [{ kg: 100, reps: 5 }] }] } });
    const b = base({ updatedAt: 2, lifts: { squat: [{ d: TODAY, sets: [{ kg: 105, reps: 4 }] }] } });
    assert.deepEqual(mergeState(a, b).lifts.squat, [{ d: TODAY, sets: [{ kg: 105, reps: 4 }] }]);
  });

  test('legacy flat {d,kg,reps} lift entries round-trip unchanged', () => {
    // Pre-multi-set data shape. mergeState only re-keys by date — it never
    // has to understand the entry's internal shape, so old history must
    // pass through byte-for-byte.
    const a = base({ updatedAt: 1, lifts: { squat: [{ d: OLD, kg: 100, reps: 6 }] } });
    const m = mergeState(a, base({ updatedAt: 0 }));
    assert.deepEqual(m.lifts.squat, [{ d: OLD, kg: 100, reps: 6 }]);
  });
});

describe('mergeState — settings follow the newer record', () => {
  test('pyramidCap, calAdjust, startDate all come from the newer side', () => {
    const older = base({ updatedAt: 1000, pyramidCap: 6, calAdjust: 100, startDate: '2026-01-01' });
    const newer = base({ updatedAt: 2000, pyramidCap: 8, calAdjust: -100, startDate: '2026-02-01' });
    const m = mergeState(older, newer);
    assert.equal(m.pyramidCap, 8);
    assert.equal(m.calAdjust, -100);
    assert.equal(m.startDate, '2026-02-01');
  });

  test('a missing setting on the newer side falls back to the older side, not a hardcoded default', () => {
    const older = base({ updatedAt: 1000, startDate: '2026-01-01' });
    const newer = { updatedAt: 2000, weights: [], logs: {}, lifts: {} }; // no startDate at all
    assert.equal(mergeState(older, newer).startDate, '2026-01-01');
  });
});

describe('mergeState — recorded WHOOP readings merge additively by date', () => {
  test('readings from two devices on different days both survive', () => {
    const a = base({ updatedAt: 1, whoop: { [OLD]: { recovery: 71, strain: 12.1, sleep: 88, hrv: 44, rhr: 51 } } });
    const b = base({ updatedAt: 2, whoop: { [TODAY]: { recovery: 55, strain: 9.4, sleep: 74, hrv: 38, rhr: 54 } } });
    const m = mergeState(a, b);
    assert.deepEqual(Object.keys(m.whoop).sort(), [OLD, TODAY].sort());
    assert.equal(m.whoop[OLD].recovery, 71);
    assert.equal(m.whoop[TODAY].recovery, 55);
  });

  test('the newer record does not wipe out other days it never saw', () => {
    // The generic unknown-field spread would have replaced the whole whoop
    // object with the newer side's, silently dropping months of history.
    const server = base({ updatedAt: 1000, whoop: { [OLD]: { recovery: 71 }, [YESTERDAY]: { recovery: 60 } } });
    const phone = base({ updatedAt: 9999, whoop: { [TODAY]: { recovery: 55 } } });
    const m = mergeState(server, phone);
    assert.deepEqual(Object.keys(m.whoop).sort(), [OLD, TODAY, YESTERDAY].sort());
  });

  test('a partial early read does not blank a complete later one', () => {
    // Fetched before WHOOP finished scoring: recovery present, strain not.
    const early = base({ updatedAt: 1, whoop: { [TODAY]: { recovery: 55, strain: null, sleep: null, hrv: null, rhr: null } } });
    const late  = base({ updatedAt: 2, whoop: { [TODAY]: { recovery: 55, strain: 14.2, sleep: 91, hrv: 40, rhr: 52 } } });
    assert.equal(mergeState(early, late).whoop[TODAY].strain, 14.2);
    // ...and in the other direction, the stored complete value is kept.
    assert.equal(mergeState(late, early).whoop[TODAY].strain, 14.2);
  });

  test('a record with no whoop data at all merges to an empty object, not undefined', () => {
    const m = mergeState(base({ updatedAt: 1 }), base({ updatedAt: 2 }));
    assert.deepEqual(m.whoop, {});
  });
});

describe('mergeState — unknown fields survive (forward compatibility)', () => {
  test('a field neither this function nor the caller knows about is not dropped', () => {
    // Regression: mergeState used to rebuild a fixed-shape object from
    // scratch, silently deleting anything outside that shape — meaning any
    // future addition to the client's state gets wiped on first sync.
    const m = mergeState(null, base({ updatedAt: 1, bodyFatPct: 14.2 }));
    assert.equal(m.bodyFatPct, 14.2);
  });

  test('an unknown field present on the older side survives when the newer side omits it', () => {
    const older = { ...base({ updatedAt: 1 }), experimentalFlag: true };
    const newer = base({ updatedAt: 2 });
    assert.equal(mergeState(older, newer).experimentalFlag, true);
  });
});

describe('mergeState — missing sides and round trips', () => {
  test('mergeState(null, incoming) treats the missing side as empty, not a throw', () => {
    const m = mergeState(null, base({ updatedAt: 1, weights: [{ d: TODAY, kg: 79 }] }));
    assert.deepEqual(m.weights, [{ d: TODAY, kg: 79 }]);
  });

  test('mergeState(stored, null) treats the missing side as empty, not a throw', () => {
    const m = mergeState(base({ updatedAt: 1, weights: [{ d: TODAY, kg: 79 }] }), null);
    assert.deepEqual(m.weights, [{ d: TODAY, kg: 79 }]);
  });

  test('three-way round trip (phone -> server -> laptop -> server) loses nothing', () => {
    const phoneFirst = base({
      updatedAt: 1000,
      weights: [{ d: OLD, kg: 82 }],
      logs: { [OLD]: { done: [0, 1], mob: [], fuel: false } }
    });
    const serverAfterPhone = mergeState(null, phoneFirst);

    const laptop = base({
      updatedAt: 2000,
      weights: [{ d: YESTERDAY, kg: 80.5 }],
      logs: { [OLD]: { done: [2], mob: [1], fuel: true }, [YESTERDAY]: { done: [0], mob: [], fuel: false } }
    });
    const serverAfterLaptop = mergeState(serverAfterPhone, laptop);

    assert.deepEqual(serverAfterLaptop.weights, [{ d: OLD, kg: 82 }, { d: YESTERDAY, kg: 80.5 }]);
    assert.deepEqual(serverAfterLaptop.logs[OLD].done, [0, 1, 2], 'old-day ticks from both devices survived');
    assert.deepEqual(serverAfterLaptop.logs[OLD].mob, [1]);
    assert.deepEqual(serverAfterLaptop.logs[YESTERDAY].done, [0]);
  });
});
