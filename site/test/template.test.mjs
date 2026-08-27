import { test } from 'node:test';
import assert from 'node:assert/strict';
import { escapeHtml, render, assertNoPlaceholders } from '../lib/template.mjs';

test('escapeHtml escapes the five HTML metacharacters', () => {
  assert.equal(escapeHtml(`<a href="x">Tom & Jerry's</a>`), '&lt;a href=&quot;x&quot;&gt;Tom &amp; Jerry&#39;s&lt;/a&gt;');
  assert.equal(escapeHtml(42), '42');
});

test('render substitutes nested keys with escaping and triple braces raw', () => {
  const out = render('<h1>{{site.name}}</h1>{{{html}}} v{{ latest.version }}', {
    site: { name: 'A & B' }, html: '<em>raw</em>', latest: { version: '1.0.1' },
  });
  assert.equal(out, '<h1>A &amp; B</h1><em>raw</em> v1.0.1');
});

test('render throws on a missing value instead of emitting an empty string', () => {
  assert.throws(() => render('{{latest.dmg.url}}', { latest: {} }), /Missing template value: latest\.dmg\.url/);
  assert.throws(() => render('{{x}}', { x: null }), /Missing template value: x/);
});

test('render leaves inserted content alone (no double substitution, no $ patterns)', () => {
  assert.equal(render('{{{a}}}', { a: '{{b}} $& $1' }), '{{b}} $& $1');
});

test('assertNoPlaceholders reports the first leftover placeholder and the file', () => {
  assert.doesNotThrow(() => assertNoPlaceholders('<p>fine</p>', 'index.html'));
  assert.throws(() => assertNoPlaceholders('<p>{{ oops }}</p>', 'index.html'), /Unresolved placeholder \{\{ oops \}\} in index\.html/);
});
