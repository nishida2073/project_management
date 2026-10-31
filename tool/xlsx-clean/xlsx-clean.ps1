param(
    [Parameter(Mandatory = $true)][string]$Path,
    [string]$Output,
    [int]$RowMargin = 10,
    [switch]$TrimFormat
)

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$src = (Resolve-Path -LiteralPath $Path).ProviderPath
if (-not $Output) {
    $Output = Join-Path (Split-Path -Parent $src) (([IO.Path]::GetFileNameWithoutExtension($src)) + '_clean' + [IO.Path]::GetExtension($src))
}
if ($Output -eq $src) {
    Write-Host "出力先が元ファイルと同じです。別のファイル名を指定してください。"
    exit 1
}

$enc = New-Object System.Text.UTF8Encoding($false)
$zin = [IO.Compression.ZipFile]::OpenRead($src)
$order = New-Object System.Collections.Generic.List[string]
$raw = @{}
foreach ($e in $zin.Entries) {
    $order.Add($e.FullName)
    $ms = New-Object IO.MemoryStream
    $st = $e.Open()
    $st.CopyTo($ms)
    $st.Dispose()
    $raw[$e.FullName] = $ms.ToArray()
}
$zin.Dispose()

$xml = @{}
$dirty = @{}
$removed = New-Object System.Collections.Generic.HashSet[string]
$stat = [ordered]@{
    '隠し定義名' = 0
    '外部参照の定義名' = 0
    '外部リンク' = 0
    '参照エラーのCF' = 0
    'CF統合(減ったルール数)' = 0
    '範囲の縮小' = 0
    '空セルの書式' = 0
    '行・列の書式' = 0
}

function Get-Xml([string]$name) {
    if (-not $xml.ContainsKey($name)) {
        $xml[$name] = [Text.Encoding]::UTF8.GetString($raw[$name])
    }
    return $xml[$name]
}

function Set-Xml([string]$name, [string]$text) {
    $xml[$name] = $text
    $dirty[$name] = $true
}

function ColNum([string]$s) {
    $n = 0
    foreach ($c in $s.ToCharArray()) { $n = $n * 26 + [int]$c - 64 }
    return $n
}

function Get-Cells([string]$sq) {
    $set = New-Object 'System.Collections.Generic.HashSet[long]'
    foreach ($p in ($sq -split ' ')) {
        if ($p -notmatch '^([A-Z]+)(\d+)(?::([A-Z]+)(\d+))?$') { continue }
        $c1 = ColNum $matches[1]
        $r1 = [int]$matches[2]
        if ($matches[3]) { $c2 = ColNum $matches[3]; $r2 = [int]$matches[4] } else { $c2 = $c1; $r2 = $r1 }
        for ($c = $c1; $c -le $c2; $c++) {
            for ($r = $r1; $r -le $r2; $r++) { [void]$set.Add([long]$c * 10000000 + $r) }
        }
    }
    return ,$set
}

function Limit-Sqref([string]$sq, [int]$maxRow) {
    $parts = @()
    foreach ($p in ($sq -split ' ')) {
        if ($p -match '^([A-Z]+)(\d+):([A-Z]+)(\d+)$' -and [int]$matches[4] -gt $maxRow) {
            if ([int]$matches[2] -gt $maxRow) { $stat['範囲の縮小']++; continue }
            $parts += "$($matches[1])$($matches[2]):$($matches[3])$maxRow"
            $stat['範囲の縮小']++
        }
        else {
            $parts += $p
        }
    }
    return ($parts -join ' ')
}

$wb = Get-Xml 'xl/workbook.xml'
$sheetNames = @($order | Where-Object { $_ -match '^xl/worksheets/sheet\d+\.xml$' })
$sheetText = ($sheetNames | ForEach-Object { Get-Xml $_ }) -join "`n"

