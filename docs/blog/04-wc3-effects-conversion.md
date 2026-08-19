# 魔兽争霸 3 特效是怎么转到 Godot 的？

> 副标题：MDX 里的粒子 / 显隐 / 绑骨小件，为什么不能「一键 glTF」完事  
> 面向：对复刻或管线好奇的读者（非必须读过本仓库）  
> 工程细节：[PE2_GODOT.md](../design/asset-convert/PE2_GODOT.md) · [ATTACHMENTS_BAKE.md](../design/asset-convert/ATTACHMENTS_BAKE.md) · [MDX_SKINNING_GODOT.md](../design/asset-convert/MDX_SKINNING_GODOT.md) · [tools/asset-convert/README.md](../../tools/asset-convert/README.md) · [ASSET_LANES.md](../architecture/ASSET_LANES.md)  
> 最后更新：2026-08-19

---

## 先说结论

1. **WC3「特效」不是一种东西**：至少包括 **ParticleEmitter2 粒子**、**Ribbon 拖尾**、**Light 光晕**、**按动画序列切换的 Geoset 显隐**，以及绑在骨头上的 **小件网格**（旗子、铃铛等，观感上也像特效）。
2. 通用 MDX→glTF（我们用的 `war3-model` / m2g 链路）**可靠导出骨骼 + 主网格**；粒子参数、很多绑骨小件、序列作用域的显隐 **进不了标准 glTF**。
3. 本项目的做法是：**网格走 glTF/.scn**，特效走 **旁路 JSON + Godot 运行时/烘焙拼装**——粒子 → `*.pe2.json` → `GPUParticles3D`；显隐 → `*.geosetvis.json`；小件/挂点 → `*.attachments.json` 再烤进 `.scn`。
4. 目标是 **观感对齐原作**，不是位级复刻整个 Warcraft 粒子虚拟机；Ribbon / 部分 Light 仍在补齐路上。

---

## 1. 原作里「特效」藏在哪？

魔兽单位、建筑、装饰物的视觉，绝大多数来自 **MDX/MDL**。一个模型大致是：

| 块 | 干什么 | 例子 |
|----|--------|------|
| **Geoset** | 主网格（可多份，可按动画藏起来） | 城墙、兵模身体；建造尘「出现」时常靠显隐 |
| **Bone / Helper** | 骨骼与挂点 | 旗杆骨、手持点 |
| **ParticleEmitter2（PE2）** | 广告牌粒子发射器 | 主城训练烟、火盆、法术尾迹 |
| **RibbonEmitter** | 拖尾带 | 武器挥砍残影 |
| **Light** | 点光 / 光晕参数 | 铃铛、火把 |
| **Sequences** | 命名动画时间轴 | `Stand` / `Birth` / `Work` / `Portrait` |

玩家口头说的「特效」，在数据里经常是 **PE2 + 材质混合模式（Additive 等）+ 某几个 Geoset 在某 Sequence 里显示**，而不是单独一个「FX 文件」。

技能抛射、命中闪光等 **独立特效模型**（`Abilities/...`、`Splats` 等）走的是同一套 MDX 规则；本仓库当前重点是 **地图单位/建筑自带发射器与绑骨件**，技能弹道可复用同一管线，但玩法接线后置。

---

## 2. 为什么不能只靠 glTF？

把 MDX 转成 glTF/GLB 之后，Godot 能直接吃到：

- 骨骼与蒙皮网格  
- 大部分材质贴图（我们另把 BLP→PNG）  
- 一部分骨骼动画  

但 **ParticleEmitter2 没有对应的 glTF 扩展** 被我们的转换器写进去。若强行忽略：

- 主城 **没有训练烟 / 建造尘**  
- 火盆、喷泉等 **装饰粒子全无**  
- 只剩「素模」

另外还有坑：

- Helper 绑的小件在 glTF 里常变成 **空节点**（有名字、无 mesh）——旗子、时钟指针会丢。  
- Geoset 的 **按 Sequence 缩放/Alpha 显隐**，经 Godot `GLTFDocument` 后 **scale 轨常丢**，建造阶段「半成品 geoset」会对不齐。

