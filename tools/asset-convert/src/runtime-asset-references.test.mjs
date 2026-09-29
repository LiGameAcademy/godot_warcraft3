import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { collectRuntimeAssetReferences, modelVersionCandidates } from './runtime-asset-references.js';

test('script literal candidates preserve source lines, ignore comments and separate interpolation', t => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'runtime-references-'));
  t.after(() => fs.rmSync(root, {recursive: true, force: true}));
  fs.writeFileSync(path.join(root, 'sample.gd'), [
    '# "Units/Ignored.mdx"',
    'const FX = "Abilities/Spell.mdl" # "Units/Ignored2.mdx"',
    'const RALLY = "UI/Feedback/Rally.glb"',
    'const DYNAMIC = "Units/%s.mdx"',
    'const LOCAL = "res://scenes/test.scn"',
  ].join('\n'));
  const result = collectRuntimeAssetReferences([root]);
  assert.deepEqual(result.refs.map(row => row.logical), ['Abilities/Spell.mdl', 'UI/Feedback/Rally.mdx']);
  assert.equal(result.refs[0].reason.line, 2);
  assert.equal(result.dynamic.length, 1);
  assert.ok(result.inputs[0].sha256);
  assert.deepEqual(collectRuntimeAssetReferences([root]), result);
});
test('model edition rules retain base fallback and do not append the version twice', () => {
  assert.deepEqual(modelVersionCandidates('Units/Priest.mdl', 2), ['Units/Priest_V1.mdx', 'Units/Priest.mdl']);
  assert.deepEqual(modelVersionCandidates('Units/Priest.mdx', 2, 'roc'), ['Units/Priest.mdx']);
  assert.deepEqual(modelVersionCandidates('Units/Priest_V1.mdx', 2), ['Units/Priest_V1.mdx']);
  assert.deepEqual(modelVersionCandidates('Units/Priest.mdx', 0), ['Units/Priest.mdx']);
  assert.throws(() => modelVersionCandidates('Units/Priest.mdx', 2, 'typo'), /Unsupported/);
});
