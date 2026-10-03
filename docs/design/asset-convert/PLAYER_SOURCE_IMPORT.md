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
- 当前是同步命令行开发验收入口；目录选择、进度、取消、失败重试 UI 和后台任务仍待实现。
- 未覆盖完整开发地图的数据表、地形纹理及所有模型。只读查看器继续消费 SCN，不承担源解析或修复。
- 原有粒子/billboard/Ribbon 近似、地图缺失资源/占位与退出清理告警仍存在。
- 打包器保留完整现有依赖目录，尚未裁剪跨平台二进制；输入旧版本、容量清理、并发导入隔离、无输入的持久索引挂载及干净机器安装验收待后续解决。

下一步先将这条已验证的入口改为可报告进度、可取消的后台导入，再接首次启动引导；随后按开发地图引用清单扩大覆盖，并完成游戏内视觉验收。