所以策略是：**标准能表达的进 glTF；表达不了的写 sidecar，在 Godot 侧还原。**

---

## 3. 总管线（一张图）

```text
经典 MPQ 里的 .mdx / .mdl
        │
        ▼  tools/asset-convert（Node：war3-model 解析）
        │
        ├─► *.gltf + *.bin + PNG     （主网格 / 骨骼 / 动画）
        ├─► *.pe2.json               （ParticleEmitter2 参数旁路）
        ├─► *.geosetvis.json         （各 Sequence 下 Geoset 显隐采样）
        ├─► *.attachments.json       （绑骨小件 / 粒子挂点清单）
        │
        ▼  Godot headless 烘焙（可选但推荐）
        │
        ├─► 同目录 *.scn             （免运行时 GLTFDocument；拼装 attachment）
        └─► 可选 assets/pe2-prefabs/*.pe2.tscn（粒子可编辑预制）

运行时 MapModelCache / 单位层：
        实例化 .scn 或 glTF
        + Wc3Pe2Particles.attach_to（读 pe2.json / 预制）
        + 播动画时按 Sequence 开关粒子 / geoset 显隐
```

资产只落在 `assets/asset-converted/`（视觉车道），规则见 [ASSET_LANES.md](../architecture/ASSET_LANES.md)。**不把暴雪原资产提交进 git**；仓库提交的是工具、契约，以及可选的 `pe2-prefabs` 等非贴图预制。

---

## 4. 粒子：ParticleEmitter2 → `pe2.json` → GPUParticles3D

### 4.1 转换期写什么？

`convert-mdx.js` 遍历 MDX 的 `ParticleEmitters2`，为每个发射器抽出近似参数，例如：

- 速度 / 重力 / 寿命 / 发射率 / 发射面宽高  
- 贴图路径（BLP→已转 PNG 的逻辑路径）  
- 行列帧动画、FilterMode（混合）  
- 段颜色 / Alpha / 缩放关键  
- 相对模型的 **pivot**（并做 WC3→glTF 坐标变换）  
- **`active_sequences`**（v2）：  
  - `null` → 全程可发射（火盆）  
  - 字符串数组 → **仅这些 Sequence 名**下发射（例如只在 `Work` / `Birth`）

可选再带上 Visibility / EmissionRate 关键采样，供调试或更细控制。

结果写在模型同 stem：`TownHall.gltf` 旁的 `TownHall.pe2.json`。

### 4.2 运行时怎么挂？

`scripts/map/presentation/effects/wc3_pe2_particles.gd`（`Wc3Pe2Particles`）：

1. 按 GLB/glTF 路径找 `*.pe2.json`（或优先实例化 `assets/pe2-prefabs/.../*.pe2.tscn`）。  
2. 在 **模型 0.01 缩放根**下挂 `Pe2Root`（避免粒子飞出地图——WC3 单位很大，我们统一缩到 Godot 尺度）。  
3. 每个发射器变成一个 `GPUParticles3D`（广告牌 + 近似参数；不是 1:1 还原整个 PE2 状态机）。  
4. 单位切动画时调用 `apply_sequence(root, "Stand"|"Work"|…)`，按 `active_sequences` **开/关 emitting**。

批量导出预制：

```bash
godot --headless --path . -s res://scripts/tool/export_pe2_scenes.gd -- --include Buildings/Human/TownHall --force
```

### 4.3 和「技能特效」的关系

技能命中、投射物若也是 MDX+PE2，**同一套 pe2 旁路可以挂**；差别在玩法层何时 `instance`、跟哪个节点、何时 `queue_free`。地图建筑烟尘已经在编辑器/游戏放置模型时 `attach_to`。

---

## 5. 「变出来 / 藏起来」：Geoset 显隐旁路

不少「特效感」其实是 **换 geoset**：

- 建造 Birth：灰尘 geoset 出现再消失  
- 升级：额外构件显示  
- Portrait：只显示头模相关 geoset  

转换器把每个 Sequence 时间窗里的显隐采成 `*.geosetvis.json`。  
`MapModelCache` 加载/烘焙时注入 `Geoset_*:visible` 动画轨，避免 Godot 丢掉 scale 轨后「永远全显示」或「永远不显示」。

