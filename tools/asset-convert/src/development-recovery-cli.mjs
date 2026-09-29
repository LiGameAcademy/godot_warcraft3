import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { detectClassicMpqs } from '../../mpq-extract/src/detect.js';
import { extractMpqs } from '../../mpq-extract/src/extract.js';
import { buildDevelopmentManifest } from './development-manifest.js';
import { recoverDevelopmentSources } from './development-recovery.js';
import { atomicWriteBytesSync } from './atomic-write.js';

const repo = fileURLToPath(new URL('../../../', import.meta.url));
const options = {map: path.join(repo, 'assets/map-parsed/echoisles'), definitions: path.join(repo, 'assets/slk-exported'),
  source: path.join(repo, '.cache/wc3-assets'), seeds: ['hpea', 'htow'], results: []};
let gameDir = '';
let output = path.join(repo, 'tools/asset-convert/tmp/development-manifest/recovery.json');
let extractionManifest = path.join(repo, '.cache/development-extraction-manifest.json');
for (let i = 2; i < process.argv.length; i++) {
  const flag = process.argv[i];
  const value = process.argv[++i];
  if (!value || value.startsWith('--')) throw new Error(`Missing value for ${flag}`);
  if (flag === '--game-dir') gameDir = path.resolve(value);
  else if (flag === '--out') output = path.resolve(value);
  else if (flag === '--extraction-manifest') extractionManifest = path.resolve(value);
  else if (flag === '--worker-result') options.results.push(path.resolve(value));
  else if (flag === '--definition-profile') options.definitionProfile = value;
  else if (flag === '--seeds') options.seeds = value.split(',').filter(Boolean);
  else if (['--map', '--definitions', '--source'].includes(flag)) options[flag.slice(2)] = path.resolve(value);
  else throw new Error(`Unknown option ${flag}`);
}
if (!gameDir) throw new Error('--game-dir is required');
const mpqs = detectClassicMpqs(gameDir);
const result = recoverDevelopmentSources({
  build: () => buildDevelopmentManifest(options),
  extract: include => extractMpqs({mpqs, gameDir, outDir: options.source, manifestPath: extractionManifest,
    force: false, include, exclude: []}),
});
atomicWriteBytesSync(output, JSON.stringify({game_dir: gameDir, archives: mpqs,
  extraction_manifest: extractionManifest, ...result}, null, 2) + '\n');
console.log(JSON.stringify({output, status: result.status, passes: result.passes.length, ...result.manifest.summary}, null, 2));
if (result.status !== 'sources_available') process.exitCode = 1;
