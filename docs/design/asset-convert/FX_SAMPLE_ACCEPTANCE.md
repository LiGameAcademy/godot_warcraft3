# 新管线投射物与光晕验收

本轮生成三个真实来源样本，不覆盖旧 `assets/asset-converted`，不修改游戏加载路径。结果仍为 `deliverable=false`，等待查看器和游戏内双重视觉验收。

## 打开样本

在仓库根目录用 PowerShell 执行，路径对应当前开发机器，无尖括号占位符：

```powershell
$env:GODOT = 'D:/GameMaker/Godot_v4.7.2-stable_mono_win64/Godot_v4.7.2-stable_mono_win64_console.exe'
$env:ASSET_SOURCE = Join-Path $PWD 'assets/.staging/wc3-assets'
node tools/asset-convert/src/worker-fx-samples.test.mjs
& $env:GODOT --path apps/asset_viewer -- --preview-report (Join-Path $PWD '.cache/fx-preview/report.json')
```

测试命令默认读取 `.cache/wc3-assets`；上述命令用 `ASSET_SOURCE` 指向当前仓库的 `assets/.staging/wc3-assets`，重建样本并执行独立项目重载、动画切换和资源隔离检查。原版资产缺失会失败，不自动跳过。场景、纹理、IR 和结果日志位于 `.cache/fx-preview`，只保存在本机。

左侧只有三条记录，初始选中牧师投射物。切换记录不会重新烘焙。`--preview-report` 只影响本次会话，不改写项目设置。

## 手动检查

牧师的原始 MDX 本来包含鸟形网格、`Textures/Sentinel.blp` 和两组 owl 骨骼；不能把鸟形轮廓本身认定为导入变形。2026-09-29 根据截图反馈确认 `Stand` 循环标记此前未写入场景，现从 IR 恢复源动画循环设置：`Stand` 自动循环，`Birth/Death` 保持单次。最终帧静止截图不能替代连续播放及原作对照。此修正不等于宣布外观保真通过。

后续循环异常排查又修正两处转换缺陷：曲线采样此前忽略 DontInterp/Hermite/Bezier，旋转也只做归一化线性插值；现在分别保持离散值、使用向量曲线和四元数球面曲线。循环末帧此前被取模替换成首帧，导致最后一个采样区间提前回弹；现在保留源末帧。离散骨骼跳变以相邻 1 微秒的 glTF 采样键保留，避免被拉成一段线性渐变。

验证：`node tools/asset-convert/src/anim-interpolation.test.mjs` 对牧师源动画的 3,500 个采样点与 `war3-model` 独立插值器比较，最大分量向量误差约 2.4e-7；同时检查生成 glTF 的末帧和跳变边界。真实场景测试检查三轮循环后同一相位的全部骨骼姿态一致，Footman 回归通过。这些检查不代表所有特效已与原作画面完全一致。

1. **PriestMissile**：播放 `Stand`，检查蓝色发光体和拖尾，没有黑色贴图方块。切换 `Death` 检查短暂蓝色散射；回到 `Stand` 应恢复飞行效果。
2. **FireBallMissile**：播放 `Stand`，检查火球、发光片和烟雾；切换 `Death`，飞行发射器关闭、爆炸发射器短暂开启；回到 `Stand` 应恢复。它是大法师攻击投射物，不是大法师单位模型。
3. **HeroArchMage**：检查脚下地面光晕和杖尖光晕。旋转摄像机，地面光晕保持在地面平面，杖尖光晕保持可见。切换玩家颜色，两处光晕应一起变色。
4. 大法师切换 `Attack-1`、`Spell`，检查发射位置随手杖动画移动；`Walk` 检查尘土。切回 `Stand1`，前一动画的发射器不能一直开启。
5. 检查深／浅背景、正面／顶面视角、暂停、重播和循环开关。帧定位能定位骨骼和发射开关，**不能反向还原已消散的粒子**；判断完整效果时使用重播。

反馈请附模型、动画、摄像机方向、队色及重播后的时间点。游戏内还需验证投射物移动、命中、销毁、遮挡和多个实例同时显示；静止预览无法验证移动中的拖尾距离。

## 覆盖与边界

