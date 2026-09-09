#import "MainWindowController.h"
#import "FindReplacePanel.h"
#import "StatusBarView.h"
#import "SciLexer.h"
#import "EditLexer.h"
#import "LexerRegistry.h"
#import "Scintilla.h"
#import "NPLocalization.h"

// 跟随系统明暗外观的 chrome 背景
@interface NPChromeView : NSView
@property (nonatomic) BOOL borderAtBottom;   // 工具栏底部描边
@property (nonatomic) BOOL borderAtTop;      // 状态栏顶部描边
@end

@interface NPRootView : NSView
@property (nonatomic, weak) MainWindowController *controller;
@end
@implementation NPRootView
- (BOOL)performKeyEquivalent:(NSEvent *)event {
	if ([self.controller handleKeyEquivalent:event]) return YES;
	return [super performKeyEquivalent:event];
}
@end

// 工具栏按钮：只做命中测试，图标由 NPChromeView 统一绘制
@interface NPImageButton : NSView
@property (nonatomic, strong) NSImage *icon;
@property (nonatomic, weak) id tbTarget;
@property (nonatomic) SEL tbAction;
@end

@implementation NPImageButton
- (BOOL)isFlipped { return YES; }
- (void)mouseUp:(NSEvent *)e {
	NSPoint p = [self convertPoint:e.locationInWindow fromView:nil];
	if (NSPointInRect(p, self.bounds) && self.tbAction) {
		[NSApp sendAction:self.tbAction to:self.tbTarget from:self];
	}
}
@end

@implementation NPChromeView
- (void)drawRect:(NSRect)dirtyRect {
	[[NSColor windowBackgroundColor] setFill];
	NSRectFill(self.bounds);
	// 图标统一在此绘制（子视图 backing layer 不可靠）
	for (NSView *sub in self.subviews) {
		if (![sub respondsToSelector:@selector(icon)]) continue;
		NSImage *img = [(id)sub icon];
		if (!img || img.size.width <= 0) continue;
		NSRect b = [sub convertRect:sub.bounds toView:self];
		NSSize is = img.size;
		NSRect r = NSMakeRect(NSMidX(b) - is.width / 2, NSMidY(b) - is.height / 2,
			is.width, is.height);
		[img drawInRect:r fromRect:NSZeroRect operation:NSCompositingOperationSourceOver
			fraction:1.0 respectFlipped:YES hints:nil];
	}
	[[NSColor separatorColor] setFill];
	if (self.borderAtBottom) {
		NSRectFill(NSMakeRect(0, 0, self.bounds.size.width, 1));
	}
	if (self.borderAtTop) {
		NSRectFill(NSMakeRect(0, self.bounds.size.height - 1, self.bounds.size.width, 1));
	}
}
@end

@implementation MainWindowController {
	FindReplacePanel *_findPanel;
	NSView *_editorHost;
	NSPopUpButton *_lexPopup;
	NSMenuItem *_wordWrapItem;
	NSMenuItem *_lineNumbersItem;
	StatusBarView *_statusBar;
	NSView *_menuBar;
	NSMutableArray<NSMenu *> *_inWindowMenus;
	NSMutableArray<NSButton *> *_menuBarButtons;
	id _keyMonitor;
	NSMenu *_recentMenu;
	NSView *_toolBar;
	EditorDocument *_document;
	NSMenuItem *_langChineseItem;
	NSMenuItem *_langEnglishItem;
	NSMenuItem *_themeAutoItem;
	NSMenuItem *_themeDefaultItem;
	NSMenuItem *_themeDarkItem;
}
@dynamic editorDocument;

- (instancetype)init {
	NSWindow *win = [[NSWindow alloc]
		initWithContentRect:NSMakeRect(140, 140, 900, 620)
		styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
			   NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable)
		backing:NSBackingStoreBuffered defer:NO];
	win.title = [NPL(@"Untitled") stringByAppendingString:@" - Notepad4"];
	win.minSize = NSMakeSize(400, 280);
	// chrome 跟随系统外观（暗色系统 → 暗色工具栏/状态栏）
	self = [super initWithWindow:win];
	if (self) {
		win.delegate = self;
		win.windowController = self;
		_document = [[EditorDocument alloc] initWithNewUntitled:1];
		[self buildUI:win];
		[self buildMenu];   // 按 Notepad4.rc 原文复刻
		[self refreshStatus];
		[self updateWindowTitle];
		[NSApp addObserver:self forKeyPath:@"effectiveAppearance"
			options:NSKeyValueObservingOptionNew context:nullptr];
		[self installKeyEquivalentMonitor];
		[win makeFirstResponder:_document.editor.content];
	}
	return self;
}

- (void)dealloc {
	[NSApp removeObserver:self forKeyPath:@"effectiveAppearance"];
}

#pragma mark - 布局（工具栏 / 编辑器 / 状态栏，单文档无标签）

- (void)buildUI:(NSWindow *)win {
	NPRootView *root = [[NPRootView alloc] initWithFrame:win.contentView.bounds];
	root.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
	root.controller = self;
	win.contentView = root;

	NPChromeView *mb = [[NPChromeView alloc] initWithFrame:NSMakeRect(0, 0, 900, 22)];
	mb.borderAtBottom = NO;
	mb.translatesAutoresizingMaskIntoConstraints = NO;
	[root addSubview:mb];
	_menuBar = mb;

	// ---- 工具栏：原版位图图标 + DefaultToolbarButtons 顺序 ----
	NPChromeView *bar = [[NPChromeView alloc] initWithFrame:NSMakeRect(0, 0, 900, 26)];
	_toolBar = bar;
	bar.borderAtBottom = YES;
	bar.translatesAutoresizingMaskIntoConstraints = NO;
	[root addSubview:bar];

	// 顺序取自 Notepad4.cpp DefaultToolbarButtons（iBitmap, action, dropdown）
	struct TBEntry { int icon; SEL act; BOOL dropdown; const char *tip; };
	static const TBEntry kTB[] = {
		{21, @selector(tbOpenFav), NO, "Open Favorites"},
		{ 2, @selector(tbBrowse), NO, "Browse..."},
		{-1, nullptr, NO, nullptr},
		{ 0, @selector(fileNew), NO, "New"},
		{26, @selector(fileNewWindow), NO, "New Window"},
		{ 1, @selector(tbOpenDropdown), YES, "Open..."},
		{-1, nullptr, NO, nullptr},
		{ 3, @selector(fileSave), NO, "Save"},
		{17, @selector(fileSaveAs), NO, "Save As..."},
		{18, @selector(fileSaveCopy), NO, "Save Copy..."},
		{-1, nullptr, NO, nullptr},
		{ 4, @selector(editUndo), NO, "Undo"},
		{ 5, @selector(editRedo), NO, "Redo"},
		{-1, nullptr, NO, nullptr},
		{ 6, @selector(editCut), NO, "Cut"},
		{ 7, @selector(editCopy), NO, "Copy"},
		{ 8, @selector(editPaste), NO, "Paste"},
		{19, @selector(editDelete), NO, "Delete"},
		{-1, nullptr, NO, nullptr},
		{ 9, @selector(searchFind), NO, "Find..."},
		{10, @selector(searchReplace), NO, "Replace..."},
		{-1, nullptr, NO, nullptr},
		{11, @selector(viewWordWrap), NO, "Word Wrap"},
		{-1, nullptr, NO, nullptr},
		{23, @selector(tbFoldDropdown), YES, "Toggle Folds"},
		{-1, nullptr, NO, nullptr},
		{12, @selector(viewZoomIn), NO, "Zoom In"},
		{13, @selector(viewZoomOut), NO, "Zoom Out"},
		{-1, nullptr, NO, nullptr},
		{14, @selector(tbSchemeMenu), NO, "Syntax Scheme..."},
		{15, @selector(tbSchemeConfig), NO, "Customize Schemes"},
		{-1, nullptr, NO, nullptr},
		{16, @selector(terminate), NO, "Exit"},
	};

	NSView *prev = nil;
	for (unsigned i = 0; i < sizeof(kTB)/sizeof(kTB[0]); i++) {
		const TBEntry &e = kTB[i];
		NSView *v = nil;
		if (e.icon < 0) {
			NSView *sep = [[NSView alloc] initWithFrame:NSZeroRect];
			sep.wantsLayer = YES;
			sep.layer.backgroundColor = [NSColor separatorColor].CGColor;
			sep.translatesAutoresizingMaskIntoConstraints = NO;
			[sep.widthAnchor constraintEqualToConstant:1].active = YES;
			[sep.heightAnchor constraintEqualToConstant:16].active = YES;
			v = sep;
		} else {
			NSString *name = [NSString stringWithFormat:@"tb16_%02d", e.icon];
			NSString *path = [[NSBundle mainBundle] pathForResource:name ofType:@"png"];
			NPImageButton *b = [[NPImageButton alloc] initWithFrame:NSMakeRect(0, 0, 22, 22)];
			b.icon = path ? [[NSImage alloc] initWithContentsOfFile:path] : [NSImage new];
			b.tbTarget = self;
			b.tbAction = e.act;
			b.toolTip = e.tip ? NPL([NSString stringWithUTF8String:e.tip]) : nil;
			b.translatesAutoresizingMaskIntoConstraints = NO;
			[b.widthAnchor constraintEqualToConstant:22].active = YES;
			[b.heightAnchor constraintEqualToConstant:22].active = YES;
			if (e.dropdown) {
				// 右下角小三角（Win32 BTNS_DROPDOWN 外观）—— 直接画在按钮上
				b.toolTip = [b.toolTip stringByAppendingString:@" ▾"];
			}
			v = b;
		}
		[bar addSubview:v];
		if (!prev) {
			[v.leadingAnchor constraintEqualToAnchor:bar.leadingAnchor constant:3].active = YES;
		} else if (e.icon < 0) {
			[prev.trailingAnchor constraintEqualToAnchor:v.leadingAnchor constant:3].active = YES;
		} else {
			[prev.trailingAnchor constraintEqualToAnchor:v.leadingAnchor constant:0].active = YES;
		}
		[v.centerYAnchor constraintEqualToAnchor:bar.centerYAnchor].active = YES;
		prev = v;
	}
	[bar.trailingAnchor constraintGreaterThanOrEqualToAnchor:prev.trailingAnchor constant:4].active = YES;

	// ---- 编辑器（占满中间）----
	_editorHost = [[NSView alloc] initWithFrame:NSZeroRect];
	_editorHost.translatesAutoresizingMaskIntoConstraints = NO;
	[root addSubview:_editorHost];
	_document.editor.translatesAutoresizingMaskIntoConstraints = NO;
	[_editorHost addSubview:_document.editor];
	[_editorHost.leadingAnchor constraintEqualToAnchor:_document.editor.leadingAnchor].active = YES;
	[_editorHost.trailingAnchor constraintEqualToAnchor:_document.editor.trailingAnchor].active = YES;
	[_editorHost.topAnchor constraintEqualToAnchor:_document.editor.topAnchor].active = YES;
	[_editorHost.bottomAnchor constraintEqualToAnchor:_document.editor.bottomAnchor].active = YES;

	// ---- 状态栏 ----
	_statusBar = [[StatusBarView alloc] initWithFrame:NSMakeRect(0, 0, 900, 22)];
	_statusBar.translatesAutoresizingMaskIntoConstraints = NO;
	[root addSubview:_statusBar];

	// 约束
	[root.leadingAnchor constraintEqualToAnchor:mb.leadingAnchor].active = YES;
	[root.trailingAnchor constraintEqualToAnchor:mb.trailingAnchor].active = YES;
	[root.topAnchor constraintEqualToAnchor:mb.topAnchor].active = YES;
	[mb.heightAnchor constraintEqualToConstant:22].active = YES;
	[mb.bottomAnchor constraintEqualToAnchor:bar.topAnchor].active = YES;
	[root.leadingAnchor constraintEqualToAnchor:bar.leadingAnchor].active = YES;
	[root.trailingAnchor constraintEqualToAnchor:bar.trailingAnchor].active = YES;
	[bar.heightAnchor constraintEqualToConstant:26].active = YES;

	[root.leadingAnchor constraintEqualToAnchor:_editorHost.leadingAnchor].active = YES;
	[root.trailingAnchor constraintEqualToAnchor:_editorHost.trailingAnchor].active = YES;
	[bar.bottomAnchor constraintEqualToAnchor:_editorHost.topAnchor].active = YES;

	[root.leadingAnchor constraintEqualToAnchor:_statusBar.leadingAnchor].active = YES;
	[root.trailingAnchor constraintEqualToAnchor:_statusBar.trailingAnchor].active = YES;
	[_statusBar.heightAnchor constraintEqualToConstant:22].active = YES;
	[_editorHost.bottomAnchor constraintEqualToAnchor:_statusBar.topAnchor].active = YES;
	[root.bottomAnchor constraintEqualToAnchor:_statusBar.bottomAnchor].active = YES;

	_findPanel = [[FindReplacePanel alloc] initWithFrame:NSMakeRect(0, 0, 620, 84)];
	[_findPanel attachToWindow:win];
	// 面板底边贴状态栏顶部（不贴边会被编辑区盖住）
	[_findPanel.bottomAnchor constraintEqualToAnchor:_statusBar.topAnchor].active = YES;
}

