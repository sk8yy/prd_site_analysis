param([string]$Basemap = (Join-Path $env:TEMP 'prd_basemap_preview.png'))
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$data = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'map-data.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$output = Join-Path $PSScriptRoot 'figures'
[void][System.IO.Directory]::CreateDirectory($output)
$baseImage = [System.Drawing.Image]::FromFile((Resolve-Path -LiteralPath $Basemap).Path)
if ($baseImage.Width -ne 2200 -or $baseImage.Height -ne 1893) { throw 'Expected 2200 x 1893 reference image' }
if ((Resolve-Path -LiteralPath $Basemap).Path -ne (Join-Path $output 'basemap-reference.png')) {
    $baseImage.Save((Join-Path $output 'basemap-reference.png'), [System.Drawing.Imaging.ImageFormat]::Png)
}
$base64 = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes((Join-Path $output 'basemap-reference.png')))
$colors = @{history='#B74448'; industry='#BE7224'; 'industrial-heritage'='#A34F3F'; 'industrial-landscape'='#BE7224'; nature='#267754'; island='#147E87'; city='#75577D'; evidence='#BD425F'; terminal='#194E73'; context='#737E83'; plan='#5D61A3'; route1='#C13856'; route2='#14628B'; route3='#9A5B2A'}
$utf8 = [System.Text.UTF8Encoding]::new($false)
$offsetX = 60
$offsetY = 245

function Add-Text([string]$Value, [single]$Left, [single]$Top, [single]$Size, [string]$Color = '#223E42', [bool]$Bold = $false) {
    $style = [System.Drawing.FontStyle]::Regular
    if ($Bold) { $style = [System.Drawing.FontStyle]::Bold }
    $font = [System.Drawing.Font]::new('Microsoft YaHei', $Size, $style, [System.Drawing.GraphicsUnit]::Pixel)
    $brush = [System.Drawing.SolidBrush]::new([System.Drawing.ColorTranslator]::FromHtml($Color))
    $graphics.DrawString($Value, $font, $brush, $Left, $Top)
    $weight = if ($Bold) { '700' } else { '400' }
    $escaped = [System.Security.SecurityElement]::Escape($Value)
    [void]$svg.AppendLine("<text x='$Left' y='$($Top + $Size)' font-family='Microsoft YaHei, sans-serif' font-size='$Size' font-weight='$weight' fill='$Color'>$escaped</text>")
    $font.Dispose()
    $brush.Dispose()
}

function Add-Area($Area) {
    $vertices = [System.Collections.Generic.List[System.Drawing.PointF]]::new()
    $pairs = [System.Collections.Generic.List[string]]::new()
    foreach ($coordinate in $Area.coords) {
        $left = [single]($offsetX + $coordinate[0])
        $top = [single]($offsetY + $coordinate[1])
        $vertices.Add([System.Drawing.PointF]::new($left, $top))
        $pairs.Add("$left,$top")
    }
    $color = if ($Area.kind -eq 'industry') { '#C08A43' } elseif ($Area.kind -eq 'plan') { '#8794C4' } else { '#3D9C63' }
    $baseColor = [System.Drawing.ColorTranslator]::FromHtml($color)
    $brush = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(51,$baseColor))
    $pen = [System.Drawing.Pen]::new($baseColor, 2)
    $pen.DashPattern = [single[]]@(3,2)
    $graphics.FillPolygon($brush, $vertices.ToArray())
    $graphics.DrawPolygon($pen, $vertices.ToArray())
    [void]$svg.AppendLine("<polygon points='$($pairs -join ' ')' fill='$color' fill-opacity='0.2' stroke='$color' stroke-width='2' stroke-dasharray='6 4'/>")
    $brush.Dispose()
    $pen.Dispose()
}

