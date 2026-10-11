# 游戏应用

先在仓库根运行 `python tools/workspace/sync_packages.py --app game`，再打开本目录的 `project.godot`。F5 启动 Echo Isles 对战；`-- --smoke-test` 用于等待双方开局后自动退出。

`app/` 是 GameDirector 与对局模块装配；`client/` 是玩家输入、选择、HUD、相机和调试；`scenes/` 与 `config/` 是产品资源。共享玩法在 `packages/gameplay/` 编辑，同步生成的 `addons/` 不手工修改。

## 游戏资产启动
F5 与发布游戏都先校验新管线缓存；缺失、损坏或编译签名过期时停留在准备资源窗口，不自动回退到旧松散模型。开发时直接运行主场景，而不是绕过启动入口运行子场景。

窗口中可填写缓存目录，点击“检查此缓存”。编辑器还需填写随发布包生成的 `asset-import-runtime` 目录，以使用相同的编译签名和源解析运行时。原版目录、缓存目录和编辑器运行时目录保存在本机 `user://asset_import.cfg`；发布包始终使用其旁边的运行时。缓存有效后进入对局，输出 `ASSET_CACHE_READY` 和实际路径；下一次普通 F5 会复用记忆路径。

命令行 `--asset-import-cache`、`--asset-import-runtime` 优先于本机记忆。显式 `--warcraft-dir` 或 `--asset-import-manifest` 仍使用对应导入入口。后台编译在编辑器启动时将工程目录传给工作进程，发布游戏不需要玩家安装 Godot 编辑器。

验收：普通 F5 选择有效缓存后重启，确认自动进入；改为不存在的缓存目录，确认停留向导；导入期间取消并重试；进入后召唤水元素，确认使用模型而不是圆柱占位。过期缓存应重新导入，不能手改版本签名绕过校验。

`override.cfg` 的 `warcraft3/asset_root` 仍用于开发工具的松散资源位置，不替代游戏缓存校验。详见 [同步与验证](../../tools/workspace/README.md)。
