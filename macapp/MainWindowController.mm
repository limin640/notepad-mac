#import "MainWindowController.h"
#import "SciLexer.h"

static NSString * const kUntitledCounterKey = @"kUntitledCounter";

@implementation MainWindowController {
	NSTabView *_tabView;
	NSInteger _untitledCounter;
}

- (instancetype)init {
	NSWindow *win = [[NSWindow alloc]
		initWithContentRect:NSMakeRect(120, 120, 1000, 680)
		styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
			   NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable |
			   NSWindowStyleMaskFullSizeContentView)
		backing:NSBackingStoreBuffered defer:NO];
	win.title = @"Notepad4";
	win.titlebarAppearsTransparent = NO;
	win.minSize = NSMakeSize(480, 320);
	self = [super initWithWindow:win];
	if (self) {
		win.delegate = self;
		win.windowController = self;
		[self buildUI:win];
		[self buildMenu];
		[self newTab];
	}
	return self;
}

- (void)buildUI:(NSWindow *)win {
	_tabView = [[NSTabView alloc] initWithFrame:win.contentView.bounds];
	_tabView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
	_tabView.delegate = self;
	_tabView.tabViewType = NSTopTabsBezelBorder;
	win.contentView = _tabView;
}

- (void)buildMenu {
	NSMenu *menubar = [[NSMenu alloc] init];

	// App 菜单
	NSMenuItem *appItem = [menubar addItemWithTitle:@"Notepad4" action:nil keyEquivalent:@""];
	NSMenu *appMenu = [[NSMenu alloc] init];
	[appMenu addItemWithTitle:@"关于 Notepad4" action:@selector(orderFrontStandardAboutPanel:) keyEquivalent:@""];
	[appMenu addItem:[NSMenuItem separatorItem]];
	[appMenu addItemWithTitle:@"隐藏" action:@selector(hide:) keyEquivalent:@"h"];
	[[appMenu addItemWithTitle:@"隐藏其它" action:@selector(hideOtherApplications:) keyEquivalent:@"h"]
		setKeyEquivalentModifierMask:NSEventModifierFlagCommand | NSEventModifierFlagOption];
	[appMenu addItemWithTitle:@"显示全部" action:@selector(unhideAllApplications:) keyEquivalent:@""];
	[appMenu addItem:[NSMenuItem separatorItem]];
	[appMenu addItemWithTitle:@"退出 Notepad4" action:@selector(terminate:) keyEquivalent:@"q"];
	appItem.submenu = appMenu;

	// 文件菜单
	NSMenuItem *fileItem = [menubar addItemWithTitle:@"文件" action:nil keyEquivalent:@""];
	NSMenu *fileMenu = [[NSMenu alloc] init];
	[fileMenu addItemWithTitle:@"新建标签页" action:@selector(newTab) keyEquivalent:@"t"];
	[fileMenu addItemWithTitle:@"打开…" action:@selector(openDocument) keyEquivalent:@"o"];
	[fileMenu addItem:[NSMenuItem separatorItem]];
	[fileMenu addItemWithTitle:@"关闭标签页" action:@selector(closeTab) keyEquivalent:@"w"];
	[fileMenu addItemWithTitle:@"保存" action:@selector(saveDocument) keyEquivalent:@"s"];
	[fileMenu addItemWithTitle:@"另存为…" action:@selector(saveDocumentAs) keyEquivalent:@"S"];
	fileItem.submenu = fileMenu;

	// 编辑菜单
	NSMenuItem *editItem = [menubar addItemWithTitle:@"编辑" action:nil keyEquivalent:@""];
	NSMenu *editMenu = [[NSMenu alloc] init];
	NSString *editSel = @"edit";
	[editMenu addItemWithTitle:@"撤销" action:@selector(undo:) keyEquivalent:@"z"];
	[editMenu addItemWithTitle:@"重做" action:@selector(redo:) keyEquivalent:@"Z"];
	[editMenu addItem:[NSMenuItem separatorItem]];
	[editMenu addItemWithTitle:@"剪切" action:@selector(cut:) keyEquivalent:@"x"];
	[editMenu addItemWithTitle:@"拷贝" action:@selector(copy:) keyEquivalent:@"c"];
	[editMenu addItemWithTitle:@"粘贴" action:@selector(paste:) keyEquivalent:@"v"];
	[editMenu addItemWithTitle:@"全选" action:@selector(selectAll:) keyEquivalent:@"a"];
	[editMenu addItem:[NSMenuItem separatorItem]];
	[editMenu addItemWithTitle:@"查找…" action:@selector(findInDoc:) keyEquivalent:@"f"];
	[editMenu addItemWithTitle:@"查找下一个" action:@selector(findNext:) keyEquivalent:@"g"];
	editItem.submenu = editMenu;

	NSApp.mainMenu = menubar;
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

- (void)addTabForDocument:(EditorDocument *)doc {
	NSTabViewItem *item = [[NSTabViewItem alloc] initWithIdentifier:doc];
	item.label = doc.tabTitle;
	NSView *container = [[NSView alloc] initWithFrame:_tabView.bounds];
	container.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
	doc.editor.frame = container.bounds;
	[container addSubview:doc.editor];
	item.view = container;
	[_tabView addTabViewItem:item];
	[_tabView selectTabViewItem:item];
	[self updateWindowTitle];
	[self observeDocument:doc];
}

- (void)observeDocument:(EditorDocument *)doc {
	[[NSNotificationCenter defaultCenter] addObserver:self
		selector:@selector(docDirtyChanged:)
		name:@"EditorDocumentDirtyChanged"
		object:doc];
}

- (void)docDirtyChanged:(NSNotification *)n {
	EditorDocument *doc = n.object;
	// 标签标题带修改点
	for (NSTabViewItem *item in _tabView.tabViewItems) {
		if (item.identifier == doc) {
			item.label = doc.dirty ? [doc.tabTitle stringByAppendingString:@" •"] : doc.tabTitle;
		}
	}
	[self updateWindowTitle];
}

- (void)updateWindowTitle {
	EditorDocument *doc = self.currentDocument;
	self.window.title = doc.windowTitle ?: @"Notepad4";
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

- (BOOL)saveDocument {
	EditorDocument *doc = self.currentDocument;
	if (!doc) return NO;
	if (!doc.fileURL) {
		return [self saveDocumentAs];
	}
	NSError *err = nil;
	if (![doc saveToURL:doc.fileURL error:&err]) {
		NSAlert *alert = [[NSAlert alloc] init];
		alert.messageText = @"保存失败";
		alert.informativeText = err.localizedDescription;
		[alert beginSheetModalForWindow:self.window completionHandler:nil];
		return NO;
	}
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
			NSAlert *alert = [[NSAlert alloc] init];
			alert.messageText = @"保存失败";
			alert.informativeText = err.localizedDescription;
			[alert beginSheetModalForWindow:self.window completionHandler:nil];
		} else {
			[doc applyLexerForExtension:panel.URL.pathExtension.lowercaseString];
			[self docDirtyChanged:[NSNotification notificationWithName:@"EditorDocumentDirtyChanged" object:doc]];
		}
	}];
	return YES;
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

#pragma mark - 查找（简易，正则面板后续阶段）

- (void)findInDoc:(id)sender {
	EditorDocument *doc = self.currentDocument;
	if (!doc) return;
	// 占位：正式查找面板在特性移植阶段
	[self findNext:sender];
}

- (void)findNext:(id)sender {
	EditorDocument *doc = self.currentDocument;
	if (!doc) return;
	NSString *needle = [NSPasteboard.generalPasteboard stringForType:NSPasteboardTypeString];
	if (!needle.length) return;
	[doc.editor findAndHighlightText:needle
		matchCase:NO wholeWord:NO wrap:YES backwards:NO];
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
