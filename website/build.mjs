import { mkdir, rm, cp, readFile, writeFile, stat } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
const root = dirname(fileURLToPath(import.meta.url));
const output = join(root, 'dist');
const stage = join(root, '.r2-staging');
const configuredBase = process.env.HOWDOEY_ASSETS_BASE_URL?.replace(/\/$/, '');
// Initial Git-connected deployment can serve the already-public recordings from GitHub.
// Configure R2 for independently hosted release media and downloads.
const base = configuredBase || 'https://raw.githubusercontent.com/atakanturg/howdoey/main/website';
const url = new URL(base);
if (url.protocol !== 'https:' || url.username || url.password || url.search || url.hash) throw new Error('Assets base must be an HTTPS URL without credentials, query, or fragment.');
await rm(output, { recursive: true, force: true });
await rm(stage, { recursive: true, force: true });
await mkdir(output, { recursive: true });
await mkdir(join(stage, 'media'), { recursive: true });
await mkdir(join(stage, 'downloads'), { recursive: true });
await cp(join(root, 'assets'), join(output, 'assets'), { recursive: true });
for (const page of ['terms.html', 'privacy.html', '404.html', 'favicon.svg', 'apple-touch-icon.png', 'robots.txt', 'sitemap.xml', '_headers']) await cp(join(root, page), join(output, page));
let html = await readFile(join(root, 'howdoey.html'), 'utf8');
for (const filename of ['email-demo.mp4', 'community-demo.mp4']) {
  await cp(join(root, 'media', filename), join(stage, 'media', filename));
  html = html.replaceAll(`media/${filename}`, `${base}/media/${filename}`);
}
const isPreview = process.env.CF_PAGES === '1' && process.env.CF_PAGES_BRANCH && process.env.CF_PAGES_BRANCH !== (process.env.HOWDOEY_PRODUCTION_BRANCH || 'main');
if (isPreview) {
  html = html.replace('<meta name="robots" content="index,follow">', '<meta name="robots" content="noindex,nofollow">');
  await writeFile(join(output, 'robots.txt'), 'User-agent: *\nDisallow: /\n');
  const headers = await readFile(join(output, '_headers'), 'utf8');
  await writeFile(join(output, '_headers'), headers + '\n/*\n  X-Robots-Tag: noindex, nofollow\n');
}
await writeFile(join(output, 'index.html'), html);
const filename = 'Howdoey-macOS-arm64.zip';
// Publish the reviewed archive directly: it is below Cloudflare's per-file limit.
// The committed copy is available in clean Linux/Git-connected builds.
const archive = join(root, 'downloads', filename);
const data = await readFile(archive);
const sha256 = createHash('sha256').update(data).digest('hex');
const bytes = data.length;
const release = JSON.parse(await readFile(join(root, 'release-metadata.json'), 'utf8'));
if (release.filename !== filename || release.sha256 !== sha256 || release.bytes !== bytes) throw new Error('Download archive does not match release-metadata.json');
await mkdir(join(output, 'downloads'), { recursive: true });
await cp(archive, join(output, 'downloads', filename));
await cp(archive, join(stage, 'downloads', filename));
const checksums = `${sha256}  ${filename}\n`;
await writeFile(join(output, 'downloads/SHA256SUMS.txt'), checksums);
await writeFile(join(stage, 'downloads/SHA256SUMS.txt'), checksums);
const publiclyAvailable = process.env.HOWDOEY_PUBLIC_DOWNLOADS !== 'false';
await writeFile(join(output, 'releases.json'), JSON.stringify({ available: publiclyAvailable, filename, path: `/downloads/${filename}`, sha256, bytes, notarized: false, localModel: 'qwen3.5:2b', modelDownload: 'Automatic first-launch download and configuration, approximately 3 GB' }, null, 2));
// Pages rejects individual files above 25 MiB. Large artifacts belong in R2.
async function ensureSize(path) {
  const { readdir } = await import('node:fs/promises');
  for (const item of await readdir(path, { withFileTypes: true })) {
    const child = join(path, item.name);
    if (item.isDirectory()) await ensureSize(child);
    else if ((await stat(child)).size > 25 * 1024 * 1024) throw new Error(`Pages asset too large: ${child}`);
  }
}
await ensureSize(output);
console.log(`Static output: ${output}\nR2 uploads: ${stage}\nPublic download enabled: ${publiclyAvailable}`);

if (!configuredBase) console.log('Video source: public GitHub recordings. Configure HOWDOEY_ASSETS_BASE_URL for R2. The app archive is served directly with the website.');
