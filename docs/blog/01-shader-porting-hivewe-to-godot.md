# 01 · GDScript Shader 跨引擎对照：HiveWE GLSL → Godot gdshader

> **副标题**：复刻魔兽争霸三地图时，把 HivEWE 的 4.5 GLSL 移植到 Godot 4 的 gdshader，跨引擎不是 1:1 翻译，是**重新设计**——本文总结 4 大坑 + 决策矩阵。
> **关联 commit**：`fa2b97b`（水面对齐）+ `b8ca82d`（shader README）
> **关联代码**：`assets/shaders/wc3_*.gdshader`（5 个）+ `D:\GameMaker\HiveWE\data\shaders\water.vert/frag`

---

## TL;DR

跨引擎 shader 翻译最容易踩的 4 个坑：

1. **Attribute 映射**——HivEWE 用 SSBO（`cliff_levels[]` / `water_heights[]`），Godot 没 SSBO，拆到 vertex attribute（`CUSTOM0/1` / `COLOR` / `INSTANCE_CUSTOM`）
2. **`flat` 限定符**——tilepoint 索引是 per-corner 不是 per-fragment，缺了 `flat` 4 角 tileset 插值 → 视觉错乱
3. **帧动画路径**——HivEWE CPU 推 uniform `current_texture`，Godot 4 可用 `TIME` 推帧（CPU 零开销），但 shore_foam 必须 `INSTANCE_CUSTOM` 推 phase
4. **透明度策略**——粒子必须 `blend_add` + `depth_draw_never`（防止互遮挡）；地面 `cull_back` 单面优化；cliff 双面（AABB 不可靠）

按"对照表 + 决策矩阵 + 踩坑" 3 段法可避免 80% 返工。

---

## 1. 背景：为什么不是 1:1 翻译

`godot_warcraft3` 是魔兽争霸三地图编辑器的 Godot 4 复刻。HiveWE 是经典 WC3 地图编辑器的现代重写（0.6+），用 OpenGL 4.5 GLSL 做渲染。我们移植到 Godot 4 时面对的核心问题：

- HivEWE 跑 OpenGL + 自定义 pipeline（手控 draw call / SSBO / 手动 GL state）
- Godot 4 跑 forward+ 渲染管线（场景节点 + 自动合批 + render_priority）
- **HivEWE 1 个 shader 文件 200-300 行** vs Godot gdshader 100-150 行（更紧凑但灵活性低）

最关键的 5 个 shader：

| shader | 作用 | 行 |
|--------|------|----|
| `wc3_ground.gdshader` | 地面 tileset 4 层 mix | ~85 |
| `wc3_cliff.gdshader` | 悬崖纹理 + 顶点 Y 位移 | ~60 |
| `wc3_water.gdshader` | 水面动画 + 深度色 | ~35 |
| `wc3_shore_foam.gdshader` | 岸浪粒子（additive）| ~80 |
| `wc3_debug_grid.gdshaderinc` | 寻路调试栅格（include）| ~50 |

**先抛结论**：跨引擎 shader 翻译**不是** 1:1 翻译，是**重新设计**。按下面的 4 大坑 + 决策矩阵做，**结果一致但代码完全不同**——这是"复刻"和"重写"的区别。

---

## 2. 坑 1：Attribute 映射（HivEWE SSBO → Godot vertex attribute）

### 2.1 HivEWE 怎么写

HivEWE `water.vert` 用 SSBO（Shader Storage Buffer Object）把整张地图数据传给 GPU：

```glsl
// water.vert:27-37
layout(std430, binding = 0) buffer layoutName {
    float cliff_levels[];
};
layout(std430, binding = 1) buffer layoutName2 {
    float water_heights[];
};
layout(std430, binding = 2) buffer layoutName3 {
    uint water_exists[];
};
```

每个 vertex 通过 `gl_InstanceID` 索引到 4 个 corner，shader 自己读 SSBO 算 4-corner OR、`water_height - ground_height` 算深度色、决定是否画水。

### 2.2 Godot 怎么写

Godot 4 **没有** SSBO（forward+ 不用 GLSL SSBO）。数据要么走 **vertex attribute**（per-vertex 数据），要么走 **uniform**（全图共享）。

我们用 `CUSTOM0/1` + `COLOR` + `INSTANCE_CUSTOM` 拆数据：

```glsl
// wc3_water.gdshader:12-15
varying vec4 v_depth_color;
void vertex() {
    v_depth_color = COLOR;  // CPU 算好深度色写 COLOR
}
void fragment() {
    vec4 tex = texture(water_frames, vec3(UV, idx));
    ALBEDO = (tex * v_depth_color).rgb;
    ALPHA = (tex * v_depth_color).a;
}
```

