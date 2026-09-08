# 【老李游戏学院】04 · 我正在用 Godot 4 复刻魔兽3，PE2 粒子把大法师暴风雪的特效砸没了之后，我才开始研究魔兽这套22 年前的粒子系统

> **副标题**：发 4 类粒子参数 + 关键帧 + Sequence 区间的，逼着我把 GPUParticles3D + AnimationPlayer 拼成「会呼吸的粒子」

> **项目状态**：**正在复刻，未完工**。本文写于 2026-09-07。
>
> 最后更新：2026-09-07

---

#02 里我埋了一个伏笔——「模型转 gltf 就完了？粒子这块全是坑」。#03 把 scn bake 这一层讲完了。接下来按说好的，该讲 PE2 粒子怎么进 Godot。

但我没打算按"先讲原理再讲实现"那种顺序写。太假了。**真实顺序是：大法师暴风雪砸下来那天，特效没了。**

于是我顺手开始查 PE2 到底是什么。下面这些是这一两周的笔记，原样摆出来。

---

## 砸下来那天

暴风雪这个技能——大法师升到 10 级之后我点了它。地面有非常微弱的一个圈（这个我到现在都没调好）。然后我右键砸了一下——

**特效没了。**

不是我手动关了，是根本没显示。站在暴风雪区域里的单位头上飘着的伤害数字是在跳的——逻辑没错。表现上**粒子层整个掉线了**。

我把仓库翻了一遍。`assets/asset-converted/Units/Human/Archmage/` 旁边有几个 sidecar：

```text
Archmage.gltf
Archmage.pe2.json           ← 粒子参数
Archmage.geosetvis.json
Archmage.attachments.json
Archmage.animkeys.json
Archmage.collision.json
```

`.pe2.json` 打开一看，是一个 16 万字符的大文件。

---

## 我对 PE2 的第一印象

WC3 的 PE2 是「Particle Emitter 2」的缩写——魔兽 2004 年（重制版之前）那套粒子系统。读 MDX 的二进制头能拿到一个发射器对象，里面装的是：

```text
PE2 一发粒子 = 贴图 + 头帧区间 + 颜色/alpha 关键帧 + 速率关键帧 + 寿命/速度/重力 + emission rate + head / tail
```

听起来就是个 `GPUParticles3D` 加点配置的事。但真正读 MDX 之后发现不一样——魔兽的粒子**不是"一直开"的**。它在 **Sequence 范围内才发射**：

```text
Archmage.pe2.json（节选）
{
  "emitters": [
    {
      "texture": "Textures/SpellFX/Blizzard_Glow.blp",
      "model_space": false,
      "head_life_ms": [333, 666],         // 头粒寿命 333-666ms
      "head_size": [16, 32],
      "head_color": [{"t": 0.0, "r": 1.0, "g": 1.0, "b": 1.0, "a": 0.0},
                     {"t": 333, "r": 1.0, "g": 1.0, "b": 1.0, "a": 1.0},
                     {"t": 666, "r": 0.6, "g": 0.7, "b": 1.0, "a": 0.0}],
      "head_rate": [{"t": 0, "rate": 0.0},
                    {"t": 333, "rate": 60.0},
                    {"t": 666, "rate": 0.0}],
      "active_sequences": ["Spell", "Channel", "Stand Channel"],
      "interval": [0, 1500]
    }
  ]
}
```

`active_sequences` 这一栏——意思是「**只有这几个动作里**才发射」。这是关键。脱离 Sequence 谈粒子就是不存在的。

---

## 我一开始以为这事很简单

我最初的设计：`Wc3Pe2Particles.build_root_from_glb()` 把 JSON 解析完，建一个 `GPUParticles3D`，设贴图、寿命、emitting=true——搞定。

跑了一下。结果是粒子**永远在喷**。Archmage 站在原地不动也喷。走路也喷。死亡也喷。

```gdscript
# 错误示范（实际写出来过，又删了）
var pe := GPUParticles3D.new()
pe.texture = ...                  # ImageTexture 塞进 .gdignore 目录
pe.lifetime = 0.5
pe.amount = 60
pe.emitting = true                # ← 完蛋了，全局都在喷
root.add_child(pe)
```

我花了 20 分钟意识到问题在哪——魔兽里粒子根本不是「永远喷」，是「**Sequence 开始时喷、结束时关**」，而且是在 `AnimationPlayer` 的 `:emitting` 轨道上以**离散关键帧**形式存在的。

---

## 真正的实现：AnimationPlayer 脉冲 + 关键帧内插

PE2 进 Godot 的核心思路：**把 PE2 的「Sequence 范围 + 头速率关键帧」翻译成 `AnimationPlayer` 的 `:emitting` VALUE 轨**。

