# Notepad for macOS

[English](README.md) | [简体中文](README.zh-CN.md) | [繁體中文](README.zh-Hant.md) | **日本語** | [한국어](README.ko.md) | [Deutsch](README.de.md) | [Français](README.fr.md) | [Español](README.es.md) | [Italiano](README.it.md) | [Português](README.pt-BR.md) | [Русский](README.ru.md)

**4 MB。ネイティブ。開いて打つ。**

Windows の軽量エディタ [Notepad4](https://github.com/zufuliu/notepad4) の、本当の Mac 版です。Scintilla + 公式 Cocoa + AppKit。Wine でも Electron でもありません。

Wine 版は約 1 GB。これは約 **4 MB**。

個人の非商用利用は無料。この移植の商用利用にはライセンスが必要です。[LICENSE](LICENSE)。

## なぜこれか

- **すぐ開く。** ウェルカム画面も拡張マーケットもない。
- **ネイティブ。** ダークモードはシステムに従う。GB18030 / GBK / BIG5 / Shift-JIS を検出。
- **90 の字句解析、色は Windows 原版と同じ。**
- **UI は原版どおり。** Notepad4 を知っていればそのまま使える。
- **プレビュー。** Markdown、HTML、画像。
- **UI 言語はシステムに追従。**

IDE ではありません。仕事は **開く、直す、保存、終了** です。

## ダウンロード

[Releases](https://github.com/limin640/notepad-mac/releases) の DMG を Applications へ。Apple シリコン、macOS 11+。

公証なし。初回は「開発元を確認できない」と出ます。**マルウェアではありません。** Control-クリック → 開く、または `xattr -cr /Applications/Notepad.app`。

## 寄付

Help → 寄付、または WeChat Pay：

![Donate](docs/donate/wechat.png)

## ビルド

```bash
./build.sh
open build/Notepad.app
```

## ライセンス

[LICENSE](LICENSE)。商用：<https://github.com/limin640/notepad-mac/issues>