$defRe = [regex]'<definedName\b([^>]*)>(.*?)</definedName>'
$bodyAll = ($defRe.Matches($wb) | ForEach-Object { [Net.WebUtility]::HtmlDecode($_.Groups[2].Value) }) -join "`n"
$wb = $defRe.Replace($wb, [System.Text.RegularExpressions.MatchEvaluator]{
    param($m)
    $attr = $m.Groups[1].Value
    $body = [Net.WebUtility]::HtmlDecode($m.Groups[2].Value)
    $nm = [Net.WebUtility]::HtmlDecode([regex]::Match($attr, 'name="([^"]*)"').Groups[1].Value)
    if ($body -match '\[\d+\]') { $stat['外部参照の定義名']++; return '' }
    if ($attr -match 'hidden="1"' -and $nm -notlike '_xlnm*') {
        $used = $sheetText.Contains($nm) -or $bodyAll.Replace($body, '').Contains($nm)
        if (-not $used) { $stat['隠し定義名']++; return '' }
    }
    return $m.Value
})

$extParts = @($order | Where-Object { $_ -like 'xl/externalLinks/*' })
$stillExternal = [regex]::IsMatch($sheetText, '<f\b[^>]*>[^<]*\[\d+\]') -or [regex]::IsMatch($wb, '\[\d+\]')
if (-not $stillExternal -and ($extParts.Count -gt 0 -or $wb -match '<externalReferences>')) {
    $wb = [regex]::Replace($wb, '<externalReferences>.*?</externalReferences>', '', 'Singleline')
    $rels = Get-Xml 'xl/_rels/workbook.xml.rels'
    Set-Xml 'xl/_rels/workbook.xml.rels' ([regex]::Replace($rels, '<Relationship [^>]*externalLink[^>]*/>', ''))
    $ct = Get-Xml '[Content_Types].xml'
    Set-Xml '[Content_Types].xml' ([regex]::Replace($ct, '<Override [^>]*externalLink[^>]*/>', ''))
    foreach ($p in $extParts) { [void]$removed.Add($p) }
    $stat['外部リンク'] = $extParts.Count
}
Set-Xml 'xl/workbook.xml' $wb

$styles = Get-Xml 'xl/styles.xml'
$dxfBlock = [regex]::Match($styles, '<dxfs count="\d+">(.*?)</dxfs>', 'Singleline').Groups[1].Value
$dxfs = @([regex]::Matches($dxfBlock, '<dxf>.*?</dxf>|<dxf/>', 'Singleline') | ForEach-Object { $_.Value })

$blockRe = [regex]'<conditionalFormatting sqref="([^"]*)">(.*?)</conditionalFormatting>'
$ruleRe = [regex]'<cfRule\b[^>]*?(?:/>|>.*?</cfRule>)'

