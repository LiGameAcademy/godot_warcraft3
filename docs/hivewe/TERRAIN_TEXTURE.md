# HiveWE 的地形纹理（Texture）

> tile_id / tile_index、变体加权、Autotile、cliff 邻接禁贴 blight。

## 1. 概念层次

| 概念 | 含义 | 存储 |
|------|------|------|
| `tile_id` (string) | 4 字符 ID，如 `"Ldrt"` | SLK 表（TerrainArt/Terrain.slk） |
| `tile_index` (int) | 解析后的数组索引 | `Map::terrain` 启动时建立 `ground_texture_to_id` |
| `corner_ground_texture[i]` | 顶点 i 的 tile 索引 | SoA 数组（与 corner 同形） |
| `corner_ground_variation[i]` | 5 bit 变体（0-31） | SoA 数组 |
| `corner_blight[i]` | 污染标志 | SoA bool |
| TileSet | 一组 tile 共享同一目录 | `Map::tilesets`（`TilesetData`） |

**`[terrain_operators.h:62]`**：

```cpp
class TextureOperator: public TerrainOperator {
    std::string tile_id;       // 用户在 UI 选（如 "Ldrt"）
    int tile_index;             // apply_begin 时从 tile_id 解析
};
```

## 2. 笔刷逻辑

**`[terrain_operators.cpp:148-201]`**：

```cpp
void TextureOperator::apply_begin(...) {
    auto& terrain = map->terrain;
    tile_index = terrain.ground_texture_to_id(tile_id);  // 字符串 → 索引
}

PathingRect TextureOperator::apply(const TerrainRect& area, double frame_delta) {
    auto& terrain = map->terrain;

    for (i, j) in area:
        if (!brush->contains(...)) continue;

        const size_t idx = terrain.ci(i, j);

        if (tile_index == terrain.blight_texture) {
            // === 贴 Blight 特殊处理 ===
            bool cliff_near = false;
            for (k=-1; k<=1; k++) for (l=-1; l<=1; l++) {
                if (边界) cliff_near = cliff_near || terrain.corner_cliff[ci(i+k, j+l)];
            }
            if (cliff_near) continue;  // 跳过：blight 不能贴 cliff
            corner_blight[idx] = true;
        } else {
            // === 普通 tile 贴图 ===
            corner_blight[idx] = false;  // 顺手清 blight
            corner_ground_texture[idx] = tile_index;
            corner_ground_variation[idx] = random_ground_variation();  // 加权随机
        }

    terrain.update_ground_textures(area);
    return area.to_pathing().adjusted(-2, -2, -2, -2);
}
```

**关键观察**：

1. **`tile_id → tile_index` 转换** 在 apply_begin（避免每帧重解析）
2. **Blight 是特殊 tile**——`tile_index == terrain.blight_texture` 走专门路径
3. **Blight 邻接 cliff 跳过**（3×3 检测）
4. **任何非 blight 笔刷顺手清 blight**（防止"贴了新地表还有污染"）
5. **变体加权随机**（不是均匀 0-31）—— 视觉一致性

## 3. 变体加权表（**关键算法**）

经典 WE / HiveWE 的 ground variation 加权（**和我们 `Wc3TerrainLogic` 一样**）：

| 变体 | 权重 | 含义 |
|------|------|------|
| 0 (中心) | **85** | 最常见（默认中心 tile） |
| 16-17 | **85** | 平边（无 90° 角） |
| 1, 4, 8, 12 | **85** | 4 种转角（NE/NW/SE/SW） |
| 2, 5, 9, 13 | **10** | 4 种转角带相邻 |
| 3, 6, 10, 14 | **4** | 4 种转角带多相邻 |
| 7, 11, 15, 18? | **1** | 4 种转角带满 |

**总和 = 570**（`VARIATION_CHANCE_SUM=570`），这跟我们 `Wc3TerrainLogic.VARIATION_CHANCE_SUM` **完全一致**！✅

**采样算法**：

```cpp
int random_ground_variation(rng) {
    int nr = rng.randi_range(0, 570) - 1;  // [0, 569]
    for (pair : VARIATION_CHANCES) {
        if (nr < pair.chance) return pair.variation;
        nr -= pair.chance;
    }
    return 0;
}
```

