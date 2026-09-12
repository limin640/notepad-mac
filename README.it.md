# Notepad for macOS

[English](README.md) | [简体中文](README.zh-CN.md) | [繁體中文](README.zh-Hant.md) | [日本語](README.ja.md) | [한국어](README.ko.md) | [Deutsch](README.de.md) | [Français](README.fr.md) | [Español](README.es.md) | **Italiano** | [Português](README.pt-BR.md) | [Русский](README.ru.md)

**4 MB. Nativo. Apri e scrivi.**

L’editor leggero Windows [Notepad4](https://github.com/zufuliu/notepad4), davvero sul Mac: Scintilla, Cocoa ufficiale, AppKit. Non Wine. Non Electron.

Un pacchetto Wine è circa 1 GB. Questa app circa **4 MB**.

Uso personale non commerciale gratuito. L’uso commerciale di questo port richiede una licenza. Vedi [LICENSE](LICENSE).

## Perché

- **Si apre subito.** Niente schermata di benvenuto.
- **Nativo.** Il dark mode segue macOS. Rileva GB18030 / GBK / BIG5 / Shift-JIS.
- **90 lexer, stessi colori di Windows.**
- **Interfaccia fedele.**
- **Anteprima** Markdown, HTML, immagini.
- **La lingua dell’UI segue il sistema.**

Non è un IDE. Il lavoro è **aprire, modificare, salvare, uscire.**

## Download

DMG da [Releases](https://github.com/limin640/notepad-mac/releases) in Applicazioni. Apple silicon, macOS 11+.

Non notarizzato. Al primo avvio il sistema avvisa. **Non è malware.** Control-clic → Apri, oppure `xattr -cr /Applications/Notepad.app`.

## Dona

Aiuto → Dona, o WeChat Pay:

![Donate](docs/donate/wechat.png)

## Compilare

```bash
./build.sh
open build/Notepad.app
```

## Licenza

[LICENSE](LICENSE). Commerciale: <https://github.com/limin640/notepad-mac/issues>
