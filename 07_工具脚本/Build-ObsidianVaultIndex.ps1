param(
    [Parameter(Mandatory = $true)][string]$VaultRoot,
    [string]$IndexRelativePath = '00_Obsidian导航\01_全库文件直链索引.md',
    [string]$NodeDirectoryRelativePath = '00_Obsidian导航\文件夹节点',
    [string]$EntryRelativePath = 'OBSIDIAN_库入口.md'
)

$ErrorActionPreference = 'Stop'
$vaultFull = [IO.Path]::GetFullPath($VaultRoot).TrimEnd('\')
if (-not (Test-Path -LiteralPath $vaultFull -PathType Container)) {
    throw "Vault root not found: $vaultFull"
}

$indexFull = [IO.Path]::GetFullPath((Join-Path $vaultFull $IndexRelativePath))
$indexDirectory = Split-Path -Parent $indexFull
$nodeDirectory = [IO.Path]::GetFullPath((Join-Path $vaultFull $NodeDirectoryRelativePath))
$entryFull = [IO.Path]::GetFullPath((Join-Path $vaultFull $EntryRelativePath))
$entryDirectory = Split-Path -Parent $entryFull
foreach ($target in @($indexFull, $nodeDirectory, $entryFull)) {
    if (-not $target.StartsWith($vaultFull + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw "Generated target must stay inside vault: $target"
    }
}

New-Item -ItemType Directory -Force -Path $indexDirectory, $nodeDirectory | Out-Null

# 只清理本工具在固定目录内生成的目录节点，不碰用户文件。
Get-ChildItem -LiteralPath $nodeDirectory -File -Filter '目录__*.md' -ErrorAction SilentlyContinue |
    ForEach-Object { Remove-Item -LiteralPath $_.FullName -Force }

$excludedDirectoryNames = @('.obsidian', '.git', '.trash')
function Test-IsExcludedPath {
    param([Parameter(Mandatory = $true)][string]$FullPath)
    $relative = $FullPath.Substring($vaultFull.Length).TrimStart('\')
    $segments = @($relative -split '\\')
    if ($segments | Where-Object { $_ -in $excludedDirectoryNames }) { return $true }
    if ($FullPath.StartsWith($nodeDirectory + '\', [StringComparison]::OrdinalIgnoreCase) -or
        $FullPath.Equals($nodeDirectory, [StringComparison]::OrdinalIgnoreCase)) { return $true }
    return $false
}

function Get-ShortHash {
    param([Parameter(Mandatory = $true)][string]$Text)
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [Text.Encoding]::UTF8.GetBytes($Text)
        return ([BitConverter]::ToString($sha.ComputeHash($bytes)).Replace('-', '').Substring(0, 12)).ToLowerInvariant()
    } finally {
        $sha.Dispose()
    }
}

$directories = @(Get-ChildItem -LiteralPath $vaultFull -Recurse -Directory -Force |
    Where-Object { -not (Test-IsExcludedPath -FullPath $_.FullName) } |
    Sort-Object FullName)
$files = @(Get-ChildItem -LiteralPath $vaultFull -Recurse -File -Force |
    Where-Object { -not (Test-IsExcludedPath -FullPath $_.FullName) } |
    Sort-Object FullName)

$nodeByDirectory = @{}
$usedNames = @{}
foreach ($directory in $directories) {
    $relative = $directory.FullName.Substring($vaultFull.Length).TrimStart('\')
    $base = '目录__' + ($relative -replace '\\', '__')
    $base = $base -replace '[<>:"/\\|?*]', '_'
    $base = $base.TrimEnd('.', ' ')
    if ($base.Length -gt 150) {
        $base = $base.Substring(0, 132).TrimEnd('.', ' ') + '__' + (Get-ShortHash -Text $relative)
    }
    $candidate = $base + '.md'
    if ($usedNames.ContainsKey($candidate.ToLowerInvariant())) {
        $candidate = $base + '__' + (Get-ShortHash -Text $relative) + '.md'
    }
    $usedNames[$candidate.ToLowerInvariant()] = $true
    $nodeByDirectory[$directory.FullName.ToLowerInvariant()] = Join-Path $nodeDirectory $candidate
}

foreach ($directory in $directories) {
    $relative = $directory.FullName.Substring($vaultFull.Length).TrimStart('\')
    $nodeFull = $nodeByDirectory[$directory.FullName.ToLowerInvariant()]
    $builder = [Text.StringBuilder]::new()
    [void]$builder.AppendLine("# 📁 $relative")
    [void]$builder.AppendLine()
    [void]$builder.AppendLine('- 节点类型：物理文件夹映射')
    [void]$builder.AppendLine("- 实际目录：``$relative``")
    [void]$builder.AppendLine()

    $parent = $directory.Parent
    if ($null -ne $parent -and $parent.FullName.StartsWith($vaultFull + '\', [StringComparison]::OrdinalIgnoreCase)) {
        $parentNode = $nodeByDirectory[$parent.FullName.ToLowerInvariant()]
        $parentTarget = [IO.Path]::GetRelativePath($nodeDirectory, $parentNode).Replace('\', '/')
        [void]$builder.AppendLine("- 上级文件夹：[$($parent.Name)](<$parentTarget>)")
    } else {
        $rootTarget = [IO.Path]::GetRelativePath($nodeDirectory, $indexFull).Replace('\', '/')
        if (Test-Path -LiteralPath $entryFull -PathType Leaf) {
            $entryTarget = [IO.Path]::GetRelativePath($nodeDirectory, $entryFull).Replace('\', '/')
            [void]$builder.AppendLine("- 库入口：[OBSIDIAN_库入口](<$entryTarget>)")
        }
        [void]$builder.AppendLine("- 上级：[全库目录树入口](<$rootTarget>)")
    }

    $children = @($directories | Where-Object { $_.Parent.FullName -eq $directory.FullName })
    if ($children.Count -gt 0) {
        [void]$builder.AppendLine()
        [void]$builder.AppendLine('## 子文件夹')
        [void]$builder.AppendLine()
        foreach ($child in $children) {
            $childNode = $nodeByDirectory[$child.FullName.ToLowerInvariant()]
            $target = [IO.Path]::GetRelativePath($nodeDirectory, $childNode).Replace('\', '/')
            [void]$builder.AppendLine("- 📁 [$($child.Name)](<$target>)")
        }
    }

    $directFiles = @($files | Where-Object { $_.DirectoryName -eq $directory.FullName })
    if ($directFiles.Count -gt 0) {
        [void]$builder.AppendLine()
        [void]$builder.AppendLine('## 本文件夹文档')
        [void]$builder.AppendLine()
        foreach ($file in $directFiles) {
            $target = [IO.Path]::GetRelativePath($nodeDirectory, $file.FullName).Replace('\', '/')
            [void]$builder.AppendLine("- [$($file.Name)](<$target>)")
        }
    }

    [IO.File]::WriteAllText($nodeFull, $builder.ToString().TrimEnd() + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
}

$topDirectories = @($directories | Where-Object { $_.Parent.FullName -eq $vaultFull })
$rootBuilder = [Text.StringBuilder]::new()
[void]$rootBuilder.AppendLine('# 全库目录树与文件直链入口')
[void]$rootBuilder.AppendLine()
[void]$rootBuilder.AppendLine("- 库根目录：``$vaultFull``")
[void]$rootBuilder.AppendLine("- 生成时间：$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
[void]$rootBuilder.AppendLine("- 物理文件夹节点：$($directories.Count)")
[void]$rootBuilder.AppendLine("- 被目录节点直接链接的普通文件：$($files.Count)")
[void]$rootBuilder.AppendLine('- 排除范围：`.obsidian`、`.git`、`.trash`及本工具生成的文件夹节点目录。')
[void]$rootBuilder.AppendLine('- 关系图结构：库入口同时直连目录树总入口与各顶层文件夹；顶层文件夹再连接子文件夹及本层文档。')
[void]$rootBuilder.AppendLine()
[void]$rootBuilder.AppendLine('## 顶层文件夹')
[void]$rootBuilder.AppendLine()
foreach ($directory in $topDirectories) {
    $nodeFull = $nodeByDirectory[$directory.FullName.ToLowerInvariant()]
    $target = [IO.Path]::GetRelativePath($indexDirectory, $nodeFull).Replace('\', '/')
    [void]$rootBuilder.AppendLine("- 📁 [$($directory.Name)](<$target>)")
}

$rootFiles = @($files | Where-Object { $_.DirectoryName -eq $vaultFull })
if ($rootFiles.Count -gt 0) {
    [void]$rootBuilder.AppendLine()
    [void]$rootBuilder.AppendLine('## 根目录文档')
    [void]$rootBuilder.AppendLine()
    foreach ($file in $rootFiles) {
        $target = [IO.Path]::GetRelativePath($indexDirectory, $file.FullName).Replace('\', '/')
        [void]$rootBuilder.AppendLine("- [$($file.Name)](<$target>)")
    }
}

[void]$rootBuilder.AppendLine()
[void]$rootBuilder.AppendLine('## 普通文件类型统计')
[void]$rootBuilder.AppendLine()
[void]$rootBuilder.AppendLine('| 类型 | 数量 |')
[void]$rootBuilder.AppendLine('|---|---:|')
foreach ($group in ($files | Group-Object { if ([string]::IsNullOrWhiteSpace($_.Extension)) { '[无扩展名]' } else { $_.Extension.ToLowerInvariant() } } | Sort-Object Name)) {
    [void]$rootBuilder.AppendLine("| ``$($group.Name)`` | $($group.Count) |")
}

[IO.File]::WriteAllText($indexFull, $rootBuilder.ToString().TrimEnd() + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))

# 在库入口中维护一段可重复生成的顶层文件夹直链，使关系图明确显示“入口→文件夹”。
$entryLinked = $false
if (Test-Path -LiteralPath $entryFull -PathType Leaf) {
    $beginMarker = '<!-- BEGIN AUTO-GENERATED FOLDER LINKS -->'
    $endMarker = '<!-- END AUTO-GENERATED FOLDER LINKS -->'
    $entryBlockBuilder = [Text.StringBuilder]::new()
    [void]$entryBlockBuilder.AppendLine($beginMarker)
    [void]$entryBlockBuilder.AppendLine('## 顶层文件夹图谱入口')
    [void]$entryBlockBuilder.AppendLine()
    [void]$entryBlockBuilder.AppendLine('以下链接由目录树工具维护，用于在关系图中明确显示“库入口 → 顶层文件夹”。')
    [void]$entryBlockBuilder.AppendLine()
    foreach ($directory in $topDirectories) {
        $nodeFull = $nodeByDirectory[$directory.FullName.ToLowerInvariant()]
        $target = [IO.Path]::GetRelativePath($entryDirectory, $nodeFull).Replace('\', '/')
        [void]$entryBlockBuilder.AppendLine("- 📁 [$($directory.Name)](<$target>)")
    }
    [void]$entryBlockBuilder.AppendLine($endMarker)
    $entryBlock = $entryBlockBuilder.ToString().TrimEnd()
    $entryText = [IO.File]::ReadAllText($entryFull, [Text.Encoding]::UTF8)
    $markerPattern = '(?s)<!-- BEGIN AUTO-GENERATED FOLDER LINKS -->.*?<!-- END AUTO-GENERATED FOLDER LINKS -->'
    if ([regex]::IsMatch($entryText, $markerPattern)) {
        $entryText = [regex]::Replace(
            $entryText,
            $markerPattern,
            [Text.RegularExpressions.MatchEvaluator]{ param($match) $entryBlock }
        )
    } else {
        $entryText = $entryText.TrimEnd() + [Environment]::NewLine + [Environment]::NewLine + $entryBlock
    }
    [IO.File]::WriteAllText($entryFull, $entryText.TrimEnd() + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
    $entryLinked = $true
}

[pscustomobject]@{
    VaultRoot = $vaultFull
    IndexPath = $indexFull
    FolderNodes = $directories.Count
    LinkedFiles = $files.Count
    EntryLinkedToTopFolders = $entryLinked
    IndexSHA256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $indexFull).Hash
}
