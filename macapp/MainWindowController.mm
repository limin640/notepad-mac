#import "MainWindowController.h"
#import "FindReplacePanel.h"
#import "StatusBarView.h"
#import "SciLexer.h"
#import "EditLexer.h"
#import "LexerRegistry.h"
#import "Scintilla.h"
#import "NPLocalization.h"
#import "PreviewPane.h"
#import "NPTheme.h"

// 跟随系统明暗外观的 chrome 背景
@interface NPChromeView : NSView
@property (nonatomic) BOOL borderAtBottom;   // 工具栏底部描边
@property (nonatomic) BOOL borderAtTop;      // 状态栏顶部描边
@end

@interface NPRootView : NSView
@property (nonatomic, weak) MainWindowController *controller;
@end
@implementation NPRootView
- (instancetype)initWithFrame:(NSRect)frame {
	self = [super initWithFrame:frame];
	if (self) [self registerForDraggedTypes:@[NSPasteboardTypeFileURL]];
	return self;
}
- (BOOL)performKeyEquivalent:(NSEvent *)event {
	if ([self.controller handleKeyEquivalent:event]) return YES;
	return [super performKeyEquivalent:event];
}
- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)sender { return NSDragOperationCopy; }
- (BOOL)prepareForDragOperation:(id<NSDraggingInfo>)sender { return YES; }
- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender {
	NSArray *urls = [[sender draggingPasteboard] readObjectsForClasses:@[[NSURL class]]
		options:@{NSPasteboardURLReadingFileURLsOnlyKey: @YES}];
	if (urls.count == 0) return NO;
	for (NSURL *u in urls) [self.controller openURLInTab:u];
	return YES;
}
@end

@interface NPMenuBarButton : NSButton
@property (nonatomic) BOOL menuOpen;
@end
@implementation NPMenuBarButton
- (NSSize)intrinsicContentSize {
	NSSize sz = [super intrinsicContentSize];
	sz.width += 20;
	sz.height = 22;
	return sz;
}
- (void)updateTrackingAreas {
	[super updateTrackingAreas];
	for (NSTrackingArea *a in [self.trackingAreas copy]) [self removeTrackingArea:a];
	[self addTrackingArea:[[NSTrackingArea alloc] initWithRect:self.bounds
		options:(NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways | NSTrackingInVisibleRect)
		owner:self userInfo:nil]];
}
- (void)applyChrome {
	self.wantsLayer = YES;
	self.layer.cornerRadius = 4;
	if (self.menuOpen) {
		self.layer.backgroundColor = [[NSColor selectedContentBackgroundColor] colorWithAlphaComponent:0.45].CGColor;
	} else {
		self.layer.backgroundColor = nil;
	}
}
- (void)mouseEntered:(NSEvent *)e {
	if ([self.target respondsToSelector:@selector(menuBarHovered:)])
		[self.target performSelector:@selector(menuBarHovered:) withObject:self];
	if (self.menuOpen) return;
	self.wantsLayer = YES;
	self.layer.cornerRadius = 4;
	self.layer.backgroundColor = [[NSColor selectedContentBackgroundColor] colorWithAlphaComponent:0.28].CGColor;
}
- (void)mouseExited:(NSEvent *)e { [self applyChrome]; }
@end

// 工具栏按钮：只做命中测试，图标由 NPChromeView 统一绘制
@interface NPImageButton : NSView
@property (nonatomic, strong) NSImage *icon;
@property (nonatomic, weak) id tbTarget;
@property (nonatomic) SEL tbAction;
@property (nonatomic) SEL tbDropAction;
@property (nonatomic) BOOL hasDropdown;
@property (nonatomic) BOOL hovered;
@end

@implementation NPImageButton
- (BOOL)isFlipped { return YES; }
- (void)updateTrackingAreas {
	[super updateTrackingAreas];
	for (NSTrackingArea *a in [self.trackingAreas copy]) [self removeTrackingArea:a];
	[self addTrackingArea:[[NSTrackingArea alloc] initWithRect:self.bounds
		options:(NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways)
		owner:self userInfo:nil]];
}
- (void)mouseEntered:(NSEvent *)e { self.hovered = YES; self.superview.needsDisplay = YES; }
- (void)mouseExited:(NSEvent *)e { self.hovered = NO; self.superview.needsDisplay = YES; }
- (void)mouseUp:(NSEvent *)e {
	NSPoint p = [self convertPoint:e.locationInWindow fromView:nil];
	if (!NSPointInRect(p, self.bounds) || !self.tbTarget) return;
	if (self.hasDropdown && self.tbDropAction && p.x > NSWidth(self.bounds) - 10)
		[NSApp sendAction:self.tbDropAction to:self.tbTarget from:self];
	else if (self.tbAction)
		[NSApp sendAction:self.tbAction to:self.tbTarget from:self];
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
		const BOOL hover = [sub respondsToSelector:@selector(hovered)] && [(id)sub hovered];
		NSBezierPath *frame = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(b, 0.5, 0.5) xRadius:3 yRadius:3];
		if (hover) {
			[[[NSColor selectedContentBackgroundColor] colorWithAlphaComponent:0.30] setFill];
			[frame fill];
		}
		[[NSColor separatorColor] setStroke];
		frame.lineWidth = 1;
		[frame stroke];
		NSSize is = img.size;
		const BOOL drop = [sub respondsToSelector:@selector(hasDropdown)] && [(id)sub hasDropdown];
		CGFloat midX = NSMidX(b) - (drop ? 3 : 0);
		NSRect r = NSMakeRect(midX - is.width / 2, NSMidY(b) - is.height / 2,
			is.width, is.height);
		[img drawInRect:r fromRect:NSZeroRect operation:NSCompositingOperationSourceOver
			fraction:1.0 respectFlipped:YES hints:nil];
		if (drop) {
			NSBezierPath *tri = [NSBezierPath bezierPath];
			const CGFloat tx = NSMaxX(b) - 5, ty = NSMinY(b) + 5;
			[tri moveToPoint:NSMakePoint(tx - 3, ty)];
			[tri lineToPoint:NSMakePoint(tx + 3, ty)];
			[tri lineToPoint:NSMakePoint(tx, ty + 4)];
			[tri closePath];
			[[NSColor secondaryLabelColor] setFill];
			[tri fill];
		}
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

@interface NPFlippedView : NSView
@end
@implementation NPFlippedView
- (BOOL)isFlipped { return YES; }
@end

@interface NPDropDownView : NSView
@property (nonatomic, strong) NSScrollView *scroller;
@property (nonatomic, strong) NSView *rowHost;
@property (nonatomic) CGFloat contentHeight;
- (void)setContentHeight:(CGFloat)h width:(CGFloat)w;
@end
@implementation NPDropDownView
- (instancetype)initWithFrame:(NSRect)frame {
	self = [super initWithFrame:frame];
	if (!self) return nil;
	_rowHost = [[NPFlippedView alloc] initWithFrame:NSZeroRect];
	_scroller = [[NSScrollView alloc] initWithFrame:NSZeroRect];
	_scroller.drawsBackground = NO;
	_scroller.hasVerticalScroller = YES;
	_scroller.hasHorizontalScroller = NO;
	_scroller.autohidesScrollers = YES;
	_scroller.borderType = NSNoBorder;
	_scroller.scrollerStyle = NSScrollerStyleOverlay;
	_scroller.documentView = _rowHost;
	[self addSubview:_scroller];
	return self;
}
- (BOOL)isFlipped { return YES; }
- (void)drawRect:(NSRect)dirtyRect {
	[[NSColor controlBackgroundColor] setFill];
	NSBezierPath *p = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds, 0.5, 0.5) xRadius:6 yRadius:6];
	[p fill];
	[[NSColor separatorColor] setStroke];
	p.lineWidth = 1;
	[p stroke];
}
- (void)layout {
	[super layout];
	_scroller.frame = NSInsetRect(self.bounds, 1, 3);
}
- (void)setContentHeight:(CGFloat)h width:(CGFloat)w {
	_contentHeight = h;
	const CGFloat innerW = MAX(20, w - 2);
	_rowHost.frame = NSMakeRect(0, 0, innerW, MAX(1, h));
	_scroller.hasVerticalScroller = (h > NSHeight(self.bounds) + 0.5);
}
@end

// 一条菜单：左侧标题，右侧快捷键，有子菜单时右侧 ›
@interface NPMenuRow : NSView
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *shortcut;
@property (nonatomic) BOOL checked;
@property (nonatomic) BOOL hasSub;
@property (nonatomic) BOOL hovered;
@property (nonatomic) BOOL rowEnabled;
@property (nonatomic) NSInteger panelIndex;
@property (nonatomic) NSInteger itemIndex;
@property (nonatomic, weak) id rowTarget;
@property (nonatomic) SEL rowAction;
@property (nonatomic) SEL hoverAction;
@end
@implementation NPMenuRow
- (BOOL)isFlipped { return YES; }
- (void)updateTrackingAreas {
	[super updateTrackingAreas];
	for (NSTrackingArea *a in [self.trackingAreas copy]) [self removeTrackingArea:a];
	[self addTrackingArea:[[NSTrackingArea alloc] initWithRect:self.bounds
		options:(NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways)
		owner:self userInfo:nil]];
}
- (void)mouseEntered:(NSEvent *)e {
	self.hovered = YES;
	self.needsDisplay = YES;
	if (self.hoverAction && self.rowTarget)
		[NSApp sendAction:self.hoverAction to:self.rowTarget from:self];
}
- (void)mouseExited:(NSEvent *)e { self.hovered = NO; self.needsDisplay = YES; }
- (void)mouseUp:(NSEvent *)e {
	NSPoint p = [self convertPoint:e.locationInWindow fromView:nil];
	if (NSPointInRect(p, self.bounds) && self.rowEnabled && self.rowAction && self.rowTarget)
		[NSApp sendAction:self.rowAction to:self.rowTarget from:self];
}
- (void)drawRect:(NSRect)dirtyRect {
	if (self.hovered && self.rowEnabled) {
		[[[NSColor selectedContentBackgroundColor] colorWithAlphaComponent:0.32] setFill];
		[[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds, 3, 1) xRadius:4 yRadius:4] fill];
	}
	NSFont *font = [NSFont systemFontOfSize:13];
	NSColor *c = self.rowEnabled ? [NSColor labelColor] : [NSColor disabledControlTextColor];
	NSDictionary *attrs = @{NSFontAttributeName: font, NSForegroundColorAttributeName: c};
	NSDictionary *scAttrs = @{NSFontAttributeName: [NSFont systemFontOfSize:12],
		NSForegroundColorAttributeName: self.rowEnabled ? [NSColor secondaryLabelColor] : [NSColor disabledControlTextColor]};
	const CGFloat y = 3;
	if (self.checked)
		[@"✓" drawAtPoint:NSMakePoint(8, y) withAttributes:attrs];
	[self.name drawAtPoint:NSMakePoint(26, y) withAttributes:attrs];
	CGFloat right = NSMaxX(self.bounds) - 10;
	if (self.hasSub) {
		[@"›" drawAtPoint:NSMakePoint(right - 10, y) withAttributes:attrs];
		right -= 16;
	}
	if (self.shortcut.length) {
		NSSize ss = [self.shortcut sizeWithAttributes:scAttrs];
		[self.shortcut drawAtPoint:NSMakePoint(right - ss.width, y + 1) withAttributes:scAttrs];
	}
}
@end

@interface NPTabChip : NSView
@property (nonatomic) BOOL selected;
@property (nonatomic, copy) NSString *title;
@property (nonatomic) NSInteger index;
@property (nonatomic, weak) id target;
@end
@implementation NPTabChip
- (BOOL)isFlipped { return YES; }
- (void)mouseUp:(NSEvent *)e {
	NSPoint p = [self convertPoint:e.locationInWindow fromView:nil];
	if (!NSPointInRect(p, self.bounds) || !self.target) return;
	if (p.x > NSWidth(self.bounds) - 16)
		[NSApp sendAction:@selector(tabCloseClicked:) to:self.target from:self];
	else
		[NSApp sendAction:@selector(tabClicked:) to:self.target from:self];
}
- (void)drawRect:(NSRect)dirtyRect {
	(void)dirtyRect;
	if (self.selected) {
		[[[NSColor selectedContentBackgroundColor] colorWithAlphaComponent:0.32] setFill];
		[[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds, 1, 2) xRadius:5 yRadius:5] fill];
	}
	NSMutableParagraphStyle *ps = [[NSMutableParagraphStyle alloc] init];
	ps.lineBreakMode = NSLineBreakByTruncatingTail;
	NSDictionary *attrs = @{
		NSFontAttributeName: [NSFont systemFontOfSize:11],
		NSForegroundColorAttributeName: [NSColor labelColor],
		NSParagraphStyleAttributeName: ps
	};
	const CGFloat textW = MAX(8.0, NSWidth(self.bounds) - 22.0);
	[(self.title ?: @"") drawInRect:NSMakeRect(8, 5, textW, 16) withAttributes:attrs];
	[@"×" drawAtPoint:NSMakePoint(NSMaxX(self.bounds) - 14, 4)
		withAttributes:@{NSFontAttributeName: [NSFont systemFontOfSize:12],
			NSForegroundColorAttributeName: [NSColor secondaryLabelColor]}];
}
@end

@interface NPTabPlus : NSView
@property (nonatomic) BOOL hovered;
@property (nonatomic, weak) id target;
@end
@implementation NPTabPlus
- (BOOL)isFlipped { return YES; }
- (void)updateTrackingAreas {
	[super updateTrackingAreas];
	for (NSTrackingArea *a in [self.trackingAreas copy]) [self removeTrackingArea:a];
	[self addTrackingArea:[[NSTrackingArea alloc] initWithRect:self.bounds
		options:(NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways)
		owner:self userInfo:nil]];
}
- (void)mouseEntered:(NSEvent *)e { self.hovered = YES; self.needsDisplay = YES; }
- (void)mouseExited:(NSEvent *)e { self.hovered = NO; self.needsDisplay = YES; }
- (void)mouseUp:(NSEvent *)e {
	NSPoint p = [self convertPoint:e.locationInWindow fromView:nil];
	if (!NSPointInRect(p, self.bounds) || !self.target) return;
	[NSApp sendAction:@selector(fileNew) to:self.target from:self];
}
- (void)drawRect:(NSRect)dirtyRect {
	if (self.hovered) {
		[[[NSColor selectedContentBackgroundColor] colorWithAlphaComponent:0.28] setFill];
		[[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds, 1, 2) xRadius:5 yRadius:5] fill];
	}
	NSDictionary *attrs = @{NSFontAttributeName: [NSFont systemFontOfSize:15 weight:NSFontWeightMedium],
		NSForegroundColorAttributeName: [NSColor labelColor]};
	NSString *s = @"+";
	NSSize sz = [s sizeWithAttributes:attrs];
	[s drawAtPoint:NSMakePoint((NSWidth(self.bounds) - sz.width) / 2.0,
		(NSHeight(self.bounds) - sz.height) / 2.0 - 1) withAttributes:attrs];
}
@end

@interface NPWorkSplit : NSSplitView
@end
@implementation NPWorkSplit
- (CGFloat)dividerThickness { return 7; }
- (void)drawDividerInRect:(NSRect)rect {
	[[NSColor windowBackgroundColor] setFill];
	NSRectFill(rect);
	[[NSColor separatorColor] setFill];
	NSRectFill(NSMakeRect(NSMidX(rect) - 0.5, NSMinY(rect), 1, NSHeight(rect)));
	const CGFloat midY = NSMidY(rect);
	for (NSInteger i = -1; i <= 1; i++) {
		NSRect dot = NSMakeRect(NSMidX(rect) - 1.5, midY + i * 6 - 1.5, 3, 3);
		[[NSBezierPath bezierPathWithOvalInRect:dot] fill];
	}
}
- (void)resetCursorRects {
	[super resetCursorRects];
	if (self.subviews.count >= 2) {
		[self addCursorRect:[self dividerRect] cursor:[NSCursor resizeLeftRightCursor]];
	}
}
- (NSRect)dividerRect {
	if (self.subviews.count < 2) return NSZeroRect;
	NSView *left = self.subviews[0];
	return NSMakeRect(NSMaxX(left.frame), 0, self.dividerThickness, NSHeight(self.bounds));
}
@end

@implementation MainWindowController {
	FindReplacePanel *_findPanel;
	NSView *_editorHost;
	NSSplitView *_workSplit;
	PreviewPane *_previewPane;
	BOOL _previewOn;
	BOOL _previewIgnore;
	BOOL _previewApplying;
	BOOL _previewSyncing;
	CGFloat _previewSplitFrac;
	CGFloat _lastPreviewUsable;
	NSInteger _lastAppliedEditorLineFromPreview;
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
	NSView *_tabBar;
	NSView *_tabPlus;
	NSLayoutConstraint *_tabBarHeight;
	NSMutableArray<EditorDocument *> *_documents;
	NSInteger _untitledSeq;
	EditorDocument *_document;
	NSMenuItem *_langSystemItem;
	NSMutableArray<NSMenuItem *> *_langItems;
	NSMenuItem *_themeAutoItem;
	NSMenuItem *_themeDefaultItem;
	NSMenuItem *_themeDarkItem;
	NSLayoutConstraint *_menuBarHeight;
	NSLayoutConstraint *_toolBarHeight;
	NSLayoutConstraint *_statusBarHeight;
	NPDropDownView *_dropDown;
	NSMutableArray<NPDropDownView *> *_dropFlyouts;
	NSMutableArray<NSMutableArray<NSMenuItem *> *> *_dropPanelItems;
	NSInteger _openMenuIndex;
	id _dropClickMonitor;
	BOOL _windowClosed;
	sptr_t _menuSelStart;
	sptr_t _menuSelEnd;
	BOOL _menuSelValid;
}
@dynamic editorDocument;

static NSMutableArray<MainWindowController *> *NPLiveControllers(void) {
	static NSMutableArray<MainWindowController *> *live;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ live = [NSMutableArray array]; });
	return live;
}
+ (NSArray *)liveControllers { return [NPLiveControllers() copy]; }
+ (NSInteger)liveControllerCount { return (NSInteger)NPLiveControllers().count; }
+ (void)registerLive:(MainWindowController *)c {
	if (!c) return;
	NSMutableArray *live = NPLiveControllers();
	if ([live containsObject:c] == NO) [live addObject:c];
}
+ (void)unregisterLive:(MainWindowController *)c {
	[NPLiveControllers() removeObject:c];
}
- (BOOL)windowIsUsable {
	if (_windowClosed) return NO;
	if (self.isWindowLoaded == NO) return NO;
	if ([self runningHeadless]) return YES;
	return self.window.isVisible;
}
- (void)presentWindow {
	if ([self runningHeadless]) return;
	if (self.isWindowLoaded == NO) return;
	[self showWindow:nil];
	[self.window orderFrontRegardless];
}

