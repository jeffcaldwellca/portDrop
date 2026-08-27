export function absolute(site, path) {
  return new URL(path, site.baseUrl).href;
}

function softwareApplication(site, latest, first) {
  return {
    '@type': 'SoftwareApplication',
    name: site.name,
    description: site.description,
    url: site.baseUrl,
    applicationCategory: 'DeveloperApplication',
    operatingSystem: 'macOS 26 or later',
    softwareVersion: latest.version,
    datePublished: first.date,
    dateModified: latest.date,
    downloadUrl: latest.dmg.url,
    installUrl: site.homebrew.caskUrl,
    releaseNotes: absolute(site, 'releases/'),
    screenshot: absolute(site, 'assets/panel-light.png'),
    image: absolute(site, 'icon-512.png'),
    fileSize: `${Math.round(latest.dmg.size / 1024)} KB`,
    offers: { '@type': 'Offer', price: '0', priceCurrency: 'USD' },
    author: { '@type': 'Person', name: site.author.name, url: site.author.url },
  };
}

export function buildJsonLd({ site, latest, first, page, faq = [] }) {
  const app = softwareApplication(site, latest, first);
  const graph = [];
  if (page === 'home') {
    graph.push({ '@type': 'WebSite', name: site.name, url: site.baseUrl }, app);
    if (faq.length) {
      graph.push({
        '@type': 'FAQPage',
        mainEntity: faq.map(({ question, answer }) => ({
          '@type': 'Question', name: question, acceptedAnswer: { '@type': 'Answer', text: answer },
        })),
      });
    }
  } else if (page === 'releases') {
    graph.push({
      '@type': 'BreadcrumbList',
      itemListElement: [
        { '@type': 'ListItem', position: 1, name: 'Home', item: site.baseUrl },
        { '@type': 'ListItem', position: 2, name: 'Releases', item: absolute(site, 'releases/') },
      ],
    }, app);
  } else {
    throw new Error(`Unknown JSON-LD page: ${page}`);
  }
  // "<\/" keeps a "</script>" inside a string from ending the <script> element; JSON.parse reads it back unchanged.
  return JSON.stringify({ '@context': 'https://schema.org', '@graph': graph }).replace(/<\//g, '<\\/');
}

export function buildSitemap(site, pages) {
  const urls = pages.map(({ path, lastmod }) => `  <url>\n    <loc>${absolute(site, path)}</loc>\n    <lastmod>${lastmod}</lastmod>\n  </url>`).join('\n');
  return `<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n${urls}\n</urlset>\n`;
}

export function buildRobots(site) {
  return `User-agent: *\nAllow: /\n\nSitemap: ${absolute(site, 'sitemap.xml')}\n`;
}

export function buildLlmsTxt(site, latest) {
  return `# ${site.name}

> ${site.tagline}

${site.description}

- Website: ${site.baseUrl}
- Latest version: ${latest.version} (${latest.dateLabel})
- Download (DMG, signed and notarized): ${latest.dmg.url}
- SHA-256 checksum: ${latest.sha256Url}
- Homebrew: \`${site.homebrew.command}\`
- Requires: ${site.minimumOS} or later
- Source code and README: ${site.repoUrl}
- Releases and changelog: ${absolute(site, 'releases/')}
- Report an issue: ${site.issuesUrl}
- Author: ${site.author.name} (${site.author.url})

## What it does

- Lists every process listening on a local TCP port, live: \`lsof\` is polled every 2 seconds while the panel is open and every 10 seconds in the background.
- Shows the owning app's real icon, name, user, and PID next to the port number.
- Detects HTTP, HTTPS, SSH, FTP, PostgreSQL, MySQL, Redis, MongoDB, VNC, SMB, and AFP by process name and well-known port, and probes unknown ports with an HTTP HEAD request so web servers get a clickable link.
- Open launches the service URL in its default handler. Kill is two-step (click, then Confirm) and sends SIGTERM; holding Option sends SIGKILL. Killing another user's or root's process uses the standard macOS administrator dialog.
- Search by port, process, user, or protocol; right-click for Copy URL / PID / host:port, Reveal in Finder, Kill, and Force Kill.
- Menu-bar badge with the number of listening ports, optional notification when a new port starts listening, Launch at Login.
- Listening TCP ports only: no UDP, no outbound connections.

## Privacy

No analytics, telemetry, or accounts. The only network traffic is the local HTTP probe to 127.0.0.1 / ::1 and a once-a-day update check (Sparkle), which can be turned off. The website sets no cookies and runs no analytics.
`;
}
