# 扣子Skill发行包

本目录保存由通用模板库当前公开发行基线生成的扣子可导入Skill压缩包。它与Codex插件分开生成，避免两端frontmatter和目录规范相互污染。

当前模板规则版本：`v1.4`。

## 使用边界

- 发行文件：[novel-writing-template-coze.zip](novel-writing-template-coze.zip)
- ZIP根目录直接包含`SKILL.md`与`references/`；`SKILL.md`的frontmatter包含`name`、`description`和`required_skills`。
- 扣子修改稿中的有效“防偷步”思路已核验并吸收；AIGC展示字段、固定三千字门槛、互相矛盾的分身规则和具体项目编号未写入通用规则。
- 正式完成必须有当前对象的真实文件、逐项核验结果和可复查证据；批量扫描、旧卡复用或摘要结论不能代替逐章逐行语义核验。
- 写前、写中、写后、每五W、C正式章和卷终均有固定必需文件矩阵；缺文件、错目录、空内容、待核、SHA或关联不一致时禁止验收。

## 文件关联

- 上游依据：[模板库唯一入口](../../../00_模板库入口/README_唯一入口.md)、[AI与Codex技能执行入口](../../../SKILL.md)、[工具边界与用法](../../../07_工具脚本/README_工具边界与用法.md)。
- 同层互证：[Codex个人插件发行包](../Codex个人插件/README.md)、[来源与维护](../../README_来源与维护.md)。
- 生成工具：[Build-NovelWritingSkillPackage.ps1](../../../07_工具脚本/Build-NovelWritingSkillPackage.ps1)。
- 变更回写：技能规则、引用文件或发行文件变化时，同步更新资产登记、来源去向、SHA清单、Obsidian导航和验收报告。
