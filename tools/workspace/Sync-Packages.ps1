# Transitional dependency-closed runtime snapshot. Source paths stay canonical in the root project.
param([ValidateSet("all", "game", "map_editor")][string]$App = "all")
$ErrorActionPreference = "Stop"
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot "../.."))
$sourceFiles = @(git -C $repoRoot ls-files --recurse-submodules -- game scripts scenes core editor addons assets)
if ($LASTEXITCODE -ne 0) { throw "Cannot enumerate tracked runtime sources" }
$selectedApps = if ($App -eq "all") { @("game", "map_editor") } else { @($App) }
foreach ($appName in $selectedApps) {
    $appRoot = [IO.Path]::GetFullPath((Join-Path $repoRoot "apps/$appName"))
    $addonRoot = [IO.Path]::GetFullPath((Join-Path $appRoot "addons"))
    foreach ($name in @("rts_foundation", "rts_content", "rts_map", "rts_gameplay", "rts_runtime")) {
        $target = [IO.Path]::GetFullPath((Join-Path $addonRoot $name))
        if (-not $target.StartsWith($addonRoot + [IO.Path]::DirectorySeparatorChar)) { throw "Unsafe generated path" }
        # Never traverse junctions outside the application when cleaning generated files.
        foreach ($parent in @($appRoot, $addonRoot, $target)) {
            if ((Test-Path -LiteralPath $parent) -and ((Get-Item -LiteralPath $parent).Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw "Symlink/junction not allowed: $parent" }
        }
        if (Test-Path -LiteralPath $target) {
            $links = Get-ChildItem -LiteralPath $target -Recurse -Force | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint }
            if ($links) { throw "Generated tree contains links: $target" }
            Remove-Item -LiteralPath $target -Recurse -Force
        }
    }
    $dest = Join-Path $addonRoot "rts_runtime"
    $records = @()
    foreach ($relative in ($sourceFiles | Sort-Object)) {
        $source = Join-Path $repoRoot $relative
        if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { continue }
        # Ignore import/editor metadata and documentation. Preserve script/resource UIDs.
        if ([IO.Path]::GetExtension($relative) -in @(".md", ".import") -or [IO.Path]::GetFileName($relative) -eq ".gdignore") { continue }
        $target = Join-Path $dest $relative
        New-Item -ItemType Directory -Force -Path (Split-Path $target) | Out-Null
        if ([IO.Path]::GetExtension($relative) -in @(".gd", ".tscn", ".tres", ".gdshader", ".json", ".cfg")) {
            $text = [IO.File]::ReadAllText($source).Replace("res://", "res://addons/rts_runtime/")
            [IO.File]::WriteAllText($target, $text, [Text.UTF8Encoding]::new($false))
        } else { Copy-Item -LiteralPath $source -Destination $target }
        $records += @{ path = $relative; sha256 = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLowerInvariant() }
    }
    [IO.File]::WriteAllText((Join-Path $dest "sync-manifest.json"), (ConvertTo-Json -InputObject $records -Depth 4), [Text.UTF8Encoding]::new($false))
    Write-Output "Synced $($records.Count) runtime files to $appName"
}
