# Camera 试验版（2026-09-25）

本轮只调整游戏镜头，不改编辑器、HUD 布局、单位控制或玩法数据。目标是提供可运行、可对比的起点；尚未完成指定版本 Warcraft III 的同场景实机校准，不宣称 1:1 复刻。

## 行为与参数

- 垂直 FOV 从 70° 改为 50°，显式采用 Godot `KEEP_HEIGHT`。50° 是试验值，不是从 WC3 FOV=70 推导的转换公式。运行入口以 GameDirector.camera_fov 为准；Camera 脚本与场景默认值保持一致。
- 默认平移即时启动、即时停止；`pan_smoothing=0`。正数可恢复平滑，并改为时间步稳定的指数权重。
- 六档距离/俯仰数值保留，档间以 `zoom_duration=0.18` 秒缓动。快速连续滚轮从当前姿态重新过渡，不跳回上一档。设为 0 恢复直接切档。
- 地图就绪后向 RtsCamera 注入 Wc3Heightfield。目标高度取中心加四邻域的加权平均，半径 1.28 Godot 单位，再以速率 10 做时间平滑；瞬移定位直接使用新地点高度。边缘采样夹在高度场内。`terrain_follow_enabled=false` 可关闭。
- 默认 `focus_duration=0`，小地图点击即时定位；显式传入时长的开场/脚本聚焦保留缓动。聚焦只插值 XZ，避免覆盖地形跟随的 Y。
- 文本输入和窗口失焦期间不轮询相机移动，鼠标离开窗口时不继续触发边缘滚动。
- 游戏小地图显式按实际相机 FOV 估计视口框，不再使用共享工具默认的 40°。它仍是地形参考平面上的估计，不是逐像素可见性；HUD 遮挡与近水平射线回退没有改变。

## 并行修改范围

主要代码在 `apps/game/client/camera/rts_camera.gd`。GameDirector 只有默认 FOV 和地图就绪后的高度场注入两处接入；game_minimap 只改视口估算参数；rts_camera.tscn 只同步 FOV。没有改公共地图工具，也没有移动、改名现有模块或改变调用方的方法签名。

## 验证与复现

`tests/unit/selftest_rts_camera.gd` 覆盖启停、地形定位、边界、聚焦中断、连续缩放及两端限制。通过 `tools/workspace/test_apps.py --app game --case unit/selftest_rts_camera.gd --godot <exe>` 执行。

`tests/media/camera_comparison.tscn` 加载真实 Echo Isles 对局，在独立 1920×1080 SubViewport 内渲染。窗口最小化，禁用测试对局的对手 AI，冻结同一战场状态，依次使用旧镜头参数与新参数，刷新投影血条和小地图，保存到 `tmp/camera-review/before.png` 与 `after.png`。该对比重建的是旧镜头设置，其他模块使用当前工作区；不是旧版本完整游戏截图。

先用 `tools.workspace.test_apps.prepare` 准备该测试，再用真实渲染器运行游戏资源根中的 `res://tests/media/camera_comparison.tscn`，不加 `--headless`。截图程序同时检查真实地图接入、默认视野与小地图定位。

本次验证：Godot 4.6.3，摄像机专项 19 项、现有 match_input 回归 12 项、真实对局/截图检查 9 项，全部通过。D3D12 / RTX 2070 实际渲染的改前与改后截图已检查。运行环境报告证书存储读取和用户目录着色器缓存写入错误，未阻止对局加载及出图；未发现 GDScript 解析或运行错误。这里验证的是程序行为和渲染结果，不代表人工鼠标手感或原作一致性已验收。

## 后续人工对比

固定原作版本、地图坐标、分辨率与缩放档位，对比主城像素高度、地砖覆盖和目标屏幕位置。随后对比推屏停止、连续滚轮、小地图切换与坡地移动。HUD 有效战场中心、中键拖拽、原作地形滤波及各类定位快捷键留到后续独立改动。
