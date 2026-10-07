# 静态寻路、动态占地与格子净空

日期：2026-10-07。功能分支 `codex/issue-2-dynamic-navigation`，内核 Issue [#1](https://github.com/LiGameAcademy/rts_kernel_cs/issues/1)、[#2](https://github.com/LiGameAcademy/rts_kernel_cs/issues/2)。静态查询 PR [#4](https://github.com/LiGameAcademy/rts_kernel_cs/pull/4) 尚待人工合并，本批以其分支为基础继续开发。

## 实现范围

纯 C# 内核提供静态八方向 A*、禁止穿墙角、稳定同代价排序；本批增加沿用 `PathQuery.can_walk_cell_clear` 的 Chebyshev 格子净空，以及每场对局独占的矩形动态占地。静态地图保持只读；重叠障碍单独计数，同 ID 替换先完整校验，非法更新不破坏原占地。

测试用 SetObstacle/RemoveObstacle 命令通过固定逻辑帧执行，使用现有命令排序与拒绝事件。它们暂不代表建筑权限或资源支付。公开查询经 RtsMatch 读取当前帧状态；宿主不能直接修改占地数组。

内核完整接口及示例见子模块 [docs/NAVIGATION.md](../../../../../external/rts_kernel/docs/NAVIGATION.md)。内核远端已迁移到 `LiGameAcademy/rts_kernel_cs`，宿主子模块 URL 同步更新。

## 快照兼容

快照升级为 v2，不接受 v1，未实现跨版本迁移。新快照保存动态障碍、待执行命令载荷及静态 PathingGrid 内容身份。恢复有导航的快照时必须提供相同地图；身份覆盖尺寸、格距、原点及阻挡字节，不覆盖尚未接入的高度场与单位定义。非法快照在新实例构造时拒绝，不影响原对局。

CLI 帧号、实体位置与此前一致，校验哈希因快照格式变化而更新。未来真正的移动参数、路径跟随状态和其他内容身份仍需随迁移加入快照。

## 验证

使用 .NET 10 SDK，Windows，Release；Godot 4.7.2 Mono。

- 内核 1027 项断言通过；静态检查包含全部 512 种 3×3 障碍布局与独立 Dijkstra 代价对照。
- 动态检查覆盖窄路净空、地图边界、重叠增删、非法替换原子性、对局隔离、快照 JSON 往返、地图不匹配、待执行命令恢复、差异字段定位及 40 轮动态更新与独立静态栅格对照。
- 游戏内容转换 4 项检查通过。
- Godot 桥接 23 项检查通过，既有无地图骨架可保存并恢复 v2 快照；不代表本批已经向 Godot 暴露动态障碍命令。
- 依赖边界及负面夹具验证通过；相关自有代码文件均低于 500 行。

验证命令：

```powershell
./tools/workspace/Test-GodotKernelBridge.ps1 -GodotConsole 'D:/GameMaker/Godot_v4.7.2-stable_mono_win64/Godot_v4.7.2-stable_mono_win64_console.exe' -Configuration Release
python tools/workspace/check_kernel_layout.py
python tests/kernel/test_dependency_layout.py
```

Godot 退出时报告 3 个 ObjectDB 实例及 2 个资源仍被占用，桥接测试断言通过且退出码为 0；本批未定位该清理报告来源，不把运行日志称为完全无错误。后续涉及 Godot 生命周期时需核查。

尚未实现单位沿路径移动、在途重规划、转向、预约、避让与实际建造占地。R02.1/R02.2 未整体完成；后续按 [Issue #3](https://github.com/LiGameAcademy/rts_kernel_cs/issues/3) 分批接入，主游戏移动仍由旧实现负责。300/500 性能基线与 Windows 导出仍按用户确认暂缓。
