# 资产导入管线重构：收尾与验收

2026-10-05。分支 `codex/asset-pipeline-rebuild`。本文是当前交付入口；历史阶段记录见 [PLAYER_SOURCE_IMPORT.md](PLAYER_SOURCE_IMPORT.md) 和 [路线图](RUNTIME_IMPORT_REBUILD_ROADMAP.md)。

## 当前交付边界

经典 MPQ 安装目录只读读取 → 随包 Node/适配器生成 IR、glTF 与依赖 → 同一游戏 EXE 的 headless 编译器生成 SCN → 校验完整内容与模型 → 原子安装路径表和内容根目录 → 发布持久索引 → 后续启动校验索引并进入游戏。玩家不需要安装 Godot 编辑器、Node、Python 或 npm。

默认覆盖 Echo Isles 开发地图、人族建造/训练和相关技能/物品、投射物、光晕、头像、地形与 UI。其他地图/种族、地图内嵌资产、CASC、音效事件及跨平台发布需要另行扩展。资产查看器是独立只读产品：检查产物和诊断，不承担编辑、转换或原作视觉验收裁定。

## 本次收尾改动

- 缓存恢复在工作线程完整校验内容/场景 SHA-256；主线程加入线程后消费一次校验结果并安装路径。避免同一次启动重复计算内容哈希，恢复时按需加载 SCN。每个编译子进程已经重载并实例化场景、对比节点清单；安装前再次验证 SCN 哈希与内容哈希。缓存恢复和最终路径检查不再逐个执行旧资产兼容扫描。
- 缓存根目录有排他的导入锁，记录拥有者及当前后台子进程的 PID 和启动时间，避免 PID 复用误判。死亡写者按其唯一 token 排他回收，避免迟到的恢复操作搬走新写者的锁。游戏已有 .NET 运行时检查独立进程存活，不能用 Godot 在 Windows 上只识别自身子进程的 API 判断其他游戏是否退出。
- 使用缓存的游戏登记进程标记，成功导入在释放写锁之前登记。其他游戏不能重导入正在使用的缓存；清理工具也拒绝活动读者。异常退出后保留的标记以进程状态判断，死亡标记不阻止恢复。
- 随包提供缓存维护 CLI，默认预览；显式执行时保留最新两份有效结构索引及其 SCN/完整内容，删除无引用派生文件与中间输入，记录 `maintenance.jsonl`。8 GiB 为软预算提示，超过预算不会删除仍被保留索引引用的资源。
- 维护使用 Windows 自带 PowerShell 查询活跃 PID 的启动时间，不依赖玩家安装 SDK；查询失败保守拒绝清理。维护拒绝未知缓存、符号链接、活动进程和损坏索引。旧空目录、死亡读者标记和锁回收目录暂不整理；恢复过程中崩溃留下的 `.takeover-*` 或缺失 owner 的锁会拒绝猜测恢复，应保留日志并换用新缓存或人工核查；不提供自动定时清理或游戏内清理按钮。

缓存协调约束针对遵守本管线的进程。它不会阻止用户或其他工具在后台手工修改文件。源安装目录不会在快速恢复时重新扫描，需要重导入才能读取源资产变化。关闭窗口时先请求取消后台哈希，再安全加入线程；取消在文件和 1 MiB 块之间检查，正在执行的系统文件读取仍需返回；冷导入最终的内容/SCN 哈希复核仍在主线程，可能短暂停顿。

## 开发者自测

在仓库根目录 PowerShell，设置构建机 Godot .NET 路径：

```powershell
$env:GODOT = 'D:/GameMaker/Godot_v4.7.2-stable_mono_win64/Godot_v4.7.2-stable_mono_win64.exe'
node tools/asset-convert/src/cache-maintenance.test.mjs
python tools/workspace/test_apps.py --godot $env:GODOT --app game --case unit/selftest_asset_import_guard.gd
python tools/workspace/test_apps.py --godot $env:GODOT --app game --case unit/selftest_asset_import_snapshot.gd
node tools/asset-convert/src/game-import-wizard.test.mjs
node tools/asset-convert/src/game-development-import.test.mjs
node tools/asset-convert/src/game-fx-review.test.mjs
```

