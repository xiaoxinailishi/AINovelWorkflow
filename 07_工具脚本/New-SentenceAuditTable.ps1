param(
    [Parameter(Mandatory = $true)][string]$SourcePath,
    [Parameter(Mandatory = $true)][string]$OutputPath,
    [Parameter(Mandatory = $true)][ValidatePattern('^[WC]\d{3}$')][string]$Prefix,
    [ValidateSet('工作单元', '正式章')][string]$Stage = '工作单元',
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$source = [System.IO.Path]::GetFullPath($SourcePath)
$output = [System.IO.Path]::GetFullPath($OutputPath)

if (-not [System.IO.File]::Exists($source)) {
    throw "正文不存在：$source"
}
if ([System.IO.File]::Exists($output) -and -not $Force) {
    throw "核验表已存在，拒绝覆盖：$output"
}

$lines = [System.IO.File]::ReadAllLines($source, [System.Text.Encoding]::UTF8)
$sha = (Get-FileHash -Algorithm SHA256 -LiteralPath $source).Hash
$title = ''
$items = New-Object System.Collections.Generic.List[object]
$closeChars = ([char]0x201D).ToString() + ([char]0x2019).ToString() + ([char]0x300D).ToString() + ([char]0x300F).ToString() + ([char]0xFF09).ToString() + ([char]0x3011).ToString() + ([char]0x300B).ToString()
$sentencePattern = '.+?(?:[。！？?!]+[' + [regex]::Escape($closeChars) + ']?|$)'

for ($i = 0; $i -lt $lines.Length; $i++) {
    $line = $lines[$i]
    $trimmed = $line.Trim()
    if ([string]::IsNullOrWhiteSpace($trimmed)) { continue }
    if ($trimmed -match '^#\s+(.+)$' -and [string]::IsNullOrWhiteSpace($title)) {
        $title = $Matches[1].Trim()
        continue
    }
    if ($trimmed -match '^#{1,6}\s+' -or $trimmed -match '^---+$') { continue }

    $matches = [regex]::Matches($trimmed, $sentencePattern)
    foreach ($match in $matches) {
        $text = $match.Value.Trim()
        if ([string]::IsNullOrWhiteSpace($text)) { continue }
        $items.Add([pscustomobject]@{ Line = $i + 1; Text = $text })
    }
}

if ([string]::IsNullOrWhiteSpace($title)) {
    $title = [System.IO.Path]::GetFileNameWithoutExtension($source)
}

function Escape-MarkdownCell([string]$value) {
    return $value.Replace('\\', '\\').Replace('|', '\|').Replace("`r", '').Replace("`n", '<br>')
}

$now = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
$rows = New-Object System.Collections.Generic.List[string]
for ($index = 0; $index -lt $items.Count; $index++) {
    $id = '{0}-S{1:D4}' -f $Prefix, ($index + 1)
    $text = Escape-MarkdownCell $items[$index].Text
    $rows.Add("| $id | $($items[$index].Line) | $text | 待填 | 待填 | 待填 | 待核 | 待填 | 待填 |")
}

$doc = New-Object System.Collections.Generic.List[string]
$doc.Add("# $title 逐句核验表")
$doc.Add('')
$doc.Add("- 阶段：$Stage 成稿后独立核验")
$doc.Add("- 正文路径：``$source``")
$doc.Add("- 清单生成时间：$now")
$doc.Add("- 清单生成时SHA256：``$sha``")
$doc.Add('- 当前最终SHA256：待核')
$doc.Add("- 候选正文句数：$($items.Count)")
$doc.Add('- 总状态：待核')
$doc.Add('- 说明：本表由工具机械生成句号、源行、原文和哈希；类型、人物、触发码、人工判断、问题与修改记录必须由主写窗口逐句填写，工具不得自动判定内容通过。')
$doc.Add('')
$doc.Add('## 一、场景关系与称谓前置表')
$doc.Add('')
$doc.Add('| 场景ID | 说话者 | 话语对象／所指人物 | 亲属关系 | 公私场合 | 临时职务身份 | 允许称谓 | 禁止机械称谓 |')
$doc.Add('|---|---|---|---|---|---|---|---|')
$doc.Add('| SC01 | 待填 | 待填 | 待填 | 待填 | 待填 | 待填 | 待填 |')
$doc.Add('')
$doc.Add('## 二、标题核验')
$doc.Add('')
$doc.Add('| 编号 | 当前标题 | 内容承诺 | 是否剧透／空泛／内部冷词 | 人工判断 | 问题／修改记录 |')
$doc.Add('|---|---|---|---|---|---|')
$doc.Add("| $Prefix-TITLE | $(Escape-MarkdownCell $title) | 待填 | 待填 | 待核 | 待填 |")
$doc.Add('')
$doc.Add('## 三、逐句核验')
$doc.Add('')
$doc.Add('| 句号 | 源行 | 原文摘要 | 类型 | 人物／对象 | 触发码 | 人工判断 | 发现的问题 | 修改记录 |')
$doc.Add('|---|---:|---|---|---|---|---|---|---|')
foreach ($row in $rows) { $doc.Add($row) }
$doc.Add('')
$doc.Add('## 四、四轮复读证据')
$doc.Add('')
$doc.Add('- 老书虫复读发现与修复：旧记录已有，须在逐句核验完成后链接或摘要。')
$doc.Add('- 小白读者复读发现与修复：旧记录已有，须在逐句核验完成后链接或摘要。')
$doc.Add('- 规则逐句核验发现与修复：待核。')
$doc.Add('- 修改后从标题到末字全文复读：待核。')
$doc.Add('')
$doc.Add('## 五、完整性闸门')
$doc.Add('')
$doc.Add('| 检查项 | 结果 | 证据 |')
$doc.Add('|---|---|---|')
$doc.Add("| 候选句数＝表格行数＝唯一句号数 | 待核 | 候选$($items.Count)句 |")
$doc.Add('| 无待核／待填／需改／阻断 | 未通过 | 当前为初始待核表 |')
$doc.Add('| 当前正文SHA＝表内最终SHA | 待核 |  |')
$doc.Add('| 实际改文均链接具名修改记录 | 待核 |  |')
$doc.Add('| 章后状态／台账已回写 | 待核 |  |')
$doc.Add('')
$doc.Add('- 机械结构检查：未执行')
$doc.Add('- 人工内容结论：待核')
$doc.Add('- 是否允许仅凭本表生成下一工作单元：否')

$parent = [System.IO.Path]::GetDirectoryName($output)
if (-not [System.IO.Directory]::Exists($parent)) {
    [System.IO.Directory]::CreateDirectory($parent) | Out-Null
}
[System.IO.File]::WriteAllLines($output, $doc, $utf8NoBom)
Write-Output "created=$output"
Write-Output "sentences=$($items.Count)"
Write-Output "sha256=$sha"
