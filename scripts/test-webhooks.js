#!/usr/bin/env node
/**
 * test-webhooks.js
 *
 * Integration smoke test — POSTs to every registered webhook endpoint and
 * asserts HTTP 200. Reads webhook paths from workflow-catalog.json.
 *
 * Usage:
 *   node scripts/test-webhooks.js
 *
 * Environment:
 *   N8N_HOST  (default: localhost)
 *   N8N_PORT  (default: 5678)
 *
 * Exit codes: 0 = all passed, 1 = one or more failures
 */

'use strict';

const http = require('http');
const path = require('path');
const fs   = require('fs');

const N8N_HOST   = process.env.N8N_HOST || 'localhost';
const N8N_PORT   = parseInt(process.env.N8N_PORT || '5678', 10);
const CATALOG    = JSON.parse(
  fs.readFileSync(path.join(__dirname, '..', 'workflow-catalog.json'), 'utf8')
);

/**
 * POST a JSON body to a webhook path and resolve with { status, body }.
 */
function postWebhook(webhookPath) {
  return new Promise((resolve, reject) => {
    const bodyStr = JSON.stringify({ test: true, source: 'ci-smoke-test' });
    const options = {
      hostname : N8N_HOST,
      port     : N8N_PORT,
      path     : webhookPath,
      method   : 'POST',
      headers  : {
        'Content-Type'   : 'application/json',
        'Content-Length' : Buffer.byteLength(bodyStr),
      },
    };

    const req = http.request(options, res => {
      let body = '';
      res.on('data', chunk => { body += chunk; });
      res.on('end', () => resolve({ status: res.statusCode, body }));
    });

    req.on('error', reject);
    req.setTimeout(10_000, () => {
      req.destroy(new Error(`Timeout after 10s on ${webhookPath}`));
    });
    req.write(bodyStr);
    req.end();
  });
}

async function main() {
  const workflows = CATALOG.workflows || [];
  console.log(`\n── Webhook Smoke Tests — ${workflows.length} endpoint(s) ──────────────────\n`);
  console.log(`Target: http://${N8N_HOST}:${N8N_PORT}\n`);

  let passed = 0;
  let failed = 0;

  for (const wf of workflows) {
    const url = `http://${N8N_HOST}:${N8N_PORT}${wf.webhook_path}`;
    try {
      const { status, body } = await postWebhook(wf.webhook_path);

      if (status === 200) {
        console.log(`  ✓ ${wf.id.padEnd(28)} ${wf.webhook_path}  →  HTTP ${status}`);
        passed++;
      } else {
        console.error(`  ✗ ${wf.id.padEnd(28)} ${wf.webhook_path}  →  HTTP ${status} (expected 200)`);
        const preview = body.replace(/\s+/g, ' ').substring(0, 120);
        console.error(`    Response preview: ${preview}`);
        failed++;
      }
    } catch (err) {
      console.error(`  ✗ ${wf.id.padEnd(28)} ${wf.webhook_path}  →  ERROR: ${err.message}`);
      failed++;
    }
  }

  console.log('\n' + '─'.repeat(55));
  if (failed > 0) {
    console.error(`\n✗ ${failed} webhook(s) failed, ${passed} passed — merge blocked.\n`);
    process.exit(1);
  } else {
    console.log(`\n✓ All ${passed} webhook(s) returned HTTP 200.\n`);
  }
}

main();
