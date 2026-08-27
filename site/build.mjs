// Builds the PortDrop website into _site/.
//   node site/build.mjs            (GITHUB_TOKEN optional; raises the API rate limit)
// Release data comes from the GitHub API at build time; notes are rendered by GitHub's markdown API.
// The build throws — never emits a half-filled page — if releases can't be fetched or a placeholder is left.
import { readFile, writeFile, mkdir, cp, rm } from 'node:fs/promises';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { render, escapeHtml, assertNoPlaceholders } from './lib/template.mjs';
import { normalizeRelease, pickLatest, releasesToHtml } from './lib/releases.mjs';
import { absolute, buildJsonLd, buildSitemap, buildRobots, buildLlmsTxt } from './lib/metadata.mjs';
import * as github from './lib/github.mjs';

const SITE_DIR = dirname(fileURLToPath(import.meta.url));
const REPO_DIR = resolve(SITE_DIR, '..');
const ROBOTS_INDEX = 'index, follow, max-image-preview:large';

export function deriveSite(site) {
  const repoUrl = `https://github.com/${site.repo}`;
  return {
    ...site,
    repoUrl,
    issuesUrl: `${repoUrl}/issues`,
    releasesUrl: `${repoUrl}/releases`,
    feedUrl: `${repoUrl}/releases.atom`,
    buildUrl: `${repoUrl}#build-from-source`,
    pathPrefix: new URL(site.baseUrl).pathname.replace(/\/$/, ''),
    homebrew: { ...site.homebrew, command: `brew install --cask ${site.homebrew.tap}/${site.homebrew.cask}` },
  };
}

export function faqToHtml(faq) {
  return faq.map(({ question, answer }) => `<div class="faq-item">\n  <dt>${escapeHtml(question)}</dt>\n  <dd>${answer}</dd>\n</div>`).join('\n');
}

export async function build({
  outDir = join(REPO_DIR, '_site'),
  fetchReleases = github.fetchReleases,
  renderMarkdown = github.renderMarkdown,
  token = process.env.GITHUB_TOKEN,
  log = console.log,
} = {}) {
  const read = (...parts) => readFile(join(SITE_DIR, ...parts), 'utf8');
  const site = deriveSite(JSON.parse(await read('site.json')));
  const faq = JSON.parse(await read('faq.json'));
  const layout = await read('layout.html');

  const raw = (await fetchReleases(site.repo, token))
    .filter((r) => !r.draft)
    .sort((a, b) => b.published_at.localeCompare(a.published_at));
  const releases = [];
  for (const r of raw) releases.push(normalizeRelease(r, await renderMarkdown(r.body ?? '', site.repo, token)));
  const latest = pickLatest(releases);
  const first = releases[releases.length - 1];

  const pages = [
    {
      file: 'index.html', root: '.', robots: ROBOTS_INDEX, canonical: site.baseUrl,
      title: `${site.name} — see and kill whatever is listening on your Mac's ports`,
      description: site.description,
      jsonld: buildJsonLd({ site, latest, first, page: 'home', faq }),
      body: await read('pages', 'index.html'), extra: { faq: faqToHtml(faq) },
    },
    {
      file: 'releases/index.html', root: '..', robots: ROBOTS_INDEX, canonical: absolute(site, 'releases/'),
      title: `${site.name} releases and changelog`,
      description: `Every ${site.name} release with notes, download links, and checksums. Latest: ${latest.version} (${latest.dateLabel}).`,
      jsonld: buildJsonLd({ site, latest, first, page: 'releases' }),
      body: await read('pages', 'releases.html'), extra: { releases: releasesToHtml(releases, latest) },
    },
    {
      // GitHub serves 404.html from any depth, so its links are absolute under the Pages path prefix.
      file: '404.html', root: site.pathPrefix, robots: 'noindex', canonical: absolute(site, '404.html'),
      title: `Page not found — ${site.name}`, description: site.description, jsonld: '',
      body: await read('pages', '404.html'), extra: {},
    },
  ];

  if ([REPO_DIR, SITE_DIR, resolve('/')].includes(resolve(outDir))) throw new Error(`Refusing to clear ${outDir}`);
  await rm(outDir, { recursive: true, force: true });
  await mkdir(join(outDir, 'releases'), { recursive: true });
  await mkdir(join(outDir, 'assets'), { recursive: true });

  for (const page of pages) {
    const ctx = { site, latest, root: page.root, ...page.extra };
    const content = render(page.body, ctx);
    const html = render(layout, {
      ...ctx, content,
      title: page.title, description: page.description, canonical: page.canonical, robots: page.robots,
      ogImage: absolute(site, 'og-image.png'),
      jsonld: page.jsonld ? `<script type="application/ld+json">${page.jsonld}</script>` : '',
    });
    assertNoPlaceholders(html, page.file);
    await writeFile(join(outDir, page.file), html);
  }

  await writeFile(join(outDir, 'sitemap.xml'), buildSitemap(site, [
    { path: '', lastmod: latest.date },
    { path: 'releases/', lastmod: latest.date },
  ]));
  await writeFile(join(outDir, 'robots.txt'), buildRobots(site));
  await writeFile(join(outDir, 'llms.txt'), buildLlmsTxt(site, latest));
  await writeFile(join(outDir, '.nojekyll'), '');
  await cp(join(SITE_DIR, 'static'), outDir, { recursive: true });
  for (const shot of ['panel-light.png', 'panel-dark.png']) {
    await cp(join(REPO_DIR, 'docs', 'screenshots', shot), join(outDir, 'assets', shot));
  }

  log(`Built ${pages.length} pages for PortDrop ${latest.version} (${releases.length} releases) → ${outDir}`);
  return { latest, pages: pages.map((p) => p.file) };
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  build().catch((err) => {
    console.error(`Build failed: ${err.message}`);
    process.exit(1);
  });
}