#pragma mark - 菜单（Notepad4.rc 原文）

static NSMenu *M(NSString *title) {
	NSMenu *m = [[NSMenu alloc] initWithTitle:title];
	return m;
}
static NSMenuItem *MI(NSMenu *m, NSString *title, SEL act, NSString *key, NSEventModifierFlags flags) {
	NSMenuItem *i = [m addItemWithTitle:title action:act keyEquivalent:key ?: @""];
	if (flags) i.keyEquivalentModifierMask = flags;
	return i;
}
static void MSep(NSMenu *m) { [m addItem:[NSMenuItem separatorItem]]; }

- (void)buildMenu {
	NSMenu *mb = [[NSMenu alloc] init];

	// App 菜单（macOS 必需）
	NSMenuItem *appItem = [mb addItemWithTitle:NPL(@"Notepad4") action:nil keyEquivalent:@""];
	NSMenu *appMenu = M(NPL(@""));
	[appMenu addItemWithTitle:NPL(@"About Notepad4") action:@selector(orderFrontStandardAboutPanel:) keyEquivalent:@""];
	MSep(appMenu);
	[appMenu addItemWithTitle:NPL(@"Hide Notepad4") action:@selector(hide:) keyEquivalent:@"h"];
	[appMenu addItemWithTitle:NPL(@"Hide Others") action:@selector(hideOtherApplications:) keyEquivalent:@"h"].keyEquivalentModifierMask = NSEventModifierFlagCommand|NSEventModifierFlagOption;
	[appMenu addItemWithTitle:NPL(@"Show All") action:@selector(unhideAllApplications:) keyEquivalent:@""];
	MSep(appMenu);
	[appMenu addItemWithTitle:NPL(@"Quit Notepad4") action:@selector(terminate:) keyEquivalent:@"q"];
	appItem.submenu = appMenu;

	NSString *F3 = [NSString stringWithFormat:@"%d", NSF3FunctionKey];
	NSString *F5 = [NSString stringWithFormat:@"%d", NSF5FunctionKey];
	NSString *F6 = [NSString stringWithFormat:@"%d", NSF6FunctionKey];
	NSString *F10 = [NSString stringWithFormat:@"%d", NSF10FunctionKey];
	NSString *F12 = [NSString stringWithFormat:@"%d", NSF12FunctionKey];

	// ===== File =====
	NSMenu *file = M(NPL(@"File"));
	MI(file, NPL(@"New\tCtrl+N"), @selector(fileNew), @"n", 0);
	MI(file, NPL(@"New Window\tAlt+N"), @selector(fileNewWindow), @"n", NSEventModifierFlagOption);
	MI(file, NPL(@"Open...\tCtrl+O"), @selector(fileOpen), @"o", 0);
	MI(file, NPL(@"Save\tCtrl+S"), @selector(fileSave), @"s", 0);
	MI(file, NPL(@"Save As...\tF6"), @selector(fileSaveAs), F6, 0);
	MI(file, NPL(@"Save Backup"), @selector(fileSaveBackup), @"", 0);
	MI(file, NPL(@"Save Copy...\tCtrl+F6"), @selector(fileSaveCopy), F6, NSEventModifierFlagCommand);
	MSep(file);
	NSMenuItem *fm = MI(file, NPL(@"File Mode"), nil, @"", 0);
	NSMenu *fms = M(NPL(@""));
	MI(fms, NPL(@"Read Only File"), @selector(toggleReadOnly), @"", 0);
	MI(fms, NPL(@"Read Only Mode\tF10"), @selector(toggleReadOnly), F10, 0);
	fm.submenu = fms;
	MI(file, NPL(@"Revert\tF5"), @selector(fileRevert), F5, 0);
	NSMenuItem *rl = MI(file, NPL(@"Reload"), nil, @"", 0);
	NSMenu *rls = M(NPL(@""));
	MI(rls, NPL(@"As UTF-8\tShift+F8"), @selector(reloadUTF8), @"", 0);
	MI(rls, NPL(@"As ANSI\tCtrl+Shift+A"), @selector(reloadANSI), @"", 0);
	MI(rls, NPL(@"As GBK"), @selector(reloadGBK), @"", 0);
	MSep(rls);
	MI(rls, NPL(@"With Encoding...\tF8"), @selector(reloadWithEncodingDialog), @"", 0);
	rl.submenu = rls;
	MSep(file);
	NSMenuItem *enc = MI(file, NPL(@"Encoding"), nil, @"", 0);
	NSMenu *encs = M(NPL(@""));
	MI(encs, NPL(@"ANSI"), @selector(setEncodingANSI), @"", 0).representedObject = @"ANSI";
	MI(encs, NPL(@"UTF-8"), @selector(setEncodingUTF8), @"", 0);
	MI(encs, NPL(@"UTF-8 BOM"), @selector(setEncodingUTF8BOM), @"", 0);
	MI(encs, NPL(@"UTF-16LE BOM"), @selector(setEncodingUTF16LE), @"", 0);
	MI(encs, NPL(@"UTF-16BE BOM"), @selector(setEncodingUTF16BE), @"", 0);
	enc.submenu = encs;
	NSMenuItem *eol = MI(file, NPL(@"Line Endings"), nil, @"", 0);
	NSMenu *eols = M(NPL(@""));
	MI(eols, NPL(@"Windows (CR+LF)"), @selector(setEOLCRLF), @"", 0);
	MI(eols, NPL(@"Unix/macOS (LF)"), @selector(setEOLLF), @"", 0);
	eol.submenu = eols;
	MSep(file);
	MI(file, NPL(@"Page Setup..."), @selector(filePageSetup), @"", 0);
	MI(file, NPL(@"Print...\tCtrl+P"), @selector(printDocument), @"p", 0);
	MSep(file);
	MI(file, NPL(@"Properties..."), @selector(fileProperties), @"", 0);
	MI(file, NPL(@"Open Containing Folder"), @selector(openContainingFolder), @"", 0);
	MSep(file);
	NSMenuItem *recent = MI(file, NPL(@"Recent (History)..."), nil, @"", 0);
	_recentMenu = M(NPL(@""));
	_recentMenu.delegate = self;
	recent.submenu = _recentMenu;
	MSep(file);
	MI(file, NPL(@"Exit\tAlt+F4"), @selector(terminate), @"", 0);
	{ NSMenuItem *_it_file = [mb addItemWithTitle:NPL(@"File") action:nil keyEquivalent:@""]; _it_file.submenu = file; }

	// ===== Edit =====
	NSMenu *edit = M(NPL(@"Edit"));
	MI(edit, NPL(@"Undo\tCtrl+Z"), @selector(undo:), @"z", 0);
	MI(edit, NPL(@"Redo\tCtrl+Y"), @selector(redo:), @"y", 0);
	MSep(edit);
	MI(edit, NPL(@"Cut\tCtrl+X"), @selector(cut:), @"x", 0);
	MI(edit, NPL(@"Copy\tCtrl+C"), @selector(copy:), @"c", 0);
	MI(edit, NPL(@"Paste\tCtrl+V"), @selector(paste:), @"v", 0);
	MI(edit, NPL(@"Delete\tDel"), @selector(editDelete), @"", 0);
	MI(edit, NPL(@"Select All\tCtrl+A"), @selector(selectAll:), @"a", 0);
	MI(edit, NPL(@"Swap\tCtrl+K"), @selector(editSwap), @"k", 0);
	MSep(edit);
	MI(edit, NPL(@"Clear Document"), @selector(editClearDocument), @"", 0);
	MI(edit, NPL(@"Clear Clipboard"), @selector(editClearClipboard), @"", 0);
	NSMenuItem *cc = MI(edit, NPL(@"Copy to Clipboard"), nil, @"", 0);
	NSMenu *ccs = M(NPL(@""));
	MI(ccs, NPL(@"File Name"), @selector(copyFileName), @"", 0);
	MI(ccs, NPL(@"Full Path Name\tAlt+Shift+F9"), @selector(copyFullPath), @"", 0);
	MSep(ccs);
	MI(ccs, NPL(@"Copy All\tAlt+A"), @selector(copyAll), @"a", NSEventModifierFlagOption);
	MI(ccs, NPL(@"Copy as RTF"), @selector(copyAsRTF), @"", 0);
	cc.submenu = ccs;
	MSep(edit);
	NSMenuItem *sel = MI(edit, NPL(@"Selection"), nil, @"", 0);
	NSMenu *sels = M(NPL(@""));
	MI(sels, NPL(@"Duplicate\tAlt+D"), @selector(editDuplicate), @"d", NSEventModifierFlagOption);
	MSep(sels);
	MI(sels, NPL(@"Toggle Line Comment\tCtrl+/"), @selector(editLineComment), @"/", 0);
	MI(sels, NPL(@"Indent\tTab"), @selector(editIndent), @"", 0);
	MI(sels, NPL(@"Unindent\tShift+Tab"), @selector(editUnindent), @"", 0);
	MSep(sels);
	MI(sels, NPL(@"Strip Trailing Blanks\tAlt+T"), @selector(editTrimTrailing), @"t", NSEventModifierFlagOption);
	MI(sels, NPL(@"Remove Blank Lines\tAlt+R"), @selector(editRemoveBlankLines), @"r", NSEventModifierFlagOption);
	sel.submenu = sels;
	NSMenuItem *lines = MI(edit, NPL(@"Lines"), nil, @"", 0);
	NSMenu *lss = M(NPL(@""));
	MI(lss, NPL(@"Move Up\tAlt+Up"), @selector(editMoveLineUp), [NSString stringWithFormat:@"%d", NSUpArrowFunctionKey], NSEventModifierFlagOption);
	MI(lss, NPL(@"Move Down\tAlt+Down"), @selector(editMoveLineDown), [NSString stringWithFormat:@"%d", NSDownArrowFunctionKey], NSEventModifierFlagOption);
	MI(lss, NPL(@"Transpose\tAlt+S"), @selector(editTranspose), @"s", NSEventModifierFlagOption);
	MSep(lss);
	MI(lss, NPL(@"Duplicate Line\tCtrl+D"), @selector(editDuplicateLine), @"d", 0);
	MI(lss, NPL(@"Cut Line\tCtrl+Shift+X"), @selector(editCutLine), @"x", NSEventModifierFlagCommand|NSEventModifierFlagShift);
	MI(lss, NPL(@"Copy Line\tCtrl+Shift+C"), @selector(editCopyLine), @"c", NSEventModifierFlagCommand|NSEventModifierFlagShift);
	MI(lss, NPL(@"Delete Line\tCtrl+Shift+D"), @selector(editDeleteLine), @"d", NSEventModifierFlagCommand|NSEventModifierFlagShift);
	MSep(lss);
	MI(lss, NPL(@"Join Lines\tCtrl+J"), @selector(editJoinLines), @"j", 0);
	MI(lss, NPL(@"Split Lines\tCtrl+I"), @selector(editSplitLines), @"i", 0);
	lines.submenu = lss;
	NSMenuItem *conv = MI(edit, NPL(@"Convert"), nil, @"", 0);
	NSMenu *cvs = M(NPL(@""));
	MI(cvs, NPL(@"UPPER CASE\tCtrl+Shift+U"), @selector(editUpper), @"u", NSEventModifierFlagCommand|NSEventModifierFlagShift);
	MI(cvs, NPL(@"lower case\tCtrl+U"), @selector(editLower), @"u", 0);
	MI(cvs, NPL(@"Invert Case"), @selector(editInvertCase), @"", 0);
	MI(cvs, NPL(@"Title Case"), @selector(editTitleCase), @"", 0);
	MSep(cvs);
	MI(cvs, NPL(@"Tabify Selection (Indent)\tCtrl+Alt+T"), @selector(editTabify), @"t", NSEventModifierFlagCommand|NSEventModifierFlagOption);
	MI(cvs, NPL(@"Untabify Selection (Indent)\tCtrl+Alt+S"), @selector(editUntabify), @"s", NSEventModifierFlagCommand|NSEventModifierFlagOption);
	conv.submenu = cvs;
	NSMenuItem *ins = MI(edit, NPL(@"Insert"), nil, @"", 0);
	NSMenu *insm = M(NPL(@""));
	MI(insm, NPL(@"Complete Word\tAlt+/"), @selector(editCompleteWord), @"/", NSEventModifierFlagOption);
	MSep(insm);
	MI(insm, NPL(@"New GUID"), @selector(insertGUID), @"", 0);
	MI(insm, NPL(@"File Name"), @selector(insertFileName), @"", 0);
	MSep(insm);
	MI(insm, NPL(@"Current Date Time"), @selector(insertDateTime), @"", 0);
	MI(insm, NPL(@"Unix Timestamp"), @selector(insertUnixTimestamp), @"", 0);
	ins.submenu = insm;
	{ NSMenuItem *_it_edit = [mb addItemWithTitle:NPL(@"Edit") action:nil keyEquivalent:@""]; _it_edit.submenu = edit; }

	// ===== Search =====
	NSMenu *search = M(NPL(@"Search"));
	MI(search, NPL(@"Find...\tCtrl+F"), @selector(searchFind), @"f", 0);
	MI(search, NPL(@"Save Find Text"), @selector(searchSaveFindText), @"", 0);
	MI(search, NPL(@"Find Next\tF3"), @selector(searchFindNext), F3, 0);
	MI(search, NPL(@"Find Previous\tShift+F3"), @selector(searchFindPrev), F3, NSEventModifierFlagShift);
	MI(search, NPL(@"Replace...\tCtrl+H"), @selector(searchReplace), @"h", 0);
	MI(search, NPL(@"Replace Next\tF4"), @selector(searchReplaceNext), [NSString stringWithFormat:@"%d", NSF4FunctionKey], 0);
	MSep(search);
	MI(search, NPL(@"Find Matching Brace\tCtrl+B"), @selector(searchFindMatchingBrace), @"b", 0);
	MI(search, NPL(@"Select Word"), @selector(searchSelectWord), @"", 0);
	MSep(search);
	NSMenuItem *bm = MI(search, NPL(@"Bookmarks"), nil, @"", 0);
	NSMenu *bms = M(NPL(@""));
	MI(bms, NPL(@"Toggle\tCtrl+F2"), @selector(bookmarkToggle), @"", NSEventModifierFlagCommand);
	MSep(bms);
	MI(bms, NPL(@"Goto Next\tF2"), @selector(bookmarkNext), [NSString stringWithFormat:@"%d", NSF2FunctionKey], 0);
	MI(bms, NPL(@"Goto Previous\tShift+F2"), @selector(bookmarkPrev), [NSString stringWithFormat:@"%d", NSF2FunctionKey], NSEventModifierFlagShift);
	MSep(bms);
	MI(bms, NPL(@"Clear All\tAlt+F2"), @selector(bookmarkClear), @"", 0);
	bm.submenu = bms;
	NSMenuItem *go = MI(search, NPL(@"Goto"), nil, @"", 0);
	NSMenu *gom = M(NPL(@""));
	MI(gom, NPL(@"Goto Line...\tCtrl+G"), @selector(gotoLine), @"g", 0);
	go.submenu = gom;
	{ NSMenuItem *_it_search = [mb addItemWithTitle:NPL(@"Search") action:nil keyEquivalent:@""]; _it_search.submenu = search; }

	// ===== View =====
	NSMenu *view = M(NPL(@"View"));
	_wordWrapItem = MI(view, NPL(@"Word Wrap\tCtrl+Shift+W"), @selector(viewWordWrap), @"w", NSEventModifierFlagCommand|NSEventModifierFlagShift);
	_wordWrapItem.state = NSControlStateValueOff;
	MI(view, NPL(@"Long Line Marker\tCtrl+Shift+L"), @selector(viewLongLineMarker), @"l", NSEventModifierFlagCommand|NSEventModifierFlagShift);
	MI(view, NPL(@"Indentation Guides\tCtrl+Shift+G"), @selector(viewIndentGuides), @"g", NSEventModifierFlagCommand|NSEventModifierFlagShift);
	MSep(view);
	MI(view, NPL(@"Show Whitespace\tCtrl+Shift+8"), @selector(viewWhitespace), @"8", NSEventModifierFlagCommand|NSEventModifierFlagShift);
	MI(view, NPL(@"Show Line Endings\tCtrl+Shift+9"), @selector(viewEOLs), @"9", NSEventModifierFlagCommand|NSEventModifierFlagShift);
	MSep(view);
	MI(view, NPL(@"Visual Brace Matching\tCtrl+Shift+V"), @selector(viewBraceMatch), @"v", NSEventModifierFlagCommand|NSEventModifierFlagShift);
	MSep(view);
	_lineNumbersItem = MI(view, NPL(@"Line Numbers\tCtrl+Shift+N"), @selector(viewLineNumbers), @"n", NSEventModifierFlagCommand|NSEventModifierFlagShift);
	_lineNumbersItem.state = NSControlStateValueOn;
	MI(view, NPL(@"Bookmark Margin\tCtrl+Shift+M"), @selector(viewBookmarkMargin), @"m", NSEventModifierFlagCommand|NSEventModifierFlagShift);
	MSep(view);
	MI(view, NPL(@"Show Code Folding"), @selector(viewCodeFolding), @"", 0);
	NSMenuItem *zm = MI(view, NPL(@"Zoom"), nil, @"", 0);
	NSMenu *zmm = M(NPL(@""));
	MI(zmm, NPL(@"Zoom In\tCtrl++"), @selector(viewZoomIn), @"+", 0);
	MI(zmm, NPL(@"Zoom Out\tCtrl+-"), @selector(viewZoomOut), @"-", 0);
	MI(zmm, NPL(@"Reset Zoom\tCtrl+\\"), @selector(viewZoomReset), @"\\", 0);
	zm.submenu = zmm;
	MI(view, NPL(@"Toggle Full Screen\tF11"), @selector(toggleFullScreen), [NSString stringWithFormat:@"%d", NSF11FunctionKey], 0);
	{ NSMenuItem *_it_view = [mb addItemWithTitle:NPL(@"View") action:nil keyEquivalent:@""]; _it_view.submenu = view; }

	// ===== Scheme =====
	NSMenu *scheme = M(NPL(@"Scheme"));
	MI(scheme, NPL(@"Syntax Scheme...\tF12"), @selector(schemeChoose), F12, 0);
	MI(scheme, NPL(@"Use Default Code Style\tShift+F12"), @selector(schemeReset), F12, NSEventModifierFlagShift);
	MSep(scheme);
	NSMenuItem *thm = MI(scheme, NPL(@"Style Theme"), nil, @"", 0);
	NSMenu *thms = M(NPL(@""));
	_themeAutoItem = MI(thms, NPL(@"Follow System"), @selector(themeAuto), @"", 0);
	_themeDefaultItem = MI(thms, NPL(@"Light"), @selector(themeDefault), @"", 0);
	_themeDarkItem = MI(thms, NPL(@"Dark"), @selector(themeDark), @"", 0);
	[self updateThemeMenuState];
	thm.submenu = thms;
	{ NSMenuItem *_it_scheme = [mb addItemWithTitle:NPL(@"Scheme") action:nil keyEquivalent:@""]; _it_scheme.submenu = scheme; }

	// ===== Settings =====
	NSMenu *settings = M(NPL(@"Settings"));
	MI(settings, NPL(@"Insert Tabs as Spaces"), @selector(settingsUseTabs), @"", 0);
	MI(settings, NPL(@"Tab Settings...\tCtrl+T"), @selector(settingsTabSettings), @"t", 0);
	MI(settings, NPL(@"Auto Completion Settings..."), @selector(settingsAutoCompletion), @"", 0);
	MSep(settings);
	NSMenuItem *lang = MI(settings, NPL(@"Language"), nil, @"", 0);
	NSMenu *langs = M(NPL(@""));
	_langChineseItem = MI(langs, @"简体中文", @selector(languageChinese), @"", 0);
	_langEnglishItem = MI(langs, @"English", @selector(languageEnglish), @"", 0);
	lang.submenu = langs;
	[self updateLanguageMenuState];
	NSMenuItem *ap = MI(settings, NPL(@"Appearance"), nil, @"", 0);
	NSMenu *aps = M(NPL(@""));
	MI(aps, NPL(@"Show Menu\tAlt+F11"), @selector(toggleMenuBar), @"", 0);
	MI(aps, NPL(@"Show Toolbar\tCtrl+F11"), @selector(toggleToolbar), @"", 0);
	MI(aps, NPL(@"Show Statusbar\tShift+F11"), @selector(toggleStatusBar), @"", 0);
	ap.submenu = aps;
	MI(settings, NPL(@"Save Settings On Exit"), @selector(settingsSaveOnExit), @"", 0);
	MI(settings, NPL(@"Save Settings Now\tF7"), @selector(settingsSaveNow), [NSString stringWithFormat:@"%d", NSF7FunctionKey], 0);
	{ NSMenuItem *_it_settings = [mb addItemWithTitle:NPL(@"Settings") action:nil keyEquivalent:@""]; _it_settings.submenu = settings; }

	// ===== Tools =====
	NSMenu *tools = M(NPL(@"Tools"));
	MI(tools, NPL(@"Execute Document\tCtrl+L"), @selector(toolsExecute), @"l", 0);
	MI(tools, NPL(@"Open Document With..."), @selector(toolsOpenWith), @"", 0);
	MI(tools, NPL(@"Run Command...\tCtrl+R"), @selector(toolsRunCommand), @"r", 0);
	MSep(tools);
	NSMenuItem *ws = MI(tools, NPL(@"Action on Selection"), nil, @"", 0);
	NSMenu *wsm = M(NPL(@""));
	MI(wsm, NPL(@"Open File, Folder, Link, etc."), @selector(actionOpenSelection), @"", 0);
	MI(wsm, NPL(@"Search with &Google"), @selector(actionSearchGoogle), @"", 0);
	ws.submenu = wsm;
	NSMenuItem *b64 = MI(tools, NPL(@"Base64"), nil, @"", 0);
	NSMenu *b64m = M(NPL(@""));
	MI(b64m, NPL(@"Standard Encode"), @selector(base64Encode), @"", 0);
	MI(b64m, NPL(@"URL Safe Encode"), @selector(base64URLSafeEncode), @"", 0);
	MI(b64m, NPL(@"Decode"), @selector(base64Decode), @"", 0);
	b64.submenu = b64m;
	NSMenuItem *webt = MI(tools, NPL(@"Web Tools"), nil, @"", 0);
	NSMenu *wtm = M(NPL(@""));
	MI(wtm, NPL(@"URL Encode\tCtrl+Shift+E"), @selector(urlEncode), @"e", NSEventModifierFlagCommand|NSEventModifierFlagShift);
	MI(wtm, NPL(@"URL Decode\tCtrl+Shift+R"), @selector(urlDecode), @"r", NSEventModifierFlagCommand|NSEventModifierFlagShift);
	MI(wtm, NPL(@"Escape HTML/XML Chars"), @selector(webEscapeHTML), @"", 0);
	MI(wtm, NPL(@"Unescape HTML/XML Chars"), @selector(webUnescapeHTML), @"", 0);
	webt.submenu = wtm;
	{ NSMenuItem *_it_tools = [mb addItemWithTitle:NPL(@"Tools") action:nil keyEquivalent:@""]; _it_tools.submenu = tools; }

	// ===== Help =====
	NSMenu *help = M(NPL(@"Help"));
	MI(help, NPL(@"Project Home"), @selector(helpHome), @"", 0);
	MI(help, NPL(@"About Notepad4"), @selector(orderFrontStandardAboutPanel:), @"", 0);
	{ NSMenuItem *_it_help = [mb addItemWithTitle:NPL(@"Help") action:nil keyEquivalent:@""]; _it_help.submenu = help; }

	_inWindowMenus = [NSMutableArray arrayWithObjects:file, edit, search, view, scheme, settings, tools, help, nil];
	NSMutableArray *titles = [NSMutableArray array];
	for (NSMenu *m in _inWindowMenus) [titles addObject:m.title];
	[self rebuildMenuBarButtons:titles];
	NSApp.mainMenu = [self buildAppMenu];
}

