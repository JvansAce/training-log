/* Regression guard for the bug that took six rounds to find.
 *
 * `.updatebar` set `display:flex` unconditionally. The browser's own default
 * stylesheet has `[hidden]{display:none}`, but an author stylesheet beats the
 * user-agent stylesheet whenever both declare the same property — origin is
 * decided before specificity is even considered. So app.js toggled the hidden
 * attribute correctly for weeks while CSS silently discarded it, and the
 * update banner was simply always on screen.
 *
 * Nothing in the jsdom suites could catch it: jsdom does not resolve the
 * cascade across origins the way a real engine does. This is a static check
 * of the same invariant — any element that relies on `hidden` must not have a
 * class whose CSS sets `display` without a matching `[hidden]` override.
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const root = new URL('..', import.meta.url);
const html = readFileSync(new URL('index.html', root), 'utf8');
const css = readFileSync(new URL('app.css', root), 'utf8');

/* Elements written with a `hidden` attribute in the shell, and their classes. */
function hiddenElements(){
  const out = [];
  for (const tag of html.match(/<[a-z][^>]*\bhidden\b[^>]*>/gi) || []){
    const cls = /class="([^"]+)"/.exec(tag);
    const id = /id="([^"]+)"/.exec(tag);
    if (cls) out.push({ id: id ? id[1] : '(no id)', classes: cls[1].trim().split(/\s+/) });
  }
  return out;
}

/* Strip comments, then collect every rule body whose selector list mentions
   this class — so `.a, .b{...}` counts for both. */
function rulesForClass(cls){
  const bare = css.replace(/\/\*[\s\S]*?\*\//g, '');
  const rules = [];
  for (const m of bare.matchAll(/([^{}]+)\{([^{}]*)\}/g)){
    const [, selector, body] = m;
    if (new RegExp(`\\.${cls}(?![\\w-])`).test(selector)) rules.push({ selector: selector.trim(), body });
  }
  return rules;
}

const declaresDisplay = body => /(^|[;{\s])display\s*:/.test(body);

test('index.html actually contains elements relying on the hidden attribute', () => {
  // If this ever fails the check below is vacuous and would pass silently.
  assert.ok(hiddenElements().length > 0, 'expected at least one [hidden] element to guard');
});

test('no class both sets display and is used on a [hidden] element without an override', () => {
  const failures = [];

  for (const el of hiddenElements()){
    for (const cls of el.classes){
      const rules = rulesForClass(cls);
      const setsDisplay = rules.filter(r => declaresDisplay(r.body) && !/\[hidden\]/.test(r.selector));
      if (!setsDisplay.length) continue;

      // Something must restore display:none when the attribute is present.
      const hasOverride = rules.some(r =>
        /\[hidden\]/.test(r.selector) && /display\s*:\s*none/.test(r.body));

      if (!hasOverride){
        failures.push(
          `#${el.id} uses .${cls}, which sets display in: ${setsDisplay.map(r => r.selector).join(', ')}\n` +
          `    An author 'display' declaration overrides the browser's [hidden]{display:none} regardless of\n` +
          `    specificity, so toggling .hidden in JS will have no visible effect.\n` +
          `    Add: .${cls}[hidden]{display:none}`);
      }
    }
  }

  assert.deepEqual(failures, [], '\n' + failures.join('\n'));
});

test('the guard detects the original bug when it is reintroduced', () => {
  // Proves the check above is load-bearing rather than trivially passing.
  const brokenCss = '.updatebar{display:flex}';
  const bare = brokenCss.replace(/\/\*[\s\S]*?\*\//g, '');
  const rules = [];
  for (const m of bare.matchAll(/([^{}]+)\{([^{}]*)\}/g)){
    const [, selector, body] = m;
    if (/\.updatebar(?![\w-])/.test(selector)) rules.push({ selector, body });
  }
  const setsDisplay = rules.some(r => declaresDisplay(r.body) && !/\[hidden\]/.test(r.selector));
  const hasOverride = rules.some(r => /\[hidden\]/.test(r.selector) && /display\s*:\s*none/.test(r.body));
  assert.ok(setsDisplay && !hasOverride, 'the detector should flag a bare display rule with no [hidden] override');
});
