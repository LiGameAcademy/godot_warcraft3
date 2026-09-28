"""Negative fixtures prove the architecture gate actually rejects dependency leaks."""
import importlib.util
import json
import pathlib
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("layout", ROOT / "tools/workspace/check_kernel_layout.py")
layout = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(layout)


class DependencyLayoutTests(unittest.TestCase):
    def test_boundaries(self):
        with tempfile.TemporaryDirectory() as folder:
            root = pathlib.Path(folder)

            def write(name, text):
                path = root / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(text, encoding="utf-8")

            kernel = "external/rts_kernel/src/Rts.Kernel/Rts.Kernel.csproj"
            assets = "external/rts_kernel/src/Rts.Kernel/obj/project.assets.json"
            write(kernel, '<Project Sdk="Microsoft.NET.Sdk"/>')
            write(assets, '{"libraries": {}}')
            write("apps/game/godot_warcraft3.csproj", '<Project><ItemGroup><ProjectReference Include="../../external/rts_kernel/src/Rts.Kernel/Rts.Kernel.csproj"/></ItemGroup></Project>')
            write("apps/map_editor/.workspace-sync.json", "[]")
            self.assertEqual(layout.check(root), [])
            write(assets, json.dumps({"libraries": {"GodotSharp/4.7.2": {}}}))
            self.assertTrue(any("Transitive" in error for error in layout.check(root)))
            write(assets, '{"libraries": {}}')
            write(kernel, '<Project Sdk="Microsoft.NET.Sdk"><ItemGroup><ProjectReference Include="../adapter/Adapter.csproj"/></ItemGroup></Project>')
            write("external/rts_kernel/src/adapter/Adapter.csproj", '<Project Sdk="Godot.NET.Sdk/4.7.2"/>')
            write("external/rts_kernel/src/adapter/obj/project.assets.json", '{"libraries": {}}')
            self.assertTrue(any("nonstandard SDK" in error for error in layout.check(root)))
            write(kernel, '<Project Sdk="Microsoft.NET.Sdk"/>')
            write("apps/map_editor/.workspace-sync.json", '[{"source":"packages/gameplay/example.gd"}]')
            self.assertTrue(any("leaked" in error for error in layout.check(root)))
            write("apps/map_editor/.workspace-sync.json", '[{"source":"external/rts_kernel/src/Rts.Kernel/Commands.cs"}]')
            self.assertTrue(any("leaked" in error for error in layout.check(root)))


if __name__ == "__main__":
    unittest.main()
