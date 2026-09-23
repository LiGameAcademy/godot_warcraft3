"""Static ownership gate for canonical source (not generated app addons)."""
import pathlib,re,json,sys,subprocess
ROOT=pathlib.Path(__file__).resolve().parents[2]

def main():
    files=[p for folder in ['packages','apps/game','apps/map_editor'] for p in (ROOT/folder).rglob('*.gd') if not any(x in p.relative_to(ROOT).parts for x in ['addons','.godot','assets','tests']) and not p.is_relative_to(ROOT/'apps/game/tools')]
    classes={};errors=[]
    for p in files:
        m=re.search(r'^class_name\s+(\w+)',p.read_text('utf-8-sig'),re.M)
        if m:
            if m[1] in classes:errors.append('Duplicate class '+m[1])
            classes[m[1]]=p.relative_to(ROOT).as_posix()
    forbidden={'foundation':['apps/','packages/content/','packages/map/','packages/gameplay/'],'content':['apps/','packages/map/','packages/gameplay/'],'map':['apps/','packages/gameplay/'],'gameplay':['apps/']}
    for p in files:
        rel=p.relative_to(ROOT).as_posix();text=p.read_text('utf-8-sig')
        if not rel.startswith('packages/'):continue
        package=rel.split('/')[1]
        src='\n'.join(x.split('#')[0] for x in text.splitlines());src=re.sub(r'"[^"\n]*"|\x27[^\x27\n]*\x27','',src)
        for c in set(re.findall(r'\b[A-Z]\w*\b',src)):
            if c in classes and any(classes[c].startswith(f) for f in forbidden[package]):errors.append(f'{rel}: {c} -> {classes[c]}')
        for target in re.findall(r'res://([^"\s]+\.g[ds])',text):
            if not target.startswith(('addons/','assets/')):errors.append(f'{rel}: application resource {target}')
    layout=json.loads((ROOT/'tools/workspace/source-layout.json').read_text())
    ignored=subprocess.run(['git','-C',str(ROOT),'check-ignore','--no-index','--stdin'],input='\n'.join(layout['moves'].values())+'\n',text=True,capture_output=True)
    if ignored.returncode not in (0,1):errors.append('Cannot check source ignore rules: '+ignored.stderr)
    errors.extend('Canonical source ignored by Git: '+p for p in ignored.stdout.splitlines())
    for old,new in layout['moves'].items():
        if (ROOT/old).is_file():errors.append('Old source remains: '+old)
        if not (ROOT/new).is_file():errors.append('Missing source: '+new)
    for app in ['game','map_editor']:
        manifest=ROOT/'apps'/app/'.workspace-sync.json'
        if manifest.exists():
            import hashlib
            for row in json.loads(manifest.read_text()):
                dest=ROOT/'apps'/app/row['path']
                if 'source' in row:
                    src=ROOT/row['source']
                    if not dest.exists() or dest.read_bytes()!=src.read_bytes():errors.append('Stale synchronized file: '+str(dest.relative_to(ROOT)))
                elif not dest.exists() or hashlib.sha256(dest.read_bytes()).hexdigest()!=row['sha256']:
                    errors.append('Invalid generated redirect: '+row['path'])
                if app=='map_editor' and any(x in row['path'] for x in ['rts_gameplay','godot_ability_system','/client/']):errors.append('Game dependency shipped to editor: '+row['path'])
    print(f'Layout: {len(files)} scripts, {len(layout["moves"])} moves, {len(errors)} violations')
    for e in errors:print(e)
    return bool(errors)
if __name__=='__main__':sys.exit(main())
