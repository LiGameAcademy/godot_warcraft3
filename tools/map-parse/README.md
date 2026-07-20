# map-parse

解析经典《魔兽争霸3》`.w3x` / `.w3m` 地图（MPQ），输出开发用 JSON。

依赖同仓库的 [`../mpq-extract`](../mpq-extract)（StormLib + koffi）打开地图包。请先在该目录执行过 `npm install`。

> 说明：npm 上的 `wc3maptranslator@5` 面向新版 `w3i`（version 33），经典冰封王座地图（version 25）无法直接使用，故本工具按经典格式自研解析。

## 默认测试图

`C:\war3\Maps\FrozenThrone\(4)LostTemple.w3x` — 冰封王座最经典的 4 人对战图之一。

## 用法

```bash
# 需已安装 tools/mpq-extract 依赖（含 StormLib.dll）
cd tools/mpq-extract && npm install && cd ../map-parse

npm run parse --
# 等价于解析 C:\war3\Maps\FrozenThrone\(4)LostTemple.w3x

npm run parse -- --map "C:/war3/Maps/FrozenThrone/(2)EchoIsles.w3x" --force
npm run parse -- --no-tilepoints   # 不写完整格点（文件更小）
npm run parse -- --raw             # 额外导出原始 war3map.*
```

## 输出

默认目录：`assets/map-parsed/<slug>/`（已 gitignore）

| 文件 | 内容 |
|------|------|
| `summary.json` | 摘要：名称、玩家、地形尺寸、单位/装饰物计数 |
| `info.json` | `war3map.w3i`（已解析 TRIGSTR） |
| `terrain.json` | `war3map.w3e` 元数据 + stats |
| `terrain-heightfield.json` | 紧凑高度/水体/地表索引（Godot 灰盒默认用这个） |
| `terrain-tilepoints.json` | 完整格点对象（`--tilepoints` 才写出） |
| `units.json` | `war3mapUnits.doo` |
| `doodads.json` | `war3map.doo` |
| `strings.json` | `war3map.wts` |
| `regions.json` / `cameras.json` | 若地图内存在 |

## 已解析格式（经典 TFT）

- `war3map.w3i` v25
- `war3map.w3e` v11
- `war3mapUnits.doo` / `war3map.doo` v8
- `war3map.wts`、`war3map.w3r`、`war3map.w3c`
