# Notepad Mac

[English](README.md) | **简体中文** | [繁體中文](README.zh-Hant.md) | [日本語](README.ja.md) | [한국어](README.ko.md) | [Deutsch](README.de.md) | [Français](README.fr.md) | [Español](README.es.md) | [Italiano](README.it.md) | [Português](README.pt-BR.md) | [Русский](README.ru.md)

**4 MB。原生。开箱即写。**

Mac 上的原生记事本：Scintilla 内核 + 官方 Cocoa 后端 + AppKit 壳。不是 Wine，不是 Electron。大约 **4 MB**。

内核来自 Windows [Notepad4](https://github.com/zufuliu/notepad4)——词法器、配色、手感都还在——名字改成大家会搜的 **Notepad Mac**。

Wine 封装大约 1 GB。这边大约 **4 MB**。差两个数量级。

个人自用免费；本移植的商业使用需授权。上游 Notepad4 / Scintilla / Boost 仍按原许可。详见 [LICENSE](LICENSE)。

## 凭什么用它

- **秒开。** 双击就是编辑器，没有欢迎页、没有扩展市场、没有语言服务器先热身。日志、配置、脚本、随手记，打开即写。
- **真·原生。** 菜单、窗口、暗色模式跟系统走。GB18030 / GBK / BIG5 / Shift-JIS 按文件探测，中文 Windows 扔过来的文本不会一打开就乱码。
- **90 种语法着色，配色跟 Windows 原版同一套。** C、Python、Go、Rust、JSON、Markdown……词表和颜色不是「大概像」，是从 Notepad4 源码搬过来的。
- **界面按原版逐项复刻。** 工具栏位图、状态栏 `Ln / Col / Ch / Sel`、折叠栏、当前行框，Windows 上手的人不用重新学。
- **该预览时预览。** Markdown、HTML、图片直接在窗口右侧渲染，不用另开浏览器。
- **11 种界面语言，跟随系统。** 简体中文、繁體中文、English、日本語、한국어、Deutsch、Français、Español、Italiano、Português、Русский。

不做什么也说清楚：它不是 IDE，没有调试器、没有 Git 面板、没有 AI 侧栏。那是 VS Code 的活。这个软件的活是——**打开文件、改几个字、存盘、走人。**

## 下载

从 [Releases](https://github.com/limin640/notepad-mac/releases) 下 DMG，把 **Notepad Mac** 拖进「应用程序」。Apple 芯片（M1 及更新），macOS 11+。

没有 Apple 公证。网上第一次打开会提示「无法验证开发者」，**不是病毒**。任选一次即可：

1. **按住 Control 点图标**（或右键）→ 打开 → 再点打开
2. 系统设置 → 隐私与安全性 → 「仍要打开」
3. 终端：`xattr -cr "/Applications/Notepad Mac.app"`

以后双击就能开。Intel Mac 请从源码编译。

## 打赏

要是这个移植确实让你少开一次 1 GB 的 Wine，或者少等一次 VS Code 启动——微信扫一下。软件里也可以：**Help → 打赏**。

![微信打赏](docs/donate/wechat.png)

## 现在有什么

| | |
|---|---|
| 语法着色 | 90 个词法器，原版词表 + 配色 |
| 主题 | 跟随系统 / 浅色 / 深色，工具栏和状态栏一起变 |
| 编码 | BOM、UTF-8、GB18030 探测；UTF-16、GBK、BIG5、Shift-JIS 重载与保存 |
| 查找替换 | 正则、大小写、全字；单个 / 全部 |
| 编辑 | 补全、书签、折叠、行操作、大小写、包围、排序、编码转换 |
| 预览 | Markdown、HTML、png/jpg/webp/heic 等图片 |
| 界面语言 | 跟随系统；可强制 English / 简体中文 / 繁體中文 / 日本語 / 한국어 / Deutsch / Français / Español / Italiano / Português / Русский |

菜单、工具栏、状态栏对照 Windows 版 `Notepad4.rc` 原文落地，不是「能用就行」的简化壳。

## 自己编译

```bash
./build.sh
open "build/Notepad Mac.app"
```

macOS 11+，Xcode（clang C++20），CMake ≥ 3.20。默认 arm64。

打 DMG（放到 GitHub Releases，不要推进 git）：

```bash
./scripts/package.sh
```

## 架构

```
scintilla_upstream/   Scintilla 5.6.6（notepad4 fork）+ 官方 Cocoa 后端
lexers_def/           原版 90 语言词表和样式（纯数据）
macapp/               AppKit 壳：窗口、菜单、工具栏、状态栏、查找、预览
tests/sci_test.mm     内核冒烟
```

Windows 上的 SRWLock / 线程池 / 编码 API，在这边换成标准库和 CFString；并行布局关掉了——Quartz surface 不是线程安全的。编辑器该快的地方仍然快。

## 许可

详见 [LICENSE](LICENSE)。

- **本移植原创代码**（`macapp/` 源码、构建脚本等）：[PolyForm Noncommercial 1.0.0](https://polyformproject.org/licenses/noncommercial/1.0.0)。个人自用可以，商业使用需授权。
- **Notepad4 词法器 / 图标等**：BSD 3-Clause（Zufu Liu / Florian Balmer 等）。
- **Scintilla**：历史许可（Neil Hodgson）。
- **Boost.Regex 头文件**：Boost Software License 1.0。

商业授权：<https://github.com/limin640/notepad-mac/issues>
