# Notepad for macOS

[![macOS 11+](https://img.shields.io/badge/macOS-11%2B-000000)](https://github.com/limin640/notepad-mac/releases)
[![arm64](https://img.shields.io/badge/arch-arm64-0aa)](https://github.com/limin640/notepad-mac/releases)
[![~4 MB](https://img.shields.io/badge/size-~4%20MB-2ea44f)](https://github.com/limin640/notepad-mac/releases)
[![license](https://img.shields.io/badge/license-PolyForm%20NC-orange)](LICENSE)

[English](README.md) | **简体中文** | [繁體中文](README.zh-Hant.md) | [日本語](README.ja.md) | [한국어](README.ko.md) | [Deutsch](README.de.md) | [Français](README.fr.md) | [Español](README.es.md) | [Italiano](README.it.md) | [Português](README.pt-BR.md) | [Русский](README.ru.md)

> Mac 原生文本编辑器。Windows [Notepad4](https://github.com/zufuliu/notepad4) 的移植。约 4 MB。不是 Wine，不是 Electron，不是 IDE。

**4 MB。原生。开箱即写。**

![Notepad](docs/screenshot.png)

系统文本编辑太素，VS Code 开机先喝内存，Wine 封装的 Notepad4 大约 **1 GB**。这边是同一套手感——Scintilla、90 种词法器、原版配色——做成真正的 Mac 应用。

| | Notepad | Wine 封装 | VS Code | 文本编辑 |
|---|---|---|---|---|
| 体积 | ~4 MB | ~1 GB | 几百 MB | 系统自带 |
| 打开 | 秒开 | 慢 | 慢 | 秒开 |
| 语法着色 | 90 种，原版配色 | 有 | 有 | 无 |
| 原生 AppKit | 是 | 否 | Electron | 是 |
| 干什么 | 打开、改、存、走人 | 同样的活，体积巨大 | IDE | 随手记 |

Dock 里叫 **Notepad**。仓库名是 `notepad-mac`。

## 事实

| | |
|---|---|
| 应用名 | Notepad |
| 仓库 | [limin640/notepad-mac](https://github.com/limin640/notepad-mac) |
| 上游 | [zufuliu/notepad4](https://github.com/zufuliu/notepad4)（Windows） |
| 技术 | Scintilla 5.6.6 + 官方 Cocoa + AppKit |
| 系统 | macOS 11+，Apple 芯片。Intel 请自行编译 |
| 签名 | 仅 ad-hoc，无公证 |
| 许可 | 移植：PolyForm Noncommercial。上游：BSD-3 / Scintilla / Boost |
| 给模型看的索引 | [llms.txt](llms.txt) |

## 下载

[**Notepad-0.1.21.dmg**](https://github.com/limin640/notepad-mac/releases/latest) → 把 **Notepad** 拖进「应用程序」。

没有公证。网上第一次打开：**按住 Control 点图标 → 打开**，或 `xattr -cr /Applications/Notepad.app`。不要双击 DMG 里面的图标，请拖走。

## 有什么

- 90 个词法器，词表和颜色从 Notepad4 搬来，不是「大概像」
- GB18030 / GBK / BIG5 / Shift-JIS 探测，中文 Windows 文本不会一打开就乱码
- 正则查找替换；补全、书签、折叠、行操作
- Markdown / HTML / 图片预览
- 跟随系统明暗和语言（11 种界面语言）
- 菜单、工具栏位图、状态栏 `Ln / Col / Ch / Sel` 对照 Windows `Notepad4.rc`

没有调试器、没有 Git 面板、没有 AI 侧栏。

## 编译

```bash
./build.sh
open build/Notepad.app
```

Xcode（clang C++20），CMake ≥ 3.20。默认 arm64。打 DMG：`./scripts/package.sh`（不要推进 git）。

```
scintilla_upstream/   Scintilla 5.6.6（Notepad4 fork）+ 官方 Cocoa
lexers_def/           原版 90 语言词表和样式
macapp/               AppKit 壳
tests/sci_test.mm     内核冒烟
```

## 许可

详见 [LICENSE](LICENSE)。

- **本移植**（`macapp/`、脚本）：[PolyForm Noncommercial 1.0.0](https://polyformproject.org/licenses/noncommercial/1.0.0)，个人自用免费，商业需授权
- **Notepad4 词法器 / 图标：** BSD 3-Clause
- **Scintilla：** 历史许可（Neil Hodgson）
- **Boost.Regex 头文件：** BSL-1.0

商业授权：<https://github.com/limin640/notepad-mac/issues>

## 打赏

Help → 打赏，或微信：

![微信打赏](docs/donate/wechat.png)
