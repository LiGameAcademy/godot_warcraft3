param(
    [Parameter(Mandatory = $true)][string]$Godot,
    [string]$OutputDirectory = "",
    [switch]$Rendered
)
$ErrorActionPreference = "Stop"
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot "../.."))
$appRoot = Join-Path $repoRoot "apps/asset_viewer"
if (!$OutputDirectory) { $OutputDirectory = Join-Path $repoRoot "tmp/model-material-lifetime" }
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
New-Item -ItemType Directory -Force $OutputDirectory | Out-Null
# Use the existing map/content host without the unrelated legacy GAS autoloads.
& python (Join-Path $repoRoot "tools/workspace/sync_packages.py") --app asset_viewer
if ($LASTEXITCODE -ne 0) { throw "Asset test host synchronization failed." }
& (Join-Path $repoRoot "tools/workspace/Invoke-GodotCheck.ps1") -Godot $Godot -AppRoot $appRoot -Phase import -Log (Join-Path $OutputDirectory "import.log")
$relative = "tests/unit/selftest_model_material_lifetime.gd"
$target = Join-Path $appRoot $relative
New-Item -ItemType Directory -Force (Split-Path $target -Parent) | Out-Null
Copy-Item -LiteralPath (Join-Path $repoRoot $relative) -Destination $target -Force
$log = Join-Path $OutputDirectory "lifetime.log"
$arguments = @("--headless", "--single-window", "--path", ('"' + $appRoot + '"'), "--log-file", ('"' + $log + '.engine"'), "--script", "res://$relative")
if ($Rendered) { $arguments = @($arguments | Where-Object { $_ -ne "--headless" }) }
$started = [Diagnostics.Stopwatch]::StartNew()
$process = Start-Process -FilePath $Godot -ArgumentList $arguments -PassThru -WindowStyle Hidden -RedirectStandardOutput $log -RedirectStandardError ($log + ".stderr")
$timedOut = $false
try {
    while (!$process.WaitForExit(1000)) {
        if ($started.Elapsed.TotalSeconds -ge 180) {
            $timedOut = $true
            $process.Kill($true)
            $process.WaitForExit()
            break
        }
    }
    $code = $process.ExitCode
}
finally { $process.Dispose() }
$result = [PSCustomObject]@{ exit_code = $code; timed_out = $timedOut; elapsed_ms = $started.Elapsed.TotalMilliseconds; rendered = [bool]$Rendered; validation_pass = $false }
$result | ConvertTo-Json | Set-Content ($log + ".result.json") -Encoding utf8
$text = (Get-Content $log -Raw) + (Get-Content ($log + ".stderr") -Raw)
if ($timedOut -or $code -ne 0 -or $text -match 'ERROR:|SCRIPT ERROR|Parse Error|\bFAIL\b|leaked at exit' -or $text -notmatch 'MODEL_MATERIAL_LIFETIME_ASSERTIONS_PASS') {
    throw "Model material lifetime regression failed. See $log"
}
$result.validation_pass = $true
$result | ConvertTo-Json | Set-Content ($log + ".result.json") -Encoding utf8
Write-Output "Model material lifetime PASS (resource lifecycle; not a simulation-frame benchmark)."