- (NSMenu *)buildAppMenu {
	NSMenu *appMenu = [[NSMenu alloc] initWithTitle:@"Notepad4"];
	[appMenu addItemWithTitle:NPL(@"About Notepad4") action:@selector(orderFrontStandardAboutPanel:) keyEquivalent:@""];
	[appMenu addItem:[NSMenuItem separatorItem]];
	NSMenuItem *svc = [appMenu addItemWithTitle:NPL(@"Services") action:nil keyEquivalent:@""];
	NSMenu *svcMenu = [[NSMenu alloc] initWithTitle:NPL(@"Services")];
	svc.submenu = svcMenu;
	NSApp.servicesMenu = svcMenu;
	[appMenu addItem:[NSMenuItem separatorItem]];
	[appMenu addItemWithTitle:NPL(@"Hide Notepad4") action:@selector(hide:) keyEquivalent:@"h"];
	NSMenuItem *ho = [appMenu addItemWithTitle:NPL(@"Hide Others") action:@selector(hideOtherApplications:) keyEquivalent:@"h"];
	ho.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagOption;
	[appMenu addItemWithTitle:NPL(@"Show All") action:@selector(unhideAllApplications:) keyEquivalent:@""];
	[appMenu addItem:[NSMenuItem separatorItem]];
	[appMenu addItemWithTitle:NPL(@"Quit Notepad4") action:@selector(terminate:) keyEquivalent:@"q"];
	NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:@"" action:nil keyEquivalent:@""];
	item.submenu = appMenu;
	NSMenu *main = [[NSMenu alloc] initWithTitle:@""];
	[main addItem:item];
	return main;
}