**`[terrain_operators.cpp]` 中实际是 `Wc3TerrainLogic.random_ground_variation()`（godot_warcraft3 的实现，**完全一样**）**

## 4. Tileset 系统

**`Map::tilesets`**（`[base/map/map.ixx:77]`）：

```cpp
TilesetData tilesets;  // 一组 tile 共享同一目录
```

**`TilesetData` 推测**（`Tileset.ixx` 文件）：

```cpp
class TilesetData {
    std::vector<std::string> ground_tilesets;  // 路径列表
    std::map<std::string, int> ground_texture_to_id;  // tile_id → index
    int ground_texture_count;  // 用于 variation 上界
};
```

**`ground_texture_to_id`** 是 SLK 解析时建立：

```cpp
// terrain.ixx 推测
int ground_texture_to_id(const std::string& tile_id) const {
    auto it = ground_texture_to_id.find(tile_id);
    return it != end ? it->second : 0;
}
```

## 5. SLK 加载（`Map::load`）

**`[base/map/map.ixx:114-152]`**（async + 并发加载）：

```cpp
auto units_future = std::async(std::launch::async, [&] {
    units_slk = slk::SLK("Units/UnitData.slk");
    units_slk.add_column("missilearc2");
    // ... add_column 加缺列
    units_meta_slk = slk::SLK("Units/UnitMetaData.slk");
    units_meta_slk.substitute(world_edit_strings, "WorldEditStrings");
    units_meta_slk.build_meta_map();
    
    unit_editor_data = ini::INI("UI/UnitEditorData.txt");
    unit_editor_data.substitute(world_edit_strings, "WorldEditStrings");
    // substitute 两次（同一文件内 key 引用）
    unit_editor_data.substitute(world_edit_strings, "WorldEditStrings");
    
    units_slk.merge(ini::INI("Units/UnitSkin.txt"), units_meta_slk);
    // ... 多个 merge
});
```

**HiveWE 并发加载 4 类 SLK**：
- `units_future`（unit data + balance + weapons + abilities + ...）
- `items_future`（item data + skin + func + strings）
- `doodads_future`（doodad data + skins + 处理空字段 → "0"）
- `destructibles_future`（destructable data + meta + func + strings）

**关键**：
- **`add_column`**：强制加缺列（兼容老 SLK）
- **`substitute(WorldEditStrings, "WorldEditStrings")`**：把 `WESTRING_*` 替换为实际字符串
- **`substitute` 调两次**：因为有些 key 引用同一文件的其他 key
- **`merge`**：合并多个 SLK/INI（覆盖优先级）
- **空字段处理**：`maxpitch = ""` 或 `"-"` → 替换为 `"0"`

## 6. cliff 邻接禁贴 blight（**关键算法**）

**为什么？** 视觉上 Blight（亡灵污染）是"腐地"，不应该出现在悬崖上（悬崖是岩石）。

**算法**：
```cpp
bool cliff_near = false;
for (k=-1; k<=1; k++) for (l=-1; l<=1; l++) {
    if (i+k 边界检查) {
        cliff_near = cliff_near || corner_cliff[ci(i+k, j+l)];
    }
}
if (cliff_near) continue;  // 跳过：cliff 邻接不能 blight
```

**注**：是 3×3 邻域（包括自己）。如果当前 cell 是 cliff，或者 8 邻居有 cliff，就跳过。

**这跟我们 `Wc3GroundTileCatalog` 当前实现的差异**：
- 我们没处理 blight（待加）
- 我们没处理 cliff 邻接（待加）
- 但我们有 `Wc3CliffCatalog` 来分辨 cliff 类型（比"是否 cliff"更细）

## 7. 对应到 godot_warcraft3

