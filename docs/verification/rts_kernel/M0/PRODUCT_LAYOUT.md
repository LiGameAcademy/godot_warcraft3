# 产品隔离与导出前置检查

日期：2026-09-28。源码基点：`f02cb50`。环境：Windows、Godot `4.7.2.stable.mono.official.ed1daf0bf`。

## 实测结果

- `sync_packages.py --app map_editor` 同步 663 个文件，只包含 foundation、content、map。
- `test_apps.py --app map_editor` 的 8 个用例全部通过：地图文档、地图文件、编辑命令、对象历史、地图导入、文件流程、预览、输入焦点。
- `check_kernel_layout.py` 通过。检查普通 .NET 内核的项目引用递归图、恢复后的传递包依赖，以及编辑器同步清单和 C# 文件隔离。
- `test_dependency_layout.py` 的负面夹具通过：传递 GodotSharp 包、间接 Godot SDK 工程、gameplay 同步到编辑器都能触发失败。

依赖门禁检查构建声明和 NuGet 恢复结果，不声称可以检测任意动态加载。更改依赖后必须重新 restore 才能获得最新结果。

## 重复验证

```powershell
python tools/workspace/sync_packages.py --app map_editor
python tools/workspace/check_kernel_layout.py
python tests/kernel/test_dependency_layout.py
python tools/workspace/test_apps.py --godot "D:\GameMaker\Godot_v4.7.2-stable_mono_win64\Godot_v4.7.2-stable_mono_win64_console.exe" --app map_editor
```

先运行现有 `Test-RtsKernel.ps1` 恢复内核依赖；门禁缺少 `project.assets.json` 时会失败，不会跳过传递依赖检查。

## 未通过的退出门

- 本机 `%APPDATA%/Godot/export_templates` 仅有 `4.6.stable` 和 `4.6.3.stable`，没有 4.7.2 模板。仓库未提供 `export_presets.cfg`。尚未执行 Windows 导出，也未验证导出后的 C# 加载与资源定位；R00.5 保持未完成。
- `benchmark_match_hotpaths.gd --scale` 当前测 100/300/600 个静止节点的邻居查询，不能作为 R00.4 的 300/500 活跃单位移动或战斗结果。新的完整场景夹具及数据尚未交付。
- 用户确认删除的三份旧台账保留在 Git 历史中；本页不替代其状态权威映射和测试映射。后续迁移应在新证据文档中继续维护这些映射。

因此 G0 仍未通过，尚不进入主游戏真实移动权威切换。
