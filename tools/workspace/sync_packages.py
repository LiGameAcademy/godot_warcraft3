"""Copy canonical packages into independent Godot applications without rewriting references."""
import argparse, hashlib, json, pathlib, shutil, subprocess
ROOT = pathlib.Path(__file__).resolve().parents[2]
PACKAGES = {"game": ("foundation", "content", "map", "gameplay"), "map_editor": ("foundation", "content", "map"), "asset_viewer": ("foundation", "content", "map")}

def safe_path(app, relative):
    relative = pathlib.Path(relative)
    if relative.parts[0] not in {'packages', 'addons', 'assets', 'tools', 'scripts', 'icon.svg'}:
        raise ValueError(f"Not a generated resource: {relative}")
    target = app / relative
    if not target.resolve().is_relative_to(app.resolve()):
        raise ValueError(f"Outside app: {target}")
    for p in (target, *target.parents):
        if p == app.parent: break
        if p.is_symlink() or p.is_junction(): raise ValueError(f"Link in generated path: {p}")
    return target

def _rmtree_generated(app, relative):
    target = safe_path(app, relative)
    if target.exists():
        for p in target.rglob('*'):
            safe_path(app, p.relative_to(app))
        shutil.rmtree(target)

def sync(name):
    app = ROOT / 'apps' / name
    manifest_path = app / '.workspace-sync.json'
    previous = json.loads(manifest_path.read_text()) if manifest_path.exists() else []
    sources = {}
    for package in PACKAGES[name]:
        base = ROOT / 'packages' / package
        for path in base.rglob('*'):
            if path.is_file() and path.suffix not in {'.md', '.import'}:
                sources[f'packages/{package}/{path.relative_to(base).as_posix()}'] = path
    # The locale directory has .gdignore: preserve raw runtime data outside it.
    for filename in ('editor_strings.csv', 'westring_name_sort_zh.json'):
        sources[f'packages/content/localization/{filename}.source'] = ROOT / 'packages/content/localization/locale' / filename
    plugins = ('godot_ability_system', 'panku_console') if name == 'game' else ()
    for plugin in plugins:
        base = ROOT / 'addons' / plugin
        # Godot plugin repos often nest the real addon at addons/<name>/ inside the repo.
        nested = base / 'addons' / plugin
        listed = subprocess.check_output(['git', '-C', str(base), 'ls-files', '-z']).decode().split('\0')
        for rel in filter(None, listed):
            src = base / rel
            if not src.is_file():
                continue
            if nested.is_dir():
                prefix = f'addons/{plugin}/'
                if not rel.startswith(prefix):
                    continue
                sources[f'addons/{plugin}/{rel[len(prefix):]}'] = src
            else:
                sources[f'addons/{plugin}/{rel}'] = src
    assets = subprocess.check_output(['git','-C',str(ROOT),'ls-files','-z','--','assets','icon.svg']).decode().split('\0')
    for rel in filter(None, assets):
        p = ROOT / rel
        if p.is_file() and p.suffix != '.import': sources[rel] = p
    # Shader files are runtime dependencies. Include local additions before their
    # first commit so a fresh app sync can validate them as well.
    shader_root = ROOT / 'assets' / 'shaders'
    if shader_root.exists():
        for p in shader_root.glob('*.gdshader'):
            if p.is_file(): sources[p.relative_to(ROOT).as_posix()] = p
    if name == 'game':
        for p in (ROOT / 'tools/godot').rglob('*'):
            if p.is_file(): sources[p.relative_to(ROOT).as_posix()] = p
        for p in (ROOT / 'tools/asset-convert/src').rglob('*'):
            if p.is_file() and p.suffix in {'.js', '.mjs'}:
                sources[p.relative_to(ROOT).as_posix()] = p
    # Binary scenes retain historical script paths. Godot .remap files redirect them
    # without duplicate scripts/class_names or rewriting users' converted assets.
    redirects = {}
    model_base = ROOT / 'packages/map/presentation/wc3_model'
    for source in model_base.glob('*.gd'):
        target = 'res://packages/map/presentation/wc3_model/' + source.name
        for old in ['scripts/presentation/wc3_model/', 'scripts/map/presentation/']:
            rel = old + source.name + '.remap'
            redirects[rel] = ('[remap]\npath=' + json.dumps(target) + '\n').encode()
    for row in previous:
        if row['path'] not in sources and row['path'] not in redirects:
            # Old manifests may still list addons/rts_* paths; allow cleanup.
            try:
                p = safe_path(app, row['path'])
            except ValueError:
                continue
            if p.is_file(): p.unlink()
    for legacy_name in ('rts_runtime', 'rts_foundation', 'rts_content', 'rts_map', 'rts_gameplay'):
        _rmtree_generated(app, f'addons/{legacy_name}')
    records = []
    for relative, source in sorted(sources.items()):
        target = safe_path(app, relative)
        target.parent.mkdir(parents=True, exist_ok=True)
        data = source.read_bytes()
        if not target.exists() or target.read_bytes() != data: target.write_bytes(data)
        records.append({'path':relative, 'source':source.relative_to(ROOT).as_posix(), 'sha256':hashlib.sha256(data).hexdigest()})
    for relative, data in sorted(redirects.items()):
        target = safe_path(app, relative)
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
        records.append({'path':relative, 'generated':'legacy_model_redirect', 'sha256':hashlib.sha256(data).hexdigest()})
    if name == 'game':
        tool_dir = app / 'tools/godot'
        payloads = ['import_billboard_pose.gd', 'import_ribbon_runtime.gd', 'import_particle_burst.gd']
        hashes = [[p.name, hashlib.sha256(p.read_bytes()).hexdigest()] for p in sorted(tool_dir.glob('import_*.gd'))]
        material = app / 'packages/map/presentation/wc3_model/wc3_pe2_material.gd'
        hashes.append(['presentation/wc3_model/wc3_pe2_material.gd', hashlib.sha256(material.read_bytes()).hexdigest()])
        for relative, data in [(f'tools/godot/{n}.source', (tool_dir / n).read_bytes()) for n in payloads] + [('tools/godot/import_compiler.source', json.dumps(hashes).encode())]:
            target = safe_path(app, relative)
            target.write_bytes(data)
            records.append({'path': relative, 'generated': 'runtime_import_payload', 'sha256': hashlib.sha256(data).hexdigest()})
    manifest_path.write_text(json.dumps(records, indent=2)+'\n', encoding='utf-8')
    config = app / 'override.cfg'
    if not config.exists(): config.write_text('[warcraft3]\nasset_root='+json.dumps((ROOT/'assets').as_posix())+'\n',encoding='utf-8')
    print(f'{name}: synced {len(records)} files; packages={",".join(PACKAGES[name])}',flush=True)

if __name__ == '__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--app',choices=('all',*PACKAGES),default='all');parser.add_argument('--test');args=parser.parse_args()
    for name in PACKAGES if args.app=='all' else (args.app,):
        sync(name)
        if args.test:
            from test_apps import prepare
            prepare(name,args.test)
