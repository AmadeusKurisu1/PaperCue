# PaperCue

PaperCue 是一个面向论文阅读和复习的 iOS 应用。它可以导入 PDF、网页或粘贴文本，提取正文后生成摘要、术语表、Anki 卡片和复习问题，帮助把长篇学术材料整理成可回顾的学习包。

![PaperCue app icon](PaperCue/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png)

## 功能

- 导入 PDF、网页链接或纯文本。
- 使用 PDFKit 和 Vision 提取 PDF 文本，支持对扫描页进行 OCR。
- 识别 DOI、arXiv、PubMed 等常见论文输入形式并规范化链接。
- 生成结构化学习材料：摘要、术语表、Anki 卡片、复习问题。
- 支持精读、复习、讨论、Anki 等生成侧重点。
- 可选择只生成部分模块，并添加自定义生成要求。
- 支持编辑生成结果，并导出为 Markdown、JSON、CSV 或 Anki TSV。
- 使用 SwiftData 本地保存文档和学习包。
- API key 存储在系统 Keychain 中。

## LLM 支持

PaperCue 使用 OpenAI-compatible 接口生成学习材料。内置提供方包括：

- OpenAI
- DeepSeek
- Kimi / Moonshot
- 阿里云百炼 DashScope
- 硅基流动 SiliconFlow
- 智谱 BigModel
- Google Gemini
- 自定义 OpenAI-compatible 服务

首次使用前，请在应用的设置页选择提供方、模型，并填写对应 API key。

## 运行环境

- Xcode
- iOS SDK
- SwiftUI
- SwiftData
- PDFKit
- Vision

当前项目目标平台为 iPhone 和 iPad。

## 快速开始

1. 克隆仓库：

   ```bash
   git clone git@github.com:AmadeusKurisu1/PaperCue.git
   cd PaperCue
   ```

2. 使用 Xcode 打开项目：

   ```bash
   open PaperCue.xcodeproj
   ```

3. 选择 `PaperCue` scheme。

4. 选择模拟器或真机运行。

5. 在应用设置中配置 LLM 提供方和 API key。

## 使用流程

1. 在文档库中导入 PDF、网页或文本。
2. 打开文档详情页，确认提取出的正文预览。
3. 选择生成配置和需要的模块。
4. 点击生成，等待学习包创建完成。
5. 按需要编辑内容，或导出到 Anki、Markdown、JSON、CSV。

## 测试

项目包含单元测试和 UI 测试：

```bash
xcodebuild test -project PaperCue.xcodeproj -scheme PaperCue -destination 'platform=iOS Simulator,name=iPhone 16'
```

如果本机没有对应模拟器，请在 Xcode 中选择可用设备，或调整 `-destination` 参数。

## 仓库结构

```text
PaperCue/
  PaperCue/             App 源码和资源
  PaperCueTests/        单元测试
  PaperCueUITests/      UI 测试
  PaperCue.xcodeproj/   Xcode 项目
```

## 说明

生成内容只基于导入文本。遇到论文中的事实、数据或引用时，仍建议回到原文核对。
