# 项目工程文档

这里保存开源项目的架构、实现约定、测试与维护记录。课程文稿、录制计划、字幕及发布素材由仓库外的教学资料目录独立维护。

## 从这里开始

1. [项目说明与环境准备](../README.md)
2. [仓库目录与文档边界](REPOSITORY_LAYOUT.md)
3. [工作区同步与验证](../tools/workspace/README.md)
4. [产品与共享包目录迁移记录](architecture/DIRECTORY_CUTOVER_2026_09_24.md)
5. [架构索引](architecture/README.md)与[子系统设计](design/README.md)

## 按任务查阅

- 工程计划：[路线图](roadmap/README.md)。
- 资产准备：[数据与管线](data/README.md)、[资源使用边界](data/LEGAL.md)。
- 资产导入：[统一导入计划](design/asset-convert/UNIFIED_IMPORT_EXECUTION_PLAN.md)、[审计基线](design/asset-convert/AUDIT_BASELINE_2026_09_27.md)、[资产查看器](../apps/asset_viewer/README.md)。
- 自动测试：[测试说明](tests/README.md)。
- 手工验收：[验收用例](test-cases/README.md)。
- 内核验证：[独立内核与桥接](verification/rts_kernel/REPOSITORY_SPLIT.md)。
- 维护历史：[技术开发日志](dev-log/README.md)。

历史文档中的旧源码路径可通过 `tools/workspace/source-layout.json` 查找新位置。历史记录描述当时的实现，不能替代当前代码及验证结果。
