# 游戏内资产视觉问题与复验

本轮针对 2026-10-05 游戏截图中的六项问题；技术自测与原作视觉裁定分开记录。

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
& 'D:/GodotProject/laoli_gamedev_godot4_course/projects/blizzard-warcraft3/godot_warcraft3/tools/asset-convert/tmp/development-rsKHf3/release/game.exe' --rendering-driver vulkan -- --asset-import-cache 'D:/GodotProject/laoli_gamedev_godot4_course/projects/blizzard-warcraft3/godot_warcraft3/tools/asset-convert/tmp/development-rsKHf3/cache' --asset-review
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
