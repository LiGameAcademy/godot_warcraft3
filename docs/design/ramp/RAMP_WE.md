# WE / HiveWE 斜坡实现思路

> **角色**：重做斜坡前的**领域权威**（只讲 WE 怎么想、怎么算；不写本仓库实现清单）。  
> **对照源码**：本地 `_ref/HiveWE`（gitignored）  
> - 落旗：`src/brush/terrain_operators.cpp` → `CliffOperator::update_ramp` / `apply_ramps`  
> - 表现：`src/base/terrain.ixx` → `update_cliff_meshes` / `is_corner_ramp_entrance` / `update_ground_heights` / `update_ground_exists`  
> **本仓库状态**：Logic（Paint + Collect）✅；Present：CliffTrans + 挂崖前过滤 + dig/入口 undig + **入口低角 +0.5**✅。  
> **分层纪律**：地形/悬崖 Present **不读**斜坡 Collect；挖洞/藏崖由 Loader / 斜坡编排调 Logic 过滤或对方 API。  
> 最后更新：2026-07-28

---

## 1. 一句话

**斜坡 = 便宜的「高→低 落 FLAG_RAMP」+ 贵的「扫窗匹配 CliffTrans 并派生 romp / 挖洞 / 半层抬高」。**

笔刷**不选模型、不改层高**；宽坡 / 转角靠**多次紧邻落旗**叠出来，mesh 全靠重建时图案匹配。

经典 World Editor 无开源实现；HiveWE 是目前最接近的可对照开源。下面称「WE 思路」= **HiveWE 行为**（与手测经典 WE 一致的部分）。

---

## 2. 两段流水线

```text
┌────────────── Paint（编辑）──────────────┐
│  点击高台角点                              │
│  → 推断坡向（鼠标相对角点）                  │
│  → 门禁（3 点低层 / 侧邻不高 / 对向轴禁贴）   │
│  → 写 corner_ramp（= W3E FLAG_RAMP）       │
│  → 可顺带写 cliff_texture                  │
│  ✗ 不写 TAG / romp / 层高 / mesh           │
└──────────────────┬───────────────────────┘
                   │ 脏区扩大后
                   ▼
┌────────────── Rebuild（表现）────────────┐
│  清空 romp → 滑窗匹配 2×3 竖/横图案        │
│  → 拼 CliffTrans 路径（A/L 四字）          │
│  → 写 romp、挂 mesh                        │
│  → 入口格不挖洞；入口低角 GPU 高 +0.5       │
│  → 地表贴图优先 cliff/romp                 │
└──────────────────────────────────────────┘
```

| 阶段 | HiveWE 入口 | 权威输出 |
|------|-------------|----------|
| Paint | `apply_ramps` → `update_ramp` | `corner_ramp[]`（布尔，存盘） |
| Rebuild | `update_cliff_meshes` 等 | `corner_romp[]`（运行时）+ CliffTrans 实例 + 地面洞/高度微调 |

---

## 3. 数据：什么进地图、什么只在运行时

| 名字（HiveWE） | 存盘？ | 含义 |
|----------------|--------|------|
| `corner_ramp` | **是** | 顶点「在坡上」。W3E 旗位 bit，本仓库 `FLAG_RAMP = 4` |
| `corner_layer_height` | 是 | 层高；**刷坡不改它** |
| `corner_romp` | **否** | 「这一格放了 CliffTrans 过渡」。匹配成功才写 |
| `corner_cliff` | 运行时派生 | 直崖格（四角层高不全等） |

`Corner` 结构里同时有 `ramp` 与 `romp`（`terrain.ixx`）：名字易混——**ramp=旗，romp=已匹配过渡模**。

注释原意（意译）：CliffTrans 会从崖边探出一格，所以一半过渡格**没有** `cliff` 旗，靠 `romp` 标记。

---

## 4. Paint：`update_ramp`

### 4.1 前提