**决策**：

| HivEWE 概念 | Godot 对应 | 备注 |
|------------|------------|------|
| `cliff_levels[]` SSBO | 顶点 `CUSTOM0/1` + CPU 写 | 数据**从 SSBO 拆到 vertex** |
| `water_heights[]` SSBO | 顶点 `COLOR`（CPU 算深度色）| CPU 端 `Wc3WaterMesh` 算 5 档 |
| `water_exists[]` SSBO | ramp skip（CPU 跳过该区）| **不**传到 GPU（没必要） |
| `gl_InstanceID` 索引 | vertex 本身在 mesh 上 | mesh 拓扑已经按 tile 排好 |

### 2.3 关键陷阱：CPU 端计算时机

`v_depth_color = COLOR` 是 vertex stage 读 attribute。CPU 端 `Wc3WaterMesh.build` 算 5 档深度色塞 vertex color：

```gdscript
# wc3_water_mesh.gd:90-95（简化）
for corner in [BL, BR, TL, TR]:
    var depth := clamp(water_h[corner] - ground[corner], 0.0, 1.0)
    if depth <= DEEP_LEVEL:
        color = mix(SHALLOW_MIN, SHALLOW_MAX, (depth - MIN_DEPTH) / (DEEP_LEVEL - MIN_DEPTH))
    else:
        color = mix(DEEP_MIN, DEEP_MAX, (depth - DEEP_LEVEL) / (MAX_DEPTH - DEEP_LEVEL))
    vertex_colors[corner] = color
```

**结果一致**——但 **CPU 算好 vs shader 算** 的取舍是真实的：
- ✅ CPU 算：vertex shader 极简，debug 容易（CPU 输出可打印）
- ❌ CPU 算：4 角重复算（每个 corner 算一次，4 个 vertex 共享 mesh 拓扑时会被算 4 次）

对于 161×161 tilemap（~52000 vertex）这点开销可接受，**没**改。

---

## 3. 坑 2：`flat` 限定符（per-corner 数据防插值）

### 3.1 踩到的 bug

`wc3_ground.gdshader` 原本 `varying vec4 v_tex`（不带 `flat`），4 角 tileset 索引在 fragment stage **被插值**——结果两个 corner 之间的三角形里 tileset 索引渐变，**视觉立刻错乱**（地面"染色"成奇怪的渐变）。

修：加 `flat` 限定符。

```glsl
// wc3_ground.gdshader:15-17
varying flat vec4 v_tex;     // ← flat 防插值
varying flat vec4 v_var;     // ← flat 防插值
varying vec2 v_local;        // ← UV 正常插值

void vertex() {
    v_tex = CUSTOM0;  // tileset 索引（per-corner）
    v_var = CUSTOM1;  // variation 编号（per-corner）
    v_local = UV;     // 贴图 UV（per-fragment 插值）
}
```

### 3.2 决策：`flat` vs 普通 `varying`

| 数据 | 限定符 | 原因 |
|------|--------|------|
| tileset 索引（per-corner）| `flat` | 索引是整数，不能插值 |
| variation 编号（per-corner）| `flat` | 同上 |
| 贴图 UV（per-fragment）| 普通 `varying` | 三角形内要插值 |
| 深度色 COLOR（per-corner）| `flat` | 5 档离散色，不插值 |
| 调试栅格世界 XZ | `varying` | 三角形内插值才有意义 |

**关键规则**：**per-corner 离散数据 → `flat`**；**per-fragment 连续数据 → 普通 `varying`**。

### 3.3 HivEWE 怎么"不踩"

HivEWE 没这个问题——`out vec4 Color` 直接输出到 fragment，**没有** vertex ↔ fragment varying 插值概念。我们必须**显式**选 `flat`，否则 GLSL 4.5 默认会插值。

---

## 4. 坑 3：帧动画路径（CPU 推 vs GPU 算）

### 4.1 HivEWE 怎么写

HivEWE `water.frag` 用 uniform `current_texture`（int），CPU 每帧改：

```glsl
// water.frag:5-13
layout (location = 6) uniform int current_texture;
in vec2 UV;
in vec4 Color;
out vec4 outColor;
void main() {
    outColor = texture(water_textures, vec3(UV, current_texture)) * Color;
}
```

CPU 端（Qt + GL）每帧：
```cpp
// HivEWE viewer 每渲染帧 += texRate/60
viewer_frame += texRate / 60.0;
shader.setUniform("current_texture", int(viewer_frame) % frame_count);
```

**问题**：CPU 端每帧都要算 + setUniform，**CPU 开销**。

