# D0 契约基线：双产品 Autoload / 启动差异

日期：2026-09-23。批次：**D0**。对照根目录当前 `project.godot`。

## 当前单体 Autoload

| 名 | 路径 | 游戏 | 地图编辑器 | 备注 |
|----|------|------|------------|------|
| LogPruner | `core/logger/log_pruner.gd` | 是 | 是 | 进程级 |
| AssetProvider | `addons/asset_provider/...` | 是 | 是 | 共享内容 |
| EditorI18n | `editor/ui/editor_i18n.gd` | **否（目标）** | 是 | 现单体误挂在游戏启动 |
| Wc3DefStore | `scripts/auto/wc3_def_store.gd` | 是 | 是 | D3 经快照 |
| Panku | 控制台 | 可选调试 | 可选 | 发布可关 |
| PerfProbe | `core/debug/perf_probe.gd` | 调试 | 调试 | |
| GameplayAbilitySystem 等 GAS | addons/godot_ability_system | 待核 | 待核 | 无直接 gameplay 引用则编辑器侧可关；删除前核场景/插件 |

## 编辑器插件

当前 `editor_plugins`：`godot_ability_system`、`panku_console`。游戏导出制品不应依赖编辑器插件启用态。

## 目标拆分（D4）

| 应用 | Autoload 原则 |
|------|----------------|
| `apps/game` | AssetProvider、内容/Def 门面、日志；无 EditorI18n；调试项按导出配置 |
| `apps/map_editor` | AssetProvider、EditorI18n、编辑工具；试玩启动外部游戏进程而非嵌入混装 Autoload |

## 主场景

| 产品 | 主场景（目标） |
|------|----------------|
| 游戏 | 对局/菜单入口（现 `run/main_scene`） |
| 编辑器 | 地图编辑根场景 |

## 配置路径

- 现：`AppLog` 等可能默认 `res://game/config/...`。
- 目标：共享库接收注入的配置 Resource/路径；各 app 自有 `config/`。
