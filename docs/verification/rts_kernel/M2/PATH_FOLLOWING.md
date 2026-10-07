# 目标路径跟随与 Godot 隔离入口

日期：2026-10-07。对应内核 Issue [#3](https://github.com/LiGameAcademy/rts_kernel_cs/issues/3) 的第一批实现，内核 PR [#6](https://github.com/LiGameAcademy/rts_kernel_cs/pull/6)。基础导航 PR #4/#5、游戏同步 PR #4 和验证修正 PR #6 已合并。本批在两个仓库的 `codex/issue-3-path-following` 分支开发。

## 交付范围

内核执行 MoveTo、Stop 和目标替换；路径经八方向 A* 生成，逐段消费每帧移动预算并精确到达世界坐标目标。动态占地成功变化后重新寻路，不可达则停止并产生 MoveFailed；到达产生一次 MoveCompleted。Godot 输入只提交命令，模型位置取自内核状态。

快照升级为 v3，新增移动目标、速度、净空、路径与索引，恢复后按相同命令继续计算。拒绝 v1/v2，暂不迁移。地图仍由宿主提供并校验身份。API 与限制见 [内核移动说明](../../../../external/rts_kernel/docs/MOVEMENT.md)。

新增 `apps/game/scenes/rts_kernel_navigation_probe.tscn` 隔离演示场景；主游戏没有切换到该场景，既有正式单位移动仍由旧 gameplay 负责。该场景直接渲染逻辑帧位置，暂未加入显示插值。

## 验证记录

Windows，.NET 10 SDK，内核 Release，Godot 4.7.2 Mono 实际加载当前 Debug。构建零警告、零错误。

- 内核 1337 项断言通过，覆盖绕墙、精确到达、所有权、停止/替换、动态重规划、阻断失败、待执行移动恢复、移动中逐帧恢复与哈希续跑、路径校验及差异报告；包括前两批导航检查。
- 游戏内容转换 4 项检查通过。
- Godot 移动 15 项检查通过：原生 CLI/Godot 移动状态哈希一致、移动快照恢复、新桥接恢复、不同步进批量收敛、失败恢复不破坏现有状态、演示场景加载、点击移动、S/R 恢复和空格停止。
- 原有 Godot 桥接 24 项检查使用当前 v3 Debug 与本轮 CLI 哈希再次通过。
- 依赖边界及负面夹具通过；本批自有代码均低于 500 行，最大 231 行。

```powershell
./tools/workspace/Test-GodotKernelBridge.ps1 -GodotConsole 'D:/GameMaker/Godot_v4.7.2-stable_mono_win64/Godot_v4.7.2-stable_mono_win64_console.exe' -Configuration Release -TestCase integration/selftest_rts_kernel_navigation.gd -CliArguments '--navigation'
./tools/workspace/Test-GodotKernelBridge.ps1 -GodotConsole 'D:/GameMaker/Godot_v4.7.2-stable_mono_win64/Godot_v4.7.2-stable_mono_win64_console.exe' -Configuration Release
python tools/workspace/check_kernel_layout.py
python tests/kernel/test_dependency_layout.py
```

本次原有桥接回归在资源已同步后直接 prepare 测试、重新构建 Debug 并启动 headless Godot，传入本轮 CLI 实际输出哈希 `5a7dbd57e66c4bfbe3f2b36014567eff4c7ca1b40826c8a433e4f4d583585e6a`；上方脚本是可重复完整入口。验证脚本保留 Release 编译，但额外构建 Debug 供实际 Godot 加载，并从当前 CLI 提取基准。

Godot 退出仍报告 3 个 ObjectDB 实例与 2 个资源被占用，两组测试断言通过且退出码为 0。该报告在本批之前已存在，来源尚未定位；不能将日志称为完全无错误。自动输入验证直接调用场景输入入口，未替代人工窗口操作和手感验收。

## 演示操作与后续

以 Mono 编辑器打开 `apps/game/project.godot`，打开并运行 `scenes/rts_kernel_navigation_probe.tscn`。左键点击墙对侧应绕到墙下方并抵达格子中心；空格停止；S 保存当前帧，移动后 R 恢复。点击墙格或地图外的命令应不改变既有移动。测试速度参数由隔离宿主提供，正式玩法必须来自权威单位定义。

Issue #3 保持开放。转向、坡度、命令排队、组队落点分配、预约、单位间避让、追击与正式单位接入仍需分批开发；这一批不标记完整移动与战斗闭环完成。出生与障碍增删仍为诊断入口，没有生产/建造权限、资源支付和挤出规则。300/500 性能基线及 Windows 导出继续暂缓。