- 光标落在**高侧**角点：`origin_level = layer[i,j]`，`target_level = origin_level - 1`。  
- 坡向 `horizontal` / `vertical` ∈ `{-1,0,1}`，由鼠标世界坐标相对格子中心决定（`apply_ramps`）：  
  `horizontal = (mouse.x > i) - (mouse.x < i)`（竖直同理）。  
- 一次调用最多同时尝试 **横臂、竖臂、对角 3×3**。  
- **本仓库 UX**（相对 HiveWE）：① `soften_dirs` 轴向主导 → 更容易单列；② 点在低侧时 `plan_from_pointer` 解析到邻域高角朝点击落坡（单轴候选不试对角 toward）。
- **三种落旗变体（必须区分）**：
  - **straight**：单列 3 点（可邻列加宽）。
  - **l**：横臂+竖臂 + **仅凹口中心**。单轴补第二臂，或双轴但尚未两臂齐时，走 L 不升 3×3。
  - **diagonal**：① 空外角双轴一次 9 点；② **L 已成型**（原点横竖臂都齐）后再双轴 → 升满 3×3。
- **低侧回退选原点**：优先「点击落在从原点沿坡向的轴上」的方案。
- **禁止**：单轴 / 未齐 L 时自动升 3×3。

### 4.2 方向门禁 `check_ramp_direction(dir_x, dir_y)`

对某一轴方向（例如 `(±1,0)` 或 `(0,±1)`）：

1. **三步都在地图内**（含原点共 3 点：`step=0..2`）。  
2. **后两步**层高必须等于 `target_level`（低一层）。  
3. **垂直侧邻**（相对坡向的左右）层高不得 **高于** `origin_level`。  
4. **紧贴对侧斜坡禁门**（对齐 HiveWE `check_ramp_direction` line 448-459）：若侧翼 corner 已有 ramp 但沿本坡向延伸不齐 → 拒绝。避免细脊两侧各落一条坡的视觉错位。  
5. **侧翼禁贴**：若侧向邻点已有 ramp：  
   - 沿本坡向有完整 3 点臂 → 允许（平行加宽）；  
   - 或侧邻属于从原点出发的垂直完整臂（L / 半侧转角）→ 允许；  
   - 否则拒绝（畸形贴边）。  

横、竖分别过门禁；对角还要求 3×3 内除原点外各点都是 `target_level`（**不**走侧翼/对侧列门禁）。**单轴**补 L 时不升对角；**双轴**且盒合法时可从 L 升满 3×3。

### 4.3 落旗形状

| 条件 | 写入 | variant |
|------|------|---------|
| 仅横合法 | 沿 X 共 **3** 点 | `straight` |
| 仅竖合法 | 沿 Y 共 **3** 点 | `straight` |
| 双轴+对角盒且（空角 **或** L 两臂已齐） | **3×3** 全写 | `diagonal` |
| 单轴补第二臂 / 双轴但仅一臂 | 缺臂 + **仅 L 中心** | `l` |
| 两臂已齐、只缺中心 | **只标中心** | `l` |

落旗时顺带把这些角的 `corner_cliff_texture` 设成原点崖贴图下标。

### 4.4 宽坡 / 转角在 Paint 里长什么样

- **宽坡**：沿崖方向再点邻列/邻行 → 又一次 3 点；**不是**一次写 9/15/21 点规模。  
- **外角整块（diagonal）**：空角上鼠标双轴且 3×3 皆低 → 一次 9 点。  
- **转角 L**：先一臂再另一臂（或双轴但原点已有臂）→ 两臂 + **只补中心**；Collect 出 `LABH`/`BALH` 等。恰一低角崖格按入口 undig +0.5。

### 4.5 Paint 明确不做

- 不改 `corner_layer_height` / 最终高度权威数组  
- 不写 `romp`、不拼 `CliffTrans****` 文件名  
- 不用「度数 / 连通点数 ∈ {3,9,15,21,27}」抽象

---

## 5. Rebuild：`update_cliff_meshes`

