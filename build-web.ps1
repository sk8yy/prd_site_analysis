$ErrorActionPreference = 'Stop'
$web = Join-Path $PSScriptRoot 'web'
$vendor = Join-Path $web 'vendor'
[void][IO.Directory]::CreateDirectory($vendor)
$packages = @(
    @{Name='leaflet.js'; Url='https://cdn.jsdelivr.net/npm/leaflet@1.9.4/dist/leaflet.js'},
    @{Name='leaflet.css'; Url='https://cdn.jsdelivr.net/npm/leaflet@1.9.4/dist/leaflet.css'},
    @{Name='leaflet-LICENSE.txt'; Url='https://cdn.jsdelivr.net/npm/leaflet@1.9.4/LICENSE'},
    @{Name='lucide.js'; Url='https://cdn.jsdelivr.net/npm/lucide@0.468.0/dist/umd/lucide.min.js'},
    @{Name='lucide-LICENSE.txt'; Url='https://cdn.jsdelivr.net/npm/lucide@0.468.0/LICENSE'}
)
$manifest = @()
foreach ($package in $packages) {
    $destination = Join-Path $vendor $package.Name
    if (-not (Test-Path -LiteralPath $destination)) {
        Invoke-WebRequest -Uri $package.Url -OutFile $destination -UseBasicParsing
    }
    $manifest += [PSCustomObject]@{Name=$package.Name; Url=$package.Url; SHA256=(Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash}
}
$utf8 = [Text.UTF8Encoding]::new($false)
$manifestPath = Join-Path $vendor 'manifest.json'
if (Test-Path -LiteralPath $manifestPath) {
    $previous = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($entry in $manifest) {
        $record = $previous | Where-Object Name -EQ $entry.Name
        if ($record -and $record.SHA256 -ne $entry.SHA256) { throw "Vendor hash mismatch: $($entry.Name)" }
    }
}
[IO.File]::WriteAllText($manifestPath, ($manifest | ConvertTo-Json), $utf8)
$data = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'map-data.json') -Raw -Encoding UTF8
$parsed = $data | ConvertFrom-Json
if ($parsed.sheets.Count -ne 5) { throw 'Expected five map sheets' }
$research = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'research-data.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$parsed | Add-Member -NotePropertyName research -NotePropertyValue $research
$data = $parsed | ConvertTo-Json -Depth 30 -Compress
$safeData = $data.Replace('<','\u003c').Replace('>','\u003e').Replace('&','\u0026')
$html = Get-Content -LiteralPath (Join-Path $web 'index.template.html') -Raw -Encoding UTF8
$html = $html.Replace('__MAP_DATA__', $safeData)
$html = $html.Replace("`r`n", "`n").Replace("`r", "`n")
$script = [regex]::Match($html, '<script id="app">([\s\S]*?)</script>').Groups[1].Value
if (-not $script) { throw 'Application script missing' }
$sha256 = [Security.Cryptography.SHA256]::Create()
$hash = [Convert]::ToBase64String($sha256.ComputeHash($utf8.GetBytes($script)))
$sha256.Dispose()
$html = $html.Replace('__SCRIPT_HASH__', $hash)
if ($html.Contains('__MAP_DATA__') -or $html.Contains('__SCRIPT_HASH__')) { throw 'Unresolved template' }
[IO.File]::WriteAllText((Join-Path $web 'index.html'), $html, $utf8)
Write-Output "Built local web atlas: $web\index.html"
Write-Output "Sheets: $($parsed.sheets.Count); vendored assets: $($manifest.Count)"