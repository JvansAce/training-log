/* Guards for a bug class that shipped once and will ship again.
 *
 * Every tickable row in this app is a div with a click handler and a
 * keydown handler that treats Space and Enter as a tap. Some of those rows
 * also contain real form controls — number inputs, a textarea, a button.
 * Nothing stops a child's event from bubbling to the row unless someone
 * remembers to, and forgetting is silent: the row just quietly logs a
 * session you did not do.
 *
 * The Mind rows shipped without the guard. Tapping the minutes field logged
 * a full session, pressing Timer marked the sit finished before it started,
 * and the row's `if (key === ' ') preventDefault()` swallowed every space
 * and newline typed into the journal — a real Chromium run produced
 * "avoidedthedentistcall". The Body rows had had the guard on .logrow since
 * multi-set logging was added, which is why only half the app was broken.
 *
 * This is a static check because the behavioural version needs a browser:
 * the failure is in event propagation and default-prevention, which jsdom
 * models but which is cheap to assert structurally on every commit.
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const app = readFileSync(new URL('../app.js', import.meta.url), 'utf8');

/* The body of a wire* function, so assertions are scoped to one handler
   set rather than matching something similar elsewhere in the file. */
function wireFn(name){
  const start = app.indexOf(`function ${name}(`);
  assert.notEqual(start, -1, `${name} should exist`);
  let depth = 0, i = app.indexOf('{', start);
  for (let j = i; j < app.length; j++){
    if (app[j] === '{') depth++;
    else if (app[j] === '}' && --depth === 0) return app.slice(start, j + 1);
  }
  throw new Error(`could not find the end of ${name}`);
}

test('the row tap handler still preventDefaults Space — the thing that makes a guard necessary', () => {
  // If this ever stops being true the guards below are belt-and-braces
  // rather than load-bearing, and the reasoning in this file needs redoing.
  const mind = wireFn('wireMind');
  assert.match(mind, /key===' '\|\|e\.key==='Enter'/,
    'wireMind should still treat Space/Enter on a row as a tap');
  assert.match(mind, /preventDefault\(\)/);
});

test('wireMind stops clicks and keys inside the minutes row from reaching the row', () => {
  const mind = wireFn('wireMind');
  const guard = /\[data-mind-mins\][\s\S]{0,400}?stopPropagation/;
  assert.match(mind, guard,
    'a click inside [data-mind-mins] must not fire the row tap — it logged a full session');
  const block = mind.slice(mind.indexOf('[data-mind-mins]'));
  assert.match(block.slice(0, 400), /onkeydown[\s\S]{0,120}stopPropagation/,
    'keydown must be stopped too, or Space in the number field ticks the practice');
});

/* Anchored on the guard itself rather than on the first mention of
   mindJournal — wireMind also focuses the textarea from the row handler,
   and that earlier occurrence is what this originally matched. */
function journalGuard(){
  const mind = wireFn('wireMind');
  const at = mind.search(/const jrow\s*=/);
  assert.notEqual(at, -1, 'the journal row should be looked up for guarding');
  return mind.slice(at, at + 500);
}

test('wireMind stops keys inside the journal from reaching the row', () => {
  const block = journalGuard();
  assert.match(block, /onkeydown[\s\S]{0,120}stopPropagation/,
    'without this the row swallows every space and newline typed into the journal');
  assert.match(block, /onclick[\s\S]{0,120}stopPropagation/);
});

test('the journal guard does not blur on Enter — an entry wants paragraphs', () => {
  assert.doesNotMatch(journalGuard(), /key==='Enter'[\s\S]{0,60}blur/,
    'Enter in a journal entry should insert a newline, not close the field');
});

test('wireToday keeps the equivalent guard on the body set rows', () => {
  const today = wireFn('wireToday');
  const at = today.indexOf(".querySelectorAll('.logrow')");
  assert.notEqual(at, -1, 'body set rows should still be wired as a group');
  const block = today.slice(at, at + 400);
  assert.match(block, /onclick[\s\S]{0,80}stopPropagation/);
  assert.match(block, /onkeydown[\s\S]{0,80}stopPropagation/);
});

test('render paths read the mind log, they do not create it', () => {
  /* mindLog() creates the day's entry as a side effect. That is right in a
     click handler and wrong in a template — merely opening Mind on a day
     you log nothing was writing an empty entry that the next save then
     persisted and synced forever. */
  for (const fn of ['practiceRow', 'ladderPanel']){
    const body = wireFn(fn);
    assert.doesNotMatch(body, /\bmindLog\(/,
      `${fn} runs during render and must use mindLogRO(), not mindLog()`);
    assert.match(body, /mindLogRO\(/, `${fn} should read the log`);
  }
});

test('the charisma drill does not advance from inside a tick handler', () => {
  /* Advancing mid-tick made the fourth tick un-undoable: the row still read
     as ticked while the current key had moved on, so tapping again pushed
     the new drill's key and credited it a use. It advances at load instead,
     which keeps the index stable for the whole day. */
  const mind = wireFn('wireMind');
  assert.doesNotMatch(mind, /bumpCharisma\(/,
    'bumpCharisma belongs in the boot sequence, not in a click handler');
  assert.match(app, /const drillMoved\s*=\s*bumpCharisma\(\)/,
    'it should still run once at load');
});

test('changing the ladder cap re-evaluates whether the week counts as cleared', () => {
  const mind = wireFn('wireMind');
  const at = mind.indexOf('[data-ladder]');
  assert.notEqual(at, -1);
  assert.match(mind.slice(at, at + 600), /recordLadder\(\)/,
    'raising the cap must un-record a week you have not actually cleared');
});

test('no wiring binds to an element without checking it rendered', () => {
  /* Panels and rows are conditional all over this app — the weigh-in row
     only renders for today, the rest timer only on lifting days, the deload
     prompt only when recovery asks. A bind with no null check throws inside
     render(), which aborts the rest of the wiring for that view: one absent
     element takes the whole page's interactivity with it.

     That shipped once. Moving the weigh-in input to the top of Today made
     #wSave conditional, and previewing any other weekday crashed. */
  const offenders = [];
  for (const fn of ['wireToday', 'wireSetup', 'wireProgress', 'wireMind', 'wireHeight']){
    const body = wireFn(fn);
    // const a=getElementById('x'), b=getElementById('y');  … then a.onclick=
    for (const m of body.matchAll(/const\s+([\w$]+)\s*=\s*document\.getElementById\([^)]*\)(?:\s*,\s*([\w$]+)\s*=\s*document\.getElementById\([^)]*\))?/g)){
      for (const name of [m[1], m[2]].filter(Boolean)){
        const after = body.slice(m.index);
        const bound = new RegExp(`\\b${name}\\.(onclick|onchange|onkeydown|value|disabled)\\s*=`).exec(after);
        if (!bound) continue;
        // Guards come in several shapes and all of them count:
        //   if(x)…  if(!x) return  if(a&&x)  if(!a||!x) return  x?.
        const guard = new RegExp(
          `if\\s*\\(\\s*!?${name}\\b` + `|&&\\s*!?${name}\\b` + `|${name}\\s*&&` +
          `|\\|\\|\\s*!${name}\\b` + `|${name}\\?\\.`);
        if (!guard.test(after.slice(0, bound.index)))
          offenders.push(`${fn}: ${name} is bound with no null check`);
      }
    }
  }
  assert.deepEqual(offenders, [], '\n' + offenders.join('\n'));
});
