import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, readFile, rm, stat } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { build, deriveSite, faqToHtml } from '../build.mjs';

const dl = (tag, name) => `https://github.com/jeffcaldwellca/portDrop/releases/download/${tag}/${name}`;
const release = (tag, published_at, extra = {}) => {
  const v = tag.slice(1);
  return {
    tag_name: tag, name: `PortDrop ${v}`, draft: false, prerelease: false, published_at,
    html_url: `https://github.com/jeffcaldwellca/portDrop/releases/tag/${tag}`, body: `Notes for ${v}`,
    assets: [
      { name: `PortDrop-${v}.dmg`, size: 4056699, browser_download_url: dl(tag, `PortDrop-${v}.dmg`) },
      { name: `PortDrop-${v}.dmg.sha256`, size: 85, browser_download_url: dl(tag, `PortDrop-${v}.dmg.sha256`) },
      { name: `PortDrop-${v}.zip`, size: 2580612, browser_download_url: dl(tag, `PortDrop-${v}.zip`) },
      { name: 'appcast.xml', size: 1170, browser_download_url: dl(tag, 'appcast.xml') },
    ],
    ...extra,
  };
};
const FIXTURE = [
  release('v1.0.0', '2026-08-25T14:38:11Z'),              // API order is not date order — the build must sort
  release('v1.1.0-beta.1', '2026-08-26T10:00:00Z', { prerelease: true }),
  release('v1.0.2', '2026-08-27T09:00:00Z', { draft: true }),
  release('v1.0.1', '2026-08-25T15:28:37Z'),
];
const stubs = {
  fetchReleases: async () => FIXTURE,
  renderMarkdown: async (text) => `<p>${text}</p>`,
  log: () => {},
};

test('deriveSite adds repo URLs, the brew command and the path prefix', () => {
  const s = deriveSite({ baseUrl: 'https://www.jeffcaldwell.ca/portDrop/', repo: 'jeffcaldwellca/portDrop', homebrew: { tap: 'jeffcaldwellca/tap', cask: 'portdrop' } });
  assert.equal(s.repoUrl, 'https://github.com/jeffcaldwellca/portDrop');
  assert.equal(s.issuesUrl, 'https://github.com/jeffcaldwellca/portDrop/issues');
  assert.equal(s.releasesUrl, 'https://github.com/jeffcaldwellca/portDrop/releases');
  assert.equal(s.feedUrl, 'https://github.com/jeffcaldwellca/portDrop/releases.atom');
  assert.equal(s.buildUrl, 'https://github.com/jeffcaldwellca/portDrop#build-from-source');
  assert.equal(s.homebrew.command, 'brew install --cask jeffcaldwellca/tap/portdrop');
  assert.equal(s.pathPrefix, '/portDrop');
  assert.equal(deriveSite({ baseUrl: 'https://portdrop.example/', repo: 'a/b', homebrew: {} }).pathPrefix, '');
});

test('faqToHtml renders escaped questions and raw answers', () => {
  assert.equal(faqToHtml([{ question: 'A & B?', answer: '<p>x</p>' }]), '<div class="faq-item">\n  <dt>A &amp; B?</dt>\n  <dd><p>x</p></dd>\n</div>');
});

