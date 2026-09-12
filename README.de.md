# Notepad for macOS

[English](README.md) | [简体中文](README.zh-CN.md) | [繁體中文](README.zh-Hant.md) | [日本語](README.ja.md) | [한국어](README.ko.md) | **Deutsch** | [Français](README.fr.md) | [Español](README.es.md) | [Italiano](README.it.md) | [Português](README.pt-BR.md) | [Русский](README.ru.md)

**4 MB. Nativ. Öffnen und tippen.**

Der schlanke Windows-Editor [Notepad4](https://github.com/zufuliu/notepad4), jetzt wirklich auf dem Mac: Scintilla, offizielles Cocoa, AppKit. Kein Wine. Kein Electron.

Ein Wine-Paket ist etwa 1 GB. Diese App ist etwa **4 MB**.

Persönliche, nicht-kommerzielle Nutzung ist frei. Kommerzielle Nutzung dieses Ports braucht eine Lizenz. Siehe [LICENSE](LICENSE).

## Warum

- **Sofort offen.** Keine Willkommensseite, kein Marketplace.
- **Nativ.** Dark Mode folgt macOS. GB18030 / GBK / BIG5 / Shift-JIS werden erkannt.
- **90 Lexer, Farben wie im Windows-Original.**
- **UI 1:1.** Wer Notepad4 kennt, kennt das hier.
- **Vorschau** für Markdown, HTML, Bilder.
- **UI-Sprache folgt dem System.**

Kein IDE. Die Arbeit ist: **öffnen, ändern, sichern, gehen.**

## Download

DMG von [Releases](https://github.com/limin640/notepad-mac/releases) nach Programme. Apple Silicon, macOS 11+.

Nicht notarisiert. Der erste Start warnt vor einem unbekannten Entwickler. **Kein Schadsoftware.** Control-Klick → Öffnen, oder `xattr -cr /Applications/Notepad.app`.

## Spenden

Hilfe → Spenden, oder WeChat Pay:

![Donate](docs/donate/wechat.png)

## Bauen

```bash
./build.sh
open build/Notepad.app
```

## Lizenz

[LICENSE](LICENSE). Kommerziell: <https://github.com/limin640/notepad-mac/issues>
