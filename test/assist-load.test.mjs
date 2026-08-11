/* Negative load — a band or an assist machine taking weight off a pull-up.
 *
 * The whole lift pipeline was written when load could only be null (plain
 * bodyweight) or positive, and several links in it read a load as "truthy"
 * rather than "greater than zero". A -15 kg set walked through those as if
 * it were 15 kg of added weight: an e1RM of -19, a progression target that
 * added help instead of taking it away, and a back-off after a layoff that
 * jumped an assisted lifter straight onto weighted pull-ups.
 *
 * These are behavioural rather than static. app.js is a browser script with
 * no exports, so the prefix up to the charts section — every pure lift
 * function lives in it — is evaluated in a vm with the two globals it
 * touches at load time stubbed out.
 */
import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

const source = readFileSync(new URL('../app.js', import.meta.url), 'utf8');
const cut = source.indexOf('/* ---------------- charts ---------------- */');
assert.notEqual(cut, -1, 'app.js should still have a charts section marking the end of the maths');

const NAMES = ['fmtLoad', 'fmtSet', 'beats', 'setsOf', 'volumeOf', 'e1rm', 'loadStep',
  'allowsAssist', 'nextTarget', 'setRowHtml', 'MAX_ASSIST'];

const sandbox = {
  document: { addEventListener(){} },
  localStorage: { getItem: () => null, setItem(){}, removeItem(){} },
  structuredClone, console, Date, Math, JSON, Object, Array, Set, Map, isNaN, parseFloat, parseInt,
};
vm.createContext(sandbox);
vm.runInContext(
  source.slice(0, cut) + `\nglobalThis.api = {${NAMES.join(',')}};\nglobalThis.setS = v => { S = v };\n`,
  sandbox);
const { fmtLoad, fmtSet, beats, volumeOf, e1rm, loadStep, allowsAssist, nextTarget, setRowHtml, MAX_ASSIST }
  = sandbox.api;

/* A history for one lift, newest last, so nextTarget has something to read. */
function withHistory(id, entries){
  sandbox.setS({ lifts: { [id]: entries }, barKg: 20 });
}

describe('which lifts can be assisted', () => {
  test('the bodyweight lifts accept a negative load', () => {
    for (const id of ['pullup', 'wpullup', 'dips'])
      assert.equal(allowsAssist(id), true, `${id} is loaded by your own body — help is a minus`);
  });

  test('everything else is not', () => {
    // "BW -15 kg" on a barbell row would be a claim about a load that
    // cannot exist: the bar does not go below empty.
    for (const id of ['row', 'squat', 'incline', 'lat', 'ohp'])
      assert.equal(allowsAssist(id), false, `${id} should not offer assistance`);
  });

  test('the input opens up only on the lifts that allow it', () => {
    assert.match(setRowHtml('pullup', 0, null), new RegExp(`min="-${MAX_ASSIST}"`));
    assert.match(setRowHtml('row', 0, null), /min="0"/);
    assert.match(setRowHtml('pullup', 0, null), /negative for assistance/,
      'the screen reader label has to say the field takes a minus');
  });
});

describe('reading a signed load back', () => {
  test('assistance prints as bodyweight minus the help', () => {
    assert.equal(fmtSet({ kg: -15, reps: 8 }), 'BW −15 kg × 8');
    assert.equal(fmtSet({ kg: -12.5, reps: 6 }), 'BW −12.5 kg × 6');
  });

  test('nothing else changed shape', () => {
    assert.equal(fmtSet({ kg: 12.5, reps: 8 }), '12.5 kg × 8');
    assert.equal(fmtSet({ kg: null, reps: 8 }), 'BW × 8');
    assert.equal(fmtSet({ reps: 8 }), 'BW × 8');
  });

  test('zero is bodyweight, not a load of nothing', () => {
    assert.equal(fmtSet({ kg: 0, reps: 8 }), 'BW × 8');
    assert.equal(fmtLoad(0), 'bodyweight');
    assert.equal(fmtLoad(null), 'bodyweight');
    assert.equal(fmtLoad(-15), '15 kg assist');
    assert.equal(fmtLoad(15), '15 kg');
  });

  test('less help is a better set, and bodyweight beats any amount of it', () => {
    assert.equal(beats({ kg: -10, reps: 8 }, { kg: -15, reps: 8 }), true);
    assert.equal(beats({ kg: -15, reps: 8 }, { kg: -10, reps: 8 }), false);
    assert.equal(beats({ kg: null, reps: 8 }, { kg: -5, reps: 8 }), true);
    assert.equal(beats({ kg: 5, reps: 8 }, { kg: null, reps: 8 }), true);
  });
});

