# notepad4-mac

[zufuliu/notepad4](https://github.com/zufuliu/notepad4) 的 macOS 原生移植（路线 C：Scintilla 内核 + 官方 Cocoa 后端 + AppKit 壳，零 Wine/Electron）。

**体积 3 MB**（Windows 原版 2 MB，Wine 封装约 1 GB）。

## 界面（按 Notepad4 源码逐项复刻）

- **菜单**：File / Edit / Search / View / Scheme / Settings / Tools / Help（对照 Notepad4.rc 原文，含全部子菜单与快捷键）
- **工具栏**：直接使用原版 `Toolbar24.bmp` 位图图标，顺序取自 `DefaultToolbarButtons`
  （Open Favorites · Browse │ New · New Window · Open▾ │ Save · Save As · Save Copy │ Undo · Redo │
  Cut · Copy · Paste · Delete │ Find · Replace │ Word Wrap │ Toggle Folds▾ │ Zoom In · Zoom Out │
  Syntax Scheme · Customize Schemes │ Exit）
- **状态栏**：`Ln x / y` │ `Col x / y` │ `Ch x / y` │ `Sel bytes / chars` │ `SelLn n` │ `Fnd n` │
  `词法器名` │ `编码` │ `CR+LF` │ `INS` │ `100%` │ `大小`（对照 `IDS_STATUSITEM_FORMAT`）
- **编辑区**：行号栏（`#2B91AF`）、折叠栏（方框 +/-，`#8080FF`/`#ADD8E6`）、当前行 outline 框、
  自动折叠 + 省略号（Boxed），TAB=4，光标 1px 线
- **主题**：Scheme → Style Theme → `Default`（亮）/ `Dark`（暗，颜色取自 `Notepad4 DarkTheme.ini`）。
  启动时跟随 macOS 系统外观（暗色系统 → 暗色编辑区 + 暗色工具栏/状态栏；亮色系统 → 全浅色）
- 单文档（Notepad4 本身无标签页）

## 功能

| 功能 | 状态 |
|---|---|
| 90 个词法器（notepad4 原版词表+配色） | ✅ lexers_def/ 全量 |
| 亮/暗主题（源码颜色值） | ✅ 像素级验证 #1E1E1E / #00B050 / #A349A4 |
| 代码折叠 | ✅ Box tree 标记 + 自动折叠 |
| 语法着色（每词法器独立样式） | ✅ 继承 stlXXX.cpp 原版配色 |
| 编码检测/转换 | ✅ BOM/UTF-8/GB18030 探测；重载为 7 种编码；保存编码切换 |
| 查找替换 | ✅ 正则/大小写/全字；替换单个/全部；循环查找 |
| 自动补全 | ✅ 词表驱动（≥2 字符触发） |
| 书签 | ✅ 切换/下一个/清除 |
| 行操作 | ✅ 移动/复制/剪切/删除/合并/转置 |
| 大小写转换 | ✅ 大写/小写 |
| 查看 | ✅ 自动换行/行号/空白字符/换行符/缩进线/缩放/状态栏 |
| 跳转到行/括号匹配 | ✅ |
| 打印 | ✅ |
| 跟随系统明暗外观 | ✅ 工具栏/状态栏/编辑区同色系切换 |

## 构建

```bash
./build.sh          # = cmake -S . -B build && cmake --build build
open build/Notepad4.app
```

要求：macOS 11+，Xcode（clang C++20），CMake ≥ 3.20。当前 arm64（可加 x86_64 universal）。

## 架构

```
scintilla_upstream/          # notepad4 的 Scintilla 5.6.6 fork
├── src/                     # 平台无关内核 + macOS 适配（PortMacOS.cxx 等）
├── cocoa/                   # 官方 Cocoa 后端（签名对齐 fork 接口）+ PortMacOSBatch.mm
├── lexers/ lexlib/          # 词法器引擎
lexers_def/                  # notepad4 原版 EDITLEXER 数据（90 语言词表+样式，纯数据）
macapp/                      # AppKit 壳（窗口/工具栏/状态栏/菜单/查找/文档）
tests/sci_test.mm            # 内核冒烟测试
```

### 移植关键点

| Windows | macOS |
|---|---|
| SRWLock/PTP 线程池 | std::shared_mutex / std::async（并行布局已禁用：Quartz surface 非线程安全） |
| WaitableTimer | steady_clock 截止时间 |
| MultiByteToWideChar | CFStringCreateWithBytes 编码映射 |
| QueryPerformanceCounter | steady_clock 纳秒 |
| Editor::BatchUpdate (ScintillaWin) | cocoa/PortMacOSBatch.mm |
| dwUrlThreshold（应用层） | src/PortMacOS.cxx（默认 16MB） |

## 许可

Notepad4 / Scintilla: BSD 3-Clause（保留原始 License.txt）。移植新增文件同许可。
