# DOO_FORMAT — W3E DOO 文件 + `doodads.json` Schema

> **角色**：W3E `war3map.doo`（Warcraft III Object）文件结构 + `tools/map-parse`
> 输出的 `doodads.json` 完整 schema。
> **改 doodad schema 时**（如加新字段）：先看本文件，再改 `tools/map-parse/src/parsers/doo-doodads.js`。
> 最后更新：2026-07-31

---

## 1. W3E `war3map.doo` 文件结构

### 1.1 文件信息

| 字段 | 含义 |
|------|------|
| 文件名 | `war3map.doo` |
| 大小 | 100KB-10MB（doodad 数量依赖）|
| 格式 | W3E 二进制（little-endian，固定字段宽度）|
| 解析 | `tools/map-parse/src/parsers/doo-doodads.js`（Node.js）|

### 1.2 二进制布局（推测，0.6+ HivEWE）

```text
File Header
  u32     format_version
  u32     doodad_count
  Doodad[count]
    i32     id (4-char packed, e.g. 'WTst' = 0x74737457)
    u32     variation
    float[3] position (x, y, z)
    float    angle (radians)
    float[3] scale
    u32     flags
    u8      life (0-100)
    i32     itemTablePtr (-1 = none)
    DroppedItemSet[?]   (复杂，可能循环)
    u32     creationNumber
```

注：HivEWE 0.6+ `doodad.h` 完整定义；0.3 旧版字段略有差异（`skin` 在 0.3 存在，0.6+ 整合到 variation）。

### 1.3 HivEWE `doodad.h` 关键字段

```cpp
struct Doodad {
    int id;                 // 4-char ID packed as int
    int variation;          // 0-15 (or 0-31 with extended)
    glm::vec3 position;     // WC3 world units
    float angle;            // Z-axis rotation
    glm::vec3 scale;        // uniform or non-uniform
    int flags;              // bitmask (see below)
    int life;               // 0-100
    int item_table_ptr;     // -1 = none
    std::vector<int> dropped_item_sets;
    int creation_number;    // unique instance ID
};
```

**flags bitmask**（HivEWE 推测）：
- `0x01` = solid（不阻挡单位）
- `0x02` = 不可破坏
- `0x04` = 不可选中
- `0x08` = 永远显示在迷雾中
- `0x10` = 沙化（被腐蚀后变树）
- `0x20` = 单位路径阻挡
- `0x100` = 编辑器选区

---

## 2. `doodads.json` Schema（`tools/map-parse` 输出）

### 2.1 顶层结构

```json
{
  "doodads": [ Doodad, Doodad, ... ]
}
```

`doodads` 数组是顶层唯一键。

### 2.2 Doodad 字典（每条目）

**12 字段**（Lost Temple 实例）：

```json
{
  "id": "WTst",                      // 4-char ID
  "variation": 8,                    // 0-15 (or 0-31 extended)
  "position": {                       // WC3 world units (NOT Godot scale)
    "x": 7680,
    "y": -7360,
    "z": 120.375
  },
  "angle": 4.7123894691467285,       // radians
  "angleDegrees": 270.000028004002,   // 冗余（度）
  "scale": {                          // uniform or per-axis
    "x": 0.965129554271698,
    "y": 0.965129554271698,
    "z": 0.965129554271698
  },
  "flags": 2,                         // bitmask
  "life": 100,                        // 0-100
  "itemTablePtr": -1,                 // -1 = none
  "droppedItemSets": [],              // array of item set ptrs
  "creationNumber": 2244              // unique instance ID
}
```

### 2.3 字段表

| 字段 | 类型 | 单位 | 默认 | 含义 |
|------|------|------|------|------|
| `id` | String | 4-char | 必填 | 资源 ID（如 `"WTst"` = 树木，`"ATtr"` = 中立小树）|
| `variation` | int | 0-15 | 0 | 变体（决定 mesh + texture）|
| `position.x` | float | WC3 world unit | 0 | X 坐标（**未缩放**）|
| `position.y` | float | WC3 world unit | 0 | Y 坐标（Godot 端转 -Z）|
| `position.z` | float | WC3 world unit | 0 | Z 坐标（**初始 Y**，refresh 时被覆盖）|
| `angle` | float | rad | 0 | 绕 Z 轴旋转（WC3 convention）|
| `angleDegrees` | float | deg | 0 | 同 `angle`（冗余，方便人读）|
| `scale.x/y/z` | float | 倍数 | 1.0 | 缩放（uniform 或各轴）|
| `flags` | int | bitmask | 0 | 见 §1.3 表 |
| `life` | int | 0-100 | 100 | 生命值（被攻击减少）|
| `itemTablePtr` | int | ptr / -1 | -1 | 掉落表指针（-1 = 无）|
| `droppedItemSets` | Array | ptrs | [] | 多个掉落表（罕见）|
| `creationNumber` | int | 唯一 ID | 自增 | 场景编辑选回用 |

### 2.4 关键单位换算

| 维度 | WC3 → Godot |
|------|-------------|
| 位置 | `× 0.01`（`Wc3Coords.WORLD_SCALE`）|
| 角度 | `Godot = -WC3 + PI`（`Wc3Coords.yaw_wc3_to_godot`）|
| 高度 | `Y` 调换为 `-Z`（WC3 Z-up → Godot Y-up）|
| tile | `1 tile = 128 WC3 unit` |

`Wc3Coords.wc3_to_godot(Vector3(x, z, -y))` 提供统一转换。

### 2.5 id 命名约定（WC3 标准）

