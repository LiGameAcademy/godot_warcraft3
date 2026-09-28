param(
    [string]$Configuration = "Debug"
)

$ErrorActionPreference = "Stop"
$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path
$projects = @(
    "external/rts_kernel/src/Rts.Kernel/Rts.Kernel.csproj",
    "apps/kernel_cli/Rts.Kernel.Cli.csproj",
    "tests/kernel/Rts.Kernel.Tests.csproj"
)

Push-Location $repositoryRoot
try {
    $kernelTest = Join-Path $repositoryRoot "external/rts_kernel/Test.ps1"
    if (-not (Test-Path $kernelTest)) {
        throw "Kernel submodule missing. Run: git submodule update --init --recursive"
    }
    & $kernelTest -Configuration $Configuration
    foreach ($project in $projects) {
        dotnet restore $project --ignore-failed-sources -p:NuGetAudit=false -m:1
        if ($LASTEXITCODE -ne 0) {
            throw "dotnet restore failed: $project"
        }
    }

    # SDK 10.0.301 can fail without diagnostics when the mixed net8/net10
    # solution graph builds concurrently. Keep the deterministic single-node
    # build until an SDK update proves the parallel graph reliable.
    dotnet build RtsKernel.sln --no-restore -p:NuGetAudit=false -m:1 -c $Configuration
    if ($LASTEXITCODE -ne 0) {
        throw "RtsKernel solution build failed"
    }

    dotnet run --project tests/kernel/Rts.Kernel.Tests.csproj --no-build -c $Configuration
    if ($LASTEXITCODE -ne 0) {
        throw "Rts.Kernel tests failed"
    }
}
finally {
    Pop-Location
}
