# 游戏 HUD（逻辑优先）

> 场景：`game/scenes/game_hud.tscn` · 脚本：`game/scripts/presentation/game_hud.gd`  
> 最后更新：2026-08-04

## 现状：默认 Control

开发期**不绑** WC3 Console / Resource 图标贴图，只用 Panel / Label / Button 跑通逻辑。  
`set_resources` / `command_pressed` / `minimap_clicked` API 保持不变，日后换皮即可。

```text
GameHud (CanvasLayer)
└── Root
    ├── TopBar          金 / 木 / 人口（文字）
    └── BottomConsole
        ├── Minimap     ColorRect（点击仍发 uv）
        ├── Info        单位名 / HP / 状态
        └── Commands    4×3 Button
```

## API

```gdscript
hud.set_resources(gold, lumber, food, food_max)
hud.bind_stock(player_stock)   # PlayerStock.changed → 自动刷新
hud.set_unit_info(name, hp, hp_max)
hud.set_command_labels(["训练", "号召", ...])
hud.set_status(text)
```

库存权威：`game/scripts/session/player_stock.gd`（**非** Godot `Resource`）。
