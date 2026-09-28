# RTS 内核独立仓库拆分

日期：2026-09-28。

独立公开仓库：[Liweimin0512/rts_kernel_cs](https://github.com/Liweimin0512/rts_kernel_cs)。默认分支 `main`，MIT 许可证，版权归属 `2026 李维民`。中文及英文 README 明确早期开发状态、已实现能力与未实现范围；API 仍可随重构变化。本次不发布 NuGet 包或正式版本。

## 职责与历史

- `external/rts_kernel`：Git 子模块，包含纯 C# 内核、纯内核测试、最小 CLI 示例、独立构建脚本和 Windows CI。
- `packages/rts_content`：留在游戏仓库，负责 WC3 JSON 地图内容到内核数据的转换。
- `apps/kernel_cli`：保留现有工程名称，现为游戏地图转换 CLI；使用 `--map` 指定解析后地图目录。
- `tests/kernel`：游戏内容转换测试与依赖边界负面夹具；纯内核检查已转移到子模块。
- Godot 桥接、游戏资产管线和集成场景继续留在游戏仓库。内核不依赖它们。

从游戏提交 `05cf2b0a01b529535601765b72f1bbee3581cda5` 提取相关路径历史，保留作者、时间与提交说明，过滤后的提交哈希发生变化。映射见独立仓库的 [docs/history-map.txt](https://github.com/Liweimin0512/rts_kernel_cs/blob/main/docs/history-map.txt)。旧历史中的宿主可能引用未提取的游戏内容工程，因此不保证历史上的每个提交可独立构建；当前发布提交已完成独立构建验证。游戏原仓库历史未重写。

首次接入固定提交：`4df1103647ea498b2e0050f2a4fdc6344253883c`。后续实际版本以游戏仓库记录的子模块提交为准。

## 初始化与开发

在游戏仓库根目录执行：

```powershell
git submodule update --init --recursive
./tools/workspace/Test-RtsKernel.ps1
./tools/workspace/Test-GodotKernelBridge.ps1 -GodotConsole 'D:\GameMaker\Godot_v4.7.2-stable_mono_win64\Godot_v4.7.2-stable_mono_win64_console.exe'
dotnet run --project apps/kernel_cli -- --map assets/map-parsed/echoisles
```

工具链为 .NET 10 SDK、Godot 4.7.2 .NET 版；内核类库保持 net8.0，独立 CLI 与测试目标为 net10.0。纯内核测试为控制台断言程序，使用子模块 `Test.ps1`，不是 `dotnet test`。地图转换命令还需要本机已生成的地图数据。

子模块通常检出在游戏记录的具体提交。修改内核前，在子模块内从该提交创建开发分支；完成后先提交并推送内核，再在游戏仓库提交新的子模块指针及相关适配改动。不要让游戏指向仅存在于本机的内核提交。

更新依赖时，在子模块中获取远端并检出明确的目标提交，运行上述验证，再在游戏仓库提交 `external/rts_kernel` 指针。普通克隆和同步使用 `git submodule update --init --recursive`，不自动追踪远端最新版本。

## 验证结果

- 独立 Release 构建：零警告、零错误；纯内核 53 项检查通过，最小 CLI 状态哈希与拆分前一致。
- 从远端克隆的实际子模块：内核 53 项、游戏内容转换 4 项、Godot 桥接 23 项检查通过。
- Echo Isles 静态地图读取成功：寻路网格 512×384，高度场 129×97。
- 依赖边界检查及负面夹具通过。
- 独立仓库首次 [Windows CI](https://github.com/Liweimin0512/rts_kernel_cs/actions/runs/36366141090) 成功，验证提交为上述固定提交。

Godot 运行时仍出现既有的 Windows 根证书提示，本次本地桥接检查通过。用户已暂缓的 300/500 单位性能基线及 Windows 导出验证保持待办；这些结果不代表完整玩法、性能目标或发行包已经验收。本次仅推送内核仓库，游戏仓库迁移提交保留在本地。