- (instancetype)init {
	NSWindow *win = [[NSWindow alloc]
		initWithContentRect:NSMakeRect(140, 140, 900, 620)
		styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
			   NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable)
		backing:NSBackingStoreBuffered defer:NO];
	win.title = [NPL(@"Untitled") stringByAppendingString:@" - Notepad Mac"];
	win.minSize = NSMakeSize(400, 280);
	// chrome 跟随系统外观（暗色系统 → 暗色工具栏/状态栏）
	self = [super initWithWindow:win];
	if (self) {
		win.delegate = self;
		win.windowController = self;
		win.releasedWhenClosed = YES;
		[MainWindowController registerLive:self];
		_document = [[EditorDocument alloc] initWithNewUntitled:1];
		_documents = [NSMutableArray arrayWithObject:_document];
		_untitledSeq = 1;
		[self buildUI:win];
		[self rebuildTabBar];
		[self applyPersistedChrome];
		[self buildMenu];   // 按 Notepad4.rc 原文复刻
		[self refreshStatus];
		[self updateWindowTitle];
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(docCaretChanged:)
			name:@"EditorDocumentCaretChanged" object:_document];
		[NSApp addObserver:self forKeyPath:@"effectiveAppearance"
			options:NSKeyValueObservingOptionNew context:nullptr];
		[self installKeyEquivalentMonitor];
		[self installDropClickMonitor];
		[win makeFirstResponder:_document.editor.content];
	}
	return self;
}

- (void)dealloc {
	[MainWindowController unregisterLive:self];
	[_previewPane shutdown];
	if (_keyMonitor) { [NSEvent removeMonitor:_keyMonitor]; _keyMonitor = nil; }
	if (_dropClickMonitor) { [NSEvent removeMonitor:_dropClickMonitor]; _dropClickMonitor = nil; }
	[NSApp removeObserver:self forKeyPath:@"effectiveAppearance"];
}

#pragma mark - 布局（菜单栏 / 工具栏 / 标签 / 编辑器 / 状态栏）

