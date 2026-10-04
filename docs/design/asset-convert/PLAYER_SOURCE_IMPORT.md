# 玩家源资产入口：Windows 发布实验

最新阶段见本文末尾“开发地图资源覆盖（2026-10-04）”。此前的四样本、外部 `--asset-root` 操作保留为历史验收记录。当前默认请求已改为开发地图请求；四样本回归须显式指定 `asset_import_samples.source`。

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


## 开发地图资源覆盖（2026-10-04）

默认首次启动清单为 `apps/game/config/development_asset_request.source`。从玩家的经典 TFT 安装目录读取 `Maps/FrozenThrone/(2)EchoIsles.w3x`，解析地图信息、地形、单位、装饰物和寻路；从同一 MPQ 来源导出定义表和文本配置。根据地图摆放、人族初始农民/主城、建造/训练/技能/物品关联和运行时脚本常量递归收集模型、头像、投射物、光晕及图标。地形对应的悬崖/过渡模型及当前 UI/可替换贴图目录补充扫描；listfile 只作补充，定义引用仍按精确名称读取。

清单只包含路径和规则，不携带原作资源。开发者重新生成它可运行 `node tools/asset-convert/scripts/build-development-request.mjs`；生成器使用开发解包目录的定义文件名和当前脚本，不在玩家机器运行。新增运行时资源引用或开发地图依赖时应更新清单。当前不是任意地图、任意种族或整部魔兽资源的完整导入。

每一代导入在缓存下的独立 `content/<UUID>/assets` 中准备地图、定义表、PNG、glTF 和必要旁路文件，并记录全部文件哈希。模型仍经原有 IR → 缓存编译 → SCN 契约，模型依赖签名改为自身源文件与贴图，不把全部 UI 贴图重复纳入每个任务。全部场景和内容文件校验成功后，才同时挂载场景路径表及这一代内容根目录、清除挂载前的定义表缓存并发布持久索引。失败与取消不发布半份地图内容；旧索引保持可恢复。

Windows release 排除原版模型、派生模型、地图数据、定义表及旧特效目录，保留游戏自写着色器和材质。正常启动不需要 `--asset-root`。缓存索引也验证地图、定义表和贴图的 SHA-256，任一文件缺失/损坏应回到配置界面；快速恢复无需原版 MPQ、中间 IR 或可执行的 Node。源目录变化不在快速启动时自动探测，需主动重新导入。

完整批次的后台编译每次启动同一游戏 EXE 编译最多 16 个任务，四样本仍每批一个，保留逐任务取消回归。取消终止当前拥有的进程，已经提交的单场景缓存可用于重试。阶段计数不是总耗时百分比；最后的哈希验证和路径挂载仍在主线程，尚未承诺大批量全过程没有停顿。

覆盖报告在内容根目录的 `coverage.json`：列出对象/模型/贴图计数、未解析引用、源缺项及路径别名。命令面板的旧 `BTNBuild`/`DISBTNBuild` 引用通过显式别名使用原版 `BTNHumanBuild`/`DISBTNHumanBuild`，报告保留对应关系。未找到真实引用会记录警告并使 `complete=false`，界面提示核查报告；模型自身必需依赖缺失仍失败。`complete` 只表示此规则范围的引用覆盖，`visual=unverified` 和 `deliverable=false` 继续保留。

这次扩大范围还修复了挂点以另一个挂点为父节点的编译、纯粒子模型的空 glTF 缓冲/无轨道动画，Godot 导入时骨骼与场景节点重名的精确映射，以及相同 float32 动画载荷的重复存储。复用动画存储不会降低采样率或改变曲线。来源元数据随 IR 首次写出；Windows 临时文件占用只进行有限重试，持续失败仍报错并保留旧目标。

### 完整发布验收与手动启动

构建机设置 Godot .NET 路径后，从仓库根目录执行：

```powershell
$env:GODOT = 'D:/GameMaker/Godot_v4.7.2-stable_mono_win64/Godot_v4.7.2-stable_mono_win64.exe'
node tools/asset-convert/src/game-development-import.test.mjs
```

测试导出正式 release，后台完成完整默认请求，验证覆盖报告与缓存索引。随后禁用随包 `node.exe` 并移走中间输入，再用持久缓存启动 86 单位地图，清空外部工具相关环境变量，且不传 `--asset-root`；最后实际渲染地图并验证图标可加载。报告、日志和截图位于 `tools/asset-convert/tmp/development-*/`，只保留成功完成后的 `report.json` 作为验收证据。

本轮验收结果：449 个 SCN、10,537 个内容文件，当前规则范围未解析引用为 0。完整后台冷导入、无 Node/中间输入的索引恢复、86 单位地图启动及实际截图通过；四样本引导 9 项回归、内容原子挂载、挂点层级/骨骼映射、纯粒子输入与 3,500 次动画采样对比通过。修正了 release 会剔除断言导致截图保存未执行的测试脚本，最终渲染复测复用了同一份成功冷导入证据（报告 `reusedColdImport=true`）。

