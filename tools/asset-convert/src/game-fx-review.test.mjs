import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
const repo = fileURLToPath(new URL('../../../', import.meta.url));
assert.ok(process.env.GODOT, 'Set GODOT to the engine executable');
const base = path.join(repo, 'tools/asset-convert/tmp');
const reports = fs.readdirSync(base).filter(name => name.startsWith('development-'))
  .map(name => path.join(base, name, 'report.json')).filter(file => fs.existsSync(file))
  .sort((a, b) => fs.statSync(b).mtimeMs - fs.statSync(a).mtimeMs);
assert.ok(reports.length, 'Run game-development-import.test.mjs first');
const report = JSON.parse(fs.readFileSync(reports[0]));
const indexes = path.join(report.cacheRoot, 'indexes');
const index = path.join(indexes, fs.readdirSync(indexes).filter(name => name.endsWith('.json')).sort().at(-1));
const output = path.join(base, 'game-fx-review');
fs.mkdirSync(output, {recursive: true});
function run(executable, args, name, timeout = 120000) {
  const child = spawnSync(executable, args, {cwd: repo, encoding: 'utf8', timeout});
  const log = (child.stdout || '') + (child.stderr || '');
  fs.writeFileSync(path.join(output, name + '.log'), log);
  assert.ifError(child.error);
  assert.equal(child.status, 0, log);
  assert.doesNotMatch(log, /SCRIPT ERROR|Parse Error|Compile Error/);
  return log;
}
run('python', ['tools/workspace/sync_packages.py', '--app', 'game'], 'sync');
run('python', ['-c', "import sys;sys.path.insert(0,'tools/workspace');from test_apps import prepare;prepare('game','integration/selftest_compiled_projectile_shell.tscn')"], 'prepare');
const log = run(process.env.GODOT.replace(/_console\.exe$/i, '.exe'), ['--path', path.join(repo, 'apps/game'),
  '--position', '-10000,-10000', '--rendering-method', 'gl_compatibility',
  'res://tests/integration/selftest_compiled_projectile_shell.tscn', '--', '--index', index, '--output', output], 'run');
assert.match(log, /PASS: actual projectile shell/);
for (const name of ['PriestMissile-flight', 'PriestMissile-impact', 'FireBallMissile-flight', 'FireBallMissile-impact', 'HeroArchMage-glow-oblique', 'HeroArchMage-glow-top']) {
  assert.ok(fs.statSync(path.join(output, name + '.png')).size > 1000);
}
fs.writeFileSync(path.join(output, 'source.json'), JSON.stringify({index, sourceReport: reports[0], visual: 'requires_original_game_comparison'}, null, 2));
console.log('PASS: moving gameplay projectile shell, cycles, impact and hero glow');
console.log('Report: ' + path.join(output, 'report.json'));
