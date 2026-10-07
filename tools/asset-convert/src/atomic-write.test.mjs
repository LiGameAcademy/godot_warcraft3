import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {atomicWriteBytesSync} from './atomic-write.js';
const root = fs.mkdtempSync(path.join(os.tmpdir(), 'asset-rename-'));
const target = path.join(root, 'value.json');
const original = fs.renameSync;
try {
  fs.writeFileSync(target, 'old');
  let attempts = 0;
  fs.renameSync = (...args) => {
    attempts++;
    if (process.platform === 'win32' && attempts < 3) throw Object.assign(new Error('locked'), {code: 'EPERM'});
    return original(...args);
  };
  atomicWriteBytesSync(target, '{"complete":true}');
  assert.deepEqual(JSON.parse(fs.readFileSync(target)), {complete: true});
  assert.equal(attempts, process.platform === 'win32' ? 3 : 1);
  for (const code of ['EPERM', 'ENOENT']) {
    attempts = 0;
    fs.renameSync = () => {attempts++; throw Object.assign(new Error(code), {code});};
    assert.throws(() => atomicWriteBytesSync(target, 'new'), {code});
    assert.equal(attempts, code === 'EPERM' && process.platform === 'win32' ? 5 : 1);
    assert.equal(fs.readFileSync(target, 'utf8'), '{"complete":true}');
    assert.equal(fs.existsSync(target + '.tmp'), false);
  }
  console.log('PASS: transient rename retry, permanent failure preserves target and cleans temporary');
} finally {
  fs.renameSync = original;
  fs.rmSync(root, {recursive: true, force: true});
}
