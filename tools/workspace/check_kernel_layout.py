"""Check the engine-free kernel dependency graph and Godot product isolation."""
import json
import pathlib
import sys
import xml.etree.ElementTree as ET

ROOT = pathlib.Path(__file__).resolve().parents[2]


def check(root=ROOT):
    errors = []
    visited = set()

    def visit(project):
        project = project.resolve()
        if project in visited:
            return
        visited.add(project)
        if not project.is_relative_to(root.resolve()):
            errors.append(f"Project reference escapes repository: {project}")
            return
        tree = ET.parse(project).getroot()
        if tree.get("Sdk") != "Microsoft.NET.Sdk":
            errors.append(f"Kernel dependency uses a nonstandard SDK: {project}")
        for item in tree.iter():
            if item.tag in {"PackageReference", "Reference", "FrameworkReference"}:
                if "godot" in item.get("Include", "").lower():
                    errors.append(f"Godot reference in kernel graph: {project}")
            if item.tag == "ProjectReference":
                visit(project.parent / item.attrib["Include"].replace("\\", "/"))
        assets = project.parent / "obj/project.assets.json"
        if not assets.exists():
            errors.append(f"Restore required before checking transitive packages: {project}")
        else:
            for library in json.loads(assets.read_text(encoding="utf-8-sig"))["libraries"]:
                if "godot" in library.lower():
                    errors.append(f"Transitive Godot dependency in {project}: {library}")

    kernel = root / "packages/rts_kernel/Rts.Kernel.csproj"
    visit(kernel)
    game = root / "apps/game/godot_warcraft3.csproj"
    game_xml = ET.parse(game).getroot()
    references = [
        (game.parent / item.attrib["Include"].replace("\\", "/")).resolve()
        for item in game_xml.iter("ProjectReference")
    ]
    if kernel.resolve() not in references:
        errors.append("Game must reference the canonical kernel project.")
    editor = root / "apps/map_editor"
    if list(editor.glob("*.csproj")) or list((editor / "addons").rglob("*.cs")):
        errors.append("Map editor unexpectedly contains a C# project or synced C# source.")
    manifest = editor / ".workspace-sync.json"
    if not manifest.exists():
        errors.append("Sync map_editor before checking its product boundary.")
    else:
        for row in json.loads(manifest.read_text(encoding="utf-8")):
            if row.get("source", "").startswith(("packages/gameplay/", "packages/rts_kernel/")):
                errors.append(f"Game-only source leaked into editor: {row['source']}")
    return errors


if __name__ == "__main__":
    failures = check()
    for failure in failures:
        print("FAIL:", failure)
    print("KERNEL_LAYOUT", "FAIL" if failures else "PASS")
    sys.exit(bool(failures))
