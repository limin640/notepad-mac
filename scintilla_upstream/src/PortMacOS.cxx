// Notepad4 macOS port: 应用层全局与 Win32 层函数兜底
// dwUrlThreshold / QueryPerformanceCounter / Editor::BatchUpdate（Windows 版在 ScintillaWin.cxx）
#include <cstdint>
#include <chrono>

#include "ScintillaTypes.h"
#include "Geometry.h"
#include "Platform.h"
#include "ElapsedPeriod.h"

// dwUrlThreshold：URL 高亮阈值（MB），0 = 禁用。默认 16MB 与 Windows 版一致。
// ScintillaBase.cxx 里 extern unsigned int dwUrlThreshold;（全局命名空间）
unsigned int dwUrlThreshold = 16;

namespace Scintilla::Internal {

// ElapsedPeriod.h 声明（Windows 由 win32 层提供；macOS 用 steady_clock 实现）
int64_t QueryPerformanceFrequency() noexcept {
	return 1'000'000'000;
}

int64_t QueryPerformanceCounter() noexcept {
	return std::chrono::duration_cast<std::chrono::nanoseconds>(
		std::chrono::steady_clock::now().time_since_epoch()).count();
}

} // namespace

// ---- Editor::Begin/EndBatchUpdate ----
// 依赖完整 Editor 类定义，放单独翻译单元（PortMacOSBatch.cxx 经 ScintillaCocoa.h 拉全依赖）
