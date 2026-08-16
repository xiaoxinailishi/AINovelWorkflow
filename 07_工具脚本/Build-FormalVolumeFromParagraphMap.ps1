param(
    [Parameter(Mandatory = $true)]
    [string]$VolumeDir,

    [Parameter(Mandatory = $true)]
    [string]$ArchiveDir,

    [Parameter(Mandatory = $true)]
    [string]$PlanPath,

    [ValidateRange(1, 1000000)]
    [int]$MinBodyNonspace = 3000,

    [ValidateRange(1, 1000000)]
    [int]$MaxBodyNonspace = 3500
)

$ErrorActionPreference = 'Stop'

if ($MaxBodyNonspace -lt $MinBodyNonspace) {
    throw 'MaxBodyNonspace must be greater than or equal to MinBodyNonspace.'
}

$volumeFull = [IO.Path]::GetFullPath($VolumeDir).TrimEnd('\')
$archiveFull = [IO.Path]::GetFullPath($ArchiveDir).TrimEnd('\')
if (-not $archiveFull.StartsWith($volumeFull + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw 'ArchiveDir must be inside VolumeDir.'
}

$plan = Get-Content -Raw -Encoding UTF8 -LiteralPath $PlanPath | ConvertFrom-Json
$sources = @(Get-ChildItem -LiteralPath $ArchiveDir -File -Filter '*.md' |
    Where-Object { $_.Name -match '^.+?(\d{3})_.*\.md$' } |
    Sort-Object Name)

if ($sources.Count -ne [int]$plan.expectedSourceFiles) {
    throw "Unexpected source file count: $($sources.Count)"
}

$paragraphs = New-Object System.Collections.Generic.List[string]
foreach ($source in $sources) {
    $raw = Get-Content -Raw -Encoding UTF8 -LiteralPath $source.FullName
    $blocks = @([regex]::Split($raw.Trim(), "\r?\n\s*\r?\n") |
        Where-Object { $_ -notmatch '^#\s' })
    foreach ($block in $blocks) {
        $paragraphs.Add($block.Trim())
    }
}

if ($paragraphs.Count -ne [int]$plan.expectedParagraphs) {
    throw "Unexpected paragraph count: $($paragraphs.Count)"
}

$start = 0
$created = New-Object System.Collections.Generic.List[string]
foreach ($chapter in $plan.chapters) {
    $endExclusive = [int]$chapter.endParagraph
    if ($endExclusive -le $start -or $endExclusive -gt $paragraphs.Count) {
        throw "Invalid paragraph boundary: $endExclusive"
    }

    $bodyParts = @()
    for ($i = $start; $i -lt $endExclusive; $i++) {
        $bodyParts += $paragraphs[$i]
    }
    $body = $bodyParts -join "`r`n`r`n"
    $bodyNonspace = ($body -replace '\s', '').Length
    if ($bodyNonspace -ne [int]$chapter.expectedBodyNonspace) {
        throw "Body length mismatch for $($chapter.file): $bodyNonspace"
    }
    if ($bodyNonspace -lt $MinBodyNonspace -or $bodyNonspace -gt $MaxBodyNonspace) {
        throw "Body length outside $MinBodyNonspace-$MaxBodyNonspace for $($chapter.file): $bodyNonspace"
    }

    $target = Join-Path $VolumeDir ([string]$chapter.file)
    if (Test-Path -LiteralPath $target) {
        throw "Target already exists: $target"
    }
    $content = '# ' + [string]$chapter.title + "`r`n`r`n" + $body + "`r`n"
    [IO.File]::WriteAllText($target, $content, [Text.UTF8Encoding]::new($false))
    $created.Add($target)
    $start = $endExclusive
}

if ($start -ne $paragraphs.Count) {
    throw "Unused paragraphs remain: $($paragraphs.Count - $start)"
}

foreach ($path in $created) {
    $raw = Get-Content -Raw -Encoding UTF8 -LiteralPath $path
    $body = $raw -replace '^# .+?\r?\n\r?\n', ''
    [pscustomobject]@{
        Name = [IO.Path]::GetFileName($path)
        BodyNonspace = (($body -replace '\s', '').Length)
        SHA256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash
    }
}