- (void)buildUI:(NSWindow *)win {
	NPRootView *root = [[NPRootView alloc] initWithFrame:win.contentView.bounds];
	root.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
	root.controller = self;
	win.contentView = root;

	NPChromeView *mb = [[NPChromeView alloc] initWithFrame:NSMakeRect(0, 0, 900, 22)];
	mb.borderAtBottom = YES;
	mb.translatesAutoresizingMaskIntoConstraints = NO;
	[root addSubview:mb];
	_menuBar = mb;

	_openMenuIndex = -1;
	_dropFlyouts = [NSMutableArray array];
	_dropPanelItems = [NSMutableArray array];

	// ---- 工具栏：原版位图图标 + DefaultToolbarButtons 顺序 ----
	NPChromeView *bar = [[NPChromeView alloc] initWithFrame:NSMakeRect(0, 0, 900, 30)];
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
		{27, @selector(viewPreview), NO, "Preview"},
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
			NPImageButton *b = [[NPImageButton alloc] initWithFrame:NSMakeRect(0, 0, 24, 24)];
			b.icon = path ? [[NSImage alloc] initWithContentsOfFile:path] : [NSImage new];
			b.tbTarget = self;
			b.tbAction = e.act;
			b.toolTip = e.tip ? NPL([NSString stringWithUTF8String:e.tip]) : nil;
			b.translatesAutoresizingMaskIntoConstraints = NO;
			[b.widthAnchor constraintEqualToConstant:(e.dropdown ? 32 : 24)].active = YES;
			[b.heightAnchor constraintEqualToConstant:24].active = YES;
			if (e.dropdown) {
				b.hasDropdown = YES;
				if (e.act == @selector(tbOpenDropdown))
					b.tbDropAction = @selector(tbOpenMenu);
				else if (e.act == @selector(tbFoldDropdown))
					b.tbDropAction = @selector(tbFoldMenu);
				b.toolTip = [b.toolTip stringByAppendingString:@" ▾"];
			}
			v = b;
		}
		[bar addSubview:v];
		if (!prev) {
			[v.leadingAnchor constraintEqualToAnchor:bar.leadingAnchor constant:6].active = YES;
		} else if (e.icon < 0) {
			[prev.trailingAnchor constraintEqualToAnchor:v.leadingAnchor constant:6].active = YES;
		} else {
			[prev.trailingAnchor constraintEqualToAnchor:v.leadingAnchor constant:-3].active = YES;
		}
		[v.centerYAnchor constraintEqualToAnchor:bar.centerYAnchor].active = YES;
		prev = v;
	}
	[bar.trailingAnchor constraintGreaterThanOrEqualToAnchor:prev.trailingAnchor constant:4].active = YES;

	NPChromeView *tabs = [[NPChromeView alloc] initWithFrame:NSMakeRect(0, 0, 900, 26)];
	tabs.borderAtBottom = YES;
	tabs.translatesAutoresizingMaskIntoConstraints = NO;
	[root addSubview:tabs];
	_tabBar = tabs;

	// ---- 编辑器（占满中间；预览时左右分栏）----
	_workSplit = [[NPWorkSplit alloc] initWithFrame:NSZeroRect];
	_workSplit.vertical = YES;
	_workSplit.dividerStyle = NSSplitViewDividerStyleThick;
	_workSplit.delegate = self;
	_workSplit.translatesAutoresizingMaskIntoConstraints = NO;
	[root addSubview:_workSplit];
	_editorHost = [[NSView alloc] initWithFrame:NSZeroRect];
	_editorHost.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
	_editorHost.translatesAutoresizingMaskIntoConstraints = YES;
	[_editorHost setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
	[_editorHost setContentCompressionResistancePriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
	[_workSplit addSubview:_editorHost];
	[_workSplit setHoldingPriority:1 forSubviewAtIndex:0];
	_previewPane = [[PreviewPane alloc] initWithFrame:NSZeroRect];
	_previewPane.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
	_previewPane.translatesAutoresizingMaskIntoConstraints = YES;
	[_previewPane setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
	[_previewPane setContentCompressionResistancePriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
	__weak typeof(self) weakSelf = self;
	_previewPane.onHTMLEdited = ^(NSString *html) { [weakSelf applyPreviewHTMLEdit:html]; };
	_previewPane.onPreviewScroll = ^(NSInteger srcLine, CGFloat frac) {
		MainWindowController *s = weakSelf;
		if (s == nil || s->_previewSyncing) return;
		[s applyPreviewScrollLine:srcLine fraction:frac];
	};
	_document.editor.translatesAutoresizingMaskIntoConstraints = NO;
	[_editorHost addSubview:_document.editor];
	[_editorHost.leadingAnchor constraintEqualToAnchor:_document.editor.leadingAnchor].active = YES;
	[_editorHost.trailingAnchor constraintEqualToAnchor:_document.editor.trailingAnchor].active = YES;
	[_editorHost.topAnchor constraintEqualToAnchor:_document.editor.topAnchor].active = YES;
	[_editorHost.bottomAnchor constraintEqualToAnchor:_document.editor.bottomAnchor].active = YES;

	// ---- 状态栏 ----
	_statusBar = [[StatusBarView alloc] initWithFrame:NSMakeRect(0, 0, 900, 22)];
	_statusBar.translatesAutoresizingMaskIntoConstraints = NO;
	[_statusBar setPreviewTarget:self];
	[root addSubview:_statusBar];

	// 约束
	[root.leadingAnchor constraintEqualToAnchor:mb.leadingAnchor].active = YES;
	[root.trailingAnchor constraintEqualToAnchor:mb.trailingAnchor].active = YES;
	[root.topAnchor constraintEqualToAnchor:mb.topAnchor].active = YES;
	_menuBarHeight = [mb.heightAnchor constraintEqualToConstant:28];
	_menuBarHeight.active = YES;
	[mb.bottomAnchor constraintEqualToAnchor:bar.topAnchor].active = YES;
	[root.leadingAnchor constraintEqualToAnchor:bar.leadingAnchor].active = YES;
	[root.trailingAnchor constraintEqualToAnchor:bar.trailingAnchor].active = YES;
	_toolBarHeight = [bar.heightAnchor constraintEqualToConstant:30];
	_toolBarHeight.active = YES;

	[root.leadingAnchor constraintEqualToAnchor:_tabBar.leadingAnchor].active = YES;
	[root.trailingAnchor constraintEqualToAnchor:_tabBar.trailingAnchor].active = YES;
	[bar.bottomAnchor constraintEqualToAnchor:_tabBar.topAnchor].active = YES;
	_tabBarHeight = [_tabBar.heightAnchor constraintEqualToConstant:26];
	_tabBarHeight.active = YES;
	NPTabPlus *plus = [[NPTabPlus alloc] initWithFrame:NSMakeRect(0, 0, 24, 22)];
	plus.translatesAutoresizingMaskIntoConstraints = NO;
	plus.target = self;
	plus.toolTip = NPL(@"New");
	[_tabBar addSubview:plus];
	_tabPlus = plus;
	[_tabBar.trailingAnchor constraintEqualToAnchor:plus.trailingAnchor constant:4].active = YES;
	[plus.centerYAnchor constraintEqualToAnchor:_tabBar.centerYAnchor].active = YES;
	[plus.widthAnchor constraintEqualToConstant:24].active = YES;
	[plus.heightAnchor constraintEqualToConstant:22].active = YES;

	[root.leadingAnchor constraintEqualToAnchor:_workSplit.leadingAnchor].active = YES;
	[root.trailingAnchor constraintEqualToAnchor:_workSplit.trailingAnchor].active = YES;
	[_tabBar.bottomAnchor constraintEqualToAnchor:_workSplit.topAnchor].active = YES;

	[root.leadingAnchor constraintEqualToAnchor:_statusBar.leadingAnchor].active = YES;
	[root.trailingAnchor constraintEqualToAnchor:_statusBar.trailingAnchor].active = YES;
	_statusBarHeight = [_statusBar.heightAnchor constraintEqualToConstant:22];
	_statusBarHeight.active = YES;
	[_workSplit.bottomAnchor constraintEqualToAnchor:_statusBar.topAnchor].active = YES;
	[root.bottomAnchor constraintEqualToAnchor:_statusBar.bottomAnchor].active = YES;

	_findPanel = [[FindReplacePanel alloc] initWithFrame:NSMakeRect(0, 0, 620, 84)];
	[_findPanel attachToWindow:win];
	// 面板底边贴状态栏顶部（不贴边会被编辑区盖住）
	[_findPanel.bottomAnchor constraintEqualToAnchor:_statusBar.topAnchor].active = YES;

	// 下拉浮在内容之上：贴菜单标题，宽度跟条目走，不插入布局、不拉满窗口
	_dropDown = [[NPDropDownView alloc] initWithFrame:NSZeroRect];
	_dropDown.hidden = YES;
	[self styleDropPanel:_dropDown];
	[root addSubview:_dropDown positioned:NSWindowAbove relativeTo:nil];
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
static NSString *Fn(unichar k) { return [NSString stringWithCharacters:&k length:1]; }
static BOOL NPPrefBool(NSString *key, BOOL fallback) {
	NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
	return [d objectForKey:key] ? [d boolForKey:key] : fallback;
}

- (void)buildMenu {
	NSMenu *mb = [[NSMenu alloc] init];

	// App 菜单（macOS 必需）
	NSMenuItem *appItem = [mb addItemWithTitle:NPL(@"Notepad Mac") action:nil keyEquivalent:@""];
	NSMenu *appMenu = M(NPL(@""));
	[appMenu addItemWithTitle:NPL(@"About Notepad Mac") action:@selector(orderFrontStandardAboutPanel:) keyEquivalent:@""];
	MSep(appMenu);
	[appMenu addItemWithTitle:NPL(@"Hide Notepad Mac") action:@selector(hide:) keyEquivalent:@"h"];
	[appMenu addItemWithTitle:NPL(@"Hide Others") action:@selector(hideOtherApplications:) keyEquivalent:@"h"].keyEquivalentModifierMask = NSEventModifierFlagCommand|NSEventModifierFlagOption;
	[appMenu addItemWithTitle:NPL(@"Show All") action:@selector(unhideAllApplications:) keyEquivalent:@""];
	MSep(appMenu);
	[appMenu addItemWithTitle:NPL(@"Quit Notepad Mac") action:@selector(terminate:) keyEquivalent:@"q"];
	appItem.submenu = appMenu;

	NSString *F2 = Fn(NSF2FunctionKey);
	NSString *F3 = Fn(NSF3FunctionKey);
	NSString *F4 = Fn(NSF4FunctionKey);
	NSString *F5 = Fn(NSF5FunctionKey);
	NSString *F6 = Fn(NSF6FunctionKey);
	NSString *F7 = Fn(NSF7FunctionKey);
	NSString *F10 = Fn(NSF10FunctionKey);
	NSString *F11 = Fn(NSF11FunctionKey);
	NSString *F12 = Fn(NSF12FunctionKey);

	// ===== File =====
	NSMenu *file = M(NPL(@"File"));
	MI(file, NPL(@"New\tCtrl+N"), @selector(fileNew), @"n", 0);
	MI(file, NPL(@"New Window\tAlt+N"), @selector(fileNewWindow), @"n", NSEventModifierFlagOption);
	MI(file, NPL(@"Close Tab\tCtrl+W"), @selector(fileCloseTab), @"w", 0);
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
	MI(fms, NPL(@"Large File Mode"), @selector(toggleLargeFileMode), @"", 0);
	fm.submenu = fms;
	MI(file, NPL(@"Revert\tF5"), @selector(fileRevert), F5, 0);
	NSMenuItem *rl = MI(file, NPL(@"Reload"), nil, @"", 0);
	NSMenu *rls = M(NPL(@""));
	MI(rls, NPL(@"As UTF-8\tShift+F8"), @selector(reloadUTF8), @"", 0);
	MI(rls, NPL(@"As ANSI\tCtrl+Shift+A"), @selector(reloadANSI), @"", 0);
	MI(rls, NPL(@"As GBK"), @selector(reloadGBK), @"", 0);
	MI(rls, NPL(@"As BIG5"), @selector(reloadBIG5), @"", 0);
	MI(rls, NPL(@"As Shift-JIS"), @selector(reloadShiftJIS), @"", 0);
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
	MI(encs, NPL(@"GBK"), @selector(setEncodingGBK), @"", 0);
	MI(encs, NPL(@"BIG5"), @selector(setEncodingBIG5), @"", 0);
	MI(encs, NPL(@"Shift-JIS"), @selector(setEncodingShiftJIS), @"", 0);
	enc.submenu = encs;
	NSMenuItem *eol = MI(file, NPL(@"Line Endings"), nil, @"", 0);
	NSMenu *eols = M(NPL(@""));
	MI(eols, NPL(@"Windows (CR+LF)"), @selector(setEOLCRLF), @"", 0);
	MI(eols, NPL(@"Unix/macOS (LF)"), @selector(setEOLLF), @"", 0);
	MI(eols, NPL(@"Classic Mac (CR)"), @selector(setEOLCR), @"", 0);
	eol.submenu = eols;
	MSep(file);
	MI(file, NPL(@"Page Setup..."), @selector(filePageSetup), @"", 0);
	MI(file, NPL(@"Print...\tCtrl+P"), @selector(printDocument), @"p", 0);
	MSep(file);
	MI(file, NPL(@"Properties..."), @selector(fileProperties), @"", 0);
	MI(file, NPL(@"Open Containing Folder"), @selector(openContainingFolder), @"", 0);
	MI(file, NPL(@"Create Desktop Shortcut"), @selector(fileCreateDesktopShortcut), @"", 0);
	MI(file, NPL(@"Manage Favorites"), @selector(fileManageFavorites), @"", 0);
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
	MI(edit, NPL(@"Copy Add\tCtrl+E"), @selector(editCopyAdd), @"e", 0);
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
	MI(ccs, NPL(@"File Name and Ext."), @selector(copyFileNameAndExt), @"", 0);
	MI(ccs, NPL(@"Full Path Name\tAlt+Shift+F9"), @selector(copyFullPath), @"", 0);
	MI(ccs, NPL(@"Window Position"), @selector(copyWinPos), @"", 0);
	MSep(ccs);
	MI(ccs, NPL(@"Copy All\tAlt+A"), @selector(copyAll), @"a", NSEventModifierFlagOption);
	MI(ccs, NPL(@"Copy Add\tCtrl+E"), @selector(editCopyAdd), @"e", 0);
	MI(ccs, NPL(@"Copy as RTF"), @selector(copyAsRTF), @"", 0);
	cc.submenu = ccs;
	MSep(edit);
	NSMenuItem *sel = MI(edit, NPL(@"Selection"), nil, @"", 0);
	NSMenu *sels = M(NPL(@""));
	MI(sels, NPL(@"Duplicate\tAlt+D"), @selector(editDuplicate), @"d", NSEventModifierFlagOption);
	MSep(sels);
	MI(sels, NPL(@"Toggle Line Comment\tCtrl+/"), @selector(editLineComment), @"/", 0);
	MI(sels, NPL(@"Toggle Stream Comment\tCtrl+Q"), @selector(editStreamComment), @"q", NSEventModifierFlagControl);
	MI(sels, NPL(@"Indent\tTab"), @selector(editIndent), @"", 0);
	MI(sels, NPL(@"Unindent\tShift+Tab"), @selector(editUnindent), @"", 0);
	MSep(sels);
	MI(sels, NPL(@"Strip Trailing Blanks\tAlt+T"), @selector(editTrimTrailing), @"t", NSEventModifierFlagOption);
	MI(sels, NPL(@"Strip First Character\tAlt+Z"), @selector(editStripFirstChar), @"z", NSEventModifierFlagOption);
	MI(sels, NPL(@"Strip Last Character\tAlt+L"), @selector(editStripLastChar), @"l", NSEventModifierFlagOption);
	MI(sels, NPL(@"Strip Leading Blanks\tAlt+K"), @selector(editTrimLeading), @"k", NSEventModifierFlagOption);
	MSep(sels);
	MI(sels, NPL(@"Merge Blank Lines\tAlt+B"), @selector(editMergeBlankLines), @"b", NSEventModifierFlagOption);
	MI(sels, NPL(@"Remove Blank Lines\tAlt+R"), @selector(editRemoveBlankLines), @"r", NSEventModifierFlagOption);
	MI(sels, NPL(@"Merge Duplicate Lines"), @selector(editMergeDuplicateLines), @"", 0);
	MI(sels, NPL(@"Remove Duplicate Lines"), @selector(editRemoveDuplicateLines), @"", 0);
	MI(sels, NPL(@"Pad with Spaces\tAlt+P"), @selector(editPadWithSpaces), @"p", NSEventModifierFlagOption);
	MI(sels, NPL(@"Compress Whitespace\tAlt+W"), @selector(editCompressWhitespace), @"w", NSEventModifierFlagOption);
	sel.submenu = sels;
	NSMenuItem *encSel = MI(edit, NPL(@"Enclose Selection"), nil, @"", 0);
	NSMenu *encSelMenu = M(NPL(@""));
	MI(encSelMenu, NPL(@"With..."), @selector(editEncloseCustom), @"", 0);
	MI(encSelMenu, NPL(@"Insert XML/HTML Tag"), @selector(editInsertXMLTag), @"", 0);
	MSep(encSelMenu);
	MI(encSelMenu, NPL(@"Enclose ()"), @selector(editEncloseParen), @"", 0);
	MI(encSelMenu, NPL(@"Enclose []"), @selector(editEncloseBracket), @"", 0);
	MI(encSelMenu, NPL(@"Enclose {}"), @selector(editEncloseBrace), @"", 0);
	MI(encSelMenu, NPL(@"Enclose <>"), @selector(editEncloseAngle), @"", 0);
	MI(encSelMenu, NPL(@"Enclose Quotes"), @selector(editEncloseQuote), @"", 0);
	MI(encSelMenu, NPL(@"Enclose Single Quotes"), @selector(editEncloseSingleQuote), @"", 0);
	MI(encSelMenu, NPL(@"Enclose Backticks"), @selector(editEncloseBacktick), @"", 0);
	MSep(encSelMenu);
	MI(encSelMenu, NPL(@"Triple Single Quotes"), @selector(editEncloseTripleSQ), @"", 0);
	MI(encSelMenu, NPL(@"Triple Double Quotes"), @selector(editEncloseTripleDQ), @"", 0);
	MI(encSelMenu, NPL(@"Triple Backticks"), @selector(editEncloseTripleBT), @"", 0);
	encSel.submenu = encSelMenu;
	NSMenuItem *lines = MI(edit, NPL(@"Lines"), nil, @"", 0);
	NSMenu *lss = M(NPL(@""));
	MI(lss, NPL(@"Move Up\tAlt+Up"), @selector(editMoveLineUp), Fn(NSUpArrowFunctionKey), NSEventModifierFlagOption);
	MI(lss, NPL(@"Move Down\tAlt+Down"), @selector(editMoveLineDown), Fn(NSDownArrowFunctionKey), NSEventModifierFlagOption);
	MI(lss, NPL(@"Transpose\tAlt+S"), @selector(editTranspose), @"s", NSEventModifierFlagOption);
	MSep(lss);
	MI(lss, NPL(@"Sort Lines"), @selector(editSortLines), @"", 0);
	MI(lss, NPL(@"Sort Lines Descending"), @selector(editSortLinesDescending), @"", 0);
	MI(lss, NPL(@"Modify Lines"), @selector(editModifyLines), @"", 0);
	MI(lss, NPL(@"Align Left"), @selector(editAlignLeft), @"", 0);
	MI(lss, NPL(@"Align Right"), @selector(editAlignRight), @"", 0);
	MI(lss, NPL(@"Align Center"), @selector(editAlignCenter), @"", 0);
	MI(lss, NPL(@"Align Justify"), @selector(editAlignJustify), @"", 0);
	MSep(lss);
	MI(lss, NPL(@"Duplicate Line\tCtrl+D"), @selector(editDuplicateLine), @"d", 0);
	MI(lss, NPL(@"Cut Line\tCtrl+Shift+X"), @selector(editCutLine), @"x", NSEventModifierFlagCommand|NSEventModifierFlagShift);
	MI(lss, NPL(@"Copy Line\tCtrl+Shift+C"), @selector(editCopyLine), @"c", NSEventModifierFlagCommand|NSEventModifierFlagShift);
	MI(lss, NPL(@"Delete Line\tCtrl+Shift+D"), @selector(editDeleteLine), @"d", NSEventModifierFlagCommand|NSEventModifierFlagShift);
	MSep(lss);
	MI(lss, NPL(@"Join Lines\tCtrl+J"), @selector(editJoinLines), @"j", 0);
	MI(lss, NPL(@"Split Lines\tCtrl+I"), @selector(editSplitLines), @"i", 0);
	MI(lss, NPL(@"Column Wrap"), @selector(editColumnWrap), @"", 0);
	MI(lss, NPL(@"Join Paragraphs"), @selector(editJoinParagraphs), @"", 0);
	lines.submenu = lss;
	NSMenuItem *conv = MI(edit, NPL(@"Convert"), nil, @"", 0);
	NSMenu *cvs = M(NPL(@""));
	MI(cvs, NPL(@"UPPER CASE\tCtrl+Shift+U"), @selector(editUpper), @"u", NSEventModifierFlagCommand|NSEventModifierFlagShift);
	MI(cvs, NPL(@"lower case\tCtrl+U"), @selector(editLower), @"u", 0);
	MI(cvs, NPL(@"Invert Case"), @selector(editInvertCase), @"", 0);
	MI(cvs, NPL(@"Title Case"), @selector(editTitleCase), @"", 0);
	MI(cvs, NPL(@"Sentence Case"), @selector(editSentenceCase), @"", 0);
	MSep(cvs);
	MI(cvs, NPL(@"Tabify Selection"), @selector(editTabifySelection), @"", 0);
	MI(cvs, NPL(@"Untabify Selection"), @selector(editUntabifySelection), @"", 0);
	MI(cvs, NPL(@"Tabify Indent\tCtrl+Alt+T"), @selector(editTabify), @"t", NSEventModifierFlagCommand|NSEventModifierFlagOption);
	MI(cvs, NPL(@"Untabify Indent\tCtrl+Alt+S"), @selector(editUntabify), @"s", NSEventModifierFlagCommand|NSEventModifierFlagOption);
	MSep(cvs);
	MI(cvs, NPL(@"Number to Hex"), @selector(editNum2Hex), @"", 0);
	MI(cvs, NPL(@"Number to Decimal"), @selector(editNum2Dec), @"", 0);
	MI(cvs, NPL(@"Number to Binary"), @selector(editNum2Bin), @"", 0);
	MI(cvs, NPL(@"Number to Octal"), @selector(editNum2Oct), @"", 0);
	MI(cvs, NPL(@"Increase Number"), @selector(editIncreaseNumber), @"", 0);
	MI(cvs, NPL(@"Decrease Number"), @selector(editDecreaseNumber), @"", 0);
	conv.submenu = cvs;
	NSMenuItem *ins = MI(edit, NPL(@"Insert"), nil, @"", 0);
	NSMenu *insm = M(NPL(@""));
	MI(insm, NPL(@"Complete Word\tAlt+/"), @selector(editCompleteWord), @"/", NSEventModifierFlagOption);
	MSep(insm);
	MI(insm, NPL(@"Insert XML/HTML Tag"), @selector(editInsertXMLTag), @"", 0);
	MI(insm, NPL(@"New GUID"), @selector(insertGUID), @"", 0);
	NSMenuItem *uni = MI(insm, NPL(@"Unicode Control Character"), nil, @"", 0);
	NSMenu *unim = M(NPL(@""));
	MI(unim, NPL(@"Word Joiner"), @selector(insertUnicodeWJ), @"", 0);
	MI(unim, NPL(@"Zero Width Joiner"), @selector(insertUnicodeZWJ), @"", 0);
	MI(unim, NPL(@"Zero Width Non-Joiner"), @selector(insertUnicodeZWNJ), @"", 0);
	MI(unim, NPL(@"Left-to-Right Mark"), @selector(insertUnicodeLRM), @"", 0);
	MI(unim, NPL(@"Right-to-Left Mark"), @selector(insertUnicodeRLM), @"", 0);
	MI(unim, NPL(@"Left-to-Right Embedding"), @selector(insertUnicodeLRE), @"", 0);
	MI(unim, NPL(@"Right-to-Left Embedding"), @selector(insertUnicodeRLE), @"", 0);
	MI(unim, NPL(@"Left-to-Right Override"), @selector(insertUnicodeLRO), @"", 0);
	MI(unim, NPL(@"Right-to-Left Override"), @selector(insertUnicodeRLO), @"", 0);
	MI(unim, NPL(@"Left-to-Right Isolate"), @selector(insertUnicodeLRI), @"", 0);
	MI(unim, NPL(@"Right-to-Left Isolate"), @selector(insertUnicodeRLI), @"", 0);
	MI(unim, NPL(@"First Strong Isolate"), @selector(insertUnicodeFSI), @"", 0);
	MI(unim, NPL(@"Pop Directional Isolate"), @selector(insertUnicodePDI), @"", 0);
	MI(unim, NPL(@"Pop Directional Formatting"), @selector(insertUnicodePDF), @"", 0);
	MI(unim, NPL(@"Arabic Letter Mark"), @selector(insertUnicodeALM), @"", 0);
	MI(unim, NPL(@"Record Separator"), @selector(insertUnicodeRS), @"", 0);
	MI(unim, NPL(@"Unit Separator"), @selector(insertUnicodeUS), @"", 0);
	MI(unim, NPL(@"Line Separator"), @selector(insertUnicodeLS), @"", 0);
	MI(unim, NPL(@"Paragraph Separator"), @selector(insertUnicodePS), @"", 0);
	MI(unim, NPL(@"Zero Width Space"), @selector(insertUnicodeZWSP), @"", 0);
	MI(unim, NPL(@"No-Break Space"), @selector(insertUnicodeNBSP), @"", 0);
	MI(unim, NPL(@"Soft Hyphen"), @selector(insertUnicodeSHY), @"", 0);
	uni.submenu = unim;
	MSep(insm);
	MI(insm, NPL(@"File Name"), @selector(insertFileName), @"", 0);
	MI(insm, NPL(@"File Name and Ext."), @selector(insertFileNameAndExt), @"", 0);
	MI(insm, NPL(@"Full Path Name"), @selector(insertPathName), @"", 0);
	MSep(insm);
	MI(insm, NPL(@"Current Date"), @selector(insertCurrentDate), @"", 0);
	MI(insm, NPL(@"Current Date Time"), @selector(insertDateTime), @"", 0);
	MI(insm, NPL(@"UTC Date Time"), @selector(insertUTCDateTime), @"", 0);
	MI(insm, NPL(@"Unix Timestamp"), @selector(insertUnixTimestamp), @"", 0);
	NSMenuItem *ots = MI(insm, NPL(@"Other Timestamps"), nil, @"", 0);
	NSMenu *otsm = M(NPL(@""));
	MI(otsm, NPL(@"Millisecond (ms)"), @selector(insertTimestampMs), @"", 0);
	MI(otsm, NPL(@"Microsecond (us)"), @selector(insertTimestampUs), @"", 0);
	MI(otsm, NPL(@"Nanosecond (ns)"), @selector(insertTimestampNs), @"", 0);
	ots.submenu = otsm;
	MI(insm, NPL(@"Short Date"), @selector(insertShortDate), @"", 0);
	MI(insm, NPL(@"Time/Date (Long Form)"), @selector(insertLongDate), @"", 0);
	MSep(insm);
	MI(insm, NPL(@"Encoding Name"), @selector(insertEncodingName), @"", 0);
	MI(insm, NPL(@"Shebang Line"), @selector(insertShebang), @"", 0);
	ins.submenu = insm;
	NSMenuItem *spc = MI(edit, NPL(@"Special"), nil, @"", 0);
	NSMenu *spcm = M(NPL(@""));
	MI(spcm, NPL(@"Char to Hex"), @selector(editChar2Hex), @"", 0);
	MI(spcm, NPL(@"Hex to Char"), @selector(editHex2Char), @"", 0);
	MI(spcm, NPL(@"Show Hex Code"), @selector(editShowHex), @"", 0);
	MI(spcm, NPL(@"Show Character Info"), @selector(editShowCharInfo), @"", 0);
	MSep(spcm);
	MI(spcm, NPL(@"Escape C Chars"), @selector(editEscapeCChars), @"", 0);
	MI(spcm, NPL(@"Unescape C Chars"), @selector(editUnescapeCChars), @"", 0);
	MSep(spcm);
	MI(spcm, NPL(@"Delete Line Left"), @selector(editDeleteLineLeft), @"", 0);
	MI(spcm, NPL(@"Delete Line Right"), @selector(editDeleteLineRight), @"", 0);
	MI(spcm, NPL(@"Delete Word Left"), @selector(editDeleteWordLeft), @"", 0);
	MI(spcm, NPL(@"Delete Word Right"), @selector(editDeleteWordRight), @"", 0);
	MSep(spcm);
	MI(spcm, NPL(@"Update Timestamps"), @selector(editUpdateTimestamps), @"", 0);
	spc.submenu = spcm;

	{ NSMenuItem *_it_edit = [mb addItemWithTitle:NPL(@"Edit") action:nil keyEquivalent:@""]; _it_edit.submenu = edit; }

	// ===== Search =====
	NSMenu *search = M(NPL(@"Search"));
	MI(search, NPL(@"Find...\tCtrl+F"), @selector(searchFind), @"f", 0);
	MI(search, NPL(@"Save Find Text"), @selector(searchSaveFindText), @"", 0);
	MI(search, NPL(@"Find Next\tF3"), @selector(searchFindNext), F3, 0);
	MI(search, NPL(@"Find Previous\tShift+F3"), @selector(searchFindPrev), F3, NSEventModifierFlagShift);
	MI(search, NPL(@"Replace...\tCtrl+H"), @selector(searchReplace), @"h", 0);
	MI(search, NPL(@"Replace Next\tF4"), @selector(searchReplaceNext), F4, 0);
	MSep(search);
	MI(search, NPL(@"Find Matching Brace\tCtrl+B"), @selector(searchFindMatchingBrace), @"b", 0);
	MI(search, NPL(@"Select to Matching Brace\tCtrl+Shift+B"), @selector(searchSelectToBrace), @"b", NSEventModifierFlagCommand|NSEventModifierFlagShift);
	MI(search, NPL(@"Select Word"), @selector(searchSelectWord), @"", 0);
	MI(search, NPL(@"Select Line"), @selector(searchSelectLine), @"", 0);
	MI(search, NPL(@"Select Lines in Current Block"), @selector(searchSelectLineBlock), @"", 0);
	MI(search, NPL(@"Select to Document Start"), @selector(searchSelectToDocStart), @"", 0);
	MI(search, NPL(@"Select to Document End"), @selector(searchSelectToDocEnd), @"", 0);
	MI(search, NPL(@"Select to Next"), @selector(searchSelectToNext), @"", 0);
	MI(search, NPL(@"Select to Previous"), @selector(searchSelectToPrev), @"", 0);
	MSep(search);
	NSMenuItem *bm = MI(search, NPL(@"Bookmarks"), nil, @"", 0);
	NSMenu *bms = M(NPL(@""));
	MI(bms, NPL(@"Toggle\tCtrl+F2"), @selector(bookmarkToggle), F2, NSEventModifierFlagCommand);
	MSep(bms);
	MI(bms, NPL(@"Goto Next\tF2"), @selector(bookmarkNext), F2, 0);
	MI(bms, NPL(@"Goto Previous\tShift+F2"), @selector(bookmarkPrev), F2, NSEventModifierFlagShift);
	MSep(bms);
	MI(bms, NPL(@"Select All Bookmarks"), @selector(bookmarkSelectAll), @"", 0);
	MI(bms, NPL(@"Clear All\tAlt+F2"), @selector(bookmarkClear), F2, NSEventModifierFlagOption);
	bm.submenu = bms;
	NSMenuItem *go = MI(search, NPL(@"Goto"), nil, @"", 0);
	NSMenu *gom = M(NPL(@""));
	MI(gom, NPL(@"Goto Line...\tCtrl+G"), @selector(gotoLine), @"g", 0);
	MSep(gom);
	MI(gom, NPL(@"Goto Block Start"), @selector(gotoBlockStart), @"", 0);
	MI(gom, NPL(@"Goto Block End"), @selector(gotoBlockEnd), @"", 0);
	MI(gom, NPL(@"Goto Previous Block"), @selector(gotoPreviousBlock), @"", 0);
	MI(gom, NPL(@"Goto Next Block"), @selector(gotoNextBlock), @"", 0);
	MI(gom, NPL(@"Goto Previous Sibling Block"), @selector(gotoPrevSiblingBlock), @"", 0);
	MI(gom, NPL(@"Goto Next Sibling Block"), @selector(gotoNextSiblingBlock), @"", 0);
	MSep(gom);
	MI(gom, NPL(@"Goto Selection Start"), @selector(gotoSelStart), @"", 0);
	MI(gom, NPL(@"Goto Selection End"), @selector(gotoSelEnd), @"", 0);
	go.submenu = gom;
	{ NSMenuItem *_it_search = [mb addItemWithTitle:NPL(@"Search") action:nil keyEquivalent:@""]; _it_search.submenu = search; }

	// ===== View =====
	NSMenu *view = M(NPL(@"View"));
	_wordWrapItem = MI(view, NPL(@"Word Wrap\tCtrl+Shift+W"), @selector(viewWordWrap), @"w", NSEventModifierFlagCommand|NSEventModifierFlagShift);
	_wordWrapItem.state = NPPrefBool(@"NP4WordWrap", NO) ? NSControlStateValueOn : NSControlStateValueOff;
	MI(view, NPL(@"Preview\tCtrl+Shift+P"), @selector(viewPreview), @"p", NSEventModifierFlagCommand|NSEventModifierFlagShift);
	MI(view, NPL(@"Long Line Marker\tCtrl+Shift+L"), @selector(viewLongLineMarker), @"l", NSEventModifierFlagCommand|NSEventModifierFlagShift);
	MI(view, NPL(@"Indentation Guides\tCtrl+Shift+G"), @selector(viewIndentGuides), @"g", NSEventModifierFlagCommand|NSEventModifierFlagShift);
	MSep(view);
	MI(view, NPL(@"Show Whitespace\tCtrl+Shift+8"), @selector(viewWhitespace), @"8", NSEventModifierFlagCommand|NSEventModifierFlagShift);
	MI(view, NPL(@"Show Line Endings\tCtrl+Shift+9"), @selector(viewEOLs), @"9", NSEventModifierFlagCommand|NSEventModifierFlagShift);
	MSep(view);
	MI(view, NPL(@"Visual Brace Matching\tCtrl+Shift+V"), @selector(viewBraceMatch), @"v", NSEventModifierFlagCommand|NSEventModifierFlagShift);
	MI(view, NPL(@"Detect URLs"), @selector(viewDetectURLs), @"", 0);
	MSep(view);
	_lineNumbersItem = MI(view, NPL(@"Line Numbers\tCtrl+Shift+N"), @selector(viewLineNumbers), @"n", NSEventModifierFlagCommand|NSEventModifierFlagShift);
	_lineNumbersItem.state = NPPrefBool(@"NP4ShowLineNumbers", YES) ? NSControlStateValueOn : NSControlStateValueOff;
	MI(view, NPL(@"Bookmark Margin\tCtrl+Shift+M"), @selector(viewBookmarkMargin), @"m", NSEventModifierFlagCommand|NSEventModifierFlagShift);
	MSep(view);
	MI(view, NPL(@"Show Code Folding"), @selector(viewCodeFolding), @"", 0);
	NSMenuItem *fold = MI(view, NPL(@"Fold"), nil, @"", 0);
	NSMenu *foldm = M(NPL(@""));
	MI(foldm, NPL(@"Toggle Current Fold"), @selector(foldToggleCurrent), @"", 0);
	MI(foldm, NPL(@"Fold All"), @selector(foldAll), @"", 0);
	MI(foldm, NPL(@"Unfold All"), @selector(unfoldAll), @"", 0);
	MI(foldm, NPL(@"Toggle All Folds"), @selector(foldToggleAll), @"", 0);
	fold.submenu = foldm;
	NSMenuItem *zm = MI(view, NPL(@"Zoom"), nil, @"", 0);
	NSMenu *zmm = M(NPL(@""));
	MI(zmm, NPL(@"Zoom In\tCtrl++"), @selector(viewZoomIn), @"+", 0);
	MI(zmm, NPL(@"Zoom Out\tCtrl+-"), @selector(viewZoomOut), @"-", 0);
	MI(zmm, NPL(@"Reset Zoom\tCtrl+\\"), @selector(viewZoomReset), @"\\", 0);
	zm.submenu = zmm;
	MI(view, NPL(@"Toggle Full Screen\tF11"), @selector(toggleFullScreen), F11, 0);
	{ NSMenuItem *_it_view = [mb addItemWithTitle:NPL(@"View") action:nil keyEquivalent:@""]; _it_view.submenu = view; }

	// ===== Scheme =====
	NSMenu *scheme = M(NPL(@"Scheme"));
	MI(scheme, NPL(@"Syntax Scheme...\tF12"), @selector(schemeChoose), F12, 0);
	MI(scheme, NPL(@"Customize Schemes"), @selector(schemeCustomize), @"", 0);
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
	_langSystemItem = MI(langs, NPL(@"Follow System"), @selector(languageSystem), @"", 0);
	_langSystemItem.representedObject = @"system";
	MSep(langs);
	_langItems = [NSMutableArray array];
	for (NSDictionary *e in NPLanguageCatalog()) {
		NSMenuItem *it = MI(langs, e[@"name"], @selector(languagePicked:), @"", 0);
		it.representedObject = e[@"code"];
		[_langItems addObject:it];
	}
	lang.submenu = langs;
	[self updateLanguageMenuState];
	NSMenuItem *ap = MI(settings, NPL(@"Appearance"), nil, @"", 0);
	NSMenu *aps = M(NPL(@""));
	MI(aps, NPL(@"Show Menu\tAlt+F11"), @selector(toggleMenuBar), @"", 0);
	MI(aps, NPL(@"Show Toolbar\tCtrl+F11"), @selector(toggleToolbar), @"", 0);
	MI(aps, NPL(@"Show Statusbar\tShift+F11"), @selector(toggleStatusBar), @"", 0);
	ap.submenu = aps;
	MI(settings, NPL(@"Save Settings On Exit"), @selector(settingsSaveOnExit), @"", 0);
	MI(settings, NPL(@"Save Settings Now\tF7"), @selector(settingsSaveNow), F7, 0);
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
	MI(wsm, NPL(@"Open Containing Folder"), @selector(openContainingFolder), @"", 0);
	MSep(wsm);
	MI(wsm, NPL(@"Calculate Expression"), @selector(editCalculateExpression), @"", 0);
	MSep(wsm);
	MI(wsm, NPL(@"Search with &Google"), @selector(actionSearchGoogle), @"", 0);
	MI(wsm, NPL(@"Search with Bing"), @selector(actionSearchBing), @"", 0);
	MI(wsm, NPL(@"Search on Wikipedia"), @selector(actionSearchWiki), @"", 0);
	ws.submenu = wsm;
	NSMenuItem *b64 = MI(tools, NPL(@"Base64"), nil, @"", 0);
	NSMenu *b64m = M(NPL(@""));
	MI(b64m, NPL(@"Standard Encode"), @selector(base64Encode), @"", 0);
	MI(b64m, NPL(@"URL Safe Encode"), @selector(base64URLSafeEncode), @"", 0);
	MI(b64m, NPL(@"Encode as HTML Embedded Image"), @selector(base64HTMLEmbed), @"", 0);
	MI(b64m, NPL(@"Decode"), @selector(base64Decode), @"", 0);
	MI(b64m, NPL(@"Decode as Hex"), @selector(base64DecodeHex), @"", 0);
	b64.submenu = b64m;
	NSMenuItem *tr = MI(tools, NPL(@"Text Transliteration"), nil, @"", 0);
	NSMenu *trm = M(NPL(@""));
	MI(trm, NPL(@"Halfwidth to Fullwidth"), @selector(mapHalfToFull), @"", 0);
	MI(trm, NPL(@"Fullwidth to Halfwidth"), @selector(mapFullToHalf), @"", 0);
	MSep(trm);
	MI(trm, NPL(@"Traditional to Simplified Chinese"), @selector(mapTradToSimp), @"", 0);
	MI(trm, NPL(@"Simplified to Traditional Chinese"), @selector(mapSimpToTrad), @"", 0);
	MSep(trm);
	MI(trm, NPL(@"Katakana to Hiragana"), @selector(mapKataToHira), @"", 0);
	MI(trm, NPL(@"Hiragana to Katakana"), @selector(mapHiraToKata), @"", 0);
	MSep(trm);
	MI(trm, NPL(@"Hanja to Hangul"), @selector(mapHanjaToHangul), @"", 0);
	MI(trm, NPL(@"Hangul Decomposition"), @selector(mapHangulDecomp), @"", 0);
	MSep(trm);
	MI(trm, NPL(@"Bengali to Latin"), @selector(mapBengaliLatin), @"", 0);
	MI(trm, NPL(@"Cyrillic to Latin"), @selector(mapCyrillicLatin), @"", 0);
	MI(trm, NPL(@"Devanagari to Latin"), @selector(mapDevanagariLatin), @"", 0);
	MI(trm, NPL(@"Malayalam to Latin"), @selector(mapMalayalamLatin), @"", 0);
	tr.submenu = trm;
	NSMenuItem *webt = MI(tools, NPL(@"Web Tools"), nil, @"", 0);
	NSMenu *wtm = M(NPL(@""));
	MI(wtm, NPL(@"CSS/JS/JSON Compress"), @selector(editCodeCompress), @"", 0);
	MI(wtm, NPL(@"CSS/JS/JSON Pretty"), @selector(editCodePretty), @"", 0);
	MSep(wtm);
	MI(wtm, NPL(@"Evaluate JS Expression"), @selector(editCalculateExpression), @"", 0);
	MI(wtm, NPL(@"Escape HTML/XML Chars"), @selector(webEscapeHTML), @"", 0);
	MI(wtm, NPL(@"Unescape HTML/XML Chars"), @selector(webUnescapeHTML), @"", 0);
	MSep(wtm);
	MI(wtm, NPL(@"URL Encode\tCtrl+Shift+E"), @selector(urlEncode), @"e", NSEventModifierFlagCommand|NSEventModifierFlagShift);
	MI(wtm, NPL(@"URL Component Encode"), @selector(urlComponentEncode), @"", 0);
	MI(wtm, NPL(@"URL Decode\tCtrl+Shift+R"), @selector(urlDecode), @"r", NSEventModifierFlagCommand|NSEventModifierFlagShift);
	webt.submenu = wtm;
	{ NSMenuItem *_it_tools = [mb addItemWithTitle:NPL(@"Tools") action:nil keyEquivalent:@""]; _it_tools.submenu = tools; }

	// ===== Help =====
	NSMenu *help = M(NPL(@"Help"));
	MI(help, NPL(@"Project Home"), @selector(helpHome), @"", 0);
	MI(help, NPL(@"Donate"), @selector(helpDonate), @"", 0);
	MI(help, NPL(@"About Notepad Mac"), @selector(orderFrontStandardAboutPanel:), @"", 0);
	{ NSMenuItem *_it_help = [mb addItemWithTitle:NPL(@"Help") action:nil keyEquivalent:@""]; _it_help.submenu = help; }

	_inWindowMenus = [NSMutableArray arrayWithObjects:file, edit, search, view, scheme, settings, tools, help, nil];
	NSMutableArray *titles = [NSMutableArray array];
	for (NSMenu *m in _inWindowMenus) [titles addObject:m.title];
	[self rebuildMenuBarButtons:titles];
	NSApp.mainMenu = [self buildAppMenu];
}

- (NSMenu *)buildAppMenu {
	NSMenu *appMenu = [[NSMenu alloc] initWithTitle:@"Notepad Mac"];
	[appMenu addItemWithTitle:NPL(@"About Notepad Mac") action:@selector(orderFrontStandardAboutPanel:) keyEquivalent:@""];
	[appMenu addItem:[NSMenuItem separatorItem]];
	NSMenuItem *svc = [appMenu addItemWithTitle:NPL(@"Services") action:nil keyEquivalent:@""];
	NSMenu *svcMenu = [[NSMenu alloc] initWithTitle:NPL(@"Services")];
	svc.submenu = svcMenu;
	NSApp.servicesMenu = svcMenu;
	[appMenu addItem:[NSMenuItem separatorItem]];
	[appMenu addItemWithTitle:NPL(@"Hide Notepad Mac") action:@selector(hide:) keyEquivalent:@"h"];
	NSMenuItem *ho = [appMenu addItemWithTitle:NPL(@"Hide Others") action:@selector(hideOtherApplications:) keyEquivalent:@"h"];
	ho.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagOption;
	[appMenu addItemWithTitle:NPL(@"Show All") action:@selector(unhideAllApplications:) keyEquivalent:@""];
	[appMenu addItem:[NSMenuItem separatorItem]];
	[appMenu addItemWithTitle:NPL(@"Quit Notepad Mac") action:@selector(terminate:) keyEquivalent:@"q"];
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
		NPMenuBarButton *b = [NPMenuBarButton buttonWithTitle:titles[i] target:self action:@selector(menuBarClicked:)];
		b.bordered = NO;
		b.font = [NSFont systemFontOfSize:12];
		b.contentTintColor = [NSColor labelColor];
		b.focusRingType = NSFocusRingTypeNone;
		b.tag = (NSInteger)i;
		b.translatesAutoresizingMaskIntoConstraints = NO;
		[_menuBar addSubview:b];
		[b.centerYAnchor constraintEqualToAnchor:_menuBar.centerYAnchor].active = YES;
		[b.heightAnchor constraintEqualToConstant:22].active = YES;
		if (prev) [prev.trailingAnchor constraintEqualToAnchor:b.leadingAnchor constant:-8].active = YES;
		else [_menuBar.leadingAnchor constraintEqualToAnchor:b.leadingAnchor constant:-8].active = YES;
		[_menuBarButtons addObject:b];
		prev = b;
	}
	if (prev) [_menuBar.trailingAnchor constraintGreaterThanOrEqualToAnchor:prev.trailingAnchor constant:8].active = YES;
}

- (void)menuBarClicked:(NSButton *)b {
	if (!self.window.isKeyWindow && ![self runningHeadless]) return;
	if (b.tag < 0 || (NSUInteger)b.tag >= _inWindowMenus.count) return;
	if (_openMenuIndex == b.tag) { [self closeInWindowMenu]; return; }
	[self openInWindowMenuAtIndex:b.tag];
}

- (void)menuBarHovered:(NSButton *)b {
	if (_openMenuIndex < 0) return;
	if (b.tag < 0 || (NSUInteger)b.tag >= _inWindowMenus.count) return;
	if (_openMenuIndex != b.tag) [self openInWindowMenuAtIndex:b.tag];
}

- (void)clearMenuOpenHighlights {
	for (NSButton *b in _menuBarButtons) {
		if ([b isKindOfClass:[NPMenuBarButton class]]) {
			((NPMenuBarButton *)b).menuOpen = NO;
			[(NPMenuBarButton *)b applyChrome];
		}
	}
}

- (void)styleDropPanel:(NSView *)v {
	v.wantsLayer = YES;
	v.layer.cornerRadius = 6;
	v.layer.masksToBounds = NO;
	v.layer.shadowColor = [NSColor colorWithWhite:0 alpha:1].CGColor;
	v.layer.shadowOpacity = 0.32;
	v.layer.shadowRadius = 10;
	v.layer.shadowOffset = NSMakeSize(0, -2);
}

- (void)clearFlyouts {
	for (NSView *v in _dropFlyouts) [v removeFromSuperview];
	[_dropFlyouts removeAllObjects];
	while (_dropPanelItems.count > 1) [_dropPanelItems removeLastObject];
}
- (void)trimFlyoutsAfterPanel:(NSInteger)panelIndex {
	while ((NSInteger)_dropFlyouts.count > panelIndex) {
		NSView *v = _dropFlyouts.lastObject;
		[v removeFromSuperview];
		[_dropFlyouts removeLastObject];
	}
	while ((NSInteger)_dropPanelItems.count > panelIndex + 1)
		[_dropPanelItems removeLastObject];
}
- (NSView *)panelViewAtIndex:(NSInteger)idx {
	if (idx <= 0) return _dropDown;
	if (idx - 1 < (NSInteger)_dropFlyouts.count) return _dropFlyouts[(NSUInteger)(idx - 1)];
	return _dropDown;
}
- (void)sizeRowsInPanel:(NSView *)panel width:(CGFloat)w {
	NSView *host = panel;
	if ([panel isKindOfClass:[NPDropDownView class]])
		host = ((NPDropDownView *)panel).rowHost ?: panel;
	for (NSView *v in host.subviews) {
		NSRect f = v.frame;
		if ([v isKindOfClass:[NPMenuRow class]]) {
			f.origin.x = 0;
			f.size.width = MAX(20, w - 2);
			v.frame = f;
			[v updateTrackingAreas];
		} else if (f.size.height <= 2) {
			f.size.width = MAX(8, w - 16);
			v.frame = f;
		}
	}
}

- (void)closeInWindowMenu {
	_openMenuIndex = -1;
	[self clearFlyouts];
	[_dropPanelItems removeAllObjects];
	_dropDown.hidden = YES;
	_dropDown.frame = NSZeroRect;
	NSView *host = _dropDown.rowHost;
	for (NSView *v in [host.subviews copy]) [v removeFromSuperview];
	[self clearMenuOpenHighlights];
	_menuSelValid = NO;
}

- (CGFloat)inWindowDropDownHeight { return _dropDown.hidden ? 0 : _dropDown.frame.size.height; }
- (NSRect)inWindowDropDownFrame { return _dropDown.frame; }
- (NPDropDownView *)lastDropPanel {
	return _dropFlyouts.count ? _dropFlyouts.lastObject : _dropDown;
}
- (NSRect)inWindowLastPanelFrame { return self.lastDropPanel.frame; }
- (CGFloat)inWindowLastPanelContentHeight { return self.lastDropPanel.contentHeight; }
- (NSInteger)inWindowCheckedRowCount {
	NSInteger n = 0;
	NSView *host = self.lastDropPanel.rowHost;
	for (NSView *v in host.subviews) {
		if ([v isKindOfClass:[NPMenuRow class]] && ((NPMenuRow *)v).checked) n++;
	}
	return n;
}
- (NSInteger)lastPanelIndex {
	return _dropFlyouts.count ? (NSInteger)_dropFlyouts.count : 0;
}
- (NSArray<NSString *> *)inWindowLastPanelRowNames {
	NSMutableArray *a = [NSMutableArray array];
	NSView *host = self.lastDropPanel.rowHost ?: self.lastDropPanel;
	for (NSView *v in host.subviews) {
		if ([v isKindOfClass:[NPMenuRow class]])
			[a addObject:((NPMenuRow *)v).name ?: @""];
	}
	return a;
}
- (NSRect)inWindowRowFrameNamed:(NSString *)name {
	NPMenuRow *r = [self menuRowInPanel:self.lastPanelIndex named:name];
	return r ? r.frame : NSZeroRect;
}
- (BOOL)scrollInWindowLastPanelToName:(NSString *)name {
	NPDropDownView *p = self.lastDropPanel;
	NPMenuRow *r = [self menuRowInPanel:self.lastPanelIndex named:name];
	if (!r || !p.scroller) return NO;
	const CGFloat visH = NSHeight(p.scroller.contentView.bounds);
	CGFloat y = NSMaxY(r.frame) - visH;
	if (y < 0) y = 0;
	[p.scroller.contentView scrollToPoint:NSMakePoint(0, y)];
	[p.scroller reflectScrolledClipView:p.scroller.contentView];
	[p layoutSubtreeIfNeeded];
	return YES;
}
- (BOOL)inWindowDropDownHasScroller {
	return _dropDown.scroller && _dropDown.scroller.superview == _dropDown
		&& _dropDown.scroller.documentView == _dropDown.rowHost;
}

- (NSSize)measureMenu:(NSMenu *)menu {
	NSFont *font = [NSFont systemFontOfSize:13];
	NSDictionary *attrs = @{NSFontAttributeName: font};
	CGFloat maxName = 72, maxSc = 0;
	BOOL anySub = NO;
	CGFloat h = 6;
	for (NSMenuItem *it in menu.itemArray) {
		if (it.isSeparatorItem) { h += 8; continue; }
		NSArray *parts = [(it.title ?: @"") componentsSeparatedByString:@"\t"];
		NSString *name = parts.firstObject ?: @"";
		NSString *sc = parts.count > 1 ? parts[1] : @"";
		maxName = MAX(maxName, [name sizeWithAttributes:attrs].width);
		if (sc.length) maxSc = MAX(maxSc, [sc sizeWithAttributes:attrs].width);
		if (it.submenu) anySub = YES;
		h += 22;
	}
	h += 6;
	CGFloat w = 8 + 18 + 6 + maxName + 16 + (maxSc > 0 ? maxSc + 10 : 0) + (anySub ? 16 : 8);
	if (w < 168) w = 168;
	if (w > 360) w = 360;
	return NSMakeSize(w, h);
}

- (void)placePanel:(NSView *)panel size:(NSSize)sz topLeft:(NSPoint)topLeft {
	NSView *root = self.window.contentView;
	CGFloat minY = 6;
	if (_statusBar && !_statusBar.hidden)
		minY = MAX(minY, NSMaxY(_statusBar.frame) + 2);
	CGFloat maxTop = NSHeight(root.bounds) - 6;
	if (_menuBar && !_menuBar.hidden)
		maxTop = MIN(maxTop, NSMinY(_menuBar.frame));
	CGFloat x = topLeft.x;
	if (x + sz.width > NSWidth(root.bounds) - 6)
		x = MAX(6, NSWidth(root.bounds) - 6 - sz.width);
	if (x < 6) x = 6;
	const CGFloat contentH = sz.height;
	const CGFloat avail = MAX(40, maxTop - minY);
	CGFloat top = topLeft.y;
	if (top > maxTop) top = maxTop;
	if (top - contentH < minY)
		top = MIN(maxTop, minY + contentH);
	CGFloat viewH = contentH;
	if (viewH > avail) viewH = avail;
	CGFloat y = top - viewH;
	if (y < minY) y = minY;
	panel.frame = NSMakeRect(x, y, sz.width, viewH);
	if ([panel isKindOfClass:[NPDropDownView class]])
		[(NPDropDownView *)panel setContentHeight:contentH width:sz.width];
	panel.hidden = NO;
}

- (void)syncMenuItemStates {
	ScintillaView *e = _document.editor;
	const BOOL wrap = [e message:SCI_GETWRAPMODE] != SC_WRAP_NONE;
	const BOOL longLine = [e message:SCI_GETEDGEMODE] != EDGE_NONE;
	const BOOL indent = [e message:SCI_GETINDENTATIONGUIDES] != 0;
	const BOOL ws = [e message:SCI_GETVIEWWS] != 0;
	const BOOL eols = [e message:SCI_GETVIEWEOL] != 0;
	const BOOL brace = _document.braceMatchEnabled;
	const BOOL ln = _document.lineNumbersVisible;
	const BOOL bm = [e message:SCI_GETMARGINWIDTHN wParam:1] > 0;
	const BOOL fold = [e message:SCI_GETMARGINWIDTHN wParam:2] > 0;
	const BOOL ro = [e message:SCI_GETREADONLY] != 0;
	const BOOL useTabs = [e message:SCI_GETUSETABS] != 0;
	const BOOL saveExit = [self persistSettingsEnabled];
	NSString *enc = _document.currentEncoding ?: @"UTF-8";
	const sptr_t eol = [e message:SCI_GETEOLMODE];
	void (^walk)(NSMenu *);
	__block void (^walkRef)(NSMenu *);
	walk = ^(NSMenu *m) {
		for (NSMenuItem *it in m.itemArray) {
			const SEL a = it.action;
			if (a == @selector(viewWordWrap)) it.state = wrap;
			else if (a == @selector(viewPreview)) it.state = _previewOn;
			else if (a == @selector(viewLongLineMarker)) it.state = longLine;
			else if (a == @selector(viewIndentGuides)) it.state = indent;
			else if (a == @selector(viewWhitespace)) it.state = ws;
			else if (a == @selector(viewEOLs)) it.state = eols;
			else if (a == @selector(viewBraceMatch)) it.state = brace;
			else if (a == @selector(viewLineNumbers)) it.state = ln;
			else if (a == @selector(viewBookmarkMargin)) it.state = bm;
			else if (a == @selector(viewCodeFolding)) it.state = fold;
			else if (a == @selector(toggleReadOnly)) it.state = ro;
			else if (a == @selector(settingsUseTabs)) it.state = !useTabs;
			else if (a == @selector(settingsSaveOnExit)) it.state = saveExit;
			else if (a == @selector(toggleMenuBar)) it.state = !_menuBar.hidden;
			else if (a == @selector(toggleToolbar)) it.state = !_toolBar.hidden;
			else if (a == @selector(toggleStatusBar)) it.state = !_statusBar.hidden;
			else if (a == @selector(setEOLCRLF)) it.state = (eol == SC_EOL_CRLF);
			else if (a == @selector(setEOLLF)) it.state = (eol == SC_EOL_LF);
			else if (a == @selector(setEOLCR)) it.state = (eol == SC_EOL_CR);
			else if (a == @selector(viewDetectURLs)) it.state = _document.URLDetectEnabled;
			else if (a == @selector(toggleLargeFileMode)) it.state = _document.largeFileMode;
			else if (a == @selector(setEncodingUTF8)) it.state = [enc isEqualToString:@"UTF-8"];
			else if (a == @selector(setEncodingUTF8BOM)) it.state = [enc isEqualToString:@"UTF-8 BOM"];
			else if (a == @selector(setEncodingUTF16LE)) it.state = [enc hasPrefix:@"UTF-16LE"];
			else if (a == @selector(setEncodingUTF16BE)) it.state = [enc hasPrefix:@"UTF-16BE"];
			else if (a == @selector(setEncodingGBK)) it.state = [enc hasPrefix:@"GB"];
			else if (a == @selector(setEncodingBIG5)) it.state = [enc isEqualToString:@"BIG5"];
			else if (a == @selector(setEncodingShiftJIS)) it.state = [enc isEqualToString:@"Shift-JIS"];
			else if (a == @selector(setEncodingANSI)) it.state = [enc isEqualToString:@"Latin-1"];
			if (it.submenu) walkRef(it.submenu);
		}
	};
	walkRef = walk;
	for (NSMenu *m in _inWindowMenus) walk(m);
	if (_wordWrapItem) _wordWrapItem.state = wrap ? NSControlStateValueOn : NSControlStateValueOff;
	if (_lineNumbersItem) _lineNumbersItem.state = ln ? NSControlStateValueOn : NSControlStateValueOff;
}

- (void)fillPanel:(NPDropDownView *)panel menu:(NSMenu *)menu panelIndex:(NSInteger)panelIndex {
	NSView *host = panel.rowHost ?: panel;
	for (NSView *v in [host.subviews copy]) [v removeFromSuperview];
	[self syncMenuItemStates];
	if (menu.delegate && [menu.delegate respondsToSelector:@selector(menuNeedsUpdate:)])
		[menu.delegate menuNeedsUpdate:menu];
	NSMutableArray<NSMenuItem *> *items = [NSMutableArray array];
	CGFloat y = 4;
	for (NSMenuItem *it in menu.itemArray) {
		if (it.isSeparatorItem) {
			NSView *sep = [[NSView alloc] initWithFrame:NSMakeRect(8, y + 3, 100, 1)];
			sep.wantsLayer = YES;
			sep.layer.backgroundColor = [NSColor separatorColor].CGColor;
			[host addSubview:sep];
			y += 8;
			continue;
		}
		if ([self respondsToSelector:@selector(validateMenuItem:)])
			it.enabled = [self validateMenuItem:it];
		NSArray *parts = [(it.title ?: @"") componentsSeparatedByString:@"\t"];
		NPMenuRow *row = [[NPMenuRow alloc] initWithFrame:NSMakeRect(1, y, 340, 22)];
		row.name = parts.firstObject ?: @"";
		row.shortcut = parts.count > 1 ? parts[1] : @"";
		row.checked = (it.state == NSControlStateValueOn);
		row.hasSub = (it.submenu != nil);
		row.rowEnabled = it.enabled;
		row.panelIndex = panelIndex;
		row.itemIndex = (NSInteger)items.count;
		row.rowTarget = self;
		row.rowAction = @selector(dropRowClicked:);
		row.hoverAction = @selector(dropRowHovered:);
		[host addSubview:row];
		[items addObject:it];
		y += 22;
	}
	while ((NSInteger)_dropPanelItems.count <= panelIndex)
		[_dropPanelItems addObject:[NSMutableArray array]];
	_dropPanelItems[panelIndex] = items;
}

- (void)openInWindowMenuAtIndex:(NSInteger)index {
	if (index < 0 || (NSUInteger)index >= _inWindowMenus.count) return;
	if (_dropDown.scroller.superview != _dropDown) {
		[_dropDown addSubview:_dropDown.scroller];
		_dropDown.scroller.documentView = _dropDown.rowHost;
	}
	const BOOL fresh = (_openMenuIndex < 0);
	_openMenuIndex = index;
	if (fresh) [self snapshotMenuSelection];
	[self clearFlyouts];
	[_dropPanelItems removeAllObjects];
	[self clearMenuOpenHighlights];
	NSButton *btn = nil;
	if (index < (NSInteger)_menuBarButtons.count) {
		btn = _menuBarButtons[index];
		if ([btn isKindOfClass:[NPMenuBarButton class]]) {
			((NPMenuBarButton *)btn).menuOpen = YES;
			[(NPMenuBarButton *)btn applyChrome];
		}
	}
	NSMenu *menu = _inWindowMenus[index];
	[self fillPanel:_dropDown menu:menu panelIndex:0];
	NSSize sz = [self measureMenu:menu];
	NSView *root = self.window.contentView;
	[root layoutSubtreeIfNeeded];
	NSPoint topLeft = NSMakePoint(8, NSMinY(_menuBar.frame));
	if (btn) {
		NSRect br = [btn convertRect:btn.bounds toView:root];
		topLeft.x = NSMinX(br);
		topLeft.y = NSMinY(_menuBar.frame);
	}
	[self placePanel:_dropDown size:sz topLeft:topLeft];
	[self sizeRowsInPanel:_dropDown width:sz.width];
	[root addSubview:_dropDown positioned:NSWindowAbove relativeTo:_statusBar];
}

- (NSMenuItem *)itemFromRow:(NPMenuRow *)row {
	if (row.panelIndex < 0 || (NSUInteger)row.panelIndex >= _dropPanelItems.count) return nil;
	NSArray<NSMenuItem *> *items = _dropPanelItems[row.panelIndex];
	if (row.itemIndex < 0 || (NSUInteger)row.itemIndex >= items.count) return nil;
	return items[row.itemIndex];
}

- (void)openFlyout:(NSMenu *)menu fromRow:(NPMenuRow *)row {
	if (!menu) return;
	[self trimFlyoutsAfterPanel:row.panelIndex];
	NPDropDownView *fly = [[NPDropDownView alloc] initWithFrame:NSZeroRect];
	[self styleDropPanel:fly];
	NSView *root = self.window.contentView;
	[root addSubview:fly positioned:NSWindowAbove relativeTo:_statusBar];
	const NSInteger next = row.panelIndex + 1;
	[self fillPanel:fly menu:menu panelIndex:next];
	NSSize sz = [self measureMenu:menu];
	NSView *parent = [self panelViewAtIndex:row.panelIndex];
	NSRect rowR = [row convertRect:row.bounds toView:root];
	NSPoint topLeft = NSMakePoint(NSMaxX(parent.frame) - 2, NSMaxY(rowR));
	if (topLeft.x + sz.width > NSWidth(root.bounds) - 6)
		topLeft.x = NSMinX(parent.frame) + 2 - sz.width;
	[self placePanel:fly size:sz topLeft:topLeft];
	[self sizeRowsInPanel:fly width:sz.width];
	[_dropFlyouts addObject:fly];
}

- (void)dropRowHovered:(NPMenuRow *)row {
	NSMenuItem *it = [self itemFromRow:row];
	if (!it) return;
	if (it.submenu) [self openFlyout:it.submenu fromRow:row];
	else [self trimFlyoutsAfterPanel:row.panelIndex];
}

- (void)dropRowClicked:(NPMenuRow *)row {
	NSMenuItem *it = [self itemFromRow:row];
	if (!it) return;
	if (it.submenu) {
		[self openFlyout:it.submenu fromRow:row];
		return;
	}
	SEL act = it.action;
	id target = it.target;
	[self restoreMenuSelectionIfNeeded];
	[self closeInWindowMenu];
	if (!act) return;
	if (!target) target = [NSApp targetForAction:act to:nil from:it];
	if (!target && [self respondsToSelector:act]) target = self;
	if (target) [NSApp sendAction:act to:target from:it];
}

- (void)installDropClickMonitor {
	if (_dropClickMonitor) return;
	__weak MainWindowController *weakSelf = self;
	_dropClickMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskLeftMouseDown
		handler:^NSEvent *(NSEvent *event) {
			MainWindowController *self_ = weakSelf;
			if (!self_ || self_->_dropDown.hidden) return event;
			NSView *root = self_.window.contentView;
			NSPoint pt = [root convertPoint:event.locationInWindow fromView:nil];
			if (NSPointInRect(pt, self_->_dropDown.frame) || NSPointInRect(pt, self_->_menuBar.frame))
				return event;
			for (NSView *f in self_->_dropFlyouts) {
				if (NSPointInRect(pt, f.frame)) return event;
			}
			[self_ closeInWindowMenu];
			return event;
		}];
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

- (BOOL)findFieldIsEditing {
	NSResponder *fr = self.window.firstResponder;
	if ([fr isKindOfClass:[NSTextView class]] && [(NSTextView *)fr isFieldEditor]) return YES;
	if ([fr isKindOfClass:[NSControl class]] &&
		([fr isKindOfClass:[NSTextField class]] || [fr isKindOfClass:[NSSearchField class]])) return YES;
	return NO;
}
- (void)undo:(id)sender { [self editUndo]; }
- (void)redo:(id)sender { [self editRedo]; }
- (void)cut:(id)sender { [self editCut]; }
- (void)copy:(id)sender { [self editCopy]; }
- (void)paste:(id)sender { [self editPaste]; }
- (void)delete:(id)sender { [self editDelete]; }
- (void)selectAll:(id)sender { [self editSelectAll]; }
- (BOOL)handleKeyEquivalent:(NSEvent *)event {
	if (event.keyCode == 53 && !_dropDown.hidden) {
		[self closeInWindowMenu];
		return YES;
	}
	const NSEventModifierFlags mods = event.modifierFlags
		& (NSEventModifierFlagCommand | NSEventModifierFlagOption
		   | NSEventModifierFlagControl | NSEventModifierFlagShift);
	const unichar ch = event.charactersIgnoringModifiers.length
		? [event.charactersIgnoringModifiers characterAtIndex:0] : 0;
	const BOOL isFn = (ch >= NSF1FunctionKey && ch <= NSF35FunctionKey)
		|| ch == NSUpArrowFunctionKey || ch == NSDownArrowFunctionKey;
	if (!(mods & (NSEventModifierFlagCommand | NSEventModifierFlagControl | NSEventModifierFlagOption)) && !isFn)
		return NO;
	if ((mods == NSEventModifierFlagCommand) && (ch == 'q' || ch == 'Q'))
		return NO;
	id editTarget = [self findFieldIsEditing] ? self.window.firstResponder : self;
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
	void (^walk)(NSMenu *, NSInteger);
	__block void (^walkRef)(NSMenu *, NSInteger);
	walk = ^(NSMenu *m, NSInteger depth) {
		for (NSMenuItem *it in m.itemArray) {
			if (it.isSeparatorItem) continue;
			[out appendFormat:@"%*s%@\n", (int)depth * 2, "", it.title];
			if (it.submenu) walkRef(it.submenu, depth + 1);
		}
	};
	walkRef = walk;
	for (NSMenu *m in _inWindowMenus) {
		[out appendFormat:@"%@\n", m.title];
		walk(m, 1);
	}
}
- (NSArray *)menuLeafCatalog {
	NSMutableArray *out = [NSMutableArray array];
	void (^walk)(NSMenu *, NSString *);
	__block void (^walkRef)(NSMenu *, NSString *);
	walk = ^(NSMenu *m, NSString *path) {
		for (NSMenuItem *it in m.itemArray) {
			if (it.isSeparatorItem) continue;
			NSString *name = [[it.title componentsSeparatedByString:@"\t"] firstObject] ?: @"";
			NSString *p = path.length ? [NSString stringWithFormat:@"%@/%@", path, name] : name;
			if (it.submenu) walkRef(it.submenu, p);
			else if (it.action)
				[out addObject:@{@"path": p, @"action": NSStringFromSelector(it.action)}];
		}
	};
	walkRef = walk;
	for (NSMenu *m in _inWindowMenus) walk(m, m.title);
	return out;
}
- (NSInteger)inWindowFlyoutCount { return (NSInteger)_dropFlyouts.count; }
- (void)snapshotMenuSelection {
	ScintillaView *e = _document.editor;
	_menuSelStart = [e message:SCI_GETSELECTIONSTART];
	_menuSelEnd = [e message:SCI_GETSELECTIONEND];
	_menuSelValid = YES;
}
- (void)restoreMenuSelectionIfNeeded {
	if (!_menuSelValid) return;
	ScintillaView *e = _document.editor;
	[e message:SCI_SETSEL wParam:_menuSelStart lParam:_menuSelEnd];
}
- (NPMenuRow *)menuRowInPanel:(NSInteger)panel named:(NSString *)name {
	NSView *p = [self panelViewAtIndex:panel];
	if ([p isKindOfClass:[NPDropDownView class]])
		p = ((NPDropDownView *)p).rowHost ?: p;
	for (NSView *v in p.subviews) {
		if (![v isKindOfClass:[NPMenuRow class]]) continue;
		NSString *n = ((NPMenuRow *)v).name ?: @"";
		if ([n isEqualToString:name] || [n isEqualToString:NPL(name)]) return (NPMenuRow *)v;
	}
	return nil;
}
- (BOOL)clickInWindowMenuPath:(NSArray<NSString *> *)names {
	if (names.count < 1) return NO;
	NSInteger top = -1;
	for (NSUInteger i = 0; i < _inWindowMenus.count; i++) {
		NSString *title = _inWindowMenus[i].title;
		if ([title isEqualToString:names[0]] || [title isEqualToString:NPL(names[0])])
			{ top = (NSInteger)i; break; }
	}
	if (top < 0) return NO;
	[self openInWindowMenuAtIndex:top];
	for (NSUInteger i = 1; i < names.count; i++) {
		NPMenuRow *row = [self menuRowInPanel:(NSInteger)i - 1 named:names[i]];
		if (!row) { [self closeInWindowMenu]; return NO; }
		[self dropRowClicked:row];
	}
	return YES;
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
	[_statusBar setPreviewActive:_previewOn];
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
	[t appendString:@" - Notepad Mac"];
	self.window.title = t;
}

- (void)docDirtyChanged:(NSNotification *)n {
	[self updateWindowTitle];
	[self refreshStatus];
	[self rebuildTabBar];
}
- (void)docCaretChanged:(NSNotification *)n { [self refreshStatus]; [self schedulePreviewRefresh]; }
- (void)docScrolled:(NSNotification *)n {
	(void)n;
	if (_previewSyncing || _previewOn == NO) return;
	if ([self previewScrollLinked] == NO) return;
	[self syncPreviewToEditor];
}

#pragma mark - File

- (void)confirmIfDirtyThen:(void (^)(void))proceed {
	if (!proceed) return;
	if (!_document.dirty) { proceed(); return; }
	if ([self runningHeadless]) { proceed(); return; }
	NSAlert *a = [[NSAlert alloc] init];
	a.messageText = NPL(@"Save changes?");
	a.informativeText = NPL(@"The document has unsaved changes.");
	[a addButtonWithTitle:NPL(@"Save")];
	[a addButtonWithTitle:NPL(@"Don't Save")];
	[a addButtonWithTitle:NPL(@"Cancel")];
	[a beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse r) {
		if (r == NSAlertFirstButtonReturn)
			[self fileSaveThen:^(BOOL ok) { if (ok) proceed(); }];
		else if (r == NSAlertSecondButtonReturn)
			proceed();
	}];
}

- (void)fileSaveThen:(void (^)(BOOL ok))done {
	if (_document.fileURL) {
		NSError *err = nil;
		const BOOL ok = [_document saveToURL:_document.fileURL error:&err];
		if (ok) [self noteRecentFile:_document.fileURL];
		[self updateWindowTitle];
		if (done) done(ok);
		return;
	}
	if ([self runningHeadless]) { if (done) done(NO); return; }
	NSSavePanel *panel = [NSSavePanel savePanel];
	panel.nameFieldStringValue = _document.tabTitle ?: @"Untitled.txt";
	[panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse r) {
		if (r != NSModalResponseOK) { if (done) done(NO); return; }
		NSError *err = nil;
		const BOOL ok = [self.editorDocument saveToURL:panel.URL error:&err];
		if (ok) {
			[self.editorDocument applyLexerForExtension:panel.URL.pathExtension.lowercaseString];
			[self noteRecentFile:panel.URL];
			[self updateWindowTitle];
			[self refreshStatus];
		}
		if (done) done(ok);
	}];
}

- (void)fileNew {
	_untitledSeq += 1;
	EditorDocument *doc = [[EditorDocument alloc] initWithNewUntitled:_untitledSeq];
	[self addAndActivateDocument:doc];
}
- (void)fileNewWindow {
	MainWindowController *wc = [[MainWindowController alloc] init];
	[wc presentWindow];
}
- (void)fileOpen {
	if ([self runningHeadless]) return;
	NSOpenPanel *panel = [NSOpenPanel openPanel];
	[panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse r) {
		if (r != NSModalResponseOK) return;
		[self openURLInTab:panel.URL];
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
	[[NSNotificationCenter defaultCenter] removeObserver:self name:@"EditorDocumentCaretChanged" object:nil];
	[[NSNotificationCenter defaultCenter] removeObserver:self name:@"EditorDocumentScrolled" object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(docDirtyChanged:) name:@"EditorDocumentDirtyChanged" object:_document];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(docCaretChanged:) name:@"EditorDocumentCaretChanged" object:_document];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(docScrolled:) name:@"EditorDocumentScrolled" object:_document];
	[_document applyPersistedEditorSettings];
	[self updateWindowTitle];
	[self refreshStatus];
	[self.window makeFirstResponder:[_document.editor content]];
	[self schedulePreviewRefresh];
}
- (BOOL)fileSave {
	if (!_document.fileURL) { [self fileSaveThen:nil]; return NO; }
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
- (NSString *)documentPropertiesText {
	ScintillaView *e = _document.editor;
	const sptr_t bytes = [e message:SCI_GETLENGTH];
	const sptr_t lines = [e message:SCI_GETLINECOUNT];
	const sptr_t eol = [e message:SCI_GETEOLMODE];
	NSString *eolName = (eol == SC_EOL_CRLF) ? @"CR+LF" : ((eol == SC_EOL_CR) ? @"CR" : @"LF");
	NSString *path = _document.fileURL.path ?: NPL(@"Untitled");
	NSString *name = _document.fileURL.lastPathComponent ?: _document.tabTitle ?: NPL(@"Untitled");
	unsigned long long disk = 0;
	if (_document.fileURL) {
		NSDictionary *attr = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil];
		disk = [attr[NSFileSize] unsignedLongLongValue];
	}
	return [NSString stringWithFormat:
		@"%@: %@\n%@: %@\n%@: %lld\n%@: %ld\n%@: %ld\n%@: %@\n%@: %@\n%@: %@\n%@: %@\n%@: %@\n%@: %@ %ld\n%@: %ld%%",
		NPL(@"Path"), path,
		NPL(@"File Name"), name,
		NPL(@"Size"), (long long)(disk ? disk : bytes),
		NPL(@"Lines"), (long)lines,
		NPL(@"Characters"), (long)bytes,
		NPL(@"Encoding"), _document.currentEncoding ?: @"UTF-8",
		NPL(@"Line Endings"), eolName,
		NPL(@"Syntax"), _document.currentLexerName.length ? _document.currentLexerName : NPL(@"Text File"),
		NPL(@"Modified"), _document.dirty ? NPL(@"Yes") : NPL(@"No"),
		NPL(@"Read Only"), [e message:SCI_GETREADONLY] ? NPL(@"Yes") : NPL(@"No"),
		NPL(@"Tabs"), [e message:SCI_GETUSETABS] ? NPL(@"Use Tabs") : NPL(@"Insert Tabs as Spaces"),
		(long)[e message:SCI_GETTABWIDTH],
		NPL(@"Zoom"), (long)[e message:SCI_GETZOOM]];
}

