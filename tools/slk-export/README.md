# slk-export

将经典《魔兽争霸3》`.slk`（SYLK 表）解析为可读的 **JSON**。

SLK 是暴雪用来存单位数值、技能、地形类型、音效表等的表格格式。第一行是列名，之后每行一条记录。

## 换表前比较

在仓库根目录运行（输入支持导出的 JSON 或原始 SLK）：

```powershell
node tools/slk-export/src/compare-tables.mjs assets/slk-exported/Units/UnitBalance.json tmp/patch-probe-extracted/Units/UnitBalance.slk tmp/patch-unitbalance-comparison.json
node tools/slk-export/src/compare-tables.test.mjs
```

比较按主键匹配，不依赖行顺序。报告区分新增/删除记录、新增/删除字段及已有字段值变化，避免新增列使全表看起来都是数值变更。缺失或重复主键会失败，防止静默丢行。默认第一列为主键，也可用第四个参数明确指定；比较不会修改输入表。

## 用法

```bash
cd tools/slk-export
npm install
# 全量导出
node src/cli.js
# 子集覆盖
node src/cli.js --include "Units/**" --overwrite
```

默认：

| 项 | 值 |
|----|-----|
| 输入 | `../../.cache/wc3-assets` |
| 输出 | `../../assets/slk-exported`（gitignore） |
| 格式 | JSON |
| 排除 | `File*.slk`、`NotUsed_*`、`Custom_V*`、`Melee_V0` |

```bash
# 单表
node src/cli.js --include "Units/UnitData.slk" --include "Units/unitUI.slk"

# 地形相关
node src/cli.js --include "TerrainArt/**" --overwrite

# 经 npm（PowerShell 需给 -- 加引号）
npm run export "--" "--include=Units/**" --overwrite
```

## 输出示例

`Units/UnitData.slk` → `assets/slk-exported/Units/UnitData.json`

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

> **已弃用 CSV**：不再写出 `.csv`；`--overwrite` 时会删除同名历史 CSV。

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

详见 docs/data/WC3_ASSET_PATHS.md（开发资料，公开版待审阅）。
