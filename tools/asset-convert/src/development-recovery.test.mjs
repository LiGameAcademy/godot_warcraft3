import test from 'node:test';
import assert from 'node:assert/strict';
import { missingSourceNames, recoverDevelopmentSources } from './development-recovery.js';

const asset = (id, available = false) => ({id, logical_path: id, available, reasons: []});
test('exact source probes include MDX and MDL and reject globs and traversal', () => {
  assert.deepEqual(missingSourceNames({assets: [asset('Units/Foo.mdl'), asset('Textures/Done.blp', true)]}),
    ['Units/Foo.mdl', 'Units/Foo.mdx']);
  for (const name of ['../file.blp', '/file.blp', 'C:/file.blp', 'Units/*.mdx', 'Units/../file.blp']) {
    assert.throws(() => missingSourceNames({assets: [asset(name)]}), /Unsafe/);
  }
});
test('recovered models discover further dependencies while unavailable names are attempted once', () => {
  let round = 0;
  const requests = [];
  const result = recoverDevelopmentSources({
    build: () => ({assets: [asset('Model.mdx', round > 0), asset('Absent.blp'),
      ...(round > 0 ? [asset('Texture.blp', round > 1)] : [])]}),
    extract: names => { requests.push(names); round++; return {errors: 0}; },
  });
  assert.equal(result.status, 'unresolved_sources');
  assert.equal(requests.length, 2);
  assert.deepEqual(requests[1], ['Texture.blp']);
  assert.deepEqual(result.passes.map(row => row.recovered), [['Model.mdx'], ['Texture.blp']]);
});
test('extraction failures and bounded runs never report success', () => {
  const failed = recoverDevelopmentSources({build: () => ({assets: [asset('Missing.blp')]}), extract: () => ({errors: 1})});
  assert.equal(failed.status, 'extraction_failed');
  let round = 0;
  const limited = recoverDevelopmentSources({maxPasses: 1, build: () => ({assets: [asset(`New${round}.blp`)]}),
    extract: () => { round++; return {errors: 0}; }});
  assert.equal(limited.status, 'pass_limit');
  assert.equal(recoverDevelopmentSources({build: () => ({assets: []}), extract: () => assert.fail()}).status, 'sources_available');
});