对脏区（再扩 2 格）：

1. 删掉区内已有崖/坡 mesh 记录。  
2. **清空**区内 `corner_romp`。  
3. 对每个格角 `(i,j)` 尝试匹配：

### 5.1 竖直 2×3 窗（高差沿 Y）

看角点：`bl, br, tl, tr` 以及上排 `ttl, ttr`（`j+2`）。

匹配条件（摘要）：

- 中排层高等于「下角与上角的 min」（坡面中间一行贴齐）。  
- 左列三格 `ramp` 全同，右列三格 `ramp` 全同，且 **左右列 ramp 相反**（一侧是坡脊、一侧不是）。  

命中则拼文件名四字（见下），加载  
`doodads/terrain/clifftrans/clifftrans{TAG}0.mdx`，  
并标记 `romp[bl]=romp[tl]=true`，然后 `continue`（本格不再放直崖）。

### 5.2 水平 2×3 窗（高差沿 X）

对称：左列 / 右列换成「下行三格 vs 上行三格」`ramp` 相反。命中后 `romp[bl]=romp[br]=true`。

### 5.3 TAG 字符（A / L）

相对 `base = min(相关角层高)`：

```text
若该角有 ramp：  char = 'L' + (layer - base) * (-4)   // 走 L 族偏移
否则：          char = 'A' + (layer - base)           // 与直崖 A/B/C 同族
```

四字顺序在竖窗 / 横窗里不同（见源码 1080–1113 行），对应 `CliffTrans` 资源名，**不是**直崖 `CliffsABCD`。

City 族路径前缀换目录（本仓库用 `CliffTypeDef.ramp_model_dir` → `CliffTrans` / `CityCliffTrans`）。

### 5.4 直崖回落

未匹配成 CliffTrans、且该格是直崖、且**不是**入口 → 按直崖 A/B/C + variation 放普通 Cliffs。

入口格：`is_corner_ramp_entrance` 为真则 **跳过**直崖模（地面要留着走）。

---

## 6. 入口、挖洞、半层高度

### 6.1 入口判定 `is_corner_ramp_entrance(x,y)`

**经典（HiveWE）**：地表格四角 **全部** `corner_ramp`，且 **不是**「对角层高两两相等」的平坦四角：

```text
ramp[bl]∧ramp[br]∧ramp[tl]∧ramp[tr]
∧ ¬(layer[bl]==layer[tr] ∧ layer[tl]==layer[br])
```

**L 凹陷扩展（本仓库）**：恰一角为四角最低，且该角与其两边邻角有 `ramp`（L 补心时常出现「高角无旗」）。按入口处理：undig + 低角 +0.5，三高一低地面朝补心下凹。

**L ≠ 对角（地形 Mesh）**：

| | 对角 | L |
|--|------|---|
| 视觉 | 3×3 顶点从高角到低角插值（约 2×2 地块连成一片斜面） | **仅内角 1 格** 2×2 顶点下凹 |
| Present | 经典四角入口可 undig 多格 | **L 凹槽 2×2 四格** undig + 藏直崖；只对凹陷低角 +0.5；三低一高不 boost（防伪对角） |

### 6.2 挖洞 `update_ground_exists`

地表格默认存在；若  

`(有模 CliffTrans footprint)`  

→ **挖掉**地面四边形（坡身用 CliffTrans 盖）。  
裸 `romp`（匹配到但无 GLB）**不挖**——避免无模灰缝。  
直崖洞仍由 `cliff_gap_mask` 负责，**不再**因「是崖格」就在斜坡 dig 里重复挖。

**入口格**（经典两低两高 / L 凹陷）→ undig + 藏直崖，用地形 Mesh 走通道；**hide 与 undig 同源**，禁止只藏崖不填地（灰缝）。  
L 邻域的两低两高经典入口仍 undig（坡口地面）；三低一高不 undig（防伪 3×3 对角）。  
**有旗无 CliffTrans**：保留直崖（对齐 WE fallback），**不要**把「四角沾到 ramp」的崖格一律 undig/藏崖——会误删坡后崖墙拉出竖缝。也不要因 L 而强制挖无模兄弟格。

