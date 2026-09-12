# Notepad Mac

[English](README.md) | [简体中文](README.zh-CN.md) | **繁體中文** | [日本語](README.ja.md) | [한국어](README.ko.md) | [Deutsch](README.de.md) | [Français](README.fr.md) | [Español](README.es.md) | [Italiano](README.it.md) | [Português](README.pt-BR.md) | [Русский](README.ru.md)

**4 MB。原生。開箱即寫。**

Windows 上那個又快又瘦的 [Notepad4](https://github.com/zufuliu/notepad4)，第一次有真正的 Mac 版：Scintilla 核心 + 官方 Cocoa 後端 + AppKit 殼。不是 Wine 套一層 Windows，不是 Electron 再塞一個瀏覽器。

macOS 內建文字編輯太素，VS Code / Cursor 開機先喝掉半杯記憶體。這條路是——**把 Notepad4 原封搬上 Mac，體積仍約 4 MB。**

Wine 封裝大約 1 GB。這邊大約 **4 MB**。差兩個數量級。

個人自用免費；本移植的商業使用需授權。詳見 [LICENSE](LICENSE)。

## 憑什麼用它

- **秒開。** 沒有歡迎頁、沒有擴充市場。日誌、設定、腳本，打開即寫。
- **真·原生。** 深色模式跟系統走。GB18030 / GBK / BIG5 / Shift-JIS 會偵測，中文 Windows 丟過來的文字不會一打開就亂碼。
- **90 種語法著色，配色跟 Windows 原版同一套。**
- **介面按原版逐項復刻。** Windows 上手的人不用重新學。
- **該預覽時預覽。** Markdown、HTML、圖片在右側渲染。
- **介面語言跟隨系統**，可強制切換。

它不是 IDE。Notepad4 的活是——**打開、改、存、走人。**

## 下載

從 [Releases](https://github.com/limin640/notepad-mac/releases) 下載 DMG，拖進「應用程式」。Apple 晶片，macOS 11+。

沒有 Apple 公證。第一次從網路上打開會被攔住，**不是病毒**。任選一次：Control-點擊 → 打開；或系統設定 → 隱私權與安全性 → 仍要打開；或 `xattr -cr "/Applications/Notepad Mac.app"`。

## 贊助

Help → 贊助，或掃 WeChat Pay：

![Donate](docs/donate/wechat.png)

## 建置

```bash
./build.sh
open "build/Notepad Mac.app"
```

## 授權

見 [LICENSE](LICENSE)。個人自用可以，本移植商業使用需授權：<https://github.com/limin640/notepad-mac/issues>
