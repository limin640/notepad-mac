#import "MainWindowController.h"
#import "FindReplacePanel.h"
#import "StatusBarView.h"
#import "SciLexer.h"
#import "EditLexer.h"
#import "LexerRegistry.h"

static NSString * const kUntitledCounterKey = @"kUntitledCounter";

@interface MainWindowController ()
@property (nonatomic, strong) NSToolbar *toolbar;
@property (nonatomic, strong) StatusBarView *statusBar;
@property (nonatomic, strong) NSTabView *tabView;
@property (nonatomic, strong) NSMenuItem *wrapItem;
@property (nonatomic, strong) NSMenuItem *lineNumbersItem;
@property (nonatomic, strong) NSMenuItem *indentItem;
@property (nonatomic, strong) NSMenuItem *statusItem;
@property (nonatomic, strong) NSPopUpButton *lex;
@end

@implementation MainWindowController {
	FindReplacePanel *_findPanel;
	NSInteger _untitledCounter;
}

- (instancetype)init {
	NSWindow *win = [[NSWindow alloc]
		initWithContentRect:NSMakeRect(120, 120, 1000, 680)
		styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
			   NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable)
		backing:NSBackingStoreBuffered defer:NO];
	win.title = @"Notepad4";
	win.minSize = NSMakeSize(480, 320);
	self = [super initWithWindow:win];
	if (self) {
		win.delegate = self;
		win.windowController = self;
		[self buildMenu];
		[self buildUI:win];
		[self newTab];
	}
	return self;
}

#pragma mark - UI 构建

- (void)buildUI:(NSWindow *)win {
	// 根容器：上工具栏区 / 中标签+编辑 / 下状态栏
	NSView *root = [[NSView alloc] initWithFrame:win.contentView.bounds];
	root.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
	win.contentView = root;

	// 工具栏（复刻 Windows 版按钮排布，symbol 图标）
	NSArray *fileSeg = @[[NSImage imageWithSystemSymbolName:@"doc.badge.plus" accessibilityDescription:nil],
		[NSImage imageWithSystemSymbolName:@"folder" accessibilityDescription:nil],
		[NSImage imageWithSystemSymbolName:@"square.and.arrow.down" accessibilityDescription:nil]];
	NSSegmentedControl *segFile = [NSSegmentedControl segmentedControlWithImages:fileSeg
		trackingMode:NSSegmentSwitchTrackingMomentary target:self action:@selector(toolbarFileAction:)];
	segFile.segmentStyle = NSSegmentStyleSeparated;

	NSSegmentedControl *segUndo = [NSSegmentedControl segmentedControlWithImages:@[
		[NSImage imageWithSystemSymbolName:@"arrow.uturn.backward" accessibilityDescription:nil],
		[NSImage imageWithSystemSymbolName:@"arrow.uturn.forward" accessibilityDescription:nil]]
		trackingMode:NSSegmentSwitchTrackingMomentary target:self action:@selector(toolbarUndoAction:)];
	segUndo.segmentStyle = NSSegmentStyleSeparated;

	NSSegmentedControl *segClipboard = [NSSegmentedControl segmentedControlWithImages:@[
		[NSImage imageWithSystemSymbolName:@"scissors" accessibilityDescription:nil],
		[NSImage imageWithSystemSymbolName:@"doc.on.doc" accessibilityDescription:nil],
		[NSImage imageWithSystemSymbolName:@"doc.on.clipboard" accessibilityDescription:nil]]
		trackingMode:NSSegmentSwitchTrackingMomentary target:self action:@selector(toolbarClipboardAction:)];
	segClipboard.segmentStyle = NSSegmentStyleSeparated;

	NSSegmentedControl *segFind = [NSSegmentedControl segmentedControlWithImages:@[
		[NSImage imageWithSystemSymbolName:@"magnifyingglass" accessibilityDescription:nil],
		[NSImage imageWithSystemSymbolName:@"arrow.right.arrow.left.square" accessibilityDescription:nil]]
		trackingMode:NSSegmentSwitchTrackingMomentary target:self action:@selector(toolbarFindAction:)];
	segFind.segmentStyle = NSSegmentStyleSeparated;

	NSSegmentedControl *segZoom = [NSSegmentedControl segmentedControlWithImages:@[
		[NSImage imageWithSystemSymbolName:@"minus.magnifyingglass" accessibilityDescription:nil],
		[NSImage imageWithSystemSymbolName:@"plus.magnifyingglass" accessibilityDescription:nil]]
		trackingMode:NSSegmentSwitchTrackingMomentary target:self action:@selector(toolbarZoomAction:)];
	segZoom.segmentStyle = NSSegmentStyleSeparated;

	// 词法器选择（F12 对应）
	NSPopUpButton *lexerPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(0,0,180,26) pullsDown:NO];
	_lex = lexerPopup;
	for (NSDictionary *info in [LexerRegistry allLexersInfo]) {
		[lexerPopup addItemWithTitle:info[@"name"]];
		lexerPopup.lastItem.representedObject = info;
	}

	NSStackView *bar = [NSStackView stackViewWithViews:@[segFile, segUndo, segClipboard, segFind, segZoom, lexerPopup]];
	bar.orientation = NSUserInterfaceLayoutOrientationHorizontal;
	bar.spacing = 12;
	bar.edgeInsets = NSEdgeInsetsMake(6, 12, 6, 12);
	bar.translatesAutoresizingMaskIntoConstraints = NO;
	bar.wantsLayer = YES;
	bar.layer.backgroundColor = [NSColor windowBackgroundColor].CGColor;
	[root addSubview:bar];

	// 标签页
	_tabView = [[NSTabView alloc] initWithFrame:NSZeroRect];
	_tabView.delegate = self;
	_tabView.tabViewType = NSTopTabsBezelBorder;
	_tabView.translatesAutoresizingMaskIntoConstraints = NO;
	[root addSubview:_tabView];

	// 状态栏
	_statusBar = [[StatusBarView alloc] initWithFrame:NSMakeRect(0, 0, 600, 22)];
	_statusBar.translatesAutoresizingMaskIntoConstraints = NO;
	[root addSubview:_statusBar];

	// 锚点布局：bar 顶部 38 / tabs 中间 / status 底部 22
	[root.leadingAnchor constraintEqualToAnchor:bar.leadingAnchor].active = YES;
	[root.trailingAnchor constraintEqualToAnchor:bar.trailingAnchor].active = YES;
	[root.topAnchor constraintEqualToAnchor:bar.topAnchor].active = YES;
	[bar.heightAnchor constraintEqualToConstant:40].active = YES;

	[root.leadingAnchor constraintEqualToAnchor:_tabView.leadingAnchor].active = YES;
	[root.trailingAnchor constraintEqualToAnchor:_tabView.trailingAnchor].active = YES;
	[bar.bottomAnchor constraintEqualToAnchor:_tabView.topAnchor].active = YES;

	[root.leadingAnchor constraintEqualToAnchor:_statusBar.leadingAnchor].active = YES;
	[root.trailingAnchor constraintEqualToAnchor:_statusBar.trailingAnchor].active = YES;
	[_statusBar.heightAnchor constraintEqualToConstant:22].active = YES;
	[_tabView.bottomAnchor constraintEqualToAnchor:_statusBar.topAnchor].active = YES;
	[root.bottomAnchor constraintEqualToAnchor:_statusBar.bottomAnchor].active = YES;

	// 查找面板（悬浮于编辑区底部之上）
	_findPanel = [[FindReplacePanel alloc] initWithFrame:NSMakeRect(0, 0, 600, 84)];
	[_findPanel attachToWindow:win];
}

