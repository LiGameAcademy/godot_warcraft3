import assert from 'node:assert/strict';
import {ClassicMpqSource, safeLogical} from './classic-mpq-source.mjs';
import {prepareSourceImport, validateRequest} from './runtime-source-import.mjs';

for (const unsafe of ['/absolute.mdx', '../escape.mdx', 'Units/../escape.mdx', 'C:/file.mdx', 'Units//unit.mdx', 'Units/bad?.mdx']) assert.throws(() => safeLogical(unsafe));
assert.equal(safeLogical('Units\\Human\\Footman.mdx'), 'Units/Human/Footman.mdx');
assert.throws(() => validateRequest({request_version:1,models:[]}));
assert.throws(() => validateRequest({request_version:1,models:['unit.mdx','UNIT.mdl']}));
assert.throws(() => validateRequest({request_version:1,models:['unit.scn']}));
const closed = [];
const io = {openArchive: name => name, closeArchive: handle => closed.push(handle),
  hasFile: (handle,name) => name === 'Units\\unit.mdx',
  extractToBuffer: handle => Buffer.from(handle)};
const archives = [{canonicalName:'War3.mpq',absolutePath:'base'}, {canonicalName:'War3Patch.mpq',absolutePath:'patch'}];
const source = new ClassicMpqSource('unused', io, archives);
const entry = source.read('Units/unit.mdx');
assert.equal(entry.bytes.toString(),'patch');
assert.equal(entry.source_package,'War3Patch.mpq');
assert.equal(entry.overlay_priority,1);
assert.throws(() => source.read('missing.mdx'),/source_dependency_missing/);
source.close(); assert.deepEqual(closed,['base','patch']);
assert.throws(() => new ClassicMpqSource('unused',{...io,openArchive:name => {if(name==='patch') throw new Error('broken archive');return name;}},archives));
assert.equal(closed.at(-1),'base');
console.log('PASS: safe requests, exact-name patch priority, missing dependency, handles closed on failure');

await assert.rejects(prepareSourceImport({gameDir:'C:/game',outDir:'C:/game/cache',request:{request_version:1,models:['unit.mdx']}}),/source_output_inside_installation/);
