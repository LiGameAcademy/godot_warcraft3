import test from 'node:test';
import assert from 'node:assert/strict';
import { definitionRoots, mergeDefinitionLayers } from './definition-layers.js';

export const fixture = [
  {source: 'Units/HumanUnitFunc.txt', text: '\ufeff[hpea]\nBuilds=htow,hbar\nRequires=halt\nArt="Icons/Base.blp"\nTip="L1","L2"\n[Hpea]\nArt=Icons/Hero.blp'},
  {source: 'Custom_V1/Units/HumanUnitFunc.txt', text: '[hpea]\nbuilds=hfoo\nRequires=""\n//Art=Ignored.blp\n;Art=Ignored2.blp\nArt=Icons/New.blp'},
];
test('profiles select one family and edition, never silently mix custom and melee', () => {
  assert.deepEqual(definitionRoots(), ['']);
  assert.deepEqual(definitionRoots('custom_tft'), ['', 'Custom_V1/']);
  assert.deepEqual(definitionRoots('melee_tft'), ['', 'Melee_V1/']);
  assert.throws(() => definitionRoots('typo'), /Unknown/);
});
test('field winners inherit missing values, clear explicit empties, retain case-sensitive IDs and provenance', () => {
  const result = mergeDefinitionLayers(fixture);
  assert.equal(result.rows.hpea.builds, 'hfoo');
  assert.equal(result.rows.hpea.requires, '');
  assert.equal(result.rows.hpea.tip, '"L1","L2"');
  assert.equal(result.rows.Hpea.art, 'Icons/Hero.blp');
  assert.equal(result.origins.hpea.art, fixture[1].source);
  assert.equal(result.changes.length, 3);
});