#pragma mark - 菜单（复刻 Windows 版：文件/编辑/搜索/查看/帮助）

- (void)buildMenu {
	NSMenu *menubar = [[NSMenu alloc] init];

	// App 菜单
	NSMenuItem *appItem = [menubar addItemWithTitle:@"Notepad4" action:nil keyEquivalent:@""];
	NSMenu *appMenu = [[NSMenu alloc] init];
	[appMenu addItemWithTitle:@"关于 Notepad4" action:@selector(orderFrontStandardAboutPanel:) keyEquivalent:@""];
	[appMenu addItem:[NSMenuItem separatorItem]];
	[appMenu addItemWithTitle:@"隐藏 Notepad4" action:@selector(hide:) keyEquivalent:@"h"];
	[appMenu addItemWithTitle:@"隐藏其它" action:@selector(hideOtherApplications:) keyEquivalent:@"h"].keyEquivalentModifierMask = NSEventModifierFlagCommand|NSEventModifierFlagOption;
	[appMenu addItemWithTitle:@"显示全部" action:@selector(unhideAllApplications:) keyEquivalent:@""];
	[appMenu addItem:[NSMenuItem separatorItem]];
	[appMenu addItemWithTitle:@"退出 Notepad4" action:@selector(terminate:) keyEquivalent:@"q"];
	appItem.submenu = appMenu;

	// 文件
	NSMenuItem *fileItem = [menubar addItemWithTitle:@"文件(F)" action:nil keyEquivalent:@""];
	NSMenu *fileMenu = [[NSMenu alloc] init];
	[fileMenu addItemWithTitle:@"新建\tCtrl+N" action:@selector(newTab) keyEquivalent:@"n"];
	[fileMenu addItemWithTitle:@"新建窗口" action:@selector(newWindow) keyEquivalent:@""];
	[fileMenu addItemWithTitle:@"打开...\tCtrl+O" action:@selector(openDocument) keyEquivalent:@"o"];
	[fileMenu addItemWithTitle:@"重新加载\tF5" action:@selector(revertDocument) keyEquivalent:[NSString stringWithFormat:@"%d", NSF5FunctionKey]];
	[fileMenu addItemWithTitle:@"在外部程序中打开" action:@selector(openExternal) keyEquivalent:@""];
	[fileMenu addItem:[NSMenuItem separatorItem]];
	[fileMenu addItemWithTitle:@"保存\tCtrl+S" action:@selector(saveDocument) keyEquivalent:@"s"];
	[fileMenu addItemWithTitle:@"另存为...\tF6" action:@selector(saveDocumentAs) keyEquivalent:[NSString stringWithFormat:@"%d", NSF6FunctionKey]];
	[fileMenu addItemWithTitle:@"保存副本...\tCtrl+F6" action:@selector(saveCopyAs) keyEquivalent:@""];
	[fileMenu addItem:[NSMenuItem separatorItem]];
	[fileMenu addItemWithTitle:@"页面设置..." action:@selector(pageSetup) keyEquivalent:@""];
	[fileMenu addItemWithTitle:@"打印...\tCtrl+P" action:@selector(printDocument) keyEquivalent:@"p"];
	[fileMenu addItem:[NSMenuItem separatorItem]];
	// 编码子菜单
	NSMenuItem *encItem = [fileMenu addItemWithTitle:@"编码" action:nil keyEquivalent:@""];
	NSMenu *encMenu = [[NSMenu alloc] init];
	for (NSString *enc in @[@"UTF-8", @"UTF-16LE", @"UTF-16BE", @"GBK", @"BIG5", @"Shift-JIS", @"Latin-1"]) {
		NSMenuItem *mi = [encMenu addItemWithTitle:[NSString stringWithFormat:@"重新加载为 %@", enc]
			action:@selector(reloadEncoding:) keyEquivalent:@""];
		mi.representedObject = enc;
	}
	[encMenu addItem:[NSMenuItem separatorItem]];
	for (NSString *enc in @[@"UTF-8", @"UTF-16LE", @"GBK"]) {
		NSMenuItem *mi = [encMenu addItemWithTitle:[NSString stringWithFormat:@"保存为 %@", enc]
			action:@selector(saveEncoding:) keyEquivalent:@""];
		mi.representedObject = enc;
	}
	encItem.submenu = encMenu;
	[fileMenu addItem:[NSMenuItem separatorItem]];
	[fileMenu addItemWithTitle:@"退出" action:@selector(terminate:) keyEquivalent:@""];
	fileItem.submenu = fileMenu;

	// 编辑（对齐 Windows 版大编辑菜单）
	NSMenuItem *editItem = [menubar addItemWithTitle:@"编辑(E)" action:nil keyEquivalent:@""];
	NSMenu *editMenu = [[NSMenu alloc] init];
	[editMenu addItemWithTitle:@"撤销\tCtrl+Z" action:@selector(undo:) keyEquivalent:@"z"];
	[editMenu addItemWithTitle:@"重做\tCtrl+Y" action:@selector(redo:) keyEquivalent:@"y"];
	[editMenu addItem:[NSMenuItem separatorItem]];
	[editMenu addItemWithTitle:@"剪切\tCtrl+X" action:@selector(cut:) keyEquivalent:@"x"];
	[editMenu addItemWithTitle:@"复制\tCtrl+C" action:@selector(copy:) keyEquivalent:@"c"];
	[editMenu addItemWithTitle:@"粘贴\tCtrl+V" action:@selector(paste:) keyEquivalent:@"v"];
	[editMenu addItem:[NSMenuItem separatorItem]];
	NSMenuItem *delMenu = [editMenu addItemWithTitle:@"删除" action:nil keyEquivalent:@""];
	NSMenu *delSub = [[NSMenu alloc] init];
	[delSub addItemWithTitle:@"删除行\tCtrl+Shift+D" action:@selector(deleteLine) keyEquivalent:@"D"].keyEquivalentModifierMask = NSEventModifierFlagCommand|NSEventModifierFlagShift;
	[delSub addItemWithTitle:@"删除到行首\tCtrl+Shift+Backspace" action:@selector(deleteLineLeft) keyEquivalent:@""];
	[delSub addItemWithTitle:@"删除到行尾\tCtrl+Shift+Del" action:@selector(deleteLineRight) keyEquivalent:@""];
	delMenu.submenu = delSub;
	[editMenu addItemWithTitle:@"全选\tCtrl+A" action:@selector(selectAll:) keyEquivalent:@"a"];
	[editMenu addItemWithTitle:@"选词\tCtrl+Space" action:@selector(selectWord) keyEquivalent:@" "].keyEquivalentModifierMask = NSEventModifierFlagCommand;
	[editMenu addItemWithTitle:@"选行\tCtrl+Shift+Space" action:@selector(selectLine) keyEquivalent:@""];
	[editMenu addItem:[NSMenuItem separatorItem]];
	NSMenuItem *lineMenu = [editMenu addItemWithTitle:@"行操作" action:nil keyEquivalent:@""];
	NSMenu *lineSub = [[NSMenu alloc] init];
	[lineSub addItemWithTitle:@"上移行\tAlt+Up" action:@selector(moveLineUp) keyEquivalent:[NSString stringWithFormat:@"%d", NSUpArrowFunctionKey]].keyEquivalentModifierMask = NSEventModifierFlagOption;
	[lineSub addItemWithTitle:@"下移行\tAlt+Down" action:@selector(moveLineDown) keyEquivalent:[NSString stringWithFormat:@"%d", NSDownArrowFunctionKey]].keyEquivalentModifierMask = NSEventModifierFlagOption;
	[lineSub addItemWithTitle:@"复制行\tCtrl+D" action:@selector(duplicateLine) keyEquivalent:@"d"];
	[lineSub addItemWithTitle:@"剪切行\tCtrl+Shift+X" action:@selector(cutLine) keyEquivalent:@"x"].keyEquivalentModifierMask = NSEventModifierFlagCommand|NSEventModifierFlagShift;
	[lineSub addItemWithTitle:@"合并行\tCtrl+J" action:@selector(joinLines) keyEquivalent:@"j"];
	[lineSub addItemWithTitle:@"行转置\tAlt+S" action:@selector(transposeLine) keyEquivalent:@""];
	[lineSub addItemWithTitle:@"去除行尾空格\tAlt+T" action:@selector(trimLines) keyEquivalent:@""];
	lineMenu.submenu = lineSub;
	NSMenuItem *caseMenu = [editMenu addItemWithTitle:@"大小写转换" action:nil keyEquivalent:@""];
	NSMenu *caseSub = [[NSMenu alloc] init];
	[caseSub addItemWithTitle:@"大写\tCtrl+Shift+U" action:@selector(toUpper) keyEquivalent:@"u"].keyEquivalentModifierMask = NSEventModifierFlagCommand|NSEventModifierFlagShift;
	[caseSub addItemWithTitle:@"小写\tCtrl+U" action:@selector(toLower) keyEquivalent:@"u"];
	[caseSub addItemWithTitle:@"词首大写" action:@selector(toTitleCase) keyEquivalent:@""];
	[caseSub addItemWithTitle:@"反转大小写" action:@selector(toInvertCase) keyEquivalent:@""];
	caseMenu.submenu = caseSub;
	NSMenuItem *enc2Menu = [editMenu addItemWithTitle:@"编码转换" action:nil keyEquivalent:@""];
	NSMenu *enc2Sub = [[NSMenu alloc] init];
	[enc2Sub addItemWithTitle:@"Tab -> 空格\tCtrl+Shift+S" action:@selector(tabsToSpaces) keyEquivalent:@""];
	[enc2Sub addItemWithTitle:@"空格 -> Tab\tCtrl+Shift+T" action:@selector(spacesToTabs) keyEquivalent:@""];
	[enc2Sub addItemWithTitle:@"URL 编码\tCtrl+Shift+E" action:@selector(urlEncode) keyEquivalent:@""];
	[enc2Sub addItemWithTitle:@"URL 解码\tCtrl+Shift+R" action:@selector(urlDecode) keyEquivalent:@""];
	enc2Menu.submenu = enc2Sub;
	editItem.submenu = editMenu;

	// 搜索
	NSMenuItem *searchItem = [menubar addItemWithTitle:@"搜索(S)" action:nil keyEquivalent:@""];
	NSMenu *searchMenu = [[NSMenu alloc] init];
	[searchMenu addItemWithTitle:@"查找...\tCtrl+F" action:@selector(findInDoc) keyEquivalent:@"f"];
	[searchMenu addItemWithTitle:@"查找下一个\tF3" action:@selector(findNext) keyEquivalent:[NSString stringWithFormat:@"%d", NSF3FunctionKey]];
	[searchMenu addItemWithTitle:@"查找上一个\tShift+F3" action:@selector(findPrev) keyEquivalent:[NSString stringWithFormat:@"%d", NSF3FunctionKey]].keyEquivalentModifierMask = NSEventModifierFlagShift;
	[searchMenu addItemWithTitle:@"替换...\tCtrl+H" action:@selector(replaceInDoc) keyEquivalent:@"h"];
	[searchMenu addItem:[NSMenuItem separatorItem]];
	[searchMenu addItemWithTitle:@"跳转到行...\tCtrl+G" action:@selector(gotoLine) keyEquivalent:@"g"];
	[searchMenu addItemWithTitle:@"跳转到匹配括号\tCtrl+B" action:@selector(gotoBrace) keyEquivalent:@"b"];
	[searchMenu addItem:[NSMenuItem separatorItem]];
	[searchMenu addItemWithTitle:@"书签: 切换\tCtrl+F2" action:@selector(bookmarkToggle) keyEquivalent:@""];
	[searchMenu addItemWithTitle:@"书签: 下一个\tF2" action:@selector(bookmarkNext) keyEquivalent:[NSString stringWithFormat:@"%d", NSF2FunctionKey]];
	[searchMenu addItemWithTitle:@"书签: 清除\tAlt+F2" action:@selector(bookmarkClear) keyEquivalent:@""];
	searchItem.submenu = searchMenu;

	// 查看
	NSMenuItem *viewItem = [menubar addItemWithTitle:@"查看(V)" action:nil keyEquivalent:@""];
	NSMenu *viewMenu = [[NSMenu alloc] init];
	[viewMenu addItemWithTitle:@"选择语法...\tF12" action:@selector(chooseLexer) keyEquivalent:[NSString stringWithFormat:@"%d", NSF12FunctionKey]];
	[viewMenu addItemWithTitle:@"使用默认代码样式\tShift+F12" action:@selector(resetStyle) keyEquivalent:@""];
	[viewMenu addItem:[NSMenuItem separatorItem]];
	_wrapItem = [viewMenu addItemWithTitle:@"自动换行\tCtrl+W" action:@selector(toggleWrap) keyEquivalent:@"w"];
	_wrapItem.state = NSControlStateValueOff;
	_lineNumbersItem = [viewMenu addItemWithTitle:@"显示行号\tCtrl+Shift+N" action:@selector(toggleLineNumbers) keyEquivalent:@"n"];
	_lineNumbersItem.state = NSControlStateValueOn;
	[viewMenu addItemWithTitle:@"显示空白字符\tCtrl+Shift+8" action:@selector(toggleWhitespace) keyEquivalent:@"8"].keyEquivalentModifierMask = NSEventModifierFlagCommand|NSEventModifierFlagShift;
	[viewMenu addItemWithTitle:@"显示换行符\tCtrl+Shift+9" action:@selector(toggleEOLs) keyEquivalent:@"9"].keyEquivalentModifierMask = NSEventModifierFlagCommand|NSEventModifierFlagShift;
	_indentItem = [viewMenu addItemWithTitle:@"显示缩进参考线\tCtrl+Shift+G" action:@selector(toggleIndentGuides) keyEquivalent:@""];
	_indentItem.state = NSControlStateValueOn;
	[viewMenu addItem:[NSMenuItem separatorItem]];
	[viewMenu addItemWithTitle:@"放大\tCtrl++" action:@selector(zoomIn) keyEquivalent:@"+"];
	[viewMenu addItemWithTitle:@"缩小\tCtrl+-" action:@selector(zoomOut) keyEquivalent:@"-"];
	[viewMenu addItemWithTitle:@"重置缩放\tCtrl+\\" action:@selector(zoomReset) keyEquivalent:@"\\"];
	[viewMenu addItem:[NSMenuItem separatorItem]];
	_statusItem = [viewMenu addItemWithTitle:@"显示状态栏\tShift+F11" action:@selector(toggleStatusBar) keyEquivalent:[NSString stringWithFormat:@"%d", NSF11FunctionKey]];
	_statusItem.state = NSControlStateValueOn;
	_statusItem.keyEquivalentModifierMask = NSEventModifierFlagShift;
	viewItem.submenu = viewMenu;

	// 帮助
	NSMenuItem *helpItem = [menubar addItemWithTitle:@"帮助(H)" action:nil keyEquivalent:@""];
	NSMenu *helpMenu = [[NSMenu alloc] init];
	[helpMenu addItemWithTitle:@"关于 Notepad4" action:@selector(orderFrontStandardAboutPanel:) keyEquivalent:@""];
	helpItem.submenu = helpMenu;

	NSApp.mainMenu = menubar;
}