### 4.2 我们怎么写（GPU 算）

Godot 4 forward+ 推荐 GPU 端算（CPU 零开销）：

```glsl
// wc3_water.gdshader:18-22
uniform float tex_rate = 15.0;  // 帧/秒

void fragment() {
    float frames = max(float(frame_count), 1.0);
    // TIME 是秒 → 直接 * tex_rate；不要再 /60（/60 是「按帧累加」写法）
    float idx = floor(mod(TIME * tex_rate, frames));
    vec4 tex = texture(water_frames, vec3(UV, idx));
    ALBEDO = (tex * v_depth_color).rgb;
}
```

**结果一致**——15 fps 动画，CPU 端 0 开销。

### 4.3 但 shore_foam 必须 CPU 推

`wc3_shore_foam.gdshader` 是粒子系统，**每 instance 需要不同 phase**（避免"所有粒子同步爆开"）。MultiMesh 提供 `INSTANCE_CUSTOM` 4 float 共享 shader 推 per-instance 数据：

```glsl
// wc3_shore_foam.gdshader:22-26
void vertex() {
    float phase = INSTANCE_CUSTOM.x;        // 每粒子起始相位
    float speed_mul = INSTANCE_CUSTOM.y;
    float scale_mul = INSTANCE_CUSTOM.z;
    float t = fract(TIME / max(life_span, 0.001) + phase);  // 错相位
    ...
}
```

CPU 端 `Wc3ShoreFoam` 给每 instance 写不同 `INSTANCE_CUSTOM.x`，shader 端**同步** TIME + **错相位** phase。

### 4.4 决策矩阵

| 场景 | CPU 推 uniform | GPU 算 TIME | INSTANCE_CUSTOM 推 phase |
|------|---------------|------------|--------------------------|
| 同步动画（水波、风摇）| ❌ 浪费 CPU | ✅ 选这个 | ❌ 不需要 |
| 每 instance 错相位（粒子）| ❌ CPU 不可能 | ⚠️ 同步不够 | ✅ 选这个 |
| 单位动画（攻击/施法）| ❌ 太复杂 | ❌ 不通用 | ❌ 不需要 → 用 AnimationPlayer 单 instance |

---

## 5. 坑 4：透明度策略（粒子 vs 水面 vs 地面）

### 5.1 render_mode 速查

| shader | render_mode | 原因 |
|--------|------------|------|
| `wc3_ground` | `cull_back, unshaded, fog_disabled` | 单面优化（heightfield mesh 单面）+ WC3 prelit |
| `wc3_cliff` | `cull_disabled, unshaded, fog_disabled` | **双面**（解旋 Basis AABB 不可靠，背面剔了出"洞"）|
| `wc3_water` | `cull_disabled, unshaded, blend_mix, fog_disabled` | 双面（看穿）+ 标准 alpha |
| `wc3_shore_foam` | `cull_disabled, unshaded, **blend_add, depth_draw_never**, fog_disabled` | **加性混合 + 不写 depth** |

### 5.2 岸浪粒子为什么必须 `depth_draw_never`

岸浪是 N 个粒子叠加，**不**应该互相遮挡。如果写 depth：
- 粒子 A 写 depth → 粒子 B 在 A 后面时**被深度测试剔除**（看不到）
- 结果：粒子数量少一半，岸浪稀疏

`depth_draw_never` 让粒子**不**写 depth，但**仍参与 depth test**（被地形/水/悬崖挡住的粒子自然消失）——这就是"加性 + 不写 depth"的语义。

### 5.3 加性混合的预乘

`wc3_shore_foam.gdshader` 输出预乘 alpha：

```glsl
// wc3_shore_foam.gdshader:58-62
float a = mask * v_alpha;
ALBEDO = rgb * a;  // 预乘（src.rgb * src.a + dst）
ALPHA = 1.0;       // blend_add 模式下 ALPHA 不重要
```

**为什么预乘**：`blend_add = src.rgb * src.a + dst.rgb`（GL_SRC_ALPHA, GL_ONE）。
要等效"rgb 加性"，必须先把 `rgb *= a` 预乘一遍。**不**预乘直接 `ALBEDO = rgb` 会过曝。

### 5.4 cliff 为什么双面

HivEWE `cliff_meshes[i].render_queue(...)` 走 OpenGL 默认 cull back，但 cliff GLB 解旋后 AABB 不可靠：
- 解旋 Basis 下 vertex 实际位置在 mesh 局部坐标系里
- AABB 用 world 算会偏
- 背面剔了会出现"洞"（视角转过去能看穿）

`cull_disabled` 关闭背面剔除——多 1 倍 vertex 渲染，但**视觉正确**。

