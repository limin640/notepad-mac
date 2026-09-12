# Notepad Mac

[English](README.md) | [简体中文](README.zh-CN.md) | [繁體中文](README.zh-Hant.md) | [日本語](README.ja.md) | [한국어](README.ko.md) | [Deutsch](README.de.md) | [Français](README.fr.md) | **Español** | [Italiano](README.it.md) | [Português](README.pt-BR.md) | [Русский](README.ru.md)

**4 MB. Nativo. Abrir y escribir.**

El editor ligero de Windows [Notepad4](https://github.com/zufuliu/notepad4), de verdad en el Mac: Scintilla, Cocoa oficial, AppKit. No es Wine. No es Electron.

Un paquete Wine ronda 1 GB. Esta app, unos **4 MB**.

Uso personal no comercial gratis. El uso comercial de este port necesita licencia. Véase [LICENSE](LICENSE).

## Por qué

- **Abre al instante.** Sin pantalla de bienvenida ni marketplace.
- **Nativo.** El modo oscuro sigue a macOS. Detecta GB18030 / GBK / BIG5 / Shift-JIS.
- **90 léxers, mismos colores que en Windows.**
- **La interfaz es la de siempre.**
- **Vista previa** de Markdown, HTML e imágenes.
- **El idioma de la UI sigue al sistema.**

No es un IDE. El trabajo es **abrir, editar, guardar, irse.**

## Descarga

DMG en [Releases](https://github.com/limin640/notepad-mac/releases), a Aplicaciones. Apple silicon, macOS 11+.

Sin notarización. El primer arranque avisa del desarrollador. **No es malware.** Control-clic → Abrir, o `xattr -cr "/Applications/Notepad Mac.app"`.

## Donar

Ayuda → Donar, o WeChat Pay:

![Donate](docs/donate/wechat.png)

## Compilar

```bash
./build.sh
open "build/Notepad Mac.app"
```

## Licencia

[LICENSE](LICENSE). Comercial: <https://github.com/limin640/notepad-mac/issues>
