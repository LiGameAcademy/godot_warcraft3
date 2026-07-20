# slk-export

将经典《魔兽争霸3》`.slk`（SYLK 表）解析为可读的 **JSON** / **CSV**。

SLK 是暴雪用来存单位数值、技能、地形类型、音效表等的表格格式。第一行是列名，之后每行一条记录。

## 用法

```bash
cd tools/slk-export
npm install
npm run export --
```

默认：

| 项 | 值 |
|----|-----|
| 输入 | `../../.cache/wc3-assets` |
| 输出 | `../../assets/slk-exported`（gitignore） |
| 格式 | JSON + CSV |
| 排除 | `File*.slk`、`NotUsed_*`、`Custom_V*`、`Melee_V0` |

```bash
# 只导出单位相关表
npm run export -- --include "Units/**" --force

# 单表
npm run export -- --include "Units/UnitData.slk" --include "Units/unitUI.slk"

# 只要 CSV（可用 Excel 打开）
npm run export -- --include "TerrainArt/**" --format csv
```

## 输出示例

`Units/UnitData.slk` →

- `assets/slk-exported/Units/UnitData.json`
- `assets/slk-exported/Units/UnitData.csv`

JSON 结构：

```json
{
  "source": "Units/UnitData.slk",
  "headers": ["unitID", "sort", "comment(s)", "..."],
  "recordCount": 812,
  "records": [
    { "unitID": "hfoo", "race": "human", "comment(s)": "Footman", "...": "..." }
  ]
}
```

另有 `assets/slk-exported/index.json` 汇总本次导出的所有表。

## 常用表

| 逻辑路径 | 内容 |
|----------|------|
| `Units/UnitData.slk` | 单位基础定义 |
| `Units/UnitBalance.slk` | 生命/成本等平衡 |
| `Units/UnitWeapons.slk` | 武器与攻击 |
| `Units/unitUI.slk` | 模型路径、缩放、图标等 |
| `Units/AbilityData.slk` | 技能数据 |
| `Units/ItemData.slk` | 物品 |
| `Doodads/Doodads.slk` | 装饰物 |
| `TerrainArt/Terrain.slk` | 地表 tile ID → 贴图 |

详见 [docs/WC3_ASSET_PATHS.md](../../docs/WC3_ASSET_PATHS.md)。
