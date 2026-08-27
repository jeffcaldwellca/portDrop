// Thin GitHub REST client. `fetchImpl` is injectable so the build can be tested offline.
const API = 'https://api.github.com';

function headers(token, extra = {}) {
  const h = {
    Accept: 'application/vnd.github+json',
    'X-GitHub-Api-Version': '2022-11-28',
    'User-Agent': 'portdrop-site-build',
    ...extra,
  };
  if (token) h.Authorization = `Bearer ${token}`;
  return h;
}

export async function fetchReleases(repo, token, fetchImpl = globalThis.fetch) {
  const res = await fetchImpl(`${API}/repos/${repo}/releases?per_page=100`, { headers: headers(token) });
  if (!res.ok) throw new Error(`GitHub releases request failed: ${res.status} ${res.statusText}`);
  const releases = await res.json();
  if (!Array.isArray(releases)) throw new Error('GitHub releases response was not a list');
  return releases;
}

// Renders release notes exactly as GitHub does (GFM, @mentions and #123 linked in the repo's context).
export async function renderMarkdown(text, repo, token, fetchImpl = globalThis.fetch) {
  if (!text || !text.trim()) return '';
  const res = await fetchImpl(`${API}/markdown`, {
    method: 'POST',
    headers: headers(token, { 'Content-Type': 'application/json' }),
    body: JSON.stringify({ text, mode: 'gfm', context: repo }),
  });
  if (!res.ok) throw new Error(`GitHub markdown request failed: ${res.status} ${res.statusText}`);
  return res.text();
}
