import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { buildDevelopmentManifest, assessCompilation } from './development-manifest.js';
import { hash } from './asset-audit.js';

test('map references are traceable, cyclic links terminate, MDL resolves case-insensitively and gaps remain explicit', () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'development-assets-'));
  const write = (file, value) => {
    const full = path.join(root, file);
    fs.mkdirSync(path.dirname(full), {recursive: true});
    fs.writeFileSync(full, typeof value === 'string' ? value : JSON.stringify(value));
  };
  try {
    write('map/units.json', {units: [{typeId: 'hfoo'}]});
    write('map/doodads.json', {doodads: [{id: 'LTlt', variation: 2}]});
    write('defs/Units/UnitUI.json', {records: [{unitUIID: 'hfoo', file: 'Units/Foo/Foo', fileVerFlags: 2}]});
    write('defs/Units/UnitAbilities.json', {records: []});
    write('defs/Units/UnitWeapons.json', {records: []});
    write('defs/Units/ItemData.json', {records: []});
    write('defs/Units/AbilityData.json', {records: []});
    write('defs/Units/DestructableData.json', {records: [{DestructableID: 'LTlt', file: 'Trees/Tree', numVar: 5}]});
    write('defs/Doodads/Doodads.json', {records: []});
    write('defs/Units/HumanUnitFunc.txt', '[hfoo]\nTrains=hbar\nMissileart=Missiles\\Bolt.mdl\n[hbar]\nTrains=hfoo\nArt=UI\\Missing.blp\n');
    write('source/units/foo/FOO_V1.mdx', 'malformed model');
    write('source/Trees/Tree2.mdx', 'malformed model');
    write('source/Missiles/Bolt.mdx', 'malformed model');
    const options = {map: path.join(root, 'map'), definitions: path.join(root, 'defs'), source: path.join(root, 'source'), seeds: []};
    const report = buildDevelopmentManifest(options);
    assert.equal(report.summary.objects, 3);
    assert.equal(report.summary.models, 3);
    assert.equal(report.summary.missing_sources, 1);
    assert.equal(report.coverage.complete, false);
    const model = report.assets.find(row => row.id === 'units/foo/foo_v1');
    assert.equal(model.assessment.technical, 'source_invalid');
    assert.equal(model.reasons[0].object_id, 'hfoo');
    assert.ok(report.assets.find(row => row.id === 'missiles/bolt').available);
    assert.deepEqual(buildDevelopmentManifest(options), report, 'unchanged inputs must produce deterministic output');
  } finally { fs.rmSync(root, {recursive: true, force: true}); }
});

test('compilation evidence rejects stale content, missing signatures and conflicting runs', () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'compile-evidence-'));
  try {
    const scene = path.join(root, 'model.scn');
    fs.writeFileSync(scene, 'scene bytes');
    const asset = {logical_path: 'Units/Foo.mdx', available: true, source_sha256: hash('source'), diagnostics: []};
    const result = {asset_id: 'units/foo', source_sha256: asset.source_sha256, ok: true,
      output_scene: scene, output_sha256: hash('scene bytes'), diagnostics: [{code: 'material_feature_pending'}]};
    assert.equal(assessCompilation(asset, []).technical, 'uncompiled');
    assert.equal(assessCompilation(asset, [{...result, source_sha256: ''}]).technical, 'stale_or_unverifiable');
    const state = assessCompilation(asset, [result]);
    assert.equal(state.technical, 'compiled_partial');
    assert.equal(state.fallback, true);
    assert.equal(state.deliverable, false);
    assert.equal(state.visual, 'unverified');
    assert.equal(assessCompilation(asset, [result, result]).technical, 'ambiguous_evidence');
    fs.writeFileSync(scene, 'changed scene');
    assert.equal(assessCompilation(asset, [result]).technical, 'stale_or_unverifiable');
  } finally { fs.rmSync(root, {recursive: true, force: true}); }
});
