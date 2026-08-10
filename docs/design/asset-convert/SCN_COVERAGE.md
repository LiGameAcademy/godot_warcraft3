# .scn 烘焙覆盖度报告

> 生成时间：2026-08-10T07:29:24.795Z
> 仓库：D:\GodotProject\laoli_gamedev_godot4_course\godot_warcraft3

## 总览

| 指标 | 数值 |
|------|------|
| .glb 总数 | 3289 |
| 已排除（.no-scn） | 716 |
| 有效 .glb | 2573 |
| .scn 总数 | 2554 |
| 有效覆盖率 | 99.3% |
| 缺漏（glb 缺 scn） | 19 |
| 孤儿（scn 无 glb） | 0 |

## 按分类

| 分类 | .glb | 已排除 | 有效 | .scn | 有效覆盖率 | 缺漏 |
|------|------|-------|------|------|-----------|------|
| Buildings | 179 | 0 | 179 | 172 | 96.1% | 7 |
| Doodads | 1593 | 0 | 1593 | 1583 | 99.4% | 10 |
| Units | 725 | 0 | 725 | 723 | 99.7% | 2 |
| 其他 | 792 | 716 | 76 | 76 | 100.0% | 0 |

## 缺漏清单（19 个）

> 这些 glb 缺同 stem .scn；runtime 走 GLTFDocument 解析 + 临时注入 geosetvis。
> 全 bake 命令：`npm run bake:scn -- --force`

### Buildings（7）

- `Buildings/Human/GryphonAviary/GryphonAviary.glb`
- `Buildings/Human/HumanTower/HumanTower.glb`
- `Buildings/Human/TownHall/TownHall.glb`
- `Buildings/NightElf/AltarOfElders/AltarOfElders.glb`
- `Buildings/NightElf/AncientOfLore/AncientofLore.glb`
- `Buildings/NightElf/AncientOfWar/AncientofWar.glb`
- `Buildings/NightElf/AncientOfWind/AncientofWind.glb`

### Doodads（10）

- `Doodads/Cinematic/DemonStorm/DemonStorm.glb`
- `Doodads/Icecrown/Water/BubbleGeyserSteam/BubbleGeyserSteam.glb`
- `Doodads/LordaeronSummer/Water/Shoreline/Shoreline0.glb`
- `Doodads/LordaeronSummer/Water/ShorelineInsideCorner/ShorelineInsideCorner0.glb`
- `Doodads/LordaeronSummer/Water/ShorelineOutsideCorner/ShorelineOutsideCorner0.glb`
- `Doodads/Outland/Water/OutlandShoreline/OutlandShoreline0.glb`
- `Doodads/Ruins/Water/BubbleGeyser/BubbleGeyser.glb`
- `Doodads/Terrain/OutlandMushroomTree/OutlandMushroomTree1D.glb`
- `Doodads/Terrain/OutlandMushroomTree/OutlandMushroomTree8D.glb`
- `Doodads/Terrain/OutlandMushroomTree/OutlandMushroomTree9D.glb`

### Units（2）

- `Units/Undead/PlagueCloud/PlagueCloud.glb`
- `Units/Undead/PlagueCloud/PlagueCloudTarget.glb`