- (void)fileProperties {
	NSString *info = [self documentPropertiesText];
	if ([self runningHeadless]) {
		NSLog(@"[props] %@", info);
		return;
	}
	NSAlert *a = [[NSAlert alloc] init];
	a.messageText = NPL(@"Properties");
	a.informativeText = info;
	[a addButtonWithTitle:NPL(@"OK")];
	[a beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse r) {}];
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
- (void)setEncodingUTF8BOM { [_document setSaveEncoding:@"UTF-8 BOM"]; [self refreshStatus]; }
- (void)setEncodingUTF16LE { [_document setSaveEncoding:@"UTF-16LE"]; [self refreshStatus]; }
- (void)setEncodingUTF16BE { [_document setSaveEncoding:@"UTF-16BE"]; [self refreshStatus]; }
- (void)setEOLCRLF {
	[_document.editor message:SCI_SETEOLMODE wParam:SC_EOL_CRLF lParam:0];
	[_document.editor message:SCI_CONVERTEOLS wParam:SC_EOL_CRLF lParam:0];
	[self refreshStatus];
}
- (void)setEOLLF {
	[_document.editor message:SCI_SETEOLMODE wParam:SC_EOL_LF lParam:0];
	[_document.editor message:SCI_CONVERTEOLS wParam:SC_EOL_LF lParam:0];
	[self refreshStatus];
}

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
- (void)editIndent { [_document.editor message:SCI_LINEINDENT wParam:0 lParam:0]; }
- (void)editUnindent { [_document.editor message:SCI_LINEDEDENT wParam:0 lParam:0]; }
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
	sptr_t a = [e message:SCI_GETSELECTIONSTART];
	sptr_t b = [e message:SCI_GETSELECTIONEND];
	if (a == b) {
		const sptr_t line = [e message:SCI_LINEFROMPOSITION wParam:a];
		if (line + 1 >= [e message:SCI_GETLINECOUNT]) return;
		a = [e message:SCI_POSITIONFROMLINE wParam:line];
		b = [e message:SCI_GETLINEENDPOSITION wParam:line + 1];
	} else {
		const sptr_t first = [e message:SCI_LINEFROMPOSITION wParam:a];
		sptr_t last = [e message:SCI_LINEFROMPOSITION wParam:b];
		a = [e message:SCI_POSITIONFROMLINE wParam:first];
		if (last + 1 < [e message:SCI_GETLINECOUNT])
			b = [e message:SCI_POSITIONFROMLINE wParam:last + 1];
		else
			b = [e message:SCI_GETLENGTH];
	}
	[e message:SCI_SETTARGETSTART wParam:a lParam:0];
	[e message:SCI_SETTARGETEND wParam:b lParam:0];
	[e message:SCI_LINESJOIN wParam:0 lParam:0];
}
- (void)editSplitLines {
	ScintillaView *e = _document.editor;
	sptr_t a = [e message:SCI_GETSELECTIONSTART];
	sptr_t b = [e message:SCI_GETSELECTIONEND];
	if (a == b) {
		const sptr_t line = [e message:SCI_LINEFROMPOSITION wParam:a];
		a = [e message:SCI_POSITIONFROMLINE wParam:line];
		b = [e message:SCI_GETLINEENDPOSITION wParam:line];
	}
	[e message:SCI_SETTARGETSTART wParam:a lParam:0];
	[e message:SCI_SETTARGETEND wParam:b lParam:0];
	[e message:SCI_LINESSPLIT wParam:0 lParam:0];
}
- (void)editUpper {
	ScintillaView *e = _document.editor;
	if ([e message:SCI_GETSELECTIONSTART] == [e message:SCI_GETSELECTIONEND]) [self searchSelectWord];
	[e message:SCI_UPPERCASE wParam:0 lParam:0];
}
- (void)editLower {
	ScintillaView *e = _document.editor;
	if ([e message:SCI_GETSELECTIONSTART] == [e message:SCI_GETSELECTIONEND]) [self searchSelectWord];
	[e message:SCI_LOWERCASE wParam:0 lParam:0];
}
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
	a.messageText = NPL(@"Goto Line");
	NSTextField *input = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 200, 24)];
	a.accessoryView = input;
	[a addButtonWithTitle:NPL(@"Goto")];
	[a addButtonWithTitle:NPL(@"Cancel")];
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
	[self persistSettings];
}
- (void)schedulePreviewRefresh {
	if (!_previewOn || _previewIgnore) return;
	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(refreshPreviewNow) object:nil];
	[self performSelector:@selector(refreshPreviewNow) withObject:nil afterDelay:0.12];
}
- (void)refreshPreviewNow {
	if (!_previewOn || !_previewPane) return;
	[_previewPane refreshDocument:_document dark:(_document.theme == NPThemeDark)];
}
- (CGFloat)clampedPreviewFrac:(CGFloat)f {
	if (f < 0.18) return 0.18;
	if (f > 0.82) return 0.82;
	return f;
}
- (CGFloat)previewUsableWidth {
	const CGFloat w = NSWidth(_workSplit.bounds);
	const CGFloat d = _workSplit.dividerThickness;
	if (w <= d + 40) return 1;
	return w - d;
}
- (CGFloat)previewSplitFraction {
	if (_previewSplitFrac <= 0) {
		NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
		CGFloat f = [d objectForKey:@"NP4PreviewSplit"] ? [d doubleForKey:@"NP4PreviewSplit"] : 0.55;
		_previewSplitFrac = [self clampedPreviewFrac:f];
	}
	return _previewSplitFrac;
}
- (void)rememberPreviewSplit {
	if (_previewApplying) return;
	if (_previewOn == NO || _workSplit.subviews.count < 2) return;
	const CGFloat usable = [self previewUsableWidth];
	if (usable < 80) return;
	// 只有真正的用户拖动才记比例；窗口缩放/程序化布局触发的 resize 不记
	if (_lastPreviewUsable > 0 && fabs(_lastPreviewUsable - usable) > 0.5) return;
	_previewSplitFrac = [self clampedPreviewFrac:NSWidth(_workSplit.subviews[0].frame) / usable];
	[[NSUserDefaults standardUserDefaults] setDouble:_previewSplitFrac forKey:@"NP4PreviewSplit"];
}
- (void)applyPreviewSplitPosition {
	if (_workSplit.subviews.count < 2) return;
	const BOOL prev = _previewApplying;
	_previewApplying = YES;
	[_workSplit.superview layoutSubtreeIfNeeded];
	[_workSplit layoutSubtreeIfNeeded];
	const CGFloat usable = [self previewUsableWidth];
	if (usable <= 120) { _previewApplying = prev; return; }
	[_workSplit setHoldingPriority:1 forSubviewAtIndex:0];
	[_workSplit setHoldingPriority:1 forSubviewAtIndex:1];
	[_workSplit setPosition:usable * [self previewSplitFraction] ofDividerAtIndex:0];
	[_workSplit layoutSubtreeIfNeeded];
	_lastPreviewUsable = usable;
	_previewApplying = prev;
}
- (void)setPreviewOn:(BOOL)on {
	if (_previewOn == on) {
		if (on) [self refreshPreviewNow];
		[_statusBar setPreviewActive:_previewOn];
		return;
	}
	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(applyPreviewSplitPosition) object:nil];
	if (on == NO && _previewOn) [self rememberPreviewSplit];
	_previewOn = on;
	if (on) {
		_previewApplying = YES;
		if (_previewPane.superview != _workSplit) [_workSplit addSubview:_previewPane];
		[self applyPreviewSplitPosition];
		[self applyPreviewSplitPosition];
		_previewApplying = NO;
		[self refreshPreviewNow];
		[self syncPreviewToEditor];
		[self performSelector:@selector(applyPreviewSplitPosition) withObject:nil afterDelay:0];
	} else {
		_previewApplying = YES;
		[_previewPane removeFromSuperview];
		[_workSplit adjustSubviews];
		_previewApplying = NO;
	}
	[_statusBar setPreviewActive:_previewOn];
	[self persistSettings];
}
- (CGFloat)previewDividerThickness { return _workSplit.dividerThickness; }
- (CGFloat)previewSplitPosition {
	if (_workSplit.subviews.count < 2) return 0;
	return NSWidth(_workSplit.subviews[0].frame);
}
- (CGFloat)previewPaneWidth {
	if (_workSplit.subviews.count < 2) return 0;
	return NSWidth(_workSplit.subviews[1].frame);
}
- (BOOL)setPreviewSplitPosition:(CGFloat)pos {
	if (_workSplit.subviews.count < 2) return NO;
	[_workSplit setPosition:pos ofDividerAtIndex:0];
	[_workSplit layoutSubtreeIfNeeded];
	[self rememberPreviewSplit];
	return YES;
}
- (NSButton *)previewStatusButton { return _statusBar.previewButton; }
- (CGFloat)splitView:(NSSplitView *)splitView constrainMinCoordinate:(CGFloat)proposedMin ofSubviewAt:(NSInteger)dividerIndex {
	(void)proposedMin; (void)dividerIndex;
	return 160;
}
- (CGFloat)splitView:(NSSplitView *)splitView constrainMaxCoordinate:(CGFloat)proposedMax ofSubviewAt:(NSInteger)dividerIndex {
	(void)proposedMax; (void)dividerIndex;
	return NSWidth(splitView.bounds) - 160 - splitView.dividerThickness;
}
- (void)splitViewDidResizeSubviews:(NSNotification *)n {
	(void)n;
	if (_previewApplying) return;   // 程序化布局期间不再触发，防递归
	if (_previewOn == NO || _workSplit.subviews.count < 2) return;
	const CGFloat usable = [self previewUsableWidth];
	// 窗口宽度变了：按记忆比例重新分配，不记新比例
	if (_lastPreviewUsable > 0 && fabs(_lastPreviewUsable - usable) > 0.5) {
		[self applyPreviewSplitPosition];
		return;
	}
	[self rememberPreviewSplit];
}
- (BOOL)splitView:(NSSplitView *)splitView canCollapseSubview:(NSView *)subview {
	(void)splitView; (void)subview;
	return NO;
}
- (void)viewPreview { [self setPreviewOn:!_previewOn]; }
- (BOOL)previewOn { return _previewOn; }
- (NSString *)previewHTML { return [PreviewPane htmlForDocument:_document] ?: @""; }
- (NSString *)previewLastPageHTML { return [_previewPane lastPageHTML] ?: @""; }
- (BOOL)previewLastRefreshInPlace { return [_previewPane lastRefreshInPlace]; }
- (BOOL)previewLastRefreshDidScroll { return [_previewPane lastRefreshDidScroll]; }
- (BOOL)previewUsesLineMap { return [_previewPane previewUsesLineMap]; }
- (BOOL)previewScrollLinked {
	return [PreviewPane kindForDocument:_document] == NPPreviewMarkdown;
}
- (NSInteger)previewLastSyncLine { return [_previewPane lastSyncLine]; }
- (CGFloat)previewLastSyncFrac { return [_previewPane lastSyncFrac]; }
- (NSInteger)editorFirstVisibleLine {
	return (NSInteger)[_document.editor message:SCI_GETFIRSTVISIBLELINE];
}
- (BOOL)setEditorFirstVisibleLine:(NSInteger)line {
	ScintillaView *e = _document.editor;
	const sptr_t n = [e message:SCI_GETLINECOUNT];
	if (line < 0) line = 0;
	if (n > 0 && line >= (NSInteger)n) line = (NSInteger)n - 1;
	[e message:SCI_SETFIRSTVISIBLELINE wParam:(sptr_t)line lParam:0];
	return [e message:SCI_GETFIRSTVISIBLELINE] == (sptr_t)line;
}
- (void)endPreviewSync { _previewSyncing = NO; }
- (void)syncPreviewToEditor {
	if (_previewOn == NO || _previewPane == nil) return;
	if ([self previewScrollLinked] == NO) return;
	ScintillaView *e = _document.editor;
	const NSInteger first = (NSInteger)[e message:SCI_GETFIRSTVISIBLELINE];
	const NSInteger n = (NSInteger)[e message:SCI_GETLINECOUNT];
	_previewSyncing = YES;
	[_previewPane scrollPreviewToSourceLine:first lineCount:n];
	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(endPreviewSync) object:nil];
	[self performSelector:@selector(endPreviewSync) withObject:nil afterDelay:0.08];
}
- (void)applyPreviewScrollLine:(NSInteger)line fraction:(CGFloat)frac {
	if (_previewOn == NO || _document == nil) return;
	if ([self previewScrollLinked] == NO) return;
	ScintillaView *e = _document.editor;
	const sptr_t n = [e message:SCI_GETLINECOUNT];
	const sptr_t vis = [e message:SCI_LINESONSCREEN];
	sptr_t dest = 0;
	if (line > 0) {
		dest = (sptr_t)line - 1;
	} else {
		const sptr_t span = (n > vis) ? (n - vis) : 0;
		if (frac < 0) frac = 0;
		if (frac > 1) frac = 1;
		dest = (sptr_t)((frac * (CGFloat)span) + 0.5);
	}
	if (dest < 0) dest = 0;
	if (n > 0 && dest >= n) dest = n - 1;
	_lastAppliedEditorLineFromPreview = (NSInteger)dest;
	const sptr_t cur = [e message:SCI_GETFIRSTVISIBLELINE];
	if (dest == cur) return;
	_previewSyncing = YES;
	[e message:SCI_SETFIRSTVISIBLELINE wParam:dest lParam:0];
	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(endPreviewSync) object:nil];
	[self performSelector:@selector(endPreviewSync) withObject:nil afterDelay:0.08];
}
- (NSInteger)lastAppliedEditorLineFromPreview { return _lastAppliedEditorLineFromPreview; }
- (void)applyPreviewHTMLEdit:(NSString *)html {
	if (html.length == 0 || !_document) return;
	_previewIgnore = YES;
	[_document.editor setString:html];
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)),
		dispatch_get_main_queue(), ^{ self->_previewIgnore = NO; });
}
- (void)viewIndentGuides {
	ScintillaView *e = _document.editor;
	const sptr_t cur = [e message:SCI_GETINDENTATIONGUIDES];
	[e message:SCI_SETINDENTATIONGUIDES wParam:(cur ? SC_IV_NONE : SC_IV_LOOKBOTH) lParam:0];
	[self persistSettings];
}
- (void)viewWhitespace {
	ScintillaView *e = _document.editor;
	const sptr_t cur = [e message:SCI_GETVIEWWS];
	[e message:SCI_SETVIEWWS wParam:(cur ? SCWS_INVISIBLE : SCWS_VISIBLEALWAYS) lParam:0];
	[self persistSettings];
}
- (void)viewEOLs {
	ScintillaView *e = _document.editor;
	const sptr_t cur = [e message:SCI_GETVIEWEOL];
	[e message:SCI_SETVIEWEOL wParam:!cur lParam:0];
	[self persistSettings];
}
- (void)viewLineNumbers {
	const BOOL on = !_document.lineNumbersVisible;
	[_document setLineNumbersVisible:on];
	_lineNumbersItem.state = on ? NSControlStateValueOn : NSControlStateValueOff;
	[self persistSettings];
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
	[self persistSettings];
}
- (void)viewZoomIn { [_document.editor message:SCI_ZOOMIN wParam:0 lParam:0]; [_document updateLineNumberWidth]; [self refreshStatus]; [self persistSettings]; }
- (void)viewZoomOut { [_document.editor message:SCI_ZOOMOUT wParam:0 lParam:0]; [_document updateLineNumberWidth]; [self refreshStatus]; [self persistSettings]; }
- (void)viewZoomReset { [_document.editor message:SCI_SETZOOM wParam:100 lParam:0]; [_document updateLineNumberWidth]; [self refreshStatus]; [self persistSettings]; }
- (void)toggleFullScreen { [self.window toggleFullScreen:nil]; }
- (void)toggleStatusBar {
	_statusBar.hidden = !_statusBar.hidden;
	_statusBarHeight.constant = _statusBar.hidden ? 0 : 22;
	[self persistSettings];
}