describe('the maths that only works on real load', () => {
  test('an assisted set has no e1RM', () => {
    // -15 × 8 through Epley reads -19 kg, which then becomes the peak of a
    // series, the number a stall is measured against, and a printed "e1RM".
    assert.equal(e1rm({ kg: -15, reps: 8 }), null);
    assert.equal(e1rm({ kg: 0, reps: 8 }), null);
    assert.equal(e1rm({ kg: null, reps: 8 }), null);
    assert.equal(Math.round(e1rm({ kg: 100, reps: 5 })), 117);
  });

  test('an assisted session reports reps, the way a bodyweight one does', () => {
    const v = volumeOf({ sets: [{ kg: -15, reps: 8 }, { kg: -15, reps: 7 }] });
    assert.equal(v.kg, null, 'negative kg-volume would read as work done in reverse');
    assert.equal(v.reps, 15);
  });

  test('the step is sized off how much load there is, not which side of zero', () => {
    assert.equal(loadStep(-10), 1);
    assert.equal(loadStep(-20), 2.5);
    assert.equal(loadStep(10), 1);
    assert.equal(loadStep(20), 2.5);
  });
});

describe('progression on an assisted lift', () => {
  test('hitting the top of the range takes help away', () => {
    withHistory('dips', [{ d: '2026-08-04', sets: [{ kg: -15, reps: 12 }, { kg: -15, reps: 12 }] }]);
    const t = nextTarget('dips', '2026-08-11', '3 × 8–12');
    assert.equal(t.kg, -12.5, 'adding load means less assistance, not more');
    assert.match(t.text, /12\.5 kg assist/);
  });

  test('the last kilo of help lands on bodyweight, and says so', () => {
    withHistory('pullup', [{ d: '2026-08-04', sets: [{ kg: -1, reps: 8 }] }]);
    const t = nextTarget('pullup', '2026-08-11', '4 × 5–8');
    assert.equal(t.kg, 0);
    assert.match(t.text, /bodyweight/, 'a target of "go 0 kg" is not a sentence anyone reads');
  });

  test('short of the range it holds the same assistance', () => {
    withHistory('dips', [{ d: '2026-08-04', sets: [{ kg: -15, reps: 9 }] }]);
    const t = nextTarget('dips', '2026-08-11', '3 × 8–12');
    assert.equal(t.kg, -15);
    assert.match(t.text, /stay 15 kg assist — chase 10 reps/);
  });

  test('coming back from a long layoff gives more help, not more weight', () => {
    withHistory('dips', [{ d: '2026-07-01', sets: [{ kg: -15, reps: 10 }] }]);
    const t = nextTarget('dips', '2026-08-11', '3 × 8–12');
    assert.ok(t.kg < -15, `backing off an assisted lift means opening deeper than -15, got ${t.kg}`);
    assert.match(t.text, /climb back/);
  });

  test('the loaded case is untouched', () => {
    withHistory('squat', [{ d: '2026-07-01', sets: [{ kg: 100, reps: 5 }] }]);
    assert.equal(nextTarget('squat', '2026-08-11', '4 × 5–8').kg, 90, 'a long layoff still opens 10% down');

    withHistory('squat', [{ d: '2026-08-04', sets: [{ kg: 100, reps: 8 }] }]);
    const t = nextTarget('squat', '2026-08-11', '4 × 5–8');
    assert.equal(t.kg, 102.5);
    assert.match(t.text, /102\.5 kg/);
  });
});

test('a typed zero is stored as bodyweight rather than as a load', () => {
  // Behavioural coverage of this needs the DOM; the invariant is one line
  // in saveSets and worth pinning where the rest of the rules live.
  const at = source.indexOf('function saveSets');
  assert.notEqual(at, -1);
  assert.match(source.slice(at, at + 700), /kg\s*===\s*0\s*\?\s*null/,
    'storing 0 puts "0 kg × 8" through every formatter and a zero point through e1RM');
});
