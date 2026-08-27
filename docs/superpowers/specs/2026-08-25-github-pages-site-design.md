# PortDrop website (GitHub Pages) — Design Spec (2026-08-25)

## Purpose
A product site for PortDrop at **https://www.jeffcaldwell.ca/portDrop/** that explains what the app does, gets people installed (Homebrew or DMG), and lists every release with its notes — built to rank in search and to be quoted accurately by AI assistants (SEO + AEO), with rich structured metadata and zero tracking.

## Decisions (from brainstorming)
- **URL**: `https://www.jeffcaldwell.ca/portDrop/` (project Pages site, `/portDrop/` subpath). The base URL is one value in `site/site.json`; a custom domain later is a `CNAME` file plus that one edit. (Changed during implementation: the account's user site carries the custom domain `www.jeffcaldwell.ca`, which GitHub applies to every project site, so the github.io URL 301-redirects there.)
- **Licensing**: the site makes **no license claim** anywhere — no "open source", no "MIT", no `license` property in JSON-LD. It links to the source on GitHub and calls the app "free".
- **Scope**: landing page (`/`), releases page (`/releases/`), `404.html`. No docs subsite.
- **Analytics**: none. No cookies, no third-party requests, no web fonts. The privacy section says so.
- **Stack**: hand-written static HTML/CSS + a zero-dependency Node build script (`site/build.mjs`, Node ≥ 20). No `package.json`, no `node_modules`, no framework. Deployed by GitHub Actions to Pages.
- **Author credit**: "Jeff Caldwell" → `https://github.com/jeffcaldwellca` (JSON-LD `Person`, footer). No email, no social handles, no `twitter:creator`.
- **Release data** comes from the GitHub Releases API at build time; release notes are rendered by GitHub's `POST /markdown` endpoint (GFM, repo context) so they match GitHub exactly without a markdown library.

## Layout

```
site/
  site.json              name, tagline, description, baseUrl, repo, author, minimumOS, homebrew tap
  layout.html            <html>/<head>/<body> shell; {{title}} {{description}} {{canonical}} {{ogImage}} {{jsonld}} {{content}} {{root}}
  pages/index.html       landing body (placeholders for latest release)
  pages/releases.html    releases body ({{releases}} is the rendered list)
  pages/404.html
  static/                styles.css, favicon.ico, favicon-32.png, icon-192.png, icon-512.png,
                         apple-touch-icon.png, site.webmanifest, robots.txt, og-image.png
  build.mjs              the build (fetch → render → write _site/)
  build.test.mjs         node --test unit tests (offline; API calls injected)
Scripts/make-og-image.swift   renders static/og-image.png (1200×630) once; the PNG is committed
Scripts/make-site-icons.sh    derives the favicon/PWA PNGs from the appiconset with sips; committed
.github/workflows/pages.yml
_site/                   build output, gitignored
```

- Screenshots are **not** duplicated: the build copies `docs/screenshots/panel-{light,dark}.png` into `_site/assets/`.
- All in-page links and asset URLs are relative (`./releases/`, `../assets/…`) via a `{{root}}` prefix (`.` on `/`, `..` on `/releases/`), so the site works under the `/portDrop/` subpath and on a local `http.server`. Absolute URLs (canonical, OG, sitemap, JSON-LD) are built from `baseUrl`.
- `404.html` uses absolute-path links built from `baseUrl`'s path (`/portDrop/`) because GitHub serves it from any depth.

## Pages

### Landing `/`
Sections, in order, each with a heading written for search intent:

1. **Hero** — app icon (`static/icon-512.png` displayed at 128 px), `<h1>PortDrop</h1>`, tagline "See every process listening on a local port — open it in one click, kill it in two." Primary CTA: **Download PortDrop {version} for macOS** → direct `.dmg` asset URL, with file size and a link to the `.sha256`. Secondary: the Homebrew command in a `<code>` block with a copy button (progressive enhancement — the only JavaScript on the page; without JS the text is still selectable). Requirement line: "Requires macOS 26 Tahoe or later. Signed and notarized." Panel screenshot via `<picture>` with a `prefers-color-scheme: dark` source; explicit `width`/`height`, `loading="eager"` (it's above the fold), `decoding="async"`.
2. **See what's listening on every port** — feature grid from the README: live list (2 s / 10 s polling), real app icons, service detection (HTTP/S, SSH, FTP, PostgreSQL, MySQL, Redis, MongoDB, VNC, SMB, AFP + HTTP probe), Open (↗), two-step Kill (Confirm reverts after 3 s; ⌥ for SIGKILL), admin escalation, search, right-click menu, menu-bar badge, new-port notification, Launch at Login.
3. **Install** — Homebrew (`brew install --cask jeffcaldwellca/tap/portdrop`), DMG (download → drag to Applications → launch; lives in the menu bar, no Dock icon), verify (`shasum -a 256 -c PortDrop-<version>.dmg.sha256`), Gatekeeper note (Developer ID + notarized), updates (Sparkle checks daily; ⚙︎ → Check for Updates…; `brew upgrade` also works). "Build from source" is a link to the README section, not repeated.
4. **How it works** — `lsof -iTCP -sTCP:LISTEN` polling, `NSRunningApplication`/bundle icon lookup, HTTP `HEAD` probe to `127.0.0.1`/`::1` only, SIGTERM vs SIGKILL, admin dialog for other users' processes, why it isn't sandboxed.
5. **Privacy** — nothing leaves your Mac; no analytics or telemetry in the app; this website sets no cookies and loads nothing from third parties.
6. **FAQ** — `<dl>`-style Q&A (also emitted as `FAQPage` JSON-LD). Questions:
   - How do I find what's using a port on my Mac?
   - How do I kill the process on port 3000 (or any port) on macOS?
   - Is PortDrop safe to install? Is it notarized?
   - Why does PortDrop ask for my password?
   - What's the difference between Kill and Force Kill?
   - Does PortDrop show UDP ports or outbound connections?
   - Which macOS versions does PortDrop support?
   - Does PortDrop send any data anywhere?
   - Is PortDrop free?
   - Where is the Dock icon / window?
   - How do I update PortDrop?
   - How do I uninstall PortDrop?
7. **Footer** — GitHub repository, Releases, Report an issue, "Made by Jeff Caldwell" (→ GitHub profile), "Requires macOS 26+".

### Releases `/releases/`
- Intro: how updates reach you (Sparkle / Homebrew), link to the Atom feed `https://github.com/jeffcaldwellca/portDrop/releases.atom`, link to the latest DMG.
- One `<article>` per non-draft release, newest first: `<h2>` "PortDrop {version}" (linked to the GitHub release), `<time datetime>` published date, "Latest" badge on the current release, "Pre-release" badge when `prerelease` is true, the notes rendered from GitHub's markdown API inside a `.notes` container, then asset links: DMG (with size), `.sha256`. The `.zip` and `appcast.xml` are Sparkle internals and are not listed.
- Breadcrumb: Home › Releases.

### 404
Branded: icon, "That port isn't listening.", link home and to releases.

## Metadata (SEO / AEO)

Per page (`layout.html`, values from the build):
- `<html lang="en">`, `<meta charset>`, viewport, `<title>`, `<meta name="description">`, `<link rel="canonical">`, `<meta name="robots" content="index, follow, max-image-preview:large">`, `<meta name="theme-color">` ×2 with `media` for light/dark, `<meta name="color-scheme" content="light dark">`, `<link rel="alternate" type="application/atom+xml">` pointing at GitHub's releases feed.
- Open Graph: `og:type` (`website`), `og:site_name`, `og:title`, `og:description`, `og:url`, `og:image` (+ `:width` 1200, `:height` 630, `:alt`), `og:locale`.
- Twitter: `twitter:card` = `summary_large_image`, `twitter:title`, `twitter:description`, `twitter:image`, `twitter:image:alt`.
- Icons: `favicon.ico`, `favicon-32.png`, `apple-touch-icon.png` (180), `site.webmanifest` (192/512).

Titles/descriptions:
- `/`: title "PortDrop — see and kill whatever is listening on your Mac's ports"; description ≈ "PortDrop is a free macOS menu-bar app that lists every process listening on a local TCP port, opens the service in one click, and kills the process in two. Homebrew or DMG. macOS 26+."
- `/releases/`: title "PortDrop releases and changelog"; description ≈ "Every PortDrop release with notes, download links, and checksums. Latest: {version} ({date})."

JSON-LD (one `<script type="application/ld+json">` per page holding a `@graph`):
- `/`: `WebSite` (name, url), `SoftwareApplication` { name, description, url, `applicationCategory: "DeveloperApplication"`, `operatingSystem: "macOS 26 or later"`, `softwareVersion`, `datePublished` (first release), `dateModified` (latest release), `downloadUrl` (DMG), `installUrl` (Homebrew tap cask URL), `releaseNotes` (`/releases/`), `screenshot` (absolute light screenshot URL), `image` (icon), `offers: { @type: Offer, price: "0", priceCurrency: "USD" }`, `author: { @type: Person, name, url }`, `fileSize` from the DMG asset }, `FAQPage` with every FAQ entry (same text as the visible `<dl>`).
- `/releases/`: `BreadcrumbList` (Home › Releases) plus one `SoftwareApplication` for the latest release (same shape as the landing page). No per-release schema — search engines don't render it.
- No `license` property anywhere (decision above).

Site-level files (generated unless noted):
- `sitemap.xml`: `/` and `/releases/`, `lastmod` = latest release date (ISO 8601).
- `robots.txt` (static): allow all, `Sitemap:` absolute URL.
- `llms.txt`: plain-text/markdown summary — what PortDrop is, requirements, install commands, latest version + DMG URL, links to README/releases, privacy stance. Regenerated on every build.
- `site.webmanifest` (static): name, short_name, icons, `display: browser`, theme/background colors.
- `og-image.png` (static, committed): 1200×630, mark + wordmark + tagline + panel screenshot on the brand gradient, drawn by `Scripts/make-og-image.swift` (same headless `NSBitmapImageRep` approach as `make-dmg-background.swift`).

Semantics/accessibility: exactly one `<h1>`; `<header>`/`<main>`/`<footer>`/`<section aria-labelledby>`; `<nav aria-label>`; `<time datetime>`; skip link; visible focus rings; alt text on every image; `prefers-reduced-motion` disables the hero glow animation (if any); colour contrast ≥ 4.5:1 for text.

## Visual direction
- Accent: the icon's blue→purple gradient (exact hex values sampled from the appiconset during implementation) as gradient for the hero glow, primary button, and badges. Neutral greys for surfaces. Light and dark via `prefers-color-scheme`, tokens on `:root`.
- Type: system stack (`-apple-system, BlinkMacSystemFont, "SF Pro Text", "Segoe UI", Roboto, Helvetica, Arial, sans-serif`); `ui-monospace, "SF Mono", Menlo, monospace` for commands.
- One CSS file (target ≤ 8 KB), no framework, no preprocessor. Max content width ~72 ch; responsive down to 360 px; feature grid collapses to one column.
- Copy button: ~20 lines of inline JS at the end of `layout.html`, only runs if `navigator.clipboard` exists.

## Build (`site/build.mjs`)
Inputs: `site/site.json`, `site/layout.html`, `site/pages/*.html`, `site/static/**`, `docs/screenshots/*.png`, env `GITHUB_TOKEN` (optional; raises the API rate limit and is always present in Actions).

Steps:
1. `fetchReleases()` — `GET https://api.github.com/repos/{repo}/releases?per_page=100`, `Accept: application/vnd.github+json`, `Authorization: Bearer $GITHUB_TOKEN` when set. Drop drafts. **Latest** = first release with `prerelease === false`. Error (non-2xx, network, zero releases) → throw; the build must fail rather than ship blank version numbers.
2. `renderMarkdown(text)` — `POST https://api.github.com/markdown` with `{ text, mode: "gfm", context: repo }` → HTML string. Empty body → `<p>No notes for this release.</p>`.
3. Build a `context` object: `{ site, latest: { version, tag, date, dmg: {url, size, sha256Url}, htmlUrl }, releases: [...] }`.
4. Render each page: substitute `{{key}}`/`{{a.b.c}}` placeholders (HTML-escaped by default; `{{{raw}}}` for pre-rendered HTML like `{{{releases}}}` and `{{{jsonld}}}`), wrap in `layout.html`, then **assert no `{{` remains** in any output file.
5. Write `_site/index.html`, `_site/releases/index.html`, `_site/404.html`, `_site/sitemap.xml`, `_site/llms.txt`, `_site/.nojekyll`; copy `static/**` to `_site/`; copy screenshots to `_site/assets/`.
6. Print a one-line summary (latest version, page count, byte sizes).

Pure, unit-tested functions: `render(template, context)` (substitution + escaping + missing-key error), `pickLatest(releases)`, `releaseToHtml(release, root)`, `buildJsonLd(context, page)`, `buildSitemap(context)`, `buildLlmsTxt(context)`, `assertNoPlaceholders(html)`, `formatBytes(n)`, `rootFor(pagePath)`. Network calls (`fetchReleases`, `renderMarkdown`) are passed in as parameters so tests run offline with fixtures.

Local preview: `node site/build.mjs && python3 -m http.server -d _site 8080` → `http://localhost:8080/`.

## Deploy (`.github/workflows/pages.yml`)
```yaml
on:
  push:            { branches: [main], paths: [site/**, docs/screenshots/**, .github/workflows/pages.yml] }
  workflow_run:    { workflows: [Release], types: [completed] }
  release:         { types: [published] }
  workflow_dispatch:
permissions: { contents: read, pages: write, id-token: write }
concurrency: { group: pages, cancel-in-progress: false }
jobs:
  build:  ubuntu-latest → checkout → setup-node (22) → node --test site/ → node site/build.mjs (GITHUB_TOKEN) → upload-pages-artifact (_site)
          if: github.event_name != 'workflow_run' || github.event.workflow_run.conclusion == 'success'
  deploy: needs build → environment github-pages → actions/deploy-pages
```
- `workflow_run` on **Release** is the trigger that actually keeps the site current: the Release workflow creates the GitHub Release with `GITHUB_TOKEN`, and GitHub does not fire `release:` events for actions taken with that token. `release: published` stays for releases made by hand in the UI. `release.yml` is not modified.
- A Release dry run (`workflow_dispatch`) also completes successfully and rebuilds the site; that's harmless (the build reads the current releases).

## Repo-side setup (one-time)
- Enable Pages with source **GitHub Actions**: `gh api -X POST repos/jeffcaldwellca/portDrop/pages -f build_type=workflow` (or via Settings → Pages).
- `gh repo edit --homepage https://www.jeffcaldwell.ca/portDrop/`.
- README: add a **Website** link/badge in the header block; keep everything else.
- `.gitignore`: add `_site/`.
- Run `Scripts/make-site-icons.sh` and `Scripts/make-og-image.swift` once and commit their outputs.

## Testing & verification
- Unit: `node --test site/build.test.mjs` for the pure functions above (fixtures for two releases incl. a draft and a pre-release; markdown renderer stub).
- Build gate: the placeholder assertion and non-empty release list make a broken build fail in CI, never a broken page.
- Manual before declaring done: open the live URL in both colour schemes; Lighthouse (performance/accessibility/best-practices/SEO — target 100 each); Google Rich Results Test on `/` (SoftwareApplication + FAQPage detected, no errors); an OG preview check; confirm `/portDrop/sitemap.xml`, `/robots.txt`, `/llms.txt`, `/404` respond; confirm the copy button works and degrades without JS.
- After the next real release: confirm the Release workflow's completion triggers `pages.yml` and the new version appears on `/` and `/releases/`.

## Out of scope
- Custom domain, analytics, i18n, blog/news, a documentation subsite, screenshots of the menu bar itself (can't be captured headlessly — see README's snapshot mode), search, and any change to the app or to `release.yml`.
