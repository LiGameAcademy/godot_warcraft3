# 操作尖峰：测量与优化（2026-09-25）

## 摘要

在保持玩法与画质不变的前提下，本轮针对「点选 / 训兵 / 出生 / 开工」等交互尖峰做了三层落地，并用同一 Echo Isles 基准把前后数字卡死：

1. **动态脚印增量**：无 `pathTex` 的普通单位不再触发整图刷新；`PathQuery` 与路径叠层按分块快照只重算变化区。
2. **生产 UI 合并**：同一帧内的队列变更只刷新一次 HUD / 命令卡。
3. **开局肖像预热**：加载阶段用真实模型离屏渲染，把首次选择的 Surface 管线编译从「点选时」挪到「进局前」。

后续已定位并处理开局首次选择的肖像管线准备尖峰，见文末「首次选择专项修复」。下方第一批结果保留为当时的测量记录。

## 范围与方法

基于 11edb7c 工作区，保留原有未提交文档。Godot 4.7.2，同一 Echo Isles 开局，固定出生位置，禁用对手经济/军队推进，加载后暂停世界模拟。保留原场景开启的路径地面叠层。

扩展 `tests/integration/benchmark_match_hotpaths.gd`：`--interactions` 依次选择农民、主城、请求训练、直接调用训练出生入口、直接调用开工入口，每项重复 6 次。首次与后续分开；出生、工地每轮清理。不是完整的农民到达工地流程，也不是持续对战帧率测试。

记录同步调用耗时、后续四次 process_frame 的时间间隔，以及嵌套热点。各优化前后串行运行三次。下列事件窗口指标：先取每次操作四个间隔的最大值，再计算每轮后五次操作的中位数，最后取三轮中位数。P95 为每轮五个事件最大间隔的 nearest-rank P95，再取三轮中位数；小样本下它就是每轮最大值，不代表长时间游戏 P95。

暂停模拟也暂停了肖像轮询，因此无渲染对照不能覆盖首次肖像加载。新增 `--live-portraits` 单独启用肖像轮询，并等待挂载完成（15 秒上限）；有渲染诊断使用这个选项。耗时样本最多保留 2048 个。

## 已测结果

- 普通单位出生：事件窗口中位值 **157.949 → 18.159 ms**；事件 P95 **180.042 → 21.086 ms**。
- 开工：事件窗口中位值 **247.629 → 59.457 ms**；事件 P95 **266.271 → 76.496 ms**。
- 训练入队：同步处理中位值 **10.796 → 3.492 ms**；事件窗口中位值 **14.084 → 16.089 ms**，事件 P95 **23.282 → 20.396 ms**。UI 工作部分移入同帧延迟合并，不能只看同步值宣称整帧同幅下降。
- 选择农民：同步处理 **3.816 → 5.044 ms**，事件窗口 **7.138 → 15.710 ms**。
- 选择主城：同步处理 **4.249 → 3.908 ms**，事件窗口 **9.443 → 15.514 ms**。

选择操作没有稳定收益，优化后普通帧间隔也更大；未证明整帧 P95 不退化。仍需隔离后台负载和固定帧节奏的持续对战对照，不能将这些无渲染数字换算成 FPS。

热点样本合并后的中位数：开工寻路准备 **77.821 → 1.013 ms**；动态脚印绘制 **39.135 → 38.736 ms**；含叠层与寻路准备的刷新 **228.490 → 41.730 ms**。训练生产 UI 通知从每次 2 次降为 1 次（首次原有 3 次），其累计耗时 **7.164 → 3.162 ms**。

原始输出在本地 `tmp/interaction-before*.log`、`tmp/interaction-optimized-*.log`，汇总在 `tmp/interaction-comparison.json`；tmp 不提交。

## 有渲染诊断（优化后，两次运行）

保持项目默认分辨率、D3D12 / Forward+，设备 RTX 2070，不降低画质。使用 `--live-portraits`；这是优化后诊断，没有渲染前后对照，也没有真实对战镜头路线。

- 首次选择农民的事件最大帧间隔分别为 **1393.071 / 1750.939 ms**，后续选择回到约 17 ms。
- 第二次运行的同步选择约 **32.592 ms**，肖像挂载 **6.654 ms**、设置 **0.640 ms**、预载轮询 **0.078 ms**。这些 CPU 埋点解释不了秒级停顿。资源加载、渲染同步或驱动等待需要继续剖析，不能直接认定是 GLTF 解析或 shader 编译。
- 第二次首次选择窗口读取到主视口渲染 CPU 最大 **1.757 ms**、GPU 最大 **5.423 ms**。这是有限窗口内的视口计时，不能覆盖所有线程等待，也不能据此排除 GPU/驱动相关阻塞。
- 第一次有渲染检查中，开工首次约 **194.533 ms**，后五次事件最大间隔中位值 **91.859 ms**，仍有明显尖峰。
- 两次均完成 30 个操作，未出现脚本错误；退出时出现 **1 个 ObjectDB 实例未释放警告**，尚未归因。不能据此认定持续对战内存泄漏，也不能忽略后续生命周期排查。

