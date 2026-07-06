#!/usr/bin/env node
/**
 * validate-catalog.js
 *
 * Static validation of workflow-catalog.json and workflows/ directory.
 * Run in CI as a fast pre-gate before the live integration test.
 *
 * Exit codes: 0 = all OK, 1 = one or more errors
 */

'use strict';

const fs   = require('fs');
const path = require('path');

const ROOT          = path.join(__dirname, '..');
const WORKFLOWS_DIR = path.join(ROOT, 'workflows');
const CATALOG_FILE  = path.join(ROOT, 'workflow-catalog.json');
const REQUIRED_CATALOG_FIELDS = ['id', 'name', 'source_repo', 'webhook_path', 'file'];

let errors = 0;
const fail = msg => { console.error(`  ✗ ${msg}`); errors++; };
const pass = msg => { console.log(`  ✓ ${msg}`); };
const section = title => console.log(`\n── ${title} ${'─'.repeat(Math.max(0, 50 - title.length))}\n`);

// ── Load files ──────────────────────────────────────────────────────────────
let catalog;
try {
  catalog = JSON.parse(fs.readFileSync(CATALOG_FILE, 'utf8'));
} catch (e) {
  console.error(`\nFATAL: Could not parse workflow-catalog.json — ${e.message}\n`);
  process.exit(1);
}

const entries      = catalog.workflows || [];
const workflowFiles = fs.readdirSync(WORKFLOWS_DIR).filter(f => f.endsWith('.json'));

console.log(`\nCatalog: ${entries.length} entr${entries.length === 1 ? 'y' : 'ies'}`);
console.log(`Files:   ${workflowFiles.length} workflow JSON file(s) in workflows/\n`);

// ── 1. Required catalog fields ───────────────────────────────────────────────
section('Required catalog fields');
entries.forEach(entry => {
  REQUIRED_CATALOG_FIELDS.forEach(field => {
    if (!entry[field]) fail(`${entry.id || '(no id)'}: missing required field "${field}"`);
    else                pass(`${entry.id}.${field} = "${entry[field]}"`);
  });
});

// ── 2. Every catalog entry → workflow file exists ────────────────────────────
section('Catalog entry → file exists');
entries.forEach(entry => {
  const filepath = path.join(ROOT, entry.file);
  if (!fs.existsSync(filepath)) fail(`${entry.id}: file not found — ${entry.file}`);
  else                          pass(`${entry.id} → ${entry.file}`);
});

// ── 3. Every workflow file → catalog entry exists ────────────────────────────
section('Workflow file → catalog entry exists');
const catalogFileBases = new Set(entries.map(e => path.basename(e.file)));
workflowFiles.forEach(file => {
  if (!catalogFileBases.has(file)) fail(`${file}: no catalog entry found`);
  else                             pass(file);
});

// ── 4. Unique workflow IDs ────────────────────────────────────────────────────
section('Unique workflow IDs');
const ids    = entries.map(e => e.id);
const dupIds = ids.filter((id, i) => ids.indexOf(id) !== i);
if (dupIds.length) fail(`Duplicate IDs detected: ${[...new Set(dupIds)].join(', ')}`);
else               pass('All IDs are unique');

// ── 5. Unique webhook paths ───────────────────────────────────────────────────
section('Unique webhook paths');
const webhookPaths    = entries.map(e => e.webhook_path);
const dupPaths        = webhookPaths.filter((p, i) => webhookPaths.indexOf(p) !== i);
if (dupPaths.length) fail(`Duplicate webhook paths: ${[...new Set(dupPaths)].join(', ')}`);
else                 pass('All webhook paths are unique');

// ── 6. Workflow JSON structure ────────────────────────────────────────────────
section('Workflow JSON structure');
workflowFiles.forEach(file => {
  const filepath = path.join(WORKFLOWS_DIR, file);
  let wf;
  try {
    wf = JSON.parse(fs.readFileSync(filepath, 'utf8'));
  } catch (e) {
    fail(`${file}: invalid JSON — ${e.message}`);
    return;
  }

  const fileErrors = [];
  if (!wf.id)                                             fileErrors.push('missing "id"');
  if (!wf.name)                                           fileErrors.push('missing "name"');
  if (!Array.isArray(wf.nodes) || wf.nodes.length === 0) fileErrors.push('"nodes" must be a non-empty array');
  if (wf.active !== true)                                 fileErrors.push('"active" must be true');
  if (!wf.connections || typeof wf.connections !== 'object') fileErrors.push('missing "connections"');

  if (fileErrors.length) fail(`${file}: ${fileErrors.join('; ')}`);
  else                   pass(`${file}: structure OK (id=${wf.id}, nodes=${wf.nodes.length})`);
});

// ── Summary ──────────────────────────────────────────────────────────────────
console.log('\n' + '─'.repeat(55));
if (errors > 0) {
  console.error(`\n✗ ${errors} error(s) found — merge blocked.\n`);
  process.exit(1);
} else {
  console.log(`\n✓ All catalog validations passed.\n`);
}
