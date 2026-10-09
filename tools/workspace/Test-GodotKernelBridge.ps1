param(
    [Parameter(Mandatory = $true)]
    [string]$GodotConsole,
    [string]$Configuration = "Debug",
    [string]$TestCase = "integration/selftest_rts_kernel_bridge.gd",
    [string[]]$CliArguments = @()
)

$ErrorActionPreference = "Stop"
$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path
$godotExecutable = (Resolve-Path $GodotConsole).Path
$godotRoot = Split-Path $godotExecutable -Parent
$godotPackages = Join-Path $godotRoot "GodotSharp/Tools/nupkgs"
$gameProject = "apps/game/godot_warcraft3.csproj"

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

    # Headless Godot loads the Debug editor assembly, including when Release was built above.
    if ($Configuration -ne "Debug") {
        dotnet build $gameProject --no-restore -p:NuGetAudit=false -c Debug
        if ($LASTEXITCODE -ne 0) { throw "Godot runtime Debug build failed" }
    }
    $cliLines = dotnet run --project external/rts_kernel/samples/Rts.Kernel.Cli --no-build -c $Configuration -- @CliArguments
    if ($LASTEXITCODE -ne 0) { throw "CLI parity baseline failed" }
    if (($cliLines -join "`n") -notmatch 'hash=([a-f0-9]{64})') {
        throw "CLI parity output did not contain a state hash"
    }
    $expectedCliHash = $Matches[1]

    python tools/workspace/sync_packages.py --app game --test $testCase
    if ($LASTEXITCODE -ne 0) {
        throw "Game package sync failed"
    }

    $logRoot = Join-Path $repositoryRoot "tmp/kernel-bridge-validation"
    New-Item -ItemType Directory -Force -Path $logRoot | Out-Null
    $scriptErrors = 'SCRIPT ERROR|Parse Error|Failed to load script|Failed loading resource|Can.t load dependency'

    # Sync can add or rename global script classes. Import before exercising the runtime.
    $importLog = Join-Path $logRoot "import.log"
    & $godotExecutable --headless --path apps/game --editor --import --quit `
        --log-file "$importLog.engine" *> $importLog
    $importExitCode = $LASTEXITCODE
    $importOutput = Get-Content -LiteralPath $importLog -Raw
    if ($importExitCode -ne 0 -or $importOutput -match $scriptErrors) {
        throw "Godot script import failed. See $importLog"
    }

    $testName = [IO.Path]::GetFileNameWithoutExtension($TestCase)
    $testLog = Join-Path $logRoot "$testName.log"
    & $godotExecutable `
        --headless `
        --path apps/game `
        --log-file "$testLog.engine" `
        -s "res://tests/$TestCase" `
        -- "--expected-cli-hash=$expectedCliHash" *> $testLog
    $testExitCode = $LASTEXITCODE
    $testOutput = Get-Content -LiteralPath $testLog -Raw
    Write-Output $testOutput
    if ($testExitCode -ne 0 -or $testOutput -match $scriptErrors) {
        throw "Godot kernel bridge test failed. See $testLog"
    }
    if ($testOutput -notmatch ([regex]::Escape($testName) + ': PASS')) {
        throw "Godot kernel bridge test did not report completion. See $testLog"
    }
}
finally {
    Pop-Location
}