#pragma mark - 工具栏动作

- (void)toolbarFileAction:(NSSegmentedControl *)sender {
	switch (sender.selectedSegment) {
		case 0: [self newTab]; break;
		case 1: [self openDocument]; break;
		case 2: [self saveDocument]; break;
	}
}

- (void)toolbarUndoAction:(NSSegmentedControl *)sender {
	EditorDocument *doc = self.currentDocument;
	if (!doc) return;
	if (sender.selectedSegment == 0) [doc.editor message:SCI_UNDO wParam:0 lParam:0];
	else [doc.editor message:SCI_REDO wParam:0 lParam:0];
	[self refreshStatus];
}

- (void)toolbarClipboardAction:(NSSegmentedControl *)sender {
	EditorDocument *doc = self.currentDocument;
	if (!doc) return;
	switch (sender.selectedSegment) {
		case 0: [doc.editor message:SCI_CUT wParam:0 lParam:0]; break;
		case 1: [doc.editor message:SCI_COPY wParam:0 lParam:0]; break;
		case 2: [doc.editor message:SCI_PASTE wParam:0 lParam:0]; break;
	}
	[self refreshStatus];
}

- (void)toolbarFindAction:(NSSegmentedControl *)sender {
	if (sender.selectedSegment == 0) [_findPanel showFind:NO];
	else [_findPanel showFind:YES];
}

