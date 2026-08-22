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

function New-Utf8FileOnlyArchive {
    param(
        [Parameter(Mandatory = $true)][string]$SourceDirectory,
        [Parameter(Mandatory = $true)][string]$DestinationPath
    )

    Add-Type -AssemblyName System.IO.Compression
    $sourceFull = [IO.Path]::GetFullPath($SourceDirectory).TrimEnd('\')
    $utf8Strict = [Text.UTF8Encoding]::new($false, $true)
    $records = [Collections.Generic.List[object]]::new()
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($file in @(Get-ChildItem -LiteralPath $sourceFull -Recurse -File -Force | Sort-Object FullName)) {
        $entryName = [IO.Path]::GetRelativePath($sourceFull, $file.FullName).Replace('\', '/').Normalize([Text.NormalizationForm]::FormC)
        $segments = @($entryName -split '/')
        if ([string]::IsNullOrWhiteSpace($entryName) -or
            $entryName.StartsWith('/', [StringComparison]::Ordinal) -or
            $entryName -match '^[A-Za-z]:' -or
            $segments -contains '..' -or
            $segments -contains '.') {
            throw "ZIP条目路径不安全：$entryName"
        }
        if (-not $seen.Add($entryName)) {
            throw "ZIP含大小写或Unicode规范化冲突路径：$entryName"
        }
        $records.Add([PSCustomObject]@{
            SourcePath = $file.FullName
            EntryName = $entryName
            SHA256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $file.FullName).Hash
        })
    }

    $stream = [IO.File]::Open($DestinationPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    try {
        $archive = [IO.Compression.ZipArchive]::new($stream, [IO.Compression.ZipArchiveMode]::Create, $true, $utf8Strict)
        try {
            foreach ($record in $records) {
                $entry = $archive.CreateEntry($record.EntryName, [IO.Compression.CompressionLevel]::Optimal)
                $input = [IO.File]::OpenRead($record.SourcePath)
                try {
                    $entryOutput = $entry.Open()
                    try { $input.CopyTo($entryOutput) } finally { $entryOutput.Dispose() }
                } finally {
                    $input.Dispose()
                }
            }
        } finally {
            $archive.Dispose()
        }
    } finally {
        $stream.Dispose()
    }

    $verifyRoot = Join-Path ([IO.Path]::GetTempPath()) ("novel-zip-verify-" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $verifyRoot -Force | Out-Null
    try {
        $readStream = [IO.File]::OpenRead($DestinationPath)
        try {
            $readArchive = [IO.Compression.ZipArchive]::new($readStream, [IO.Compression.ZipArchiveMode]::Read, $false, $utf8Strict)
            try {
                if ($readArchive.Entries.Count -ne $records.Count) {
                    throw "ZIP条目数与源文件数不一致：ZIP=$($readArchive.Entries.Count)，源文件=$($records.Count)"
                }
                foreach ($entry in $readArchive.Entries) {
                    if ($entry.FullName.EndsWith('/', [StringComparison]::Ordinal)) {
                        throw "ZIP含显式目录条目：$($entry.FullName)"
                    }
                    $target = [IO.Path]::GetFullPath((Join-Path $verifyRoot $entry.FullName.Replace('/', '\')))
                    $verifyPrefix = [IO.Path]::GetFullPath($verifyRoot).TrimEnd('\') + '\'
                    if (-not $target.StartsWith($verifyPrefix, [StringComparison]::OrdinalIgnoreCase)) {
                        throw "ZIP解压目标越界：$($entry.FullName)"
                    }
                    $parent = [IO.Directory]::GetParent($target).FullName
                    if (-not [IO.Directory]::Exists($parent)) { [IO.Directory]::CreateDirectory($parent) | Out-Null }
                    $entryInput = $entry.Open()
                    try {
                        $fileOutput = [IO.File]::Create($target)
                        try { $entryInput.CopyTo($fileOutput) } finally { $fileOutput.Dispose() }
                    } finally {
                        $entryInput.Dispose()
                    }
                }
            } finally {
                $readArchive.Dispose()
            }
        } finally {
            $readStream.Dispose()
        }

        foreach ($record in $records) {
            $extracted = Join-Path $verifyRoot $record.EntryName.Replace('/', '\')
            if (-not (Test-Path -LiteralPath $extracted -PathType Leaf) -or
                (Get-FileHash -Algorithm SHA256 -LiteralPath $extracted).Hash -ne $record.SHA256) {
                throw "ZIP干净解压后文件缺失或SHA256不一致：$($record.EntryName)"
            }
        }
    } finally {
        $tempPrefix = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
        $verifyFull = [IO.Path]::GetFullPath($verifyRoot)
        if (-not $verifyFull.StartsWith($tempPrefix, [StringComparison]::OrdinalIgnoreCase)) {
            throw "拒绝清理非临时目录：$verifyFull"
        }
        if (Test-Path -LiteralPath $verifyFull) { Remove-Item -LiteralPath $verifyFull -Recurse -Force }
    }

    [PSCustomObject]@{
        DirectoryEntries = 0
        Utf8EntryNames = 'ENFORCED'
        CleanExtractionSHA256 = 'PASS'
    }
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
        $cleanedReferenceText = [regex]::Replace(
            $cleanedReferenceText,
            '(?m)^.*\((?:<)?\.\./(?:__filelist\.txt|_transfer_test\.txt|chunk_\d+\.py)(?:>)?\).*\r?\n?',
            ''
        )
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

    $zipValidation = New-Utf8FileOnlyArchive -SourceDirectory $stage -DestinationPath $outputFull

    $zip = Get-Item -LiteralPath $outputFull
    $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $outputFull).Hash
    [PSCustomObject]@{
        OutputPath = $zip.FullName
        Files = (Get-ChildItem -LiteralPath $stage -Recurse -File).Count
        Bytes = $zip.Length
        SHA256 = $hash
        Target = $Target
        Frontmatter = $keys -join ','
        DirectoryEntries = $zipValidation.DirectoryEntries
        Utf8EntryNames = $zipValidation.Utf8EntryNames
        CleanExtractionSHA256 = $zipValidation.CleanExtractionSHA256
    }
}
finally {
    if (Test-Path -LiteralPath $stage) {
        Remove-Item -LiteralPath $stage -Recurse -Force
    }
}