- (void)rebuildMenuBarButtons:(NSArray<NSString *> *)titles {
	for (NSView *v in [_menuBar.subviews copy]) [v removeFromSuperview];
	_menuBarButtons = [NSMutableArray array];
	NSView *prev = nil;
	for (NSUInteger i = 0; i < titles.count; i++) {
		NSButton *b = [NSButton buttonWithTitle:titles[i] target:self action:@selector(menuBarClicked:)];
		b.bordered = NO;
		b.font = [NSFont systemFontOfSize:12];
		b.contentTintColor = [NSColor labelColor];
		b.tag = (NSInteger)i;
		b.translatesAutoresizingMaskIntoConstraints = NO;
		[_menuBar addSubview:b];
		[b.centerYAnchor constraintEqualToAnchor:_menuBar.centerYAnchor].active = YES;
		[b.heightAnchor constraintEqualToConstant:18].active = YES;
		if (prev) [prev.trailingAnchor constraintEqualToAnchor:b.leadingAnchor constant:2].active = YES;
		else [_menuBar.leadingAnchor constraintEqualToAnchor:b.leadingAnchor constant:-6].active = YES;
		[_menuBarButtons addObject:b];
		prev = b;
	}
	if (prev) [_menuBar.trailingAnchor constraintGreaterThanOrEqualToAnchor:prev.trailingAnchor constant:6].active = YES;
}

- (void)menuBarClicked:(NSButton *)b {
	if (b.tag < 0 || (NSUInteger)b.tag >= _inWindowMenus.count) return;
	NSMenu *menu = _inWindowMenus[b.tag];
	b.wantsLayer = YES;
	b.layer.backgroundColor = [NSColor selectedContentBackgroundColor].CGColor;
	b.layer.cornerRadius = 4;
	[menu popUpMenuPositioningItem:nil atLocation:NSMakePoint(0, 0) inView:b];
	b.layer.backgroundColor = NULL;
}

static BOOL NPInvokeMatchingItem(NSMenu *menu, NSEvent *event, id editTarget) {
	const NSEventModifierFlags want = event.modifierFlags
		& (NSEventModifierFlagCommand | NSEventModifierFlagOption
		   | NSEventModifierFlagControl | NSEventModifierFlagShift);
	NSString *chars = event.charactersIgnoringModifiers.lowercaseString;
	if (chars.length == 0) return NO;
	for (NSMenuItem *it in menu.itemArray) {
		if (it.isSeparatorItem) continue;
		if (it.submenu && NPInvokeMatchingItem(it.submenu, event, editTarget)) return YES;
		if (it.keyEquivalent.length == 0 || !it.action) continue;
		const NSEventModifierFlags have = it.keyEquivalentModifierMask
			& (NSEventModifierFlagCommand | NSEventModifierFlagOption
			   | NSEventModifierFlagControl | NSEventModifierFlagShift);
		if (have != want) continue;
		if (![it.keyEquivalent.lowercaseString isEqualToString:chars]) continue;
		id target = it.target;
		if (!target) {
			SEL act = it.action;
			if (act == @selector(selectAll:) || act == @selector(cut:)
				|| act == @selector(copy:) || act == @selector(paste:)
				|| act == @selector(undo:) || act == @selector(redo:)
				|| act == @selector(delete:)) {
				target = editTarget;
			} else {
				target = [NSApp targetForAction:act to:nil from:it];
			}
			if (!target && editTarget) target = editTarget;
		}
		if (!target) continue;
		if ([target respondsToSelector:@selector(validateMenuItem:)]
			&& ![target validateMenuItem:it]) continue;
		return [NSApp sendAction:it.action to:target from:it];
	}
	return NO;
}

- (BOOL)handleKeyEquivalent:(NSEvent *)event {
	id editTarget = _document.editor.content;
	for (NSMenu *m in _inWindowMenus) {
		if (NPInvokeMatchingItem(m, event, editTarget)) return YES;
	}
	return NO;
}

- (void)installKeyEquivalentMonitor {
	if (_keyMonitor) return;
	__weak typeof(self) weakSelf = self;
	_keyMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown
		handler:^NSEvent *(NSEvent *event) {
			MainWindowController *s = weakSelf;
			if (!s) return event;
			if ([s handleKeyEquivalent:event]) return nil;
			return event;
		}];
}

- (NSArray<NSString *> *)inWindowMenuTitles {
	NSMutableArray *a = [NSMutableArray array];
	for (NSButton *b in _menuBarButtons) [a addObject:b.title ?: @""];
	return a;
}

- (void)dumpInWindowMenus:(NSMutableString *)out {
	for (NSMenu *m in _inWindowMenus) {
		[out appendFormat:@"%@\n", m.title];
		for (NSMenuItem *it in m.itemArray) {
			if (it.isSeparatorItem) continue;
			[out appendFormat:@"  %@\n", it.title];
		}
	}
}


- (EditorDocument *)editorDocument {
	return _document;
}
- (void)setEditorDocument:(EditorDocument *)doc {
	_document = doc;
}

#pragma mark - 状态与标题

- (void)refreshStatus {
	[_statusBar updateForDocument:_document];
}

// 对照 Notepad4 UpdateWindowTitle(): "* " + "文件名 [目录]" + " - Notepad4"
- (void)updateWindowTitle {
	NSMutableString *t = [NSMutableString string];
	if (_document.dirty) [t appendString:@"* "];
	if (_document.fileURL) {
		[t appendFormat:@"%@ [%@]", _document.fileURL.lastPathComponent,
			[_document.fileURL.path stringByDeletingLastPathComponent]];
	} else {
		[t appendString:NPL(@"Untitled")];
	}
	[t appendString:@" - Notepad4"];
	self.window.title = t;
}

- (void)docDirtyChanged:(NSNotification *)n {
	[self updateWindowTitle];
	[self refreshStatus];
}

#pragma mark - File

