[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ReleaseRoot,

    [Parameter(Mandatory = $true)]
    [string]$OutputPath,

    [ValidateSet('Codex', 'Coze')]
    [string]$Target = 'Coze',

    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-FrontmatterKeys {
    param([Parameter(Mandatory = $true)][string]$Path)

    $lines = Get-Content -Encoding UTF8 -LiteralPath $Path
    if ($lines.Count -lt 4 -or $lines[0] -ne '---') {
        throw "SKILL.md缺少YAML frontmatter：$Path"
    }

    $end = -1
    for ($i = 1; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -eq '---') {
            $end = $i
            break
        }
    }
    if ($end -lt 0) {
        throw "SKILL.md frontmatter未闭合：$Path"
    }

    $keys = @()
    foreach ($line in $lines[1..($end - 1)]) {
        if ($line -match '^([a-zA-Z0-9_-]+):') {
            $keys += $Matches[1]
        }
    }
    return $keys
}

$release = (Resolve-Path -LiteralPath $ReleaseRoot).Path
$skillSource = Join-Path $release 'SKILL.md'
if (-not (Test-Path -LiteralPath $skillSource -PathType Leaf)) {
    throw "发行根目录缺少SKILL.md：$release"
}

$outputFull = [System.IO.Path]::GetFullPath($OutputPath)
if (Test-Path -LiteralPath $outputFull) {
    if (-not $Force) {
        throw "输出文件已存在；确认覆盖时使用-Force：$outputFull"
    }
    Remove-Item -LiteralPath $outputFull -Force
}

$outputParent = [System.IO.Directory]::GetParent($outputFull).FullName
if (-not (Test-Path -LiteralPath $outputParent)) {
    New-Item -ItemType Directory -Path $outputParent -Force | Out-Null
}

$stage = Join-Path ([System.IO.Path]::GetTempPath()) ("novel-writing-template-" + [guid]::NewGuid().ToString('N'))
$referencesRoot = Join-Path $stage 'references'
New-Item -ItemType Directory -Path $referencesRoot -Force | Out-Null