首次启动发布回归包括错误目录重试、两阶段取消、损坏索引重建、离线恢复、地图启动、实际界面渲染、独立写者/读者排斥及随包清理后恢复；四模型夹具不承担完整地图启动检查。完整开发地图测试覆盖完整冷导入、覆盖报告、无原作资产打包、禁用随包 Node/移走 IR 后启动 86 单位地图和图标渲染。报告在各测试末尾输出绝对路径。

`ASSET_TEST_RETRY` 用已有目录重新执行完整后台源导入，允许复用此前完成的单场景缓存；报告记录 `retriedInterruptedImport` 和 `sceneCacheHits`。它不跳过本次导入或索引校验。

`ASSET_TEST_RECOVER` 只验证已真实发布的完整索引、离线启动和渲染；保留冷导入原报告，不生成冷导入 UI/进度证据。报告 `recoveredPublishedIndex=true` 时不能标记一次新的完整冷导入通过。完整批次测试时限为 60 分钟，仍须检查进度与结果，不能只放宽时限当作修复。

`ASSET_TEST_REUSE` 仅用于重新导出后检查已有成功冷导入的恢复与渲染；报告 `reusedColdImport=true` 时不应声称进行了新一次完整冷导入。技术测试与视觉裁定分开记录。

## 打开验收构建

```powershell
$reportFile = Get-ChildItem tools/asset-convert/tmp/development-*/report.json | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$report = Get-Content $reportFile.FullName -Raw | ConvertFrom-Json
& $report.binary --rendering-driver vulkan -- --asset-import-cache $report.cacheRoot
```

当前有窗口验收使用 OpenGL 兼容模式。默认项目配置为 D3D12：本机手动启动在「放置单位模型 6/97」停留超过十分钟且窗口无响应；同一发布包与缓存改用兼容模式，约 21.2 秒完成地图及图标渲染。D3D12 正常启动尚未通过，不能用兼容模式截图代替默认后端验收。同一发布包与缓存改用 Vulkan + Forward+，约 47.0 秒也完成地图及图标渲染；上述手动命令因此显式选择 Vulkan，保留 Forward+。OpenGL 兼容模式可作为备用，但效果应注明所用后端。保留资源缓存；D3D12 底层阻塞原因仍需单独定位。对照日志和截图在 `tools/asset-convert/tmp/loading-debug/`。

第一次导入改用新缓存：

```powershell
$manualCache = Join-Path $reportFile.DirectoryName 'manual-cache'
& $report.binary --rendering-driver vulkan -- --asset-import-cache $manualCache --asset-import-wizard
```

清理前关闭使用该缓存的游戏。使用发布包自带工具，先预览；确认报告的 `root`、`retainedIndexes` 和 `remove` 后再执行：

```powershell
$runtime = Join-Path (Split-Path $report.binary) 'asset-import-runtime'
$maintenance = Join-Path $runtime 'tools/asset-convert/src/cache-maintenance.mjs'
& (Join-Path $runtime 'node.exe') $maintenance $report.cacheRoot
# 对同一派生缓存执行报告中的删除：
& (Join-Path $runtime 'node.exe') $maintenance $report.cacheRoot --apply
& $report.binary --rendering-driver vulkan -- --asset-import-cache $report.cacheRoot
```

工具不会修复坏索引。收到 `cache_index_invalid` 时先保留诊断、通过重新导入或新缓存目录恢复，勿直接猜测哪些模型可删除。

## 游戏内视觉验收

以相同原版安装来源为基准，记录地图、单位、动画、队色和机位。查看器方便检查结构、帧和诊断，最终以真实对局表现及原作对照为准。保真基座和明确的增强效果分别判定，不能用旧导入效果作为唯一正确答案。