foreach ($sn in $sheetNames) {
    $sx = Get-Xml $sn
    $maxR = 0
    $maxC = 0
    foreach ($m in [regex]::Matches($sx, '<c r="([A-Z]+)(\d+)"[^>/]*>(?:<f|<v|<is)')) {
        $c = ColNum $m.Groups[1].Value
        $r = [int]$m.Groups[2].Value
        if ($r -gt $maxR) { $maxR = $r }
        if ($c -gt $maxC) { $maxC = $c }
    }

    $rowLimit = $maxR + $RowMargin
    $entries = New-Object System.Collections.Generic.List[object]
    $blocks = $blockRe.Matches($sx)
    $bi = 0
    $blockSq = @{}
    foreach ($b in $blocks) {
        $sq = Limit-Sqref $b.Groups[1].Value $rowLimit
        if (-not $sq) { $bi++; continue }
        $blockSq[$bi] = $sq
        $anc = (($sq -split ' ')[0] -split ':')[0]
        foreach ($rm in $ruleRe.Matches($b.Groups[2].Value)) {
            $rt = $rm.Value
            if ($rt -match '#REF!') { $stat['参照エラーのCF']++; continue }
            $attrs = @{}
            foreach ($am in [regex]::Matches([regex]::Match($rt, '^<cfRule\b([^>]*)>').Groups[1].Value, '(\w+)="([^"]*)"')) {
                $attrs[$am.Groups[1].Value] = $am.Groups[2].Value
            }
            $ok = $true
            $norm = @()
            foreach ($fm in [regex]::Matches($rt, '<formula>(.*?)</formula>')) {
                $f = [Net.WebUtility]::HtmlDecode($fm.Groups[1].Value)
                foreach ($tm in [regex]::Matches($f, '(?<![A-Za-z$])(\$?[A-Z]{1,3}\$?\d+)')) {
                    $t = $tm.Groups[1].Value
                    if ($t -ne $anc -and $t -notmatch '^\$[A-Z]{1,3}\$\d+$') { $ok = $false }
                }
                $norm += [regex]::Replace($f, '(?<![A-Za-z$])' + [regex]::Escape($anc) + '(?!\d)', '@')
            }
            $dxfText = if ($attrs.ContainsKey('dxfId')) { $dxfs[[int]$attrs['dxfId']] } else { '' }
            $key = (@($attrs['type'], $attrs['operator'], $dxfText, $attrs['stopIfTrue'], ($norm -join '|')) -join '##')
            $entries.Add([pscustomobject]@{
                Block = $bi
                Anchor = $anc
                Sq = $sq
                Rule = $rt
                Attrs = $attrs
                Key = $key
                Ok = $ok
                Cells = (Get-Cells $sq)
                Group = $null
            })
        }
        $bi++
    }

    $groups = @{}
    foreach ($e in $entries) {
        if (-not $e.Ok) { continue }
        if (-not $groups.ContainsKey($e.Key)) { $groups[$e.Key] = New-Object System.Collections.Generic.List[object] }
        $groups[$e.Key].Add($e)
    }
    $merged = New-Object System.Collections.Generic.List[string]
    foreach ($key in $groups.Keys) {
        $mem = $groups[$key]
        if ($mem.Count -lt 2) { continue }
        $gset = New-Object 'System.Collections.Generic.HashSet[long]'
        foreach ($e in $mem) { $gset.UnionWith($e.Cells) }
        $conflict = $false
        foreach ($e in $entries) {
            if ($mem.Contains($e)) { continue }
            if ($gset.Overlaps($e.Cells)) { $conflict = $true; break }
        }
        if ($conflict) { continue }
        foreach ($e in $mem) { $e.Group = $key }

        $sorted = @($mem | Sort-Object { ColNum ([regex]::Match($_.Anchor, '^[A-Z]+').Value) }, { [int]([regex]::Match($_.Anchor, '\d+$').Value) })
        $anchor = $sorted[0].Anchor
        $ranges = ($sorted | ForEach-Object { $_.Sq }) -join ' '
        $first = $sorted[0]
        $prio = ($mem | ForEach-Object { [int]$_.Attrs['priority'] } | Measure-Object -Minimum).Minimum
        $formulaText = ''
        foreach ($f in ($key -split '##')[-1] -split '\|') {
            $formulaText += '<formula>' + ($f.Replace('@', $anchor).Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;')) + '</formula>'
        }
        $extra = ''
        if ($first.Attrs.ContainsKey('stopIfTrue') -and $first.Attrs['stopIfTrue']) { $extra += ' stopIfTrue="' + $first.Attrs['stopIfTrue'] + '"' }
        $op = if ($first.Attrs.ContainsKey('operator') -and $first.Attrs['operator']) { ' operator="' + $first.Attrs['operator'] + '"' } else { '' }
        $rule = '<cfRule type="' + $first.Attrs['type'] + '" dxfId="' + $first.Attrs['dxfId'] + '" priority="' + $prio + '"' + $extra + $op + '>' + $formulaText + '</cfRule>'
        $merged.Add('<conditionalFormatting sqref="' + $ranges + '">' + $rule + '</conditionalFormatting>')
        $stat['CF統合(減ったルール数)'] += $mem.Count - 1
    }

    $sb = New-Object System.Text.StringBuilder
    $pos = 0
    $last = $blocks.Count - 1
    for ($i = 0; $i -le $last; $i++) {
        $b = $blocks[$i]
        [void]$sb.Append($sx.Substring($pos, $b.Index - $pos))
        $pos = $b.Index + $b.Length
        $kept = @($entries | Where-Object { $_.Block -eq $i -and -not $_.Group } | ForEach-Object { $_.Rule })
        $sq = $blockSq[$i]
        if ($sq -and $kept.Count -gt 0) {
            [void]$sb.Append('<conditionalFormatting sqref="' + $sq + '">' + ($kept -join '') + '</conditionalFormatting>')
        }
        if ($i -eq $last) {
            foreach ($mtext in $merged) { [void]$sb.Append($mtext) }
        }
    }
    [void]$sb.Append($sx.Substring($pos))
    $sx = $sb.ToString()

    $sx = [regex]::Replace($sx, '(<dataValidation\b[^>]*?sqref=")([^"]*)(")', [System.Text.RegularExpressions.MatchEvaluator]{
        param($m)
        $m.Groups[1].Value + (Limit-Sqref $m.Groups[2].Value $rowLimit) + $m.Groups[3].Value
    })

    if ($TrimFormat -and $maxC -gt 0) {
        $sx = [regex]::Replace($sx, '<col min="(\d+)" max="(\d+)"([^>]*)/>', [System.Text.RegularExpressions.MatchEvaluator]{
            param($m)
            $mn = [int]$m.Groups[1].Value
            $mx = [int]$m.Groups[2].Value
            if ($mn -gt $maxC) { $stat['行・列の書式']++; return '' }
            if ($mx -gt $maxC) { $stat['行・列の書式']++; return "<col min=""$mn"" max=""$maxC""$($m.Groups[3].Value)/>" }
            return $m.Value
        })
        $sx = [regex]::Replace($sx, '<cols>\s*</cols>', '')
    }
    if ($TrimFormat -and $maxR -gt 0) {
        $sx = [regex]::Replace($sx, '<row r="(\d+)"([^>]*)>', [System.Text.RegularExpressions.MatchEvaluator]{
            param($m)
            if ([int]$m.Groups[1].Value -le $maxR) { return $m.Value }
            $attrs = $m.Groups[2].Value
            $changed = $attrs -match ' s="\d+"' -or $attrs -match ' customFormat="1"'
            if ($changed) { $stat['行・列の書式']++ }
            $attrs = [regex]::Replace($attrs, ' s="\d+"', '')
            $attrs = [regex]::Replace($attrs, ' customFormat="1"', '')
            return "<row r=""$($m.Groups[1].Value)""$attrs>"
        })
        $sx = [regex]::Replace($sx, '<c r="([A-Z]+)(\d+)"[^>]*/>', [System.Text.RegularExpressions.MatchEvaluator]{
            param($m)
            if ((ColNum $m.Groups[1].Value) -le $maxC -and [int]$m.Groups[2].Value -le $maxR) { return $m.Value }
            $stat['空セルの書式']++
            return ''
        })
    }

    if ($sx -ne (Get-Xml $sn)) { Set-Xml $sn $sx }
}

foreach ($n in $dirty.Keys) {
    if ($n.EndsWith('.xml') -or $n.EndsWith('.rels')) {
        try { [void][xml]$xml[$n] } catch { throw "XML が壊れています: $n" }
    }
}

if (Test-Path -LiteralPath $Output) { Remove-Item -LiteralPath $Output -Force }
$zout = [IO.Compression.ZipFile]::Open($Output, 'Create')
foreach ($n in $order) {
    if ($removed.Contains($n)) { continue }
    $ent = $zout.CreateEntry($n)
    $es = $ent.Open()
    if ($dirty.ContainsKey($n)) { $bytes = $enc.GetBytes($xml[$n]) } else { $bytes = $raw[$n] }
    $es.Write($bytes, 0, $bytes.Length)
    $es.Dispose()
}
$zout.Dispose()

Write-Host "出力: $Output"
foreach ($k in $stat.Keys) { Write-Host ("  {0}: {1}" -f $k, $stat[$k]) }
