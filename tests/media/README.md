# 导航开发日志取景入口

`navigation_capture.tscn` 加载真实游戏场景，在本次演示中固定出生位置、关闭对手经济与军队自动行为、关闭地面调试层和边缘滚屏，选中农民并定位镜头。移动和寻路仍由游戏原有逻辑处理。

同步：`python tools/workspace/sync_packages.py --app game --test media/navigation_capture.tscn`

使用本机 Godot 运行：`Godot --path apps/game --resolution 1280x720 res://tests/media/navigation_capture.tscn`

准备完成后输出 `CAPTURE_READY`，并将初始截图保存到项目的 `tmp/devlog-navigation-media/01_game_overview.png`。右键下达移动命令；F9 切换路径线。录制时保持游戏窗口前台，避免其他窗口遮挡。

本次使用 FFmpeg 对游戏客户区进行录制。D3D12 下按窗口标题的 GDI 抓取曾产生黑屏，因此实际使用已核对位置的客户区区域抓取；屏幕坐标随窗口与显示器布局变化，重新录制前必须重新确认。录屏为视觉素材，不用于帧时间测量。

成品在 `tmp/devlog-navigation-media/deliverables/`，这些媒体不纳入 Git。生产入口与用户编辑中的 HUD 场景不受此入口影响。

## Panku 旧版对照

`navigation_comparison.tscn` 复用取景入口，并自动打开 Panku Expression Monitor。F6 启动三秒倒计时，以真实 CommandRouter 对初始首个可控移动单位下达固定目标（起点 + `(0, 1024)`）的命令。该场景两版均返回不可达，专门展示失败搜索时的主线程阻塞，不代表所有地面点击。

通过 `-- --variant BEFORE --result-dir <绝对输出路径>` 指定标签及结果目录；当前版使用 AFTER。两版使用同一份回放脚本、种子、HUD、素材及引擎，旧版在独立 worktree 中运行。完整结果位于 `tmp/devlog-navigation-media/comparison/`。

Panku 展示的 `demo.command_ms()` 为同步命令调用的墙钟耗时，不含鼠标拾取。`demo.frame_peak_ms()` 为下单开始至返回两秒后的 `_process` 回调最大墙钟间隔，包含录屏和系统调度影响；不是纯寻路耗时。即时 FPS / process / physics 只是上下文。脚本不修改寻路实现、不注入延时、不改变时间倍率，每次启动仅回放一次。
