param(
    [Parameter(Mandatory = $true)][string]$SourcePath,
    [Parameter(Mandatory = $true)][string]$AuditPath,
    [Parameter(Mandatory = $true)][ValidatePattern('^[WC]\d{3}$')][string]$Prefix
)

$ErrorActionPreference = 'Stop'
$source = [System.IO.Path]::GetFullPath($SourcePath)
$audit = [System.IO.Path]::GetFullPath($AuditPath)
if (-not [System.IO.File]::Exists($source)) { throw "正文不存在：$source" }
if (-not [System.IO.File]::Exists($audit)) { throw "逐句表不存在：$audit" }

$sourceHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $source).Hash
$table = [System.IO.File]::ReadAllText($audit, [System.Text.Encoding]::UTF8)
$sourceLines = [System.IO.File]::ReadAllLines($source, [System.Text.Encoding]::UTF8)
$candidateCount = 0
$seenTitle = $false
$closeChars = ([char]0x201D).ToString() + ([char]0x2019).ToString() + ([char]0x300D).ToString() + ([char]0x300F).ToString() + ([char]0xFF09).ToString() + ([char]0x3011).ToString() + ([char]0x300B).ToString()
$sentencePattern = '.+?(?:[。！？?!]+[' + [regex]::Escape($closeChars) + ']?|$)'
foreach ($line in $sourceLines) {
    $trimmed = $line.Trim()
    if ([string]::IsNullOrWhiteSpace($trimmed)) { continue }
    if (-not $seenTitle -and $trimmed -match '^#\s+') {
        $seenTitle = $true
        continue
    }
    if ($trimmed -match '^#{1,6}\s+' -or $trimmed -match '^---+$') { continue }
    $candidateCount += [regex]::Matches($trimmed, $sentencePattern).Count
}
$rowPattern = '(?m)^\|\s*' + [regex]::Escape($Prefix) + '-S\d{4}\s*\|'
$rows = [regex]::Matches($table, $rowPattern)
$ids = [regex]::Matches($table, '(?m)^\|\s*(' + [regex]::Escape($Prefix) + '-S\d{4})\s*\|') | ForEach-Object { $_.Groups[1].Value }
$unique = @($ids | Sort-Object -Unique).Count
$declaredMatch = [regex]::Match($table, '(?m)^- 候选正文句数：(\d+)\s*$')
$finalHashMatch = [regex]::Match($table, '(?m)^- 当前最终SHA256：`?([A-Fa-f0-9]{64})`?\s*$')
$pending = [regex]::Matches($table, '\|\s*(待核|待填|需改|阻断)\s*\|').Count

$errors = New-Object System.Collections.Generic.List[string]
if (-not $declaredMatch.Success) { $errors.Add('缺少候选正文句数') }
elseif ([int]$declaredMatch.Groups[1].Value -ne $rows.Count) { $errors.Add("候选句数与表格行数不一致：declared=$($declaredMatch.Groups[1].Value), rows=$($rows.Count)") }
if ($candidateCount -ne $rows.Count) { $errors.Add("当前正文候选句数与表格行数不一致：source=$candidateCount, rows=$($rows.Count)") }
if ($unique -ne $rows.Count) { $errors.Add("句号不唯一：rows=$($rows.Count), unique=$unique") }
if (-not $finalHashMatch.Success) { $errors.Add('当前最终SHA256尚未填写') }
elseif ($finalHashMatch.Groups[1].Value.ToUpperInvariant() -ne $sourceHash) { $errors.Add('当前正文SHA256与逐句表最终SHA256不一致') }
if ($pending -gt 0) { $errors.Add("仍有待核／待填／需改／阻断单元：$pending") }

Write-Output "source_sha256=$sourceHash"
Write-Output "rows=$($rows.Count)"
Write-Output "source_candidates=$candidateCount"
Write-Output "unique_ids=$unique"
Write-Output "pending_tokens=$pending"
if ($errors.Count -gt 0) {
    foreach ($error in $errors) { Write-Output "FAIL: $error" }
    exit 1
}
Write-Output 'PASS: 机械结构检查通过；本结果不代表人工内容核验通过。'
