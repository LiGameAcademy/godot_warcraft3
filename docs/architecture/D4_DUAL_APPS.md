# D4 双应用与同步

- `apps/game`、`apps/map_editor`：独立 `project.godot` 与 boot 场景。
- `tools/workspace/Sync-Packages.ps1`：把 `packages/*` 与过渡源码复制到 `addons/rts_*`。
- 主仓库根项目在切流前仍是日常开发入口。

```powershell
.\tools\workspace\Sync-Packages.ps1
& $env:GODOT --headless --path apps/game --quit-after 1
& $env:GODOT --headless --path apps/map_editor --quit-after 1
```

审查后修复：同步已改为依赖完整的过渡 `rts_runtime` 包，并纳入子模块及路径映射。请使用 `tools/workspace/Test-Apps.ps1 -Godot <引擎路径>`，不要仅以 `--quit-after 1` 判断成功。范围限制见 [修复记录](REVIEW_FIXES_2026_09_23.md)。
