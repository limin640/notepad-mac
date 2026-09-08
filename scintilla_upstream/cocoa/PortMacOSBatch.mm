// Notepad4 macOS port: Editor::Begin/EndBatchUpdate 兜底
// Windows 版在 ScintillaWin.cxx 3033-3057；include 链对照 ScintillaCocoa.mm。
#include <cassert>
#include <cmath>
#include <string>
#include <string_view>
#include <vector>
#include <optional>
#include <algorithm>
#include <memory>

#import <Cocoa/Cocoa.h>

#import "ScintillaTypes.h"
#import "ScintillaMessages.h"
#import "ScintillaStructures.h"

#import "Debugging.h"
#import "Geometry.h"
#import "Platform.h"
#import "ScintillaView.h"
#import "ScintillaCocoa.h"
#import "PlatCocoa.h"

namespace Scintilla::Internal {

void Editor::BeginBatchUpdate() noexcept {
	++batchUpdateDepth;
	if (batchUpdateDepth == 1) {
		batchUpdateState.modEventMask = modEventMask;
		modEventMask = ModificationFlags::None;
		batchUpdateState.actions = pdoc->UndoActions();
		batchUpdateState.lines = pdoc->LinesTotal();
	}
}

void Editor::EndBatchUpdate() noexcept {
	--batchUpdateDepth;
	if (batchUpdateDepth == 0) {
		modEventMask = batchUpdateState.modEventMask;
		Redraw();
		if (batchUpdateState.actions != pdoc->UndoActions()) {
			NotificationData scn = {};
			scn.nmhdr.code = Notification::Modified;
			scn.linesAdded = pdoc->LinesTotal() - batchUpdateState.lines;
			NotifyParent(scn);
		}
	}
}

} // namespace
