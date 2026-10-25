// Explicit manual release command; building does not upload anything.
import { spawnSync } from 'node:child_process';
import { access } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
const root = dirname(fileURLToPath(import.meta.url));
const bucket = process.env.HOWDOEY_R2_BUCKET;
if (!bucket || !/^[a-z0-9][a-z0-9-]+$/.test(bucket)) throw new Error('Set HOWDOEY_R2_BUCKET to an existing R2 bucket.');
for (const [key, type] of [['media/email-demo.mp4','video/mp4'], ['media/community-demo.mp4','video/mp4'], ['downloads/Howdoey-macOS-arm64.zip','application/zip'], ['downloads/SHA256SUMS.txt','text/plain']]) {
  const file = join(root, '.r2-staging', key);
  try { await access(file); } catch { if (key.startsWith('downloads/')) continue; throw new Error(`Build first: missing ${key}`); }
  const args = ['wrangler', 'r2', 'object', 'put', `${bucket}/${key}`, '--file', file, '--content-type', type, '--remote'];
  if (type === 'application/zip') args.push('--content-disposition', 'attachment; filename="Howdoey-macOS-arm64.zip"');
  const result = spawnSync('npx', args, { stdio: 'inherit', cwd: root });
  if (result.error || result.status !== 0) throw new Error(`Upload failed: ${key}`);
}
