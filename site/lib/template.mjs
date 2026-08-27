// Minimal template engine: {{a.b}} inserts an HTML-escaped value, {{{a.b}}} inserts raw HTML.
// Missing values are errors — a page must never ship with a blank version number or link.

const ESCAPES = { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' };

export function escapeHtml(value) {
  return String(value).replace(/[&<>"']/g, (c) => ESCAPES[c]);
}

function lookup(ctx, path) {
  return path.split('.').reduce((obj, key) => (obj == null ? undefined : obj[key]), ctx);
}

export function render(template, ctx) {
  return template.replace(/\{\{\{\s*([\w.]+)\s*\}\}\}|\{\{\s*([\w.]+)\s*\}\}/g, (_, rawKey, escapedKey) => {
    const key = rawKey ?? escapedKey;
    const value = lookup(ctx, key);
    if (value === undefined || value === null) throw new Error(`Missing template value: ${key}`);
    return rawKey ? String(value) : escapeHtml(value);
  });
}

export function assertNoPlaceholders(html, name) {
  const outsideCode = html.replace(/<(code|pre)\b[^>]*>[\s\S]*?<\/\1>/gi, '');
  const leftover = outsideCode.match(/\{\{[^}]*\}\}/);
  if (leftover) throw new Error(`Unresolved placeholder ${leftover[0]} in ${name}`);
}
