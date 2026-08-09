# 游戏 HUD（逻辑优先）

> 场景：`game/scenes/game_hud.tscn` · 脚本：`game/scripts/presentation/game_hud.gd`  
> 最后更新：2026-08-09

## 现状：默认 Control

开发期**不绑** WC3 Console / Resource 图标贴图，命令区仍用 Panel / Label / Button。  
小地图已接 `GameMinimap`（与编辑器同 UV 工具）。

```text
GameHud (CanvasLayer)
└── Root
    ├── TopBar          金 / 木 / 人口（文字）
    └── BottomConsole
        ├── Minimap     GameMinimap（war3mapMap + 黄框 + 单位色点）
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
hud.configure_minimap(map_dir, hf, unit_host, cam, rig, local_player)
```

库存权威：`game/scripts/session/player_stock.gd`（**非** Godot `Resource`）。
