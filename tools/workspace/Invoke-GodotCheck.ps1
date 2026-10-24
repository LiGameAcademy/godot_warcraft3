param(
    [Parameter(Mandatory = $true)][string]$Godot,
    [Parameter(Mandatory = $true)][string]$AppRoot,
    [Parameter(Mandatory = $true)][string]$Log,
    [Parameter(Mandatory = $true)][ValidateSet("import", "boot")][string]$Phase,
    [string[]]$BootArguments = @(),
    [switch]$Rendered,
    [switch]$DiagnosticVerbose,
    [ValidateRange(1, 1800)][int]$TimeoutSeconds = 180
)
$ErrorActionPreference = "Stop"
$AppRoot = [IO.Path]::GetFullPath($AppRoot)
$Log = [IO.Path]::GetFullPath($Log)
New-Item -ItemType Directory -Force -Path ([IO.Path]::GetDirectoryName($Log)) | Out-Null
if ($Phase -eq "boot" -and (Split-Path $AppRoot -Leaf) -eq "game" -and !("--asset-import-manifest" -in $BootArguments) -and !("--warcraft-dir" -in $BootArguments)) {
    throw "Headless game startup requires explicit --asset-import-manifest or --warcraft-dir; otherwise it waits in the interactive asset wizard. Pass -BootArguments with an existing resource entry."
}
$arguments = @("--headless", "--path", ('"' + $AppRoot + '"'), "--log-file", ('"' + $Log + '.engine"'))
if ($Phase -eq "import") { $arguments += @("--editor", "--import") }
else {
    $arguments += @("--", "--smoke-test")
    $arguments += @($BootArguments | ForEach-Object { '"' + $_ + '"' })
}
if ($Rendered) { $arguments = @($arguments | Where-Object { $_ -ne "--headless" }) }
if ($DiagnosticVerbose) { $arguments += "--verbose" }
$watch = [Diagnostics.Stopwatch]::StartNew()
$process = Start-Process -FilePath $Godot -ArgumentList $arguments -PassThru -WindowStyle Hidden -RedirectStandardOutput $Log -RedirectStandardError ($Log + ".stderr")
$timedOut = $false
try {
    while (!$process.WaitForExit(1000)) {
        if ($watch.Elapsed.TotalSeconds -ge $TimeoutSeconds) {
            $timedOut = $true
            # Only the process created above and its descendants belong to this check.
            $process.Kill($true)
            $process.WaitForExit()
            break
        }
    }
    $watch.Stop()
    $code = $process.ExitCode
    $result = [PSCustomObject]@{
        phase = $Phase; pid = $process.Id; elapsed_ms = $watch.Elapsed.TotalMilliseconds
        exit_code = $code; timed_out = $timedOut; timeout_seconds = $TimeoutSeconds; validation_pass = $false
    }
    $result | ConvertTo-Json | Set-Content -LiteralPath ($Log + ".result.json") -Encoding utf8
}
finally { $process.Dispose() }
if ($timedOut) { throw "$Phase timed out; startup skipped. See $Log" }
if ($null -eq $code -or $code -ne 0) { throw "$Phase exited with code $code. See $Log" }
$output = (Get-Content -LiteralPath $Log -Raw) + (Get-Content -LiteralPath ($Log + ".stderr") -Raw)
if ($output -match 'SCRIPT ERROR|ERROR:|Parse Error|Failed to load script|Failed loading resource|Can.t load dependency') {
    throw "$Phase reported resource/script errors. See $Log"
}
if ($Phase -eq "boot" -and $output -notmatch 'APP startup PASS') { throw "Playable application did not start. See $Log" }
if ($Phase -eq "import") {
    $imports = @("icon.svg.import")
    if (Test-Path -LiteralPath (Join-Path $AppRoot "addons/panku_console/res/icons2/question.svg")) {
        $imports += "addons/panku_console/res/icons2/question.svg.import"
    }
    foreach ($relative in $imports) {
        $import = Join-Path $AppRoot $relative
        if (!(Test-Path -LiteralPath $import)) { throw "Import metadata missing: $relative" }
        $match = [regex]::Match((Get-Content -LiteralPath $import -Raw), '(?m)^path="res://([^"]+)"')
        if (!$match.Success -or !(Test-Path -LiteralPath (Join-Path $AppRoot $match.Groups[1].Value))) {
            throw "Imported resource missing: $relative"
        }
    }
}
$result.validation_pass = $true
$result | ConvertTo-Json | Set-Content -LiteralPath ($Log + ".result.json") -Encoding utf8
Write-Output "$Phase PASS ($($watch.Elapsed.TotalSeconds.ToString('0.00')) seconds)"