- IR 保留静态 billboard 骨骼，补充粒子纹理及父级运动采样。发射开关、速率、范围和运动写入动画。
- 区分网格 Additive（SRC_COLOR/ONE）与 AddAlpha（SRC_ALPHA/ONE），组合 Geoset 颜色／透明度。粒子使用独立的 FilterMode 映射，复用现有粒子材质构建器。
- 粒子为原生 `GPUParticles3D`，图集、三阶段颜色／尺寸和双头尾绘制随场景保存，没有运行时 JSON 读取。
- 相机朝向使用 `.scn` 内嵌的 SkeletonModifier3D，保留动画后的中心和缩放；同一 Geoset 内的地面光晕不跟着镜头转。
- 当前保留原作叠层光晕几何，没有宣称全部光晕已重构。朝向会替换来源骨骼旋转，尚未恢复绕法线自转；火球部分材质按无光照近似。粒子轨迹采样为 30 Hz，尾部为速度对齐面片，均有日志。
- 粒子的动态速度／重力、全局控制轨、Squirt 爆发和锁轴 billboard 遇到时记录未支持。新增 Ribbon 样本和边界见下节。
- 技术检查覆盖独立项目重载、发射开关复位、朝向中心不漂移、地面骨骼不变及 A/B 材质和粒子参数隔离。渲染截图证明当前样本可显示，不能代替原作对照验收。

## 第二批：Ribbon 拖带（2026-09-29）

新 worker 增加回春术 `RejuvenationTarget`（3 条）、复活 `Resurrecttarget`（4 条）和碎片投射物 `FragMissile`（1 条）。IR 记录上下端点、父级运动、寿命、速率、颜色、透明度、显隐和图集槽；SCN 内嵌纹理、材质、动画和运行脚本，无需旧项目的 Ribbon 脚本或 JSON。

在项目根目录 PowerShell 执行：

```powershell
$env:GODOT = 'D:/GameMaker/Godot_v4.7.2-stable_mono_win64/Godot_v4.7.2-stable_mono_win64_console.exe'
node tools/asset-convert/src/ribbon-ir.test.mjs
node tools/asset-convert/src/worker-ribbon-samples.test.mjs
& $env:GODOT --path apps/asset_viewer -- --preview-report "$PWD/.cache/ribbon-preview/report.json"
```

建议先看 **RejuvenationTarget → Stand**，点击重播，观察绕行拖带，再测试暂停、继续、倒退帧和切换 Birth/Death。真实源模型的上下宽度分别沿发射器局部 Y 轴变换，不能改成面向摄像机的统一半宽。静止投射物不保证有可见长尾：FragMissile 必须移动才能留下世界空间路径，自动测试覆盖这一点。

复活样本用来核对复杂父节点运动和动态宽度；其其他网格还有 `material_feature_pending` 和 `geoset_color_pending`，画面中可能有不透明片，**整个模型尚未视觉验收**。

技术证据：592 个复活拖带端点与 `war3-model` 独立源渲染器比较，最大误差约 4.2e-7 米。独立项目仅复制 SCN 和测试脚本，覆盖动画驱动、世界空间历史、暂停、倒退、切换动画、停发寿命和双实例资源隔离。旧三项 FX 样本回归通过。

当前限制明确记录为 `ribbon_sampling_approximation`：

- 端点轨迹采样 30 Hz；发射点在相邻实际更新之间插值。
- 暂停时间轴冻结历史；倒退、循环、切换动画或一次前跳超过 0.25 秒清空历史，避免连接无关姿态。小幅向前拖帧视为时间推进，不能重建跳过的精确历史；需要完整效果时重播。单次动画结束后历史随时间轴冻结，尚未实现独立于动画的收尾时钟。
- Ribbon 全局控制轨、重力、多层材质、动态纹理／材质透明度和其他混合模式尚未支持，发射器跳过并记录 `ribbon_controls_pending`。父节点全局运动已经参与端点采样；支持 Blend、Additive、AddAlpha。
- 不追加旧实现的假路径点、统一半宽、尾部额外淡出。旧牧师光球替换属于增强表现，不能混入 fidelity；独立 enhanced 编译仍待实现。

下一步收集视觉反馈并处理朝向／拖尾剩余误差，然后进入导出游戏内创建、保存、重载资产的验证。上述技术通过不替代原作及游戏内验收。
