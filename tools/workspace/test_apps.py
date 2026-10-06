"""Run repository-owned regressions inside each independent product resource root."""
import argparse, os, pathlib, re, subprocess, sys, json
ROOT=pathlib.Path(__file__).resolve().parents[2]
SUITES={
'asset_viewer':['unit/selftest_asset_audit_catalog.gd','integration/selftest_asset_viewer.gd'],
'game':[
'unit/selftest_spell_fx_compiler.tscn','unit/selftest_extended_sequence_controls.gd','unit/selftest_compiled_model_presentation.gd','unit/selftest_asset_import_guard.gd','unit/selftest_asset_import_snapshot.gd',
'unit/selftest_interaction_hotpaths.tscn','unit/selftest_portrait_warmup.tscn',
'unit/selftest_c_combat_damage.gd','unit/selftest_c_combat_projectile.gd','unit/selftest_combat_module.tscn','unit/selftest_attack_chase_facing.tscn','unit/selftest_building_attack_range.tscn','unit/selftest_hero_combat_stats.tscn','unit/selftest_command_request.tscn','unit/selftest_entity_behavior.tscn','unit/selftest_content_snapshot.tscn','unit/selftest_item_system.tscn','unit/selftest_gas_healing.tscn','unit/selftest_command_card_module.tscn','unit/selftest_path_debug_module.tscn','unit/selftest_group_move.gd','integration/selftest_module_bindings_game.tscn','integration/selftest_match_end_game.tscn'],
'map_editor':['unit/selftest_map_document.gd','unit/selftest_editor_map_file.gd','unit/selftest_editor_commands.gd','unit/selftest_editor_object_history.gd','unit/selftest_editor_map_import.gd','integration/selftest_editor_file_flow.tscn','integration/selftest_editor_preview.tscn','integration/selftest_editor_input_focus.tscn']}

def prepare(app, case):
    pending=['tests/'+case]; seen=set()
    while pending:
        rel=pending.pop()
        if rel in seen:continue
        seen.add(rel); src=ROOT/rel
        if not src.resolve().is_relative_to((ROOT/'tests').resolve()):
            raise ValueError('Test path outside tests: '+rel)
        if not src.is_file():raise FileNotFoundError(src)
        dest=ROOT/'apps'/app/rel
        if not dest.resolve().is_relative_to((ROOT/'apps'/app/'tests').resolve()):
            raise ValueError('Test destination outside generated tests: '+rel)
        dest.parent.mkdir(parents=True,exist_ok=True);dest.write_bytes(src.read_bytes())
        if src.suffix in {'.gd','.tscn'}:
            text=src.read_text('utf-8-sig')
            for dep in re.findall(r'res://(tests/[^"\s]+)',text):
                if (ROOT/dep).is_file():pending.append(dep)
            uid=rel+'.uid'
            if (ROOT/uid).is_file():pending.append(uid)
    # Fixture directories can be assembled at runtime, not just through preload.
    for fixture_root in ['tests/fixtures','content/samples']:
        for src in (ROOT/fixture_root).rglob('*'):
            if src.is_file():
                dst=ROOT/'apps'/app/src.relative_to(ROOT);dst.parent.mkdir(parents=True,exist_ok=True);dst.write_bytes(src.read_bytes())

def main():
    p=argparse.ArgumentParser();p.add_argument('--godot',required=True);p.add_argument('--app',choices=['all',*SUITES],default='all');p.add_argument('--case');a=p.parse_args()
    failures=[]; results=[]; logs=ROOT/'tmp/directory-regressions';logs.mkdir(parents=True,exist_ok=True)
    for app in SUITES if a.app=='all' else [a.app]:
        for case in [a.case] if a.case else SUITES[app]:
            prepare(app,case);log=logs/(app+'-'+pathlib.Path(case).stem+'.log')
            args=[a.godot,'--headless','--path',str(ROOT/'apps'/app),'--log-file',str(log)+'.engine']
            if case.endswith('.gd'):args+=['-s']
            args+=['res://tests/'+case]
            if 'match_end_game' in case:args+=['--','--restart']
            try:
                with log.open('wb') as f:r=subprocess.run(args,stdout=f,stderr=subprocess.STDOUT,timeout=240)
                text=log.read_text('utf-8',errors='replace')
                ok=r.returncode==0 and not re.search(r'SCRIPT ERROR|Parse Error|Failed to load script|\bFAIL\b',text) and bool(re.search(r'PASS|passed|selftest_\w+ OK',text,re.I))
                summary='; '.join(x for x in text.splitlines() if re.search(r'PASS|\bFAIL\b|checks',x))[-350:]
            except subprocess.TimeoutExpired:ok=False;summary='TIMEOUT'
            print(app,case,'PASS' if ok else 'FAIL',summary,flush=True)
            results.append({'app':app,'case':case,'passed':ok,'summary':summary})
            if not ok:failures.append(app+':'+case)
    (logs/'results.json').write_text(json.dumps(results,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print('Failures:',failures,flush=True);return bool(failures)
if __name__=='__main__':sys.exit(main())