- (void)fileNew {
	self.editorDocument = [[EditorDocument alloc] initWithNewUntitled:1];
	[self swapEditor];
}
- (void)fileNewWindow {
	MainWindowController *wc = [[MainWindowController alloc] init];
	[wc showWindow:nil];
}
- (void)fileOpen {
	NSOpenPanel *panel = [NSOpenPanel openPanel];
	[panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse r) {
		if (r != NSModalResponseOK) return;
		EditorDocument *doc = [[EditorDocument alloc] initWithFileURL:panel.URL contents:@""];
		NSError *err = nil;
		if ([doc loadFromURL:panel.URL error:&err]) {
			self.editorDocument = doc;
			[self swapEditor];
			[self noteRecentFile:panel.URL];
		}
	}];
}
- (void)swapEditor {
	for (NSView *sub in _editorHost.subviews) [sub removeFromSuperview];
	_document.editor.translatesAutoresizingMaskIntoConstraints = NO;
	[_editorHost addSubview:_document.editor];
	[_editorHost.leadingAnchor constraintEqualToAnchor:_document.editor.leadingAnchor].active = YES;
	[_editorHost.trailingAnchor constraintEqualToAnchor:_document.editor.trailingAnchor].active = YES;
	[_editorHost.topAnchor constraintEqualToAnchor:_document.editor.topAnchor].active = YES;
	[_editorHost.bottomAnchor constraintEqualToAnchor:_document.editor.bottomAnchor].active = YES;
	[[NSNotificationCenter defaultCenter] removeObserver:self name:@"EditorDocumentDirtyChanged" object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(docDirtyChanged:) name:@"EditorDocumentDirtyChanged" object:_document];
	[self updateWindowTitle];
	[self refreshStatus];
	[self.window makeFirstResponder:[_document.editor content]];
}
- (BOOL)fileSave {
	if (!_document.fileURL) { [self fileSaveAs]; return YES; }
	NSError *err = nil;
	if (![_document saveToURL:_document.fileURL error:&err]) return NO;
	[self noteRecentFile:_document.fileURL];
	[self updateWindowTitle];
	return YES;
}
- (void)fileSaveAs {
	NSSavePanel *panel = [NSSavePanel savePanel];
	panel.nameFieldStringValue = _document.tabTitle ?: @"Untitled.txt";
	[panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse r) {
		if (r != NSModalResponseOK) return;
		NSError *err = nil;
		if ([self.editorDocument saveToURL:panel.URL error:&err]) {
			[self.editorDocument applyLexerForExtension:panel.URL.pathExtension.lowercaseString];
			[self updateWindowTitle];
			[self refreshStatus];
		}
	}];
}
- (void)fileSaveBackup {
	if (!_document.fileURL) { [self fileSaveCopy]; return; }
	NSURL *bak = [_document.fileURL URLByAppendingPathExtension:@"bak"];
	NSError *err = nil;
	[_document writeContentsToURL:bak updateIdentity:NO error:&err];
}
- (void)fileSaveCopy {
	NSSavePanel *panel = [NSSavePanel savePanel];
	panel.nameFieldStringValue = _document.tabTitle ?: @"Untitled.txt";
	[panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse r) {
		if (r != NSModalResponseOK) return;
		NSError *err = nil;
		[_document writeContentsToURL:panel.URL updateIdentity:NO error:&err];
	}];
}
- (void)fileRevert {
	if (_document.fileURL) {
		[_document reloadWithEncoding:_document.currentEncoding];
		[self refreshStatus];
	}
}
- (void)fileProperties {
	NSString *info = [NSString stringWithFormat:@"%@\n%@\n%@",
		_document.fileURL.path ?: @"(untitled)",
		_document.currentEncoding ?: @"UTF-8",
		_document.currentLexer ? @"lexer" : @"text"];
	NSAlert *a = [[NSAlert alloc] init];
	a.messageText = @"Properties";
	a.informativeText = info;
	[a runModal];
}
- (void)openContainingFolder {
	if (_document.fileURL) {
		[[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs:@[_document.fileURL]];
	}
}
- (void)printDocument {
	NSPrintOperation *op = [NSPrintOperation printOperationWithView:_document.editor];
	[op runOperation];
}

#pragma mark - Reload/Encoding

- (void)reloadUTF8 { [_document reloadWithEncoding:@"UTF-8"]; [self refreshStatus]; }
- (void)reloadANSI { [_document reloadWithEncoding:@"Latin-1"]; [self refreshStatus]; }
- (void)reloadGBK { [_document reloadWithEncoding:@"GBK"]; [self refreshStatus]; }
- (void)setEncodingUTF8 { [_document setSaveEncoding:@"UTF-8"]; [self refreshStatus]; }
- (void)setEncodingUTF8BOM { [_document setSaveEncoding:@"UTF-8"]; }
- (void)setEncodingUTF16LE { [_document setSaveEncoding:@"UTF-16LE"]; [self refreshStatus]; }
- (void)setEncodingUTF16BE { [_document setSaveEncoding:@"UTF-16BE"]; [self refreshStatus]; }
- (void)setEOLCRLF { [_document.editor message:SCI_CONVERTEOLS wParam:SC_EOL_CRLF lParam:0]; [self refreshStatus]; }
- (void)setEOLLF { [_document.editor message:SCI_CONVERTEOLS wParam:SC_EOL_LF lParam:0]; [self refreshStatus]; }

#pragma mark - Edit

- (void)editUndo { [_document.editor message:SCI_UNDO wParam:0 lParam:0]; [self refreshStatus]; }
- (void)editRedo { [_document.editor message:SCI_REDO wParam:0 lParam:0]; [self refreshStatus]; }
- (void)editCut { [_document.editor message:SCI_CUT wParam:0 lParam:0]; }
- (void)editCopy { [_document.editor message:SCI_COPY wParam:0 lParam:0]; }
- (void)editPaste { [_document.editor message:SCI_PASTE wParam:0 lParam:0]; }
- (void)editDelete { [_document.editor message:SCI_CLEAR wParam:0 lParam:0]; }
- (void)editSelectAll { [_document.editor message:SCI_SELECTALL wParam:0 lParam:0]; }
- (void)editClearDocument { [_document.editor message:SCI_CLEARALL wParam:0 lParam:0]; }
static NSString *NPLineCommentPrefix(const EDITLEXER *lex) {
	if (lex && (lex->lexerAttr & LexerAttr_NoLineComment)) return nil;
	const int lexer = lex ? lex->iLexer : SCLEX_NULL;
	switch (lexer) {
		case SCLEX_PYTHON: case SCLEX_PERL: case SCLEX_RUBY: case SCLEX_BASH:
		case SCLEX_CMAKE: case SCLEX_YAML: case SCLEX_PROPERTIES:
		case SCLEX_MAKEFILE: case SCLEX_TCL:
		case SCLEX_POWERSHELL: case SCLEX_BATCH:
			return @"#";
		case SCLEX_SQL: case SCLEX_LUA:
			return @"--";
		case SCLEX_VISUALBASIC:
			return @"'";
		case SCLEX_LISP: case SCLEX_ASM:
			return @";";
		case SCLEX_HTML: case SCLEX_XML: case SCLEX_NULL:
			return nil;
		default:
			return @"//";
	}
}
- (void)editLineComment {
	NSString *prefix = NPLineCommentPrefix(_document.currentLexer);
	if (!prefix.length) return;
	ScintillaView *e = _document.editor;
	const sptr_t selStart = [e message:SCI_GETSELECTIONSTART];
	const sptr_t selEnd = [e message:SCI_GETSELECTIONEND];
	const sptr_t first = [e message:SCI_LINEFROMPOSITION wParam:selStart];
	const sptr_t last = [e message:SCI_LINEFROMPOSITION wParam:(selEnd > selStart ? selEnd : selStart)];
	BOOL allCommented = YES;
	for (sptr_t l = first; l <= last; l++) {
		const sptr_t ls = [e message:SCI_POSITIONFROMLINE wParam:l];
		const sptr_t le = [e message:SCI_GETLINEENDPOSITION wParam:l];
		if (ls == le) continue;
		sptr_t q = ls;
		while (q < le) {
			const char c = (char)[e message:SCI_GETCHARAT wParam:q];
			if (c != ' ' && c != '\t') break;
			q++;
		}
		if (q == le) continue;
		BOOL match = YES;
		for (NSUInteger i = 0; i < prefix.length; i++) {
			if (q + (sptr_t)i >= le || (char)[e message:SCI_GETCHARAT wParam:q + (sptr_t)i] != [prefix characterAtIndex:i]) {
				match = NO; break;
			}
		}
		if (!match) { allCommented = NO; break; }
	}
	[e message:SCI_BEGINUNDOACTION wParam:0 lParam:0];
	for (sptr_t l = first; l <= last; l++) {
		const sptr_t ls = [e message:SCI_POSITIONFROMLINE wParam:l];
		const sptr_t le = [e message:SCI_GETLINEENDPOSITION wParam:l];
		if (ls == le) continue;
		sptr_t q = ls;
		while (q < le) {
			const char c = (char)[e message:SCI_GETCHARAT wParam:q];
			if (c != ' ' && c != '\t') break;
			q++;
		}
		if (q == le) continue;
		if (allCommented) {
			sptr_t del = q + (sptr_t)prefix.length;
			if (del < le && (char)[e message:SCI_GETCHARAT wParam:del] == ' ') del++;
			[e message:SCI_SETTARGETSTART wParam:q lParam:0];
			[e message:SCI_SETTARGETEND wParam:del lParam:0];
			[e message:SCI_REPLACETARGET wParam:0 lParam:(sptr_t)""];
		} else {
			[e message:SCI_SETTARGETSTART wParam:q lParam:0];
			[e message:SCI_SETTARGETEND wParam:q lParam:0];
			[e message:SCI_REPLACETARGET wParam:-1 lParam:(sptr_t)prefix.UTF8String];
		}
	}
	[e message:SCI_ENDUNDOACTION wParam:0 lParam:0];
	[self refreshStatus];
}
- (void)editIndent { [_document.editor message:SCI_TAB wParam:0 lParam:0]; }
- (void)editUnindent { [_document.editor message:SCI_BACKTAB wParam:0 lParam:0]; }
- (void)editTrimTrailing {
	ScintillaView *e = _document.editor;
	const sptr_t lines = [e message:SCI_GETLINECOUNT];
	[e message:SCI_BEGINUNDOACTION wParam:0 lParam:0];
	for (sptr_t l = 0; l < lines; l++) {
		[e message:SCI_TARGETFROMSELECTION wParam:0 lParam:0];
		const sptr_t start = [e message:SCI_POSITIONFROMLINE wParam:l];
		const sptr_t end = [e message:SCI_GETLINEENDPOSITION wParam:l];
		// 找行尾空白起点
		sptr_t p = end;
		while (p > start) {
			const char ch = (char)[e message:SCI_GETCHARAT wParam:p-1];
			if (ch == ' ' || ch == '\t') p--;
			else break;
		}
		if (p < end) {
			[e message:SCI_SETTARGETSTART wParam:p lParam:0];
			[e message:SCI_SETTARGETEND wParam:end lParam:0];
			[e message:SCI_REPLACETARGET wParam:0 lParam:(sptr_t)""];
		}
	}
	[e message:SCI_ENDUNDOACTION wParam:0 lParam:0];
}
- (void)editMoveLineUp { [_document.editor message:SCI_MOVESELECTEDLINESUP wParam:0 lParam:0]; }
- (void)editMoveLineDown { [_document.editor message:SCI_MOVESELECTEDLINESDOWN wParam:0 lParam:0]; }
- (void)editTranspose { [_document.editor message:SCI_LINETRANSPOSE wParam:0 lParam:0]; }
- (void)editDuplicateLine { [_document.editor message:SCI_LINEDUPLICATE wParam:0 lParam:0]; }
- (void)editCutLine { [_document.editor message:SCI_LINECUT wParam:0 lParam:0]; }
- (void)editCopyLine { [_document.editor message:SCI_LINECOPY wParam:0 lParam:0]; }
- (void)editDeleteLine { [_document.editor message:SCI_LINEDELETE wParam:0 lParam:0]; }
- (void)editJoinLines {
	ScintillaView *e = _document.editor;
	[e message:SCI_TARGETFROMSELECTION wParam:0 lParam:0];
	[e message:SCI_LINESJOIN wParam:0 lParam:0];
}
- (void)editSplitLines {
	ScintillaView *e = _document.editor;
	[e message:SCI_TARGETFROMSELECTION wParam:0 lParam:0];
	[e message:SCI_LINESSPLIT wParam:0 lParam:0];
}
- (void)editUpper { [_document.editor message:SCI_UPPERCASE wParam:0 lParam:0]; }
- (void)editLower { [_document.editor message:SCI_LOWERCASE wParam:0 lParam:0]; }
- (void)editCompleteWord { [_document completeWord]; }
- (void)insertGUID {
	NSString *guid = [NSUUID UUID].UUIDString.lowercaseString;
	[_document.editor message:SCI_REPLACESEL wParam:0 lParam:(sptr_t)guid.UTF8String];
}
- (void)insertDateTime {
	NSDateFormatter *f = [[NSDateFormatter alloc] init];
	f.dateFormat = @"yyyy-MM-dd HH:mm:ss";
	NSString *s = [f stringFromDate:[NSDate date]];
	[_document.editor message:SCI_REPLACESEL wParam:0 lParam:(sptr_t)s.UTF8String];
}

#pragma mark - Search

- (void)searchFind { [_findPanel showFind:NO]; }
- (void)searchReplace { [_findPanel showFind:YES]; }
- (void)searchFindNext { [_findPanel findNext:_document]; [self refreshStatus]; }
- (void)searchFindPrev { [_findPanel findPrevious:_document]; [self refreshStatus]; }
- (void)gotoLine {
	NSAlert *a = [[NSAlert alloc] init];
	a.messageText = @"Goto Line";
	NSTextField *input = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 200, 24)];
	a.accessoryView = input;
	[a addButtonWithTitle:@"Goto"];
	[a addButtonWithTitle:@"Cancel"];
	[a beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse r) {
		if (r != NSAlertFirstButtonReturn) return;
		long line = input.stringValue.longLongValue;
		if (line > 0) {
			[self.editorDocument.editor message:SCI_GOTOLINE wParam:line - 1 lParam:0];
			[self refreshStatus];
		}
	}];
}
- (void)bookmarkToggle {
	ScintillaView *e = _document.editor;
	const sptr_t line = [e message:SCI_LINEFROMPOSITION wParam:[e message:SCI_GETCURRENTPOS]];
	const sptr_t mark = [e message:SCI_MARKERGET wParam:line];
	if (mark & 2) [e message:SCI_MARKERDELETE wParam:line lParam:1];
	else [e message:SCI_MARKERADD wParam:line lParam:1];
}
- (void)bookmarkNext {
	ScintillaView *e = _document.editor;
	const sptr_t line = [e message:SCI_LINEFROMPOSITION wParam:[e message:SCI_GETCURRENTPOS]];
	const sptr_t next = [e message:SCI_MARKERNEXT wParam:line + 1 lParam:2];
	if (next >= 0) [e message:SCI_GOTOLINE wParam:next lParam:0];
	[self refreshStatus];
}
- (void)bookmarkPrev {
	ScintillaView *e = _document.editor;
	const sptr_t line = [e message:SCI_LINEFROMPOSITION wParam:[e message:SCI_GETCURRENTPOS]];
	const sptr_t prev = [e message:SCI_MARKERPREVIOUS wParam:line - 1 lParam:2];
	if (prev >= 0) [e message:SCI_GOTOLINE wParam:prev lParam:0];
	[self refreshStatus];
}
- (void)bookmarkClear { [_document.editor message:SCI_MARKERDELETEALL wParam:1 lParam:0]; }

