param([Parameter(Mandatory = $true)][string]$Godot)
$ErrorActionPreference = "Stop"
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot "../.."))
$appRoot = Join-Path $repoRoot "apps/combat_lab"
& dotnet build (Join-Path $appRoot "CombatLab.csproj") -c Debug
if ($LASTEXITCODE -ne 0) { throw "Combat laboratory build failed." }
$previous = $env:DOTNET_ROLL_FORWARD
try {
    # This process alone may use an installed newer runtime; project remains net8.0.
    $env:DOTNET_ROLL_FORWARD = "LatestMajor"
    Start-Process -FilePath $Godot -ArgumentList @("--path", ('"' + $appRoot + '"')) -PassThru
}
finally { $env:DOTNET_ROLL_FORWARD = $previous }
