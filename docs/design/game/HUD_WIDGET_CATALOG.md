# HUD 控件目录与组合契约

日期：2026-09-23。状态：第一批面板已落地（ResourceBar / CommandPanel / SelectionDetailsPanel / ActivityFeedPanel / MinimapDock）；其余组合控件与布局外壳仍待推进。配套 [布局方案](HUD_LAYOUT_REDESIGN.md)、[模块边界](../../architecture/GAMEPLAY_MODULE_BOUNDARIES.md)。

## 1. 四级组织

基础控件 → 组合控件 → HUD 功能面板 → 布局外壳。控件只消费展示数据、发出操作意图；Presenter 负责订阅、查询和调用命令。状态权威保留在 Gameplay，不把 Node、GameDirector 或可写业务组件作为所有控件的万能上下文。对局壳经 Autoload [`UiManager`](UI_FRAMEWORK.md) 注册 Surface / 推送 VM / 路由 `UiIntent`；`UiManager` 不做 Requires/扣费。

当前落地目录：`apps/game/client/hud/panels/`（功能面板）+ 既有 `client/hud/` 基础件（肖像、Buff、冷却、背包、小地图）。`GameHud`（`scenes/game_hud.tscn`）仅组装与转发，不再内嵌各区逻辑。

## 2. 基础控件

| 控件 | 职责 | 结构 / 输入输出 |
|---|---|---|
| IconActionButton | 图标与统一交互状态 | Button + Icon、HotkeyBadge、CountBadge、StateIndicator、CooldownOverlay；输入图标/标签/启用原因，输出主/次操作 |
| ValueBar | 生命、法力、经验及通用进度 | ProgressBar + 当前/最大数值标签 + 可选标题；不主动读取单位 |
| CooldownOverlay | 冷却扇形与数字 | 遮罩 + 时间标签；鼠标穿透，只显示传入时间，不推进玩法冷却 |
| Badge | 快捷键、数量、等级、技能点 | 背景 + 短文本/图标；位置由组合控件指定 |
| StatChip | 单项属性与增减值 | Icon + Value + Modifier；发出说明请求 |
| StateIndicator | 选中、自动施法、暂停、受阻 | 状态图标/边框 + 可选文本；不只使用颜色区分 |
| SectionHeader | 标题、数量与附加操作 | Title + Count + Spacer + Actions |
| EmptyState | 无选择/无任务等空态 | 图标 + 说明 + 可选操作 |
| OverflowIndicator | 表示还有未展示的内容 | +N 按钮，输出展开请求；不能代替访问隐藏内容的入口 |

禁止基础控件查技能表、读磁盘路径或决定操作合法性。图标由展示模型/资源适配提供。冷却数字、键位、数量占不同角落，避免互相遮挡；Tooltip 说明不可用原因。

## 3. 组合控件

| 控件 | 职责与结构 | 操作意图 |
|---|---|---|
| EntityPortrait | 静态/动态肖像 + 等级 + 状态遮罩 | 选择/定位请求 |
| VitalsPanel | 多个 ValueBar：生命、法力、可选经验 | 通常无业务操作 |
| StatGroup | Grid/Flow 中的 StatChip | 属性详情请求 |
| EffectIcon | Buff 图标 + 层数 + 剩余时间 | 说明请求，不默认可驱散 |
| EffectStrip | 有限数量 EffectIcon + 溢出入口 | 完整效果列表请求 |
| SelectionTypeTile | 类型图标 + 数量 + 主选/子组状态 | 子组选择或主选切换，语义分开 |
| QueueItemView | 图标 + 名称/等级 + 进度 + 等待/暂停状态 | 查看来源、定位、取消请求 |
| QueueStrip | 当前任务区 + 等待任务容器 + 溢出入口 | 使用稳定 task_id 操作，不用数组下标当身份 |
| InventorySlot | IconActionButton + 拖放预览/目标高亮 | 使用、丢弃、交换请求，含稳定槽位身份 |
| ControlGroupButton | 编号 + 代表图标 + 成员数 + 警报 | 召回、定位、修改成员请求 |
| HeroSummaryCard | 肖像 + 血蓝 + 等级/技能点 + 死亡/复活 | 选择、定位、升级入口请求 |
| NotificationItem | 图标 + 文本 + 操作/关闭 | 定位目标或关闭，不自行修改世界 |

物品、队列、控制组可以共享基础按钮，但必须保持不同交互契约。不要用几十个开关把它们合成万能按钮。

## 4. 功能面板