try {
    $files = Get-ChildItem -LiteralPath $release -Recurse -File -Force | Where-Object {
        $relative = [System.IO.Path]::GetRelativePath($release, $_.FullName)
        $segments = $relative -split '[\\/]'
        $relative -ne 'SKILL.md' -and
        $relative -ne '99_来源与维护\通用模板库文件清单.tsv' -and
        -not ($segments | Where-Object { $_ -in @('.git', '.obsidian', '.trash', 'dist', '发行包') })
    }

    foreach ($file in $files) {
        $relative = [System.IO.Path]::GetRelativePath($release, $file.FullName)
        $destinationFile = Join-Path $referencesRoot $relative
        $destinationParent = [System.IO.Directory]::GetParent($destinationFile).FullName
        if (-not (Test-Path -LiteralPath $destinationParent)) {
            New-Item -ItemType Directory -Path $destinationParent -Force | Out-Null
        }
        Copy-Item -LiteralPath $file.FullName -Destination $destinationFile -Force
    }

    Get-ChildItem -LiteralPath $referencesRoot -Recurse -File -Filter '*.md' | ForEach-Object {
        $referenceText = Get-Content -Raw -Encoding UTF8 -LiteralPath $_.FullName
        $cleanedReferenceText = $referenceText -replace '\[([^\]]+)\]\((?:<)?[^)\r\n]*发行包[^)\r\n]*(?:>)?\)', '$1'
        $cleanedReferenceText = $cleanedReferenceText.Replace('通用模板库文件清单.tsv', '技能包文件清单.tsv')
        $topSkillRelative = [System.IO.Path]::GetRelativePath($_.DirectoryName, (Join-Path $stage 'SKILL.md')).Replace('\', '/')
        $cleanedReferenceText = [regex]::Replace($cleanedReferenceText, '\((?:<)?(?:\.\.?/)*SKILL\.md(?:>)?\)', "($topSkillRelative)")
        if ($cleanedReferenceText -ne $referenceText) {
            [System.IO.File]::WriteAllText($_.FullName, $cleanedReferenceText, [System.Text.UTF8Encoding]::new($false))
        }
    }

    $skillText = Get-Content -Raw -Encoding UTF8 -LiteralPath $skillSource
    $prefixes = @(
        '00_模板库入口/',
        '00_Obsidian导航/',
        '01_通用规则库/',
        '02_语言与风格库/',
        '03_新书项目骨架/',
        '04_写作模板库/',
        '05_人物与设定模板库/',
        '06_核验模板库/',
        '07_工具脚本/',
        '99_来源与维护/'
    )
    foreach ($prefix in $prefixes) {
        $skillText = $skillText.Replace($prefix, "references/$prefix")
    }
    $skillText = $skillText.Replace('(OBSIDIAN_库入口.md)', '(references/OBSIDIAN_库入口.md)')

    if ($Target -eq 'Coze') {
        $skillText = $skillText -replace '(?m)^(description:.*)$', "`$1`nrequired_skills: []"
    }

    $packagedSkill = Join-Path $stage 'SKILL.md'
    [System.IO.File]::WriteAllText($packagedSkill, $skillText, [System.Text.UTF8Encoding]::new($false))

    $packageManifest = Join-Path $referencesRoot '99_来源与维护\技能包文件清单.tsv'
    $packageManifestParent = [System.IO.Directory]::GetParent($packageManifest).FullName
    if (-not (Test-Path -LiteralPath $packageManifestParent)) {
        New-Item -ItemType Directory -Path $packageManifestParent -Force | Out-Null
    }
    Get-ChildItem -LiteralPath $referencesRoot -Recurse -File -Force |
        Where-Object { $_.FullName -ne $packageManifest } |
        Sort-Object FullName |
        ForEach-Object {
            [PSCustomObject]@{
                RelativePath = [System.IO.Path]::GetRelativePath($referencesRoot, $_.FullName)
                Length = $_.Length
                SHA256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $_.FullName).Hash
            }
        } | Export-Csv -LiteralPath $packageManifest -Delimiter "`t" -NoTypeInformation -Encoding UTF8

    $keys = @(Get-FrontmatterKeys -Path $packagedSkill)
    $allowedKeys = if ($Target -eq 'Coze') { @('name', 'description', 'required_skills') } else { @('name', 'description') }
    $unexpected = @($keys | Where-Object { $_ -notin $allowedKeys })
    if ($unexpected.Count -gt 0 -or 'name' -notin $keys -or 'description' -notin $keys) {
        throw "SKILL.md frontmatter不符合$Target目标；当前键：$($keys -join ', ')"
    }
    if ($Target -eq 'Codex' -and $keys.Count -ne 2) {
        throw "Codex SKILL.md frontmatter只能包含name和description；当前键：$($keys -join ', ')"
    }
    if ($Target -eq 'Coze' -and ('required_skills' -notin $keys -or $keys.Count -ne 3)) {
        throw "扣子SKILL.md frontmatter必须包含name、description和required_skills；当前键：$($keys -join ', ')"
    }

    $textExtensions = @('.md', '.ps1', '.tsv', '.txt', '.example', '.json')
    $pathLeaks = @()
    Get-ChildItem -LiteralPath $stage -Recurse -File | Where-Object {
        $_.Extension -in $textExtensions -or $_.Name -in @('LICENSE', '.gitignore')
    } | ForEach-Object {
        $content = Get-Content -Raw -Encoding UTF8 -LiteralPath $_.FullName
        if ($content -match '[A-Za-z]:\\') {
            $pathLeaks += [System.IO.Path]::GetRelativePath($stage, $_.FullName)
        }
    }
    if ($pathLeaks.Count -gt 0) {
        throw "技能包仍含本机绝对路径：$($pathLeaks -join ', ')"
    }

    Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $outputFull -CompressionLevel Optimal

    $zip = Get-Item -LiteralPath $outputFull
    $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $outputFull).Hash
    [PSCustomObject]@{
        OutputPath = $zip.FullName
        Files = (Get-ChildItem -LiteralPath $stage -Recurse -File).Count
        Bytes = $zip.Length
        SHA256 = $hash
        Target = $Target
        Frontmatter = $keys -join ','
    }
}
finally {
    if (Test-Path -LiteralPath $stage) {
        Remove-Item -LiteralPath $stage -Recurse -Force
    }
}
