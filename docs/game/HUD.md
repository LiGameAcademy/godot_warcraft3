# 游戏 HUD（人族 Console）

> 场景：`game/scenes/game_hud.tscn` · 脚本：`game/scripts/presentation/game_hud.gd`  
> 对标：`editor/scenes/editor_hud.tscn`（同为 CanvasLayer 壳，业务由 Director 驱动）  
> 最后更新：2026-08-03

## 方案：纯 Control 布局（当前）

```text
GameHud (CanvasLayer)
└── Root
    ├── TopBar                 右上：金 / 木 / 人口
    └── BottomConsole          底栏 ~24% 高
        ├── PanelBg            深色石质近似底
        └── Columns
            ├── Minimap
            ├── Portrait + Info
            └── Commands 4×3
```

### 为什么不用 HumanUITile01 全屏壳？

`HumanUITile01–04` 是 **`HumanUI.mdx` 的 UV 材质切片**，不是整屏 2D 外框。  
当 `TextureRect` 全屏拉伸时，会看到碎石块、黑洞、顶栏碎片——正是 UV 图集本来的样子，不是布局 bug。

| 资产 | 用途 |
|------|------|
| `HumanUITile0x.png` | 3D 控制台模型材质（勿当屏框） |
| `HumanUI.glb` | 远期 SubViewport 装饰壳 |
| `Widgets/Console/Human/human-console-button-*.png` | 指令格 2D 控件 |
| `Feedback/Resources/Resource*.png` | 资源图标 |

远期：用 `SubViewport` + 正交相机渲染 `HumanUI.glb` **只替换装饰壳**；交互层 API 不变。

## 布局

```text
┌─────────────────────────────┬──────────────────┐
│  (游戏视野)                  │ Gold Lumber Food │
├──────────┬──────────────────┴──────────────────┤
│ Minimap  │ Portrait │ 单位信息 / 状态           │ Commands 4×3 │
└──────────┴─────────────────────────────────────┴──────────────┘
```

## API

```gdscript
hud.set_resources(gold, lumber, food, food_max)
hud.set_unit_info(name, hp, hp_max)
hud.set_portrait_texture(tex)
hud.set_minimap_texture(tex)
hud.set_status(text)
hud.set_command_icon(slot, tex)  # 0..11；null 恢复空槽
```

信号：`command_pressed(slot)` · `minimap_clicked(uv)`（GameDirector 已接镜头跳转）。

## 后续

- 阶段 C：Session 资源写入 TopBar  
- 阶段 D：选中单位刷新肖像/血量/指令图标  
- 小地图实时单位点  
- 可选：ConsoleChrome → SubViewport(`HumanUI.glb`)  
