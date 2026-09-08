#import "MainWindowController.h"
#import "FindReplacePanel.h"
#import "StatusBarView.h"
#import "SciLexer.h"
#import "EditLexer.h"
#import "LexerRegistry.h"
#import "Scintilla.h"

@implementation MainWindowController {
	FindReplacePanel *_findPanel;
	NSView *_editorHost;
	NSPopUpButton *_lexPopup;
	NSMenuItem *_wordWrapItem;
	NSMenuItem *_lineNumbersItem;
	StatusBarView *_statusBar;
	EditorDocument *_document;
}
@dynamic document;

- (instancetype)init {
	NSWindow *win = [[NSWindow alloc]
		initWithContentRect:NSMakeRect(140, 140, 900, 620)
		styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
			   NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable)
		backing:NSBackingStoreBuffered defer:NO];
	win.title = @"Untitled - Notepad4";
	win.minSize = NSMakeSize(400, 280);
	self = [super initWithWindow:win];
	if (self) {
		win.delegate = self;
		win.windowController = self;
		_document = [[EditorDocument alloc] initWithNewUntitled:1];
		[self buildUI:win];
		[self buildMenu];   // 按 Notepad4.rc 原文复刻
		[self refreshStatus];
		[self updateWindowTitle];
	}
	return self;
}

#pragma mark - 布局（工具栏 / 编辑器 / 状态栏，单文档无标签）

