import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { buildDevelopmentManifest } from './development-manifest.js';
import { atomicWriteBytesSync } from './atomic-write.js';

const repo = fileURLToPath(new URL('../../../', import.meta.url));
const options = {map: path.join(repo, 'assets/map-parsed/echoisles'), definitions: path.join(repo, 'assets/slk-exported'),
  source: path.join(repo, '.cache/wc3-assets'), seeds: ['hpea', 'htow'], results: []};
let output = path.join(repo, 'tools/asset-convert/tmp/development-manifest/echoisles.json');
for (let i = 2; i < process.argv.length; i++) {
  const flag = process.argv[i];
  const value = process.argv[++i];
  if (!value || value.startsWith('--')) throw new Error(`Missing value for ${flag}`);
  if (flag === '--out') output = path.resolve(value);
  else if (flag === '--worker-result') options.results.push(path.resolve(value));
  else if (flag === '--seeds') options.seeds = value.split(',').filter(Boolean);
  else if (['--map', '--definitions', '--source'].includes(flag)) options[flag.slice(2)] = path.resolve(value);
  else throw new Error(`Unknown option ${flag}`);
}
const manifest = buildDevelopmentManifest(options);
fs.mkdirSync(path.dirname(output), {recursive: true});
atomicWriteBytesSync(output, JSON.stringify(manifest, null, 2) + '\n');
console.log(JSON.stringify({output, ...manifest.summary, coverage_complete: manifest.coverage.complete}, null, 2));
