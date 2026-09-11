#!/usr/bin/env python3
"""Write README.<lang>.md siblings. English and zh-CN stay hand-edited; this updates the nav line."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
NAV = [
    ("English", "README.md"),
    ("简体中文", "README.zh-CN.md"),
    ("繁體中文", "README.zh-Hant.md"),
    ("日本語", "README.ja.md"),
    ("한국어", "README.ko.md"),
    ("Deutsch", "README.de.md"),
    ("Français", "README.fr.md"),
    ("Español", "README.es.md"),
    ("Italiano", "README.it.md"),
    ("Português", "README.pt-BR.md"),
    ("Русский", "README.ru.md"),
]


def switcher(current):
    parts = []
    for name, fn in NAV:
        parts.append(f"**{name}**" if fn == current else f"[{name}]({fn})")
    return " | ".join(parts)


BODIES = {
    "README.zh-Hant.md": """# Notepad4 for macOS

{nav}

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

從 [Releases](https://github.com/limin640/notepad4-mac/releases) 下載 DMG，拖進「應用程式」。Apple 晶片，macOS 11+。

沒有 Apple 公證。第一次從網路上打開會被攔住，**不是病毒**。任選一次：Control-點擊 → 打開；或系統設定 → 隱私權與安全性 → 仍要打開；或 `xattr -cr /Applications/Notepad4.app`。

## 贊助

Help → 贊助，或掃 WeChat Pay：

![Donate](docs/donate/wechat.png)

## 建置

```bash
./build.sh
open build/Notepad4.app
```

## 授權

見 [LICENSE](LICENSE)。個人自用可以，本移植商業使用需授權：<https://github.com/limin640/notepad4-mac/issues>
""",
    "README.ja.md": """# Notepad4 for macOS

{nav}

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

[Releases](https://github.com/limin640/notepad4-mac/releases) の DMG を Applications へ。Apple シリコン、macOS 11+。

公証なし。初回は「開発元を確認できない」と出ます。**マルウェアではありません。** Control-クリック → 開く、または `xattr -cr /Applications/Notepad4.app`。

## 寄付

Help → 寄付、または WeChat Pay：

![Donate](docs/donate/wechat.png)

## ビルド

```bash
./build.sh
open build/Notepad4.app
```

## ライセンス

[LICENSE](LICENSE)。商用：<https://github.com/limin640/notepad4-mac/issues>
""",
    "README.ko.md": """# Notepad4 for macOS

{nav}

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

[Releases](https://github.com/limin640/notepad4-mac/releases)의 DMG를 응용 프로그램으로. Apple 실리콘, macOS 11+.

공증 없음. 처음 열 때 개발자를 확인할 수 없다고 뜹니다. **악성코드가 아닙니다.** Control-클릭 → 열기, 또는 `xattr -cr /Applications/Notepad4.app`.

## 후원

Help → 후원, 또는 WeChat Pay:

![Donate](docs/donate/wechat.png)

## 빌드

```bash
./build.sh
open build/Notepad4.app
```

## 라이선스

[LICENSE](LICENSE). 상업용: <https://github.com/limin640/notepad4-mac/issues>
""",
    "README.de.md": """# Notepad4 for macOS

{nav}

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

DMG von [Releases](https://github.com/limin640/notepad4-mac/releases) nach Programme. Apple Silicon, macOS 11+.

Nicht notarisiert. Der erste Start warnt vor einem unbekannten Entwickler. **Kein Schadsoftware.** Control-Klick → Öffnen, oder `xattr -cr /Applications/Notepad4.app`.

## Spenden

Hilfe → Spenden, oder WeChat Pay:

![Donate](docs/donate/wechat.png)

## Bauen

```bash
./build.sh
open build/Notepad4.app
```

## Lizenz

[LICENSE](LICENSE). Kommerziell: <https://github.com/limin640/notepad4-mac/issues>
""",
    "README.fr.md": """# Notepad4 for macOS

{nav}

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
""",
    "README.es.md": """# Notepad4 for macOS

{nav}

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

DMG en [Releases](https://github.com/limin640/notepad4-mac/releases), a Aplicaciones. Apple silicon, macOS 11+.

Sin notarización. El primer arranque avisa del desarrollador. **No es malware.** Control-clic → Abrir, o `xattr -cr /Applications/Notepad4.app`.

## Donar

Ayuda → Donar, o WeChat Pay:

![Donate](docs/donate/wechat.png)

## Compilar

```bash
./build.sh
open build/Notepad4.app
```

## Licencia

[LICENSE](LICENSE). Comercial: <https://github.com/limin640/notepad4-mac/issues>
""",
    "README.it.md": """# Notepad4 for macOS

{nav}

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

DMG da [Releases](https://github.com/limin640/notepad4-mac/releases) in Applicazioni. Apple silicon, macOS 11+.

Non notarizzato. Al primo avvio il sistema avvisa. **Non è malware.** Control-clic → Apri, oppure `xattr -cr /Applications/Notepad4.app`.

## Dona

Aiuto → Dona, o WeChat Pay:

![Donate](docs/donate/wechat.png)

## Compilare

```bash
./build.sh
open build/Notepad4.app
```

## Licenza

[LICENSE](LICENSE). Commerciale: <https://github.com/limin640/notepad4-mac/issues>
""",
    "README.pt-BR.md": """# Notepad4 for macOS

{nav}

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
""",
    "README.ru.md": """# Notepad4 for macOS

{nav}

**4 МБ. Нативно. Открыл и пишешь.**

Лёгкий Windows-редактор [Notepad4](https://github.com/zufuliu/notepad4) наконец на Mac: Scintilla, официальный Cocoa, AppKit. Не Wine. Не Electron.

Сборка Wine — около 1 ГБ. Это приложение — около **4 МБ**.

Личное некоммерческое использование бесплатно. Коммерческое использование этого порта — по лицензии. См. [LICENSE](LICENSE).

## Зачем

- **Открывается сразу.** Без экрана приветствия.
- **Нативно.** Тёмная тема как в системе. Определение GB18030 / GBK / BIG5 / Shift-JIS.
- **90 лексерів, цвета как в Windows.**
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
""",
}

# typo fix ru
BODIES["README.ru.md"] = BODIES["README.ru.md"].replace("лексерів", "лексеров")


def patch_nav(path: Path, filename: str):
    text = path.read_text(encoding="utf-8")
    nav = switcher(filename)
    lines = text.splitlines()
    # replace first non-empty line after title that looks like a language switcher, or insert
    if len(lines) >= 3 and ("README" in lines[2] or "English" in lines[2] or "简体" in lines[2]):
        lines[2] = nav
        path.write_text("\n".join(lines) + "\n", encoding="utf-8")
        return
    # insert after title
    out = [lines[0], "", nav] + lines[1:]
    path.write_text("\n".join(out) + "\n", encoding="utf-8")


def main():
    for fn, body in BODIES.items():
        p = ROOT / fn
        p.write_text(body.format(nav=switcher(fn)).rstrip() + "\n", encoding="utf-8")
        print("wrote", fn)
    patch_nav(ROOT / "README.md", "README.md")
    patch_nav(ROOT / "README.zh-CN.md", "README.zh-CN.md")
    print("patched nav on en/zh-CN")


if __name__ == "__main__":
    main()
