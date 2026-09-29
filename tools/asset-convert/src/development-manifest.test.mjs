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
    const options = {map: path.join(root, 'map'), definitions: path.join(root, 'defs'), source: path.join(root, 'source'), seeds: [], definitionProfile: 'candidates'};
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
    assert.deepEqual(report.missing_definitions, ['Units/AbilityBuffData.slk']);

    write('defs/Units/UnitAbilities.json', {records: [{unitAbilID: 'hfoo', abilList: 'Afoo'}]});
    write('defs/Units/AbilityData.json', {records: [{alias: 'Afoo', BuffID1: 'Bfoo'}]});
    write('source/Units/AbilityBuffData.slk', 'ID;PWXL;N;E\nB;X1;Y2\nC;X1;Y1;K"alias"\nC;X1;Y2;K"Bfoo"\nE\n');
    write('defs/Melee_V0/Units/HumanUnitFunc.txt', '[hfoo]\nMissileart=Missiles/Overlay.mdl\n//Art=UI/Comment.blp\nArt=UI/Icon.tga\n');
    write('source/UI/Icon.blp', 'fixture icon');
    write('source/Missiles/Overlay.mdx', 'malformed model');
    const supplemented = buildDevelopmentManifest(options);
    assert.equal(supplemented.missing_definitions.length, 0);
    assert.equal(supplemented.unresolved_references.length, 0);
    assert.ok(supplemented.objects.some(row => row.id === 'Bfoo'));
    assert.ok(supplemented.inputs.some(row => row.path.endsWith('AbilityBuffData.slk') && row.sha256));
    assert.ok(supplemented.assets.find(row => row.id === 'missiles/bolt'), 'base candidate retained');
    assert.equal(supplemented.assets.find(row => row.id === 'missiles/overlay').reasons[0].table,
      'Melee_V0/Units/HumanUnitFunc.txt');
    assert.equal(supplemented.definition_conflicts[0].object_id, 'hfoo');
    assert.equal(supplemented.definition_conflicts[0].previous.source, 'Units/HumanUnitFunc.txt');
    assert.ok(!supplemented.assets.some(row => row.logical_path.includes('Comment')));
    assert.equal(supplemented.assets.find(row => row.id === 'ui/icon.blp').reasons[0].requested_path, 'UI/Icon.tga');
    const baseOnly = buildDevelopmentManifest({...options, definitionProfile: 'base'});
    assert.ok(!baseOnly.assets.some(row => row.id === 'missiles/overlay'));
    const melee = buildDevelopmentManifest({...options, definitionProfile: 'melee_roc'});
    assert.ok(!melee.assets.some(row => row.id === 'missiles/bolt'), 'overridden model must leave effective scope');
    assert.ok(melee.assets.some(row => row.id === 'missiles/overlay'));
    assert.equal(melee.configuration.definition_profile, 'melee_roc');
    write('source/Units/AbilityBuffData.slk', 'invalid table');
    assert.throws(() => buildDevelopmentManifest(options), /Invalid definition table/);
    // Exported definitions are the configured authority when both formats exist.
    write('defs/Units/AbilityBuffData.json', {records: [{alias: 'Bother'}]});
    assert.ok(buildDevelopmentManifest(options).unresolved_references.some(row => row.target === 'Bfoo'));
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
