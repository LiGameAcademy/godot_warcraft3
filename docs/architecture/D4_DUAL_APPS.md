# D4 双应用与同步

完整目录迁移已实施：游戏与地图编辑器分别使用独立 project.godot，packages 是共享源码唯一位置；旧 rts_runtime 过渡包已退出。

请使用 [workspace 工具](../../tools/workspace/README.md) 同步、导入、运行真实场景与回归。当前结构、资产挂载、依赖边界及验证限制见 [2026-09-24 验收记录](DIRECTORY_CUTOVER_2026_09_24.md)。
