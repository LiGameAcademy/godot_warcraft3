# 斜坡渲染规则对照与用户地图回归

更新：2026-09-13。本记录取代此前 RAMP_WE / HIVEWE_ALIGN 中关于 L 碗、外角补洞与中点污染容错的渲染结论。

## 对照来源

本地 `_ref/HiveWE` 提交 `b70f9b8ab888347894168bf139b21b60c2ac87ce`。直接阅读源码，未以此前的中文转述作为规则依据：

- [terrain.ixx](https://github.com/stijnherfst/HiveWE/blob/b70f9b8ab888347894168bf139b21b60c2ac87ce/src/base/terrain.ixx)：real_tile_texture、is_corner_ramp_entrance、update_ground_heights、update_ground_exists、update_cliff_meshes。
- [terrain_operators.cpp](https://github.com/stijnherfst/HiveWE/blob/b70f9b8ab888347894168bf139b21b60c2ac87ce/src/brush/terrain_operators.cpp)：输入与斜坡标记规则，用于识别当前笔刷扩展。

这是对公开 HiveWE 的行为对照，不是对未取得的暴雪原作源码的验证。

## 本次修复

1. 入口由四角坡旗与对角层高关系共同决定，地面保留、低角抬高 64 单位、直崖替换使用同一条件。删除无来源的 L 碗与外角邻域补洞代码。
2. 取消独立的对角挖洞操作；对角入口应该保留地面，不应再次被挖掉。
3. 坡体模型仅匹配列内一致、两列相反的旗位，取消中点污染容错，避免模型形状与地面洞口不对应。
4. 地表纹理先汇总附近悬崖/坡体覆盖，再查询当前角点的 cliffTextures；不从遍历到的第一个邻格借类型。坡旗只在附近没有 romp 时保留所画地表，15 仍映射为悬崖索引 1。
5. 对来源规则不成立的旧测试断言作了替换，保留原地形场景，改为对照地面存在、抬高与直崖替换的一致性。测试不再要求凭三个坡旗生成额外坡面。

## 验证证据

- `tests/unit/selftest_ramp_hivewe.gd`：1,296 组四角层高/旗位组合；64 种两列旗位；邻格类型与本角不同、坡旗优先级、romp 与 15 哨兵纹理。独立期望来自上述源码规则，PASS。
- `selftest_ramp_present.gd`、`selftest_ramp_logic.gd`、`selftest_ramp_data.gd`：PASS；Lost Temple 仍为 58 个坡体、116 个 romp 点。
- `selftest_ramp_brush_direction.tscn`：实际 D3D12 挂模、同格转向、预览方向、撤销重做、保存重开 PASS。拾取为可控替身，不是操作系统鼠标全流程。
- 用户提供的 `111.wc3map.json` 原样保存在 `tests/fixtures/editor/ramp-user-111.wc3map.json`，64×64，15 个坡旗。`ramp_user_visual.tscn` 用同一文档渲染，并检查 4,096 格地面保留是否符合对照规则，0 failures。
- 近景截图：`tmp/ramp-user-111-fixed.png`。原用户文件未写入，修复通过重新加载生效。可打开 fixture 重复操作。
- 系统仍输出证书存储读取错误；不将 PASS 表述为日志无任何错误。

## 范围与限制

本次对齐的是坡体收集、入口地面/抬高/直崖替换以及相关地表纹理优先级。笔刷仍有本项目的方向软化、低侧寻点和 L 形交互扩展；Shader 的自由高度插值与 Godot 模型转换沿用现有实现。尚不能据此声称所有地形、纹理滤波、原版编辑器输入行为或所有地图都完全一致。

复验：

```powershell
& 'C:/Users/Administrator/Desktop/Godot_v4.6.3-stable_win64_console.exe' --headless --path . --script res://tests/unit/selftest_ramp_hivewe.gd
& 'C:/Users/Administrator/Desktop/Godot_v4.6.3-stable_win64_console.exe' --path . res://tests/integration/ramp_user_visual.tscn
```

## 111 连续绘制后的接缝与纹理修复

新增原样复现场景 `tests/fixtures/editor/ramp-user-111-continued.wc3map.json`，18 个坡旗。此前的 15 旗 fixture 保留。

- 原版直崖 (34,30) 的不规则边缘与入口地面的线性边缘不重合，中间顶点形成三角裂口。`Wc3CliffStitcher` 仅调整与入口共享的直崖边缘，网格交点检查四个相邻单元；内部岩石轮廓、UV、三角连接和缓存源模型均保持不变。Shader 继续添加自由高度，CPU 只处理层高和入口抬高。
- 这是适配本项目较宽松的连续斜坡笔刷的接缝处理，**不是 HiveWE 原有算法的逐行移植**。受影响的模型需独立网格，可能增加绘制批次；未宣称所有复杂地形均已验证。
- 斜坡笔刷不再写入当前面板的悬崖纹理索引，与 HiveWE apply_ramps 保留纹理的行为一致。防止重新打开地图后，默认泥土选项将已有草地覆盖。
- 对比前后两份 111，仅能确认 (34,31)、(34,32) 两个 cliffTextures 从 1 被改成 0。`tmp/111-repaired.wc3map.json` 仅将这两个值恢复为 1，保留用户最新 18 个坡旗及其他全部数据；用户原文件未覆盖。截图 `tmp/111-repaired.png`。
- `selftest_cliff_stitcher.gd` 检查边界中点与角点高度、内部顶点、UV、索引、源网格不变以及无入口时复用源网格。
- `ramp_user_visual.tscn -- res://tests/fixtures/editor/ramp-user-111-continued.wc3map.json` 验证 4,096 格覆盖以及实际挂载直崖 (34,30) 接缝；修复副本同样检查。
- `selftest_ramp_brush_direction.tscn` 新增草地悬崖搭配泥土面板选项的连续绘制、撤销、重做、保存重开纹理不变断言。


2026-09-14：222 暴露未覆盖的坡体半层边界；新增共享周界计划，来源兼容范围与后续约束见 [RAMP_222_SEAMS.md](RAMP_222_SEAMS.md)。
