# D4 双应用与同步

- `apps/game`、`apps/map_editor`：独立 `project.godot` 与 boot 场景。
- `tools/workspace/Sync-Packages.ps1`：把 `packages/*` 与过渡源码复制到 `addons/rts_*`。
- 主仓库根项目在切流前仍是日常开发入口。

```powershell
.\tools\workspace\Sync-Packages.ps1
& $env:GODOT --headless --path apps/game --quit-after 1
& $env:GODOT --headless --path apps/map_editor --quit-after 1
```
