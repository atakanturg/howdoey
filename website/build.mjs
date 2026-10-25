import { mkdir, rm, cp, readFile, writeFile, stat } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
const root = dirname(fileURLToPath(import.meta.url));
const output = join(root, 'dist');
const stage = join(root, '.r2-staging');
const base = process.env.HOWDOEY_ASSETS_BASE_URL?.replace(/\/$/, '');
if (!base) throw new Error('Set HOWDOEY_ASSETS_BASE_URL to your public HTTPS R2 custom domain before building. See README.md.');
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
const archive = join(root, '../desktop/dist', filename);
const publiclyAvailable = process.env.HOWDOEY_PUBLIC_DOWNLOADS === 'true';
let sha256 = null, bytes = null;
try {
  const data = await readFile(archive); sha256 = createHash('sha256').update(data).digest('hex'); bytes = data.length;
  await cp(archive, join(stage, 'downloads', filename));
  await writeFile(join(stage, 'downloads/SHA256SUMS.txt'), `${sha256}  ${filename}\n`);
 } catch (error) {
  if (error.code !== 'ENOENT') throw error;
  // Git-connected Pages builds do not have a local macOS build directory.
  // Metadata identifies the separately uploaded R2 artifact.
  const release = JSON.parse(await readFile(join(root, 'release-metadata.json'), 'utf8'));
  if (release.filename !== filename || !/^[a-f0-9]{64}$/.test(release.sha256) || !Number.isSafeInteger(release.bytes) || release.bytes <= 0) throw new Error('Invalid release metadata');
  sha256 = release.sha256; bytes = release.bytes;
}
await writeFile(join(output, 'releases.json'), JSON.stringify({ available: publiclyAvailable && !!sha256, filename, path: `${base}/downloads/${filename}`, sha256, bytes, notarized: false, localModel: 'qwen3.5:2b', modelDownload: 'First launch, approximately 3 GB' }, null, 2));
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
console.log(`Pages output: ${output}\nR2 uploads: ${stage}\nPublic download enabled: ${publiclyAvailable}`);
