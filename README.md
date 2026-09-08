# notepad4-mac

Notepad4 (zufuliu/notepad4) 的 macOS 原生移植。路线 C：Scintilla 内核 + 官方 Cocoa 后端 + 原生 AppKit 壳。

## 架构

```
scintilla_upstream/          # notepad4 的 Scintilla fork（5.6.6，lexer 内置架构）
├── src/                     # 平台无关内核（含 macOS 平台适配）
│   ├── ParallelSupport.h    # Win32 并行原语 → std::shared_mutex 桩
│   ├── PortMacOS.cxx        # dwUrlThreshold / QPC 兜底
│   └── Document.cxx         # MultiByteToWideChar → CoreFoundation 转换
├── cocoa/                   # 官方 Scintilla 5.6.6 Cocoa 后端（签名对齐 fork 接口）
│   └── PortMacOSBatch.mm    # Editor::BatchUpdate（Windows 在 ScintillaWin.cxx）
├── lexers/ lexlib/          # 80+ 词法器（平台无关）
tests/sci_test.mm            # 冒烟测试：ScintillaView + C++ 词法高亮
```

## 构建

```bash
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build -j8
./build/sci_test    # 冒烟测试：弹出 900x600 窗口，C++ 语法高亮
```

要求：macOS 11+，Xcode（clang, C++20），arm64 + x86_64 universal。

## 平台适配清单（fork → macOS）

| Windows 原实现 | macOS 适配 |
|---|---|
| ParallelSupport.h（SRWLock/HeapAlloc/PTP） | std::shared_mutex / new[] / std::async |
| WaitableTimer 空闲定时 | steady_clock 时间戳比对 |
| MultiByteToWideChar（DBCS） | CFStringCreateWithBytes + 编码映射 |
| ScintillaWin.cxx BatchUpdate | PortMacOSBatch.mm（WM_SETREDRAW→Redraw） |
| QueryPerformanceCounter | steady_clock 纳秒 |
| intrin.h SIMD | `#if _WIN32` 守卫（ARM64 路径本就不用） |
| GetActiveProcessorCount | std::thread::hardware_concurrency |

fork 接口改动对齐（cocoa 层签名追平）：Surface 全系 noexcept/SCICALL、FontMetrics 合并五连、ListBox 新接口、SelectionText 新 Copy 签名、SCI_GETSTYLEINDEXAT 替代 SCI_GETSTYLEAT、popup 编译禁用（SCI_EnablePopupMenu=0）。

## 许可

- Notepad4 / Scintilla：BSD 3-Clause（保留原始 License.txt）
- 本移植新增文件：同 BSD 3-Clause
