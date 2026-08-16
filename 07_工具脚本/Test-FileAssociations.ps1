param(
    [Parameter(Mandatory = $true)][string]$VaultRoot,
    [switch]$FailOnMissing
)

$ErrorActionPreference = 'Stop'
$vaultFull = [IO.Path]::GetFullPath($VaultRoot).TrimEnd('\')
if (-not (Test-Path -LiteralPath $vaultFull -PathType Container)) {
    throw "Vault root not found: $vaultFull"
}

$excludedDirectoryNames = @('.obsidian', '.git', '.trash', '99_迁移与历史')
function Test-IsExcludedPath {
    param([Parameter(Mandatory = $true)][string]$FullPath)

    $relative = $FullPath.Substring($vaultFull.Length).TrimStart('\')
    $separatorPattern = [regex]::Escape([IO.Path]::DirectorySeparatorChar)
    $segments = @($relative -split $separatorPattern)
    if ($segments | Where-Object { $_ -in $excludedDirectoryNames }) { return $true }
    if ($relative.StartsWith('00_Obsidian导航\文件夹节点\', [StringComparison]::OrdinalIgnoreCase)) { return $true }
    return $false
}

function Remove-FencedCode {
    param([Parameter(Mandatory = $true)][string]$Text)
    return [regex]::Replace($Text, '(?ms)^```.*?^```\s*', '')
}

function Test-HasAssociationBlock {
    param([Parameter(Mandatory = $true)][string]$Text)

    if ($Text -match '(?m)^##\s+.*文件关联\s*$') { return $true }

    $frontMatter = [regex]::Match($Text, '\A---\r?\n(?<yaml>.*?)\r?\n---(?:\r?\n|\z)', 'Singleline')
    if (-not $frontMatter.Success) { return $false }

    $yaml = $frontMatter.Groups['yaml'].Value
    $hasFileType = $yaml -match '(?m)^文件类型\s*:'
    $hasBusinessLink = $yaml -match '(?m)^(卷纲|细纲|执行入口|来源工作单元|人物卡|研究与任务卡|核验记录|修改记录)\s*:'
    return $hasFileType -and $hasBusinessLink
}

function Get-OutgoingLinkCount {
    param([Parameter(Mandatory = $true)][string]$Text)

    $withoutCode = Remove-FencedCode -Text $Text
    $markdown = [regex]::Matches($withoutCode, '(?<!\!)\[[^\]]+\]\((?<target>[^)]+)\)') |
        Where-Object { $_.Groups['target'].Value -notmatch '^(?:https?|mailto):' }
    $wiki = [regex]::Matches($withoutCode, '\[\[(?<target>[^\]|#]+)(?:#[^\]|]+)?(?:\|[^\]]+)?\]\]')
    return $markdown.Count + $wiki.Count
}

$files = @(Get-ChildItem -LiteralPath $vaultFull -Recurse -File -Filter '*.md' -Force |
    Where-Object { -not (Test-IsExcludedPath -FullPath $_.FullName) } |
    Sort-Object FullName)

$missingAssociation = [Collections.Generic.List[string]]::new()
$withoutOutgoingLink = [Collections.Generic.List[string]]::new()
$withAssociation = 0
$withOutgoingLink = 0

foreach ($file in $files) {
    $text = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8
    $relative = $file.FullName.Substring($vaultFull.Length).TrimStart('\')

    if (Test-HasAssociationBlock -Text $text) {
        $withAssociation++
    } else {
        $missingAssociation.Add($relative)
    }

    if ((Get-OutgoingLinkCount -Text $text) -gt 0) {
        $withOutgoingLink++
    } else {
        $withoutOutgoingLink.Add($relative)
    }
}

"VaultRoot=$vaultFull"
"MarkdownFiles=$($files.Count)"
"WithAssociation=$withAssociation"
"MissingAssociation=$($missingAssociation.Count)"
"WithOutgoingBusinessCandidate=$withOutgoingLink"
"WithoutOutgoingBusinessCandidate=$($withoutOutgoingLink.Count)"

foreach ($relative in $missingAssociation) {
    "MISSING_ASSOCIATION`t$relative"
}
foreach ($relative in $withoutOutgoingLink) {
    "NO_OUTGOING_LINK`t$relative"
}

if ($FailOnMissing -and ($missingAssociation.Count -gt 0 -or $withoutOutgoingLink.Count -gt 0)) {
    exit 2
}
