# 知乎专栏方案与大纲（godot_warcraft3）

> **平台**：知乎专栏（免费）  
> **作者**：玩物不丧志的老李（哈尔滨）  
> **项目状态**：**正在复刻，未完工**——本文所有进度以仓库 `NEXT.md` 与 commit 为准  
> **首发关系**：与 B 站「老李游戏学院」视频课互补——知乎放深度长文、可检索；B 站放过程演示、踩坑镜头  
> **合规**：仓库不含暴雪资产；MDX/贴图/SLK 全部从用户本机正版 War3 客户端解包（[LEGAL.md](../data/LEGAL.md)）  
> 最后更新：2026-09-05

---

## 1. 专栏基本信息

| 项 | 内容 |
|----|------|
| **专栏名** | 《用 Godot 复刻魔兽3 · 一个哈尔滨老李的实战笔记》 |
| **副标题（写在介绍里）** | 正在复刻中：从 0 到 1 真实踩坑实录 · 分层架构 / 资产管线 / 对战竖切 / 寻路 / 特效，只贴真代码 |
| **作者署名** | 玩物不丧志的老李 |
| **头像 / 封面** | 复用 B 站同款；专栏头图建议放一张「当前能跑起来的 Echo Isles 主城截图」，标注"开发中 v0.x" |
| **定位** | 工程向 + 叙事向混合：技术读者看实现，普通玩家看「为什么这一步要这么做」 |
| **调性关键词** | 正在做、踩过的坑、每周二长文 + 周五快讯、活的仓库、B 站互补 |

---

## 2. 专栏介绍（直接复制到知乎）

> 大家好，我是玩物不丧志的老李。
>
> 这个专栏记录我**正在**用 **Godot 4.6** 从零复刻《魔兽争霸3》玩法的全过程——对，**正在复刻**，不是写完回头总结的"成功学"。人族 Melee 竖切跑通了，斜坡、水体、联机、完整科技树还在 todo 里。
>
> 仓库完全开源（`godot_warcraft3`），不含任何暴雪资产，所有 MDX、贴图、SLK 都从你本机正版客户端解包。
>
> 与「教程合集」不同，这里只写我**真踩过**的坑：分层架构、资产三车道、HiveWE GLSL 移植、F-PATH 5 模块寻路、PE2 粒子旁路、人族 Melee 竖切收尾……每一篇都附 commit、文档链接、可运行的代码片段。
>
> 节奏：**每周 1~2 篇长文（4000-6000 字）**，穿插 1 条「本周踩坑快讯」（500-1000 字）。不发水文，不搬运 API 文档。
>
> 你将看到：
> - 跨引擎移植不是 1:1 翻译，是重新设计
> - 「复刻 + 锦上添花」的方法论：原作有 5 项寻路要素，缺一就不像
> - 玩法、地图、资产三层管线的契约与门禁
> - 一个独立开发者如何把"想做的很大"切成一摞"每周能交付"的小 PR
>
> 欢迎评论区提具体问题，下一篇可能就是为你而写。

---

## 3. 更新频次与节奏

| 类型 | 频率 | 字数 | 来源 | 用途 |
|------|------|------|------|------|
| **长图文**（核心） | 每周二 1 篇 | **3500–5000**（首篇 3500 字验证完读率，再调） | `docs/blog/` 已有 draft + 新写 | 沉淀工程决策，可被搜索引擎检索 |
| **踩坑快讯** | 每周五 1 条 | 500–1000 | 当周 dev-log、commit、selftest 结果 | 保持账号活跃，给长图文预热 |
| **里程碑盘点** | 每月初 1 篇 | 3000–5000 | `NEXT.md` + commit 历史 | 给新人 / 回头客一个「现在到哪了」的快照 |
| **读者答疑** | 不定期 | 1500–3000 | 评论区高频问题 | 互动 + 反向选题 |

知乎专栏算法偏好「稳定节奏」——**长图文定周二 20:00**、**快讯定周五 21:00**最稳。

---

## 4. 专栏大纲（12 篇主长文 + 节奏）

> 选题已在 [docs/blog/README.md](../blog/README.md) 排好，按知乎读者的认知曲线重新编排：先讲故事、再讲架构、最后贴代码。

