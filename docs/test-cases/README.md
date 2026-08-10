# test-cases/ — 测试用例文档

> 各模块的**手动测试用例**（区别于 `tests/` 自动 selftest）。
> 配合 `tests/` 自动 selftest：手动 = 人工/前台验收；自动 = headless 单测。

## 目录结构

```text
docs/test-cases/
├── README.md                              (本文件)
├── pathfinding/
│   └── TEST_CASES.md                      寻路（F-PATH + F3）
├── ramp/                                  (待补)
├── water/                                 (待补)
├── cliff/                                 (待补)
├── building/                              F2 建造（待补）
├── group-move/                            F3 群体移动（待补）
├── minimap/                               (待补)
└── editor/                                (待补)
```

## 用例格式

每个测试用例文档按以下结构组织：

```markdown
# <模块名> · 测试用例

## 1. 验收目标
## 2. 准备（前置条件）
## 3. headless 验收（selftest）
## 4. 手动验收
## 5. 边界 / 已知失败
## 6. 性能基准
```

## 与 docs/tests/ 的区别

| 目录 | 内容 | 用途 |
|------|------|------|
| `docs/tests/` | **测试索引**（headless 跑法） | 自动 selftest 速查 |
| `docs/test-cases/` | **测试用例文档**（手动验收 + 步骤 + 期望） | 手动验收 / 回归 / 复刻对比 |

`docs/tests/README.md` 是 **怎么跑**；`docs/test-cases/<topic>/TEST_CASES.md` 是 **怎么验**。

## 最后更新

2026-08-10
