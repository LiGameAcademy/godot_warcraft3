# 游戏应用

先在仓库根运行 `python tools/workspace/sync_packages.py --app game`，再打开本目录的 `project.godot`。F5 启动 Echo Isles 对战；`-- --smoke-test` 用于等待双方开局后自动退出。

`app/` 是 GameDirector 与对局模块装配；`client/` 是玩家输入、选择、HUD、相机和调试；`scenes/` 与 `config/` 是产品资源。共享玩法在 `packages/gameplay/` 编辑，同步生成的 `addons/` 不手工修改。

`override.cfg` 的 `warcraft3/asset_root` 指向本机已转换资产。详见 [同步与验证](../../tools/workspace/README.md)。
