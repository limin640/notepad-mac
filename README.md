# Notepad for macOS

**English** | [简体中文](README.zh-CN.md) | [繁體中文](README.zh-Hant.md) | [日本語](README.ja.md) | [한국어](README.ko.md) | [Deutsch](README.de.md) | [Français](README.fr.md) | [Español](README.es.md) | [Italiano](README.it.md) | [Português](README.pt-BR.md) | [Русский](README.ru.md)

**4 MB. Native. Open a file and type.**

A native Mac notepad: Scintilla core, official Cocoa backend, AppKit shell. Not Wine. Not Electron. About **4 MB**.

It is a port of Windows [Notepad4](https://github.com/zufuliu/notepad4) — same lexers, same colors, same muscle memory. The app is called **Notepad**.

A Wine bundle is about 1 GB. This app is about **4 MB**. Two orders of magnitude.

Personal and non-commercial use is free. Commercial use of this Mac port needs a license. Upstream Notepad4 / Scintilla / Boost keep their original licenses. See [LICENSE](LICENSE).

## Why this

- **Instant.** Double-click, you are in the editor. No welcome page, no marketplace, no language server warming up. Logs, configs, scripts, notes — open and type.
- **Native.** Menus, windows, and dark mode follow macOS. GB18030 / GBK / BIG5 / Shift-JIS are detected from the file. Text from Chinese Windows does not open as mojibake.
- **90 lexers, same colors as the Windows original.** C, Python, Go, Rust, JSON, Markdown… the word lists and styles were copied from Notepad4, not approximated.
- **UI rebuilt item by item.** Toolbar bitmaps, status bar `Ln / Col / Ch / Sel`, fold margin, current-line frame. If you already know Notepad4, you already know this.
- **Preview when you need it.** Markdown, HTML, and images render in the right pane. No extra browser.
- **UI in 11 languages, following the system.** English, 简体中文, 繁體中文, 日本語, 한국어, Deutsch, Français, Español, Italiano, Português, Русский.

What it is not: not an IDE. No debugger, no Git pane, no AI sidebar. That is VS Code’s job. This app’s job is **open, edit, save, leave.**

## Download

Get the DMG from [Releases](https://github.com/limin640/notepad-mac/releases) and drop **Notepad** on Applications. Apple silicon (M1 and later), macOS 11+.

The build is not notarized. The first launch from the internet will say the developer cannot be verified. **That is Gatekeeper, not malware.** Do one of these once:

1. **Control-click** (or right-click) the icon → Open → Open
2. System Settings → Privacy & Security → Open Anyway
3. Terminal: `xattr -cr /Applications/Notepad.app`

After that, double-click works. Intel Macs: build from source.

## Donate

If this port saved you a 1 GB Wine install or a VS Code cold start, Help → Donate, or scan the WeChat Pay code:

![Donate](docs/donate/wechat.png)

## What’s in

| | |
|---|---|
| Syntax | 90 lexers, original word lists and colors |
| Theme | Follow system / light / dark — toolbar and status bar included |
| Encoding | BOM, UTF-8, GB18030 detect; UTF-16, GBK, BIG5, Shift-JIS reload and save |
| Find / replace | Regex, case, whole word; one or all |
| Edit | Completion, bookmarks, folding, line ops, case, enclose, sort, conversions |
| Preview | Markdown, HTML, png/jpg/webp/heic and similar |
| UI language | Follow system, or lock English, 简体中文, 繁體中文, 日本語, 한국어, Deutsch, Français, Español, Italiano, Português, Русский |

Menus, toolbar, and status bar follow the Windows `Notepad4.rc` text. This is not a thin “good enough” shell.

## Build

```bash
./build.sh
open build/Notepad.app
```

macOS 11+, Xcode (clang C++20), CMake ≥ 3.20. Default arch is arm64.

DMG for GitHub Releases (do not commit it):

```bash
./scripts/package.sh
```

## Layout

```
scintilla_upstream/   Scintilla 5.6.6 (Notepad4 fork) + official Cocoa backend
lexers_def/           Original 90-language word lists and styles (data only)
macapp/               AppKit shell: window, menus, toolbar, status, find, preview
tests/sci_test.mm     Core smoke tests
```

Windows SRWLock / thread pool / encoding APIs become the standard library and CFString. Parallel layout is off — a Quartz surface is not thread-safe. The parts that should be fast still are.

## License

See [LICENSE](LICENSE).

- **Original port code** (`macapp/` sources, build scripts, etc.): [PolyForm Noncommercial 1.0.0](https://polyformproject.org/licenses/noncommercial/1.0.0). Personal use is fine; commercial use needs a license.
- **Notepad4 lexers / icons, etc.:** BSD 3-Clause (Zufu Liu / Florian Balmer and others).
- **Scintilla:** historical license (Neil Hodgson).
- **Boost.Regex headers:** Boost Software License 1.0.

Commercial license: <https://github.com/limin640/notepad-mac/issues>
