# 武器飞弹（Weapon Missile）→ Godot Present

> **层**：资源映射（MDX → pe2/gltf/sidecar）+ 表现（`Wc3FxPresenter` / `Wc3Pe2Particles` / 未来 Ribbon·Shader）+ 玩法挂载（`combat_projectile_shell`）。  
> **范围金样**：牧师 `PriestMissile`、大法师 `FireBallMissile`、水元素 `WaterElementalMissile`。  
> **相关**：[PE2_GODOT.md](../asset-convert/PE2_GODOT.md) · [COMBAT_SYSTEM.md](../game/COMBAT_SYSTEM.md) · `Wc3FxPresenter`  
> **最后更新**：2026-09-06  
> **手测烤本**：`tmp/model-review/Abilities/Weapons/{FireBallMissile,PriestMissile,WaterElementalMissile}/`（gitignore）

---

## 1. 目标

抛光三单位**普攻飞弹**视觉：对齐经典 MDX 语义，在 Godot 里用：

1. **GPUParticles3D** ← ParticleEmitter2（已有主路径）  
2. **FxBillboard / 软圆** ← Additive·少面 geoset（`Wc3FxPresenter`）  
3. **Shader / 专用节点** ← GPU 粒子映射失败或观感明显不对的部分（Ribbon、真 Tail、拖尾光带等）

原则：**先分类、再选型**；禁止按单位名写死分支（可按路径族 / mesh 语义 / pe2 flags 判定）。

### 1.1 原作过时诊断（FireBall 标本）

WC3（~2002）特效不是「画质差」这么简单，而是**为固定管线 / 低 fill-rate / CPU 粒子**堆出来的幻觉。重构前先拆：**哪些是时代妥协（可换现代手段），哪些是辨识度意图（要保留）**。

#### 仍值得保留的意图（语义层）

| 意图 | FireBall 里怎么体现 |
|------|---------------------|
| 飞行可读光核 | 中心亮、外圈暖黄，远距离仍能认出「一颗火球」 |
| 运动感 | 身后烟迹 + 焰核拖尾，方向一眼可读 |
| 命中反馈 | 短促爆开（暖黄→红）、光闪一下再灭 |
| 阶段切分 | Stand 飞行 / Death 命中（Birth 几乎空）——玩法壳仍可沿用 |

#### 过时的实现手段（技术层）

| # | 原作做法（FireBall 实测） | 为何过时 | 现代替代方向 |
|---|---------------------------|----------|--------------|
| 1 | **交叉/少面 Additive 网格装球体**（G0≈29 vert / 30 face，绑多骨；再叠 G1 单四边形 `lensflare1A` α≈0.3） | 用几何「糊」成球，靠 Additive 叠亮；侧看穿帮、近看硬边 | **单 Billboard / 径向 soft-orb shader**（一张程序圆或噪声球，朝相机） |
| 2 | **粒子 = 朝相机的 Quad + Head/Tail 标志位**（焰核 `FrameFlags=3` Both，`TailLength=0.25`） | 无连续丝带、无速度场拉伸；Tail 是第二套扁片，不是真实拖尾 | GPU 粒子 **velocity-align + stretch**，或短 **TrailMesh**；不必 1:1 复刻 Head+Tail 双套 |
| 3 | **三档色/透明/缩放关键帧**（SegmentColor / Alpha / ParticleScaling 各 3 点） | 固定函数时代的曲线卡；无法做噪声湍流、温度场 | 一条曲线或 **ramp 纹理** 驱动；可加简单噪声位移 |
| 4 | **8×8 精灵表当「云爆」**（Death `Clouds8x8`，`LifeSpanUV`/`DecayUV` 切格） | 预烘焙序列帧，分辨率与帧数锁死；现代仍可用，但只适合「一次性爆」 | 保留 sheet **或** 少量粒子 + soft disk dissolve；不要把飞行核也做成 sheet |
| 5 | **点光 Omni 硬衰减**（Intensity 7，Att 80→200 WC3 单位） | 无 GI、无体积散射；只是「亮一下周围」 | 短寿命 **Omni + 可选雾/辉光**；或纯 screen bloom，不必 MDX 同参 |
| 6 | **Sequence 开关发射器**（visibility / active_sequences 切 Stand↔Death） | 逻辑清晰但粗糙：关闸=粒子瞬间没，开闸=脉冲喷 | 保留「飞行态 / 命中态」状态机；过渡用 **lifetime 自然收束** 而非硬切 mesh |
| 7 | **贴图语义混杂**（烟 `Dust5ABlack` Blend、焰 `Dust6ColorRed` Additive、壳 `Dust6Color`、爆 `Clouds8x8`） | 美术靠手工叠层凑色；同资产多路径复用 | Present 层用 **tint/ramp 统一色温**，减少「五张灰图硬叠」 |