| 对象 | 需要观察 | 合格条件 |
| --- | --- | --- |
| Footman/Peasant | Stand、行走、攻击、死亡、队色、贴图 | 动作连续，骨骼无拉裂；没有黑面/占位贴图；队色不覆盖普通贴图 |
| 牧师投射物 | 连续攻击、飞行方向、发射开关、命中、三轮以上循环 | 没有重复粒子或循环累积漂移；源控制生效；大小/颜色/尾迹与原作对照有结论 |
| 大法师投射物 | 不同攻击距离/朝向，命中与消失 | 朝向正确；尾迹不翻转/拉长；命中及消失符合动画，不残留前一发 |
| 英雄光晕 | 顶视/斜视、移动、队色、多英雄实例 | 位置跟随且稳定；不成为实体黑片；实例颜色互不影响；形状与原作对照 |
| 地形与界面 | 悬崖、地面、选择环、框选、图标、命令面板 | 没有缺图；选择反馈可见；摄像机移动后表现稳定 |

每项记录：通过/不通过/待确认、源安装版本、截图或短视频、问题资产逻辑路径、观察动作。已知不支持的材质多层、纹理动画、Squirt 等诊断需要注明是否影响样本；不能因为能加载就抹去诊断。发现问题再按影响划分为阻止合并或后续独立改进。

## 干净 Windows 安装验收

在没有 Godot、Node、Python、npm 与 .NET SDK 的另一台机器或干净 VM 上复制完整发布目录，保留随包 .NET 运行文件和 `asset-import-runtime`。准备玩家自己的经典 MPQ 安装与所需开发地图，从空缓存完成目录选择、取消/重试、导入、进入游戏；重启后拔掉源目录也应由缓存进入游戏。记录操作系统、显卡、发布包版本、导入/启动时间和日志。

清空构建机 PATH 与禁用随包解析器是隔离回归，不能替代这一真实安装检查。若缺少运行库或 DLL，保留错误并修正发布依赖后再测。

## 合并与发布判断

技术实现收尾、提交 Git 与最终发行为不同状态。只有技术回归通过、游戏内视觉样本有明确裁定、干净机器安装通过，才建议合并主干并确定可发布范围。当前 `deliverable=false` 和 `visual=unverified` 保持诚实，不通过文档将其改为已验收。

## 本次实际验收记录

- 缓存维护、写锁/PID 复用/当前子进程/同代回收保护、一次性后台校验/损坏场景拒绝安装、内容原子路径表单测通过；新的两份单测已加入常规 game suite。
- 当前代码的 Windows 发布引导 12 项检查通过，报告 `tools/asset-convert/tmp/wizard-rWG6nb/report.json`。包含随包维护 CLI 实际预览/清理后恢复、真实独立写者/读者保护；四模型夹具不再假定可以验收全量地图。
- 首次全量尝试完成 449 个场景编译，但最终验收超时。修复后的完整重试复用 449 个单场景缓存，并于 19:49 发布完整索引；验收程序在附加复核超过原来的 31 分钟上限，未把这次冷验收记为通过。日志在 `closeout-full-test.log` 和 `closeout-full-retry.log`。
- 重新导出当前代码，从已发布索引验收恢复通过：449 个模型、10,537 个内容文件、引用覆盖完整；禁用随包 Node/移走 IR 后可进入 86 单位地图，实际地图及图标渲染通过。报告 `tools/asset-convert/tmp/development-qr5w3F/report.json` 标记 `recoveredPublishedIndex=true`，冷报告保持原样。内容/SCN 哈希约 9.45/2.81 秒，路径安装约 1.8 毫秒，一次离线启动约 23.6 秒；受磁盘缓存和负载影响。
- 为复用资产证据，完整恢复构建沿用了此前的源解析运行时；源解析实现没有变化。新版维护 CLI 已在上述新发布引导构建中另外验收。当前代码正常重新打包会生成新版 runtime-bundle 并按既有策略失效旧索引。

- 当前代码及重新打包的源运行时从空缓存独立完整验收通过，报告 `tools/asset-convert/tmp/development-w0Inu9/report.json`：449 个 SCN、10,537 个内容文件，场景缓存命中 0；`reusedColdImport`、`recoveredPublishedIndex` 和 `retriedInterruptedImport` 均为 false。完整后台导入约 1,018 秒；禁用随包 Node/移走 IR 后，离线 86 单位地图与实际地图/图标渲染通过。两次启动进程约 19.5/20.8 秒，内容/SCN 哈希约 7.37/2.45 秒，路径安装约 3 毫秒。时间受硬件及磁盘缓存影响。

