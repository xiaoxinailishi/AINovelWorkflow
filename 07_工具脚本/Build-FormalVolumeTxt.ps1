param(
    [Parameter(Mandatory = $true)][string]$RootDir,
    [Parameter(Mandatory = $true)][string]$ProfilePath,
    [Parameter(Mandatory = $true)][string]$OutputPath,
    [string]$EndingMarkerRegex = '（第.+卷结束）'
)

$ErrorActionPreference = 'Stop'
$rootFull = [System.IO.Path]::GetFullPath($RootDir).TrimEnd('\')
$outputFull = [System.IO.Path]::GetFullPath($OutputPath)
if (-not $outputFull.StartsWith($rootFull + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
    throw 'OutputPath must be inside RootDir.'
}
$OutputPath = $outputFull
$profile = Get-Content -Raw -Encoding UTF8 -LiteralPath $ProfilePath | ConvertFrom-Json
$volumeDir = Split-Path -Parent ([System.IO.Path]::GetFullPath($OutputPath))
$parts = New-Object System.Collections.Generic.List[string]
$sourceRows = New-Object System.Collections.Generic.List[object]

foreach ($chapter in $profile.chapters) {
    $path = Join-Path $volumeDir ([string]$chapter.sourceFile)
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Formal chapter missing: $path"
    }
    $raw = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
    $normalized = ($raw -replace "`r`n", "`n") -replace "`r", "`n"
    $normalized = $normalized.TrimEnd("`n".ToCharArray())
    if ($normalized -notmatch '^# .+') {
        throw "Formal title format error: $path"
    }
    $parts.Add($normalized)
    $sourceRows.Add([pscustomobject]@{
        File = [System.IO.Path]::GetFileName($path)
        SHA256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash
    })
}

$expectedLf = ($parts -join "`n`n") + "`n"
$expectedCrlf = $expectedLf -replace "`n", "`r`n"
$utf8Bom = New-Object System.Text.UTF8Encoding($true)
[System.IO.File]::WriteAllText($OutputPath, $expectedCrlf, $utf8Bom)

$bytes = [System.IO.File]::ReadAllBytes($OutputPath)
if ($bytes.Length -lt 3 -or $bytes[0] -ne 0xEF -or $bytes[1] -ne 0xBB -or $bytes[2] -ne 0xBF) {
    throw 'TXT has no UTF-8 BOM'
}
$actual = [System.IO.File]::ReadAllText($OutputPath, [System.Text.Encoding]::UTF8)
if ($actual -ne $expectedCrlf) {
    throw 'TXT readback differs from expected text'
}
if ([regex]::IsMatch($actual, '(?<!\r)\n')) {
    throw 'TXT contains non-CRLF newlines'
}
$headings = [regex]::Matches($actual, '(?m)^# .+').Count
if ($headings -ne $profile.chapters.Count) {
    throw "TXT heading count mismatch: $headings"
}
if ($actual -notmatch ('(?m)^# .+' + $EndingMarkerRegex + '\r?$')) {
    throw 'TXT has no volume-ending title marker'
}

[pscustomobject]@{
    Chapters = $headings
    CharactersIncludingWhitespace = $actual.Length
    Bytes = $bytes.Length
    SHA256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $OutputPath).Hash
    NormalizedContentSHA256 = ([BitConverter]::ToString(
        [System.Security.Cryptography.SHA256]::Create().ComputeHash(
            [System.Text.Encoding]::UTF8.GetBytes($expectedLf)
        )
    ) -replace '-', '')
    Sources = $sourceRows
}
