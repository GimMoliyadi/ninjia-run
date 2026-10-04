import { readdirSync } from 'node:fs';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../tests/', import.meta.url));
const files = readdirSync(root)
  .filter((name) => name.endsWith('.test.js'))
  .sort()
  .map((name) => join(root, name));

if (!files.length) {
  console.error('No test files found in tests/.');
  process.exit(1);
}

const result = spawnSync(process.execPath, ['--test', ...files], { stdio: 'inherit' });
process.exit(result.status ?? 1);
