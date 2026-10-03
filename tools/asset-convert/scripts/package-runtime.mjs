import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {createHash} from 'node:crypto';

const repo = fileURLToPath(new URL('../../../', import.meta.url));
/** Prepare a new Windows x64 sidecar directory; never overwrite an existing package. */
export async function packageRuntime(destination) {
  if (process.platform !== 'win32' || process.arch !== 'x64') throw new Error('Windows x64 runtime only');
  if (fs.existsSync(destination)) throw new Error('Runtime destination already exists');
  fs.mkdirSync(destination, {recursive: true});
  const pending = ['tools/asset-convert/src/runtime-source-import.mjs'];
  const seen = new Set();
  const copy = relative => {
    const target = path.join(destination, relative);
    fs.mkdirSync(path.dirname(target), {recursive: true});
    fs.copyFileSync(path.join(repo, relative), target);
  };
  while (pending.length) {
    const relative = pending.pop();
    if (seen.has(relative)) continue;
    if (!relative.startsWith('tools/') || relative.includes('..')) throw new Error('Source outside tools: ' + relative);
    seen.add(relative); copy(relative);
    const text = fs.readFileSync(path.join(repo, relative), 'utf8');
    for (const match of text.matchAll(/^import\s+(?:[^;]*?\sfrom\s*)?['"](\.[^'"]+)['"]/gm)) {
      pending.push(path.posix.normalize(path.posix.join(path.posix.dirname(relative), match[1])));
    }
  }
  for (const pkg of ['asset-convert', 'mpq-extract']) {
    copy(`tools/${pkg}/package.json`);
    fs.cpSync(path.join(repo, `tools/${pkg}/node_modules`), path.join(destination, `tools/${pkg}/node_modules`), {recursive: true});
  }
  copy('tools/mpq-extract/vendor/stormlib/StormLib.dll');
  fs.copyFileSync(process.execPath, path.join(destination, 'node.exe'));
  // License inputs are versioned and local: packaging/player import needs no network.
  const licenseRoot = path.join(repo, 'tools/asset-convert/vendor/runtime-licenses');
  for (const [filename, source] of [['NODE-LICENSE', `node-${process.version}.LICENSE`], ['STORMLIB-LICENSE', 'StormLib-v9.40.LICENSE']]) {
    fs.copyFileSync(path.join(licenseRoot, source), path.join(destination, filename));
  }
  const digest = file => createHash('sha256').update(fs.readFileSync(file)).digest('hex');
  const hashes = fs.readdirSync(destination, {recursive: true})
    .filter(relative => fs.statSync(path.join(destination, relative)).isFile())
    .sort().map(relative => [relative.replaceAll('\\', '/'), digest(path.join(destination, relative))]);
  fs.writeFileSync(path.join(destination, 'runtime-bundle.json'), JSON.stringify({version: 1, platform: 'win32-x64', node: process.version, hashes}, null, 2));
  return destination;
}
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  if (!process.argv[2]) throw new Error('Provide destination');
  console.log(await packageRuntime(path.resolve(process.argv[2])));
}
