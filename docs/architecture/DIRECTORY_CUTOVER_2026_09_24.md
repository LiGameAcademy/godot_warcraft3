# 双产品目录迁移验收记录

日期：2026-09-24。前置提交：`671aaa2`（地图层通过工厂/初始化端口接入游戏单位）。

## 已实施的目录

```text
apps/
  game/              project.godot、boot、app 装配、client 输入/HUD/相机、scenes、config
  map_editor/        project.godot、boot、app、documents/commands、tools、input、ui、presentation、scenes
packages/
  foundation/        日志、时间等待、在场性、性能计数
  content/           定义、表存储、资源 I/O、内容快照、覆盖包、本地化
  map/               数据、目录索引、地形/寻路查询、世界表现、模型缓存、地图场景
  gameplay/          match、entities、按功能组织的 features、catalog、integration、共享世界表现
content/             内置内容说明、示例 Mod
assets/              资产管线工作目录；大型转换产物继续不入 Git
addons/              第三方子模块的唯一源位置
tools/              离线流水线、godot 资产工具、workspace 同步与验证
tests/              唯一测试源码；按产品准备临时运行副本
```

根 `project.godot` 已归档；不再从根目录启动。原 `game/`、`editor/`、`scripts/`、`core/`、`scenes/` 的受版本控制运行源码均已归位。逐文件映射见 `tools/workspace/source-layout.json`。

## 运行与依赖

- 包源码中的资源路径固定为 `res://packages/<package>/...`（同步副本落在各应用的 `packages/`；不是 Godot addon），同步直接复制并保持 UID；不再把整个项目重写进一个 rts_runtime 包。
- 编辑器不包含 gameplay、游戏客户端、GAS 或 Panku。MapUnitLayer 的单位工厂和初始化回调由游戏入口注入，编辑器创建普通展示节点。
- Selectable/选中环可共享；UnitSelector 玩家输入留在游戏 client；带采集/建造语义的 Interactable/InteractionSetup 归 gameplay。
- 现有 `*_module` 多数是对局服务和 UI 的装配协调，置于游戏 app；不以改目录名掩盖职责混合。纯玩法组件保留在共享 gameplay。
- RuntimeAssets 进入 content，资源定位由 ContentPaths 统一处理。模型解析与渲染缓存 MapModelCache 继续归 map，未把整个缓存体系重写。
- 巨型已烘焙 `.scn` 保留原位；同步生成历史脚本 `.remap`，保持加载性能和原画质。新资源流水线使用新路径。
- 日志基础设施不再依赖 RuntimeAssets 或游戏专属配置；应用通过 ProjectSettings 提供日志配置。

## 验收与边界

已验证（Godot 4.7.2 Mono）：

- 762 个源码/资源/说明文件按映射迁移；359 个已有 UID 与前置基线逐项一致。
- `check_layout.py`：351 个自有运行脚本，0 个包依赖/重复类/缺失迁移/源码被忽略/同步内容违规。两个应用自有代码的固定脚本与场景引用检查无缺失。
- 两个应用最终导入与真实主场景启动通过；游戏启动验证生成双方对战（2 个玩家、20 个野怪营地、86 个单位）。编辑器同步内容不包含 gameplay、GAS 或游戏客户端。
- `test_apps.py` 的 24 组回归全部通过：战斗、命令、实体注册、内容快照、物品、技能治疗、命令卡、路径显示、群体移动、模块绑定、对战重开，以及编辑器文档/保存/撤销/导入/预览/焦点。
- 迁移后的架构运行检查另外通过 9 项；Node/MCP CLI 调用伤害公式测试通过。
- 资产工具入口以不匹配任何模型的 include 过滤器验证：发现 3289 个模型，exported=0、failed=0；没有执行全量重新烘焙。
- Node/Python 语法检查与 Git 空白检查通过。日志保存在根 `tmp/layout-*` 与 `tmp/directory-regressions/`，不提交本机日志。

测试促成的配套修正：外部资源路径覆盖模型异步预载和目录读取；技能/物品文本表存在性检查经过资源门面；测试工具复制示例 Mod；编辑器显式屏蔽模态窗口期间的背景相机输入。测试写入迁至应用临时目录，避免依赖本机用户目录写权限。

本轮未验证独立导出制品、跨平台运行、有渲染视觉一致性或长时间性能；第三方插件示例不属于自有代码引用验收。原有系统根证书/编辑器设置权限诊断与本次源码编译验证分开记录。

目录迁移完成不等于所有领域接口完成重构；攻击动画调用、部分 logic 服务的场景依赖、Mod 热切换和跨平台发布仍是后续独立工作。本轮不改变战斗、寻路算法、画质或 AI 更新频率。

操作入口见 [workspace 工具说明](../../tools/workspace/README.md)。历史设计/审查文档保留当时路径，可通过迁移映射定位当前源码。
