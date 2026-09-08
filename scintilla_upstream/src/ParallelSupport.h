// This file is part of Notepad4.
// See License.txt for details about distribution and modification.
// macOS port: Win32 parallel helpers replaced with std equivalents.
#pragma once

#include <memory>
#include <shared_mutex>

namespace Scintilla::Internal {

// 堆分配包装（macOS 桩：标准分配器，零初始化）
struct HeapPointerFreer {
	template <typename T>
	void operator()(T *ptr) const noexcept {
		::operator delete[](ptr);
	}

	template <typename T>
	requires std::is_unbounded_array_v<T>
	static std::unique_ptr<T, HeapPointerFreer> make_unique(size_t size) noexcept {
		using U = std::remove_extent_t<T>;
		return std::unique_ptr<T, HeapPointerFreer>{new U[size]{}};
	}
};

inline bool WaitableTimerExpired(void *) noexcept {
	return false;
}

#define _Acquires_lock_(x)
#define _Releases_lock_(x)
#define _Acquires_shared_lock_(x)
#define _Releases_shared_lock_(x)

class NativeMutex {
	std::shared_mutex m;
public:
	void lock() noexcept { m.lock(); }
	void unlock() noexcept { m.unlock(); }
	void lock_shared() noexcept { m.lock_shared(); }
	void unlock_shared() noexcept { m.unlock_shared(); }
};

template <class Mutex>
class LockGuard {
	Mutex &mutex;
public:
	explicit LockGuard(Mutex& m) noexcept : mutex{m} { mutex.lock(); }
	~LockGuard() { mutex.unlock(); }
	LockGuard(LockGuard const&) = delete;
	LockGuard(LockGuard const&&) = delete;
	LockGuard& operator=(LockGuard const&) = delete;
	LockGuard& operator=(LockGuard const&&) = delete;
};

} // namespace Scintilla::Internal