这一步在仓库里是 [`scripts/tool/wc3_scn_pe2.gd`](../../scripts/tool/wc3_scn_pe2.gd) 做的。这是真实代码——大约 200 行，省略中间的 helper，直接看主入口和它怎么注入 `:emitting` 轨：

```gdscript
# scripts/tool/wc3_scn_pe2.gd（节选；headless bake 阶段）
extends RefCounted

static func apply(root: Node, glb_path: String) -> Dictionary:
    var result := {"ok": false, "emitters": 0, "tracks": 0, "bones": 0}
    if root == null or glb_path.is_empty():
        return result
    _remove_existing_pe2(root)                               # 重 bake 时清旧 Pe2Root
    if not Wc3Pe2Particles.has_emitters(glb_path):
        result["ok"] = true; return result                   # 没 PE2 直接 ok
    var pe2: Node3D = Wc3Pe2Particles.build_root_from_glb(glb_path)
    if pe2 == null: result["ok"] = true; return result
    var parent: Node3D = Wc3Pe2Particles.resolve_model_root(root as Node3D)
    if parent == null: pe2.free(); return result
    parent.add_child(pe2)
    _set_owner_recursive(pe2, root)
    result["bones"] = Wc3Pe2Particles.bind_emitters_to_bones(root, pe2)   # 跟杖尖
    _set_owner_recursive(pe2, root)
    result["emitters"] = _count_particles(pe2)
    result["tracks"] = _inject_tracks(root, pe2, glb_path)               # 重点在这
    Wc3Pe2Particles.apply_sequence(root, "Stand")                       # 默认 Stand
    result["ok"] = true
    return result


static func _inject_tracks(root: Node, pe2_root: Node, glb_path: String) -> int:
    var ap := _find_ap(root)
    if ap == null: return 0
    var anim_root: Node = ap.get_node_or_null(ap.root_node)
    if anim_root == null: anim_root = ap.get_parent()
    if anim_root == null: anim_root = root
    var particles: Array[GPUParticles3D] = []
    _collect_particles(root, particles)                        # 也找 Attach_*/Tip 下的
    if particles.is_empty(): return 0

    var seqs: Array = Wc3Pe2Particles.load_payload(glb_path).get("sequences", []) as Array
    var n := 0
    for anim_name in ap.get_animation_list():
        var anim := ap.get_animation(anim_name)
        if anim == null: continue
        var interval := _seq_interval(seqs, str(anim_name))   # 该 Sequence 的时间区间
        for p in particles:
                # ← 只在 interval 内、且 head_rate>0 的时刻写 emitting=true
                # ← 必须写「全关」键：否则切到 Death 时 Stand 粒子还卡在上一剪辑
                #   的 emitting=true —— 火球 Death 看不到爆开、尾烟不停。
            var keys := _emitting_keys(p, str(anim_name), interval, anim.length)
            if keys.is_empty(): keys = [{"t": 0.0, "on": false}]
            var emit_path := NodePath("%s:emitting" % str(rel))
            _remove_tracks_with_path(anim, emit_path, Animation.TYPE_VALUE)
            var ti := anim.add_track(Animation.TYPE_VALUE)
            anim.track_set_path(ti, emit_path)
            anim.value_track_set_update_mode(ti, Animation.UPDATE_DISCRETE)   # ← 离散！
            anim.track_set_interpolation_type(ti, Animation.INTERPOLATION_NEAREST)
            for kv in keys:
                anim.track_insert_key(ti, float(kv["t"]), bool(kv["on"]))
            n += 1
            # 绑骨的：跟 BoneAttachment，不写 position 轨
            if bool(p.get_meta(Wc3Pe2Particles.META_BONE_BOUND, false)): continue
            ...
    return n
```

> 上面的中文 `# ←`注释是我现在写文章时加的。仓库原版就是英文。

`UPDATE_DISCRETE + INTERPOLATION_NEAREST` 这一对很关键——`:emitting` 是布尔，**不能插值**，要在 0 和 1 之间硬切，否则 Godot 会从 0 平滑过渡到 1，期间粒子速率会出现奇怪中间值。

`_emitting_keys()` 把头速率 + vis 关键帧按时间排，**只在状态切换点写键**——比如 `false→true` 在 333ms，`true→false` 在 666ms。不写中间值。

---

## 砸下来特效没了怎么修的

回到最初那个问题——暴风雪砸下来时粒子消失。

排查路径：

1. 看 `.scn` 里 Pe2Root 还在不在——在
2. 看 `AnimationPlayer` 的 Spell 动画里 `:emitting` 轨有没有键——**没有**
3. 看 `_emitting_keys` 的输出——0 个键，全是空
4. 看 `interval`——**Spell 这个 Sequence 在 `wc3_scn_pe2.gd` 的 `_seq_interval` 里查不到**

