# Notepad4 for macOS

[English](README.md) | [简体中文](README.zh-CN.md) | [繁體中文](README.zh-Hant.md) | [日本語](README.ja.md) | [한국어](README.ko.md) | [Deutsch](README.de.md) | [Français](README.fr.md) | [Español](README.es.md) | [Italiano](README.it.md) | **Português** | [Русский](README.ru.md)

**4 MB. Nativo. Abrir e digitar.**

O editor leve do Windows [Notepad4](https://github.com/zufuliu/notepad4), de verdade no Mac: Scintilla, Cocoa oficial, AppKit. Não é Wine. Não é Electron.

Um pacote Wine tem cerca de 1 GB. Este app, cerca de **4 MB**.

Uso pessoal não comercial gratuito. Uso comercial deste port precisa de licença. Veja [LICENSE](LICENSE).

## Por quê

- **Abre na hora.** Sem tela de boas-vindas.
- **Nativo.** O modo escuro segue o macOS. Detecta GB18030 / GBK / BIG5 / Shift-JIS.
- **90 lexers, as mesmas cores do Windows.**
- **Interface fiel.**
- **Pré-visualização** de Markdown, HTML e imagens.
- **O idioma da UI segue o sistema.**

Não é uma IDE. O trabalho é **abrir, editar, salvar, sair.**

## Download

DMG em [Releases](https://github.com/limin640/notepad4-mac/releases), para Aplicativos. Apple silicon, macOS 11+.

Sem notarização. A primeira abertura avisa sobre o desenvolvedor. **Não é malware.** Control-clique → Abrir, ou `xattr -cr /Applications/Notepad4.app`.

## Doar

Ajuda → Doar, ou WeChat Pay:

![Donate](docs/donate/wechat.png)

## Compilar

```bash
./build.sh
open build/Notepad4.app
```

## Licença

[LICENSE](LICENSE). Comercial: <https://github.com/limin640/notepad4-mac/issues>
