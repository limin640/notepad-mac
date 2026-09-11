# Notepad4 for macOS

[English](README.md) | [简体中文](README.zh-CN.md) | [繁體中文](README.zh-Hant.md) | [日本語](README.ja.md) | [한국어](README.ko.md) | [Deutsch](README.de.md) | [Français](README.fr.md) | [Español](README.es.md) | [Italiano](README.it.md) | [Português](README.pt-BR.md) | **Русский**

**4 МБ. Нативно. Открыл и пишешь.**

Лёгкий Windows-редактор [Notepad4](https://github.com/zufuliu/notepad4) наконец на Mac: Scintilla, официальный Cocoa, AppKit. Не Wine. Не Electron.

Сборка Wine — около 1 ГБ. Это приложение — около **4 МБ**.

Личное некоммерческое использование бесплатно. Коммерческое использование этого порта — по лицензии. См. [LICENSE](LICENSE).

## Зачем

- **Открывается сразу.** Без экрана приветствия.
- **Нативно.** Тёмная тема как в системе. Определение GB18030 / GBK / BIG5 / Shift-JIS.
- **90 лексеров, цвета как в Windows.**
- **Интерфейс как в оригинале.**
- **Просмотр** Markdown, HTML, картинок.
- **Язык интерфейса следует за системой.**

Это не IDE. Работа — **открыть, править, сохранить, уйти.**

## Загрузка

DMG из [Releases](https://github.com/limin640/notepad4-mac/releases) в Программы. Apple silicon, macOS 11+.

Без нотаризации. При первом запуске система предупредит. **Это не вредонос.** Control-клик → Открыть, или `xattr -cr /Applications/Notepad4.app`.

## Поддержать

Справка → Поддержать, или WeChat Pay:

![Donate](docs/donate/wechat.png)

## Сборка

```bash
./build.sh
open build/Notepad4.app
```

## Лицензия

[LICENSE](LICENSE). Коммерция: <https://github.com/limin640/notepad4-mac/issues>