#### 诊断结论 → 重构原则（修订）

```text
可做：按 geoset / PE2 / Ribbon 的「几何·材质·发射语义」选型（soft-orb shader、Tail 拉伸、Trail…）
不可做：按资源路径整包抛弃 MDX、手写白名单重写 Present（无法推广到法杖/光环/建筑装饰）
```

试刀 `FireballMissileModern`（路径含 `fireballmissile` 即整包 ModernFX）**证明观感可行，但甄别手段不成立 → 不作为主线**。主线：

| 层 | 策略 |
|----|------|
| 树结构 | **保留** Armature / geoset 节点 / Pe2Root / Sequence |
| 单 geoset | `Wc3FxPresenter.classify_mesh` → KEEP / soft-orb / textured billboard |
| PE2 | 保留 emitter；缺口用 stretch / UV / rate 补 |
| Ribbon | sidecar + Trail，仍绑原节点 |

### 1.2 甄别手段：只能「部件级」，不能「资产级整包」

| 能自动判的（推荐） | 依据 | 例 |
|--------------------|------|-----|
| Additive·少面·近正方 AABB | 面数 / aspect / blend | 火球壳、牧师星闪 → soft-orb |
| ≤4 三角扁片 | 面数 | lensflare、箭矢贴图 → billboard |
| 水平极薄盘 | Y≪XZ | 法师光环脚底 → **KEEP**（勿竖广告牌） |
| 细长高 aspect | aspect + 面数 | 实体矛/斧 → KEEP |
| PE2 Head/Tail / sheet | `frame_flags` / rows×cols | 拉伸或播格，仍挂原 emitter |
| RibbonEmitter | sidecar type | Trail，不塞进 GPUParticles |
| TeamGlow / TeamColor | replaceable / attachments kind | 单位队色与法杖辉光，**与武器飞弹分流** |

| 不能可靠判的（禁止） | 为何 |
|----------------------|------|
| 「这个 MDX 整文件该不该重写」 | 同一文件常混：糊球 + 实体 + 光环 + 绑点装饰 |
| 路径名 / 单位 ID 白名单 | 法杖特效、建筑旗、技能 attach 会漏或误伤 |
| 「飞弹目录就全现代化」 | `Abilities/Weapons/Axe` 是实体斧，不能当火球 |

**大法师法杖**：属单位模型上的 TeamGlow / 绑点小件，走 `attachments` + team_glow 分流；与武器 `FireBallMissile` 不是同一类决策，也不该进飞弹白名单。

### 1.3 试刀归档（已否决为主线）

| 组件 | 状态 |
|------|------|
| `FireballMissileModern` 路径整包 | **spike only**；`wants()` 已关闭 |
| `wc3_fx_soft_orb.gdshader` | **保留**，并入 `Wc3FxPresenter` 对 `SOFT_SPHERE` |
| tmp `FireBallMissile_Modern.scn` | 仅对照用，非正式管线产物 |

