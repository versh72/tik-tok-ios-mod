#!/usr/bin/env node
/**
 * Serves Tools/web/ over the local network so the iPhone can open it.
 *
 * WHY THIS EXISTS
 * ---------------
 * Tapping an .html file in the iOS Files app opens a Quick Look preview,
 * which does not execute JavaScript. The page's buttons would be dead. Safari
 * will only run the script when the file is served over http(s).
 *
 * Options that all work, in order of least friction:
 *   1. this server + the iPhone on the same Wi-Fi   (no upload, no account)
 *   2. any static host, opened as a URL             (needs the phone on data)
 *
 * A random public host is NOT recommended: several of them set a
 * Content-Security-Policy whose connect-src does not include the probe targets,
 * which makes every probe report failure. This server sets no CSP at all,
 * precisely so the page behaves as written.
 *
 * Usage:  node Tools/serve-web.mjs [port]
 * Then open the printed URL in Safari on the iPhone.
 */

import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import { networkInterfaces } from 'node:os';
import { join, extname, normalize } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(fileURLToPath(new URL('.', import.meta.url)), 'web');
const PORT = Number(process.argv[2]) || 8080;

const TYPES = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
};

// Resolve the LAN address, not the loopback one — the phone cannot reach
// 127.0.0.1, it means the phone itself.
function lanAddresses() {
  const out = [];
  for (const list of Object.values(networkInterfaces())) {
    for (const net of list || []) {
      if (net.family === 'IPv4' && !net.internal) out.push(net.address);
    }
  }
  return out;
}

const server = createServer(async (req, res) => {
  const requested = decodeURIComponent((req.url || '/').split('?')[0]);
  const name = requested === '/' ? '/netdiag.html' : requested;

  // Contain every request inside ROOT. Without this, the server would happily
  // serve C:\Users\...\Documents to anything on the Wi-Fi.
  const resolved = normalize(join(ROOT, name));
  if (!resolved.startsWith(ROOT)) {
    res.writeHead(403).end('forbidden');
    return;
  }

  try {
    const body = await readFile(resolved);
    res.writeHead(200, {
      'Content-Type': TYPES[extname(resolved)] || 'application/octet-stream',
      'Cache-Control': 'no-store',
      // Deliberately no Content-Security-Policy. A host-provided CSP with a
      // fixed connect-src list silently breaks the probes, which is worse
      // than having no protection on a page that makes no authenticated
      // request and stores nothing.
    });
    res.end(body);
  } catch {
    res.writeHead(404).end('not found');
  }
});

server.listen(PORT, '0.0.0.0', () => {
  const ips = lanAddresses();
  console.log('\n  NetDiag is served from:\n');
  for (const ip of ips) console.log(`    http://${ip}:${PORT}/`);
  if (!ips.length) {
    console.log('    (no LAN interface found — is this machine on Wi-Fi?)');
  }
  console.log('\n  Open that address in Safari on the iPhone.');
  console.log('  Both devices must be on the SAME Wi-Fi.');
  console.log('  Stop with Ctrl+C.\n');
});