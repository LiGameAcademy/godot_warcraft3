# 地表纹理局部更新

2026-09-13。本轮只优化纯地表纹理笔划及其撤销/重做，未宣称高度、悬崖、斜坡编辑已经达到性能目标。

## 实现

TerrainBrush 收集实际改变纹理的顶点；MapTerrainLayer 将顶点扩展为相邻四格，复用现有角点纹理规则和层混合计算，更新对应六顶点的 UV/CUSTOM0/CUSTOM1 属性块。构建时记录每格对应的首顶点，悬崖挖洞格没有顶点则跳过。HeightfieldMesh 使用当前 surface format 查询 stride/offset，不修改顶点、法线、索引、碰撞或共享材质。

实现参考 Godot 的 [RenderingServer 属性步长与偏移接口](https://docs.godotengine.org/en/stable/classes/class_renderingserver.html)；代码对预期的未压缩格式进行检查，不匹配时退回完整重建。

PaintStrokeCommand 只有在高度、水高、层、标记和悬崖字段均未变化时，才允许撤销/重做走这条路径。有斜坡挖洞/高度补偿/romp 数据时继续完整重建，避免只更新地面而漏掉独立斜坡网格。新文档设置会清空笔刷待更新顶点。

## 正确性证据

`tests/integration/selftest_terrain_texture_update.tscn` 在实际 D3D12 渲染器运行，通过以下对照：边角及内部顶点局部绘制后与完整重建的 vertex、normal、UV、CUSTOM0、CUSTOM1、index 数组逐项相等；反向修改仍相等；局部更新保留 mesh 身份；斜坡挖洞拒绝局部路径。

`tests/integration/selftest_editor_preview.tscn` 已增加真实编辑器回调检查：笔刷刷新、撤销、重做不替换 mesh，权威纹理正确恢复；后续预览与返回保护测试仍通过。两项均 PASS、退出码 0；系统证书读取错误仍单独记录。

## 同样例复测

使用上轮保存的两张地图（`--reuse-fixtures`），CPU/GPU/分辨率不变。纯纹理局部更新每组 20/20 次成功，无缩小样例或隐藏对象。

| 指标 P95 | 64×64 / 100 对象 | 256×256 / 1,000 对象 |
| --- | ---: | ---: |
| 优化前地形重建 CPU | 514.133 ms | 7,667.299 ms |
| 局部纹理更新 CPU | 0.459 ms | 0.532 ms |
| 编辑器回调含小地图刷新 | 43.344 ms | 599.428 ms |

浏览约 60 FPS；保存/加载分别为小图 89/49 ms、大图 1,517/635 ms。新结果 `tmp/editor-performance.json`，旧结果 `tmp/editor-performance-before-texture.json`，新日志 `logs/editor-performance-texture.log`。

```powershell
& 'C:/Users/Administrator/Desktop/Godot_v4.6.3-stable_win64_console.exe' --path . --log-file ./logs/editor-performance-texture.log res://tests/integration/editor_performance.tscn -- --reuse-fixtures --texture-update
```

下一步：大图小地图刷新仍带来约 599 ms 的回调耗时；高度/悬崖/斜坡仍需局部更新或其他完整保真优化。当前测量不含完整鼠标输入至画面呈现延迟，不能将 0.5 ms 当作整个编辑器响应时间，也不能标记整体 E08 完成。

## 后续：小地图脏区域刷新

已将 MapMinimapRaster.rasterize_dirty 从全图重绘改为真实矩形区域更新。纯纹理操作复用 Inspector 缓存，按顶点更新像素，随后仍立即更新 256×256 显示图。像素计算沿用原有崖、水深、不可玩区域规则，Y 翻转与非方形地图留边保持不变。初次生成或更换地表颜色目录会完整失效；新地图/非纹理修改继续完整刷新。

`selftest_minimap_dirty.gd` 对照逐像素字节：角落、内部、水色、地图边界、重复和越界脏矩形、无脏数据、首次生成、更换颜色目录，以及非方形显示缩放均通过。`selftest_editor_preview.tscn` 的实际笔刷、撤销和重做回调后，小地图也与独立完整刷新相等；D3D12 集成测试 PASS。

同一保存样例、硬件、分辨率、20 次更新复测：

| 指标 P95 | 64×64 / 100 对象 | 256×256 / 1,000 对象 |
| --- | ---: | ---: |
| 底层局部更新 | 0.472 ms | 0.629 ms |
| 编辑器回调含即时小地图刷新 | 1.025 ms | 1.284 ms |

复测日志 `logs/editor-performance-minimap.log`，新 JSON `tmp/editor-performance.json`，上一阶段 JSON `tmp/editor-performance-before-minimap.json`。此处优化没有通过隐藏小地图或延后刷新来规避成本。测试仍只覆盖纯纹理 CPU 回调，不等于所有地形工具、全流程输入延迟和原版视觉的验收。

待办更新：小地图纯纹理刷新瓶颈已消除；高度、悬崖、斜坡的全图更新成本与大图初始表现构建仍需优化。

## 高度重建：避免重复应用空斜坡遮罩

2026-09-13：为 MapLoader.rebuild_terrain_cliffs_water 增加分段 CPU 计时，保存在 last_terrain_rebuild_timings。64×64 / 100 对象固定样例中，地面构建约 228 ms，斜坡阶段另耗约 221 ms；斜坡阶段即使没有实际挖洞或抬高，也会再次构建整张地面。

MapTerrainLayer.apply_ramp_dig 现对比合成后的地面挖洞遮罩、入口高度提升及过渡纹理遮罩；效果未变时不重建。空遮罩和全零遮罩视为等效。真正新增、清除洞口或高度提升仍会重建。

同一硬件（i7-9700KF / RTX 2070、Godot 4.6.3、D3D12）及同一 `tmp/editor-benchmark-64.wc3map.json`，10 次高度修改的结果：

| 指标（CPU，中位数） | 优化前 | 优化后 |
| --- | ---: | ---: |
| 地面及坡崖过滤 | 227.690 ms | 231.544 ms |
| 斜坡阶段 | 220.894 ms | 42.812 ms |
| 完整地形重建 | 500.360 ms | 327.031 ms |
| 最大单次总耗时 | 514.410 ms | 335.884 ms |

总耗时下降约 35%，仍未满足 100 ms 编辑响应门槛。这里计量 MapLoader 的 CPU 重建，不包含全部编辑器回调、小地图刷新或鼠标到屏幕的延迟；10 个样本用于瓶颈定位，不作为全面性能验收。

`selftest_ramp_mask_update.tscn` 实际 D3D12 测试 PASS：全零遮罩保持 mesh 身份、挖洞移除一格、相同遮罩不重建、清除后顶点/法线/索引/纹理数组恢复一致、入口高度提升和清除仍正确。日志 `logs/ramp-mask-update.log`；性能原始数据 `tmp/editor-height-profile-before.json`、`tmp/editor-height-profile.json`。所有运行仍有系统证书读取错误。

```powershell
& 'C:/Users/Administrator/Desktop/Godot_v4.6.3-stable_win64_console.exe' --path . --log-file ./logs/editor-height-profile-optimized.log res://tests/integration/editor_height_performance.tscn
& 'C:/Users/Administrator/Desktop/Godot_v4.6.3-stable_win64_console.exe' --path . --log-file ./logs/ramp-mask-update.log res://tests/integration/selftest_ramp_mask_update.tscn
```

性能脚本需要既有 64×64 固定样例；仅在内存中修改高度，不覆盖样例地图。

## 地面构建：复用共享顶点与纹理层组合

2026-09-13 后续优化：每次构建内，地形格点的位置与角点纹理只计算一次，不再由相邻四格各算一遍；相同四角纹理和变体的 LayerSlots 复用。所有缓存仅存活于该次构建，避免地图高度、纹理、悬崖和斜坡改变时跨次复用旧值。

`terrain_reference_builder.gd` 保留优化前的独立网格循环作为数值对照。`selftest_terrain_build_cache.tscn` 在三种混合高度/纹理/悬崖层/挖洞/斜坡入口提升输入下，对比全部顶点、法线、UV、自定义纹理通道和索引，D3D12 测试 PASS（0 failures）。

固定 64×64 / 100 对象、10 次高度重建的实测结果见 `tmp/editor-height-profile.json`；此次优化前的数据保存在 `tmp/editor-height-profile-before-corner-cache.json`。地面阶段中位数由 231.544 ms 降至 120.338 ms，整体中位数由 327.031 ms 降至 218.422 ms（本次最大值 232.184 ms），仍未达到 100 ms 门槛。仍是 MapLoader CPU 重建范围，不是完整编辑响应延迟。

```powershell
& 'C:/Users/Administrator/Desktop/Godot_v4.6.3-stable_win64_console.exe' --path . --log-file ./logs/terrain-build-cache.log res://tests/integration/selftest_terrain_build_cache.tscn
```


## 四边形写入临时数组与通道批量追加

HeightfieldMesh.add_quad 直接写入六个顶点，避免每格为两个三角形重新创建位置和 UV 数组；完整 RGBA 自定义通道通过 append_array 追加，短/长通道仍按原规则补齐或截取。保留退化法线回退和自定义 UV 行为。

terrain_reference_mesh.gd 保留优化前 quad/vertex 写入实现；selftest_terrain_build_cache 增加自定义通道开关、默认/完整/短长通道、自定义 UV、退化三角形的全部 mesh 通道对照。与三种地形组合对照一起在 D3D12 下 PASS（0 failures）。

固定 64×64 / 100 对象、10 次高度重建：地面阶段中位数 99.874 ms，总耗时中位数 194.286 ms，最大值 202.353 ms。前次总耗时中位数 218.422 ms。此次前后数据为 tmp/editor-height-profile-before-mesh-append.json 与 tmp/editor-height-profile.json，运行日志 logs/editor-height-profile-mesh-append.log。仅为 CPU 重建计时，仍未满足 100 ms 编辑响应目标；系统证书日志错误仍存在。


## 无斜坡地图跳过斜坡规划扫描

MapRampLayer 在确认所有地形点没有 FLAG_RAMP、收集结果没有 placement 且 romp 全零时，跳过 dig/diagonal/entrance/boost 规划。仍清除旧斜坡模型、统计值及地面的旧挖洞/抬高遮罩，因此删除最后一条斜坡不会残留洞口。存在任一标记或收集结果时继续走原有规划。

selftest_ramp_mask_update 已扩展验证无标记状态清除既有模型、洞口和抬高，所有顶点/法线/索引/纹理通道回到原始结果；重复空斜坡更新不替换 mesh。实际 D3D12 测试 PASS（0 failures）。

同一 64×64 / 100 对象、10 次重建，斜坡阶段中位数 0.334 ms，整体中位数 151.493 ms，最大 155.750 ms；上一阶段整体中位数为 194.287 ms。原始前后数据为 tmp/editor-height-profile-before-empty-ramp.json 与 tmp/editor-height-profile.json，日志 logs/editor-height-profile-empty-ramp.log。仍未达到 100 ms 目标，也未计入完整编辑器交互延迟。本次性能运行仍有系统证书与退出 ObjectDB 警告。


## 四边形批量写入试验（未采用）

2026-09-13：尝试将四边形的位置、法线、UV 和索引分别整组 append_array，替代六次顶点写入。独立参考实现的全部网格通道对照通过，但固定 64×64 / 100 对象的 10 次重建未测出收益：地面阶段中位数由 99.864 ms 变为 101.139 ms，整体由 151.493 ms 变为 155.892 ms。单轮结果不足以证明稳定回退，但也不支持保留额外改动，因此撤回本次批量四边形试验，保留直接六顶点与 RGBA 批量追加实现。

前后原始记录分别为 `tmp/editor-height-profile-before-quad-bulk.json`、`tmp/editor-height-profile-quad-bulk.json`；日志 `logs/editor-height-profile-quad-bulk.log`。`tmp/editor-height-profile.json` 仅代表最后一次测量，不能将其自动视为当前实现的基线。性能门槛仍未通过。


## 无斜坡时跳过标记入口计算

斜坡调试显示在无 FLAG_RAMP 时直接返回，仍清理上次标记。扫描将 JSON 数字显式转为整数，避免导入地图中的浮点数触发位运算错误。新增回归覆盖浮点旗数组、首次标记、删除最后标记及释放旧节点。

固定样例 10 次重建的 overlays 中位数由 18.962 ms 降至 0.256 ms，总耗时由 151.493 ms 降至 138.446 ms，最大 142.900 ms。结果为 `tmp/editor-height-profile-debug-empty-fixed.json`，日志 `logs/editor-height-profile-debug-empty-fixed.log`，仍有系统证书错误，未达到 100 ms 门槛。此数据测于后续斜坡绘制修复之前，不能代表有斜坡地图的性能。