- (void)toolbarZoomAction:(NSSegmentedControl *)sender {
	EditorDocument *doc = self.currentDocument;
	if (!doc) return;
	ScintillaView *e = doc.editor;
	if (sender.selectedSegment == 0) [e message:SCI_ZOOMOUT wParam:0 lParam:0];
	else [e message:SCI_ZOOMIN wParam:0 lParam:0];
	[self refreshStatus];
}

- (void)lexerChanged:(NSPopUpButton *)sender {
	EditorDocument *doc = self.currentDocument;
	if (!doc) return;
	NSDictionary *info = sender.selectedItem.representedObject;
	NSString *exts = info[@"extensions"];
	NSString *firstExt = [[exts componentsSeparatedByString:@";"] firstObject] ?: @"txt";
	[doc applyLexerForExtension:[firstExt stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]];
	[self refreshStatus];
}

#pragma mark - Tab 管理

- (EditorDocument *)currentDocument {
	NSTabViewItem *item = _tabView.selectedTabViewItem;
	return item ? item.identifier : nil;
}

- (void)newTab {
	_untitledCounter += 1;
	EditorDocument *doc = [[EditorDocument alloc] initWithNewUntitled:_untitledCounter];
	[self addTabForDocument:doc];
}

- (void)newWindow {
	MainWindowController *wc = [[MainWindowController alloc] init];
	[wc showWindow:nil];
}