这和粒子是正交的两条线：**网格显隐 + 粒子发射** 常一起构成原作观感。

---

## 6. 绑骨小件与挂点：`attachments.json` + 烤 `.scn`

旗子、时钟指针、铃铛等是 **Helper + 引用某 Geoset**，不是独立粒子。纯 glTF 常留下空壳节点。

做法（详见 [ATTACHMENTS_BAKE.md](../design/asset-convert/ATTACHMENTS_BAKE.md)）：

1. 转换时写出 `attachments.json`：类型（mesh / particle / light / ribbon）、绑哪根骨、引用哪个 Geoset 或 pe2 源、变换。  
2. `export_model_scenes.gd` 烤 `.scn` 时创建 `BoneAttachment3D`，挂上 `MeshInstance3D` 或粒子节点。  
3. 动画尽量合并进主 `AnimationPlayer`，运行时一次切动画带动全身。

粒子既可以在 **运行时 attach_to**，也可以在烤场景时按 attachment 清单嵌进去——以当前实现与 visuals 配方为准；对使用者而言：**重转模型 + bake scn** 后，建筑烟与旗子应一起回来。

---

## 7. 材质向的「特效感」

MDX FilterMode（如 Additive / AddAlpha）会映射到材质命名约定（如 `_fm3` / `_fm4`），Godot 侧用对应混合，让光晕、软烟不画成实心块。这不单独占一个 json，但属于特效观感的一部分；缺了会出现「白片 / 黑块」。

---

## 8. 已知差距（诚实清单）

| 项 | 状态 |
|----|------|
| PE2 → GPUParticles 近似 | ✅ 常用建筑/装饰可用；参数非位级一致 |
| Sequence 开关粒子 | ✅ `active_sequences` |
| Geoset 序列显隐 | ✅ geosetvis + bake |
| 绑骨小件 mesh | ✅ attachments 方案（按模型覆盖度仍在补） |
| RibbonEmitter | 🟡 清单有类型，保真度有限 |
| Light 块 | 🟡 部分用灯/材质近似 |
| 全技能弹道库批量验收 | 📋 玩法层后置 |
| MDX Portrait Camera | 📋 HUD 肖像暂用启发式相机 |

---

## 9. 自己跑一遍（最小命令）

```bash
# 在 tools/asset-convert
npm install
# 例：重转人族主城（含 pe2 / geosetvis / attachments）并 bake .scn
npm run convert -- --include "Buildings/Human/TownHall/**" --force
```

Godot 里打开地图或编辑器，选中主城：应能看到模型；训练/建造相关 Sequence 下应有烟尘类粒子（具体以该模型 pe2 的 `active_sequences` 为准）。

更多开关见 `tools/asset-convert/README.md`（`--skip-scn`、`--workers`、只补 pe2 预制等）。

---

## 10. 设计取舍（给同好）

- **旁路 JSON 而不是改 glTF 扩展**：工具链简单、可 diff、可原子写盘；Godot 版本升级少绑自定义扩展。  
- **GPUParticles 近似而不是软件粒子 VM**：性能与可维护性优先；要对着原作调的是贴图、寿命、发射率与 Sequence 门闩。  
- **预制 pe2.tscn 可提交、贴图不入库**：方便协作调粒子，又不把暴雪 PNG 推进 git。

若你只做「能看见烟」，PE2 旁路就够；若要「主城像原作一样挂满旗与钟」，必须上 attachments 烘焙。两条线解决的是 MDX 里 **不同子集** 的问题。

---

## 相关代码速查

| 环节 | 路径 |
|------|------|
| MDX 转换 + 写 pe2/geosetvis/attachments | `tools/asset-convert/src/convert-mdx.js` |
| 粒子运行时 | `scripts/map/presentation/effects/wc3_pe2_particles.gd` |
| 导出 pe2 预制 | `scripts/tool/export_pe2_scenes.gd` |
| 模型 .scn 烘焙 / 拼装 | `scripts/tool/export_model_scenes.gd` |
| 小件方案长文 | `docs/design/asset-convert/ATTACHMENTS_BAKE.md` |
| 资产车道 | `docs/architecture/ASSET_LANES.md` |