| # | 专栏标题 | 知乎读者获得感 | 对应文档 / Commit | 状态 |
|---|---------|---------------|------------------|------|
| **01** | 《我正在用 Godot 4 复刻魔兽3，但先把架构图撕了重画》 | 「正在做」+ 重点 2 类读者（A 复刻/大型项目开发者；B Godot 中级想找跨引擎分层思路） + 6 条差异化卖点 | [LAYERED_ARCHITECTURE.md](../architecture/LAYERED_ARCHITECTURE.md) | ✅ 写好（约 3500 字）→ [zhihu-01-layered-architecture.md](zhihu-01-layered-architecture.md) |
| 02 | 《我正在用 Godot 4 复刻魔兽3，但先把魔兽资源解包出来》 | 4 个 Node 工具 + 1 个 Autoload + 三车道契约 + 4 个真实踩坑 | [PIPELINE.md](../data/PIPELINE.md) + [ASSET_LANES.md](../architecture/ASSET_LANES.md) + [CONTENT_PACKS.md](../data/CONTENT_PACKS.md) | ✅ 写好（约 4500 字）→ [zhihu-02-asset-pipeline.md](zhihu-02-asset-pipeline.md) |
| 03 | 《魔兽3特效怎么进 Godot：PE2 / 显隐 / 绑骨小件，glTF 救不了的部分》 | sidecar JSON + GPUParticles3D 近似；上一期 #02 留的伏笔 | [blog/04-wc3-effects-...md](../blog/04-wc3-effects-conversion.md) | ✅ draft |
| 04 | 《HiveWE GLSL → Godot gdshader：跨引擎不是翻译，是重写》 | 4 大坑（SSBO / flat / TIME / blend_add） | [blog/01-shader-...md](../blog/01-shader-porting-hivewe-to-godot.md) | ✅ draft |
| 05 | 《F-PATH 寻路模块：5 纯函数 + 队形 + 上下坡 + 战斗 steering》 | 「复刻 + 锦上添花」方法论 | [blog/02-pathing-...md](../blog/02-pathing-modules-hivewe-to-godot.md) | ✅ draft |
| 06 | 《人族 Melee 竖切：F0→F10 一条命令管道是怎么代替上帝类的》 | GameDirector 瘦身 → CommandRouter 派发 | [GAMEPLAY_VERTICAL.md](../design/game/GAMEPLAY_VERTICAL.md) + [ARCHITECTURE.md](../design/game/ARCHITECTURE.md) | 待写 |
| 07 | 《为什么野怪脚下不能叠尸体：Geoset 显隐 + Stand snap 的来龙去脉》 | 一个具体的「看起来对」= 多个系统协同 | [dev-log/2026-08-23](../dev-log/2026-08-23-feature-f10-water-elemental.md) + [dev-log/2026-08-24](../dev-log/2026-08-24-ability-polish-water-visuals.md) | 待写 |
| 08 | 《牧师前胸透视 vs 水元素塑料感：FilterMode 与 `_fm*` 的正确打开方式》 | 材质的「加性 vs 透明 vs scissor」决策矩阵 | [dev-log/2026-08-24](../dev-log/2026-08-24-ability-polish-water-visuals.md) §2-3 | 待写 |
| 09 | 《斜坡逻辑 4-phase：从 HiveWE side-ramp gate 到 Phase A/B/C/D》 | 「不先做斜坡」如何反而更快 | `wc3_ramp_paint.gd` + [RAMP_REFACTOR.md](../design/ramp/RAMP_REFACTOR.md) | 待写 |
| 10 | 《Pathing data 层：从 WPM 文件到 GPU 纹理，260KB 装下一张地图》 | 调试线 F9 怎么画出来的 | `wc3_pathing_map.gd` + `wc3_pathing_textures.gd` | 待写 |
| 11 | 《人族可玩闭环收尾：野怪 AI / 英雄复活 / Keep / 铁匠 / 队列 HUD》 | 一份「人工点一遍」的验收剧本 | [NEXT.md](../roadmap/NEXT.md) N1 | 待写 |
| 12 | 《第一个里程碑：30 天把 Echo Isles 跑到能玩，背后有多少次 git mv》 | 心路 + 节奏感，给同好打气 | 自写 | 待写 |

**配菜**（穿插在主长文之间，不占 # 号）：

- **踩坑快讯**：从 commit + dev-log 提炼（500-1000 字）。例：「今天 selftest 全过 / 某条 ramp 卡了 2 小时 / PE2 烘焙时区问题」
- **里程碑盘点**：每月初 1 篇，对照 [NEXT.md](../roadmap/NEXT.md) 拉一个进度条
- **试刊**：[zhihu-00-pitfall-trial.md](zhihu-00-pitfall-trial.md) — 首发快讯，调性验证

---

## 5. 配图规范

| 项 | 约定 |
|----|------|
| 路径 | `./images/章节号-序号描述.png`（例：`./images/01-01-layered-architecture.png`） |
| 来源 | Godot 跑 `editor_main.tscn` / `game_main.tscn` 截图；或仓库已有 PNG（分层图、决策矩阵手绘图） |
| 风格 | 暗色背景优先；箭头与框线红色高亮；代码片段截图用 Godot 编辑器或 VSCode 暗色主题 |
| 数量 | 每篇 ≥ 2 张；架构/决策类图必备，踩坑前后对比图加分 |

---

## 6. 运营动作清单

| # | 动作 | 频次 | 备注 |
|---|------|------|------|
| 1 | 首发 #01（周二 20:00） | 一次性 | 置顶到专栏目录首位；首篇明确"正在做"调性，避免读者以为"复刻完成 demo" |
| 2 | 长图文 | 每周二 | 维持节奏 12 周；进度描述统一带"截至本文 X 月 X 日" |
| 3 | 踩坑快讯 | 每周五 | 与 B 站「开发日志」视频互为印证 |
| 4 | 月度盘点 | 每月初 | 对照 `NEXT.md` 拉进度条；已完成的打 ✅，未做的标 ❌ |
| 5 | B 站导流 | 每篇附视频章节链接 | 双向倒流 |
| 6 | 评论区高频问题 | 不定期 | 反向选题，写「读者答疑篇」 |

---

## 7. 文档落点

| 主题 | 路径 |
|------|------|
| 本方案（本文件） | `docs/dev-log/zhihu-column-outline.md` |
| 第一篇图文（分层架构） | [zhihu-01-layered-architecture.md](zhihu-01-layered-architecture.md) |
| 第二篇图文（资产解包） | [zhihu-02-asset-pipeline.md](zhihu-02-asset-pipeline.md) |
| 踩坑快讯试刊 | [zhihu-00-pitfall-trial.md](zhihu-00-pitfall-trial.md) |
| 现有工程 blog | [../blog/README.md](../blog/README.md) |
| 当前冲刺主线 | [../roadmap/NEXT.md](../roadmap/NEXT.md) |
| 地图分层重构 | [../roadmap/ROADMAP.md](../roadmap/ROADMAP.md) · [../architecture/LAYERED_ARCHITECTURE.md](../architecture/LAYERED_ARCHITECTURE.md) |

---

最后更新：2026-09-05
