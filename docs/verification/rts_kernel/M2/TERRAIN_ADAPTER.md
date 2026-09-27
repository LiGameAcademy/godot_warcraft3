# R02.1 静态地图适配首批

日期：2026-09-28。R02.1 状态：部分完成。

## 本批实现

新增普通 net8.0 内容转换工程 `packages/rts_content`，依赖方向为 Content → Kernel。宿主读取文件，转换器接收 JSON 文本，内核只持有不可变的行优先网格与高度数据。Godot 场景树、资源类型与文件路径不进入内核。

- `PathingGrid` 保留 WC3 XY 原点、格宽、全部阻挡位；地面可走性检查 0x02，越界不可走。输入数组复制，可选阻挡数组按位 OR 合并。
- `TerrainHeights` 使用已有 heights 数组及双线性插值；输入必须为有限数字，越界显式返回 false。
- `ParsedTerrainReader` 支持 pathing 的 cellsBase64/cells，以及 terrain-heightfield 的 tilepointWidth/tilepointHeight/tileSize/centerOffset/heights。
- CLI 的 `--map <目录>` 可直接加载现有解析数据，无需 Godot。

## 验证

`tools/workspace/Test-RtsKernel.ps1`：54 checks 通过，构建 0 警告、0 错误；新增 12 项覆盖负原点、上边界、非有限坐标、阻挡叠加、数组隔离、两种编码、高度插值及坏数据拒绝。

```powershell
dotnet run --project apps/kernel_cli/Rts.Kernel.Cli.csproj --no-build -- --map assets/map-parsed/echoisles
```

本机 Echo Isles 加载成功：pathing 512×384、格宽 32；heightfield 129×97、格宽 128。真实资源保留在既有本地资源目录，不加入版本库。架构检查 `check_kernel_layout.py` 通过。

SDK 10.0.301 在新增项目后的并行 restore 曾无诊断失败；沿用既有单节点 build 策略，为 restore 也加 `-m:1` 后通过。

## 行为差异与剩余工作

旧 `Wc3Heightfield.interpolated_height` 在最右/最上边缘可能跨行取样或返回 0；新实现将边缘归入最后一个有效四边形。该差异有专门测试，接入旧地形表现时需要对照，不直接替换旧函数。

原始 pathing.json 不包含全部运行时建筑/装饰物叠加。当前虽有合并缓冲区入口，但尚未从 Godot 导出阻挡层；不得把原始网格称为完整可走性。出生点、移动参数、地图内容哈希、对局绑定及快照地图身份也尚未实现。真实寻路与单位移动权威未切换。

按用户确认，性能基线及 Windows 导出暂缓，后续继续补齐；这一调整允许推进 M2，不视为 G0 已通过。
