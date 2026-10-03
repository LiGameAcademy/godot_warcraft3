# 玩家源资产入口：Windows 发布实验

2026-10-03。本轮验证原版安装目录 → MPQ 精确读取 → 原有 JS 适配器 → IR/glTF/依赖 → 游戏缓存编译 → SCN。结果保持 `deliverable=false`；不代表开发地图全量或特效视觉保真通过。

## 运行边界

采用随发布包携带的 Node + JS 适配器 + Koffi/StormLib，复用已有模型、BLP、粒子和 Ribbon 解析，暂不重写为 C++/GDExtension。玩家不安装 Node、Godot 编辑器或 npm；发布进程通过明确的 EXE 路径启动打包运行时，`OS.execute` 使用参数数组并隐藏控制台，不启动 shell。测试清空 PATH、GODOT、ASSET_SOURCE、STORMLIB_DLL、NODE_PATH 和 NODE_OPTIONS。

Godot 编译/保存 SCN 仍由游戏内同步编译核心完成；Node 子进程只读取源文件并产生编译输入。独立 JavaScript 开发项目继续复用同一适配器实现。

```text
release/
  game.exe / game.pck / .NET 运行文件
  asset-import-runtime/
    node.exe
    NODE-LICENSE / STORMLIB-LICENSE
    runtime-bundle.json
    tools/asset-convert/{package.json,src/,node_modules/}
    tools/mpq-extract/{package.json,src/,node_modules/,vendor/stormlib/StormLib.dll}
    tools/pipeline-log.mjs
```

发布实验没有将原作 MDX/BLP、原始归档或本机开发缓存复制到运行时目录。JS 依赖保留各自许可；Node 与 StormLib 官方许可原文保存在 `tools/asset-convert/vendor/runtime-licenses/`。打包阶段离线读取这些文件，Node 版本变化需要匹配的新许可输入。实际发行前仍需决定固定版本、依赖裁剪和安装包构建策略。

## 输入与来源

`ClassicMpqSource` 以只读方式打开已识别的经典 MPQ。覆盖顺序沿用现有开发工具：War3 → War3x → War3Local → War3xLocal → War3Patch，后者优先。不依赖 listfile，逐个精确名称探测模型及其纹理，因此列表中未列出的补丁资产仍可找到。归档打开失败明确终止并关闭已打开句柄；依赖缺失明确失败，不把占位纹理当成功。

请求格式：

```json
{"request_version":1,"models":["Units/Human/Footman/Footman.mdx"]}
```

入口校验版本、非空模型数组、MDX/MDL 扩展名与不重复的逻辑身份；拒绝绝对路径、父目录跳转、空路径段和非法路径字符。源安装目录只读，输出不得位于该目录内。记录每个实际源模型/纹理的逻辑路径、源包、优先级和 SHA-256；模型来源写入 IR，原始依赖纳入 bake task。

输入批次签名包含请求、原始模型与纹理内容、来源以及打包运行时实际文件哈希。输入目录使用此签名，重复运行保持路径与内容稳定，可命中 SCN 缓存。每次重新生成 PNG 可修复损坏的派生纹理；任务清单最后写出，准备失败不会触发游戏路径表安装，已有独立 SCN 仍可使用。本阶段扩大请求或修改任一批次依赖会使整个批次输入路径变化，尚未优化为逐资产准备缓存。

## 验证与操作

从仓库根目录执行：

```powershell
$env:GODOT = 'D:/GameMaker/Godot_v4.7.2-stable_mono_win64/Godot_v4.7.2-stable_mono_win64_console.exe'
$env:WC3_PATH = 'D:/Program Files (x86)/Warcraft3'
node tools/asset-convert/src/runtime-source-import.test.mjs
node tools/asset-convert/src/game-source-import.test.mjs
```

测试自行同步并导出正式游戏，准备运行时 sidecar，发布进程直接读取原版安装目录。默认四个真实模型：Footman、PriestMissile、HeroArchMage 和 RejuvenationTarget；包含普通模型、粒子、光晕和 Ribbon。测试报告保存在 `tools/asset-convert/tmp/game-source-*/report.json`，逐次日志同目录。

手动打开最新成功构建：

```powershell
$reportFile = Get-ChildItem tools/asset-convert/tmp/game-source-*/report.json | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$report = Get-Content $reportFile.FullName -Raw | ConvertFrom-Json
$resultFile = Join-Path $reportFile.DirectoryName 'manual-source.result.json'
& $report.binary -- --warcraft-dir $report.gameDir --asset-import-cache $report.cacheRoot --asset-import-result $resultFile --asset-import-only
```

希望继续进入地图时，删除 `--asset-import-only` 并添加 `--asset-root` 指向仓库 `assets` 的实际路径；这一依赖只服务现有开发地图的其他资源，四个导入样本自身从 MPQ 读取。命令行 `--asset-import-request` 可指定外部请求清单，否则使用包内样本清单。`--warcraft-dir` 与预生成清单入口 `--asset-import-manifest` 互斥。

构建工具也可单独调用，目标必须是尚不存在的目录：

```powershell
node tools/asset-convert/scripts/package-runtime.mjs .cache/player-import-build/asset-import-runtime
```

这是明确的构建步骤；仅按 Godot preset 导出 EXE 不会自动产生 Node sidecar。未打包 sidecar 时游戏返回 `source_runtime_missing`。

## 本轮验证结果

