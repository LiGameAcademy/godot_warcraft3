import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {createHash} from 'node:crypto';

export function checkExportedCache({records, inputs, scratch, binary, release, project, editor, run}) {
  let checks = 0;
  const digest = file => createHash('sha256').update(fs.readFileSync(file)).digest('hex');
  function compile(record, {mode='--compile', status=0, executable=binary} = {}) {
    const child = run(executable, ['--headless','--',mode,record.task,record.resultPath], release, true);
    assert.equal(child.status, status, child.log);
    assert.doesNotMatch(child.log, /SCRIPT ERROR|ERROR:/);
    return JSON.parse(fs.readFileSync(record.resultPath));
  }
  function expect(record, status, reason, options) {
    const result = compile(record, options);
    assert.equal(result.cache.status, status);
    if (reason) assert.equal(result.cache.reason, reason);
    record.output_scene = result.output_scene;
    checks++;
    return result;
  }
  for (const record of records) {
    const before = digest(record.output_scene);
    const stamp = fs.statSync(record.output_scene).mtimeMs;
    expect(record,'hit','verified');
    assert.equal(digest(record.output_scene),before);
    assert.equal(fs.statSync(record.output_scene).mtimeMs,stamp);
  }
  const record = records.find(value => value.name === 'PriestMissile');
  const originalTask = fs.readFileSync(record.task);
  const task = JSON.parse(originalTask);
  const originalIr = fs.readFileSync(task.ir_path);
  const ir = JSON.parse(originalIr);
  ir.source.source_hash = 'changed source signature';
  fs.writeFileSync(task.ir_path, JSON.stringify(ir));
  expect(record,'rebuilt','signature_changed');
  fs.writeFileSync(task.ir_path,originalIr);
  expect(record,'rebuilt','signature_changed');
  const geometry = fs.readFileSync(task.geometry_path);
  const gltf = JSON.parse(geometry);
  gltf.extras = {cache_test:true};
  fs.writeFileSync(task.geometry_path,JSON.stringify(gltf));
  expect(record,'rebuilt','signature_changed');
  fs.writeFileSync(task.geometry_path,geometry);
  const texturePaths = ir.textures.source_payload.filter(entry => entry.uri).map(entry => path.resolve(path.dirname(task.ir_path),entry.uri));
  const texture = fs.readFileSync(texturePaths[0]);
  fs.copyFileSync(texturePaths[1],texturePaths[0]);
  expect(record,'rebuilt','signature_changed');
  fs.writeFileSync(texturePaths[0],texture);
  const source = path.join(inputs,'cache-source.txt');
  fs.writeFileSync(source,'source version one');
  task.source_path = source;
  fs.writeFileSync(record.task,JSON.stringify(task));
  expect(record,'rebuilt','signature_changed');
  fs.writeFileSync(source,'source version two');
  expect(record,'rebuilt','signature_changed');
  for (const [key,value] of [['rules_version','next rules'],['profile','enhanced'],['expected_signature','next signature']]) {
    task[key] = value;
    fs.writeFileSync(record.task,JSON.stringify(task));
    expect(record,'rebuilt','signature_changed');
  }
  const dependency = path.join(inputs,'cache-dependency.txt');
  fs.writeFileSync(dependency,'dependency one');
  task.dependencies = [dependency];
  fs.writeFileSync(record.task,JSON.stringify(task));
  expect(record,'rebuilt','signature_changed');
  fs.writeFileSync(dependency,'dependency two');
  expect(record,'rebuilt','signature_changed');
  fs.unlinkSync(dependency);
  const oldScene = record.output_scene;
  const oldHash = digest(oldScene);
  const missing = compile(record,{status:2});
  assert.equal(missing.diagnostics[0].code,'cache_dependency_missing');
  assert.equal(digest(oldScene),oldHash);
  checks++;
  fs.writeFileSync(record.task,originalTask);
  expect(record,'rebuilt','signature_changed');
  for (const mode of ['--fail-scene-commit','--fail-record-commit']) {
    const preserved = record.output_scene;
    const hash = digest(preserved);
    const changed = {...JSON.parse(originalTask),rules_version:mode};
    fs.writeFileSync(record.task,JSON.stringify(changed));
    const failed = compile(record,{mode,status:1});
    assert.equal(failed.ok,false);
    assert.equal(failed.diagnostics[0].code,mode === '--fail-scene-commit' ? 'cache_scene_replace_failed' : 'cache_record_replace_failed');
    assert.equal(digest(preserved),hash);
    fs.writeFileSync(record.task,originalTask);
    expect(record,'hit','verified');
    assert.ok(!fs.readdirSync(path.dirname(record.output_scene)).some(name => name.includes('.pending.')));
    checks++;
  }
  const preservedInputScene = record.output_scene;
  const inputSceneHash = digest(preservedInputScene);
  const inputBefore = fs.readFileSync(source);
  fs.writeFileSync(record.task,JSON.stringify({...JSON.parse(originalTask),source_path:source}));
  const changedDuringCompile = compile(record,{mode:'--change-input',status:1});
  assert.equal(changedDuringCompile.diagnostics[0].code,'cache_inputs_changed');
  assert.equal(digest(preservedInputScene),inputSceneHash);
  fs.writeFileSync(source,inputBefore);
  fs.writeFileSync(record.task,originalTask);
  expect(record,'hit','verified');
  checks++;
  fs.writeFileSync(record.output_scene,'corrupt scene');
  expect(record,'rebuilt','scene_corrupt');
  fs.unlinkSync(record.output_scene);
  expect(record,'rebuilt','scene_missing');
  const recordFile = () => record.output_scene.replace(/\.scn$/,'.json');
  fs.writeFileSync(recordFile(),'{broken json');
  expect(record,'rebuilt','record_invalid');
  const metadata = JSON.parse(fs.readFileSync(recordFile()));
  metadata.cache_version = 999;
  fs.writeFileSync(recordFile(),JSON.stringify(metadata));
  expect(record,'rebuilt','record_invalid');
  const wrongIdentity = JSON.parse(fs.readFileSync(recordFile()));
  wrongIdentity.result.asset_id = 'wrong identity';
  fs.writeFileSync(recordFile(),JSON.stringify(wrongIdentity));
  expect(record,'rebuilt','record_invalid');
  fs.writeFileSync(path.join(path.dirname(record.output_scene),'99999999999999999999.pending.scn'),'interrupted');
  expect(record,'hit','verified');
  const future = (BigInt(Date.now()) * 1000n + 10000000000n).toString().padStart(20,'0') + '-clock-test';
  const directory = path.dirname(record.output_scene);
  fs.copyFileSync(record.output_scene,path.join(directory,future+'.scn'));
  fs.copyFileSync(recordFile(),path.join(directory,future+'.json'));
  fs.writeFileSync(record.task,JSON.stringify({...JSON.parse(originalTask),rules_version:'clock rollback'}));
  expect(record,'rebuilt','signature_changed');
  assert.ok(path.basename(record.output_scene).localeCompare(future+'.scn') > 0);
  fs.writeFileSync(record.task,originalTask);
  expect(record,'rebuilt','signature_changed');
  // A real re-export tests compiler version and build-payload invalidation.
  const core = path.join(project,'import_scene_compiler.gd');
  const coreBytes = fs.readFileSync(core,'utf8');
  const build = path.join(project,'import_compiler.source');
  const buildBytes = fs.readFileSync(build);
  for (const mutation of ['version','build']) {
    if (mutation === 'version') fs.writeFileSync(core,coreBytes.replace('COMPILER_VERSION: String = "2"','COMPILER_VERSION: String = "3"'));
    else fs.writeFileSync(build,Buffer.concat([buildBytes,Buffer.from(' ')]));
    const executable = path.join(release,`runtime-import-${mutation}.exe`);
    const exported = run(editor,['--headless','--path',project,'--export-release','Windows Desktop',executable],project);
    assert.equal(exported.status,0,exported.log);
    expect(record,'rebuilt','signature_changed',{executable});
    fs.writeFileSync(core,coreBytes);
    fs.writeFileSync(build,buildBytes);
    expect(record,'rebuilt','signature_changed');
  }
  fs.unlinkSync(path.join(path.dirname(record.output_scene),'99999999999999999999.pending.scn'));
  expect(record,'hit','verified');
  console.log(`Exported cache PASS: ${checks} checks (hits, signatures, corruption, commit failures, restart)`);
  fs.writeFileSync(path.join(scratch,'cache-checks.json'),JSON.stringify({checks,passed:true},null,2));
}
