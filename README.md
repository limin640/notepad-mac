# notepad4-mac

[zufuliu/notepad4](https://github.com/zufuliu/notepad4) 的 macOS 原生移植（路线 C：Scintilla 内核 + 官方 Cocoa 后端 + AppKit 壳，零 Wine/Electron）。

**体积 3 MB**（Windows 原版 2 MB，Wine 封装约 1 GB）。

## 界面（复刻 Windows 版）

- 顶部工具栏：新建/打开/保存 · 撤销/重做 · 剪切/复制/粘贴 · 查找/替换 · 缩放 · 词法器选择
- 多标签页文档（修改点标记 •）
- 底部状态栏六格：`Ln 行, Col 列 (选择字节) — 总行数` | `CRLF/LF` | `编码` | `文档大小` | `缩放%` | `词法器名`
- 菜单：文件(F) / 编辑(E) / 搜索(S) / 查看(V) / 帮助(H)——40+ 命令对齐 Windows 版 IDM_ 清单

## 功能

| 功能 | 状态 |
|---|---|
| 90 个词法器（notepad4 原版词表+配色） | ✅ lexers_def/ 全量 |
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