| 类别 | 4-char ID 前缀 | 示例 |
|------|---------------|------|
| 树木（T） | `WT`, `AT`, `JT` | `WTst` = 灰木树 |
| 中立生物 | `n` 或 `u` 前缀 | `nten` = 中立古树 |
| 单位 | 4-char unit ID | `Hpal` = 人类牧师 |
| 物品 | `I` 前缀 | `I000` = 金币 |
| 装饰物 | `D` 前缀 | `Dshd` = 阴影标记 |

**Cat`WTst`** = Warcraft 灰木树（灰木是 variation 8 的标准 texture）。

---

## 3. `tools/map-parse` 实现

### 3.1 解析器

**`tools/map-parse/src/parsers/doo-doodads.js`**（推测结构）：

```js
function parseDoodads(buffer) {
    const doodads = [];
    const view = new DataView(buffer);
    let offset = 8;  // skip format_version + count
    
    for (let i = 0; i < count; i++) {
        const id = view.getInt32(offset, true);  offset += 4;
        const variation = view.getUint32(offset, true); offset += 4;
        const px = view.getFloat32(offset, true); offset += 4;
        const py = view.getFloat32(offset, true); offset += 4;
        const pz = view.getFloat32(offset, true); offset += 4;
        const angle = view.getFloat32(offset, true); offset += 4;
        const sx = view.getFloat32(offset, true); offset += 4;
        const sy = view.getFloat32(offset, true); offset += 4;
        const sz = view.getFloat32(offset, true); offset += 4;
        const flags = view.getUint32(offset, true); offset += 4;
        const life = view.getUint8(offset, true);   offset += 1;
        // pad?
        const itemTablePtr = view.getInt32(offset, true); offset += 4;
        // droppedItemSets (loop until sentinel)
        const droppedItemSets = parseItemSets(view, offset);
        const creationNumber = view.getUint32(offset, true); offset += 4;
        
        doodads.push({
            id: idToString(id),
            variation, position: {x: px, y: py, z: pz},
            angle, angleDegrees: radToDeg(angle),
            scale: {x: sx, y: sy, z: sz},
            flags, life, itemTablePtr, droppedItemSets, creationNumber
        });
    }
    
    return doodads;
}
```

**注**：实际 W3E 二进制结构更复杂（含 alignment + padding）—— 这是简化版。

### 3.2 改 parser

要加新字段：
1. 改 `doo-doodads.js` —— 读新字段 + 写 JSON
2. 改 `MapDoodadLayer._apply_doodad_xform` —— 用新字段
3. 加 selftest —— 解析已知 map 验证

---

## 4. `Doodad` 在 Godot 端的生命周期

```text
war3map.doo (W3E 二进制)
  → tools/map-parse (Node.js)
  → assets/map-parsed/<map>/doodads.json
  → MapBuildContext.doodads: Dictionary
  → MapDoodadLayer.build(ctx)
     → 按 (id, variation) 分组
     → 决定 GLB / placeholder
     → 实例化节点（存 doodad_data meta）
     → _apply_height_update（刷 Y）
```

详见 [README.md](README.md) §2。

---

## 5. 已知坑

1. **`position.z` 是初始值** —— 改地形后被覆盖；JSON 仍保留原 Z
2. **`angleDegrees` 冗余** —— 解析时算；写回时不用
3. **`flags` bitmask 0x100 罕见** —— 编辑器选区标记（不要给运行时用）
4. **`life` 仅游戏逻辑** —— present 不渲染血条（v2 项：单位层有）
5. **`itemTablePtr` 罕见** —— 经典 WE 地图大多 -1；掉落表由 Item 子系统处理（`Wc3Item` v2）
6. **`creationNumber` 唯一但不复用** —— 删除 doodad 后 ID 不回收；UI 选回时按此 ID 找

---

## 6. vibecoding 指导

### 6.1 加新 doodad 字段

1. **改 W3E 格式**（如加 `health_regen` 字段）：
   - 改 `tools/map-parse/src/parsers/doo-doodads.js` —— 读 + 写
   - 改 `assets/map-parsed/<map>/doodads.json` schema
2. **改 `MapDoodadLayer`**：
   - 改 `_place_doodad_instance` —— 用新字段（如果影响渲染）
   - 改 `_apply_doodad_xform` —— 用新字段（如果影响 transform）
3. **加 selftest**：解析已知 map + 断言字段值

### 6.2 改 id 命名

WC3 ID 是 4 字符固定——不可改。新 doodad 类型要在源 `Units/<id>/<id>.mdx` + `units.slk` / `doodads.slk` 注册。

### 6.3 改 flags 含义

`flags` 是 bitmask——加新 bit 不破坏老数据（向后兼容）。但**别**复用已用 bit。

### 6.4 改 variation

`variation` 0-15 是基础；0-15 + 16 = extended 集（`extended` 标志在 SLK 决定）。改 variation 范围要同步改 SLK parser。

---

## 7. 何时查这里

- **改 doodads.json schema** → §2
- **改 tools/map-parse** → §3 + `tools/map-parse/src/parsers/doo-doodads.js`
- **改 W3E 格式** → §1
- **加新 doodad 字段** → §6.1

---

## 8. 相关文档

- [README.md](README.md) —— MapDoodadLayer 架构
- [Y_REFRESH.md](Y_REFRESH.md) —— `change_doodad_heights` 等价
- [data/PIPELINE.md](../../data/PIPELINE.md) —— `war3map.doo` → `doodads.json` 流水线
- [data/WC3_ASSET_PATHS.md](../../data/WC3_ASSET_PATHS.md) —— `Units/<id>/<id>.mdx` 路径
- [tools/map-parse/README.md](../../../tools/map-parse/README.md) —— 解析器总览
- [hivewe/TERRAIN_MESH.md](../hivewe/TERRAIN_MESH.md) —— heightfield 体系
- [roadmap/ROADMAP.md §⑩ 应用高度](../../roadmap/ROADMAP.md)
