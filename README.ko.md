# Notepad Mac

[English](README.md) | [简体中文](README.zh-CN.md) | [繁體中文](README.zh-Hant.md) | [日本語](README.ja.md) | **한국어** | [Deutsch](README.de.md) | [Français](README.fr.md) | [Español](README.es.md) | [Italiano](README.it.md) | [Português](README.pt-BR.md) | [Русский](README.ru.md)

**4 MB. 네이티브. 열고 치면 됩니다.**

Windows의 가벼운 [Notepad4](https://github.com/zufuliu/notepad4)를 Mac에 그대로 옮겼습니다. Scintilla + 공식 Cocoa + AppKit. Wine도 Electron도 아닙니다.

Wine 묶음은 약 1 GB. 이건 약 **4 MB**.

개인 비상업 이용은 무료. 이 이식의 상업적 이용은 라이선스가 필요합니다. [LICENSE](LICENSE).

## 왜 이걸 쓰나

- **바로 열림.** 환영 화면, 확장 장터 없음.
- **네이티브.** 다크 모드는 시스템을 따름. GB18030 / GBK / BIG5 / Shift-JIS 감지.
- **구문 강조 90종, 색은 Windows 원판과 같음.**
- **UI는 원판 그대로.**
- **미리보기.** Markdown, HTML, 이미지.
- **UI 언어는 시스템을 따름.**

IDE가 아닙니다. 할 일은 **열고, 고치고, 저장하고, 나가는 것**입니다.

## 다운로드

[Releases](https://github.com/limin640/notepad-mac/releases)의 DMG를 응용 프로그램으로. Apple 실리콘, macOS 11+.

공증 없음. 처음 열 때 개발자를 확인할 수 없다고 뜹니다. **악성코드가 아닙니다.** Control-클릭 → 열기, 또는 `xattr -cr "/Applications/Notepad Mac.app"`.

## 후원

Help → 후원, 또는 WeChat Pay:

![Donate](docs/donate/wechat.png)

## 빌드

```bash
./build.sh
open "build/Notepad Mac.app"
```

## 라이선스

[LICENSE](LICENSE). 상업용: <https://github.com/limin640/notepad-mac/issues>