- (void)addTabForDocument:(EditorDocument *)doc {
	NSTabViewItem *item = [[NSTabViewItem alloc] initWithIdentifier:doc];
	item.label = doc.tabTitle;
	NSView *container = [[NSView alloc] initWithFrame:NSZeroRect];
	container.translatesAutoresizingMaskIntoConstraints = NO;
	doc.editor.translatesAutoresizingMaskIntoConstraints = NO;
	[container addSubview:doc.editor];
	[container addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|[ed]|" options:0 metrics:nil views:@{@"ed": doc.editor}]];
	[container addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|[ed]|" options:0 metrics:nil views:@{@"ed": doc.editor}]];
	item.view = container;
	[_tabView addTabViewItem:item];
	[_tabView selectTabViewItem:item];
	[self updateWindowTitle];
	[[NSNotificationCenter defaultCenter] addObserver:self
		selector:@selector(docDirtyChanged:)
		name:@"EditorDocumentDirtyChanged" object:doc];
	[[NSNotificationCenter defaultCenter] addObserver:self
		selector:@selector(refreshStatus)
		name:@"EditorDocumentDirtyChanged" object:doc];
}

- (void)docDirtyChanged:(NSNotification *)n {
	EditorDocument *doc = n.object;
	for (NSTabViewItem *item in _tabView.tabViewItems) {
		if (item.identifier == doc) {
			item.label = doc.dirty ? [doc.tabTitle stringByAppendingString:@" •"] : doc.tabTitle;
		}
	}
	[self updateWindowTitle];
}

- (void)refreshStatus {
	[self.statusBar updateForDocument:self.currentDocument];
}

- (void)updateWindowTitle {
	EditorDocument *doc = self.currentDocument;
	self.window.title = doc.windowTitle ?: @"Notepad4";
	[self refreshStatus];
}

- (void)tabView:(NSTabView *)tabView didSelectTabViewItem:(NSTabViewItem *)item {
	[self updateWindowTitle];
	[self.window makeFirstResponder:[[self.currentDocument editor] content]];
}

#pragma mark - 文件动作

- (void)openDocument {
	NSOpenPanel *panel = [NSOpenPanel openPanel];
	panel.allowsMultipleSelection = YES;
	panel.canChooseDirectories = NO;
	[panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse resp) {
		if (resp != NSModalResponseOK) return;
		for (NSURL *url in panel.URLs) {
			EditorDocument *doc = [[EditorDocument alloc] initWithFileURL:url contents:@""];
			NSError *err = nil;
			if ([doc loadFromURL:url error:&err]) {
				[self addTabForDocument:doc];
			} else {
				NSAlert *alert = [[NSAlert alloc] init];
				alert.messageText = @"打开失败";
				alert.informativeText = err.localizedDescription;
				[alert beginSheetModalForWindow:self.window completionHandler:nil];
			}
		}
	}];
}

- (void)revertDocument {
	EditorDocument *doc = self.currentDocument;
	if (doc.fileURL) {
		[doc reloadWithEncoding:doc.currentEncoding];
		[self refreshStatus];
	}
}

- (void)openExternal {
	EditorDocument *doc = self.currentDocument;
	if (doc.fileURL) {
		[[NSWorkspace sharedWorkspace] openURL:doc.fileURL];
	}
}

- (BOOL)saveDocument {
	EditorDocument *doc = self.currentDocument;
	if (!doc) return NO;
	if (!doc.fileURL) return [self saveDocumentAs];
	NSError *err = nil;
	if (![doc saveToURL:doc.fileURL error:&err]) {
		NSAlert *a = [[NSAlert alloc] init];
		a.messageText = @"保存失败";
		a.informativeText = err.localizedDescription;
		[a beginSheetModalForWindow:self.window completionHandler:nil];
		return NO;
	}
	[self refreshStatus];
	return YES;
}

- (BOOL)saveDocumentAs {
	EditorDocument *doc = self.currentDocument;
	if (!doc) return NO;
	NSSavePanel *panel = [NSSavePanel savePanel];
	panel.nameFieldStringValue = doc.tabTitle;
	[panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse resp) {
		if (resp != NSModalResponseOK) return;
		NSError *err = nil;
		if (![doc saveToURL:panel.URL error:&err]) {
			NSAlert *a = [[NSAlert alloc] init];
			a.messageText = @"保存失败";
			a.informativeText = err.localizedDescription;
			[a beginSheetModalForWindow:self.window completionHandler:nil];
		} else {
			[doc applyLexerForExtension:panel.URL.pathExtension.lowercaseString];
			[self docDirtyChanged:[NSNotification notificationWithName:@"x" object:doc]];
			[self refreshStatus];
		}
	}];
	return YES;
}