手测正式烤本：结构保留的 `FireBallMissile.scn`（soft-orb 替换糊球 geoset，PE2 仍在）。

---

## 2. MDX 结构速查（三金样）

| | FireBall（Hamg） | Priest（hmpr） | WaterElemental（hwat） |
|--|------------------|----------------|------------------------|
| 路径 | `Abilities/Weapons/FireBallMissile/` | `…/PriestMissile/` | `…/WaterElementalMissile/` |
| Sequences | Stand / Death / Birth | Stand / Birth / Death | **仅 Birth / Death**（无 Stand） |
| Geosets | 2（Additive 球 + lensflare 四边形） | 3（AddAlpha 双瓣球 + Additive 星） | **0**（纯粒子+飘带） |
| PE2 | 3 | 2 | 3 |
| Ribbon | 0 | 0 | **1**（`BlizRibbon01`） |
| Light | 1 | 0 | 0 |
| 飞行序列（玩法） | Stand | Stand | **Birth 强制 LOOP** |
| 命中序列 | Death | Death | Death |

> **Birth 为何常「没效果」？** FireBall / Priest 的 Birth 是 **~33ms 空壳**（geoset 全隐、无 PE2 active）：WC3 模型习惯保留 Birth/Stand/Death 三件套命名，飞弹实际用 **Stand 飞 / Death 爆**。水元素反过来：**无 Stand**，Birth≈0.5s 才是飞行态（PE2+Ribbon）。

### 2.1 FireBallMissile

| 部件 | 原作角色 | 现状 Godot |
|------|----------|------------|
| G0 Additive `Dust6Color` | 飞行软火球壳 | → `SOFT_SPHERE` FxBillboard（Plan B 可选提升） |
| G1 Additive `lensflare1A` | 十字光晕面片 | → 软圆 / 广告牌 |
| PE2 `BlizParticle02` Mix 烟 | Stand 烟迹 | GPUParticles（Dust5ABlack） |
| PE2 `BlizParticle01` Additive Head+Tail | Stand 焰核 | GPUParticles；**Tail 仅为拉长 Quad** |
| PE2 `BlizParticle02burst` 8×8 云 | Death 爆开 | GPUParticles；`decay_uv` 未真播格 |
| Light | 飞行点光 | Omni + Flash；pivot 偏离主体时 `Wc3MdxOmni` 吸到视觉中心 |

### 2.2 PriestMissile

| 部件 | 原作角色 | 现状 Godot |
|------|----------|------------|
| G0/G1 AddAlpha `Sentinel` | 双瓣魔法球（交叉/叠层） | Presenter 可能 KEEP 或广告牌；**观感常偏硬/双影** → 优先 **shader 软球或单 billboard 合成** |
| G2 Additive `Star8` | 中心星闪 | 软圆 / billboard |
| PE2 `BlizParticle02v` Tail | Stand 青蓝曳迹（Dust3） | GPUParticles Tail 近似 |
| PE2 `BlizParticle01` Tail | Death 电光爆（Zap1，latitude 180） | GPUParticles 脉冲 |

### 2.3 WaterElementalMissile

| 部件 | 原作角色 | 现状 Godot |
|------|----------|------------|
| 无 Geoset / 无 `.bin` | 纯特效壳 | glTF 仅 Armature；`bake:scn` 仍可 inject PE2 |
| PE2 `BlizParticle03` Head+Tail | Birth 水滴曳迹（WaterBlobs1） | GPUParticles；飞行靠 Birth LOOP；**Birth-only 计入飞行曳迹增强** |
| PE2 `…burst` / `…burst01` | Death 水花（gravity≈770） | GPUParticles |
| **Ribbon `BlizRibbon01`** | Birth 青蓝拖尾（见下表） | **`Wc3RibbonPresenter` → `RibbonRoot`/`Wc3RibbonEmitter`**（路径条带 + Birth 平移轨） |

`BlizRibbon01`（MDX 实测，2026-09-06 重解）：

