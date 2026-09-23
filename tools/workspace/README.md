# Sync-Packages.ps1 — 将 packages / 过渡源码同步到应用 addons

用法（仓库根）:

```powershell
.\tools\workspace\Sync-Packages.ps1
.\tools\workspace\Sync-Packages.ps1 -App game
```

规则:
- 源只读复制到 `apps/<app>/addons/rts_<pkg>/`
- 写入 `.sync-hash` 便于检查过期
- 不使用符号链接（Windows 权限无关）
