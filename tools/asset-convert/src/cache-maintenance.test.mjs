import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import {maintainCache} from './cache-maintenance.mjs';
const root = fs.mkdtempSync(path.join(os.tmpdir(), 'wc3-maintenance-'));
function write(relative, data) {
 const filename = path.join(root, relative);fs.mkdirSync(path.dirname(filename), {recursive: true});
 fs.writeFileSync(filename, typeof data === 'object' ? JSON.stringify(data) : data);return filename;
}
try {
 write('.asset-cache-v1', {version: 1, kind: 'warcraft-derived-content'});
 for (const n of [1, 2, 3]) {
  const scene = write(`scenes/${n}.scn`, 'scene-' + n);write(`scenes/${n}.json`, 'record');
  const content = path.join(root, 'content', String(n));write(`content/${n}/map.json`, 'map');
  write(`indexes/000${n}.json`, {version: 1, results: [{output_scene: scene}], content: {root: content}});
 }
 write('inputs/old/model.ir.json', 'regenerable');write('sessions/cancelled/task.json', 'unfinished');
 const dry = maintainCache(root);
 assert.equal(dry.retainedIndexes.length, 2);assert.ok(dry.reclaimBytes > 0);
 assert.ok(fs.existsSync(path.join(root, 'scenes/1.scn')));
 assert.ok(!dry.remove.includes('scenes' + path.sep + '3.scn'));
 if (process.platform === 'win32') {
  write('.readers/reused.json', {pid: process.pid, birth: '0'});
  assert.equal(maintainCache(root).apply, false);
  fs.unlinkSync(path.join(root, '.readers/reused.json'));
 }
 write('.readers/live.json', {pid: process.pid});
 assert.throws(() => maintainCache(root, {apply: true}), /reader_active/);
 fs.unlinkSync(path.join(root, '.readers/live.json'));
 write('.import-lock/owner.json', {pid: process.pid, token: 'other'});
 assert.throws(() => maintainCache(root), /cache_busy/);
 fs.unlinkSync(path.join(root, '.import-lock/owner.json'));fs.rmdirSync(path.join(root, '.import-lock'));
 const applied = maintainCache(root, {apply: true, budgetBytes: 1});
 assert.equal(applied.overBudget, true);assert.equal(fs.existsSync(path.join(root, 'scenes/1.scn')), false);
 for (const n of [2, 3]) {assert.ok(fs.existsSync(path.join(root, `scenes/${n}.scn`)));assert.ok(fs.existsSync(path.join(root, `content/${n}/map.json`)));}
 assert.equal(maintainCache(root).reclaimBytes, 0);
 write('indexes/0004.json', 'broken');
 assert.throws(() => maintainCache(root, {apply: true}));
 assert.ok(fs.existsSync(path.join(root, 'scenes/3.scn')));
 write('War3.mpq', 'original archive marker');
 assert.throws(() => maintainCache(root, {apply: true}), /original_source_refused/);
 console.log('PASS: dry run, keep two generations, protected readers/writer, budget reporting, malformed-index refusal');
} finally {
 assert.equal(path.dirname(path.resolve(root)), path.resolve(os.tmpdir()));
 fs.rmSync(root, {recursive: true, force: true});
}