此次冷导入约 1,012 秒；缓存地图启动观察到约 34 秒及一次 286 秒，不能据此承诺快速启动。下一轮应分段测量完整文件哈希、场景预加载和地图初始化，再决定减少重复校验/延迟加载的边界。启动挂载前仍有定义表缺项警告，渲染退出日志还有 Godot 的空材质及对象清理信息，保留日志继续排查；未计为原作视觉验收通过。

打开最新成功构建（复用验收缓存）：

```powershell
$reportFile = Get-ChildItem tools/asset-convert/tmp/development-*/report.json | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$report = Get-Content $reportFile.FullName -Raw | ConvertFrom-Json
& $report.binary -- --asset-import-cache $report.cacheRoot
```

验证玩家首次启动，应改用一个新缓存目录，并强制显示配置界面：

```powershell
$manualCache = Join-Path $reportFile.DirectoryName 'manual-cache'
& $report.binary -- --asset-import-cache $manualCache --asset-import-wizard
```

1. 选择含 MPQ 和上述 Echo Isles 文件的经典安装目录，查看定义表/地图/贴图/模型各阶段进度。
2. 取消后不得进入地图；重试成功后点击继续，检查地形、悬崖、农民/主城和 UI，选择单位检查图标/选择环。
3. 训练牧师、大法师并攻击，检查投射物、光晕、动画循环；与原作游戏内表现比较，不能将“可加载”当保真通过。
4. 关闭游戏后，同一命令移除 `--asset-import-wizard`，应从缓存进入地图。
5. 修改缓存的贴图/定义表或删除 SCN，下一次启动应回到导入界面，而不是使用半损坏内容。

剩余工作：游戏内视觉验收、干净机器安装、缓存容量及旧版本清理、多个游戏进程的导入协调。地图内嵌资源覆盖、其他地图/种族、CASC、音效事件和跨平台发布不在本轮覆盖承诺内。


## 对局特效接入与启动测量（2026-10-05）

真实 `CombatProjectileShell` 曾继续对新 SCN 调用旧粒子挂载、强制发射/循环、尺度增强及软球替换。这会让查看器和游戏使用不同表现。本轮依据编译标记分流：统一管线产物直接加载已编译场景，使用源 +X 飞行轴、源尺度、材质、粒子控制轨和循环标记，命中播放 Death 并按动画时长安排清理；旧资产继续原兼容处理。旧几何轴向/缩放计算独立为小型辅助脚本，投射物壳不超过 500 行。本轮没有改动伤害计算。

验收命令（先完成前节发布导入，设置 `GODOT`）：

```powershell
node tools/asset-convert/src/game-fx-review.test.mjs
```

脚本自动定位最新成功的开发导入报告，使用其 SCN，在游戏工程内实例化真实投射物壳，验证移动、无重复旧粒子、源发射开关、三轮循环不漂移、非循环 Death 命中及英雄光晕。结果在 `tools/asset-convert/tmp/game-fx-review/`，含六张截图、技术报告、来源索引和运行日志。已实际看过牧师/火球飞行及英雄顶视图；牧师蓝绿形态、火球红黄形态和红色光晕可见。测试场景不是实际完整对局，原作对照仍未验收，材质多层/纹理动画/Squirt 等既有诊断不因此升级为支持。

手动验收使用前节发布包启动命令。在对局中训练单位攻击固定目标，对照查看器检查飞行方向、命中、暂停/恢复、重复发射及队色；再与相同原版安装、相同单位/动作/机位的游戏画面对照。`selftest_wc3_fx_presenter.gd` 因固定开发 glTF 夹具缺失失败，尚未证明旧特效样本整套回归；已验证本次提取的旧轴向和缩放函数。渲染测试仍有退出资源清理警告，日志保留。

正常发布启动增加 `--asset-import-profile` 可输出 `ASSET_IMPORT_PROFILE` JSON 行，不改变缓存策略，也不写原版目录。记录内容索引哈希、场景索引哈希、安装内容复核和场景加载四段；发布验收报告新增 `startupTimings`。本轮最终一次缓存地图启动约 43.9 秒，四段约 12.0/3.1/8.5/8.1 秒；另一轮约 24.4/20.5/7.3/7.3 秒。时间受磁盘缓存和机器负载影响，不能当固定承诺。

下步优先将完整内容复核从主线程迁出，评估同一启动事务避免重复哈希、场景按需加载的边界；保持损坏检测、失败可恢复和对局内容封存，再进行多进程/容量清理。此轮只添加测量，没有降低哈希校验或宣称启动优化完成。