#pragma mark - Scheme

- (void)schemeChoose {
	NSAlert *a = [[NSAlert alloc] init];
	a.messageText = NPL(@"Syntax Scheme...");
	NSPopUpButton *pop = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(0, 0, 300, 26) pullsDown:NO];
	for (NSDictionary *info in [LexerRegistry allLexersInfo]) {
		NSMenuItem *it = [[NSMenuItem alloc] initWithTitle:info[@"name"] ?: @"" action:nil keyEquivalent:@""];
		it.representedObject = info;
		[pop.menu addItem:it];
	}
	a.accessoryView = pop;
	[a addButtonWithTitle:NPL(@"OK")];
	[a addButtonWithTitle:NPL(@"Cancel")];
	[a beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse r) {
		if (r != NSAlertFirstButtonReturn) return;
		[self schemeChanged:pop];
	}];
}
- (void)schemeReset {
	NSString *name = _document.currentLexerName;
	if (name.length) [LexerRegistry clearUserOverridesForLexerName:name];
	if (_document.fileURL)
		[_document applyLexerForExtension:_document.fileURL.pathExtension.lowercaseString];
	else if (_document.currentLexer)
		[LexerRegistry applyLexer:_document.currentLexer toEditor:_document.editor darkMode:(_document.theme == NPThemeDark)];
	[self refreshStatus];
}

