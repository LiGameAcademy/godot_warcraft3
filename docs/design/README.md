# design/ — 设计驱动文档

> 11 个子系统按"专题"二级归类。  
> 配合：[architecture/](../architecture/)（架构）· [data/](../data/)（数据流水线）· [roadmap/](../roadmap/)（路线图）· [test-cases/](../test-cases/)（测试用例）· [blog/](../blog/)  
> 最后更新：2026-08-10

## 目录结构

```text
docs/design/
├── README.md                          (本文件)
├── pathfinding/                       寻路系统
│   ├── INDEX.md                       主索引（5 阶段 6 模块）
│   ├── CHOICE.md                      主方案拍板（WC3 离散网格 A*）
│   └── GROUP_MOVE.md                  F3 群体移动
├── building/                          建造（待 F2-B 补）
│   └── BUILD_SYSTEM.md                四族非对称建造设计
├── ramp/                              斜坡（HiveWE 同构）
│   ├── README.md
│   ├── RAMP_WE.md                     WC3 经典斜坡行为参考
│   ├── RAMP_REFACTOR.md               斜坡重构计划
│   └── HIVEWE_ALIGN.md                与 HiveWE 对齐
├── cliff/                             直崖
│   ├── README.md
│   ├── CLIFF.md                       领域规则
│   └── CLIFF_REFACTOR.md              分层重构里程碑
├── water/                             水体
│   ├── README.md
│   └── WATER.md
├── doodad/                            装饰物
│   ├── README.md
│   ├── HIVEWE_ALIGN.md
│   ├── Y_REFRESH.md                   doodad Y 高度刷新
│   └── DOO_FORMAT.md                  .doo 文件格式
├── unit/                              单位
│   └── HIVEWE_ALIGN.md
├── terrain/                           地形
│   ├── README.md
│   ├── TERRAIN_TILES.md               地面纹理
│   └── HEX_MAP_LESSONS.md             六边形地图参考
├── editor/                            编辑器
│   ├── README.md
│   ├── UI.md
│   ├── I18N.md
│   ├── EDITOR.md
│   ├── COMMANDS.md
│   └── BRUSHES.md
├── game/                              对战地图
│   ├── README.md
│   ├── ROADMAP.md                     游戏向路线图
│   ├── HUD.md
│   ├── ENVIRONMENT.md
│   └── ARCHITECTURE.md
├── minimap/                           小地图
│   ├── MINIMAP.md
│   └── PHASE3.md
├── presentation/                      表现层
│   ├── README.md
│   ├── Z_ORDER.md
│   └── LAYERS.md
├── shader/                            着色器
│   └── README.md
├── asset-convert/                     MDX/glTF 烘焙
│   ├── ATTACHMENTS_BAKE.md            小件 / 特效 sidecar 拼装
│   ├── MDX_SKINNING_GODOT.md          蒙皮空间、Stand rest、挂点 Tip
│   ├── PE2_GODOT.md                   ParticleEmitter2 / TeamGlow → Godot
│   ├── DEVLOG_2026-08-19.md           当日开发日志（杖尖 / PE2 / 回归）
│   └── SCN_COVERAGE.md                .scn 覆盖率快照
└── hivewe/                            HiveWE 行为参考
    ├── README.md
    ├── WATER_DEEP_ANALYSIS.md
    ├── WATER.md
    ├── UNDO.md
    ├── TERRAIN_TEXTURE.md
    ├── TERRAIN_MESH.md
    ├── RAMP.md
    ├── OPERATORS.md
    └── CLIFF.md
```

## 与 docs/ 其它一级目录的边界

| 一级 | 内容 | 关系 |
|------|------|------|
| `design/` | **设计驱动**（索引 / 口径 / 决策 / 改造计划） | 主导；game/ROADMAP.md → 阶段目标；design/<topic>/ → 子系统设计 |
| `architecture/` | **架构**（分层 / 模块边界 / 数据契约） | 跨 design/<topic>/ 的全局结构 |
| `data/` | **数据流水线**（WC3 资源提取 / SLK / BLP / MDX / GLB） | 给 design/ 提供数据契约 |
| `roadmap/` | **路线图**（阶段 / 优先级 / 总览） | 阶段目标反向驱动 design/<topic>/ |
| `test-cases/` | **测试用例**（手动验收 / 复刻对比） | design/<topic>/ 设计的可观察性验收 |
| `tests/` | **测试索引**（headless 跑法） | 自动 selftest 速查（与 test-cases/ 互补） |
| `blog/` | **blog 系列**（开发心得 / 对齐笔记） | 公开向；与设计文档互补 |

## docs 拍平原则

设计驱动 + 1 关注点 / 1 文档。新建 design 文档时：

1. **确认位置**——已有子目录用现有的；新专题新建 `design/<topic>/`
2. **README 必填**——每个子目录有 README.md 总览 + 当前状态
3. **cross-link 风格**——优先用**当前文件目录相对**；跨级用 `../`
4. **死链即 TODO**——指向不存在文件的 link 在 [roadmap/TODO.md "死链清单" 段](../roadmap/TODO.md) 记录
5. **CI 验证**——提交前跑一遍 `node tools/check-docs-links.mjs`，零死链再 commit

最后更新：2026-08-10
