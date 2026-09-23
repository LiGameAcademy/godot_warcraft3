param(
    [Parameter(Mandatory = $true)][string]$Godot,
    [ValidateSet("all", "game", "map_editor")][string]$App = "all"
)
$ErrorActionPreference = "Stop"
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot "../.."))
& (Join-Path $PSScriptRoot "Sync-Packages.ps1") -App $App
$logRoot = Join-Path $repoRoot "tmp/app-validation"
New-Item -ItemType Directory -Force -Path $logRoot | Out-Null
$selected = if ($App -eq "all") { @("game", "map_editor") } else { @($App) }
foreach ($name in $selected) {
    $appRoot = Join-Path $repoRoot "apps/$name"
    foreach ($phase in @("import", "boot")) {
        $log = Join-Path $logRoot "$name-$phase.log"
        $arguments = @("--headless", "--path", $appRoot, "--log-file", "$log.engine")
        if ($phase -eq "import") { $arguments += @("--editor", "--import", "--quit") }
        else { $arguments += @("--", "--smoke-test") }
        & $Godot @arguments *> $log
        $exitCode = $LASTEXITCODE
        $output = Get-Content -LiteralPath $log -Raw
        if ($exitCode -ne 0 -or $output -match 'SCRIPT ERROR|Parse Error|Failed to load script|Failed loading resource|Can.t load dependency') {
            throw "$name $phase failed. See $log"
        }
        if ($phase -eq "boot" -and $output -notmatch 'APP startup PASS') {
            throw "$name did not exercise the runtime package. See $log"
        }
    }
    Write-Output "$name import and actual application startup PASS"
}
