# Notepad4 for macOS

[English](README.md) | [简体中文](README.zh-CN.md) | [繁體中文](README.zh-Hant.md) | [日本語](README.ja.md) | [한국어](README.ko.md) | [Deutsch](README.de.md) | **Français** | [Español](README.es.md) | [Italiano](README.it.md) | [Português](README.pt-BR.md) | [Русский](README.ru.md)

**4 Mo. Natif. Ouvrir et taper.**

Le petit éditeur Windows [Notepad4](https://github.com/zufuliu/notepad4), enfin vraiment sur Mac : Scintilla, Cocoa officiel, AppKit. Pas Wine. Pas Electron.

Un paquet Wine fait environ 1 Go. Ici, environ **4 Mo**.

Usage personnel non commercial libre. L’usage commercial de ce port nécessite une licence. Voir [LICENSE](LICENSE).

## Pourquoi

- **Ouverture instantanée.** Pas de page d’accueil, pas de marketplace.
- **Natif.** Le mode sombre suit macOS. GB18030 / GBK / BIG5 / Shift-JIS détectés.
- **90 analyseurs, mêmes couleurs que Windows.**
- **Interface à l’identique.**
- **Aperçu** Markdown, HTML, images.
- **La langue de l’UI suit le système.**

Ce n’est pas un IDE. Le travail : **ouvrir, modifier, enregistrer, partir.**

## Télécharger

DMG depuis [Releases](https://github.com/limin640/notepad4-mac/releases) vers Applications. Apple silicon, macOS 11+.

Pas de notarisation. Le premier lancement affiche un développeur inconnu. **Ce n’est pas un malware.** Contrôle-clic → Ouvrir, ou `xattr -cr /Applications/Notepad4.app`.

## Don

Aide → Faire un don, ou WeChat Pay :

![Donate](docs/donate/wechat.png)

## Compilation

```bash
./build.sh
open build/Notepad4.app
```

## Licence

[LICENSE](LICENSE). Commercial : <https://github.com/limin640/notepad4-mac/issues>
