# Dev-Setup.ps1 — Windows 一键准备开发资源
#
# 用法（仓库根目录）:
#   .\tools\Dev-Setup.ps1 -GameDir "D:\Program Files (x86)\Warcraft3"
#   .\tools\Dev-Setup.ps1 -GameDir "D:\Warcraft III" -Godot "D:\Godot\Godot_v4.6.3-stable_win64_console.exe"
#   .\tools\Dev-Setup.ps1 -GameDir $env:WC3_GAME_DIR -Profile full -Force
#
# 等价于: node tools/dev-setup.mjs ...

[CmdletBinding()]
param(
    [string]$GameDir = $env:WC3_GAME_DIR,
    [ValidateSet("game", "lost-temple", "full", "deps-only")]
    [string]$Profile = "game",
    [string]$Godot = $env:GODOT,
    [string]$Maps = "echoisles",
    [switch]$Force,
    [switch]$SkipExtract,
    [switch]$SkipGodot,
    [string[]]$Only,
    [switch]$Help
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root

if ($Help) {
    node "$Root\tools\dev-setup.mjs" --help
    exit 0
}

$node = Get-Command node -ErrorAction SilentlyContinue
if (-not $node) {
    Write-Error "未找到 Node.js。请安装 Node 18+ 并确保 node 在 PATH 中。"
}

$argsList = @("$Root\tools\dev-setup.mjs", "--profile", $Profile, "--maps", $Maps)
if ($GameDir) { $argsList += @("--game-dir", $GameDir) }
if ($Godot) { $argsList += @("--godot", $Godot) }
if ($Force) { $argsList += "--force" }
if ($SkipExtract) { $argsList += "--skip-extract" }
if ($SkipGodot) { $argsList += "--skip-godot" }
foreach ($o in $Only) { $argsList += @("--only", $o) }

Write-Host "Dev-Setup → node $($argsList -join ' ')" -ForegroundColor Cyan
& node @argsList
exit $LASTEXITCODE
