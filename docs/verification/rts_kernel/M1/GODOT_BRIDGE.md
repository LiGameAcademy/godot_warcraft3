# M1 Godot C# 桥接验证

日期：2026-09-28。状态：已验证。

## 边界

- `Rts.Kernel` 仍是 `net8.0` 普通类库，不引用 Godot。
- `apps/game/godot_warcraft3.csproj` 是 Godot 4.7.2 的 `net8.0` 宿主，只在这一层引用 `Godot.NET.Sdk` 和内核。
- `RtsKernelBridge` 是当前唯一跨语言入口。GDScript 提交不可变命令，通过一次批量读取取得实体表现镜像；不取得或修改 `RtsMatch`、`EntityState` 等内核对象。
- 事件从桥接信号单向流向 Godot。当前隔离切片没有把旧节点状态同步回内核。

## 隔离切片

`apps/game/scenes/rts_kernel_bridge_probe.tscn` 是 M1 专用验证入口：

1. GDScript 创建对局并提交生成命令。
2. C# 内核以固定 30 Hz 推进测试实体。
3. 方向键提交速度命令，空格提交停止命令。
4. `Polygon2D` 只读取批量视图并更新位置；没有模型资源时内核仍可推进。

该场景不接管主游戏单位，避免旧 `UnitNavigator` 与新内核同时写位置。它只证明桥接闭环，不代表寻路已经迁移。

## 重复验证

```powershell
tools/workspace/Test-GodotKernelBridge.ps1 `
  -GodotConsole "D:\GameMaker\Godot_v4.7.2-stable_mono_win64\Godot_v4.7.2-stable_mono_win64_console.exe"
```

当前结果：

- Godot C# 工程恢复、编译成功，0 警告、0 错误。
- 纯内核测试：PASS，42 checks；其中包含快照规范校验和字段级首差异报告。
- `selftest_rts_kernel_bridge.gd`：PASS，23 checks；覆盖命令、批量镜像、事件信号、CLI/Godot 哈希对照、双实例交错推进和宿主销毁后重建。
- 隔离场景 headless 运行 10 帧，无脚本错误。
- Godot 仍报告无法读取 Windows 根证书库；本次只使用本地 SDK 包和本地资源，未影响验证。

## 尚未覆盖

- Windows 导出产物。
- 主游戏真实单位的移动权威切换。
- 不同绘制频率下对完整主游戏命令日志的长时间逐帧哈希对比。
- Godot 宿主销毁、重建及快照恢复的长时间压力验证；当前只覆盖短流程。

R01.1–R01.5 已有最小实现及上述短流程证据；不同 Step 批次的收敛测试不替代实际绘制频率验证。M1 的前置门 G0 仍等待 300/500 单位基线与 Windows 导出验证；editor 产品隔离已验证，见 `../M0/PRODUCT_LAYOUT.md`。