static NSString *NPHexFromColor(NSColor *c) {
	NSColor *rgb = [c colorUsingColorSpace:NSColorSpace.sRGBColorSpace] ?: c;
	return [NSString stringWithFormat:@"#%02X%02X%02X",
		(int)(rgb.redComponent * 255.0 + 0.5),
		(int)(rgb.greenComponent * 255.0 + 0.5),
		(int)(rgb.blueComponent * 255.0 + 0.5)];
}
static NSColor *NPColorFromBGR(long v) {
	return [NSColor colorWithSRGBRed:((v) & 0xFF) / 255.0
		green:((v >> 8) & 0xFF) / 255.0
		blue:((v >> 16) & 0xFF) / 255.0
		alpha:1];
}

- (void)schemeCustomize {
	const EDITLEXER *lex = _document.currentLexer;
	if (!lex) {
		if ([self runningHeadless]) return;
		NSAlert *a = [[NSAlert alloc] init];
		a.messageText = NPL(@"Customize Schemes");
		a.informativeText = NPL(@"Open a file or choose a syntax scheme first.");
		[a addButtonWithTitle:NPL(@"OK")];
		[a beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse r) {}];
		return;
	}
	if ([self runningHeadless]) return;
	NSArray<NSDictionary *> *styles = [LexerRegistry styleDescriptorsForLexer:lex];
	NSView *box = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 360, 150)];
	NSPopUpButton *pop = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(0, 120, 360, 26) pullsDown:NO];
	for (NSDictionary *st in styles) [pop addItemWithTitle:st[@"name"] ?: @""];
	NSTextField *foreLbl = [NSTextField labelWithString:NPL(@"Foreground")];
	foreLbl.frame = NSMakeRect(0, 86, 90, 20);
	NSColorWell *fore = [[NSColorWell alloc] initWithFrame:NSMakeRect(96, 84, 44, 24)];
	NSTextField *backLbl = [NSTextField labelWithString:NPL(@"Background")];
	backLbl.frame = NSMakeRect(160, 86, 90, 20);
	NSColorWell *back = [[NSColorWell alloc] initWithFrame:NSMakeRect(256, 84, 44, 24)];
	NSButton *bold = [NSButton checkboxWithTitle:NPL(@"Bold") target:nil action:nil];
	bold.frame = NSMakeRect(0, 50, 80, 20);
	NSButton *italic = [NSButton checkboxWithTitle:NPL(@"Italic") target:nil action:nil];
	italic.frame = NSMakeRect(90, 50, 80, 20);
	void (^loadStyle)(void) = ^{
		NSInteger idx = pop.indexOfSelectedItem;
		if (idx < 0 || (NSUInteger)idx >= styles.count) return;
		unsigned long sid = [styles[idx][@"style"] unsignedLongValue];
		if (sid > STYLE_MAX) sid &= 0xFF;
		const long f = [_document.editor message:SCI_STYLEGETFORE wParam:sid];
		const long b = [_document.editor message:SCI_STYLEGETBACK wParam:sid];
		fore.color = NPColorFromBGR(f);
		back.color = NPColorFromBGR(b);
		bold.state = [_document.editor message:SCI_STYLEGETBOLD wParam:sid] ? NSControlStateValueOn : NSControlStateValueOff;
		italic.state = [_document.editor message:SCI_STYLEGETITALIC wParam:sid] ? NSControlStateValueOn : NSControlStateValueOff;
	};
	loadStyle();
	[box addSubview:pop]; [box addSubview:foreLbl]; [box addSubview:fore];
	[box addSubview:backLbl]; [box addSubview:back]; [box addSubview:bold]; [box addSubview:italic];
	NSAlert *a = [[NSAlert alloc] init];
	a.messageText = NPL(@"Customize Schemes");
	a.informativeText = [LexerRegistry displayNameForLexer:lex] ?: @"";
	a.accessoryView = box;
	[a addButtonWithTitle:NPL(@"Apply")];
	[a addButtonWithTitle:NPL(@"Reset")];
	[a addButtonWithTitle:NPL(@"Close")];
	[a beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse r) {
		NSString *lname = [LexerRegistry displayNameForLexer:lex];
		if (r == NSAlertSecondButtonReturn) {
			[LexerRegistry clearUserOverridesForLexerName:lname];
			[LexerRegistry applyLexer:lex toEditor:self.editorDocument.editor darkMode:(self.editorDocument.theme == NPThemeDark)];
			[self refreshStatus];
			return;
		}
		if (r != NSAlertFirstButtonReturn) return;
		NSInteger idx = pop.indexOfSelectedItem;
		if (idx < 0 || (NSUInteger)idx >= styles.count) return;
		NSString *sname = styles[idx][@"name"];
		NSMutableString *val = [NSMutableString string];
		[val appendFormat:@"fore:%@; back:%@", NPHexFromColor(fore.color), NPHexFromColor(back.color)];
		if (bold.state == NSControlStateValueOn) [val appendString:@"; bold"];
		if (italic.state == NSControlStateValueOn) [val appendString:@"; italic"];
		[LexerRegistry setUserStyleValue:val forLexerName:lname styleName:sname];
		[LexerRegistry applyLexer:lex toEditor:self.editorDocument.editor darkMode:(self.editorDocument.theme == NPThemeDark)];
		[self refreshStatus];
	}];
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
	NSString *pref = NPLanguagePreferenceCode();
	_langSystemItem.state = [pref isEqualToString:@"system"] ? NSControlStateValueOn : NSControlStateValueOff;
	for (NSMenuItem *it in _langItems) {
		it.state = [pref isEqualToString:it.representedObject] ? NSControlStateValueOn : NSControlStateValueOff;
	}
}