| 面板 | 内容与结构 |
|---|---|
| ResourceBar | 金/木 StatChip、人口指示；突出满人口状态 |
| MatchStatusBar | 时间、对局阶段、菜单入口 |
| HeroRosterPanel | 稳定顺序的 HeroSummaryCard；死亡英雄保留位置 |
| SelectionDetailsPanel | 空态、普通单位、英雄、建筑、多选模板宿主 |
| CommandPanel | Header + 分类页 + 固定 4×3 按钮槽 + 返回入口 |
| InventoryPanel | Header + 3×2 InventorySlot；视觉位置与原物品索引显式映射 |
| LocalProductionPanel | 所选建筑的当前项、QueueStrip、明确的取消入口 |
| GlobalProductionPanel | 全部/研究升级/训练筛选 + 跨建筑任务列表 + 展开入口 |
| ControlGroupBar | 非空控制组；编辑时显示所有槽位 |
| MinimapPanel | 地图底图、单位标记、镜头框、地图工具 |
| NotificationPanel | 数量上限、排列、历史入口；寿命策略由展示控制器管理 |

HeroDetailsView = EntityHeader + EntityPortrait + VitalsPanel（含经验）+ StatGroup + EffectStrip + SkillPointIndicator。技能仍在 CommandPanel，物品仍在 InventoryPanel，不复制第二套状态。

BuildingDetailsView = EntityHeader + Portrait + Vitals + ConstructionProgress / LocalProductionPanel + StatGroup。施工与生产按模式显示，避免无条件纵向堆叠。

## 5. 布局外壳

```text
GameHud
└── HudRoot
    ├── TopStatusDock
    │   ├── ResourceBar
    │   └── MatchStatusBar
    ├── HeroRosterPanel
    ├── GlobalProductionPanel
    ├── BottomDock
    │   ├── ControlGroupBar
    │   └── BottomContent
    │       ├── MinimapPanel
    │       ├── SelectionDetailsPanel
    │       ├── ContextPanelHost（物品/生产/扩展详情）
    │       └── CommandPanel
    ├── NotificationPanel
    ├── TooltipHost
    ├── ModalHost
    └── DebugOverlay
```

- HudLayout：只分配空间、选择完整/紧凑模板，不生成业务数据。
- ContextPanelHost：切换面板及空间，不拥有背包和生产队列。
- TooltipView：渲染标题、描述、费用、条件、快捷键；TooltipHost 管理延时、定位、换侧、视口约束。
- ModalHost：管理模态焦点、返回与输入阻挡。随本地 UI 生命周期存在，无需额外 Autoload。
- 普通区域使用 Container 协调尺寸；覆盖层另行排序，不用 z-index 掩盖普通面板挤压。

## 6. 数据与生命周期契约

建议提供小型类型化展示数据，不向每个按钮传完整业务对象。以 QueueItemView 为例：

```text
输入：task_id、名称、图标、目标等级、status、progress、remaining_sec、
      source_entity_id、可取消状态与原因
输出：inspect_requested(task_id)、locate_requested(task_id)、cancel_requested(task_id)
```

Presenter 在执行时重新解析身份与合法性；任务已完成/来源建筑已销毁时返回结果，不操作过期引用。控件按 task_id 更新，避免相同定义的两个任务混淆。

结构更新和数值更新分离：选择类型改变才重组模板；生命、冷却、进度局部刷新。绑定新对象前断开旧订阅；隐藏或销毁时取消 Tooltip、拖放和临时订阅。重开后不能保留上局实体引用。

快捷键标签消费实际绑定结果；控件不独立监听全局键盘，由输入上下文统一分发。图标/资源采用共享引用，不由每次重绘重新加载。

## 7. 目录与实现顺序

近期沿用 `client/hud/`，功能面板落在 `client/hud/panels/`；可按实际文件继续增加 `primitives/`、`components/`、`layout/`、`presenters/`、`preview/`；不预创建空目录。双项目切换时整体归游戏客户端 UI，共享基础主题仅在编辑器确实需要时上提。

优先复用已有 UnitPortraitView、CooldownButtonOverlay、UnitCombatStatChip、UnitBuffStrip、InventoryPanel 和 GameMinimap，通过适配逐步统一接口，不直接改名重写。

**已落地（第一批面板）**：`ResourceBar`、`CommandPanel`、`SelectionDetailsPanel`、`ActivityFeedPanel`、`MinimapDock`；`GameHud` 降为组装外壳。共享 `HudIconCache`。

**已落地（U1 响应式）**：`HudLayout` 按视口宽分 FULL/COMPACT/TIGHT，夹紧底栏高度占比，缩放小地图/详情/命令格并防横向重叠。

仍待：IconActionButton、ValueBar、StatChip（与 UnitCombatStatChip 统一）、QueueItemView、QueueStrip；第二批英雄栏、控制组、全局生产与 Tooltip/通知管理。保持现有按钮操作与冷却局部刷新行为。

每个组合控件提供模拟数据预览场景；覆盖长文本、禁用原因、冷却、自动施法、空态、16+ 多选、相同任务、队列溢出、英雄死亡及 UI 缩放。测试显示语义与实际操作意图，不编写仅复述控件树的测试；布局矩形和截图验收沿用 HUD_LAYOUT_REDESIGN.md。
