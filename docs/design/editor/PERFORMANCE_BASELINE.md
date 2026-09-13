# 编辑器性能基线（优化前）

日期：2026-09-13。此结果明确表明地形编辑响应尚不达标，不是性能验收通过记录。

后续纯纹理优化与同样例复测见 [地表纹理局部更新](TERRAIN_INCREMENTAL.md)。本页保留优化前数值，原 JSON 已备份至 tmp/editor-performance-before-texture.json。

环境：Intel Core i7-9700KF 3.60GHz、NVIDIA GeForce RTX 2070、Windows、Godot 4.6.3、D3D12 Forward+、1280×720、VSync enabled。

| 固定负载 | 64×64 / 100 对象 | 256×256 / 1,000 对象 |
| --- | ---: | ---: |
| 原版对象构成 | 80 LTlt / 20 hpea | 800 LTlt / 200 hpea |
| 地图表现构建（含单位队列完成） | 3,388 ms | 23,934 ms |
| 单文件保存 | 83 ms | 1,211 ms |
| 文档解析加载（不含表现重建） | 52 ms | 636 ms |
| 地表编辑 CPU 重建 P95 | 514 ms | 7,667 ms |
| 中心视角旋转平均 FPS | 60.0 | 60.3 |
| 帧间隔 P95 | 16.85 ms | 16.84 ms |
| Godot 静态分配器内存 | 182.8 MB | 326.6 MB |
| 占位模型 | 0 | 0 |

测量工具：`tests/integration/editor_performance.tscn`；结果 JSON 为 `tmp/editor-performance.json`，日志为 `logs/editor-performance.log`，保存的测试地图为 `tmp/editor-benchmark-64.wc3map.json` 和 `tmp/editor-benchmark-256.wc3map.json`。每组地表更新 20 次，预热 10 帧后采样视角旋转 90 帧。对象位置按固定公式生成；首轮地表变体沿用创建逻辑的随机变体，精确样例以保存文件为准。

```powershell
& 'C:/Users/Administrator/Desktop/Godot_v4.6.3-stable_win64_console.exe' --path . --log-file ./logs/editor-performance.log res://tests/integration/editor_performance.tscn
```

范围限制：编辑耗时是 paint_corner + 同步 rebuild_terrain_only 的 CPU 时间，不含输入到屏幕呈现总延迟；浏览只测中心近距视角；文档加载与表现构建分别计时；内存不是进程 RSS 或显存；场景构建是在编辑器初始启动之后；本次没有将低于目标的结果改写为通过。

原暂定小图编辑响应 ≤100 ms，目前仅 CPU 阶段就达 514 ms，因此 E08 未满足。小图保存/加载各 ≤5 s、中心浏览 ≥30 FPS 的本次样例指标达到，但不能覆盖全部操作和视角。

代码证据：MapLoader.rebuild_terrain_only 每次创建上下文、计算拓扑并调用 MapTerrainLayer.build，后者清空网格、逐格重新生成全部顶点与材质数组。单顶点地表绘制仍走全图路径。下一步应区分纯纹理更新、高度更新和拓扑变化，更新受影响网格区域，保持悬崖/斜坡/水与碰撞正确，再用同一规模与保存样例复测；不能通过关闭必要表现或缩小地图来掩盖问题。