CliffTrans 竖/横 footprint 各 **2 格**（崖格 + 探出格）；探出格常无 `cliff`，必须靠 footprint 挖掉，否则会只挖一格。  
例外：L 凹陷外角平底格（低角所在、非崖）即使落在双臂 footprint 内也 **不挖**，否则内角灰缝。  
坡身 footprint **优先于** undig（邻列加宽后入口判定变真也不能把坡身填回去；L 外角平底除外）。

### 6.3 入口抬高 `update_ground_heights`

先算普通：`gpu_h = height + layer - 2`。  
再扫入口格：四角都在坡上且有层差时，对 **层高 == 四角 min（低侧）** 的角，GPU 高度再 **+0.5**（半层），让坡脚地面贴过渡模。赋值幂等（多格共享同一角可重复写）。

### 6.4 地表贴图 `real_tile_texture`

优先级：**附近 romp /（崖且本角非 ramp）** → 用崖地砖映射；否则 blight；否则普通地表。  
这样坡身周边会染成崖脚纹理。

---

## 7. 和「手感」的对照（避免再走错路）

| 手感现象 | WE 真实机制 |
|----------|-------------|
| 一次刷出「一列坡」 | 一次 3 点 FLAG |
| 坡变宽 | 邻列再刷一次 3 点 |
| 外角一块三角/方坡 | **空角**双轴 → `diagonal` 3×3；已有一臂再补 → `l`（臂+中心） |
| 蓝菱形很多、模很少 | 旗可以密，CliffTrans 只认特定 2×3 图案 |
| 内角平底 | 双臂 + L 中心 → Collect `LABH`/`BALH`；L 凹陷入口 undig+0.5 |
| 点在低处刷不动 | `target = origin−1`，必须点高台 |

**错误模型（已废弃）**：用连通落旗点数 3/9/15/21/27 或「度数」在一次 `paint` 里表达形态——那是把 Rebuild 的事塞进 Paint，难对齐、难 review。

---

## 8. 映射到本仓库（契约，非实现）

| WE | 本仓库应对 |
|----|------------|
| `corner_ramp` | `flagsPacked & FLAG_RAMP` / `Wc3TileVertex.has_ramp`（已有） |
| `update_ramp` | ✅ `Wc3RampLogic.paint_*` ← `Wc3RampPaint`（只写旗 + cliff_tex） |
| `corner_romp` + CliffTrans 列表 | ✅ `Wc3RampCollect` ← `Wc3RampLogic.collect_placements`（与 cliff 拓扑分离） |
| `update_cliff_meshes` 匹配 | ✅ Collect 滑窗；Catalog `glb_path` resolve |
| 挖洞 / +0.5 / 挂模 | Logic：`plan_dig_*` / `plan_entrance_height_boost` / `filter_cliff_placements`；Loader 挂崖前过滤；Present：`apply_ramp_dig(..., boost)` + CliffTrans |
| 鼠标方向 | ✅ Editor `terrain_brush` 传入 ±X/±Y |

### 8.1 Present 所有权（禁止反向依赖）

```text
直崖：Wc3CliffLogic.build_topology → cliff_gap_mask（仅直崖）
      MapLoader：ensure_ramp → filter_cliff_placements → MapCliffLayer.build
      MapCliffLayer 只消费已过滤的 cliff_placements（不读 ctx.ramp）

斜坡：Wc3RampLogic.collect → ctx.ramp
      MapRampLayer.build：
        · terrain.apply_ramp_dig(dig, entrances, boost)
          ← romp∪cliff 挖洞；入口 undig；入口低角 bake +0.5（不写 HF）
        · 挂 CliffTrans（instance_transform_trans）
      可选后置：脏区；其它地面补洞（一般不需要——坡身=CliffTrans）
```