#pragma mark - View

- (void)viewWordWrap {
	_wordWrapItem.state = (_wordWrapItem.state == NSControlStateValueOn) ? NSControlStateValueOff : NSControlStateValueOn;
	[_document.editor message:SCI_SETWRAPMODE wParam:(_wordWrapItem.state == NSControlStateValueOn) ? SC_WRAP_WORD : SC_WRAP_NONE lParam:0];
}
- (void)viewIndentGuides {
	ScintillaView *e = _document.editor;
	const sptr_t cur = [e message:SCI_GETINDENTATIONGUIDES];
	[e message:SCI_SETINDENTATIONGUIDES wParam:(cur ? SC_IV_NONE : SC_IV_LOOKBOTH) lParam:0];
}
- (void)viewWhitespace {
	ScintillaView *e = _document.editor;
	const sptr_t cur = [e message:SCI_GETVIEWWS];
	[e message:SCI_SETVIEWWS wParam:(cur ? SCWS_INVISIBLE : SCWS_VISIBLEALWAYS) lParam:0];
}
- (void)viewEOLs {
	ScintillaView *e = _document.editor;
	const sptr_t cur = [e message:SCI_GETVIEWEOL];
	[e message:SCI_SETVIEWEOL wParam:!cur lParam:0];
}
- (void)viewLineNumbers {
	_lineNumbersItem.state = (_lineNumbersItem.state == NSControlStateValueOn) ? NSControlStateValueOff : NSControlStateValueOn;
	[_document.editor message:SCI_SETMARGINWIDTHN wParam:0 lParam:(_lineNumbersItem.state == NSControlStateValueOn) ? 48 : 0];
}
- (void)viewCodeFolding {
	ScintillaView *e = _document.editor;
	const sptr_t cur = [e message:SCI_GETMARGINWIDTHN wParam:2];
	[e message:SCI_SETMARGINTYPEN wParam:2 lParam:SC_MARGIN_SYMBOL];
	[e message:SCI_SETMARGINMASKN wParam:2 lParam:SC_MASK_FOLDERS];
	[e message:SCI_SETMARGINWIDTHN wParam:2 lParam:cur ? 0 : 14];
	[e message:SCI_MARKERDEFINE wParam:SC_MARKNUM_FOLDER lParam:SC_MARK_BOXPLUS];
	[e message:SCI_MARKERDEFINE wParam:SC_MARKNUM_FOLDEROPEN lParam:SC_MARK_BOXMINUS];
	[e message:SCI_MARKERDEFINE wParam:SC_MARKNUM_FOLDERSUB lParam:SC_MARK_VLINE];
	[e message:SCI_MARKERDEFINE wParam:SC_MARKNUM_FOLDERTAIL lParam:SC_MARK_LCORNER];
	[e message:SCI_SETPROPERTY wParam:(sptr_t)"fold" lParam:(sptr_t)"1"];
	[e message:SCI_SETFOLDFLAGS wParam:16 lParam:0];
}
- (void)viewZoomIn { [_document.editor message:SCI_ZOOMIN wParam:0 lParam:0]; [self refreshStatus]; }
- (void)viewZoomOut { [_document.editor message:SCI_ZOOMOUT wParam:0 lParam:0]; [self refreshStatus]; }
- (void)viewZoomReset { [_document.editor message:SCI_SETZOOM wParam:0 lParam:0]; [self refreshStatus]; }
- (void)toggleFullScreen { [self.window toggleFullScreen:nil]; }
- (void)toggleStatusBar {
	_statusBar.hidden = !_statusBar.hidden;
}

#pragma mark - Scheme

- (void)schemeChoose { [self.window makeFirstResponder:_lexPopup]; }
- (void)schemeReset {
	if (_document.fileURL) {
		[_document applyLexerForExtension:_document.fileURL.pathExtension.lowercaseString];
		[self refreshStatus];
	}
}
- (void)schemeChanged:(NSPopUpButton *)sender {
	NSDictionary *info = sender.selectedItem.representedObject;
	NSString *exts = info[@"extensions"];
	NSString *first = [[exts componentsSeparatedByString:@";"] firstObject] ?: @"txt";
	[_document applyLexerForExtension:[first stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]];
	[self refreshStatus];
}
// 查找面板显示/隐藏（面板浮在编辑区之上，布局无需调整）
- (void)updateLanguageMenuState {
	const NPLanguage lang = NPLanguageGet();
	_langChineseItem.state = (lang == NPLanguageChinese) ? NSControlStateValueOn : NSControlStateValueOff;
	_langEnglishItem.state = (lang == NPLanguageEnglish) ? NSControlStateValueOn : NSControlStateValueOff;
}

// 切换界面语言：重建菜单 + 状态栏 + 查找面板 + 标题
- (void)applyLanguage:(NPLanguage)lang {
	NPLanguageSet(lang);
	[self buildMenu];
	[_statusBar applyLanguage];
	[_findPanel applyLanguage];
	[self updateWindowTitle];
	[self refreshStatus];
	[self.window.contentView setNeedsDisplay:YES];
}

- (void)languageChinese { [self applyLanguage:NPLanguageChinese]; }
- (void)languageEnglish { [self applyLanguage:NPLanguageEnglish]; }

- (void)updateThemeMenuState {
	const NPThemeMode mode = NPThemeModeGet();
	_themeAutoItem.state = (mode == NPThemeModeAuto) ? NSControlStateValueOn : NSControlStateValueOff;
	_themeDefaultItem.state = (mode == NPThemeModeLight) ? NSControlStateValueOn : NSControlStateValueOff;
	_themeDarkItem.state = (mode == NPThemeModeDark) ? NSControlStateValueOn : NSControlStateValueOff;
}

// 切换主题模式：写盘 + 设应用外观 + 重刷编辑器与 chrome
- (void)applyThemeMode:(NPThemeMode)mode {
	NPThemeModeSet(mode);
	[_document setTheme:NPThemeResolve(mode)];
	[self updateThemeMenuState];
	[self.window.contentView setNeedsDisplay:YES];
	[self refreshStatus];
}

- (void)themeAuto { [self applyThemeMode:NPThemeModeAuto]; }
- (void)themeDefault { [self applyThemeMode:NPThemeModeLight]; }
- (void)themeDark { [self applyThemeMode:NPThemeModeDark]; }

