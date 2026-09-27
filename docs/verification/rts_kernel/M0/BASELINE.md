# M0 基线记录

日期：2026-09-27。状态：进行中。关联路线图：[RTS_KERNEL_ROADMAP.md](../../../roadmap/RTS_KERNEL_ROADMAP.md)。

## 冻结版本

- 基线提交：`0bd6ca19160c522c058be73637f62c5b7f80cac7`（RTS 设计与路线图已提交）。
- 启动流程前置提交：`26b0d5c`；专项自检 9 项通过，应用 smoke test 通过。
- 操作系统：Windows NT 10.0.26100.0。
- .NET SDK：10.0.301；运行时：Microsoft.NETCore.App 10.0.9。SDK 10 已实测可恢复并编译 `net8.0`。
- Godot：使用用户指定的 `D:/GameMaker/Godot_v4.7.2-stable_mono_win64`，版本 `4.7.2.stable.mono.official.ed1daf0bf`；其 GodotSharp 工具与插件运行配置目标为 `net8.0`，并自带 `Godot.NET.Sdk.4.7.2.nupkg`。
- 版本分层：`Rts.Kernel` 目标为 `net8.0` 供 Godot 加载；当前 PC 的 CLI 与测试宿主目标为 `net10.0` 并引用同一内核。不能把宿主目标升级解释为内核可以改成 net10。

## 冻结地图

- 游戏默认入口：`apps/game/scenes/game_main.tscn`。
- 配置路径：`res://assets/map-parsed/echoisles`，经 ContentPaths 解析为仓库外置资产根下的 `assets/map-parsed/echoisles`。
- 地图数据：13 个文件，2,394,319 bytes。
- 目录指纹：将按相对路径排序的 `relative-path + space + lowercase(file SHA-256)` 以 LF 连接并在末尾加 LF，再做 SHA-256；结果为 `14fd9321d4e8ec19ebf15461134ca3b13f85da2ca4f8a748f9ffa76d9c8dd3f8`。
- 关键输入哈希：`pathing.json` 为 `cc965d97f48009f7dbf8554dee5a79560ab39c20f0412c5c69595199925e9e88`；`terrain-heightfield.json` 为 `153bd0eecdca0b2dd9b05df5d0fe320faad6f10044691bfca6a713b15982941f`；`units.json` 为 `cc4a83acd2bcce27119932921b2da251c8e6cee21d0d1c1c3c68ed9d1475b6ca`。

该目录指纹是本次基线的证据，不是未来内容哈希协议。M1/M2 的规范化地图哈希需要独立定义。

## 已运行回归

统一使用 `C:\Users\Administrator\Desktop\Godot_v4.6.3-stable_win64_console.exe`，由 `tools/workspace/test_apps.py` 同步并在 `apps/game` 资源根运行。

- `unit/selftest_command_request.tscn`：PASS，11 checks。
- `unit/selftest_entity_behavior.tscn`：PASS，16 checks。
- `unit/selftest_content_snapshot.tscn`：PASS，14 checks。
- `unit/selftest_c_combat_projectile.gd`：PASS。
- `unit/selftest_combat_module.tscn`：PASS，12 checks。
- `integration/selftest_match_end_game.tscn -- --restart`：PASS，23 checks。
- `tests/unit/selftest_boot_flow.gd`：PASS，9 checks。
- 游戏 `--smoke-test`：PASS；启动时报告 2 个玩家、20 个阵营、86 个单位。
- 另用 Godot 4.7.2 Mono 重跑 `tests/unit/selftest_boot_flow.gd`：PASS，9 checks。

Godot 每次启动报告无法读取系统根证书库，但上述测试退出码均为 0，未影响本地资源测试。该环境问题不计作 Gameplay 基线失败；涉及网络或远程下载时必须重新评估。

## 未完成的 M0 证据

- 尚无满足路线图定义的 300/500 活跃单位固定压力夹具；现有 `benchmark_match_hotpaths.tscn` 侧重交互热路径，不能替代移动、混战、采集建造三类基线。
- 尚未运行全量 game/map_editor 套件；本页仅证明所列关键用例。
- Godot Mono 可执行文件已找到并验证版本；M1 仍需在实际 C# Godot 项目中完成加载与导出验证。

## 首个内核骨架

- `Rts.Kernel` 已建立为无 Godot 引用的 `net8.0` 类库。
- CLI 与测试宿主使用本机现有 `net10.0`，均引用同一内核程序集。
- 初版包含固定 30 Hz Step、EntityId、稳定命令排序、显式事件、可保存随机流、JSON 快照/恢复和状态哈希。
- `tools/workspace/Test-RtsKernel.ps1` 是当前统一验证入口。
- 初版测试 37 项通过；覆盖固定帧移动、过期命令拒绝、待执行命令与随机流快照、恢复后逐帧一致、双实例交错推进和执行期拒绝事件。
- SDK 10.0.301 对混合 net8/net10 解决方案并行构建会无诊断失败；验证脚本暂时使用 `-m:1`。单项目构建和单节点解决方案构建均为 0 警告、0 错误。

M0 的退出门 G0 必须在补齐性能夹具/基线和 Godot .NET 工具链验证后才可通过。