| HiveWE | godot_warcraft3 | 评价 |
|--------|----------------|------|
| `corner_ground_texture[]` | `Wc3Heightfield.ground_textures[]` | ✅ 1:1 |
| `corner_ground_variation[]` | `Wc3Heightfield.ground_variations[]` | ✅ 1:1 |
| `corner_blight[]` | **未实现** | ❌ 缺 |
| `ground_texture_to_id(tile_id)` | `Wc3TerrainTileCatalog._tile_to_png` | ✅ 思路同 |
| `TilesetData` | `Wc3TerrainTileCatalog` | ✅ 简化 |
| `random_ground_variation` 加权表 | `Wc3TerrainLogic.random_ground_variation` | ✅ **完全一致** |
| `VARIATION_CHANCE_SUM=570` | `Vc3TerrainLogic.VARIATION_CHANCE_SUM=570` | ✅ |
| 18 项加权（4×NE+NW+SE+SW 等） | `Wc3TerrainLogic.VARIATION_CHANCES` | ✅ |
| `corner_cliff` 邻接 blight 跳过 | **未实现** | ❌ 缺 |
| Blight 自动清（任何非 blight 笔刷） | **未实现** | ❌ 缺 |
| `add_column` / `merge` / `substitute` | **未实现**（我们有 `Wc3DefStore` + `*Def`） | ⚠️ 我们按 *Def Resource 走，更类型安全 |
| SLK 并发加载 | `Wc3DefStore` 同步预加载 4 表 | ⚠️ 我们地图小，没必要并发 |
| `corner_blight[idx] = false` | **未实现** | ❌ 缺 |
| CliffOperator 放 cliff 后清 4 角 blight | **未实现** | ❌ 缺 |

## 8. vibecoding 指导

### 8.1 `Wc3Heightfield` 加 `blights` / `boundaries`

**两个标志位**：

```gdscript
# Wc3Heightfield
var blights: PackedByteArray = PackedByteArray()  # 1 byte/corner, 0/1
var boundaries: PackedByteArray = PackedByteArray()

func is_blight(ix, iy) -> bool: ...
func set_blight(ix, iy, v) -> void: ...
```

**或者合并到 `flags_packed`**（已有 FLAG_WATER=1 / FLAG_RAMP=4）：

```gdscript
const FLAG_BLIGHT := 2
const FLAG_BOUNDARY := 8
```

**推荐第二种**（省 SoA）—— 但 `flags_packed` 是 `int` 不是 bit field，要确认能否装 32 位。

### 8.2 笔刷加 blight 邻接检测

**步骤**：
1. `Wc3TerrainLogic.set_ground_tex(ix, iy, tile_id, is_blight)` 内部加分支
2. 如果 `is_blight`，检查 3×3 邻接 `corner_cliff`
3. 任何非 blight 笔刷顺手 `flags_packed[idx] &= ~FLAG_BLIGHT`

**`Wc3CliffLogic` 配合**：放下 cliff 后 `flags_packed[bl/br/tl/tr] &= ~FLAG_BLIGHT`

### 8.3 18 项加权表是 hivewe-classic 沿用

**不**改 `Wc3TerrainLogic.VARIATION_CHANCES`——已和 HiveWE 对齐 ✅

如果新加 variation（如 18-31），需要查 HiveWE / WC3 源码是否扩展过；目前看 0-15 已覆盖所有 tile 类型，18+ 是 padding。

### 8.4 我们的 SLK 加载是"类型化"

**HiveWE**：`SLK + merge + substitute`（动态表合并）
**我们**：`Wc3DefStore` + `*Def.from_slk_record`（静态类型 + Resource）

**评价**：我们更类型安全（GDScript 编译时检查），HiveWE 更灵活（无 schema 限制）

**对 vibecoding 的指导**：
- ✅ **保持** 我们 *Def 路线（已落地）
- ⚠️ **加新字段** 在 *Def 加 `@export` + `from_slk_record` 加解析（一致风格）
- ❌ **不要照搬** `add_column`（动态列）—— 我们表格固定，schema 固定

### 8.5 `Map::tilesets` vs 我们的 `Wc3GroundTileCatalog`

**HiveWE**：`tilesets` 是 Map 的成员（运行时变）
**我们**：`Wc3GroundTileCatalog` 是全局 Catalog（Autoload 风格）

**差异**：
- HiveWE 切图 = 切 SLK
- 我们切图 = 改 `Wc3TerrainTileCatalog.load_default()` 然后再 build

**对 vibecoding 的指导**：
- 保持现状（Catalog 简单）
- 切图支持可以加在 `MapLoader`：按 `map_dir/main_tileset` 选 Catalog
