param(
    [Parameter(Mandatory = $true)][string]$Godot,
    [ValidateSet("all", "game", "map_editor", "asset_viewer")][string]$App = "all",
    [string[]]$BootArguments = @(),
    [ValidateRange(1, 1800)][int]$TimeoutSeconds = 180
)
$ErrorActionPreference = "Stop"
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot "../.."))
& (Join-Path $PSScriptRoot "Sync-Packages.ps1") -App $App
$logRoot = Join-Path $repoRoot "tmp/app-validation"
New-Item -ItemType Directory -Force -Path $logRoot | Out-Null
$selected = if ($App -eq "all") { @("game", "map_editor", "asset_viewer") } else { @($App) }
foreach ($name in $selected) {
    $appRoot = Join-Path $repoRoot "apps/$name"
    foreach ($phase in @("import", "boot")) {
        $log = Join-Path $logRoot "$name-$phase.log"
        & (Join-Path $PSScriptRoot "Invoke-GodotCheck.ps1") -Godot $Godot -AppRoot $appRoot -Log $log -Phase $phase -TimeoutSeconds $TimeoutSeconds -BootArguments $BootArguments -Rendered:($phase -eq "boot")
    }
    Write-Output "$name import and actual application startup PASS"
}
