import { test } from 'node:test';
import assert from 'node:assert/strict';
import { absolute, buildJsonLd, buildSitemap, buildRobots, buildLlmsTxt } from '../lib/metadata.mjs';

const site = {
  name: 'PortDrop', tagline: 'Tag line.', description: 'Desc.', baseUrl: 'https://www.jeffcaldwell.ca/portDrop/',
  repo: 'jeffcaldwellca/portDrop', repoUrl: 'https://github.com/jeffcaldwellca/portDrop',
  issuesUrl: 'https://github.com/jeffcaldwellca/portDrop/issues', releasesUrl: 'https://github.com/jeffcaldwellca/portDrop/releases',
  feedUrl: 'https://github.com/jeffcaldwellca/portDrop/releases.atom',
  author: { name: 'Jeff Caldwell', url: 'https://github.com/jeffcaldwellca' }, minimumOS: 'macOS 26 Tahoe',
  homebrew: { tap: 'jeffcaldwellca/tap', cask: 'portdrop', caskUrl: 'https://github.com/jeffcaldwellca/homebrew-tap/blob/main/Casks/portdrop.rb', command: 'brew install --cask jeffcaldwellca/tap/portdrop' },
};
const latest = { version: '1.0.1', date: '2026-08-25', dateLabel: 'August 25, 2026', dmg: { url: 'https://x/PortDrop-1.0.1.dmg', size: 4056699, sizeLabel: '4.1 MB' }, sha256Url: 'https://x/PortDrop-1.0.1.dmg.sha256' };
const first = { ...latest, version: '1.0.0', date: '2026-08-20' };

test('absolute resolves against the base URL, keeping the /portDrop/ prefix', () => {
  assert.equal(absolute(site, 'releases/'), 'https://www.jeffcaldwell.ca/portDrop/releases/');
  assert.equal(absolute(site, ''), 'https://www.jeffcaldwell.ca/portDrop/');
});

test('home JSON-LD has WebSite, SoftwareApplication and FAQPage with the right fields', () => {
  const faq = [{ question: 'Q?', answer: '<p>A</p>' }];
  const graph = JSON.parse(buildJsonLd({ site, latest, first, page: 'home', faq }))['@graph'];
  const types = graph.map((n) => n['@type']);
  assert.deepEqual(types, ['WebSite', 'SoftwareApplication', 'FAQPage']);
  const app = graph[1];
  assert.equal(app.softwareVersion, '1.0.1');
  assert.equal(app.datePublished, '2026-08-20');
  assert.equal(app.dateModified, '2026-08-25');
  assert.equal(app.downloadUrl, 'https://x/PortDrop-1.0.1.dmg');
  assert.equal(app.installUrl, site.homebrew.caskUrl);
  assert.equal(app.operatingSystem, 'macOS 26 or later');
  assert.equal(app.applicationCategory, 'DeveloperApplication');
  assert.equal(app.releaseNotes, 'https://www.jeffcaldwell.ca/portDrop/releases/');
  assert.equal(app.screenshot, 'https://www.jeffcaldwell.ca/portDrop/assets/panel-light.png');
  assert.equal(app.fileSize, '3962 KB');
  assert.deepEqual(app.offers, { '@type': 'Offer', price: '0', priceCurrency: 'USD' });
  assert.deepEqual(app.author, { '@type': 'Person', name: 'Jeff Caldwell', url: 'https://github.com/jeffcaldwellca' });
  assert.equal('license' in app, false);
  assert.deepEqual(graph[2].mainEntity[0], { '@type': 'Question', name: 'Q?', acceptedAnswer: { '@type': 'Answer', text: '<p>A</p>' } });
});

test('releases JSON-LD has a breadcrumb plus the app, and no FAQ', () => {
  const graph = JSON.parse(buildJsonLd({ site, latest, first, page: 'releases' }))['@graph'];
  assert.deepEqual(graph.map((n) => n['@type']), ['BreadcrumbList', 'SoftwareApplication']);
  assert.equal(graph[0].itemListElement[1].item, 'https://www.jeffcaldwell.ca/portDrop/releases/');
});

test('JSON-LD never contains a raw </script> terminator', () => {
  const faq = [{ question: 'Q', answer: '</script><p>x</p>' }];
  const json = buildJsonLd({ site, latest, first, page: 'home', faq });
  assert.doesNotMatch(json, /<\/script/);
  assert.equal(JSON.parse(json)['@graph'][2].mainEntity[0].acceptedAnswer.text, '</script><p>x</p>');
});

test('sitemap lists every page with lastmod', () => {
  const xml = buildSitemap(site, [{ path: '', lastmod: '2026-08-25' }, { path: 'releases/', lastmod: '2026-08-25' }]);
  assert.match(xml, /^<\?xml version="1\.0" encoding="UTF-8"\?>/);
  assert.match(xml, /<loc>https:\/\/www\.jeffcaldwell\.ca\/portDrop\/<\/loc>\s*<lastmod>2026-08-25<\/lastmod>/);
  assert.match(xml, /<loc>https:\/\/www\.jeffcaldwell\.ca\/portDrop\/releases\/<\/loc>/);
});

test('robots allows everything and points at the sitemap', () => {
  assert.equal(buildRobots(site), 'User-agent: *\nAllow: /\n\nSitemap: https://www.jeffcaldwell.ca/portDrop/sitemap.xml\n');
});

test('llms.txt summarises the product with the latest version and install commands', () => {
  const txt = buildLlmsTxt(site, latest);
  assert.match(txt, /^# PortDrop\n/);
  assert.match(txt, /Latest version: 1\.0\.1 \(August 25, 2026\)/);
  assert.match(txt, /brew install --cask jeffcaldwellca\/tap\/portdrop/);
  assert.match(txt, /https:\/\/x\/PortDrop-1\.0\.1\.dmg/);
  assert.match(txt, /macOS 26 Tahoe or later/);
  assert.doesNotMatch(txt, /open source|MIT|licen[cs]e/i);
});