日志：本地 `tmp/interaction-render*.log`（含 errors / engine 日志）。

## 实现

1. 普通移动单位无 pathTex 时，出生/移除不再刷新整张动态阻挡和叠层。判定沿用 Catalog 的脚印规则，而非硬编码单位名单；建筑仍刷新。
2. PathQuery 保留不同净空的 AStarGrid2D。分块比较动态字节快照，只重算变化区域及净空外扩格；静态数据变化或大范围动态变化仍走全量构建。直接修改格子也能检测，不引入帧缓存或预约语义变化。
3. 路径叠层复用 Image 和 ImageTexture，比较分块快照，仅重写变化像素；保持原颜色、Y 翻转、遮挡标志和开关。
4. ProductionModule 不再将同一次 `_begin_active` 的 queue_changed 和 training_started 重复转发。ProductionPanel 合并待处理队列、弱引用防止已移除队列访问；入队请求通过同一 UI 更新入口。
5. 在选择、训练、出生、开工、动态阻挡、寻路准备、肖像挂载/初始化/预载轮询中补充默认关闭的 MatchHotpathMetrics。子项耗时嵌套，不能相加当成总耗时。

## 验证

新增 `selftest_interaction_hotpaths.tscn`：92,192 个断言，覆盖分块边界、动态添加/撤销、不同净空、边缘、非行走标志、静态直接修改、像素颜色与计数、纹理复用、普通单位/建筑脚印识别，以及队列事件合并和释放后的延迟回调。

既有测试通过：path_click_latency、production_module、units_module、command_card_module、hud_layout、portrait_shutdown、build_module_game、module_bindings_game。目录依赖检查通过。未运行 30 分钟持续对战，未验证整帧 P95 不退化。

## 仍需处理

- 动态脚印仍重新遍历全图单位和装饰物，约 39 ms；下一步应为静态装饰脚印与动态建筑脚印建立独立缓存，并正确处理重叠脚印的撤销。
- 模型首次加载、实例化和首次渲染仍可能形成尖峰；需要资源预热和受预算控制的实例准备，不能只用 call_deferred 假定已经跨帧。
- 选择单位尚未解决。不能宣称本轮消除了全部卡顿。

## 复现

```powershell
python tools/workspace/sync_packages.py --app game --test integration/benchmark_match_hotpaths.tscn
& $Godot --headless --path apps/game res://tests/integration/benchmark_match_hotpaths.tscn -- --interactions
# 有渲染诊断，保留项目画质、分辨率，暂停世界但允许肖像加载：
& $Godot --path apps/game res://tests/integration/benchmark_match_hotpaths.tscn -- --interactions --live-portraits
python tools/workspace/test_apps.py --app game --godot $Godot --case unit/selftest_interaction_hotpaths.tscn
```


## 首次选择专项修复

### 定位

增加 idle 对照、正常选择、禁用肖像的诊断分支、仅显示肖像，以及 RenderingServer 管线编译计数。三个分支独立启动同一场景，保持 D3D12 / Forward+、原画质和分辨率：

- 正常选择：最大事件帧间隔 1803.012 ms，Surface 编译增加 4 次。
- 仅诊断时跳过肖像：30.068 ms，Surface 编译增加 0 次。
- 单独显示肖像：1655.655 ms，Surface 编译增加 4 次。
- 提前渲染空肖像视口：首次真实选择仍为 1318.215 ms，没有解决。
- 提前实例化并在隐藏视口渲染实际肖像：准备 hpea、htow、Hamg 耗时 3120.652 ms；随后首次选择为 31.989 ms，Surface 编译增加 0 次。