- (void)buildUI:(NSWindow *)win {
	NSView *root = [[NSView alloc] initWithFrame:win.contentView.bounds];
	root.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
	win.contentView = root;

	// ---- 工具栏：一排 16px 小图标 + 竖分隔线（对照 v24.07HD 截图）----
	NSView *bar = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 900, 30)];
	bar.wantsLayer = YES;
	bar.layer.backgroundColor = [NSColor controlBackgroundColor].CGColor;
	bar.translatesAutoresizingMaskIntoConstraints = NO;
	[root addSubview:bar];

	NSButton * (^TB)(NSString *sym, SEL act, NSString *tip) = ^NSButton *(NSString *sym, SEL act, NSString *tip) {
		NSButton *b = [NSButton buttonWithImage:
			([NSImage imageWithSystemSymbolName:sym accessibilityDescription:nil]
			 ?: [NSImage imageNamed:NSImageNameSmartBadgeTemplate])
			target:self action:act];
		b.imageScaling = NSImageScaleProportionallyDown;
		b.bezelStyle = NSBezelStyleTexturedRounded;
		b.toolTip = tip;
		b.translatesAutoresizingMaskIntoConstraints = NO;
		[b.widthAnchor constraintEqualToConstant:28].active = YES;
		[b.heightAnchor constraintEqualToConstant:24].active = YES;
		return b;
	};
	NSView * (^SEP)(void) = ^NSView *(void) {
		NSView *s = [[NSView alloc] initWithFrame:NSZeroRect];
		s.wantsLayer = YES;
		s.layer.backgroundColor = [NSColor separatorColor].CGColor;
		s.translatesAutoresizingMaskIntoConstraints = NO;
		[s.widthAnchor constraintEqualToConstant:1].active = YES;
		[s.heightAnchor constraintEqualToConstant:18].active = YES;
		return s;
	};

	// 顺序对照截图：New | Open▾ | Save | SaveAs | Print | PrintPreview | ─ | Undo | Redo | ─ |
	// Cut | Copy | Paste | ─ | Find | FindNext | ─ | Wrap | Folding | ─ | Reload
	NSArray *items = @[
		TB(@"doc", @selector(fileNew), @"New (Ctrl+N)"),
		TB(@"folder", @selector(fileOpen), @"Open... (Ctrl+O)"),
		TB(@"square.and.arrow.down", @selector(fileSave), @"Save (Ctrl+S)"),
		TB(@"square.and.arrow.down.on.square", @selector(fileSaveAs), @"Save As... (F6)"),
		TB(@"printer", @selector(printDocument), @"Print... (Ctrl+P)"),
		SEP(),
		TB(@"arrow.uturn.backward", @selector(editUndo), @"Undo (Ctrl+Z)"),
		TB(@"arrow.uturn.forward", @selector(editRedo), @"Redo (Ctrl+Y)"),
		SEP(),
		TB(@"scissors", @selector(editCut), @"Cut (Ctrl+X)"),
		TB(@"doc.on.doc", @selector(editCopy), @"Copy (Ctrl+C)"),
		TB(@"doc.on.clipboard", @selector(editPaste), @"Paste (Ctrl+V)"),
		SEP(),
		TB(@"magnifyingglass", @selector(searchFind), @"Find... (Ctrl+F)"),
		TB(@"arrow.down.right", @selector(searchFindNext), @"Find Next (F3)"),
		TB(@"arrow.left.arrow.right.square", @selector(searchReplace), @"Replace... (Ctrl+H)"),
		SEP(),
		TB(@"text.justify", @selector(viewWordWrap), @"Word Wrap (Ctrl+Shift+W)"),
		TB(@"chevron.left.forwardslash.chevron.right", @selector(viewCodeFolding), @"Code Folding"),
		TB(@"arrow.clockwise", @selector(fileRevert), @"Reload (F5)"),
	];

	// 水平排开
	NSView *prev = nil;
	for (NSView *v in items) {
		[bar addSubview:v];
		if (!prev) {
			[bar.leadingAnchor constraintEqualToAnchor:v.leadingAnchor constant:2].active = YES;
		} else {
			[prev.trailingAnchor constraintEqualToAnchor:v.leadingAnchor constant:2].active = YES;
		}
		[v.centerYAnchor constraintEqualToAnchor:bar.centerYAnchor].active = YES;
		prev = v;
	}
	// 右侧：词法器下拉（截图最右是循环箭头=reload，下拉在工具栏末尾之外；但 F12 Scheme 更常用，放这）
	NSPopUpButton *lex = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
	lex.translatesAutoresizingMaskIntoConstraints = NO;
	for (NSDictionary *info in [LexerRegistry allLexersInfo]) {
		[lex addItemWithTitle:info[@"name"]];
		lex.lastItem.representedObject = info;
	}
	[bar addSubview:lex];
	[prev.trailingAnchor constraintEqualToAnchor:lex.leadingAnchor constant:8].active = YES;
	[lex.centerYAnchor constraintEqualToAnchor:bar.centerYAnchor].active = YES;
	[bar.trailingAnchor constraintEqualToAnchor:lex.trailingAnchor constant:4].active = YES;
	[lex.widthAnchor constraintEqualToConstant:150].active = YES;
	_lexPopup = lex;

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
	[root.leadingAnchor constraintEqualToAnchor:bar.leadingAnchor].active = YES;
	[root.trailingAnchor constraintEqualToAnchor:bar.trailingAnchor].active = YES;
	[root.topAnchor constraintEqualToAnchor:bar.topAnchor].active = YES;
	[bar.heightAnchor constraintEqualToConstant:30].active = YES;

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
	NSMenuItem *appItem = [mb addItemWithTitle:@"Notepad4" action:nil keyEquivalent:@""];
	NSMenu *appMenu = M(@"");
	[appMenu addItemWithTitle:@"About Notepad4" action:@selector(orderFrontStandardAboutPanel:) keyEquivalent:@""];
	MSep(appMenu);
	[appMenu addItemWithTitle:@"Hide Notepad4" action:@selector(hide:) keyEquivalent:@"h"];
	[appMenu addItemWithTitle:@"Hide Others" action:@selector(hideOtherApplications:) keyEquivalent:@"h"].keyEquivalentModifierMask = NSEventModifierFlagCommand|NSEventModifierFlagOption;
	[appMenu addItemWithTitle:@"Show All" action:@selector(unhideAllApplications:) keyEquivalent:@""];
	MSep(appMenu);
	[appMenu addItemWithTitle:@"Quit Notepad4" action:@selector(terminate:) keyEquivalent:@"q"];
	appItem.submenu = appMenu;

	NSString *F3 = [NSString stringWithFormat:@"%d", NSF3FunctionKey];
	NSString *F5 = [NSString stringWithFormat:@"%d", NSF5FunctionKey];
	NSString *F6 = [NSString stringWithFormat:@"%d", NSF6FunctionKey];
	NSString *F10 = [NSString stringWithFormat:@"%d", NSF10FunctionKey];
	NSString *F12 = [NSString stringWithFormat:@"%d", NSF12FunctionKey];

	// ===== File =====
	NSMenu *file = M(@"File");
	MI(file, @"New\tCtrl+N", @selector(fileNew), @"n", 0);
	MI(file, @"New Window\tAlt+N", @selector(fileNewWindow), @"n", NSEventModifierFlagOption);
	MI(file, @"Open...\tCtrl+O", @selector(fileOpen), @"o", 0);
	MI(file, @"Save\tCtrl+S", @selector(fileSave), @"s", 0);
	MI(file, @"Save As...\tF6", @selector(fileSaveAs), F6, 0);
	MI(file, @"Save Backup", @selector(fileSaveBackup), @"", 0);
	MI(file, @"Save Copy...\tCtrl+F6", @selector(fileSaveCopy), F6, NSEventModifierFlagCommand);
	MSep(file);
	NSMenuItem *fm = MI(file, @"File Mode", nil, @"", 0);
	NSMenu *fms = M(@"");
	MI(fms, @"Read Only File", @selector(nyi), @"", 0);
	MI(fms, @"Read Only Mode\tF10", @selector(nyi), F10, 0);
	fm.submenu = fms;
	MI(file, @"Revert\tF5", @selector(fileRevert), F5, 0);
	NSMenuItem *rl = MI(file, @"Reload", nil, @"", 0);
	NSMenu *rls = M(@"");
	MI(rls, @"As UTF-8\tShift+F8", @selector(reloadUTF8), @"", 0);
	MI(rls, @"As ANSI\tCtrl+Shift+A", @selector(reloadANSI), @"", 0);
	MI(rls, @"As GBK", @selector(reloadGBK), @"", 0);
	MSep(rls);
	MI(rls, @"With Encoding...\tF8", @selector(nyi), @"", 0);
	rl.submenu = rls;
	MSep(file);
	NSMenuItem *enc = MI(file, @"Encoding", nil, @"", 0);
	NSMenu *encs = M(@"");
	MI(encs, @"ANSI", @selector(nyi), @"", 0).representedObject = @"ANSI";
	MI(encs, @"UTF-8", @selector(setEncodingUTF8), @"", 0);
	MI(encs, @"UTF-8 BOM", @selector(setEncodingUTF8BOM), @"", 0);
	MI(encs, @"UTF-16LE BOM", @selector(setEncodingUTF16LE), @"", 0);
	MI(encs, @"UTF-16BE BOM", @selector(setEncodingUTF16BE), @"", 0);
	enc.submenu = encs;
	NSMenuItem *eol = MI(file, @"Line Endings", nil, @"", 0);
	NSMenu *eols = M(@"");
	MI(eols, @"Windows (CR+LF)", @selector(setEOLCRLF), @"", 0);
	MI(eols, @"Unix/macOS (LF)", @selector(setEOLLF), @"", 0);
	eol.submenu = eols;
	MSep(file);
	MI(file, @"Page Setup...", @selector(nyi), @"", 0);
	MI(file, @"Print...\tCtrl+P", @selector(printDocument), @"p", 0);
	MSep(file);
	MI(file, @"Properties...", @selector(fileProperties), @"", 0);
	MI(file, @"Open Containing Folder", @selector(openContainingFolder), @"", 0);
	MSep(file);
	MI(file, @"Recent (History)...\tAlt+H", @selector(nyi), @"", 0);
	MSep(file);
	MI(file, @"Exit\tAlt+F4", @selector(terminate), @"", 0);
	{ NSMenuItem *_it_file = [mb addItemWithTitle:@"File" action:nil keyEquivalent:@""]; _it_file.submenu = file; }

	// ===== Edit =====
	NSMenu *edit = M(@"Edit");
	MI(edit, @"Undo\tCtrl+Z", @selector(editUndo), @"z", 0);
	MI(edit, @"Redo\tCtrl+Y", @selector(editRedo), @"y", 0);
	MSep(edit);
	MI(edit, @"Cut\tCtrl+X", @selector(editCut), @"x", 0);
	MI(edit, @"Copy\tCtrl+C", @selector(editCopy), @"c", 0);
	MI(edit, @"Paste\tCtrl+V", @selector(editPaste), @"v", 0);
	MI(edit, @"Delete\tDel", @selector(editDelete), @"", 0);
	MI(edit, @"Select All\tCtrl+A", @selector(editSelectAll), @"a", 0);
	MI(edit, @"Swap\tCtrl+K", @selector(nyi), @"k", 0);
	MSep(edit);
	MI(edit, @"Clear Document", @selector(editClearDocument), @"", 0);
	MI(edit, @"Clear Clipboard", @selector(nyi), @"", 0);
	NSMenuItem *cc = MI(edit, @"Copy to Clipboard", nil, @"", 0);
	NSMenu *ccs = M(@"");
	MI(ccs, @"File Name", @selector(nyi), @"", 0);
	MI(ccs, @"Full Path Name\tAlt+Shift+F9", @selector(nyi), @"", 0);
	MSep(ccs);
	MI(ccs, @"Copy All\tAlt+A", @selector(nyi), @"a", NSEventModifierFlagOption);
	MI(ccs, @"Copy as RTF", @selector(nyi), @"", 0);
	cc.submenu = ccs;
	MSep(edit);
	NSMenuItem *sel = MI(edit, @"Selection", nil, @"", 0);
	NSMenu *sels = M(@"");
	MI(sels, @"Duplicate\tAlt+D", @selector(nyi), @"d", NSEventModifierFlagOption);
	MSep(sels);
	MI(sels, @"Toggle Line Comment\tCtrl+/", @selector(editLineComment), @"/", 0);
	MI(sels, @"Indent\tTab", @selector(editIndent), @"", 0);
	MI(sels, @"Unindent\tShift+Tab", @selector(editUnindent), @"", 0);
	MSep(sels);
	MI(sels, @"Strip Trailing Blanks\tAlt+T", @selector(editTrimTrailing), @"t", NSEventModifierFlagOption);
	MI(sels, @"Remove Blank Lines\tAlt+R", @selector(nyi), @"r", NSEventModifierFlagOption);
	sel.submenu = sels;
	NSMenuItem *lines = MI(edit, @"Lines", nil, @"", 0);
	NSMenu *lss = M(@"");
	MI(lss, @"Move Up\tAlt+Up", @selector(editMoveLineUp), [NSString stringWithFormat:@"%d", NSUpArrowFunctionKey], NSEventModifierFlagOption);
	MI(lss, @"Move Down\tAlt+Down", @selector(editMoveLineDown), [NSString stringWithFormat:@"%d", NSDownArrowFunctionKey], NSEventModifierFlagOption);
	MI(lss, @"Transpose\tAlt+S", @selector(editTranspose), @"s", NSEventModifierFlagOption);
	MSep(lss);
	MI(lss, @"Duplicate Line\tCtrl+D", @selector(editDuplicateLine), @"d", 0);
	MI(lss, @"Cut Line\tCtrl+Shift+X", @selector(editCutLine), @"x", NSEventModifierFlagCommand|NSEventModifierFlagShift);
	MI(lss, @"Copy Line\tCtrl+Shift+C", @selector(editCopyLine), @"c", NSEventModifierFlagCommand|NSEventModifierFlagShift);
	MI(lss, @"Delete Line\tCtrl+Shift+D", @selector(editDeleteLine), @"d", NSEventModifierFlagCommand|NSEventModifierFlagShift);
	MSep(lss);
	MI(lss, @"Join Lines\tCtrl+J", @selector(editJoinLines), @"j", 0);
	MI(lss, @"Split Lines\tCtrl+I", @selector(editSplitLines), @"i", 0);
	lines.submenu = lss;
	NSMenuItem *conv = MI(edit, @"Convert", nil, @"", 0);
	NSMenu *cvs = M(@"");
	MI(cvs, @"UPPER CASE\tCtrl+Shift+U", @selector(editUpper), @"u", NSEventModifierFlagCommand|NSEventModifierFlagShift);
	MI(cvs, @"lower case\tCtrl+U", @selector(editLower), @"u", 0);
	MI(cvs, @"Invert Case", @selector(nyi), @"", 0);
	MI(cvs, @"Title Case", @selector(nyi), @"", 0);
	MSep(cvs);
	MI(cvs, @"Tabify Selection (Indent)\tCtrl+Alt+T", @selector(nyi), @"t", NSEventModifierFlagCommand|NSEventModifierFlagOption);
	MI(cvs, @"Untabify Selection (Indent)\tCtrl+Alt+S", @selector(nyi), @"s", NSEventModifierFlagCommand|NSEventModifierFlagOption);
	conv.submenu = cvs;
	NSMenuItem *ins = MI(edit, @"Insert", nil, @"", 0);
	NSMenu *insm = M(@"");
	MI(insm, @"Complete Word\tAlt+/", @selector(editCompleteWord), @"/", NSEventModifierFlagOption);
	MSep(insm);
	MI(insm, @"New GUID", @selector(insertGUID), @"", 0);
	MI(insm, @"File Name", @selector(nyi), @"", 0);
	MSep(insm);
	MI(insm, @"Current Date Time", @selector(insertDateTime), @"", 0);
	MI(insm, @"Unix Timestamp", @selector(nyi), @"", 0);
	ins.submenu = insm;
	{ NSMenuItem *_it_edit = [mb addItemWithTitle:@"Edit" action:nil keyEquivalent:@""]; _it_edit.submenu = edit; }

	// ===== Search =====
	NSMenu *search = M(@"Search");
	MI(search, @"Find...\tCtrl+F", @selector(searchFind), @"f", 0);
	MI(search, @"Save Find Text", @selector(nyi), @"", 0);
	MI(search, @"Find Next\tF3", @selector(searchFindNext), F3, 0);
	MI(search, @"Find Previous\tShift+F3", @selector(searchFindPrev), F3, NSEventModifierFlagShift);
	MI(search, @"Replace...\tCtrl+H", @selector(searchReplace), @"h", 0);
	MI(search, @"Replace Next\tF4", @selector(nyi), [NSString stringWithFormat:@"%d", NSF4FunctionKey], 0);
	MSep(search);
	MI(search, @"Find Matching Brace\tCtrl+B", @selector(nyi), @"b", 0);
	MI(search, @"Select Word", @selector(nyi), @"", 0);
	MSep(search);
	NSMenuItem *bm = MI(search, @"Bookmarks", nil, @"", 0);
	NSMenu *bms = M(@"");
	MI(bms, @"Toggle\tCtrl+F2", @selector(bookmarkToggle), @"", NSEventModifierFlagCommand);
	MSep(bms);
	MI(bms, @"Goto Next\tF2", @selector(bookmarkNext), [NSString stringWithFormat:@"%d", NSF2FunctionKey], 0);
	MI(bms, @"Goto Previous\tShift+F2", @selector(bookmarkPrev), [NSString stringWithFormat:@"%d", NSF2FunctionKey], NSEventModifierFlagShift);
	MSep(bms);
	MI(bms, @"Clear All\tAlt+F2", @selector(bookmarkClear), @"", 0);
	bm.submenu = bms;
	NSMenuItem *go = MI(search, @"Goto", nil, @"", 0);
	NSMenu *gom = M(@"");
	MI(gom, @"Goto Line...\tCtrl+G", @selector(gotoLine), @"g", 0);
	go.submenu = gom;
	{ NSMenuItem *_it_search = [mb addItemWithTitle:@"Search" action:nil keyEquivalent:@""]; _it_search.submenu = search; }

	// ===== View =====
	NSMenu *view = M(@"View");
	_wordWrapItem = MI(view, @"Word Wrap\tCtrl+Shift+W", @selector(viewWordWrap), @"w", NSEventModifierFlagCommand|NSEventModifierFlagShift);
	_wordWrapItem.state = NSControlStateValueOff;
	MI(view, @"Long Line Marker\tCtrl+Shift+L", @selector(nyi), @"l", NSEventModifierFlagCommand|NSEventModifierFlagShift);
	MI(view, @"Indentation Guides\tCtrl+Shift+G", @selector(viewIndentGuides), @"g", NSEventModifierFlagCommand|NSEventModifierFlagShift);
	MSep(view);
	MI(view, @"Show Whitespace\tCtrl+Shift+8", @selector(viewWhitespace), @"8", NSEventModifierFlagCommand|NSEventModifierFlagShift);
	MI(view, @"Show Line Endings\tCtrl+Shift+9", @selector(viewEOLs), @"9", NSEventModifierFlagCommand|NSEventModifierFlagShift);
	MSep(view);
	MI(view, @"Visual Brace Matching\tCtrl+Shift+V", @selector(nyi), @"v", NSEventModifierFlagCommand|NSEventModifierFlagShift);
	MSep(view);
	_lineNumbersItem = MI(view, @"Line Numbers\tCtrl+Shift+N", @selector(viewLineNumbers), @"n", NSEventModifierFlagCommand|NSEventModifierFlagShift);
	_lineNumbersItem.state = NSControlStateValueOn;
	MI(view, @"Bookmark Margin\tCtrl+Shift+M", @selector(nyi), @"m", NSEventModifierFlagCommand|NSEventModifierFlagShift);
	MSep(view);
	MI(view, @"Show Code Folding", @selector(viewCodeFolding), @"", 0);
	NSMenuItem *zm = MI(view, @"Zoom", nil, @"", 0);
	NSMenu *zmm = M(@"");
	MI(zmm, @"Zoom In\tCtrl++", @selector(viewZoomIn), @"+", 0);
	MI(zmm, @"Zoom Out\tCtrl+-", @selector(viewZoomOut), @"-", 0);
	MI(zmm, @"Reset Zoom\tCtrl+\\", @selector(viewZoomReset), @"\\", 0);
	zm.submenu = zmm;
	MI(view, @"Toggle Full Screen\tF11", @selector(toggleFullScreen), [NSString stringWithFormat:@"%d", NSF11FunctionKey], 0);
	{ NSMenuItem *_it_view = [mb addItemWithTitle:@"View" action:nil keyEquivalent:@""]; _it_view.submenu = view; }

	// ===== Scheme =====
	NSMenu *scheme = M(@"Scheme");
	MI(scheme, @"Syntax Scheme...\tF12", @selector(schemeChoose), F12, 0);
	MI(scheme, @"Use Default Code Style\tShift+F12", @selector(schemeReset), F12, NSEventModifierFlagShift);
	MSep(scheme);
	NSMenuItem *thm = MI(scheme, @"Style Theme", nil, @"", 0);
	NSMenu *thms = M(@"");
	MI(thms, @"Default", @selector(themeDefault), @"", 0);
	MI(thms, @"Dark", @selector(themeDark), @"", 0);
	thm.submenu = thms;
	{ NSMenuItem *_it_scheme = [mb addItemWithTitle:@"Scheme" action:nil keyEquivalent:@""]; _it_scheme.submenu = scheme; }

	// ===== Settings =====
	NSMenu *settings = M(@"Settings");
	MI(settings, @"Insert Tabs as Spaces", @selector(nyi), @"", 0);
	MI(settings, @"Tab Settings...\tCtrl+T", @selector(nyi), @"t", 0);
	MI(settings, @"Auto Completion Settings...", @selector(nyi), @"", 0);
	MSep(settings);
	NSMenuItem *ap = MI(settings, @"Appearance", nil, @"", 0);
	NSMenu *aps = M(@"");
	MI(aps, @"Show Menu\tAlt+F11", @selector(nyi), @"", 0);
	MI(aps, @"Show Toolbar\tCtrl+F11", @selector(nyi), @"", 0);
	MI(aps, @"Show Statusbar\tShift+F11", @selector(toggleStatusBar), @"", 0);
	ap.submenu = aps;
	MI(settings, @"Save Settings On Exit", @selector(nyi), @"", 0);
	MI(settings, @"Save Settings Now\tF7", @selector(nyi), [NSString stringWithFormat:@"%d", NSF7FunctionKey], 0);
	{ NSMenuItem *_it_settings = [mb addItemWithTitle:@"Settings" action:nil keyEquivalent:@""]; _it_settings.submenu = settings; }

	// ===== Tools =====
	NSMenu *tools = M(@"Tools");
	MI(tools, @"Execute Document\tCtrl+L", @selector(nyi), @"l", 0);
	MI(tools, @"Open Document With...", @selector(nyi), @"", 0);
	MI(tools, @"Run Command...\tCtrl+R", @selector(nyi), @"r", 0);
	MSep(tools);
	NSMenuItem *ws = MI(tools, @"Action on Selection", nil, @"", 0);
	NSMenu *wsm = M(@"");
	MI(wsm, @"Open File, Folder, Link, etc.", @selector(nyi), @"", 0);
	MI(wsm, @"Search with &Google", @selector(nyi), @"", 0);
	ws.submenu = wsm;
	NSMenuItem *b64 = MI(tools, @"Base64", nil, @"", 0);
	NSMenu *b64m = M(@"");
	MI(b64m, @"Standard Encode", @selector(base64Encode), @"", 0);
	MI(b64m, @"URL Safe Encode", @selector(nyi), @"", 0);
	MI(b64m, @"Decode", @selector(base64Decode), @"", 0);
	b64.submenu = b64m;
	NSMenuItem *webt = MI(tools, @"Web Tools", nil, @"", 0);
	NSMenu *wtm = M(@"");
	MI(wtm, @"URL Encode\tCtrl+Shift+E", @selector(urlEncode), @"e", NSEventModifierFlagCommand|NSEventModifierFlagShift);
	MI(wtm, @"URL Decode\tCtrl+Shift+R", @selector(urlDecode), @"r", NSEventModifierFlagCommand|NSEventModifierFlagShift);
	MI(wtm, @"Escape HTML/XML Chars", @selector(nyi), @"", 0);
	MI(wtm, @"Unescape HTML/XML Chars", @selector(nyi), @"", 0);
	webt.submenu = wtm;
	{ NSMenuItem *_it_tools = [mb addItemWithTitle:@"Tools" action:nil keyEquivalent:@""]; _it_tools.submenu = tools; }

	// ===== Help =====
	NSMenu *help = M(@"Help");
	MI(help, @"Project Home", @selector(helpHome), @"", 0);
	MI(help, @"About Notepad4", @selector(orderFrontStandardAboutPanel:), @"", 0);
	{ NSMenuItem *_it_help = [mb addItemWithTitle:@"Help" action:nil keyEquivalent:@""]; _it_help.submenu = help; }

	NSApp.mainMenu = mb;
}

