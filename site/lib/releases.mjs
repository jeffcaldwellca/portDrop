import { escapeHtml } from './template.mjs';

export function formatBytes(bytes) {
  if (bytes >= 1e6) return `${(bytes / 1e6).toFixed(1)} MB`;
  if (bytes >= 1e3) return `${Math.round(bytes / 1e3)} KB`;
  return `${bytes} B`;
}

export function formatDate(iso) {
  return new Date(iso).toLocaleDateString('en-US', { year: 'numeric', month: 'long', day: 'numeric', timeZone: 'UTC' });
}

// Shapes a GitHub Releases API object into what the templates need. `notesHtml` is the release body
// already rendered by GitHub's markdown API.
export function normalizeRelease(release, notesHtml) {
  const version = release.tag_name.replace(/^v/, '');
  const asset = (suffix) => release.assets.find((a) => a.name === `PortDrop-${version}${suffix}`) ?? null;
  const dmg = asset('.dmg');
  const sha = asset('.dmg.sha256');
  return {
    version,
    tag: release.tag_name,
    name: release.name || `PortDrop ${version}`,
    htmlUrl: release.html_url,
    prerelease: Boolean(release.prerelease),
    publishedAt: release.published_at,
    date: release.published_at.slice(0, 10),
    dateLabel: formatDate(release.published_at),
    notesHtml: notesHtml?.trim() || '<p>No notes for this release.</p>',
    dmg: dmg ? { url: dmg.browser_download_url, size: dmg.size, sizeLabel: formatBytes(dmg.size) } : null,
    sha256Url: sha ? sha.browser_download_url : null,
  };
}

export function pickLatest(releases) {
  const latest = releases.find((r) => !r.prerelease && r.dmg && r.sha256Url);
  if (!latest) throw new Error('No published release with a DMG and checksum');
  return latest;
}

export function releaseToHtml(r, isLatest) {
  const badges = [
    isLatest ? '<span class="badge badge-latest">Latest</span>' : '',
    r.prerelease ? '<span class="badge badge-pre">Pre-release</span>' : '',
  ].filter(Boolean).join(' ');
  const assets = [
    r.dmg ? `<a class="asset" href="${escapeHtml(r.dmg.url)}">PortDrop-${escapeHtml(r.version)}.dmg <span class="muted">(${r.dmg.sizeLabel})</span></a>` : '',
    r.sha256Url ? `<a class="asset" href="${escapeHtml(r.sha256Url)}">SHA-256 checksum</a>` : '',
  ].filter(Boolean).join('\n    ');
  return `<article class="release" id="v${escapeHtml(r.version)}">
  <header>
    <h2><a href="${escapeHtml(r.htmlUrl)}">PortDrop ${escapeHtml(r.version)}</a>${badges ? ' ' + badges : ''}</h2>
    <p class="muted"><time datetime="${escapeHtml(r.date)}">${escapeHtml(r.dateLabel)}</time></p>
  </header>
  <div class="notes">${r.notesHtml}</div>
${assets ? `  <p class="assets">\n    ${assets}\n  </p>\n` : ''}</article>`;
}

export function releasesToHtml(releases, latest) {
  return releases.map((r) => releaseToHtml(r, r === latest)).join('\n');
}
