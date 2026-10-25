// Loopback preview only. Public hosting uses build.mjs and Cloudflare Pages/R2.
import http from 'node:http';
import { createReadStream, existsSync, statSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { join, dirname } from 'node:path';
const root = dirname(fileURLToPath(import.meta.url));
const dist = join(root, '../desktop/dist');
const filename = `Howdoey-macOS-${process.arch === 'arm64' ? 'arm64' : 'x86_64'}.zip`;
http.createServer((req, res) => {
  if (!['GET', 'HEAD'].includes(req.method)) { res.writeHead(405); res.end(); return; }
  const path = new URL(req.url, 'http://localhost').pathname;
  if (['/api/download', '/releases.json'].includes(path)) {
    const body = JSON.stringify({ available: existsSync(join(dist, filename)), filename, path: `/downloads/${filename}`, notarized: false });
    res.writeHead(200, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' }); res.end(req.method === 'HEAD' ? '' : body); return;
  }
  let file, type;
  if (['/', '/index.html', '/howdoey.html'].includes(path)) { file = join(root, 'howdoey.html'); type = 'text/html; charset=utf-8'; }
  else if (/^\/(terms|privacy|404)\.html$/.test(path)) { file = join(root, path.slice(1)); type = 'text/html; charset=utf-8'; }
  else if (['/favicon.svg', '/apple-touch-icon.png', '/robots.txt', '/sitemap.xml'].includes(path)) { file = join(root, path.slice(1)); type = ({ '/favicon.svg':'image/svg+xml', '/apple-touch-icon.png':'image/png', '/robots.txt':'text/plain', '/sitemap.xml':'application/xml' })[path]; }
  else if (/^\/assets\/howdoey\/(select|ask|guide-attach|guide-file|guide-done|download-open)\.png$/.test(path)) { file = join(root, path.slice(1)); type = 'image/png'; }
  else if (path === '/assets/howdoey/screenshots.js') { file = join(root, path.slice(1)); type = 'text/javascript; charset=utf-8'; }
  else if (/^\/media\/(email|community)-demo\.mp4$/.test(path)) { file = join(root, path.slice(1)); type = 'video/mp4'; }
  else if (path === `/downloads/${filename}`) { file = join(dist, filename); type = 'application/zip'; }
  else if (path === '/downloads/SHA256SUMS.txt') { file = join(dist, 'SHA256SUMS.txt'); type = 'text/plain'; }
  else { res.writeHead(404); res.end('Not found'); return; }
  if (!existsSync(file)) { res.writeHead(404); res.end('Unavailable'); return; }
  const size = statSync(file).size;
  const headers = { 'Content-Type': type, 'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff', 'Accept-Ranges': 'bytes' };
  if (type === 'application/zip') headers['Content-Disposition'] = `attachment; filename="${filename}"`;
  let start = 0, end = size - 1, status = 200;
  if (req.headers.range) {
    const match = /^bytes=(\d*)-(\d*)$/.exec(req.headers.range);
    if (!match || (!match[1] && !match[2])) { res.writeHead(416, { 'Content-Range': `bytes */${size}` }); res.end(); return; }
    if (!match[1]) start = Math.max(0, size - Number(match[2]));
    else { start = Number(match[1]); if (match[2]) end = Math.min(end, Number(match[2])); }
    if (start > end || start >= size) { res.writeHead(416, { 'Content-Range': `bytes */${size}` }); res.end(); return; }
    status = 206; headers['Content-Range'] = `bytes ${start}-${end}/${size}`;
  }
  headers['Content-Length'] = Math.max(0, end - start + 1);
  res.writeHead(status, headers);
  if (req.method === 'HEAD' || !size) res.end(); else createReadStream(file, { start, end }).pipe(res);
}).listen(8080, '127.0.0.1', () => console.log('Howdoey preview: http://127.0.0.1:8080'));
