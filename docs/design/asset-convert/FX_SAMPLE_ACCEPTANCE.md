# 新管线投射物与光晕验收

本轮生成三个真实来源样本，不覆盖旧 `assets/asset-converted`，不修改游戏加载路径。结果仍为 `deliverable=false`，等待查看器和游戏内双重视觉验收。

## 打开样本

在仓库根目录用 PowerShell 执行，路径对应当前开发机器，无尖括号占位符：

```powershell
$env:GODOT = 'D:/GameMaker/Godot_v4.7.2-stable_mono_win64/Godot_v4.7.2-stable_mono_win64_console.exe'
node tools/asset-convert/src/worker-fx-samples.test.mjs
& $env:GODOT --path apps/asset_viewer -- --preview-report 'D:/GodotProject/laoli_gamedev_godot4_course/godot_warcraft3/.cache/fx-preview/report.json'
```

测试命令读取 `.cache/wc3-assets`（可用 `ASSET_SOURCE` 改写），重建样本并执行独立项目重载、动画切换和资源隔离检查。原版资产缺失会失败，不自动跳过。场景、纹理、IR 和结果日志位于 `.cache/fx-preview`，只保存在本机。

左侧只有三条记录，初始选中牧师投射物。切换记录不会重新烘焙。`--preview-report` 只影响本次会话，不改写项目设置。

## 手动检查

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
- 动态速度／重力、全局控制轨、Squirt 爆发和锁轴 billboard 遇到时记录未支持。Ribbon 有明确诊断，本批三个模型不含 Ribbon，下一批仍需真实 Ribbon 样本。
- 技术检查覆盖独立项目重载、发射开关复位、朝向中心不漂移、地面骨骼不变及 A/B 材质和粒子参数隔离。渲染截图证明当前样本可显示，不能代替原作对照验收。

下一步先收集本批视觉反馈，再处理 Ribbon 和绕法线旋转／拖尾误差，之后进入已规划的导出游戏内导入验证。