function Add-Path($Coordinates, [string]$Color, [single]$Width = 6) {
    $vertices = [System.Collections.Generic.List[System.Drawing.PointF]]::new()
    $pairs = [System.Collections.Generic.List[string]]::new()
    foreach ($coordinate in $Coordinates) {
        $left = [single]($offsetX + $coordinate[0])
        $top = [single]($offsetY + $coordinate[1])
        $vertices.Add([System.Drawing.PointF]::new($left, $top))
        $pairs.Add("$left,$top")
    }
    $pen = [System.Drawing.Pen]::new([System.Drawing.ColorTranslator]::FromHtml($Color), $Width)
    $pen.DashPattern = [single[]]@(3,2)
    $pen.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Round
    $graphics.DrawLines($pen, $vertices.ToArray())
    [void]$svg.AppendLine("<polyline points='$($pairs -join ' ')' fill='none' stroke='$Color' stroke-width='$Width' stroke-dasharray='18 12' stroke-linejoin='round'/>")
    $pen.Dispose()
}

function Add-Marker([single]$Left, [single]$Top, [string]$Kind, [string]$Identifier) {
    $color = $colors[$Kind]
    $brush = [System.Drawing.SolidBrush]::new([System.Drawing.ColorTranslator]::FromHtml($color))
    $pen = [System.Drawing.Pen]::new([System.Drawing.Color]::White, 4)
    if ($Kind -eq 'plan') {
        $graphics.FillEllipse([System.Drawing.Brushes]::White, $Left-12, $Top-12, 24, 24)
        $pen.Color = $brush.Color
        $graphics.DrawEllipse($pen, $Left-12, $Top-12, 24, 24)
        [void]$svg.AppendLine("<circle cx='$Left' cy='$Top' r='12' fill='white' stroke='$color' stroke-width='4'/>")
    } else {
        $graphics.FillEllipse($brush, $Left-12, $Top-12, 24, 24)
        $graphics.DrawEllipse($pen, $Left-12, $Top-12, 24, 24)
        [void]$svg.AppendLine("<circle cx='$Left' cy='$Top' r='12' fill='$color' stroke='white' stroke-width='4'/>")
    }
    if ($Identifier) {
        $font = [System.Drawing.Font]::new('Microsoft YaHei', 21, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
        $size = $graphics.MeasureString($Identifier, $font)
        $font.Dispose()
        $labelLeft = [single][Math]::Min($Left+17, $offsetX+2200-$size.Width-8)
        $labelTop = [single]($Top-16)
        for ($attempt = 0; $attempt -lt 20; $attempt++) {
            $rectangle = [System.Drawing.RectangleF]::new($labelLeft,$labelTop,$size.Width+8,30)
            $overlap = $false
            foreach ($used in $labelBounds) { if ($used.IntersectsWith($rectangle)) { $overlap = $true; break } }
            if (-not $overlap) { break }
            $labelTop += 32
        }
        $labelBounds.Add($rectangle)
        $leader = [System.Drawing.Pen]::new($brush.Color, 1)
        $graphics.DrawLine($leader, $Left, $Top, $labelLeft, [single]($labelTop+15))
        $leader.Dispose()
        [void]$svg.AppendLine("<line x1='$Left' y1='$Top' x2='$labelLeft' y2='$($labelTop+15)' stroke='$color' stroke-width='1'/>")
        $graphics.FillRectangle([System.Drawing.Brushes]::White, $rectangle)
        [void]$svg.AppendLine("<rect x='$labelLeft' y='$labelTop' width='$($size.Width+8)' height='30' fill='white'/>")
        Add-Text $Identifier ($labelLeft+4) $labelTop 21 $color
    }
    $brush.Dispose()
    $pen.Dispose()
}

try {
    foreach ($sheet in $data.sheets) {
        $bitmap = [System.Drawing.Bitmap]::new(3300, 2380)
        $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
        $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $graphics.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
        $graphics.Clear([System.Drawing.Color]::White)
        $svg = [System.Text.StringBuilder]::new()
        $labelBounds = [System.Collections.Generic.List[System.Drawing.RectangleF]]::new()
        [void]$svg.AppendLine("<svg xmlns='http://www.w3.org/2000/svg' width='3300' height='2380' viewBox='0 0 3300 2380'><rect width='3300' height='2380' fill='white'/>")
        $graphics.DrawImage($baseImage, $offsetX, $offsetY, 2200, 1893)
        $veil = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(50,255,255,255))
        $graphics.FillRectangle($veil, $offsetX, $offsetY, 2200, 1893)
        $veil.Dispose()
        [void]$svg.AppendLine("<image x='$offsetX' y='$offsetY' width='2200' height='1893' href='data:image/png;base64,$base64'/><rect x='$offsetX' y='$offsetY' width='2200' height='1893' fill='white' opacity='0.196'/>")
        Add-Text 'PEARL RIVER ESTUARY / LANDSCAPE + CRUISE' 66 32 26 '#527578' $true
        Add-Text $sheet.title 60 83 64 '#163D42' $true
        Add-Text $sheet.subtitle 65 173 30 '#617477'
        foreach ($area in $sheet.areas) { Add-Area $area }
        foreach ($line in $sheet.lines) { Add-Path $line.coords $colors[$line.kind] 7 }
        foreach ($point in $sheet.points) { Add-Marker ($offsetX+$point.xy[0]) ($offsetY+$point.xy[1]) $point.kind $point.name }
        Add-Text 'NANSHA' 790 510 24 '#789194'
        Add-Text 'DONGGUAN' 1190 433 24 '#789194'
        Add-Text 'ZHONGSHAN' 615 974 24 '#789194'
        Add-Text 'SHENZHEN' 1590 800 24 '#789194'
        Add-Text 'ZHUHAI' 709 1360 24 '#789194'
        Add-Text 'HONG KONG' 1740 1270 24 '#789194'
        Add-Text 'LINGDINGYANG' 1110 1270 24 '#789194'
        Add-Text 'INDEX / EVIDENCE' 2340 249 29 '#163D42' $true
        $rowTop = 311
        $rowStep = [Math]::Min(76, [Math]::Floor(1400 / $sheet.points.Count))
        $indexFont = if ($sheet.points.Count -gt 22) { 25 } else { 27 }
        foreach ($point in $sheet.points) {
            Add-Marker 2360 ($rowTop+19) $point.kind ''
            Add-Text $point.name 2390 $rowTop $indexFont '#223E42' $true
            $rowTop += $rowStep
        }
        $rowTop += 25
        Add-Text 'READING NOTES' 2340 $rowTop 26 '#163D42' $true
        $rowTop += 49
        foreach ($note in @('绿色自然、蓝紫规划、橙色港区研究面。','沿可辨岸形概化，内陆边界仍为示意。','虚线为观景界面／联系，不是航迹。','非工程红线、非权属界，未地理配准。','来源名称、城市对和措施见交互图谱。')) {
            Add-Text $note 2340 $rowTop 25 '#4C6266'
            $rowTop += 46
        }
        Add-Text '综合资源、旅游产品与公共空间供给，识别展靓、提质及避让机会；本图不代替分段证据判断。' 65 2182 35 '#163D42' $true
        Add-Text 'SCHEMATIC ONLY / 2026-09-23 / IMAGE-SPACE DIGITISING / NO GIS REGISTRATION / NO NAVIGATION USE' 66 2260 25 '#607579'
        Add-Text 'Named sources and assessments: offline atlas. All locations provisional. User-supplied basemap; original unchanged.' 66 2307 24 '#607579'
        [void]$svg.AppendLine('</svg>')
        $bitmap.Save((Join-Path $output ($sheet.file+'.png')), [System.Drawing.Imaging.ImageFormat]::Png)
        [System.IO.File]::WriteAllText((Join-Path $output ($sheet.file+'.svg')), $svg.ToString(), $utf8)
        $thumbnail = [System.Drawing.Bitmap]::new(1650,1190)
        $thumbGraphics = [System.Drawing.Graphics]::FromImage($thumbnail)
        $thumbGraphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $thumbGraphics.DrawImage($bitmap,0,0,1650,1190)
        $thumbnail.Save((Join-Path $output ($sheet.file+'_preview.png')), [System.Drawing.Imaging.ImageFormat]::Png)
        $thumbGraphics.Dispose()
        $thumbnail.Dispose()
        $graphics.Dispose()
        $bitmap.Dispose()
        Write-Output "Rendered $($sheet.file)"
    }
} finally { $baseImage.Dispose() }