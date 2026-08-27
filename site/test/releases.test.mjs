import { test } from 'node:test';
import assert from 'node:assert/strict';
import { formatBytes, formatDate, normalizeRelease, pickLatest, releaseToHtml, releasesToHtml, demoteHeadings } from '../lib/releases.mjs';

const asset = (name, size) => ({ name, size, browser_download_url: `https://github.com/jeffcaldwellca/portDrop/releases/download/v1.0.1/${name}`, content_type: 'application/octet-stream' });
const API_RELEASE = {
  tag_name: 'v1.0.1', name: 'PortDrop 1.0.1', draft: false, prerelease: false,
  published_at: '2026-08-25T15:28:37Z', html_url: 'https://github.com/jeffcaldwellca/portDrop/releases/tag/v1.0.1',
  body: '**Full Changelog**: v1.0.0...v1.0.1',
  assets: [asset('appcast.xml', 1170), asset('PortDrop-1.0.1.dmg', 4056699), asset('PortDrop-1.0.1.dmg.sha256', 85), asset('PortDrop-1.0.1.zip', 2580612)],
};

test('formatBytes picks a sensible unit', () => {
  assert.equal(formatBytes(4056699), '4.1 MB');
  assert.equal(formatBytes(2580), '3 KB');
  assert.equal(formatBytes(85), '85 B');
});

test('formatDate is a long en-US date in UTC', () => {
  assert.equal(formatDate('2026-08-25T23:59:59Z'), 'August 25, 2026');
});

test('demoteHeadings shifts every heading down one level and caps at h6', () => {
  assert.equal(demoteHeadings('<h2 dir="auto">What\'s Changed</h2><h6>x</h6>'), '<h3 dir="auto">What\'s Changed</h3><h6>x</h6>');
});

test('normalizeRelease demotes headings in the rendered notes', () => {
  const r = normalizeRelease(API_RELEASE, '<h2 dir="auto">What\'s Changed</h2><ul><li>fix</li></ul>');
  assert.equal(r.notesHtml, '<h3 dir="auto">What\'s Changed</h3><ul><li>fix</li></ul>');
});

test('normalizeRelease extracts version, date, DMG and checksum assets', () => {
  const r = normalizeRelease(API_RELEASE, '<p>notes</p>');
  assert.equal(r.version, '1.0.1');
  assert.equal(r.tag, 'v1.0.1');
  assert.equal(r.date, '2026-08-25');
  assert.equal(r.dateLabel, 'August 25, 2026');
  assert.equal(r.prerelease, false);
  assert.equal(r.notesHtml, '<p>notes</p>');
  assert.deepEqual(r.dmg, { url: 'https://github.com/jeffcaldwellca/portDrop/releases/download/v1.0.1/PortDrop-1.0.1.dmg', size: 4056699, sizeLabel: '4.1 MB' });
  assert.equal(r.sha256Url, 'https://github.com/jeffcaldwellca/portDrop/releases/download/v1.0.1/PortDrop-1.0.1.dmg.sha256');
});

test('normalizeRelease tolerates missing name, notes, and assets', () => {
  const r = normalizeRelease({ ...API_RELEASE, name: '', body: null, assets: [] }, '   ');
  assert.equal(r.name, 'PortDrop 1.0.1');
  assert.equal(r.notesHtml, '<p>No notes for this release.</p>');
  assert.equal(r.dmg, null);
  assert.equal(r.sha256Url, null);
});

test('pickLatest skips pre-releases and releases without a DMG + checksum', () => {
  const pre = normalizeRelease({ ...API_RELEASE, tag_name: 'v1.1.0-beta.1', prerelease: true }, '');
  const noDmg = normalizeRelease({ ...API_RELEASE, tag_name: 'v1.0.2', assets: [] }, '');
  const good = normalizeRelease(API_RELEASE, '');
  assert.equal(pickLatest([pre, noDmg, good]), good);
  assert.throws(() => pickLatest([pre, noDmg]), /No published release with a DMG and checksum/);
});

test('releaseToHtml renders an article with badges, time, notes, and assets', () => {
  const html = releaseToHtml(normalizeRelease(API_RELEASE, '<p>notes</p>'), true);
  assert.match(html, /<article class="release" id="v1\.0\.1">/);
  assert.match(html, /<h2><a href="https:\/\/github\.com\/jeffcaldwellca\/portDrop\/releases\/tag\/v1\.0\.1">PortDrop 1\.0\.1<\/a> <span class="badge badge-latest">Latest<\/span><\/h2>/);
  assert.match(html, /<time datetime="2026-08-25">August 25, 2026<\/time>/);
  assert.match(html, /<div class="notes"><p>notes<\/p><\/div>/);
  assert.match(html, /PortDrop-1\.0\.1\.dmg <span class="muted">\(4\.1 MB\)<\/span>/);
  assert.match(html, /SHA-256 checksum/);
  assert.doesNotMatch(html, /appcast|\.zip/);
});

test('releaseToHtml marks pre-releases and omits the assets paragraph when there are none', () => {
  const html = releaseToHtml(normalizeRelease({ ...API_RELEASE, prerelease: true, assets: [] }, ''), false);
  assert.match(html, /badge-pre">Pre-release</);
  assert.doesNotMatch(html, /badge-latest/);
  assert.doesNotMatch(html, /class="assets"/);
});

test('releasesToHtml joins articles and flags only the latest', () => {
  const a = normalizeRelease(API_RELEASE, '');
  const b = normalizeRelease({ ...API_RELEASE, tag_name: 'v1.0.0' }, '');
  const html = releasesToHtml([a, b], a);
  assert.equal((html.match(/<article /g) || []).length, 2);
  assert.equal((html.match(/badge-latest/g) || []).length, 1);
});