// 切换界面语言：重建菜单 + 状态栏 + 查找面板 + 标题
- (void)applyLanguageCode:(NSString *)code {
	NPLanguageSetCode(code);
	[self closeInWindowMenu];
	[self buildMenu];
	[_statusBar applyLanguage];
	[_statusBar setPreviewTarget:self];
	[_statusBar setPreviewActive:_previewOn];
	[_findPanel applyLanguage];
	[self updateWindowTitle];
	[self refreshStatus];
	[self.window.contentView setNeedsDisplay:YES];
}

- (void)applyLanguage:(NPLanguage)lang {
	if (lang == NPLanguageSystem) [self applyLanguageCode:@"system"];
	else if (lang == NPLanguageEnglish) [self applyLanguageCode:@"en"];
	else [self applyLanguageCode:@"zh-Hans"];
}

- (void)languageChinese { [self applyLanguageCode:@"zh-Hans"]; }
- (void)languageEnglish { [self applyLanguageCode:@"en"]; }
- (void)languageSystem { [self applyLanguageCode:@"system"]; }
- (void)languagePicked:(NSMenuItem *)sender {
	NSString *code = sender.representedObject;
	if (code.length) [self applyLanguageCode:code];
}

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
	[self openURLInTab:[NSURL fileURLWithPath:item.representedObject]];
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
	if (rtf) [pb setData:rtf forType:NSPasteboardTypeRTF];
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
	[e message:SCI_SETSEL
		wParam:[e message:SCI_WORDSTARTPOSITION wParam:pos lParam:0]
		lParam:[e message:SCI_WORDENDPOSITION wParam:pos lParam:0]];
}
- (void)viewLongLineMarker {
	ScintillaView *e = _document.editor;
	if ([e message:SCI_GETEDGEMODE] != EDGE_NONE) [e message:SCI_SETEDGEMODE wParam:EDGE_NONE lParam:0];
	else { [e message:SCI_SETEDGECOLUMN wParam:80 lParam:0]; [e message:SCI_SETEDGEMODE wParam:EDGE_LINE lParam:0]; }
	[self persistSettings];
}
- (void)viewBraceMatch {
	const BOOL on = _document.braceMatchEnabled ? NO : YES;
	[_document setBraceMatchEnabled:on];
	[[NSUserDefaults standardUserDefaults] setBool:on forKey:@"NP4BraceMatch"];
	[self persistSettings];
}
- (void)viewBookmarkMargin {
	ScintillaView *e = _document.editor;
	const sptr_t w = [e message:SCI_GETMARGINWIDTHN wParam:1 lParam:0];
	[e message:SCI_SETMARGINWIDTHN wParam:1 lParam:(w > 0 ? 0 : 16)];
	[self persistSettings];
}
- (void)settingsUseTabs {
	ScintillaView *e = _document.editor;
	[e message:SCI_SETUSETABS wParam:([e message:SCI_GETUSETABS] ? 0 : 1) lParam:0];
	[self persistSettings];
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
		[self persistSettings];
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
	[self writeSettingsToDefaults];
	[[NSUserDefaults standardUserDefaults] synchronize];
	if ([self runningHeadless]) return;
	NSAlert *a = [[NSAlert alloc] init]; a.messageText = NPL(@"Settings saved"); [a addButtonWithTitle:NPL(@"OK")];
	[a beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse r) {}];
}
- (BOOL)runningHeadless {
	return [[[NSProcessInfo processInfo] arguments] containsObject:@"--headless"];
}
- (BOOL)persistSettingsEnabled {
	return [[NSUserDefaults standardUserDefaults] objectForKey:@"NP4SaveOnExit"] == nil
		|| [[NSUserDefaults standardUserDefaults] boolForKey:@"NP4SaveOnExit"];
}
- (void)writeSettingsToDefaults {
	NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
	ScintillaView *e = _document.editor;
	[d setBool:([e message:SCI_GETWRAPMODE] != SC_WRAP_NONE) forKey:@"NP4WordWrap"];
	[d setBool:_document.lineNumbersVisible forKey:@"NP4ShowLineNumbers"];
	[d setBool:([e message:SCI_GETMARGINWIDTHN wParam:2] > 0) forKey:@"NP4ShowCodeFolding"];
	[d setBool:([e message:SCI_GETMARGINWIDTHN wParam:1] > 0) forKey:@"NP4ShowBookmarkMargin"];
	[d setBool:([e message:SCI_GETINDENTATIONGUIDES] != 0) forKey:@"NP4ShowIndentGuides"];
	[d setBool:([e message:SCI_GETVIEWWS] != 0) forKey:@"NP4ViewWhiteSpace"];
	[d setBool:([e message:SCI_GETVIEWEOL] != 0) forKey:@"NP4ViewEOLs"];
	[d setBool:([e message:SCI_GETUSETABS] != 0) forKey:@"NP4UseTabs"];
	[d setInteger:[e message:SCI_GETTABWIDTH] forKey:@"NP4TabWidth"];
	[d setInteger:[e message:SCI_GETINDENT] forKey:@"NP4IndentWidth"];
	[d setInteger:[e message:SCI_GETZOOM] forKey:@"NP4Zoom"];
	[d setBool:([e message:SCI_GETEDGEMODE] != EDGE_NONE) forKey:@"NP4LongLineMarker"];
	[d setBool:_document.braceMatchEnabled forKey:@"NP4BraceMatch"];
	[d setBool:_document.URLDetectEnabled forKey:@"NP4URLDetect"];
	[d setBool:!_menuBar.hidden forKey:@"NP4ShowMenu"];
	[d setBool:!_toolBar.hidden forKey:@"NP4ShowToolbar"];
	[d setBool:!_statusBar.hidden forKey:@"NP4ShowStatusbar"];
	[d setBool:_previewOn forKey:@"NP4ShowPreview"];
	[d setDouble:[self previewSplitFraction] forKey:@"NP4PreviewSplit"];
	if (self.window && [self runningHeadless] == NO)
		[d setObject:NSStringFromRect(self.window.frame) forKey:@"NP4WindowFrame"];
}
- (void)persistSettings {
	if ([self runningHeadless]) return;
	if (![self persistSettingsEnabled]) return;
	[self writeSettingsToDefaults];
}
- (void)applyPersistedChrome {
	if ([self runningHeadless]) return;
	if (!NPPrefBool(@"NP4ShowMenu", YES)) {
		_menuBar.hidden = YES;
		_menuBarHeight.constant = 0;
	}
	if (!NPPrefBool(@"NP4ShowToolbar", YES)) {
		_toolBar.hidden = YES;
		_toolBarHeight.constant = 0;
	}
	if (!NPPrefBool(@"NP4ShowStatusbar", YES)) {
		_statusBar.hidden = YES;
		_statusBarHeight.constant = 0;
	}
	if (NPPrefBool(@"NP4ShowPreview", NO)) [self setPreviewOn:YES];
	NSString *fs = [[NSUserDefaults standardUserDefaults] stringForKey:@"NP4WindowFrame"];
	if (fs.length) {
		NSRect r = NSRectFromString(fs);
		if (r.size.width >= 400 && r.size.height >= 280)
			[self.window setFrame:r display:NO];
	}
}
- (void)toggleMenuBar {
	if (!_menuBar.hidden) [self closeInWindowMenu];
	_menuBar.hidden = !_menuBar.hidden;
	_menuBarHeight.constant = _menuBar.hidden ? 0 : 28;
	[self persistSettings];
}
- (void)toggleToolbar {
	_toolBar.hidden = !_toolBar.hidden;
	_toolBarHeight.constant = _toolBar.hidden ? 0 : 30;
	[self persistSettings];
}
- (void)addCurrentToFavorites {
	NSString *path = _document.fileURL.path;
	if (!path.length) return;
	NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
	NSMutableArray *list = [([d arrayForKey:@"NP4Favorites"] ?: @[]) mutableCopy];
	[list removeObject:path];
	[list insertObject:path atIndex:0];
	if (list.count > 30) [list removeObjectsInRange:NSMakeRange(30, list.count - 30)];
	[d setObject:list forKey:@"NP4Favorites"];
}
- (void)openFavorite:(NSMenuItem *)item {
	[self openURLInTab:[NSURL fileURLWithPath:item.representedObject]];
}
- (void)openToolbarMenu:(NSMenu *)menu fromView:(NSView *)anchor {
	if (!menu) return;
	if (!self.window.isKeyWindow && ![self runningHeadless]) return;
	_openMenuIndex = -2;
	[self clearFlyouts];
	[_dropPanelItems removeAllObjects];
	[self clearMenuOpenHighlights];
	[self fillPanel:_dropDown menu:menu panelIndex:0];
	NSSize sz = [self measureMenu:menu];
	NSView *root = self.window.contentView;
	[root layoutSubtreeIfNeeded];
	NSRect br = [anchor convertRect:anchor.bounds toView:root];
	NSPoint topLeft = NSMakePoint(NSMinX(br), NSMinY(br));
	[self placePanel:_dropDown size:sz topLeft:topLeft];
	[self sizeRowsInPanel:_dropDown width:sz.width];
	[root addSubview:_dropDown positioned:NSWindowAbove relativeTo:nil];
}