| 字段 | 值 |
|------|-----|
| HeightAbove / Below | 30 / 30 |
| Color (RGB) | ≈ (0.027, 0.463, 1) |
| Alpha | 0.9 |
| LifeSpan | 0.35 s |
| EmissionRate | 40 |
| Texture | `Textures/RibbonBlur1`（Additive 料） |
| Translation | Birth 内 Z 摆动（33→167→333→533） |

---

## 3. 映射决策树

```text
MDX 飞弹块
 ├─ Geoset
 │   ├─ Additive / AddAlpha + 少面 + 近正方 AABB → FxBillboard 软圆（wc3_team_glow billboard）
 │   ├─ ≤4 三角扁广告牌 + 贴图 → textured Billboard
 │   ├─ 细长 / 实体武器网格 → KEEP mesh
 │   └─ AddAlpha 多层球（Priest Sentinel）且软圆不理想 → Shader 合成球（§5）
 ├─ ParticleEmitter2 → pe2.json → GPUParticles3D（§4）
 ├─ RibbonEmitter → ribbon.json → Wc3RibbonPresenter / Wc3RibbonEmitter
 └─ Light → OmniLight3D（衰减后补）
```

玩法壳（`combat_projectile_shell`）：

| 阶段 | 行为 |
|------|------|
| 飞行 | 优先 Stand；无则 Birth + **LOOP**（水元素） |
| 命中 | 优先 Death（触发 burst PE2 + 藏飞行 geoset） |
| 无可视 | 允许仅 Armature+PE2（水元素） |

---

## 4. GPUParticles3D（PE2）——已接与缺口

权威字段表见 [PE2_GODOT.md §3](../asset-convert/PE2_GODOT.md)。武器飞弹特别相关的缺口：

| 缺口 | 对三金样的影响 | 建议 |
|------|----------------|------|
| 真 **Tail**（按速度拉条） | FireBall / Priest / 水滴曳迹偏「短点」 | P1：速度对齐 `align_y` + 长度∝speed；P2：TrailMesh/自定义 draw |
| **Head+Tail Both** | FireBall Particle01、水滴 Particle03 | 拆成两个 GPUParticles 或一次 draw 两套 UV |
| **decay_uv / 序列帧** | FireBall Death Clouds8x8 钉第 0 格 | `anim_speed` + lifetime 采样格；必要时 AnimatedTexture |
| **emission_rate 动画** | 峰值喷量丢失 | `amount_ratio` 或短窗 restart |
| **Ribbon** | 水元素拖尾 | ✅ `Wc3RibbonEmitter` 路径条带（可再换 RibbonTrailMesh） |
| FilterMode 全表 | Priest AddAlpha 球 | 材质层 + shader |

**何时继续用 GPUParticles**：有清晰的 Head 点喷、burst、烟尘、短寿命焰核。  
**何时不要硬撑 GPUParticles**：连续屏幕空间条带（Ribbon）、需要精确 8×8 序列爆炸且 UV 动画复杂、多层 AddAlpha 实体球要融成一颗光核。

---

## 5. Shader / 专用节点（补 GPU 不够时）

### 5.1 软球 / 光核（Priest Sentinel、FireBall 壳）

| 方案 | 适用 |
|------|------|
| 现有 `wc3_team_glow` + `use_billboard` | Additive 少面壳（FireBall）— 已用 |
| 新建 `wc3_fx_soft_orb.gdshader` | AddAlpha 双 geoset 融成单球：径向 falloff + 双色 tint + 可选噪声 |
| 单 Quad Billboard + 程序圆 | 性能最好；牺牲立体交叉感 |

验收：牧师飞弹远看是一颗青白光核，不出现「两片硬板」。

### 5.2 Ribbon / 拖尾（水元素 BlizRibbon01）