- 使用本次新生成的 SCN 重跑真实投射物壳技术检查通过：牧师/火球移动、三轮循环、命中 Death 和英雄光晕，报告 `tools/asset-convert/tmp/game-fx-review/report.json`，附六张截图。该测试不替代完整对局及原作对照。
- 既有旧特效测试 `selftest_wc3_fx_presenter.gd` 缺少固定开发 glTF 夹具，未完成整套旧样本回归；Godot 导出/退出仍有资源清理告警，日志保留。地图截图中的网格和彩色区域是现有开发显示，视觉裁定仍需实际交互及原作对照。

技术收尾已完成空缓存全量导入及缓存恢复回归；原作视觉裁定和真实干净 Windows 安装保持待验收。不要据此直接把整个分支标为可发布或自动合并。

## 游戏截图问题复验（2026-10-05）

队色、肖像背景、建筑禁建外圈、建筑肖像及额外测试开局的原因、修复与手动流程见 [GAME_ASSET_REVIEW.md](GAME_ASSET_REVIEW.md)。启动增加 `--asset-review` 可获得牧师与大法师。必须使用本轮新场景缓存；默认 D3D12 阻塞及原作视觉裁定仍不据此视为完成。


## 大法师技能复验（2026-10-06）

召唤单位的源引用闭包、技能场景旧处理入口、Squirt 爆发、技能材质曲线、特效寿命和每波重复读取 SCN 的问题已纳入本轮修复。原因、手动流程及明确剩余近似见 [GAME_ASSET_REVIEW.md](GAME_ASSET_REVIEW.md)。本轮另外验证三个等级水元素、连续暴风雪与完整群体传送；保真视觉仍由原作对照裁定。

新技能验收使用 `tools/asset-convert/tmp/development-9beFl2/report.json` 与 `asset-review-spells.json`：480 个模型、10,903 个内容文件；全量导入证据保留，最终重新导出后复用缓存验收。命中特效也绕过旧网格重建；暴风雪长帧明显降低，剩余近似及性能边界见上述说明，不据此宣布原作视觉通过。

## 动画结束切换回归（2026-10-06）

真实 SCN 中的水元素 Birth 和大法师 Spell 保留了正确的单次标记，游戏播放层却只读取旧版元数据并覆盖成循环。本轮补齐新旧动画循环标记兼容，按实例隔离循环策略修改，并补充动画结束信号、三级召唤出生结束及大法师施法姿态结束检查。此前召唤验收只检查模型/肖像存在，这一遗漏已记录在 [GAME_ASSET_REVIEW.md](GAME_ASSET_REVIEW.md)。现有场景缓存可以复用，需要重启更新后的游戏。

专项回归与重新导出的离线游戏技能复验通过，三级水元素均切到 Stand，大法师均结束施法姿态，连续暴风雪和群体传送生命周期通过。使用同一份 480 场景缓存；当前报告记录复用冷导入产物。启动内容/SCN 哈希检查约 318.5／48.4 秒，整段技能验收仍出现约 895 毫秒长帧，启动和运行性能需要继续诊断，详见上述说明。


## 缓存校验性能与取消（2026-10-07）

缓存恢复改用默认两个工作任务进行完整流式 SHA-256 校验，引导增加文件数、读取量、耗时和“取消校验”。关闭时按块取消，并修复校验完成后尚未挂载期间的取消竞态。真实 10,903 内容文件和 480 场景的双线程校验约 6.86／9.36 秒；系统文件缓存影响显著，不能将首次串行读取的 195 秒直接作为同条件加速比较。实现、测量、手动验收及下一轮长帧目标见 [CACHE_VALIDATION_PERFORMANCE.md](CACHE_VALIDATION_PERFORMANCE.md)。


本轮正式发布引导 12 项回归与完整游戏缓存复用/技能复验通过。不过发布包第一遍内容/场景校验仍约 292.56／50.76 秒，后续渲染启动明显更快；首次读取慢尚未解决，不能把编辑器重复读取基准用于承诺玩家启动时间。详见性能记录中的实际发布证据与限制。
