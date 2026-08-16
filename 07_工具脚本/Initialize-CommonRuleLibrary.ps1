param(
    [Parameter(Mandatory = $true)][string]$TemplateRoot,
    [Parameter(Mandatory = $true)][string]$ProjectRoot,
    [switch]$VerifyOnly
)

$ErrorActionPreference = 'Stop'
$templateFull = [IO.Path]::GetFullPath($TemplateRoot).TrimEnd('\')
$projectFull = [IO.Path]::GetFullPath($ProjectRoot).TrimEnd('\')

$mappings = @(
    [pscustomobject]@{
        Kind = 'Directory'
        Source = Join-Path $templateFull '01_通用规则库'
        Target = Join-Path $projectFull '01_规则库\00_通用规则'
        Layer = '通用规则'
    },
    [pscustomobject]@{
        Kind = 'Directory'
        Source = Join-Path $templateFull '02_语言与风格库'
        Target = Join-Path $projectFull '01_规则库\07_语言与风格'
        Layer = '语言与风格'
    },
    [pscustomobject]@{
        Kind = 'File'
        Source = Join-Path $templateFull '00_模板库入口\04_逐卷写作与验收细则.md'
        Target = Join-Path $projectFull '00_项目入口\11_逐卷章纲正文工作流与验收.md'
        Layer = '流程硬规则'
    },
    [pscustomobject]@{
        Kind = 'File'
        Source = Join-Path $templateFull '00_模板库入口\05_正文防复发审计清单.md'
        Target = Join-Path $projectFull '00_项目入口\17_正文防复发错误与机械人工审计清单.md'
        Layer = '流程硬规则'
    },
    [pscustomobject]@{
        Kind = 'File'
        Source = Join-Path $templateFull '00_模板库入口\06_逐句核验与改文失效规则.md'
        Target = Join-Path $projectFull '00_项目入口\19_逐句核验与卷终复核硬规则.md'
        Layer = '流程硬规则'
    },
    [pscustomobject]@{
        Kind = 'File'
        Source = Join-Path $templateFull '00_模板库入口\03_每卷严格生产流程.md'
        Target = Join-Path $projectFull '00_项目入口\20_全卷正文生产流程图与文档核验卡执行手册.md'
        Layer = '流程硬规则'
    }
)

foreach ($mapping in $mappings) {
    $expectedPathType = if ($mapping.Kind -eq 'Directory') { 'Container' } else { 'Leaf' }
    if (-not (Test-Path -LiteralPath $mapping.Source -PathType $expectedPathType)) {
        throw "Template source missing: $($mapping.Source)"
    }

    if ($VerifyOnly) { continue }

    if ($mapping.Kind -eq 'Directory') {
        $existing = @(Get-ChildItem -LiteralPath $mapping.Target -Recurse -File -ErrorAction SilentlyContinue)
        if ($existing.Count -gt 0) {
            throw "Target layer is not empty; refusing to overwrite: $($mapping.Target)"
        }
        New-Item -ItemType Directory -Force -Path $mapping.Target | Out-Null
        Get-ChildItem -LiteralPath $mapping.Source -Recurse -File | ForEach-Object {
            $relative = $_.FullName.Substring($mapping.Source.Length).TrimStart('\')
            $destination = Join-Path $mapping.Target $relative
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destination) | Out-Null
            Copy-Item -LiteralPath $_.FullName -Destination $destination
        }
    } else {
        if (Test-Path -LiteralPath $mapping.Target) {
            throw "Target file already exists; refusing to overwrite: $($mapping.Target)"
        }
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $mapping.Target) | Out-Null
        Copy-Item -LiteralPath $mapping.Source -Destination $mapping.Target
    }
}

$rows = New-Object System.Collections.Generic.List[object]
$errors = New-Object System.Collections.Generic.List[string]
foreach ($mapping in $mappings) {
    if ($mapping.Kind -eq 'Directory') {
        $sourceFiles = @(Get-ChildItem -LiteralPath $mapping.Source -Recurse -File | Sort-Object FullName)
        $targetFiles = @(Get-ChildItem -LiteralPath $mapping.Target -Recurse -File -ErrorAction SilentlyContinue | Sort-Object FullName)
        $sourceRelative = @($sourceFiles | ForEach-Object { $_.FullName.Substring($mapping.Source.Length).TrimStart('\') })

        foreach ($source in $sourceFiles) {
            $relative = $source.FullName.Substring($mapping.Source.Length).TrimStart('\')
            $target = Join-Path $mapping.Target $relative
            $sourceHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $source.FullName).Hash
            $targetHash = if (Test-Path -LiteralPath $target -PathType Leaf) {
                (Get-FileHash -Algorithm SHA256 -LiteralPath $target).Hash
            } else { '' }
            $status = if ($sourceHash -eq $targetHash) { '一致' } else { '缺失或不一致' }
            if ($status -ne '一致') { $errors.Add("$($mapping.Layer):$relative") }
            $rows.Add([pscustomobject]@{
                Layer = $mapping.Layer
                ProjectPath = $target.Substring($projectFull.Length).TrimStart('\')
                SourceSHA256 = $sourceHash
                TargetSHA256 = $targetHash
                Status = $status
            })
        }

        foreach ($target in $targetFiles) {
            $relative = $target.FullName.Substring($mapping.Target.Length).TrimStart('\')
            if ($relative -notin $sourceRelative) {
                $errors.Add("目标多出:$($mapping.Layer):$relative")
            }
        }
    } else {
        $sourceHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $mapping.Source).Hash
        $targetHash = if (Test-Path -LiteralPath $mapping.Target -PathType Leaf) {
            (Get-FileHash -Algorithm SHA256 -LiteralPath $mapping.Target).Hash
        } else { '' }
        $status = if ($sourceHash -eq $targetHash) { '一致' } else { '缺失或不一致' }
        if ($status -ne '一致') { $errors.Add("$($mapping.Layer):$($mapping.Target)") }
        $rows.Add([pscustomobject]@{
            Layer = $mapping.Layer
            ProjectPath = $mapping.Target.Substring($projectFull.Length).TrimStart('\')
            SourceSHA256 = $sourceHash
            TargetSHA256 = $targetHash
            Status = $status
        })
    }
}

$manifestDir = Join-Path $projectFull '00_项目入口'
New-Item -ItemType Directory -Force -Path $manifestDir | Out-Null
$manifestPath = Join-Path $manifestDir '通用规则迁移清单.tsv'
$rows | Export-Csv -Delimiter "`t" -NoTypeInformation -Encoding UTF8 -LiteralPath $manifestPath

if ($errors.Count -gt 0) {
    throw ("Common rule migration verification failed:`r`n" + ($errors -join "`r`n"))
}

[pscustomobject]@{
    Files = $rows.Count
    Manifest = $manifestPath
    Status = 'PASS'
}
