# 游戏内资产视觉问题与复验

记录游戏内资产问题、修复与手动复验；技术自测与原作视觉裁定分开记录。

## 修复与边界

| 问题 | 原因与处理 |
| --- | --- |
| 中立建筑背后的红色大板 | 部分源材质使用 `Textures/BackGround.blp`；主城另有仅在 Portrait 序列显示的四顶点队色板。编译时按纹理或源序列语义保留肖像背景标记；战场及 HUD 实例把对应网格渲染层设为 0，源显隐动画不会把它重新画出来。HUD 使用已有的背景控件。 |
| 建筑、英雄、新训练步兵保留红色 | 旧队色处理依赖外部 Shader 路径；新 SCN 使用内嵌 Shader。新的表现适配器按编译元数据处理队色底层、Team Glow 和单层 ReplaceableId=1 材质，修改前复制材质，两个实例互不影响。农民的队色底层使用 FilterMode=1、Shading=17，顶层使用 FilterMode=2、Shading=0；合成现在支持不透明的裁切底层与逐层单双面规则。透明底层仍保留诊断回退。 |
| 野怪队色 | 无固定覆盖的中立单位使用源 TeamColor 的暗灰贴图；仍遵循 UnitUI 的固定队色。例如部分中立商店明确设为红色，不能一并去色。 |
| 建筑外圈阻路 | 引用收集漏掉 UnitData 中的 pathTex，主建筑寻路贴图未导入，触发实心矩形兜底。补齐 UnitData 引用后使用源 TGA 的独立 RGB 通道：蓝色禁建、红色禁行，外圈不会因兜底变成实心障碍。 |
| 建筑肖像过小、背景遮挡 | 源 Camera 数据进入统一 IR，再嵌入 SCN；HUD 优先用源机位与视锥，播放已有 Portrait 序列。包围盒回退不计肖像背景及粒子。Camera 的平移、目标平移和旋转按当前 Portrait 的源时间区间采样，支持步进、线性、Hermite 和 Bezier 插值；全局 Camera 轨目前回退到基本机位。 |
| 一级主城显示升级层、脚手架 | glTF 为全局动画延长循环片段，新显隐编译曾因时长不等拒绝源 GeosetAnim。现在允许较长循环片段，并在其中重复新增的局部控制轨；保留原骨骼和全局动画，不截断旗帜等动画。新的显隐轨接管源零缩放隐藏状态。一级主城使用 Stand，其他等级和建造网格按源轨隐藏。 |
| 建造火光 | 新 SCN 已有源粒子，单位层不再额外挂旧 PE2 粒子。保持现有源效果与近似实现，本轮不调火光强度；形态仍需与原作对照。 |

新 SCN 的实例化绕过旧模型材质与特效启发式改写。旧资源继续使用原兼容路径。

