import { test } from 'node:test';
import assert from 'node:assert/strict';
import { fetchReleases, renderMarkdown } from '../lib/github.mjs';

function stubFetch(response) {
  const calls = [];
  const fetchImpl = async (url, init) => { calls.push({ url, init }); return response; };
  return { calls, fetchImpl };
}

test('fetchReleases hits the releases endpoint with API headers and a bearer token', async () => {
  const { calls, fetchImpl } = stubFetch({ ok: true, status: 200, json: async () => [{ tag_name: 'v1.0.1' }] });
  const releases = await fetchReleases('jeffcaldwellca/portDrop', 'tok', fetchImpl);
  assert.deepEqual(releases, [{ tag_name: 'v1.0.1' }]);
  assert.equal(calls[0].url, 'https://api.github.com/repos/jeffcaldwellca/portDrop/releases?per_page=100');
  assert.equal(calls[0].init.headers.Authorization, 'Bearer tok');
  assert.equal(calls[0].init.headers.Accept, 'application/vnd.github+json');
  assert.equal(calls[0].init.headers['X-GitHub-Api-Version'], '2022-11-28');
  assert.match(calls[0].init.headers['User-Agent'], /portdrop/i);
});

test('fetchReleases omits Authorization without a token', async () => {
  const { calls, fetchImpl } = stubFetch({ ok: true, status: 200, json: async () => [] });
  await fetchReleases('a/b', undefined, fetchImpl);
  assert.equal('Authorization' in calls[0].init.headers, false);
});

test('fetchReleases throws on HTTP errors and on non-list bodies', async () => {
  await assert.rejects(fetchReleases('a/b', undefined, stubFetch({ ok: false, status: 403, statusText: 'rate limited' }).fetchImpl), /403 rate limited/);
  await assert.rejects(fetchReleases('a/b', undefined, stubFetch({ ok: true, status: 200, json: async () => ({ message: 'nope' }) }).fetchImpl), /not a list/);
});

test('renderMarkdown posts GFM with repo context and returns the HTML', async () => {
  const { calls, fetchImpl } = stubFetch({ ok: true, status: 200, text: async () => '<p>hi</p>' });
  assert.equal(await renderMarkdown('hi', 'a/b', 'tok', fetchImpl), '<p>hi</p>');
  assert.equal(calls[0].url, 'https://api.github.com/markdown');
  assert.equal(calls[0].init.method, 'POST');
  assert.deepEqual(JSON.parse(calls[0].init.body), { text: 'hi', mode: 'gfm', context: 'a/b' });
  assert.equal(calls[0].init.headers['Content-Type'], 'application/json');
});

test('renderMarkdown short-circuits blank input and throws on HTTP errors', async () => {
  const { calls, fetchImpl } = stubFetch({ ok: true, status: 200, text: async () => 'x' });
  assert.equal(await renderMarkdown('  \n', 'a/b', undefined, fetchImpl), '');
  assert.equal(calls.length, 0);
  await assert.rejects(renderMarkdown('hi', 'a/b', undefined, stubFetch({ ok: false, status: 500, statusText: 'boom' }).fetchImpl), /500 boom/);
});