这将秒级尖峰定位到真实肖像首次进入渲染场景后的管线准备。并不是选中逻辑或肖像轮询中的秒级 GDScript 执行。Godot 官方说明 Surface 管线可能在模型首次进入场景时编译，预加载资源本身并不保证完成这一工作；参见 [管线编译卡顿](https://docs.godotengine.org/en/stable/tutorials/performance/pipeline_compilations.html)。

### 实现与成本

- 对局加载阶段收集当前本地玩家已有单位的类型，通过 SelectionHudModule → GameHud → SelectionDetailsPanel → UnitPortraitView 准备肖像。
- 使用原模型、原灯光、原材质、原视口，隐藏 HUD 内容但执行离屏渲染；等待脚本挂载和实际渲染完成，然后保留实例供第一次选择复用。仅创建空视口的方案未采用。
- 沿用最多 10 个实例的池容量，15 秒单类型等待上限；无渲染模式跳过 GPU 准备。异步加载失败时沿用原有肖像加载/回退行为，不永久阻止开局。
- 加载屏显示“准备单位显示…”。准备期间暂停对局子树，预热完成后恢复原 process_mode，再触发 session_ready，避免 AI 或玩家提前开始操作。
- is_session_ready 现在同时要求地图业务装配和表现准备完成；原 _bootstrapped 仍防止重入。
- 取消、离树、依赖重绑会使旧任务失效；重绑清理旧模型池。准备过程不发送选择事件、不发命令、不显示临时肖像。

这里将必要的一次性渲染准备移入加载阶段，而非消除其成本。实测会增加几秒加载时间；首次遇到尚未准备的新单位类型、Mod 材质或新的渲染特性，仍可能有资源加载或管线准备尖峰。没有降低肖像画质，也没有改 AI 更新频率。

### 复现开关

```powershell
# 原首次选择路径（诊断用）：
& $Godot --path apps/game res://tests/integration/benchmark_match_hotpaths.tscn -- --interactions --live-portraits --selection-probe --probe-all-starting --skip-portrait-warmup
# 正常预热后的首次选择：
& $Godot --path apps/game res://tests/integration/benchmark_match_hotpaths.tscn -- --interactions --live-portraits --selection-probe --probe-all-starting
```

`--no-portrait`、`--portrait-only`、`--warm-empty-portrait`、`--warm-real-portrait` 仅属于基准隔离实验，不改变正常游戏默认设置。原始记录位于本地 `tmp/selection-*.log` 与 `tmp/portrait-cold-*.log`、`tmp/portrait-warm-*.log`。


### 最终对照与回归

同一机器、同一场景和图形配置，交替启动关闭预热与开启预热的独立进程；未清空驱动缓存。每组 3 次成功样本，每次只统计该进程的首次选择事件窗口最大帧间隔：

- 农民，关闭预热：2038.171 / 1918.929 / 1325.777 ms，中位 **1918.929 ms**。
- 农民，开启预热：32.472 / 32.341 / 34.847 ms，中位 **32.472 ms**。
- 主城，关闭预热：105.094 / 105.657 / 99.169 ms，中位 **105.094 ms**。
- 主城，开启预热：27.998 / 28.198 / 28.837 ms，中位 **28.198 ms**。
- 农民首次选择的 Surface 编译新增数：关闭时三次均 4，开启时三次均 0；Draw 编译新增数均为 0。

仍有约 17 ms 的首次命令卡处理；本轮针对的是秒级肖像尖峰，不等于保证每次操作都小于 16.7 ms。数据来自暂停世界、保留真实渲染的诊断场景，不是持续对战的整体 FPS，也不代表其它显卡或 Mod 内容。

六次原始对照中，第三次预热组在 MapUnitLayer._place_one_internal 的 add_child 阶段发生了一次 signal 11 原生崩溃，此时尚未进入对局肖像准备。保留 `tmp/portrait-warm-3-errors.log`，该次不作为成功测量；单独补跑 `portrait-warm-3-retry` 成功。崩溃尚未归因，不能宣称启动稳定性全部通过。此前有渲染测试出现的单个 ObjectDB 退出警告仍存在。

通过的回归：

- 新增 portrait_warmup：无渲染 8 项、有渲染 11 项断言，检查就绪门槛、隐藏预热、模型池复用、取消、依赖替换，以及不擅自恢复对局处理模式。
- portrait_shutdown：6 项；selection_hud_module：6 项；HUD layout。
- module_bindings_game：30 项。
- match_end_game --restart：无渲染和有渲染均通过 23 项，验证新局完成准备并恢复处理。
- 目录依赖检查通过，原有未提交文档保留。

selection_hud_module 的旧测试替身未包含现有 bind_inventory 的 read_only 参数，已修正其签名后复测通过；没有为迁就测试改变生产接口。

## 提交阶段对照

| 阶段 | 内容 | 主要代码 |
|------|------|----------|
| A | 动态脚印 / 寻路面增量刷新 | `path_query.gd`、`map_pathing_layer.gd`、`map_loader.gd`、`units_module.gd` |
| B | 训练队列 UI 同帧合并 | `production_module.gd`、`production_panel.gd` |
| C | 开局肖像离屏预热 | `unit_portrait_view.gd`、`selection_hud_module.gd`、`game_director.gd` |
| D | 交互基准、自测与本文档 | `benchmark_match_hotpaths.gd`、`selftest_interaction_hotpaths*`、`selftest_portrait_warmup*` |
