# D0 契约基线：依赖禁区

日期：2026-09-23。批次：**D0**。

依赖箭头表示「允许使用」。违反禁区的引用必须经应用装配层注入，或留在适配器内。

## 目标分层（与目标架构一致）

```text
GameApp / EditorApp
        ↓
Gameplay 应用用例 / 共享地图与内容 API
        ↓
Gameplay 领域 / 地图查询契约 / 内容定义契约
        ↓
Godot 适配器 / 存储与解码
```

## 禁止引用（未来 packages 与当前单项目等价约束）

| 禁止 | 说明 |
|------|------|
| `packages/map` → `packages/gameplay` 或 `game/features` | 地图共享库不导入玩法 |
| `packages/content` → `apps/*` 或 `res://game/config` | 内容库不绑产品配置路径 |
| `packages/foundation` → 任何上层包 | 仅基础类型/日志抽象 |
| 领域 `rules/` / `state/` → SceneTree、HUD、Autoload 文件路径 | 允许 Vector2i、RefCounted |
| 命令合法性 → 当前 HUD 选中 | UI 预检可重复；权威在命令入口 |
| 共享/脚本层硬编码 `res://game/config/debug_log.json` 作为唯一日志配置 | 应用启动注入 |

## 当前单项目允许的过渡

| 允许（过渡） | 清理目标 |
|--------------|----------|
| `game/app/game_director.gd` 装配并注入 Callable | 保留为应用入口，不膨胀业务 |
| `game/scripts/**` 未迁完的实现 | 逐批迁入 features / entities / match |
| Autoload：`AssetProvider`、`Wc3DefStore` | D3 后由快照门面包装；双产品分拆 Autoload 列表 |
| Autoload：`EditorI18n`、GAS 插件 | 仅编辑器或明确依赖的应用启用（见 PRODUCT_AUTOLOADS） |

## 适配边界（允许）

- Gameplay 通过 **WorldQuery / PathQuery / Heightfield 只读端口** 使用地图，不直接 new MapLoader 内部层。
- 内容通过 **DefinitionProvider / AssetResolver**（D3）解析；物理路径只出现在 infrastructure。
- 完成事件用对局内信号；有成功/失败的事务必须返回结果，信号不能替代。

## 架构门禁测试

`tests/architecture/` 用静态扫描断言活跃代码不引入新的禁区路径字符串。基线见 `selftest_dependency_bounds.tscn`。