// 系统外观变化：仅跟随模式下重刷
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object
	change:(NSDictionary *)change context:(void *)context {
	if (object == NSApp && [keyPath isEqualToString:@"effectiveAppearance"]) {
		if (NPThemeModeGet() == NPThemeModeAuto) {
			[_document setTheme:NPThemeResolve(NPThemeModeAuto)];
			[self.window.contentView setNeedsDisplay:YES];
			[self refreshStatus];
		}
		return;
	}
	[super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
}


#pragma mark - 原 nyi 项实现
- (void)filePageSetup { [[NSPageLayout pageLayout] runModalWithPrintInfo:[NSPrintInfo sharedPrintInfo]]; }
- (void)toggleReadOnly {
	ScintillaView *e = _document.editor;
	[e message:SCI_SETREADONLY wParam:([e message:SCI_GETREADONLY] ? 0 : 1) lParam:0];
	[self refreshStatus];
}
- (void)reloadWithEncodingDialog {
	NSAlert *a = [[NSAlert alloc] init];
	a.messageText = NPL(@"Reload with Encoding");
	NSPopUpButton *pop = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(0, 0, 220, 26) pullsDown:NO];
	[pop addItemsWithTitles:@[@"UTF-8", @"UTF-16LE", @"UTF-16BE", @"GB18030", @"BIG5", @"Shift-JIS", @"Latin-1"]];
	a.accessoryView = pop;
	[a addButtonWithTitle:NPL(@"Reload")];
	[a addButtonWithTitle:NPL(@"Cancel")];
	[a beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse r) {
		if (r != NSAlertFirstButtonReturn) return;
		[_document reloadWithEncoding:pop.titleOfSelectedItem];
		[self refreshStatus];
	}];
}
- (void)setEncodingANSI { [_document setSaveEncoding:@"Latin-1"]; [self refreshStatus]; }
- (void)noteRecentFile:(NSURL *)url {
	if (!url.path.length) return;
	NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
	NSMutableArray *list = [([d arrayForKey:@"NP4RecentFiles"] ?: @[]) mutableCopy];
	[list removeObject:url.path];
	[list insertObject:url.path atIndex:0];
	if (list.count > 10) [list removeObjectsInRange:NSMakeRange(10, list.count - 10)];
	[d setObject:list forKey:@"NP4RecentFiles"];
}
- (void)openRecentFile:(NSMenuItem *)item {
	NSURL *url = [NSURL fileURLWithPath:item.representedObject];
	EditorDocument *doc = [[EditorDocument alloc] initWithFileURL:url contents:@""];
	NSError *err = nil;
	if ([doc loadFromURL:url error:&err]) {
		self.editorDocument = doc;
		[self swapEditor];
		[self noteRecentFile:url];
	}
}
- (void)menuNeedsUpdate:(NSMenu *)menu {
	if (menu != _recentMenu) return;
	[menu removeAllItems];
	NSArray<NSString *> *list = [[NSUserDefaults standardUserDefaults] arrayForKey:@"NP4RecentFiles"] ?: @[];
	if (!list.count) {
		NSMenuItem *empty = [menu addItemWithTitle:NPL(@"No recent files") action:nil keyEquivalent:@""];
		empty.enabled = NO;
		return;
	}
	for (NSString *path in list) {
		NSMenuItem *it = [menu addItemWithTitle:path.lastPathComponent action:@selector(openRecentFile:) keyEquivalent:@""];
		it.target = self; it.representedObject = path; it.toolTip = path;
	}
}
- (void)editSwap {
	ScintillaView *e = _document.editor;
	NSPasteboard *pb = [NSPasteboard generalPasteboard];
	NSString *clip = [pb stringForType:NSPasteboardTypeString] ?: @"";
	const sptr_t selStart = [e message:SCI_GETSELECTIONSTART];
	const sptr_t selEnd = [e message:SCI_GETSELECTIONEND];
	if (selStart == selEnd) {
		if (!clip.length) return;
		[e message:SCI_REPLACESEL wParam:0 lParam:(sptr_t)clip.UTF8String];
		[pb clearContents];
	} else {
		NSString *sel = [e selectedString] ?: @"";
		[e message:SCI_REPLACESEL wParam:0 lParam:(sptr_t)clip.UTF8String];
		[pb clearContents];
		if (sel.length) [pb setString:sel forType:NSPasteboardTypeString];
	}
	[self refreshStatus];
}
- (void)editClearClipboard { [[NSPasteboard generalPasteboard] clearContents]; }
- (void)copyFileName {
	NSString *name = _document.fileURL.lastPathComponent;
	if (name) { [[NSPasteboard generalPasteboard] clearContents]; [[NSPasteboard generalPasteboard] setString:name forType:NSPasteboardTypeString]; }
}
- (void)copyFullPath {
	NSString *path = _document.fileURL.path;
	if (path) { [[NSPasteboard generalPasteboard] clearContents]; [[NSPasteboard generalPasteboard] setString:path forType:NSPasteboardTypeString]; }
}
- (void)copyAll { [_document.editor message:SCI_COPYRANGE wParam:0 lParam:[_document.editor message:SCI_GETLENGTH]]; }
- (void)copyAsRTF {
	NSString *text = [_document.editor string];
	if (!text.length) return;
	NSAttributedString *as = [[NSAttributedString alloc] initWithString:text attributes:@{}];
	NSData *rtf = [as dataFromRange:NSMakeRange(0, as.length) documentAttributes:@{NSDocumentTypeDocumentAttribute: NSRTFTextDocumentType} error:nil];
	NSPasteboard *pb = [NSPasteboard generalPasteboard];
	[pb clearContents];
	[pb setString:text forType:NSPasteboardTypeString];
	if (rtf) [pb setData:rtf forType:NSRTFPboardType];
}
- (void)editDuplicate { [_document.editor message:SCI_SELECTIONDUPLICATE wParam:0 lParam:0]; }
- (void)editRemoveBlankLines {
	ScintillaView *e = _document.editor;
	const sptr_t first = [e message:SCI_LINEFROMPOSITION wParam:[e message:SCI_GETSELECTIONSTART]];
	const sptr_t last = [e message:SCI_LINEFROMPOSITION wParam:[e message:SCI_GETSELECTIONEND]];
	[e message:SCI_BEGINUNDOACTION wParam:0 lParam:0];
	for (sptr_t l = last; l >= first; l--) {
		const sptr_t ls = [e message:SCI_POSITIONFROMLINE wParam:l];
		const sptr_t le = [e message:SCI_GETLINEENDPOSITION wParam:l];
		BOOL blank = YES;
		for (sptr_t x = ls; x < le; x++) {
			const char c = (char)[e message:SCI_GETCHARAT wParam:x];
			if (c != ' ' && c != '\t') { blank = NO; break; }
		}
		if (!blank) continue;
		sptr_t delEnd = le;
		if (l < [e message:SCI_GETLINECOUNT] - 1) delEnd = [e message:SCI_POSITIONFROMLINE wParam:l + 1];
		[e message:SCI_SETTARGETSTART wParam:ls lParam:0];
		[e message:SCI_SETTARGETEND wParam:delEnd lParam:0];
		[e message:SCI_REPLACETARGET wParam:0 lParam:(sptr_t)""];
	}
	[e message:SCI_ENDUNDOACTION wParam:0 lParam:0];
}
- (void)editInvertCase {
	ScintillaView *e = _document.editor;
	NSString *sel = [e selectedString];
	if (!sel.length) return;
	NSMutableString *out = [NSMutableString stringWithCapacity:sel.length];
	for (NSUInteger i = 0; i < sel.length; i++) {
		NSString *ch = [sel substringWithRange:NSMakeRange(i, 1)];
		NSString *up = ch.uppercaseString, *lo = ch.lowercaseString;
		[out appendString:[ch isEqualToString:up] ? lo : up];
	}
	[e message:SCI_REPLACESEL wParam:0 lParam:(sptr_t)out.UTF8String];
}
- (void)editTitleCase {
	ScintillaView *e = _document.editor;
	NSString *sel = [e selectedString];
	if (!sel.length) return;
	[e message:SCI_REPLACESEL wParam:0 lParam:(sptr_t)sel.capitalizedString.UTF8String];
}
- (void)convertLeadingWhitespaceToTabs:(BOOL)toTabs {
	ScintillaView *e = _document.editor;
	const sptr_t tabWidth = [e message:SCI_GETTABWIDTH];
	if (tabWidth <= 0) return;
	const sptr_t first = [e message:SCI_LINEFROMPOSITION wParam:[e message:SCI_GETSELECTIONSTART]];
	const sptr_t last = [e message:SCI_LINEFROMPOSITION wParam:[e message:SCI_GETSELECTIONEND]];
	[e message:SCI_BEGINUNDOACTION wParam:0 lParam:0];
	for (sptr_t l = first; l <= last; l++) {
		const sptr_t ls = [e message:SCI_POSITIONFROMLINE wParam:l];
		sptr_t x = ls;
		while (x < [e message:SCI_GETLINEENDPOSITION wParam:l]) {
			const char c = (char)[e message:SCI_GETCHARAT wParam:x];
			if (c != ' ' && c != '\t') break;
			x++;
		}
		if (x == ls) continue;
		const char *raw = (const char *)[e message:SCI_GETRANGEPOINTER wParam:ls lParam:(x - ls)];
		if (!raw) continue;
		NSString *ws = [[NSString alloc] initWithBytes:raw length:(NSUInteger)(x - ls) encoding:NSUTF8StringEncoding];
		if (!ws) continue;
		NSMutableString *out = [NSMutableString string];
		if (toTabs) {
			sptr_t col = 0;
			for (NSUInteger i = 0; i < ws.length; i++) {
				if ([ws characterAtIndex:i] == '\t') { [out appendString:@"\t"]; col += tabWidth - (col % tabWidth); }
				else { col++; [out appendString:(col % tabWidth == 0) ? @"\t" : @" "]; }
			}
		} else {
			for (NSUInteger i = 0; i < ws.length; i++) {
				if ([ws characterAtIndex:i] == '\t') [out appendString:[@"" stringByPaddingToLength:tabWidth withString:@" " startingAtIndex:0]];
				else [out appendString:@" "];
			}
		}
		if ([out isEqualToString:ws]) continue;
		[e message:SCI_SETTARGETSTART wParam:ls lParam:0];
		[e message:SCI_SETTARGETEND wParam:x lParam:0];
		[e message:SCI_REPLACETARGET wParam:-1 lParam:(sptr_t)out.UTF8String];
	}
	[e message:SCI_ENDUNDOACTION wParam:0 lParam:0];
}
- (void)editTabify { [self convertLeadingWhitespaceToTabs:YES]; }
- (void)editUntabify { [self convertLeadingWhitespaceToTabs:NO]; }
- (void)insertFileName {
	NSString *name = _document.fileURL.lastPathComponent ?: NPL(@"Untitled");
	[_document.editor message:SCI_REPLACESEL wParam:0 lParam:(sptr_t)name.UTF8String];
}
- (void)insertUnixTimestamp {
	NSString *ts = [NSString stringWithFormat:@"%lld", (long long)[NSDate date].timeIntervalSince1970];
	[_document.editor message:SCI_REPLACESEL wParam:0 lParam:(sptr_t)ts.UTF8String];
}
- (void)searchSaveFindText {
	[[NSUserDefaults standardUserDefaults] setObject:([_findPanel currentFindText] ?: @"") forKey:@"NP4FindText"];
}
- (void)searchReplaceNext { [_findPanel replaceOne:_document]; [self refreshStatus]; }
- (void)searchFindMatchingBrace {
	ScintillaView *e = _document.editor;
	const sptr_t pos = [e message:SCI_GETCURRENTPOS];
	const sptr_t m = [e message:SCI_BRACEMATCH wParam:pos lParam:0];
	if (m >= 0) [e message:SCI_SETSEL wParam:pos lParam:m + 1];
}
- (void)searchSelectWord {
	ScintillaView *e = _document.editor;
	const sptr_t pos = [e message:SCI_GETCURRENTPOS];
	[e message:SCI_SETSEL wParam:[e message:SCI_WORDSTARTPOSITION wParam:pos lParam:1] lParam:[e message:SCI_WORDENDPOSITION wParam:pos lParam:1]];
}
- (void)viewLongLineMarker {
	ScintillaView *e = _document.editor;
	if ([e message:SCI_GETEDGEMODE] != EDGE_NONE) [e message:SCI_SETEDGEMODE wParam:EDGE_NONE lParam:0];
	else { [e message:SCI_SETEDGECOLUMN wParam:80 lParam:0]; [e message:SCI_SETEDGEMODE wParam:EDGE_LINE lParam:0]; }
}
- (void)viewBraceMatch {
	ScintillaView *e = _document.editor;
	static BOOL on = YES; on = !on;
	const sptr_t pos = [e message:SCI_GETCURRENTPOS];
	if (on) [e message:SCI_BRACEHIGHLIGHT wParam:pos lParam:[e message:SCI_BRACEMATCH wParam:pos lParam:0]];
	else [e message:SCI_BRACEHIGHLIGHT wParam:(sptr_t)-1 lParam:(sptr_t)-1];
}
- (void)viewBookmarkMargin {
	ScintillaView *e = _document.editor;
	const sptr_t w = [e message:SCI_GETMARGINWIDTHN wParam:1 lParam:0];
	[e message:SCI_SETMARGINWIDTHN wParam:1 lParam:(w > 0 ? 0 : 16)];
}
- (void)settingsUseTabs {
	ScintillaView *e = _document.editor;
	[e message:SCI_SETUSETABS wParam:([e message:SCI_GETUSETABS] ? 0 : 1) lParam:0];
}
- (void)settingsTabSettings {
	NSAlert *a = [[NSAlert alloc] init]; a.messageText = NPL(@"Tab Settings");
	NSView *box = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 260, 84)];
	NSTextField *tabLbl = [NSTextField labelWithString:NPL(@"Tab Width")]; tabLbl.frame = NSMakeRect(0, 56, 120, 20);
	NSTextField *tabVal = [[NSTextField alloc] initWithFrame:NSMakeRect(130, 54, 60, 24)];
	tabVal.integerValue = [_document.editor message:SCI_GETTABWIDTH];
	NSTextField *indLbl = [NSTextField labelWithString:NPL(@"Indent Width")]; indLbl.frame = NSMakeRect(0, 28, 120, 20);
	NSTextField *indVal = [[NSTextField alloc] initWithFrame:NSMakeRect(130, 26, 60, 24)];
	indVal.integerValue = [_document.editor message:SCI_GETINDENT];
	NSButton *useTabs = [NSButton checkboxWithTitle:NPL(@"Use Tabs") target:nil action:nil];
	useTabs.frame = NSMakeRect(0, 0, 200, 20);
	useTabs.state = ([_document.editor message:SCI_GETUSETABS] != 0) ? NSControlStateValueOn : NSControlStateValueOff;
	[box addSubview:tabLbl]; [box addSubview:tabVal]; [box addSubview:indLbl]; [box addSubview:indVal]; [box addSubview:useTabs];
	a.accessoryView = box; [a addButtonWithTitle:NPL(@"OK")]; [a addButtonWithTitle:NPL(@"Cancel")];
	[a beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse r) {
		if (r != NSAlertFirstButtonReturn) return;
		ScintillaView *e = _document.editor;
		if (tabVal.integerValue > 0) [e message:SCI_SETTABWIDTH wParam:tabVal.integerValue lParam:0];
		if (indVal.integerValue > 0) [e message:SCI_SETINDENT wParam:indVal.integerValue lParam:0];
		[e message:SCI_SETUSETABS wParam:(useTabs.state == NSControlStateValueOn ? 1 : 0) lParam:0];
	}];
}
- (void)settingsAutoCompletion {
	NSAlert *a = [[NSAlert alloc] init]; a.messageText = NPL(@"Auto Completion Settings");
	NSButton *onTyping = [NSButton checkboxWithTitle:NPL(@"Auto complete on typing") target:nil action:nil];
	onTyping.frame = NSMakeRect(0, 0, 260, 20);
	NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
	onTyping.state = ([d objectForKey:@"NP4AutoCompleteOnTyping"] == nil || [d boolForKey:@"NP4AutoCompleteOnTyping"]) ? NSControlStateValueOn : NSControlStateValueOff;
	a.accessoryView = onTyping; [a addButtonWithTitle:NPL(@"OK")]; [a addButtonWithTitle:NPL(@"Cancel")];
	[a beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse r) {
		if (r != NSAlertFirstButtonReturn) return;
		[d setBool:(onTyping.state == NSControlStateValueOn) forKey:@"NP4AutoCompleteOnTyping"];
	}];
}
- (void)settingsSaveOnExit {
	NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
	const BOOL cur = ([d objectForKey:@"NP4SaveOnExit"] == nil) || [d boolForKey:@"NP4SaveOnExit"];
	[d setBool:!cur forKey:@"NP4SaveOnExit"];
}
- (void)settingsSaveNow {
	[[NSUserDefaults standardUserDefaults] synchronize];
	NSAlert *a = [[NSAlert alloc] init]; a.messageText = NPL(@"Settings saved"); [a addButtonWithTitle:NPL(@"OK")];
	[a beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse r) {}];
}
- (void)toggleMenuBar { _menuBar.hidden = !_menuBar.hidden; }
- (void)toggleToolbar { _toolBar.hidden = !_toolBar.hidden; }
- (void)toolsExecute {
	NSURL *url = _document.fileURL;
	if (!url) {
		NSAlert *a = [[NSAlert alloc] init]; a.messageText = NPL(@"Save the file first");
		[a addButtonWithTitle:NPL(@"Save")]; [a addButtonWithTitle:NPL(@"Cancel")];
		[a beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse r) {
			if (r == NSAlertFirstButtonReturn && [self fileSave]) [[NSWorkspace sharedWorkspace] openURL:_document.fileURL];
		}];
		return;
	}
	[[NSWorkspace sharedWorkspace] openURL:url];
}
- (void)toolsOpenWith {
	NSURL *url = _document.fileURL;
	if (!url) { [self toolsExecute]; return; }
	NSOpenPanel *op = [NSOpenPanel openPanel];
	op.canChooseFiles = YES; op.canChooseDirectories = NO;
	op.directoryURL = [NSURL fileURLWithPath:@"/Applications"]; op.allowedFileTypes = @[@"app"];
	[op beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse r) {
		if (r != NSModalResponseOK) return;
		[[NSWorkspace sharedWorkspace] openURLs:@[url] withApplicationAtURL:op.URLs.firstObject
			configuration:[NSWorkspaceOpenConfiguration configuration] completionHandler:nil];
	}];
}
- (void)toolsRunCommand {
	NSAlert *a = [[NSAlert alloc] init]; a.messageText = NPL(@"Run Command");
	NSTextField *cmd = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 380, 24)];
	cmd.stringValue = [[NSUserDefaults standardUserDefaults] stringForKey:@"NP4RunCommand"] ?: @"";
	cmd.placeholderString = @"echo $(FullPath)"; a.accessoryView = cmd;
	[a addButtonWithTitle:NPL(@"OK")]; [a addButtonWithTitle:NPL(@"Cancel")];
	[a beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse r) {
		if (r != NSAlertFirstButtonReturn || !cmd.stringValue.length) return;
		[[NSUserDefaults standardUserDefaults] setObject:cmd.stringValue forKey:@"NP4RunCommand"];
		NSString *line = cmd.stringValue;
		NSString *path = _document.fileURL.path ?: @"";
		line = [line stringByReplacingOccurrencesOfString:@"$(FullPath)" withString:path];
		line = [line stringByReplacingOccurrencesOfString:@"$(FileName)" withString:_document.fileURL.lastPathComponent ?: @""];
		NSTask *task = [[NSTask alloc] init]; task.launchPath = @"/bin/sh"; task.arguments = @[@"-c", line];
		NSPipe *pipe = [NSPipe pipe]; task.standardOutput = pipe; task.standardError = pipe;
		@try { [task launch]; [task waitUntilExit]; } @catch (NSException *ex) { return; }
		NSString *text = [[NSString alloc] initWithData:[pipe.fileHandleForReading readDataToEndOfFile] encoding:NSUTF8StringEncoding] ?: @"";
		NSAlert *res = [[NSAlert alloc] init];
		res.messageText = [NSString stringWithFormat:NPL(@"Command exited with status %d"), task.terminationStatus];
		res.informativeText = text.length > 4000 ? [text substringToIndex:4000] : text;
		[res addButtonWithTitle:NPL(@"OK")];
		[res beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse rr) {}];
	}];
}
- (void)actionOpenSelection {
	NSString *sel = [[_document.editor selectedString] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if (!sel.length) return;
	NSURL *url = ([sel hasPrefix:@"http://"] || [sel hasPrefix:@"https://"] || [sel hasPrefix:@"file://"]) ? [NSURL URLWithString:sel] : [NSURL fileURLWithPath:[sel stringByExpandingTildeInPath]];
	if (url) [[NSWorkspace sharedWorkspace] openURL:url];
}
- (void)actionSearchGoogle {
	NSString *sel = [_document.editor selectedString];
	if (!sel.length) return;
	NSString *q = [sel stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
	[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:[@"https://www.google.com/search?q=" stringByAppendingString:q ?: @""]]];
}
- (void)base64URLSafeEncode {
	NSString *sel = [_document.editor selectedString];
	if (!sel.length) return;
	NSString *b64 = [[sel dataUsingEncoding:NSUTF8StringEncoding] base64EncodedStringWithOptions:0];
	b64 = [[[b64 stringByReplacingOccurrencesOfString:@"+" withString:@"-"] stringByReplacingOccurrencesOfString:@"/" withString:@"_"] stringByReplacingOccurrencesOfString:@"=" withString:@""];
	[_document.editor message:SCI_REPLACESEL wParam:0 lParam:(sptr_t)b64.UTF8String];
}
- (void)webEscapeHTML {
	NSString *sel = [_document.editor selectedString];
	if (!sel.length) return;
	NSString *x = [[[[[sel stringByReplacingOccurrencesOfString:@"&" withString:@"&amp;"] stringByReplacingOccurrencesOfString:@"<" withString:@"&lt;"] stringByReplacingOccurrencesOfString:@">" withString:@"&gt;"] stringByReplacingOccurrencesOfString:@"\"" withString:@"&quot;"] stringByReplacingOccurrencesOfString:@"'" withString:@"&#39;"];
	[_document.editor message:SCI_REPLACESEL wParam:0 lParam:(sptr_t)x.UTF8String];
}
- (void)webUnescapeHTML {
	NSString *sel = [_document.editor selectedString];
	if (!sel.length) return;
	NSString *x = [[[[[sel stringByReplacingOccurrencesOfString:@"&lt;" withString:@"<"] stringByReplacingOccurrencesOfString:@"&gt;" withString:@">"] stringByReplacingOccurrencesOfString:@"&quot;" withString:@"\""] stringByReplacingOccurrencesOfString:@"&#39;" withString:@"'"] stringByReplacingOccurrencesOfString:@"&amp;" withString:@"&"];
	[_document.editor message:SCI_REPLACESEL wParam:0 lParam:(sptr_t)x.UTF8String];
}

#pragma mark - Tools

- (void)base64Encode {
	NSString *sel = [_document.editor selectedString];
	if (!sel.length) return;
	NSString *b64 = [[sel dataUsingEncoding:NSUTF8StringEncoding] base64EncodedStringWithOptions:0];
	[_document.editor message:SCI_REPLACESEL wParam:0 lParam:(sptr_t)b64.UTF8String];
}
- (void)base64Decode {
	NSString *sel = [_document.editor selectedString];
	if (!sel.length) return;
	NSData *d = [[NSData alloc] initWithBase64EncodedString:sel options:0];
	NSString *s = d ? [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] : nil;
	if (s) [_document.editor message:SCI_REPLACESEL wParam:0 lParam:(sptr_t)s.UTF8String];
}
- (void)urlEncode {
	NSString *sel = [_document.editor selectedString];
	if (!sel.length) return;
	NSString *s = [sel stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
	[_document.editor message:SCI_REPLACESEL wParam:0 lParam:(sptr_t)s.UTF8String];
}
- (void)urlDecode {
	NSString *sel = [_document.editor selectedString];
	if (!sel.length) return;
	NSString *s = [sel stringByRemovingPercentEncoding];
	if (s) [_document.editor message:SCI_REPLACESEL wParam:0 lParam:(sptr_t)s.UTF8String];
}
- (void)helpHome {
	[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"https://github.com/zufuliu/notepad4"]];
}

- (void)nyi {
	NSLog(@"[Notepad4-mac] action not yet implemented");
}

#pragma mark - NSWindowDelegate

- (BOOL)windowShouldClose:(NSWindow *)sender {
	if (_document.dirty) {
		NSAlert *a = [[NSAlert alloc] init];
		a.messageText = @"Save changes?";
		a.informativeText = @"The document has unsaved changes.";
		[a addButtonWithTitle:@"Save"];
		[a addButtonWithTitle:@"Don't Save"];
		[a addButtonWithTitle:@"Cancel"];
		[a beginSheetModalForWindow:sender completionHandler:^(NSModalResponse r) {
			if (r == NSAlertFirstButtonReturn) { if ([self fileSave]) [sender performClose:nil]; }
			else if (r == NSAlertSecondButtonReturn) [sender performClose:nil];
		}];
		return NO;
	}
	return YES;
}

@end
