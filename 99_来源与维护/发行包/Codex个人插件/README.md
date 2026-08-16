# Codex个人插件发行包

本目录保存由通用模板库当前公开发行基线生成的Codex个人插件压缩包。插件内置`novel-writing-template`技能，但不包含任何具体小说正文、人物、世界观或作者裁决。

## 安装边界

- 发行文件：[ai-novel-workflow-codex-plugin.zip](ai-novel-workflow-codex-plugin.zip)
- 解压后，插件根目录必须直接包含`.codex-plugin/plugin.json`和`skills/novel-writing-template/SKILL.md`。
- `SKILL.md`只负责强制预检、阶段路由和完成闸门，不能替代模板库唯一入口、规则全文、项目现状或人工语义验收。
- 正式完成必须有当前对象的真实文件、逐项核验结果和可复查证据；快速草稿不得伪装成正式完成。

## 文件关联

- 上游依据：[模板库唯一入口](../../../00_模板库入口/README_唯一入口.md)、[AI与Codex技能执行入口](../../../SKILL.md)、[工具边界与用法](../../../07_工具脚本/README_工具边界与用法.md)。
- 同层互证：[扣子Skill发行包](../扣子Skill/README.md)、[来源与维护](../../README_来源与维护.md)。
- 生成工具：[Build-NovelWritingSkillPackage.ps1](../../../07_工具脚本/Build-NovelWritingSkillPackage.ps1)与Codex插件官方结构校验流程。
- 变更回写：插件结构、技能规则或发行文件变化时，同步更新资产登记、来源去向、SHA清单、Obsidian导航和验收报告。