- (EditorDocument *)document {
	return _document;
}
- (void)setDocument:(EditorDocument *)doc {
	_document = doc;
}

#pragma mark - 状态与标题

- (void)refreshStatus {
	[_statusBar updateForDocument:_document];
}

- (void)updateWindowTitle {
	NSString *base = _document.fileURL.lastPathComponent ?: @"Untitled";
	NSString *prefix = _document.dirty ? @"*" : @"";
	self.window.title = [NSString stringWithFormat:@"%@%@ - Notepad4", prefix, base];
}

- (void)docDirtyChanged:(NSNotification *)n {
	[self updateWindowTitle];
	[self refreshStatus];
}

#pragma mark - File

- (void)fileNew {
	self.document = [[EditorDocument alloc] initWithNewUntitled:1];
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
			self.document = doc;
			[self swapEditor];
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
	[self updateWindowTitle];
	return YES;
}
- (void)fileSaveAs {
	NSSavePanel *panel = [NSSavePanel savePanel];
	panel.nameFieldStringValue = _document.tabTitle ?: @"Untitled.txt";
	[panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse r) {
		if (r != NSModalResponseOK) return;
		NSError *err = nil;
		if ([self.document saveToURL:panel.URL error:&err]) {
			[self.document applyLexerForExtension:panel.URL.pathExtension.lowercaseString];
			[self updateWindowTitle];
			[self refreshStatus];
		}
	}];
}
- (void)fileSaveBackup {}
- (void)fileSaveCopy {}
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
- (void)editLineComment { /* 需要词法器 line-comment 配置，后续接 */ }
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
- (void)editCompleteWord { /* 手动触发补全 */ }
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
			[self.document.editor message:SCI_GOTOLINE wParam:line - 1 lParam:0];
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
- (void)themeDefault {}
- (void)themeDark {}

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
