# 双应用共享源码同步与验证

`Sync-Packages.ps1` 从根工程及已初始化子模块的受版本控制源码生成 `apps/<app>/addons/rts_runtime/`，转换内部 res:// 路径，并记录输出文件内容哈希。原源码仍在根工程编辑。

这是保证依赖完整的过渡包，尚未按最终四个包裁剪；不复制被忽略的大型转换资产。生成目录禁止手工修改。旧 rts_* 生成目录会在检查目标范围和链接后清除。

```powershell
./tools/workspace/Test-Apps.ps1 -Godot 'D:/path/to/Godot_console.exe'
```

验证先同步，再依次导入并实际创建 GameSession/PlayerStock；同时检查脚本错误、退出码和完成标记。`-App game` 或 `-App map_editor` 可只验证一个应用。启动壳通过不等于完整游戏/编辑器或导出制品已验收。
