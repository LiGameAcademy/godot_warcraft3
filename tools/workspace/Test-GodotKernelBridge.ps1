param(
    [Parameter(Mandatory = $true)]
    [string]$GodotConsole,
    [string]$Configuration = "Debug"
)

$ErrorActionPreference = "Stop"
$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path
$godotExecutable = (Resolve-Path $GodotConsole).Path
$godotRoot = Split-Path $godotExecutable -Parent
$godotPackages = Join-Path $godotRoot "GodotSharp/Tools/nupkgs"
$gameProject = "apps/game/godot_warcraft3.csproj"
$testCase = "integration/selftest_rts_kernel_bridge.gd"

if (-not (Test-Path $godotPackages)) {
    throw "Godot .NET package directory not found: $godotPackages"
}

Push-Location $repositoryRoot
try {
    & (Join-Path $PSScriptRoot "Test-RtsKernel.ps1") -Configuration $Configuration

    dotnet restore $gameProject --source $godotPackages --ignore-failed-sources -p:NuGetAudit=false
    if ($LASTEXITCODE -ne 0) {
        throw "Godot C# project restore failed"
    }

    dotnet build $gameProject --no-restore -p:NuGetAudit=false -c $Configuration
    if ($LASTEXITCODE -ne 0) {
        throw "Godot C# project build failed"
    }

    python tools/workspace/sync_packages.py --app game --test $testCase
    if ($LASTEXITCODE -ne 0) {
        throw "Game package sync failed"
    }

    & $godotExecutable `
        --headless `
        --path apps/game `
        --log-file tmp/selftest_rts_kernel_bridge.log `
        -s "res://tests/$testCase"
    if ($LASTEXITCODE -ne 0) {
        throw "Godot kernel bridge test failed"
    }
}
finally {
    Pop-Location
}