- (void)saveCopyAs {
	EditorDocument *doc = self.currentDocument;
	if (!doc) return;
	NSSavePanel *panel = [NSSavePanel savePanel];
	panel.nameFieldStringValue = doc.tabTitle;
	[panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse resp) {
		if (resp != NSModalResponseOK) return;
		NSString *text = [doc.editor string];
		[text writeToURL:panel.URL atomically:YES encoding:NSUTF8StringEncoding error:nil];
	}];
}

- (void)pageSetup {}
- (void)printDocument {
	EditorDocument *doc = self.currentDocument;
	if (!doc) return;
	NSPrintOperation *op = [NSPrintOperation printOperationWithView:doc.editor];
	[op runOperationModalForWindow:self.window delegate:nil didRunSelector:nil contextInfo:nil];
}

- (void)closeTab {
	if (_tabView.numberOfTabViewItems <= 1) {
		[self.window performClose:self];
		return;
	}
	NSTabViewItem *item = _tabView.selectedTabViewItem;
	EditorDocument *doc = item.identifier;
	[[NSNotificationCenter defaultCenter] removeObserver:self name:@"EditorDocumentDirtyChanged" object:doc];
	[_tabView removeTabViewItem:item];
	[self updateWindowTitle];
}

#pragma mark - 编码

