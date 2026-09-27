param([ValidateSet("all", "game", "map_editor", "asset_viewer")][string]$App = "all", [string]$Python = "python")
$ErrorActionPreference = "Stop"
& $Python (Join-Path $PSScriptRoot "sync_packages.py") --app $App
if ($LASTEXITCODE -ne 0) { throw "Package synchronization failed" }
