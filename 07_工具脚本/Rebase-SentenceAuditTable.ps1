param(
    [Parameter(Mandatory = $true)][string]$SourcePath,
    [Parameter(Mandatory = $true)][string]$TablePath,
    [Parameter(Mandatory = $true)][ValidatePattern('^[WC]\d{3}$')][string]$Prefix
)

$ErrorActionPreference = 'Stop'
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$source = [IO.Path]::GetFullPath($SourcePath)
$tablePathFull = [IO.Path]::GetFullPath($TablePath)

if (-not [IO.File]::Exists($source)) { throw "正文不存在：$source" }
if (-not [IO.File]::Exists($tablePathFull)) { throw "逐句表不存在：$tablePathFull" }

$sourceLines = [IO.File]::ReadAllLines($source, [Text.Encoding]::UTF8)
$tableLines = [IO.File]::ReadAllLines($tablePathFull, [Text.Encoding]::UTF8)
$sha = (Get-FileHash -Algorithm SHA256 -LiteralPath $source).Hash

$closeChars = ([char]0x201D).ToString() + ([char]0x2019).ToString() + ([char]0x300D).ToString() + ([char]0x300F).ToString() + ([char]0xFF09).ToString() + ([char]0x3011).ToString() + ([char]0x300B).ToString()
$sentencePattern = '.+?(?:[。！？?!]+[' + [regex]::Escape($closeChars) + ']?|$)'
$items = New-Object System.Collections.Generic.List[object]

for ($i = 0; $i -lt $sourceLines.Length; $i++) {
    $trimmed = $sourceLines[$i].Trim()
    if ([string]::IsNullOrWhiteSpace($trimmed)) { continue }
    if ($trimmed -match '^#{1,6}\s+' -or $trimmed -match '^---+$') { continue }
    foreach ($match in [regex]::Matches($trimmed, $sentencePattern)) {
        $text = $match.Value.Trim()
        if (-not [string]::IsNullOrWhiteSpace($text)) {
            $items.Add([pscustomobject]@{ Line = $i + 1; Text = $text })
        }
    }
}

$rowPattern = '^\|\s*' + [regex]::Escape($Prefix) + '-S\d{4}\s*\|\s*\d+\s*\|\s*(.*?)\s*\|\s*(.*?)\s*\|\s*(.*?)\s*\|\s*(.*?)\s*\|\s*(.*?)\s*\|\s*(.*?)\s*\|\s*(.*?)\s*\|$'
$oldRows = @{}
$firstRowIndex = -1
$lastRowIndex = -1

for ($i = 0; $i -lt $tableLines.Length; $i++) {
    $m = [regex]::Match($tableLines[$i], $rowPattern)
    if (-not $m.Success) { continue }
    if ($firstRowIndex -lt 0) { $firstRowIndex = $i }
    $lastRowIndex = $i
    $text = $m.Groups[1].Value.Trim()
    if (-not $oldRows.ContainsKey($text)) {
        $oldRows[$text] = New-Object System.Collections.Generic.Queue[object]
    }
    $oldRows[$text].Enqueue([pscustomobject]@{
        Type = $m.Groups[2].Value.Trim()
        Actor = $m.Groups[3].Value.Trim()
        Trigger = $m.Groups[4].Value.Trim()
        Judgment = $m.Groups[5].Value.Trim()
        Problem = $m.Groups[6].Value.Trim()
        Record = $m.Groups[7].Value.Trim()
    })
}

if ($firstRowIndex -lt 0 -or $lastRowIndex -lt $firstRowIndex) {
    throw '未找到旧逐句表正文行'
}

function Escape-Cell([string]$value) {
    return $value.Replace('|', '\|').Replace("`r", '').Replace("`n", '<br>')
}

$newRows = New-Object System.Collections.Generic.List[string]
$unmatched = 0
for ($i = 0; $i -lt $items.Count; $i++) {
    $id = '{0}-S{1:D4}' -f $Prefix, ($i + 1)
    $text = Escape-Cell $items[$i].Text
    $meta = $null
    if ($oldRows.ContainsKey($text) -and $oldRows[$text].Count -gt 0) {
        $meta = $oldRows[$text].Dequeue()
    }
    if ($null -eq $meta) {
        $unmatched++
        $newRows.Add("| $id | $($items[$i].Line) | $text | 待填 | 待填 | 待填 | 待核 | 待填 | 待填 |")
    } else {
        $newRows.Add("| $id | $($items[$i].Line) | $text | $($meta.Type) | $($meta.Actor) | $($meta.Trigger) | $($meta.Judgment) | $($meta.Problem) | $($meta.Record) |")
    }
}

$result = New-Object System.Collections.Generic.List[string]
for ($i = 0; $i -lt $firstRowIndex; $i++) { $result.Add($tableLines[$i]) }
foreach ($row in $newRows) { $result.Add($row) }
for ($i = $lastRowIndex + 1; $i -lt $tableLines.Length; $i++) { $result.Add($tableLines[$i]) }

for ($i = 0; $i -lt $result.Count; $i++) {
    if ($result[$i] -match '^- 清单生成时SHA256：') { $result[$i] = "- 清单生成时SHA256：``$sha``" }
    elseif ($result[$i] -match '^- 当前最终SHA256：') { $result[$i] = "- 当前最终SHA256：``$sha``" }
    elseif ($result[$i] -match '^- 候选正文句数：') { $result[$i] = "- 候选正文句数：$($items.Count)" }
    elseif ($result[$i] -match '^- 总状态：') { $result[$i] = '- 总状态：待核' }
}

[IO.File]::WriteAllLines($tablePathFull, $result, $utf8NoBom)
Write-Output "rebased=$tablePathFull"
Write-Output "sentences=$($items.Count)"
Write-Output "unmatched=$unmatched"
Write-Output "sha256=$sha"