- (void)reloadEncoding:(NSMenuItem *)sender {
	EditorDocument *doc = self.currentDocument;
	if (doc) [doc reloadWithEncoding:sender.representedObject];
	[self refreshStatus];
}

- (void)saveEncoding:(NSMenuItem *)sender {
	EditorDocument *doc = self.currentDocument;
	if (doc) [doc setSaveEncoding:sender.representedObject];
	[self refreshStatus];
}

#pragma mark - 编辑扩展动作

- (ScintillaView *)curEditor {
	return self.currentDocument.editor;
}

- (void)deleteLine { [[self curEditor] message:SCI_LINEDELETE wParam:0 lParam:0]; [self refreshStatus]; }
- (void)deleteLineLeft { [[self curEditor] message:SCI_DELLINELEFT wParam:0 lParam:0]; }
- (void)deleteLineRight { [[self curEditor] message:SCI_DELLINERIGHT wParam:0 lParam:0]; }
- (void)selectWord { [[self curEditor] message:SCI_WORDRIGHT wParam:0 lParam:0]; [[self curEditor] message:SCI_WORDLEFTEXTEND wParam:0 lParam:0]; }
- (void)selectLine { [[self curEditor] message:SCI_LINETRANSPOSE wParam:0 lParam:0]; [[self curEditor] message:SCI_LINETRANSPOSE wParam:0 lParam:0]; } // 占位，见下行真实现
- (void)moveLineUp { [[self curEditor] message:SCI_MOVESELECTEDLINESUP wParam:0 lParam:0]; [self refreshStatus]; }
- (void)moveLineDown { [[self curEditor] message:SCI_MOVESELECTEDLINESDOWN wParam:0 lParam:0]; [self refreshStatus]; }
- (void)duplicateLine { [[self curEditor] message:SCI_LINEDUPLICATE wParam:0 lParam:0]; [self refreshStatus]; }
- (void)cutLine { [[self curEditor] message:SCI_LINECUT wParam:0 lParam:0]; }
- (void)joinLines { [[self curEditor] message:SCI_TARGETFROMSELECTION wParam:0 lParam:0]; [[self curEditor] message:SCI_LINESJOIN wParam:0 lParam:0]; }
- (void)transposeLine { [[self curEditor] message:SCI_LINETRANSPOSE wParam:0 lParam:0]; }
- (void)trimLines { [[self curEditor] message:SCI_TARGETWHOLEDOCUMENT wParam:0 lParam:0]; /* 简化：全文档去尾空格后续接 */ }

- (void)toUpper { [[self curEditor] message:SCI_UPPERCASE wParam:0 lParam:0]; }
- (void)toLower { [[self curEditor] message:SCI_LOWERCASE wParam:0 lParam:0]; }
- (void)toTitleCase { /* TitleCase 后续接 EditCase */ }
- (void)toInvertCase { /* 后续接 */ }

- (void)tabsToSpaces { [[self curEditor] message:SCI_TARGETWHOLEDOCUMENT wParam:0 lParam:0]; [[self curEditor] message:SCI_SETUSETABS wParam:0 lParam:0]; }
- (void)spacesToTabs { [[self curEditor] message:SCI_TARGETWHOLEDOCUMENT wParam:0 lParam:0]; }
- (void)urlEncode {}
- (void)urlDecode {}

#pragma mark - 搜索动作