---

## 6. 决策矩阵（5 shader × 8 维度）

| 维度 | ground | cliff | water | shore_foam | debug_grid.inc |
|------|--------|-------|-------|------------|----------------|
| cull | `back` | **disabled** | **disabled** | **disabled** | — |
| blend | mix | mix | mix | **add** | — |
| depth_draw | opaque | opaque | opaque | **never** | — |
| unshaded | ✅ | ✅ | ✅ | ✅ | — |
| fog | disabled | disabled | disabled | disabled | — |
| render_priority | 0 | 0 | **1** | **16** | 90 (debug) |
| 动画 | 无 | 无 | **GPU TIME** | **INSTANCE_CUSTOM phase** | 无 |
| 顶点数据 | `CUSTOM0/1` flat | MODEL 算 height | `COLOR` flat | `INSTANCE_CUSTOM` | — |

**关键观察**：HivEWE 用 SSBO + uniform + CPU 推帧；我们用 vertex attribute + `TIME` + `INSTANCE_CUSTOM`。**实现路径完全不同，结果一致**。

---

## 7. 踩过的坑（按发现顺序）

### 7.1 `flat` 忘了加 → 地面染色错乱

**症状**：地面 4 corner 之间出现奇怪的渐变色。
**原因**：`varying vec4 v_tex` 默认被插值，tileset 索引渐变。
**修**：加 `flat` 限定符，**0.5 小时**。

### 7.2 shore_foam `discard` 阈值太小 → 性能爆

**症状**：160×160 地图 60 fps 掉到 15 fps。
**原因**：`if (mask < 0.001) discard` 太宽松，几乎所有 fragment 都参与 blend_add + texture sample。
**修**：阈值提到 0.004 + 配合 `if (mask * v_alpha < 0.004) discard`（两个条件乘积）。
**耗时**：**1 小时**（用 profiler 找的）。

### 7.3 选错帧动画路径 → 浪费 CPU

**症状**：HivEWE `current_texture` 直接搬到 Godot（用 uniform），CPU 每帧 setUniform。
**后果**：水面动画卡顿 5%（CPU 端 GL state 切换）。
**修**：改 GPU 算（`TIME * tex_rate`），CPU 端只 set 1 次。
**耗时**：**20 分钟**（commit `b8ca82d` 同期）。

### 7.4 cliff `cull_back` 出现"洞"

**症状**：转视角时 cliff 局部看到地形背景（应该有 cliff 的地方没 mesh）。
**原因**：解旋 Basis 下 GLB AABB 不可靠，背面剔了。
**修**：改 `cull_disabled`。
**耗时**：**0.5 小时**（GLB 模型 export + cull mode 验证）。

### 7.5 GLB 外链贴图（未解决）

**症状**：某些 GLB 引用的 albedo 贴图在 Godot 里看不到。
**原因**：`glTF` 支持外部 `.bin` / 贴图，m2g 工具**没**合并到 GLB。
**TODO**：`docs/roadmap/TODO.md` 已记，m2g 工具下一步加 `--embed` 选项。

---

## 8. 结果

5 个 shader 总计 **~7KB gdshader 代码**，跨 5 个 Layer（ground / cliff / ramp / water / foam）。

- ✅ 5 档深度色与 HivEWE 1:1 一致（`MIN_DEPTH/DEEP_LEVEL/MAX_DEPTH` 复用 HivEWE `10/128, 64/128, 72/128`）
- ✅ 帧动画 15 fps 等同 HivEWE viewer
- ✅ shore_foam additive + depth_draw_never = HivEWE `ParticleEmitter2` 视觉
- ✅ cliff 顶点 Y 位移（`h * 128.0`）等于 HivEWE `gpu_final_ground_heights`
- ✅ 性能：161×161 tilemap + 几百 doodad 60fps

**复刻原则**：跨引擎不是 1:1 翻译，是**重新设计**。按"对照表 + 决策矩阵 + 踩坑" 3 段法，结果一致但代码完全不同——这就是"复刻"。

---

## 9. 后续 TODO

| # | 任务 | 状态 |
|---|------|------|
| 1 | m2g `--embed`（GLB 合并外部贴图）| 📋 TODO |
| 2 | `instance_color` 替代 `INSTANCE_CUSTOM` 推玩家色（Godot 4.3+）| 📋 TODO |
| 3 | shader 内 TIME 受 pause 影响 → 加 `Engine.time_scale` 修正 | 📋 |
| 4 | Doodad shader 错相位（`INSTANCE_CUSTOM.x` 推 phase）| 📋 |

---

最后更新：2026-08-05
