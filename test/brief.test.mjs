/* Static guards for the "Ask Claude" briefing.
 *
 * The briefing is the one place in the app where user-written text (session
 * notes) is assembled into a blob and then rendered back into the DOM. It has
 * to be raw in the clipboard — Claude should see exactly what was typed — and
 * escaped in the on-screen preview. Those two requirements pull in opposite
 * directions, which is precisely the kind of thing that gets "simplified"
 * later by someone dropping the escapeHtml call.
 *
 * Behavioural coverage lives in the jsdom and Chromium suites; these are the
 * invariants worth failing a build over, and they need no browser.
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const root = new URL('..', import.meta.url);
const app = readFileSync(new URL('app.js', root), 'utf8');
const css = readFileSync(new URL('app.css', root), 'utf8');

test('the preview escapes the briefing before putting it in the DOM', () => {
  // A session note reading `</pre><img src=x onerror=...>` must not become
  // markup. The clipboard copy is deliberately unescaped; the preview is not.
  assert.match(app, /id="briefText">\$\{escapeHtml\(coachBrief\(\)\)\}/,
    'the #briefText preview must interpolate escapeHtml(coachBrief()), not the raw string');
});

test('the clipboard gets the briefing raw, not the escaped preview', () => {
  // Reading textContent back out of the preview would work too, but it also
  // silently ships whatever a stale render left there. Rebuild on the tap.
  assert.match(app, /copyText\(coachBrief\(\)\)/,
    'the copy handler should call coachBrief() fresh');
  assert.doesNotMatch(app, /copyText\([^)]*briefText/,
    'the copy handler must not read the escaped preview back out of the DOM');
});

test('copying degrades rather than failing silently', () => {
  const fn = /async function copyText\(txt\)\{[\s\S]*?\n\}/.exec(app);
  assert.ok(fn, 'copyText should exist');
  const body = fn[0];
  assert.match(body, /navigator\.clipboard/, 'should try the async clipboard first');
  assert.match(body, /execCommand\('copy'\)/, 'should fall back to the selection copy');
  assert.match(body, /return false/, 'should report failure rather than swallowing it');
  // Every caller must handle a false return by showing the text to copy by hand.
  for (const m of app.matchAll(/if\(await copyText\([^)]*\)\)/g)){
    const after = app.slice(m.index, m.index + 400);
    assert.match(after, /else\s+revealBrief|else\s*\{[\s\S]*?revealBrief|toast\(/,
      'a copy attempt must tell the user what happened either way');
  }
});

test('every element the briefing handlers reach for is actually rendered', () => {
  // Renaming an id in the template without renaming it in wireProgress
  // produces a button that does nothing, with no error anywhere.
  for (const id of ['briefCopy', 'briefShare', 'briefWrap', 'briefText']){
    assert.match(app, new RegExp(`getElementById\\('${id}'\\)`), `${id} should be looked up`);
    assert.match(app, new RegExp(`id="${id}"`), `${id} should be rendered`);
  }
});

test('the preview is height-capped and wraps', () => {
  // A briefing is hundreds of lines of monospace. Unwrapped it pushes the
  // whole page sideways on a phone; uncapped it buries the tab bar.
  const rule = /pre\.brief\{([^}]*)\}/.exec(css);
  assert.ok(rule, 'pre.brief should be styled');
  assert.match(rule[1], /max-height:/, 'should cap its height');
  assert.match(rule[1], /overflow:\s*auto/, 'should scroll internally');
  assert.match(rule[1], /white-space:\s*pre-wrap/, 'should wrap rather than overflow the viewport');
});

test('the briefing states its own no-API-key premise', () => {
  // The whole point of this feature is that it uses a Claude subscription
  // instead of a billed API key. If someone later adds a fetch to an
  // Anthropic endpoint, this file is where the contradiction shows up.
  assert.doesNotMatch(app, /api\.anthropic\.com|ANTHROPIC_API_KEY|x-api-key/i,
    'this app must not call the Anthropic API — the briefing is a clipboard hand-off');
  assert.match(app, /No API key/, 'the panel should say so on screen');
});
