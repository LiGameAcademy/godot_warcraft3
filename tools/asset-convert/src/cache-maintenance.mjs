import fs from 'node:fs';
import {spawnSync} from 'node:child_process';
import path from 'node:path';
import {randomUUID, createHash} from 'node:crypto';
import {fileURLToPath} from 'node:url';
function processBirth(pid) {
  if (process.platform !== 'win32') return 'unknown';
  const executable = path.join(process.env.SystemRoot || 'C:/Windows', 'System32/WindowsPowerShell/v1.0/powershell.exe');
  const query = `[System.Diagnostics.Process]::GetProcessById(${pid}).StartTime.ToUniversalTime().Ticks.ToString()`;
  const result = spawnSync(executable, ['-NoLogo', '-NoProfile', '-NonInteractive', '-Command', query],
    {encoding: 'utf8', windowsHide: true, timeout: 5000});
  return result.status === 0 && !result.error ? result.stdout.trim() : 'unknown';
}
function alive(owner) {
  const pid = typeof owner === 'object' && owner ? owner.pid : owner;
  if (!Number.isInteger(pid) || pid <= 0) return true;
  try {process.kill(pid, 0);} catch (error) {return error.code !== 'ESRCH';}
  if (!owner?.birth || owner.birth === 'unknown') return true;
  const actual = processBirth(pid);
  return actual === 'unknown' || actual === owner.birth;
}
function inside(root, filename) {
  const target = path.resolve(filename);
  const relative = path.relative(root, target);
  if (!relative || relative === '..' || relative.startsWith('..' + path.sep) || path.isAbsolute(relative)) throw new Error('cache_path_outside_root');
  return target;
}
function read(filename) {return JSON.parse(fs.readFileSync(filename, 'utf8'));}
function walk(root, directory) {
  if (!fs.existsSync(directory)) return [];
  const result = [];
  for (const entry of fs.readdirSync(directory, {withFileTypes: true})) {
    const filename = inside(root, path.join(directory, entry.name));
    const info = fs.lstatSync(filename);
    if (info.isSymbolicLink()) throw new Error('cache_symlink_refused');
    if (info.isDirectory()) result.push(...walk(root, filename));
    else result.push({path: filename, bytes: info.size});
  }
  return result;
}
export function maintainCache(directory, {apply = false, budgetBytes = 8 * 1024 ** 3} = {}) {
  const requested = path.resolve(directory);
  if (fs.lstatSync(requested).isSymbolicLink()) throw new Error('cache_symlink_refused');
  const root = fs.realpathSync(requested);
  if (fs.existsSync(path.join(root, 'War3.mpq'))) throw new Error('cache_original_source_refused');
  const marker = read(path.join(root, '.asset-cache-v1'));
  if (marker.version !== 1 || marker.kind !== 'warcraft-derived-content') throw new Error('cache_marker_missing');
  const lock = path.join(root, '.import-lock');
  let acquired = false;
  if (fs.existsSync(lock)) {
    const owner = read(path.join(lock, 'owner.json'));
    if (alive(owner) || (owner.children || []).some(alive)) throw new Error('cache_busy');
    if (!owner.token || typeof owner.token !== 'string') throw new Error('cache_busy');
    const takeover = inside(root, path.join(root, '.takeover-' + createHash('sha256').update(owner.token).digest('hex')));
    fs.mkdirSync(takeover);
    try {
      if (read(path.join(lock, 'owner.json')).token !== owner.token) throw new Error('cache_busy');
      fs.renameSync(lock, inside(root, path.join(root, '.stale-lock-' + randomUUID())));
      fs.mkdirSync(lock);
      acquired = true;
    } finally {fs.rmdirSync(takeover);}
  }
  if (!acquired) fs.mkdirSync(lock); // Exclusive with the game, import workers and other cleanup runs.
  const token = randomUUID();
  fs.writeFileSync(path.join(lock, 'owner.json'), JSON.stringify({pid: process.pid, birth: processBirth(process.pid), token}));
  try {
    for (const filename of walk(root, path.join(root, '.readers'))) {
      if (alive(read(filename.path))) throw new Error('cache_reader_active');
    }
    const indexes = walk(root, path.join(root, 'indexes')).filter(row => row.path.endsWith('.json')).sort((a, b) => b.path.localeCompare(a.path));
    const records = indexes.map(row => ({...row, record: read(row.path)}));
    // A malformed index may hide live references. Fail closed rather than guessing.
    for (const {record} of records) {
      if (record.version !== 1 || !Array.isArray(record.results) || !record.results.length) throw new Error('cache_index_invalid');
    }
    const retained = records.slice(0, 2);
    const keep = new Set(retained.map(row => row.path.toLowerCase()));
    const contentRoots = [];
    for (const {record} of retained) {
      for (const result of record.results) {
        const scene = inside(root, result.output_scene);
        keep.add(scene.toLowerCase());
        keep.add(scene.replace(/\.scn$/i, '.json').toLowerCase());
      }
      if (record.content?.root) contentRoots.push(inside(root, record.content.root).toLowerCase() + path.sep);
    }
    const files = ['indexes', 'scenes', 'content', 'inputs', 'sessions'].flatMap(name => walk(root, path.join(root, name)));
    const remove = files.filter(row => !keep.has(row.path.toLowerCase()) && !contentRoots.some(prefix => row.path.toLowerCase().startsWith(prefix)));
    const totalBytes = files.reduce((sum, row) => sum + row.bytes, 0);
    const reclaimBytes = remove.reduce((sum, row) => sum + row.bytes, 0);
    const report = {root, apply, retainedIndexes: retained.map(row => row.path), totalBytes, reclaimBytes,
      remainingBytes: totalBytes - reclaimBytes, budgetBytes, overBudget: totalBytes - reclaimBytes > budgetBytes,
      remove: remove.map(row => path.relative(root, row.path))};
    if (apply) {
      for (const row of remove) {
        inside(root, row.path);
        if (fs.lstatSync(row.path).isSymbolicLink()) throw new Error('cache_symlink_refused');
        fs.unlinkSync(row.path);
      }
      fs.appendFileSync(path.join(root, 'maintenance.jsonl'), JSON.stringify({...report, timestamp: new Date().toISOString()}) + '\n');
    }
    return report;
  } finally {
    if (read(path.join(lock, 'owner.json')).token === token) {
      fs.unlinkSync(path.join(lock, 'owner.json'));
      fs.rmdirSync(lock);
    }
  }
}
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  if (!process.argv[2]) throw new Error('Provide the derived cache directory');
  console.log(JSON.stringify(maintainCache(process.argv[2], {apply: process.argv.includes('--apply')}), null, 2));
}