| MDX | Godot 落地 |
|-----|------------|
| HeightAbove/Below、LifeSpan、EmissionRate、Color/Alpha | **`Wc3RibbonEmitter`**：世界路径环形缓冲 → Additive strip |
| Texture `RibbonBlur1` + Additive | bake 内嵌 ImageTexture |
| Birth 内 Translation 动画 | AnimationPlayer `POSITION_3D` 轨（相对 Birth interval） |

状态：sidecar ✅ → bake `RibbonRoot` ✅。后续可换 `RibbonTrailMesh` 减 CPU，语义不变。

### 5.3 命中爆（FireBall Clouds8x8 / 水花）

优先修 PE2 UV 动画；若仍糊：一次性 `Sprite3D`/`Decal` 序列帧 shader（`wc3_fx_sheet.gdshader`）播 Death 脉冲。

---

## 6. 管线与目录

```text
MDX
  → convert（gltf + pe2.json + geosetvis + attachments）
  → export_model_scenes / MapModelCache.bake
       ├─ Wc3Pe2Particles → GPUParticles3D
       ├─ Wc3FxPresenter → FxBillboard / KEEP
       └─ Wc3RibbonPresenter → RibbonRoot / Wc3RibbonEmitter
  → combat_projectile_shell 实例化 .scn，播 Stand|Birth / Death
```

手测（已刷新，含贴图副本）：

```text
tmp/model-review/Abilities/Weapons/
  FireBallMissile/          # Stand/Death/Birth + PE2
  PriestMissile/            # Stand/Birth/Death + PE2
  WaterElementalMissile/    # Birth/Death + PE2 + RibbonRoot
  README.md
```

用编辑器打开对应 `.scn`，在 AnimationPlayer 切序列。水元素无 Stand，飞行应对齐玩法壳的 Birth LOOP。

重解 + 重转（需本机经典客户端）：

```bash
# extract（npm 会吞 --include，请 node 直调）
cd tools/mpq-extract
node src/cli.js --game-dir "<经典WC3>" --force \
  --include "Abilities/Weapons/WaterElementalMissile/**"

cd ../asset-convert
node src/cli.js --force --include "Abilities/Weapons/WaterElementalMissile/**"
```

---

## 7. 抛光优先级（建议）

| P | 项 | 受益 |
|---|-----|------|
| P0 | 三金样烤本进 `tmp/model-review` 可手测 | 本文 |
| P0 | 水元素 Ribbon sidecar + 最小 Trail 呈现 | hwat 辨识度 |
| P1 | Priest AddAlpha → soft_orb shader（或合并 billboard） | hmpr |
| P1 | FireBall Tail / Death sheet UV | Hamg |
| P2 | PE2 rate 动画、Both Head+Tail 拆分 | 全体武器 |
| P2 | Plan B 推广到 Priest（可选） | 层级清理 |

---

## 8. 相关代码

| 路径 | 职责 |
|------|------|
| `scripts/presentation/wc3_model/wc3_fx_presenter.gd` | 飞弹 geoset 语义 |
| `scripts/map/presentation/effects/wc3_pe2_particles.gd` | PE2 → GPUParticles |
| `scripts/tool/wc3_scn_pe2.gd` | bake emitting 轨 |
| `game/scripts/presentation/combat_projectile_shell.gd` | 飞行/命中序列 |
| `game/scripts/logic/combat/combat_query.gd` | Missileart 路径 |
| `tests/unit/selftest_wc3_fx_presenter.gd` | FireBall 软球 |
| `tests/unit/selftest_c_combat_projectile.gd` | Hamg/hwat art 路径 |

---

## 9. 验收清单

- [ ] FireBall：Stand 见焰核+烟；Death 见爆；无双硬板  
- [ ] Priest：Stand 单光核+青曳迹；Death 电光脉冲  
- [ ] Water：Birth 见水滴+**拖尾条带**；Death 见水花；飞行循环 Birth  
- [ ] 三目录均可在 `tmp/model-review/.../*.scn` 独立打开手测  