test('build writes a complete site from stubbed release data', async () => {
  const outDir = await mkdtemp(join(tmpdir(), 'portdrop-site-'));
  try {
    const result = await build({ ...stubs, outDir });
    assert.equal(result.latest.version, '1.0.1');

    const index = await readFile(join(outDir, 'index.html'), 'utf8');
    const releases = await readFile(join(outDir, 'releases', 'index.html'), 'utf8');
    const notFound = await readFile(join(outDir, '404.html'), 'utf8');
    for (const [name, html] of [['index', index], ['releases', releases], ['404', notFound]]) {
      assert.doesNotMatch(html, /\{\{/, `${name} has an unresolved placeholder`);
      assert.match(html, /<html lang="en">/);
      assert.doesNotMatch(html, /open source|MIT licen|licen[cs]e/i, `${name} mentions licensing`);
      assert.doesNotMatch(html, /<script src=|<link rel="stylesheet" href="https?:|https:\/\/fonts\.|googletagmanager|google-analytics|plausible\.io/i, `${name} loads third-party resources`);
    }

    // Landing page: title/canonical/OG, latest release stamped in, JSON-LD parses with the expected types.
    assert.match(index, /<title>PortDrop — see and kill whatever is listening on your Mac&#39;s ports<\/title>/);
    assert.match(index, /<link rel="canonical" href="https:\/\/www\.jeffcaldwell\.ca\/portDrop\/">/);
    assert.match(index, /<meta property="og:image" content="https:\/\/www\.jeffcaldwell\.ca\/portDrop\/og-image\.png">/);
    assert.match(index, /Download PortDrop 1\.0\.1 for macOS/);
    assert.match(index, /href="https:\/\/github\.com\/jeffcaldwellca\/portDrop\/releases\/download\/v1\.0\.1\/PortDrop-1\.0\.1\.dmg"/);
    assert.match(index, /brew install --cask jeffcaldwellca\/tap\/portdrop/);
    assert.match(index, /href="\.\/styles\.css"/);
    assert.match(index, /<dt>How do I find what&#39;s using a port on my Mac\?<\/dt>/);
    const ld = JSON.parse(index.match(/<script type="application\/ld\+json">(.*?)<\/script>/s)[1]);
    assert.deepEqual(ld['@graph'].map((n) => n['@type']), ['WebSite', 'SoftwareApplication', 'FAQPage']);
    assert.equal(ld['@graph'][1].softwareVersion, '1.0.1');
    assert.equal(ld['@graph'][1].datePublished, '2026-08-25');
    assert.equal(ld['@graph'][2].mainEntity.length, 12);

    // Releases page: newest first, draft excluded, pre-release marked, only the latest badged, relative root.
    assert.match(releases, /<title>PortDrop releases and changelog<\/title>/);
    assert.match(releases, /href="\.\.\/styles\.css"/);
    const order = [...releases.matchAll(/<article class="release" id="v([^"]+)">/g)].map((m) => m[1]);
    assert.deepEqual(order, ['1.1.0-beta.1', '1.0.1', '1.0.0']);
    assert.equal((releases.match(/badge-latest/g) || []).length, 1);
    assert.match(releases, /badge-pre">Pre-release/);
    assert.match(releases, /<p>Notes for 1\.0\.1<\/p>/);
    const ld2 = JSON.parse(releases.match(/<script type="application\/ld\+json">(.*?)<\/script>/s)[1]);
    assert.deepEqual(ld2['@graph'].map((n) => n['@type']), ['BreadcrumbList', 'SoftwareApplication']);

    // 404: absolute-path links under the Pages prefix, noindex, no JSON-LD.
    assert.match(notFound, /href="\/portDrop\/styles\.css"/);
    assert.match(notFound, /<meta name="robots" content="noindex">/);
    assert.doesNotMatch(notFound, /application\/ld\+json/);

    // Site-level files and copied assets.
    const sitemap = await readFile(join(outDir, 'sitemap.xml'), 'utf8');
    assert.match(sitemap, /<loc>https:\/\/www\.jeffcaldwell\.ca\/portDrop\/releases\/<\/loc>\s*<lastmod>2026-08-25<\/lastmod>/);
    assert.match(await readFile(join(outDir, 'robots.txt'), 'utf8'), /Sitemap: https:\/\/www\.jeffcaldwell\.ca\/portDrop\/sitemap\.xml/);
    assert.match(await readFile(join(outDir, 'llms.txt'), 'utf8'), /Latest version: 1\.0\.1/);
    for (const f of ['.nojekyll', 'styles.css', 'og-image.png', 'favicon.ico', 'site.webmanifest', 'assets/panel-light.png', 'assets/panel-dark.png']) {
      await stat(join(outDir, f));
    }
  } finally {
    await rm(outDir, { recursive: true, force: true });
  }
});

test('build fails loudly when there is no publishable release', async () => {
  const outDir = await mkdtemp(join(tmpdir(), 'portdrop-site-'));
  try {
    await assert.rejects(build({ ...stubs, outDir, fetchReleases: async () => [FIXTURE[1]] }), /No published release with a DMG and checksum/);
  } finally {
    await rm(outDir, { recursive: true, force: true });
  }
});