原因：

```gdscript
static func _seq_interval(seqs: Array, anim_name: String) -> Vector2:
    var want := AnimPlayback.compact_seq_name(anim_name)
    for s in seqs:
        ...
        if AnimPlayback.compact_seq_name(str(d.get("name", ""))) != want: continue
        var iv: Variant = d.get("interval", [])
        ...
        return Vector2(float((iv as Array)[0]), float((iv as Array)[1]))
    return Vector2.ZERO     # ← 找不到就返回 0
```

我去看了 `.pe2.json` 里 emitter 的 `active_sequences` 字段：

```json
"active_sequences": ["Spell", "Channel", "Stand Channel"]
```

而 Godot 的 AnimationPlayer 里这个动作叫 `Spell`——`compact_seq_name` 真实实现长这样（[`scripts/presentation/wc3_model/anim_playback.gd`](../../scripts/presentation/wc3_model/anim_playback.gd)）：

```gdscript
static func compact_seq_name(s: String) -> String:
    var leaf := anim_leaf(s).strip_edges()
    return leaf.replace("_", "").replace(" ", "").to_lower()
```

它是**全小写 + 去下划线 + 去空格**的——所以 `"Spell"` / `"spell"` / `"SPELL"` 都会变 `"spell"`，跟 AnimationPlayer 里的 `Spell` 都能对上。这块本身没问题。

**真正的问题在别处**：`.pe2.json` 里有几个 emitter 的 `active_sequences` 写的是 MDX 里的**动作名 id**，比如 `"spell"`、`"death"` 这些**全小写**；但 m2g 转换过程会把某些名字重整（比如 `"channel"` 拆成 `"channel start"` / `"channel loop"`）。重整前后 .pe2.json 没同步——结果 PE2 期望的"channel" 在 Godot 侧找不到对应动作。`_seq_interval` 返回 ZERO → `_emitting_keys` 空 → 写 `false` 键上去 → 全程不发射。

那次的临时修法：我在 `_inject_tracks` 里多加了一段同族 fallback——找不到精确名字就尝试 `get_slice(" ", 0)` 取首词（`channel start` → `channel`），能匹配上就把同样的 interval 套过去。但这只能应付**少量**重整，**彻底修要等 m2g 那边把 PE2 同步规则改对**。这是个跨模块的债务，目前挂着。

> 反正砸下来那个雪那天能飘了。但说实话——**效果还是很弱**。"微弱"那个原话我在视频里说过。是因为 `_emitting_keys` 只看 head_rate + vis，没看 head_size、head_color 这些——所以雪片还是太小、颜色还是太淡。这些得之后慢慢调。

---

## 绑骨：跟杖尖那一下

Archmage 的法杖顶上有发光粒子——这个不挂在模型根，挂在 BoneAttachment3D 下跟着 Bone_Head 或 Bone_Weapon 走。

`bind_emitters_to_bones` 在 wc3_scn_pe2.gd 里是这样：

```gdscript
# scripts/tool/wc3_scn_pe2.gd（约 28 行）
result["bones"] = Wc3Pe2Particles.bind_emitters_to_bones(root, pe2)
```

我没把 `bind_emitters_to_bones` 的实现贴上来——因为**我自己改了三遍才改对**：

- 第一版：直接 `parent.add_child(emitter)` 然后用 `BoneAttachment3D` 套——结果是粒子被绑骨但**位置在世界原点**飘
- 第二版：先 `add_child` 再 `reparent_to_bone`——结果 Godot 4.6 的 BoneAttachment3D 节点 ref 没生效
- 第三版（现在）：`Wc3Pe2Particles.pivot_for_sequence()` 取每个 Sequence 的发射器 pivot，烘焙成 `AnimationPlayer` 的 `POSITION_3D` 轨——和粒子本身的脉冲轨分两条

绕来绕去最后发现，**绑骨粒子不应该写 position 轨**——`_inject_tracks` 里就有：

```gdscript
if bool(p.get_meta(Wc3Pe2Particles.META_BONE_BOUND, false)): continue
```

`continue` 是关键。绑骨的发射器位置由 `BoneAttachment3D` 节点驱动；再写一条 `POSITION_3D` 轨反而会盖掉 BoneAttachment 的工作。

这种"看起来对其实错"的小坑，整个粒子系统到处都是。

---

## 粒子烘焙覆盖率怎么盯的

写到这里我已经意识到 PE2 没法"一次性全做对"——会持续迭代。我需要一个脚本告诉我**今天我烘焙了多少个、还有哪些没覆盖到**，下次改的时候能局部跑。

仓库里有 [`tools/check-pe2-coverage.mjs`](../../tools/check-pe2-coverage.mjs)：