队色合成用片段的 `FRONT_FACING` 判断单面顶层，基础 API 见 [Godot 空间 Shader 文档](https://docs.godotengine.org/en/4.4/tutorials/shaders/shader_reference/spatial_shader.html)。

## 测试开局

在现有启动参数末尾增加 `--asset-review`，会在本地基地旁加入牧师 `hmpr` 与大法师 `Hamg`；普通开局不增加单位。配置为 `apps/game/config/asset_review_start.tres`，便于调整位置。

需要使用本轮重新编译的场景缓存。旧 SCN 不含新肖像背景和 Camera 元数据，直接复用旧缓存不能验证这些修复。

## 本机测试构建启动

在 PowerShell 粘贴这一整条命令即可，不需要先定义 `$report` 或安装 Godot。路径对应本轮发布测试产物；后续重新运行全量测试时以新报告路径为准。

```powershell
& 'D:/GodotProject/laoli_gamedev_godot4_course/projects/blizzard-warcraft3/godot_warcraft3/tools/asset-convert/tmp/development-9beFl2/release/game.exe' --rendering-driver vulkan -- --asset-import-cache 'D:/GodotProject/laoli_gamedev_godot4_course/projects/blizzard-warcraft3/godot_warcraft3/tools/asset-convert/tmp/development-9beFl2/cache' --asset-review
```

## 手动检查

1. 先检查双方一级主城：只显示一级建筑，没有二三级外壳、脚手架和背景板；检查农场、兵营等建筑的 Stand 状态。再到雇佣兵营、地精商店附近，确认战场没有红色背景大板。
2. 检查农民的衣服、双方英雄和建筑的队色，再检查野怪使用中立暗灰队色；中立建筑的固定颜色以 UnitUI 定义为准。
3. 分别看两方主城、英雄；建兵营并训练步兵，确认队色跟随所属玩家。切换选择后再检查肖像颜色。
4. 开启寻路调试：建筑外圈应只有禁建标记。命令单位通过建筑之间的可通行间隙，并验证外圈仍不允许建造。
5. 选择主城和兵营，检查肖像构图及 Portrait 动画；切换到单位再切回，观察是否出现遮挡或残帧。
6. 用初始牧师和大法师攻击目标，检查投射物移动、循环、命中，以及英雄光晕；这些表现仍由你与原作裁定。
7. 建造建筑，记录火光与原作的差异，单独决定是否需要调强度。

## 开发者回归

```powershell
node --test tools/asset-convert/src/development-manifest.test.mjs tools/asset-convert/src/model-ir.test.mjs
python tools/workspace/test_apps.py --godot $env:GODOT --app game --case unit/selftest_compiled_model_presentation.gd
python tools/workspace/test_apps.py --godot $env:GODOT --app game --case unit/selftest_extended_sequence_controls.gd
node tools/asset-convert/src/game-development-import.test.mjs
```

完整发布测试保留普通 86 单位开局及 OpenGL 离线渲染检查，增加 Vulkan 测试开局：验证一级主城的原生显隐轨、真实背景网格、农民及运行时生成对象的队色材质、建筑源寻路贴图、初始测试单位，以及主城和兵营的 Camera/Portrait 序列。临时验收脚本另行生成步兵和兵营，检查运行时生成路径；不会改变普通或手动测试开局。

默认 D3D12 的本机阻塞仍未定位；当前手动验收明确使用 Vulkan。完整管线与干净机器的收尾边界见 [ASSET_PIPELINE_CLOSEOUT.md](ASSET_PIPELINE_CLOSEOUT.md)。

## 诊断日志边界

完整测试保留导入与渲染日志。此前目录恢复冲突和验收脚本类型错误均保留失败日志；修正后重跑，不能把中断尝试记成通过。离线测试临时禁用 Node 与输入 IR，现在用 finally 恢复，以免失败污染下一次验收。

默认旧资产库中的查看器集成夹具缺少 PriestMissile 与 FireBallMissile；用已编译 SCN 的 `--preview-report` 验证可避免依赖该旧库，但不会把旧库缺项改成已修复。新农民 SCN 的 Vulkan 查看器启动及 Shader 渲染检查通过。

## 本轮实际结果（2026-10-06）

最终报告为 `tools/asset-convert/tmp/development-rsKHf3/report.json`。完成全量重试：449 个 SCN、10,545 个内容文件，引用覆盖完整、0 场景缓存命中，后台导入约 797 秒。`retriedInterruptedImport=true`；这是保留历史中断记录的重试，不冒充全新空目录安装。

禁用随包 Node、移走 IR 后，离线 86 单位开局约 18.5 秒；OpenGL 实际渲染约 23.7 秒，Vulkan 测试开局及六组肖像截图约 34.3 秒。内容哈希约 7.05 秒、场景哈希约 2.44 秒；时间受机器负载影响。

截图已人工检查：一级主城、农民队色、主城及兵营肖像显示正常，没有大背景板或升级脚手架。自动检查覆盖双方农民、主城、英雄及运行时生成对象的真实队色材质；保留原生显隐轨、禁建外圈/禁行主体和建筑 Camera/Portrait 元数据。普通开局没有测试单位，`--asset-review` 才添加牧师及大法师。

源引用/IR 的 5 个 JS 测试、队色实例隔离与农民合成材质、延长循环/显隐/Camera 采样、肖像预热、寻路调试及实体行为回归通过。最终场景的查看器使用独立只读报告复验，日志位于 `tools/asset-convert/tmp/visual-fixes-viewer-final.log`。

渲染日志仍有少量 Godot `Parameter material is null` 提示及开发地形表缺项警告，本轮没有将它们标为已修复；实际地图、图标及上述图像检查通过。D3D12 阻塞、原作投射物/火光视觉裁定和干净 Windows 安装仍待独立验收。


## 大法师技能复验（2026-10-06）

### 本轮问题与处理

- 水元素圆柱是模型加载失败时的占位几何体。引用闭包此前漏掉 AbilityData 的 `UnitID1`～`UnitID3`，没有导入 `hwat`／`hwt2`／`hwt3` 使用的 WaterElemental 与肖像。现在按源技能表递归追踪召唤单位，三个等级共享模型但保留各自单位配置。
- 地面和附着技能仍进入旧 GLTF 材质修正、包围盒缩放和 PE2 重挂入口。新 SCN 已使用米制坐标并自带粒子，再次处理会重复缩小或修改原效果。技能现在按编译元数据直接实例化原场景；旧资产使用兼容入口。
- 暴风雪源模型包含五个发射器，原生编译曾跳过其中两个 Squirt 发射器。IR 现在保留精确爆发时间与粒子数，SCN 通过内嵌脚本和动画事件触发原生单次爆发。持续速率不用于替代爆发数。
- 技能网格使用的 Unfogged 标记现在编译为 Godot 对应属性；材质层及 Geoset 的 Hermite／Bezier 淡入淡出按 30 Hz 烘焙，仍保留源关键帧。Color-add Shader 支持透明度变化，避免只在末端突然熄灭。
- 暴风雪单次 Birth 不再被固定 1.35 秒寿命提前截断；有 Birth／Stand／Death 的传送落点按源序列切换并正常清理。
- 技能场景保持只读 PackedScene 缓存，开局准备时预读暴风雪和传送资源；每波落冰不再重新读取嵌入贴图的 SCN。循环设置复制到实例自己的 Animation，粒子和可变材质仍独占。

### 手动施法检查

使用上面的新构建命令，先关闭旧版本游戏窗口以避免检查错构建。新编译器和引用扫描会失效旧缓存，需要重新导入；不要手工删除本机所有资源目录。

1. 选择基地旁的大法师，按 F4 打开 GM 菜单，升至 10 级并解锁技能；关闭 GM 菜单。建议关闭地面网格和 Pathing 色块后检查画面。
2. 分别以水元素技能 1／2／3 级召唤。应看到水元素身体、出生动画、持续动画和正确的肖像，不能出现红色圆柱；继续检查移动、攻击和消散。
3. 连续施放暴风雪，观察落冰、着地爆发和消退。等冷却后再施放，检查每波是否仍有明显停顿。中途下达移动指令，检查引导中止且已有落冰正常消退。
4. 群体传送先观察施法者环，再检查出发位置的残留效果、落点光柱与符文，以及附近友军到达。取消施法后，施法者环和目的地预览应清理。
5. 对照原作同等级技能的形态、大小、密度、节奏和持续时间。粒子模拟、拖带及部分发光材质仍存在近似，技术测试不代表原作视觉已通过。

### 开发者证据

```powershell
node --test tools/asset-convert/src/development-manifest.test.mjs tools/asset-convert/src/particle-bursts.test.mjs
python tools/workspace/test_apps.py --godot $env:GODOT --app game --case unit/selftest_spell_fx_compiler.tscn
node tools/asset-convert/src/worker-spell-samples.test.mjs
node tools/asset-convert/src/game-development-import.test.mjs
```

最后两条命令需要设置实际的 `$env:GODOT`。独立真实模型测试检查水元素、暴风雪和三个传送模型；发布游戏验收通过真正的 AbilityCastController 执行三个等级召唤、两次暴风雪和群体传送，保留截图、帧耗时分位数与场景加载计数。帧耗时用于定位性能，受显卡、并行游戏实例和后台负载影响，不等于通用性能保证。

水元素的部分多层材质及纹理动画仍走兼容回退，诊断没有删除；源粒子模拟仍是 Godot 原生近似。传送的少量原本受光加色面采用无光近似，并保留 `fx_unlit_approximation`。原作视觉裁定保持待验收。

暴风雪命中的 FrostDamage 也改为原生 SCN 直读，并和地面特效一起提前缓存，保留源尺寸、动画与粒子。此前每个目标都会进入旧材质修正、网格重建和 PE2 重挂入口，导致周期性长帧。缓存实例化与动画初始化分项测量合计约 2 毫秒，未据此引入对象池。


### 本轮验收记录

新缓存位于 `tools/asset-convert/tmp/development-9beFl2/cache`，最终发布复验报告为同目录上一级的 `report.json`。全量导入完成 480 个 SCN、10,903 个内容文件，引用覆盖完整，场景缓存命中 0。完整后台导入约 1,701 秒；原始 `cold.json` 与失败尝试日志保留在 `full-import-attempt/`。此前中断后重试完成导入，不将其称为空目录一次成功。

最终复验重新导出最新游戏代码并复用上述已编译缓存，因此报告明确记录 `reusedColdImport=true`。测试临时禁用随包 Node、移走输入 IR，离线 86 单位开局、OpenGL 地图渲染、Vulkan 三等级召唤、连续暴风雪、群体传送及取消清理通过；Node 与 IR 在 finally 中恢复。导入结果和复验结果不能混为同一次冷启动。

命中特效优化前后的同机测量保留在 `profile-before-hit-fix/asset-review-spells.json` 与最终 `asset-review-spells.json`。优化前两次暴风雪的最长帧约 280／229 毫秒；最终复验约 72／70 毫秒。地面和 FrostDamage 场景加载计数施法前后均为 1。其他技能可能在自动治疗时首次加载，整局总计数增加不代表暴风雪重复读取。不同运行负载会影响结果，P95 仍约 50 毫秒，不能据此宣称完全消除卡顿。

截图检查确认水元素身体、传送光柱和符文可见；测试等待异步肖像加载后再检查三个等级肖像。水元素多层材质／纹理动画、粒子模拟及少量加色受光仍有上述近似。原作视觉保真、持续对局性能与干净 Windows 验收保持待确认。日志中的既有 Godot 空材质提示和退出资源告警也没有被本轮消除。

## 水元素出生与大法师施法无法结束（2026-10-06）

这是新管线动画元数据与游戏播放层之间的兼容回归。真实水元素 SCN 的 Birth 长约 1.067 秒、大法师 SCN 的 Spell 长约 2.7 秒，两段均保留 `source_looping=false`，导入结果正确。但 `AnimPlayback.play()` 只识别旧 `wc3_seq_looping`，播放时把两段改成 `LOOP_LINEAR`。循环动画不发出 `animation_finished`，因此已有 Birth → Stand 与施法姿态结束回调一直不能运行。

播放层现在优先读取 `source_looping`，保留旧标记兼容和战斗动画的显式单次播放策略。只有确实需要改变循环方式时才复制当前实例的动画库及目标动画，不修改共享模板。没有用出生动画时长决定召唤规则，也没有为此重新编译全部模型；现有 480 场景缓存可继续使用，需要更新并重启游戏程序。

新增 `selftest_anim_playback_looping.tscn` 验证源单次/循环标记、旧标记、结束信号、Attack 强制单次和 A/B/模板隔离。真实技能验收现在等待三级水元素切到 Stand、大法师退出 Spell，再观察至少一个 Birth 时长，确认没有重启出生阶段。上一轮只验证召唤模型、肖像存在，没有覆盖这两个结束切换；本轮补齐这一缺口。

手动复验使用本页上方 `development-9beFl2/report.json` 的发布程序和缓存，开启 `--asset-review`：

1. 选择初始大法师并学习水元素；使用 GM 升级/技能解锁方便测试。
2. 召唤后观察约 4 秒：水元素完成一次出生、进入正常待机；大法师退出施法姿态。
3. 继续观察 10 秒，水元素不反复出生；分别命令它和大法师移动、攻击，确认动作可以切换。
4. 升到二、三级技能重复召唤；再检查暴风雪引导结束和群体传送完成/取消后，大法师都能恢复操作。

实际复验：循环策略、技能编译、扩展序列控制和编译模型表现四项回归通过；最新独立游戏重新导出并复用 480 个 SCN，在禁用随包 Node、移走输入 IR 的条件下完成缓存启动、地图渲染和实际技能测试，报告 `failures=0`。`summon_transitions` 记录三个等级均为水元素 `Stand`、大法师 `Stand1`、`caster_spell_casting=false`，连续暴风雪、群体传送和取消清理通过。报告仍标记 `reusedColdImport=true`，本轮没有冒称重新完成全量冷导入。

本轮校验 10,903 个内容文件约 318.5 秒、480 个场景约 48.4 秒，路径安装约 2.8 毫秒；启动耗时明显偏高，仍需单独诊断。两次暴风雪最长帧约 114／79 毫秒，整个技能测试最大帧约 895 毫秒、P95 约 55.5 毫秒，不能宣称消除卡顿。测试等待已改为累计游戏帧时间，并保留实际墙上时间帧耗时和超时保护；此前墙上时间等待导致的长帧误判日志保留在 `animation-loop-validation-attempts/`，原先复验报告保留在 `before-animation-loop-fix/`。退出资源/空材质告警及原作视觉对照保持原有待确认状态。