### 8.2 跳过直崖算法（按模型实例，挂模前过滤）

直崖一格可有多块叠段（`cliff_slices_at`：跨度>2 时每 2 层一块，最多约 4 块）。必须以 **(ix,iy,piece_base)** 判断，对齐 WE `continue`（**不**事后 MultiMesh 零缩放）：

1. **入口格**：该格全部直崖 placement 都跳过（留地面通道）。
2. **CliffTrans footprint 覆盖**（竖窗 `(i,j)+(i,j+1)`；横窗 `(i,j)+(i+1,j)`），且高度带相交：
   - 崖块 `[piece_base, piece_base+2)` ∩ 坡 `[ramp_base, ramp_base+2)` 非空 → **只跳过该块**。
3. 否则保留（高台上层叠段可留，避免整墙消失）。

Logic：`Wc3RampCollect.should_hide_cliff_piece` / `filter_cliff_placements`；编排：`MapLoader._apply_ramp_cliff_filter`。

**禁止**：`MapTerrainLayer` / `MapCliffLayer` 根据 `ctx.ramp` / romp 自行改洞或跳过实例。  
**禁止**：在 `Wc3CliffLogic.build_topology` 里 `merge` 斜坡挖洞（已拆除）。
**禁止**：依赖 MultiMesh 零缩放藏崖（崖 shader / 奇异矩阵不可靠）。

分层纪律仍遵 [LAYERED_ARCHITECTURE.md](../../architecture/LAYERED_ARCHITECTURE.md)：Paint/Collect 在 Logic，mesh 在 Present，禁止 Layer 内选型。

与直崖关系：直崖已完成 `milestone/cliff-layered`；斜坡是 **平行通道**，共享层高与 Catalog 族目录，不塞进 `Wc3CliffLogic.paint_corner`。

**改崖清坡**：只清**层高实际变更的顶点**所穿过的连续 `FLAG_RAMP` 臂（自身 + 四向各最多 2 步，遇空停）。  
**禁止**：刷点 ±2 方阵、脏区 AABB、Document 再 `clear_flags_around` 一次（会误删平行邻列仍合法的坡）。  
蓝菱形随 rebuild 读旗消失。

勿与 ROADMAP **⑩ 应用高度**（装饰物贴地）或「纯高度坡 B」混淆——那些不写 `FLAG_RAMP`、不挂 CliffTrans。

---

## 9. 建议验收顺序（重做时）

1. **只 Paint**：✅ 蓝菱形 + `selftest_ramp_logic`；点高侧 3 点；邻列加宽；低侧拒绝。  
2. **Collect**：✅ `selftest_ramp_data` / Lost Temple 滑窗统计。  
3. **Present 核心**：✅ 挂 CliffTrans + 挂崖前按叠段过滤直崖 + dig/入口 undig + **入口低角 +0.5**（`selftest_ramp_present`）。  
4. **Present 后置**：脏区与 City 族细化；手测坡脚贴合。

---

## 10. 源码索引

| 主题 | 文件 | 符号 |
|------|------|------|
| 笔刷循环 | `terrain_operators.cpp` | `apply_ramps` ~L331 |
| 落旗 | 同上 | `update_ramp` ~L406 |
| CliffTrans 匹配 | `terrain.ixx` | `update_cliff_meshes` ~L1047 |
| 入口 | 同上 | `is_corner_ramp_entrance` ~L819 |
| +0.5 | 同上 | `update_ground_heights` ~L903 |
| 挖洞 | 同上 | `update_ground_exists` ~L1002 |
| 贴图优先 | 同上 | `real_tile_texture` ~L711 |
| W3E 读写 ramp | 同上 | load/save flags 中 `corner_ramp` bit |

本地克隆：`_ref/HiveWE`（见根目录 `.gitignore`）。经典 0.3 可执行对照路径见 `.cursor/rules/hivewe-cliff-reference.mdc`。