- (void)tbOpenFav {
	NSMenu *m = [[NSMenu alloc] init];
	NSMenuItem *add = [m addItemWithTitle:NPL(@"Add to Favorites") action:@selector(addCurrentToFavorites) keyEquivalent:@""];
	add.target = self;
	add.enabled = _document.fileURL != nil;
	[m addItem:[NSMenuItem separatorItem]];
	NSArray *list = [[NSUserDefaults standardUserDefaults] arrayForKey:@"NP4Favorites"] ?: @[];
	if (!list.count) {
		NSMenuItem *empty = [m addItemWithTitle:NPL(@"No favorites") action:nil keyEquivalent:@""];
		empty.enabled = NO;
	} else {
		for (NSString *path in list) {
			NSMenuItem *it = [m addItemWithTitle:path.lastPathComponent action:@selector(openFavorite:) keyEquivalent:@""];
			it.target = self;
			it.representedObject = path;
			it.toolTip = path;
		}
	}
	NSView *anchor = nil;
	if ([NSApp currentEvent].window == self.window)
		anchor = [self.window.contentView hitTest:[NSApp currentEvent].locationInWindow];
	if (!anchor) {
		for (NSView *v in _toolBar.subviews) {
			if ([v isKindOfClass:[NPImageButton class]] && ((NPImageButton *)v).tbAction == @selector(tbOpenFav))
				{ anchor = v; break; }
		}
	}
	[self openToolbarMenu:m fromView:anchor ?: _toolBar];
}
- (void)tbBrowse { [self openContainingFolder]; }
- (void)tbOpenDropdown { [self fileOpen]; }
- (void)tbOpenMenu {
	NSMenu *m = [[NSMenu alloc] init];
	NSMenuItem *open = [m addItemWithTitle:NPL(@"Open...") action:@selector(fileOpen) keyEquivalent:@""];
	open.target = self;
	[m addItem:[NSMenuItem separatorItem]];
	NSArray *list = [[NSUserDefaults standardUserDefaults] arrayForKey:@"NP4RecentFiles"] ?: @[];
	if (!list.count) {
		NSMenuItem *empty = [m addItemWithTitle:NPL(@"No recent files") action:nil keyEquivalent:@""];
		empty.enabled = NO;
	} else {
		for (NSString *path in list) {
			NSMenuItem *it = [m addItemWithTitle:path.lastPathComponent action:@selector(openRecentFile:) keyEquivalent:@""];
			it.target = self;
			it.representedObject = path;
			it.toolTip = path;
		}
	}
	NSView *anchor = nil;
	for (NSView *v in _toolBar.subviews) {
		if ([v isKindOfClass:[NPImageButton class]] && ((NPImageButton *)v).tbAction == @selector(tbOpenDropdown))
			{ anchor = v; break; }
	}
	[self openToolbarMenu:m fromView:anchor ?: _toolBar];
}
- (void)ensureFoldingEnabled {
	ScintillaView *e = _document.editor;
	[e setLexerProperty:@"fold" value:@"1"];
	[e setLexerProperty:@"fold.compact" value:@"0"];
	[e setLexerProperty:@"fold.comment" value:@"1"];
	[e setLexerProperty:@"fold.preprocessor" value:@"1"];
	[e message:SCI_SETMARGINTYPEN wParam:2 lParam:SC_MARGIN_SYMBOL];
	[e message:SCI_SETMARGINMASKN wParam:2 lParam:SC_MASK_FOLDERS];
	[e message:SCI_SETMARGINSENSITIVEN wParam:2 lParam:1];
	if ([e message:SCI_GETMARGINWIDTHN wParam:2] <= 0)
		[e message:SCI_SETMARGINWIDTHN wParam:2 lParam:14];
	[e message:SCI_MARKERDEFINE wParam:SC_MARKNUM_FOLDER lParam:SC_MARK_BOXPLUS];
	[e message:SCI_MARKERDEFINE wParam:SC_MARKNUM_FOLDEROPEN lParam:SC_MARK_BOXMINUS];
	[e message:SCI_MARKERDEFINE wParam:SC_MARKNUM_FOLDERSUB lParam:SC_MARK_VLINE];
	[e message:SCI_MARKERDEFINE wParam:SC_MARKNUM_FOLDERTAIL lParam:SC_MARK_LCORNER];
	[e message:SCI_MARKERDEFINE wParam:SC_MARKNUM_FOLDEREND lParam:SC_MARK_BOXPLUSCONNECTED];
	[e message:SCI_MARKERDEFINE wParam:SC_MARKNUM_FOLDEROPENMID lParam:SC_MARK_BOXMINUSCONNECTED];
	[e message:SCI_MARKERDEFINE wParam:SC_MARKNUM_FOLDERMIDTAIL lParam:SC_MARK_TCORNER];
	[e message:SCI_SETFOLDFLAGS wParam:16 lParam:0];
	[e message:SCI_COLOURISE wParam:0 lParam:-1];
}
- (sptr_t)foldHeaderLine {
	ScintillaView *e = _document.editor;
	sptr_t line = [e message:SCI_LINEFROMPOSITION wParam:[e message:SCI_GETCURRENTPOS]];
	const sptr_t level = [e message:SCI_GETFOLDLEVEL wParam:line];
	if (!(level & SC_FOLDLEVELHEADERFLAG)) {
		const sptr_t parent = [e message:SCI_GETFOLDPARENT wParam:line];
		if (parent >= 0) line = parent;
	}
	return line;
}
- (void)foldToggleCurrent {
	[self ensureFoldingEnabled];
	ScintillaView *e = _document.editor;
	const sptr_t line = [self foldHeaderLine];
	const sptr_t expanded = [e message:SCI_GETFOLDEXPANDED wParam:line];
	[e message:SCI_FOLDLINE wParam:line lParam:(expanded ? SC_FOLDACTION_CONTRACT : SC_FOLDACTION_EXPAND)];
}
- (void)foldAll {
	[self ensureFoldingEnabled];
	[_document.editor message:SCI_FOLDALL wParam:SC_FOLDACTION_CONTRACT lParam:0];
}
- (void)unfoldAll {
	[self ensureFoldingEnabled];
	[_document.editor message:SCI_FOLDALL wParam:SC_FOLDACTION_EXPAND lParam:0];
}
- (void)foldToggleAll {
	[self ensureFoldingEnabled];
	[_document.editor message:SCI_FOLDALL wParam:SC_FOLDACTION_TOGGLE lParam:0];
}
- (void)tbFoldDropdown { [self foldToggleCurrent]; }
- (void)tbFoldMenu {
	NSMenu *m = [[NSMenu alloc] init];
	NSMenuItem *(^add)(NSString *, SEL) = ^NSMenuItem *(NSString *title, SEL act) {
		NSMenuItem *it = [m addItemWithTitle:title action:act keyEquivalent:@""];
		it.target = self;
		return it;
	};
	add(NPL(@"Toggle Current Fold"), @selector(foldToggleCurrent));
	add(NPL(@"Fold All"), @selector(foldAll));
	add(NPL(@"Unfold All"), @selector(unfoldAll));
	add(NPL(@"Toggle All Folds"), @selector(foldToggleAll));
	[m addItem:[NSMenuItem separatorItem]];
	add(NPL(@"Show Code Folding"), @selector(viewCodeFolding));
	NSView *anchor = nil;
	for (NSView *v in _toolBar.subviews) {
		if ([v isKindOfClass:[NPImageButton class]] && ((NPImageButton *)v).tbAction == @selector(tbFoldDropdown))
			{ anchor = v; break; }
	}
	[self openToolbarMenu:m fromView:anchor ?: _toolBar];
}
- (void)tbSchemeMenu { [self schemeChoose]; }
- (void)tbSchemeConfig { [self schemeCustomize]; }
- (void)terminate { [NSApp terminate:nil]; }
- (BOOL)validateMenuItem:(NSMenuItem *)item {
	const SEL a = item.action;
	if (a == @selector(fileRevert) || a == @selector(openContainingFolder)
		|| a == @selector(fileSaveBackup))
		return _document.fileURL != nil;
	if (a == @selector(undo:) || a == @selector(editUndo))
		return [_document.editor message:SCI_CANUNDO] != 0;
	if (a == @selector(redo:) || a == @selector(editRedo))
		return [_document.editor message:SCI_CANREDO] != 0;
	return YES;
}
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
	NSMutableCharacterSet *allowed = [NSMutableCharacterSet alphanumericCharacterSet];
	[allowed addCharactersInString:@"-._~"];
	NSString *enc = [sel stringByAddingPercentEncodingWithAllowedCharacters:allowed];
	if (enc) [_document.editor message:SCI_REPLACESEL wParam:0 lParam:(sptr_t)enc.UTF8String];
}
- (void)urlDecode {
	NSString *sel = [_document.editor selectedString];
	if (!sel.length) return;
	NSString *s = [sel stringByRemovingPercentEncoding];
	if (s) [_document.editor message:SCI_REPLACESEL wParam:0 lParam:(sptr_t)s.UTF8String];
}
- (NSString *)projectHomeURL {
	return @"https://github.com/limin640/notepad-mac";
}
- (void)helpHome {
	if ([self runningHeadless]) return;
	[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:[self projectHomeURL]]];
}
- (void)helpDonate {
	if ([self runningHeadless]) return;
	NSAlert *a = [[NSAlert alloc] init];
	a.messageText = NPL(@"Donate");
	NSImage *qr = [NSImage imageNamed:@"wechat-donate"];
	if (!qr) {
		NSString *path = [[NSBundle mainBundle] pathForResource:@"wechat-donate" ofType:@"png"];
		if (path) qr = [[NSImage alloc] initWithContentsOfFile:path];
	}
	if (qr) {
		a.informativeText = NPL(@"If you find Notepad Mac useful, you can donate via WeChat Pay.");
		NSImageView *iv = [[NSImageView alloc] initWithFrame:NSMakeRect(0, 0, 240, 240)];
		iv.image = qr;
		iv.imageScaling = NSImageScaleProportionallyUpOrDown;
		a.accessoryView = iv;
	} else {
		a.informativeText = NPL(@"See the project homepage for the donation QR code.");
	}
	[a addButtonWithTitle:NPL(@"OK")];
	[a runModal];
}

- (void)nyi {
	NSLog(@"[Notepad4-mac] action not yet implemented");
}

#pragma mark - NSWindowDelegate


- (NSInteger)tabCount { return (NSInteger)_documents.count; }
- (BOOL)hasTabNewButton { return _tabPlus != nil && _tabPlus.hidden == NO; }
- (BOOL)currentTabIsReusable {
	return _document.fileURL == nil && !_document.dirty
		&& [_document.editor message:SCI_GETLENGTH] == 0;
}
- (void)addAndActivateDocument:(EditorDocument *)doc {
	if (!doc) return;
	if (!_documents) _documents = [NSMutableArray array];
	[_documents addObject:doc];
	[self activateDocument:doc];
}
- (void)activateDocument:(EditorDocument *)doc {
	if (!doc) return;
	_document = doc;
	[self swapEditor];
	[self rebuildTabBar];
}
- (void)openURLInTab:(NSURL *)url {
	if (!url.path.length) return;
	BOOL isDir = NO;
	if ([[NSFileManager defaultManager] fileExistsAtPath:url.path isDirectory:&isDir] && isDir) return;
	for (EditorDocument *d in _documents) {
		if ([d.fileURL.path isEqualToString:url.path]) {
			[self activateDocument:d];
			return;
		}
	}
	EditorDocument *doc = [[EditorDocument alloc] initWithFileURL:url contents:@""];
	if (![doc loadFromURL:url error:nil]) return;
	if ([self currentTabIsReusable] && _documents.count) {
		NSUInteger idx = [_documents indexOfObject:_document];
		if (idx != NSNotFound) _documents[idx] = doc;
		[self activateDocument:doc];
	} else {
		[self addAndActivateDocument:doc];
	}
	[self noteRecentFile:url];
}
- (void)rebuildTabBar {
	if (!_tabBar) return;
	for (NSView *v in [_tabBar.subviews copy]) {
		if (v == _tabPlus) continue;
		[v removeFromSuperview];
	}
	CGFloat x = 4;
	for (NSUInteger i = 0; i < _documents.count; i++) {
		EditorDocument *d = _documents[i];
		NSString *name = d.fileURL.lastPathComponent ?: d.tabTitle;
		if (!name.length) name = NPL(@"Untitled");
		if (d.dirty) name = [@"* " stringByAppendingString:name];
		const CGFloat w = MIN(180, MAX(88, [name sizeWithAttributes:@{NSFontAttributeName:[NSFont systemFontOfSize:11]}].width + 28));
		NPTabChip *chip = [[NPTabChip alloc] initWithFrame:NSMakeRect(x, 1, w, 24)];
		chip.title = name;
		chip.index = (NSInteger)i;
		chip.selected = (d == _document);
		chip.target = self;
		[_tabBar addSubview:chip];
		x += w + 2;
	}
	if (_tabPlus) [_tabBar addSubview:_tabPlus];
	_tabBar.needsDisplay = YES;
}
- (void)tabClicked:(NPTabChip *)chip {
	if (chip.index < 0 || (NSUInteger)chip.index >= _documents.count) return;
	[self activateDocument:_documents[chip.index]];
}
- (void)tabCloseClicked:(NPTabChip *)chip {
	if (chip.index < 0 || (NSUInteger)chip.index >= _documents.count) return;
	[self activateDocument:_documents[chip.index]];
	[self fileCloseTab];
}
- (void)fileCloseTab {
	void (^go)(void) = ^{
		if (_documents.count <= 1) {
			[_document.editor message:SCI_SETSAVEPOINT wParam:0 lParam:0];
			[self.window performClose:nil];
			return;
		}
		NSInteger idx = (NSInteger)[_documents indexOfObject:_document];
		[_documents removeObject:_document];
		if (idx >= (NSInteger)_documents.count) idx = (NSInteger)_documents.count - 1;
		if (idx < 0) idx = 0;
		[self activateDocument:_documents[idx]];
	};
	if (!_document.dirty) { go(); return; }
	if ([self runningHeadless]) { go(); return; }
	NSAlert *a = [[NSAlert alloc] init];
	a.messageText = NPL(@"Save changes?");
	a.informativeText = NPL(@"The document has unsaved changes.");
	[a addButtonWithTitle:NPL(@"Save")];
	[a addButtonWithTitle:NPL(@"Don't Save")];
	[a addButtonWithTitle:NPL(@"Cancel")];
	[a beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse r) {
		if (r == NSAlertFirstButtonReturn)
			[self fileSaveThen:^(BOOL ok) { if (ok) go(); }];
		else if (r == NSAlertSecondButtonReturn)
			go();
	}];
}

- (void)finishCloseTask {
	if (_windowClosed) return;
	_windowClosed = YES;
	[self persistSettings];
	[self closeInWindowMenu];
	[_previewPane shutdown];
	if (_keyMonitor) { [NSEvent removeMonitor:_keyMonitor]; _keyMonitor = nil; }
	if (_dropClickMonitor) { [NSEvent removeMonitor:_dropClickMonitor]; _dropClickMonitor = nil; }
	[MainWindowController unregisterLive:self];
	NSDocumentController *dc = [NSDocumentController sharedDocumentController];
	for (NSDocument *d in [dc.documents copy]) [d close];
	if ([self runningHeadless]) return;
	if ([MainWindowController liveControllerCount] == 0)
		[NSApp terminate:nil];
}
- (void)windowWillClose:(NSNotification *)note {
	(void)note;
	[self finishCloseTask];
}
- (BOOL)windowShouldClose:(NSWindow *)sender {
	[self persistSettings];
	BOOL anyDirty = NO;
	for (EditorDocument *d in _documents) { if (d.dirty) { anyDirty = YES; break; } }
	if (!anyDirty) return YES;
	if ([self runningHeadless]) return YES;
	NSAlert *a = [[NSAlert alloc] init];
	a.messageText = NPL(@"Save changes?");
	a.informativeText = NPL(@"There are unsaved documents.");
	[a addButtonWithTitle:NPL(@"Save")];
	[a addButtonWithTitle:NPL(@"Don't Save")];
	[a addButtonWithTitle:NPL(@"Cancel")];
	[a beginSheetModalForWindow:sender completionHandler:^(NSModalResponse r) {
		if (r == NSAlertSecondButtonReturn) {
			for (EditorDocument *d in _documents) {
				if (d.dirty) [d.editor message:SCI_SETSAVEPOINT wParam:0 lParam:0];
			}
			[sender close];
			return;
		}
		if (r != NSAlertFirstButtonReturn) return;
		for (EditorDocument *d in _documents) {
			if (!d.dirty) continue;
			if (d.fileURL) { [d saveToURL:d.fileURL error:nil]; continue; }
			[self activateDocument:d];
			[self fileSaveThen:^(BOOL ok) { if (ok) [sender close]; }];
			return;
		}
		[sender close];
	}];
	return NO;
}

@end