- (void)findInDoc { [_findPanel showFind:NO]; }
- (void)replaceInDoc { [_findPanel showFind:YES]; }
- (void)findNext:(id)sender {
	EditorDocument *doc = self.currentDocument;
	if (doc) [_findPanel findNext:doc];
	[self refreshStatus];
}
- (void)findPrev:(id)sender {
	EditorDocument *doc = self.currentDocument;
	if (doc) [_findPanel findPrevious:doc];
	[self refreshStatus];
}
- (void)gotoLine {
	EditorDocument *doc = self.currentDocument;
	if (!doc) return;
	NSAlert *a = [[NSAlert alloc] init];
	a.messageText = @"跳转到行";
	NSTextField *input = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 200, 24)];
	a.accessoryView = input;
	[a addButtonWithTitle:@"跳转"];
	[a addButtonWithTitle:@"取消"];
	[a beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse r) {
		if (r != NSAlertFirstButtonReturn) return;
		long line = input.stringValue.longLongValue;
		if (line > 0) {
			ScintillaView *e = doc.editor;
			const sptr_t pos = [e message:SCI_POSITIONFROMLINE wParam:line - 1];
			[e message:SCI_GOTOLINE wParam:line - 1 lParam:0];
			[e message:SCI_SETSELECTION wParam:pos lParam:pos];
		}
	}];
}
- (void)gotoBrace {
	ScintillaView *e = self.curEditor;
	[e message:SCI_BRACEMATCHNEXT wParam:0 lParam:0];
}
- (void)bookmarkToggle {
	ScintillaView *e = self.curEditor;
	const sptr_t line = [e message:SCI_LINEFROMPOSITION wParam:[e message:SCI_GETCURRENTPOS]];
	[e message:SCI_MARKERDELETE wParam:line lParam:-1];
	[e message:SCI_MARKERADD wParam:line lParam:1];
}
- (void)bookmarkNext {
	ScintillaView *e = self.curEditor;
	const sptr_t line = [e message:SCI_LINEFROMPOSITION wParam:[e message:SCI_GETCURRENTPOS]];
	const sptr_t next = [e message:SCI_MARKERNEXT wParam:line + 1 lParam:2];
	if (next >= 0) [e message:SCI_GOTOLINE wParam:next lParam:0];
}
- (void)bookmarkClear {
	ScintillaView *e = self.curEditor;
	[e message:SCI_MARKERDELETEALL wParam:1 lParam:0];
}

#pragma mark - 查看动作

- (void)chooseLexer {
	// 焦点跳到工具栏词法器选择
	[self.window makeFirstResponder:_lex];
}
- (void)resetStyle {
	EditorDocument *doc = self.currentDocument;
	if (doc) [doc applyLexerForExtension:doc.fileURL.pathExtension.lowercaseString ?: @""];
}
- (void)toggleWrap {
	_wrapItem.state = (_wrapItem.state == NSControlStateValueOn) ? NSControlStateValueOff : NSControlStateValueOn;
	ScintillaView *e = self.curEditor;
	[e message:SCI_SETWRAPMODE wParam:(_wrapItem.state == NSControlStateValueOn) ? SC_WRAP_WORD : SC_WRAP_NONE lParam:0];
}
- (void)toggleLineNumbers {
	_lineNumbersItem.state = (_lineNumbersItem.state == NSControlStateValueOn) ? NSControlStateValueOff : NSControlStateValueOn;
	ScintillaView *e = self.curEditor;
	[e message:SCI_SETMARGINWIDTHN wParam:0 lParam:(_lineNumbersItem.state == NSControlStateValueOn) ? 48 : 0];
}
- (void)toggleWhitespace {
	ScintillaView *e = self.curEditor;
	const sptr_t cur = [e message:SCI_GETVIEWWS];
	[e message:SCI_SETVIEWWS wParam:(cur ? SCWS_INVISIBLE : SCWS_VISIBLEALWAYS) lParam:0];
}
- (void)toggleEOLs {
	ScintillaView *e = self.curEditor;
	const sptr_t cur = [e message:SCI_GETVIEWEOL];
	[e message:SCI_SETVIEWEOL wParam:!cur lParam:0];
}
- (void)toggleIndentGuides {
	_indentItem.state = (_indentItem.state == NSControlStateValueOn) ? NSControlStateValueOff : NSControlStateValueOn;
	ScintillaView *e = self.curEditor;
	[e message:SCI_SETINDENTATIONGUIDES wParam:(_indentItem.state == NSControlStateValueOn) ? SC_IV_LOOKBOTH : SC_IV_NONE lParam:0];
}
- (void)zoomIn { [[self curEditor] message:SCI_ZOOMIN wParam:0 lParam:0]; [self refreshStatus]; }
- (void)zoomOut { [[self curEditor] message:SCI_ZOOMOUT wParam:0 lParam:0]; [self refreshStatus]; }
- (void)zoomReset { [[self curEditor] message:SCI_SETZOOM wParam:0 lParam:0]; [self refreshStatus]; }
- (void)toggleStatusBar {
	_statusItem.state = (_statusItem.state == NSControlStateValueOn) ? NSControlStateValueOff : NSControlStateValueOn;
	self.statusBar.hidden = (_statusItem.state == NSControlStateValueOff);
}

#pragma mark - NSWindowDelegate

- (BOOL)windowShouldClose:(NSWindow *)sender {
	for (NSTabViewItem *item in _tabView.tabViewItems) {
		EditorDocument *doc = item.identifier;
		if (doc.dirty) {
			NSAlert *alert = [[NSAlert alloc] init];
			alert.messageText = [NSString stringWithFormat:@"“%@”有未保存的修改。", doc.tabTitle];
			alert.informativeText = @"关闭前保存修改吗？";
			[alert addButtonWithTitle:@"保存"];
			[alert addButtonWithTitle:@"不保存"];
			[alert addButtonWithTitle:@"取消"];
			[alert beginSheetModalForWindow:sender completionHandler:^(NSModalResponse resp) {
				if (resp == NSAlertFirstButtonReturn) {
					if ([self saveDocument]) [sender performClose:nil];
				} else if (resp == NSAlertSecondButtonReturn) {
					[sender performClose:nil];
				}
			}];
			return NO;
		}
	}
	return YES;
}

@end
