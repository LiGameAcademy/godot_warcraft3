# 资产查看器

独立 Godot 项目，复用 `foundation/content/map` 共享包和外部资产目录。它直接加载现有 `.scn`，不会隐式转换、重新 bake 或叠加投射物增强。手动切换玩家颜色时调用与游戏相同的队伍色处理。

## 启动

在仓库根执行：

```powershell
# 首次准备 Node 依赖；已安装时可跳过
npm --prefix tools/asset-convert install
# 生成全量审计报告，仅读取源和转换资产
npm --prefix tools/asset-convert run audit
# 同步共享包；首次创建本机外部资产配置
python tools/workspace/sync_packages.py --app asset_viewer
# 用与游戏一致的 Godot 版本打开
& $env:GODOT --editor --path apps/asset_viewer
```

也可直接打开本目录 `project.godot` 后运行。审计默认读取仓库 `.cache/wc3-assets`、`.cache/manifest.json`、`assets/asset-converted`、`assets/slk-exported`；路径可通过 `audit -- --source ... --converted ... --manifest ... --slk ... --out ...` 指定，相对路径以调用目录为准。

查看器的资产路径来自 `override.cfg` 中的 `warcraft3/asset_root`。默认报告在该资产目录的上一级 `.cache/asset-audit/latest/report.json`；可在界面打开其他报告，或配置 `warcraft3/audit_report` 的绝对路径。报告来自其他资产库时，还需相应修改 `asset_root`，报告不会自动改写资产路径。

## 当前功能

- 默认按路径显示树状目录，可切换平面列表；支持全部展开／折叠，搜索时展开匹配路径。两种视图共用筛选与选择，切换不会重载模型或中断动画。
- 路径、类别、问题文字搜索；按最高严重等级及是否已 bake 筛选。
- 无 `.scn` 的模型仍可查看审计问题；无报告时可只浏览已有 `.scn`。
- 查看模型、选择动画、暂停、继续、重播、玩家颜色切换。
- 拖动旋转、滚轮缩放、适应主体、地面和背景切换。
- 显示来源、源内容签名、特征和问题；显示实际加载的场景路径。

“重播”会重新实例化模型，清理旧粒子；GPU 粒子使用固定随机种子。暂停会同时停止场景处理和粒子速度。自动取景优先使用可见主体，纯光晕模型回退到光晕几何；粒子专用模型可能仍需手动缩放。

预览使用白色环境补光与方向光。此前场景误将环境光来源设为天空，但没有天空资源，背光区域因缺乏补光而接近黑色；现改为颜色环境光并将天空贡献设为零。这是查看器照明修正，不修改烘焙材质，也不代表已完成原作照明匹配。

当前产物标记为“保真／增强未分离”，没有虚假的保真切换按钮。首版未提供原始 MDX 渲染、任意时间拖动、挂点可视化、资源编辑、完整性能分析或跨项目打包；这些不影响本阶段的全量审计和已有场景检查。完整保真／增强 profile 将在管线阶段 B 接入后共用。

## 审计语义

`report.json` 保存所有模型、来源、源特征、导出数量对照、依赖、分类及问题。`tasks.json` 提供按严重性及影响模型数排序的任务和实现位置，`summary.md` 提供摘要。同一模型的同类问题在汇总中只计一次；不同问题之间可重叠。报告和源解析缓存均为本地生成文件，不提交魔兽衍生资产。

特征数量匹配不证明动画轨或画面完全正确；规则中包含静态确定性检查和需进一步验证的风险候选。全部视觉状态初始为未验证，游戏内参考仍是最终标准。扫描覆盖当前磁盘上可访问的模型，不承诺已枚举所有 MPQ 内容。glTF 依赖缺失表示重建链路有风险，不能据此断言已内嵌纹理的 `.scn` 当前显示错误。

CLI：存在源解析失败时仍完成报告并退出 1；命令／I/O 失败退出 2。其他 P0/P1 问题列入报告，不能只靠退出码判断资产库质量。未知 MDX 块保留偏移信息，未解析的能力不能视为支持。

## 验证

```powershell
npm --prefix tools/asset-convert run test:audit
python tools/workspace/test_apps.py --godot $env:GODOT --app asset_viewer
./tools/workspace/Test-Apps.ps1 -Godot $env:GODOT -App asset_viewer
# 真实 Forward+ 渲染截图（先运行上面的测试准备测试副本）
& $env:GODOT --path apps/asset_viewer --fixed-fps 60 -s res://tests/integration/selftest_asset_viewer.gd -- --capture
```

集成测试需要本地已有牧师投射物、火球、大法师和步兵 `.scn`。除加载和动画检查外，还检查树／列表筛选一致性、选中状态、切换不重启实例，以及展开／折叠。真实渲染对比使用同一模型姿势与机位，分别保存旧天空补光设置和修正设置到本应用的 `tmp/asset-viewer-footman-before.png`、`tmp/asset-viewer-footman-after.png`，并检查预览中央区域亮度改善。无资产环境下应只运行 catalog 单测和应用启动检查，不能把真实资源集成测试跳过后报告为通过。
