param(
    [Parameter(Mandatory = $true)][string]$Godot,
    [switch]$Profiles,
    [string]$OutputDirectory = ""
)
$ErrorActionPreference = "Stop"
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot "../.."))
if (!$OutputDirectory) { $OutputDirectory = Join-Path $repoRoot "tmp/combat-lab-checks" }
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
$labRoot = Join-Path $repoRoot "apps/combat_lab"
$testProject = Join-Path $PSScriptRoot "CombatLab.Tests.csproj"
& dotnet build $testProject -c Release
if ($LASTEXITCODE -ne 0) { throw "CLI build failed." }
& dotnet build (Join-Path $labRoot "CombatLab.csproj") -c Debug
if ($LASTEXITCODE -ne 0) { throw "Godot host build failed." }
$cli = Join-Path $PSScriptRoot "bin/Release/net10.0/CombatLab.Tests.dll"
function Run-Check([string]$Name, [string]$Executable, [string[]]$Arguments, [string]$Marker) {
    $log = Join-Path $OutputDirectory "$Name.log"
    & $Executable @Arguments *> $log
    $code = $LASTEXITCODE
    $text = Get-Content -LiteralPath $log -Raw
    if ($code -ne 0 -or $text -match 'SCRIPT ERROR|ERROR:|COMBAT_LAB_FAILED' -or $text -notmatch $Marker) {
        throw "$Name failed (exit $code). See $log"
    }
    Write-Host "$Name PASS"
    return $text
}
$oldRuntime = $env:DOTNET_ROLL_FORWARD
try {
    $env:DOTNET_ROLL_FORWARD = "LatestMajor"
    $null = Run-Check "domain" "dotnet" @($cli) "COMBAT_LAB_CLI_PASS"
    $null = Run-Check "interaction" $Godot @("--headless", "--path", $labRoot, "--", "--self-test") "COMBAT_LAB_SELFTEST_PASS"
    if ($Profiles) {
        $results = @()
        foreach ($count in @(24, 300, 500)) {
            $fixture = Join-Path $OutputDirectory "resume-$count.json"
            $null = Run-Check "save-$count" "dotnet" @($cli, "--save-profile", "$count", $fixture) "COMBAT_LAB_CLI_PASS"
            foreach ($mode in @("fresh", "restore")) {
                # No business Step in a measured process before its real first frame, except isolated loading preparation.
                $cliArgs = @($cli, "--profile", "$count")
                $godotArgs = @("--headless", "--path", $labRoot, "--", "--profile", "$count")
                if ($mode -eq "restore") { $cliArgs += $fixture; $godotArgs += $fixture }
                $cliText = Run-Check "cli-$count-$mode" "dotnet" $cliArgs "combat_lab_host"
                $godotText = Run-Check "godot-$count-$mode" $Godot $godotArgs "COMBAT_LAB_PROFILE_PASS"
                $cliResult = ($cliText -split "\r?\n" | Where-Object { $_.StartsWith('{"scenario"') }) | ConvertFrom-Json
                $godotResult = ($godotText -split "\r?\n" | Where-Object { $_.StartsWith('{"scenario"') }) | ConvertFrom-Json
                if ($cliResult.state_hash -ne $godotResult.state_hash -or $cliResult.event_hash -ne $godotResult.event_hash) {
                    throw "$count $mode CLI/Godot state/event trace mismatch."
                }
                $results += [PSCustomObject]@{ count = $count; mode = $mode; cli = $cliResult; godot = $godotResult }
            }
        }
        $results | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $OutputDirectory "profiles.json") -Encoding utf8
        $over = @($results | Where-Object { $_.cli.over_budget -gt 0 -or $_.godot.over_budget -gt 0 })
        if ($over.Count -gt 0) { throw "30Hz gate FAIL; all samples including firsts retained in profiles.json." }
        Write-Host "Cold CLI/Godot profile gate PASS (logic step only; not whole rendered frame)."
    }
}
finally { $env:DOTNET_ROLL_FORWARD = $oldRuntime }