```javascript
#!/usr/bin/env node
// tools/check-pe2-coverage.mjs
// 老李 P2-7：检查 PE2 预制覆盖度
// 扫 .glb 旁路 .pe2.json（m2g 输出）vs assets/pe2-prefabs/*.pe2.tscn（export_pe2_scenes 烘焙）。
// 报告 .pe2.json 总数 / .tscn 总数 / 哪些 .pe2.json 没对应 .tscn（runtime 走 JSON fallback）。

const ASSET_CONVERTED = path.join(REPO_ROOT, "assets", "asset-converted");
const PE2_PREFABS = path.join(REPO_ROOT, "assets", "pe2-prefabs");

// walk() 拿所有 .pe2.json 和所有 .pe2.tscn
// 输出：
//   pe2JsonTotal:     资产旁路有多少个 JSON
//   pe2TscnTotal:     已经烘焙出预制的数量
//   jsonMissingTscnList:  JSON 有但 .tscn 还没有的（runtime 临时解析 JSON）
//   tscnOrphanList:   .tscn 有但 JSON 已经删了的（脏数据）
//
// 跑：
//   node tools/check-pe2-coverage.mjs --md progress.md   # 写进度表
//   node tools/check-pe2-coverage.mjs --fail            # CI 报警
```

我每周跑一次，看哪些单位还没烘焙。具体多少个我就不在这里写数字了——文章发出去的时候数字会变，**留个进度表路径就够了**。

---

## 顺便说一句：粒子贴图为什么不 ExtResource

贴图那一步我之前没讲清楚。

`ImageTexture` 是直接 inline 进 `.scn` 的——不是 `ExtResource("res://...")`。原因是：

- `asset-converted/` 整个目录有 `.gdignore`
- 运行时走 `RuntimeAssets` 物理路径加载
- 如果 `.scn` 里写的是 `res://assets/asset-converted/...`，编辑器打开 / 烘焙 / 重新打开都会报错

所以 PE2 的贴图是 bake 时 `Image.load(物理路径)` → 转 `ImageTexture` → `PackedScene.pack()` 序列化进 `.scn`。代价是 **.scn 体积涨**——大法师的暴风雪 .scn 涨了 280KB，全是贴图内嵌。

这个我还在纠结要不要改——理论上应该让 `.scn` 引用逻辑路径 + 运行时解析贴图。但目前要写运行时 PE2 fallback 路径，工作量挺大。先内嵌，把粒子逻辑写对。

---

## 当前到哪儿——别问我几个 0 几个 0

我先把丑话说前头：

- 大法师暴风雪现在砸得下来，但**效果离原作差很远**。粒子稀疏、颜色淡
- 辉煌光环基本能看（这次视频里展示的那个），但**离单位距离判定**还有点 bug——光环范围扩大后边缘单位偶发吃不到
- 群体传送**只放了闪光圈，没有传送本身**——传送中单位去哪了还没实现
- 水元素能召唤出来，但**完全塑料感**——这个是材质问题，不在粒子范畴

RibbonEmitter 这一块**几乎还没碰**——particlesGPU 太老了，加上时间紧，先跳过。TownHall 的 Omni 灯也还占位 0/8。

下一步想做的：

- 群体传送的"传送本身"——单位瞬移那一下的视觉
- 牧师飞弹的轨迹特效（这次视频里我吐槽"有点夸张"）
- 暴风雪特效调密一点
- 野怪 AI（这是我立下的 flag，下期视频要做）

---

## 这一期结尾

写到这里比之前几期要糙一些——前几期（#01 #02 #03）讲架构、讲管线，那是有体系的东西；这一期讲粒子，说实话**我自己也还在摸索**。如果你照着仓库代码去走一遍，会发现 PE2 的覆盖度是真的不全——这没办法，半年时间不可能把22 年前的粒子系统完整复刻。

我之前在视频里说过一句话：**先把能做的做出来，剩下的慢慢磨**。粒子这种东西就是慢慢磨的范畴。

评论区我想问几个问题：

- 你做粒子一般是 CPUParticles3D 还是 GPUParticles3D？理由是？
- 关键帧驱动的 `:emitting` 脉冲这套，你有没有更好的方案？
- `*.pe2.json` 这种 sidecar 思路你接受吗？还是更愿意把 PE2 翻译成自定义 glTF 扩展？

---

🌐 更多资源：

[知识星球](https://wx.zsxq.com/group/28885154818841) | [B 站频道](https://space.bilibili.com/8618918) | [YouTube频道](https://www.youtube.com/@user-oldLee)

（注：仓库目前还没开源——本文贴的代码都是节选自本地仓库，等项目跑到 v0.1 能上手试玩了再放出来。）
