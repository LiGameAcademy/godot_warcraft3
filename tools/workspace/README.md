# 多应用共享源码同步与验证

Python 3.12+、Godot 4.7.2 Mono；第三方子模块需先初始化。

```powershell
python tools/workspace/sync_packages.py
& $env:GODOT --editor --path apps/game
& $env:GODOT --editor --path apps/map_editor
& $env:GODOT --editor --path apps/asset_viewer
```

只编辑 `apps/<产品>/` 中的应用源码和 `packages/` 的共享源码。同步生成固定 `packages/<包>/`（`res://packages/...`）路径，保留 UID，不改写资源引用。共享包不是 Godot addon；真插件仍落在 `addons/`。游戏使用四个共享包与 GAS/Panku；地图编辑器和资产查看器只使用 foundation/content/map。根目录已不是 Godot 项目。查看器用法与审计说明见 [资产查看器](../../apps/asset_viewer/README.md)。

生成目录、清单、测试副本和本地 `override.cfg` 均不提交。清单保存来源路径及 SHA256；同步按清单移除过时文件，并拒绝越界路径和符号链接/junction。旧 `.scn` 脚本路径通过生成的 `.remap` 兼容，不生成重复 class_name。

转换资产保留在仓库根 `assets/`，同步不复制被 Git 忽略的大型产物。首次同步生成 `apps/<产品>/override.cfg` 的 `warcraft3/asset_root` 本机绝对路径；后续不会覆盖用户修改。发布时需自行配置外部资产位置；本轮未验证独立导出制品。

```powershell
python tools/workspace/check_layout.py
./tools/workspace/Test-Apps.ps1 -Godot $env:GODOT
python tools/workspace/test_apps.py --godot $env:GODOT
# 单测及编辑器回归在对应应用的 res:// 下执行
python tools/workspace/test_apps.py --godot $env:GODOT --app map_editor --case unit/selftest_editor_map_file.gd
```

`Test-Apps.ps1` 检查导入、脚本错误、退出码和真实应用启动标记；游戏等待双方开局，编辑器加载完整主场景。`test_apps.py` 按应用准备测试与 fixtures，串行运行回归，每例有超时。日志位于根 `tmp/`。

`source-layout.json` 记录本轮源码原路径与新路径，不是运行时依赖表。`legacy-project.cfg` 仅留存切换时配置供核对，不作为运行入口。资源流水线的 Godot 脚本在 `tools/godot/`，经同步在游戏应用内执行；Node 工具仍从仓库根运行。