正式 release 的 10 项检查通过：原版 MPQ → IR → SCN、纹理/来源记录、跨进程命中、损坏派生 PNG 修复、非法安装目录、越界请求、缺失模型、缺失随包运行时、有效重试保持良好 SCN，以及 86 单位的可玩地图启动。源适配器单元测试覆盖精确读取/补丁优先级、失败关闭句柄和源目录只读保护。普通 Loading 启动、查看器通用交互及 Footman 节点树/动画/六向视图回归通过；四个新样本实际渲染截图已检查。

旧 `selftest_asset_viewer --capture` 中的“切换环境光使 Footman 增亮”断言在新产物上未通过（中心亮度 0.1487 → 0.1487）。没有修改此断言或将它算作通过；本轮使用专项测试检查新产物渲染，光照比较的适用性/差异留待视觉验收排查。截图能看到模型和特效，不等于与原作一致。

本次 sidecar 共 461 个文件，约 117 MiB；原版资源仅进入用户缓存。最新成功报告、逐次日志和缓存实际路径由测试输出记录，不提交本机原版资产或二进制。

## 限制与下一步

- 仅验证 Windows x64 经典 MPQ；CASC、嵌套地形归档、地图自带资源覆盖及其他平台未接入。
- Windows 发布包已接入首次启动目录选择、后台阶段进度、取消与失败重试；命令行同步入口继续保留。
- 未覆盖完整开发地图的数据表、地形纹理及所有模型。只读查看器继续消费 SCN，不承担源解析或修复。
- 原有粒子/billboard/Ribbon 近似、地图缺失资源/占位与退出清理告警仍存在。
- 打包器保留完整现有依赖目录，尚未裁剪跨平台二进制；输入旧版本、容量清理、多游戏进程并发导入协调及干净机器安装验收待后续解决。持久索引挂载已支持，不再需要解析输入仍然存在。

下一步按开发地图引用清单扩大覆盖，包含数据表、地形和纹理；随后完成游戏内视觉验收与干净机器安装验收。

## 首次启动与后台导入（2026-10-03）

Windows 发布包默认先检查 `user://wc3-cache/source-import/indexes`。引擎、编译器、样本请求及随包解析版本匹配，且每个 SCN 文件存在、哈希正确时，直接挂载完整路径表并进入原有 Loading 流程。没有有效索引则显示“准备游戏资源”：选择原版目录 → 开始导入 → 查看阶段进度 → 继续进入游戏。更换原版来源应主动重新导入；快速启动不会再次读取 MPQ 检测源文件变化。

源解析由随包 Node 子进程执行；每个场景由同一游戏 EXE 的 headless 子进程编译。主界面逐帧轮询进度与结果；最终校验/挂载仍在主线程完成，当前四个样本通过了界面持续更新检查，不代表任意大批量挂载都没有帧耗时。阶段计数表示当前阶段完成数，不是整体耗时百分比。

取消终止本次拥有的子进程，确认退出后才允许重试。完成的单场景缓存保留，半成品不挂载，既有成功索引不替换。全部任务成功且可加载后才发布独立的索引文件；未提交的 `.pending` 不参与恢复。Windows 进度快照也发布为独立文件，避免读取时替换同名文件的占用冲突。若索引发布失败，界面显示警告，本次可继续，下次需要重新生成索引。暂不清理旧版本和取消留下的中间文件。

### 手动验收

先运行 `node tools/asset-convert/src/game-import-wizard.test.mjs`（构建环境需设置 `GODOT`，如前文）。测试输出完整报告绝对路径。测试专用入口仅加入这份测试构建，生产 preset 和启动场景在导出后恢复；正常导出仍须另外打包 `asset-import-runtime`。

在仓库根目录 PowerShell 运行：

```powershell
$reportFile = Get-ChildItem tools/asset-convert/tmp/wizard-*/report.json | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$report = Get-Content $reportFile.FullName -Raw | ConvertFrom-Json
$assetRoot = Join-Path $PWD 'assets'
$manualCache = Join-Path $reportFile.DirectoryName 'manual-cache'
& $report.binary -- --asset-root $assetRoot --asset-import-cache $manualCache --asset-import-wizard
```

1. 使用新缓存时应显示目录选择界面；输入错误目录，应明确失败并允许修改后重试。
2. 选择原版目录并导入。窗口可以操作，能看到“读取模型与纹理”“生成模型编译输入”“编译场景缓存”的进度。
3. 导入中点击取消，应回到可重试状态，“继续进入游戏”不可用。再次导入应成功，已完成的场景可命中缓存。
4. 成功后点击继续，应进入 Loading 与开发地图。当前地图仍需要命令中的外部 `assets`；四个模型成功不代表完整地图原版导入已完成。
5. 关闭后再次启动相同命令，移除 `--asset-import-wizard`：应复用索引直接进入 Loading。缓存命中可在解析运行时或中间输入不可用时工作；真实重导入仍要求完整 sidecar。
6. 强制显示配置界面可保留 `--asset-import-wizard`。索引或 SCN 损坏、版本变化时，应回到配置界面，重新导入修复。

本轮正式发布包 9 项引导验收、既有同步导入 8 项兼容回归和正常 Loading → 可玩地图回归通过。自动验收覆盖缓存不得写入原版目录、冷导入、界面持续更新、两阶段取消保护原索引、离线索引恢复、错误目录重试、损坏索引重建、界面实际渲染与缓存恢复后的可玩地图启动。截图和逐次日志保存在报告同目录。完整资源覆盖和原作视觉一致性仍需下一轮验收。
