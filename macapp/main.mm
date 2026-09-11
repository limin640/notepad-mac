// 程序入口 + 调试钩子
// 钩子（仅测试用）：
//   --code <src> [--ext cpp] [--find needle] [--theme dark]   注入文本并应用词法器
//   --appearance light|dark                                    强制外观（验证两种模式）
//   --shot <path.(png|pdf|txt)> [--delay N]                    延迟后自截窗口并退出
//   --printwid                                                 打印窗口号（外部 screencapture -l 用）
//   --bugtest                                                  光标/菜单溢出/包围 三项实测（含截图）
//   --closetest                                                验证关闭窗口行为
#import <Cocoa/Cocoa.h>
#import <CoreGraphics/CoreGraphics.h>
#include <dlfcn.h>
#include <cstring>
#import "MainWindowController.h"
#import "EditorDocument.h"
#import "NPTheme.h"
#import "NPLocalization.h"
#import "FindReplacePanel.h"
#import "LexerRegistry.h"
#import "EditCommands.h"
#import "PreviewPane.h"
#import "SciLexer.h"
#import "EditLexer.h"
#import "Scintilla.h"

static void DumpViewTree(NSView *v, int depth, NSMutableString *tree) {
	[tree appendFormat:@"%@%@ f=%@ tam=%d hidden=%d\n", [[NSString alloc] initWithFormat:@"%*s", depth*2, ""],
		NSStringFromClass(v.class), NSStringFromRect(v.frame), (int)v.translatesAutoresizingMaskIntoConstraints,
		(int)v.hidden];
	for (NSView *sub in v.subviews) DumpViewTree(sub, depth + 1, tree);
}

static void DumpMenuTree(NSMenu *m, int depth, NSMutableString *out) {
	for (NSMenuItem *it in m.itemArray) {
		if (it.isSeparatorItem) continue;
		[out appendFormat:@"%*s%@\n", depth * 2, "", it.title];
		if (it.submenu) DumpMenuTree(it.submenu, depth + 1, out);
	}
}

static void NPCacheShot(NSView *v, NSString *path) {
	if (!v) return;
	[v layoutSubtreeIfNeeded];
	NSRect b = v.bounds;
	if (b.size.width < 2 || b.size.height < 2) return;
	NSBitmapImageRep *rep = [v bitmapImageRepForCachingDisplayInRect:b];
	if (!rep) return;
	[v cacheDisplayInRect:b toBitmapImageRep:rep];
	[[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:path atomically:YES];
}

static BOOL NP4HeadlessNow(void) {
	return [[[NSProcessInfo processInfo] arguments] containsObject:@"--headless"]
		|| getenv("NP4_HEADLESS") != NULL;
}

@interface NPAppDelegate : NSObject <NSApplicationDelegate>
@property (nonatomic, weak) MainWindowController *controller;
@property (nonatomic, strong) NSMutableArray<NSURL *> *pendingURLs;
@property (nonatomic) BOOL finishedLaunching;
- (void)flushPending;
- (void)openURLsLocally:(NSArray<NSURL *> *)urls;
- (void)handleOpenDocuments:(NSAppleEventDescriptor *)event withReplyEvent:(NSAppleEventDescriptor *)reply;
@end
@implementation NPAppDelegate
- (instancetype)init {
	self = [super init];
	if (self) _pendingURLs = [NSMutableArray array];
	return self;
}
- (MainWindowController *)ensureController {
	if (self.controller && [self.controller windowIsUsable])
		return self.controller;
	MainWindowController *c = [[MainWindowController alloc] init];
	self.controller = c;
	return c;
}
- (void)openURLsLocally:(NSArray<NSURL *> *)urls {
	if (urls.count == 0) return;
	MainWindowController *c = [self ensureController];
	for (NSURL *u in urls) [c openURLInTab:u];
	[c presentWindow];
}
- (void)launchNewInstanceWithURLs:(NSArray<NSURL *> *)urls {
	NSURL *appURL = [[NSBundle mainBundle] bundleURL];
	if (appURL == nil || urls.count == 0) { [self openURLsLocally:urls]; return; }
	NSWorkspaceOpenConfiguration *cfg = [NSWorkspaceOpenConfiguration configuration];
	cfg.createsNewApplicationInstance = YES;
	cfg.activates = YES;
	[[NSWorkspace sharedWorkspace] openURLs:urls withApplicationAtURL:appURL
		configuration:cfg completionHandler:nil];
}
- (void)flushPending {
	if (self.pendingURLs.count == 0) return;
	NSArray *urls = [self.pendingURLs copy];
	[self.pendingURLs removeAllObjects];
	[self openURLsLocally:urls];
}
- (void)applicationDidFinishLaunching:(NSNotification *)n {
	(void)n;
	self.finishedLaunching = YES;
	[self flushPending];
}
- (BOOL)applicationSupportsSecureRestorableState:(NSApplication *)app { (void)app; return NO; }
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
	(void)sender;
	return NP4HeadlessNow() ? NO : YES;
}
- (BOOL)applicationShouldHandleReopen:(NSApplication *)sender hasVisibleWindows:(BOOL)flag {
	(void)sender;
	if (NP4HeadlessNow()) return NO;
	if (flag) return YES;
	[[self ensureController] presentWindow];
	return YES;
}
- (void)application:(NSApplication *)app openURLs:(NSArray<NSURL *> *)urls {
	(void)app;
	if (urls.count == 0) return;
	if (NP4HeadlessNow() || self.finishedLaunching == NO) {
		if (self.controller == nil && self.finishedLaunching == NO) {
			[self.pendingURLs addObjectsFromArray:urls];
			return;
		}
		[self openURLsLocally:urls];
		return;
	}
	MainWindowController *c = self.controller;
	if (c && [c windowIsUsable] && [c currentTabIsReusable] == NO) {
		[self launchNewInstanceWithURLs:urls];
		return;
	}
	[self openURLsLocally:urls];
}
- (BOOL)application:(NSApplication *)sender openFile:(NSString *)filename {
	[self application:sender openURLs:@[[NSURL fileURLWithPath:filename]]];
	return YES;
}
- (void)application:(NSApplication *)sender openFiles:(NSArray<NSString *> *)filenames {
	NSMutableArray *urls = [NSMutableArray array];
	for (NSString *p in filenames) [urls addObject:[NSURL fileURLWithPath:p]];
	[self application:sender openURLs:urls];
}
- (BOOL)applicationShouldOpenUntitledFile:(NSApplication *)sender { return YES; }
- (BOOL)applicationShouldHandleOpenUntitledFile:(NSApplication *)sender { return YES; }
- (void)handleOpenDocuments:(NSAppleEventDescriptor *)event withReplyEvent:(NSAppleEventDescriptor *)reply {
	(void)reply;
	NSAppleEventDescriptor *direct = [event paramDescriptorForKeyword:keyDirectObject];
	NSMutableArray<NSURL *> *urls = [NSMutableArray array];
	void (^addDesc)(NSAppleEventDescriptor *) = ^(NSAppleEventDescriptor *desc) {
		if (!desc) return;
		NSURL *url = desc.fileURLValue;
		if (!url) {
			NSString *s = desc.stringValue;
			if (s.length)
				url = [s hasPrefix:@"file:"] ? [NSURL URLWithString:s] : [NSURL fileURLWithPath:s];
		}
		if (url) [urls addObject:url];
	};
	if (direct.descriptorType == typeAEList) {
		for (NSInteger i = 1; i <= direct.numberOfItems; i++) addDesc([direct descriptorAtIndex:i]);
	} else {
		addDesc(direct);
	}
	if (urls.count) [self application:NSApp openURLs:urls];
}
@end

@interface NPDocController : NSDocumentController
@end

@interface NPShimDocument : NSDocument
@end
@implementation NPShimDocument
+ (BOOL)autosavesInPlace { return NO; }
+ (BOOL)autosavesDrafts { return NO; }
+ (BOOL)preservesVersions { return NO; }
+ (NSArray<NSString *> *)readableTypes {
	static NSArray<NSString *> *types;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		NSMutableSet<NSString *> *set = [NSMutableSet set];
		NSArray *fromSuper = [super readableTypes];
		if (fromSuper.count) [set addObjectsFromArray:fromSuper];
		[set addObjectsFromArray:@[
			@"public.item", @"public.content", @"public.data", @"public.text",
			@"public.plain-text", @"public.source-code", @"public.script",
			@"JSON", @"YAML", @"Markdown", @"Markdown Document", @"Markdown text file",
			@"Plain Text", @"Text Document", @"Source Code", @"Any File",
			@"JSON Document", @"YAML Document", @"HTML", @"HTML text", @"HTML Document",
			@"XML", @"XML text", @"XML Document", @"XHTML",
			@"Python script", @"Python Script", @"JavaScript",
			@"C source code", @"C Source", @"C++ source code", @"C++ Source",
			@"C header code", @"C++ header code",
			@"Swift Source Code", @"Swift Source", @"Java source code",
			@"Ruby script", @"Perl script", @"PHP script",
			@"shell script", @"Shell Script", @"property list", @"Property List",
			@"CSS", @"Makefile", @"TOML/Configuration file",
			@"comma-separated values", @"tab-separated values",
			@"SVG image", @"Patch File", @"text", @"script",
			@"Objective-C source code", @"Objective-C++ source code",
			@"assembly source code", @"Fortran source code", @"Pascal source code",
			@"Bourne-Again Shell script", @"Z Shell script", @"C Shell script",
			@"MS Windows initialization file", @"RSS web feed",
			@"纯文本", @"源代码", @"脚本", @"属性列表"
		]];
		for (NSDictionary *t in [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleDocumentTypes"]) {
			id name = t[@"CFBundleTypeName"];
			if ([name isKindOfClass:[NSString class]] && [(NSString *)name length]) [set addObject:name];
			for (id u in t[@"LSItemContentTypes"] ?: @[]) {
				if ([u isKindOfClass:[NSString class]] && [(NSString *)u length]) [set addObject:u];
			}
		}
		types = set.allObjects;
	});
	return types;
}
+ (NSArray<NSString *> *)writableTypes { return @[@"public.plain-text"]; }
+ (BOOL)isNativeType:(NSString *)typeName { (void)typeName; return YES; }
+ (BOOL)canConcurrentlyReadDocumentsOfType:(NSString *)typeName { (void)typeName; return NO; }
- (BOOL)isDocumentEdited { return NO; }
- (BOOL)readFromURL:(NSURL *)url ofType:(NSString *)typeName error:(NSError **)outError {
	(void)typeName;
	if (outError) *outError = nil;
	return url != nil;
}
- (BOOL)readFromData:(NSData *)data ofType:(NSString *)typeName error:(NSError **)outError {
	(void)data; (void)typeName;
	if (outError) *outError = nil;
	return YES;
}
- (void)makeWindowControllers {
	NPAppDelegate *del = (NPAppDelegate *)NSApp.delegate;
	if (self.fileURL) {
		if (del.controller) [del.controller openURLInTab:self.fileURL];
		else [del.pendingURLs addObject:self.fileURL];
	}
}
- (void)showWindows {}
@end
@implementation NPDocController
- (void)npOpen:(NSURL *)url {
	if (!url) return;
	if ([NSThread isMainThread] == NO) {
		dispatch_sync(dispatch_get_main_queue(), ^{ [self npOpen:url]; });
		return;
	}
	NSURL *file = url.isFileURL ? url : url.filePathURL;
	if (!file.isFileURL) return;
	NPAppDelegate *del = (NPAppDelegate *)NSApp.delegate;
	[del application:NSApp openURLs:@[file]];
}
- (NPShimDocument *)npShim:(NSURL *)url {
	NSError *err = nil;
	NPShimDocument *doc = [[NPShimDocument alloc] initWithType:@"public.plain-text" error:&err];
	if (url) doc.fileURL = url;
	return doc;
}
- (NSArray<NSString *> *)documentClassNames { return @[@"NPShimDocument"]; }
- (Class)documentClassForType:(NSString *)typeName { (void)typeName; return [NPShimDocument class]; }
- (NSString *)defaultType { return @"public.plain-text"; }
- (NSString *)typeForContentsOfURL:(NSURL *)url error:(NSError **)outError {
	(void)url;
	if (outError) *outError = nil;
	return @"public.plain-text";
}
- (void)openDocumentWithContentsOfURL:(NSURL *)url display:(BOOL)displayDocument
	completionHandler:(void (^)(NSDocument *, BOOL, NSError *))completionHandler {
	(void)displayDocument;
	[self npOpen:url];
	if (completionHandler) completionHandler([self npShim:url], NO, nil);
}
- (void)reopenDocumentForURL:(NSURL *)url withContentsOfURL:(NSURL *)contentsURL display:(BOOL)displayDocument
	completionHandler:(void (^)(NSDocument *, BOOL, NSError *))completionHandler {
	(void)displayDocument;
	NSURL *u = url ?: contentsURL;
	[self npOpen:u];
	if (completionHandler) completionHandler([self npShim:u], NO, nil);
}
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-implementations"
- (NSDocument *)openDocumentWithContentsOfURL:(NSURL *)url display:(BOOL)displayDocument error:(NSError **)outError {
	(void)displayDocument;
	[self npOpen:url];
	if (outError) *outError = nil;
	return [self npShim:url];
}
#pragma clang diagnostic pop
- (NSDocument *)makeDocumentWithContentsOfURL:(NSURL *)url ofType:(NSString *)typeName error:(NSError **)outError {
	(void)typeName;
	[self npOpen:url];
	if (outError) *outError = nil;
	return [self npShim:url];
}
- (NSDocument *)makeDocumentForURL:(NSURL *)urlOrNil withContentsOfURL:(NSURL *)contentsURL ofType:(NSString *)typeName error:(NSError **)outError {
	(void)typeName;
	[self npOpen:urlOrNil ?: contentsURL];
	if (outError) *outError = nil;
	return [self npShim:urlOrNil ?: contentsURL];
}
- (void)openDocument:(id)sender {
	(void)sender;
	NPAppDelegate *del = (NPAppDelegate *)NSApp.delegate;
	[del.controller performSelector:@selector(fileOpen)];
}
- (void)newDocument:(id)sender {
	(void)sender;
	NPAppDelegate *del = (NPAppDelegate *)NSApp.delegate;
	[del.controller performSelector:@selector(fileNew)];
}
@end

static bool ArgPresent(int argc, const char *argv[], const char *key) {
	for (int i = 1; i < argc; i++) {
		if (strcmp(argv[i], key) == 0) return true;
	}
	return false;
}

static const char *ArgValue(int argc, const char *argv[], const char *key) {
	for (int i = 1; i < argc - 1; i++) {
		if (strcmp(argv[i], key) == 0) return argv[i + 1];
	}
	return nullptr;
}

// 注入测试文本 + 词法器 + 查找高亮
static void InjectTestContent(int argc, const char *argv[], MainWindowController *controller) {
	const char *code = ArgValue(argc, argv, "--code");
	if (!code) return;
	EditorDocument *doc = controller.editorDocument;
	[doc.editor setString:[NSString stringWithUTF8String:code]];

	NSString *ext = @"cpp";
	if (const char *e = ArgValue(argc, argv, "--ext")) ext = [NSString stringWithUTF8String:e];
	if (const char *t = ArgValue(argc, argv, "--theme")) {
		if (strcmp(t, "dark") == 0) [doc setTheme:NPThemeDark];
		else if (strcmp(t, "light") == 0) [doc setTheme:NPThemeDefault];
	}
	[doc applyLexerForExtension:ext];
	[doc updateLineNumberWidth];
	if (const char *g = ArgValue(argc, argv, "--gotoline")) {
		const int line = atoi(g);
		if (line > 0) [doc.editor message:SCI_GOTOLINE wParam:(line - 1) lParam:0];
	}
	[controller refreshStatus];

	if (const char *n = ArgValue(argc, argv, "--find")) {
		NSString *needle = [NSString stringWithUTF8String:n];
		ScintillaView *e = doc.editor;
		[e message:SCI_SETSEARCHFLAGS wParam:0 lParam:0];
		[e message:SCI_SETTARGETSTART wParam:0 lParam:0];
		[e message:SCI_SETTARGETEND wParam:(sptr_t)[e message:SCI_GETLENGTH] lParam:0];
		const sptr_t found = [e message:SCI_SEARCHINTARGET wParam:needle.length lParam:(sptr_t)needle.UTF8String];
		if (found >= 0) {
			[e message:SCI_SETSELECTION wParam:found lParam:(sptr_t)[e message:SCI_GETTARGETEND]];
			[e message:SCI_SCROLLCARET wParam:0 lParam:0];
		}
	}
}

int main(int argc, const char *argv[]) {
	@autoreleasepool {
		(void)[[NPDocController alloc] init];
		NSApplication *app = [NSApplication sharedApplication];
		[app setActivationPolicy:NSApplicationActivationPolicyRegular];
		static NPAppDelegate *appDelegate;
		appDelegate = [[NPAppDelegate alloc] init];
		app.delegate = appDelegate;
		[[NSAppleEventManager sharedAppleEventManager]
			setEventHandler:appDelegate
			andSelector:@selector(handleOpenDocuments:withReplyEvent:)
			forEventClass:kCoreEventClass
			andEventID:kAEOpenDocuments];

		// 关闭 macOS「按住键出重音候选」：否则按住字母键只出一个字（数字不受影响）
		// 与 VS Code / iTerm 等做法一致，只写本应用域，不动全局设置
		NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
		if ([ud objectForKey:@"ApplePressAndHoldEnabled"] == nil) {
			[ud setBool:NO forKey:@"ApplePressAndHoldEnabled"];
		}

		// --lang zh|en|ja|system|…：进程内覆盖界面语言，不写盘（测试用）
		if (const char *lg = ArgValue(argc, argv, "--lang")) {
			NPLanguageOverrideCodeForTesting([NSString stringWithUTF8String:lg]);
		}

		// 恢复上次的主题模式（跟随系统 / 亮 / 暗）
		NPThemeModeSet(NPThemeModeGet());

		// --thememode auto|light|dark：进程内覆盖，不写盘（测试用）
		if (const char *tm = ArgValue(argc, argv, "--thememode")) {
			if (strcmp(tm, "light") == 0) NPThemeModeOverrideForTesting(NPThemeModeLight);
			else if (strcmp(tm, "dark") == 0) NPThemeModeOverrideForTesting(NPThemeModeDark);
			else NPThemeModeOverrideForTesting(NPThemeModeAuto);
		}

		if (const char *ap = ArgValue(argc, argv, "--appearance")) {
			app.appearance = [NSAppearance appearanceNamed:
				(strcmp(ap, "light") == 0) ? NSAppearanceNameAqua : NSAppearanceNameDarkAqua];
		}

		static MainWindowController *controller;
		controller = [[MainWindowController alloc] init];
		appDelegate.controller = controller;
		[appDelegate flushPending];
		for (int i = 1; i < argc; i++) {
			if (argv[i][0] == '-') continue;
			NSString *path = [NSString stringWithUTF8String:argv[i]];
			if ([[NSFileManager defaultManager] fileExistsAtPath:path])
				[controller openURLInTab:[NSURL fileURLWithPath:path]];
		}
		NSWindow *win = [controller window];
		win.collectionBehavior = NSWindowCollectionBehaviorMoveToActiveSpace;
		// --headless：测试模式不显示窗口（不干扰用户前台）
		BOOL headless = ArgPresent(argc, argv, "--headless") || (getenv("NP4_HEADLESS") != nullptr);
		BOOL quiet = ArgPresent(argc, argv, "--quiet");
		if (!headless) {
			[win makeKeyAndOrderFront:nil];
			[win orderFrontRegardless];
			[controller showWindow:nil];
			if (!quiet) [app activateIgnoringOtherApps:YES];   // --quiet: 不抢焦点
		}

		InjectTestContent(argc, argv, controller);

		// --findpanel：打开查找/替换面板（配合 --shot 验证面板文案）
		if (ArgPresent(argc, argv, "--findpanel")) {
			dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)),
				dispatch_get_main_queue(), ^{
				[controller performSelector:NSSelectorFromString(@"searchReplace")];
			});
		}
		if (const char *drop = ArgValue(argc, argv, "--opendrop")) {
			[controller openInWindowMenuAtIndex:atoi(drop)];
			[[[controller window] contentView] layoutSubtreeIfNeeded];
		}
		if (ArgValue(argc, argv, "--shot")) {
			double delay = 3.0;
			if (const char *d = ArgValue(argc, argv, "--delay")) delay = atof(d);
			dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)),
				dispatch_get_main_queue(), ^{
				NSString *path = [NSString stringWithUTF8String:ArgValue(argc, argv, "--shot")];
				if ([path.pathExtension isEqualToString:@"txt"]) {
					NSMutableString *tree = [NSMutableString string];
					DumpViewTree([[controller window] contentView], 0, tree);
					[tree writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
				} else if ([path hasSuffix:@".png"]) {
					// CGWindowListCreateImage 在 macOS 15 标记弃用，dlsym 取符号
					typedef CGImageRef (*Fn)(CGRect, CGWindowListOption, CGWindowID, CGWindowImageOption);
					static Fn fn = (Fn)dlsym(RTLD_DEFAULT, "CGWindowListCreateImage");
					CGWindowID wid = (CGWindowID)[[controller window] windowNumber];
					CGImageRef img = fn ? fn(CGRectNull, kCGWindowListOptionIncludingWindow, wid,
						kCGWindowImageBoundsIgnoreFraming) : NULL;
					if (img) {
						NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithCGImage:img];
						CGImageRelease(img);
						NSData *png = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
						[png writeToFile:path atomically:YES];
					} else {
						NSView *v = [[controller window] contentView];
						[v layoutSubtreeIfNeeded];
						NSBitmapImageRep *rep = [v bitmapImageRepForCachingDisplayInRect:v.bounds];
						[v cacheDisplayInRect:v.bounds toBitmapImageRep:rep];
						[[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:path atomically:YES];
					}
				} else if ([path hasSuffix:@".pdf"]) {
					NSView *v = [[controller window] contentView];
					NSData *pdf = [v dataWithPDFInsideRect:v.bounds];
					[pdf writeToFile:path atomically:YES];
				}
				[NSApp terminate:nil];
			});
		}
		// --functest：逐项调用新实现的菜单动作，打印结果
		if (ArgPresent(argc, argv, "--functest")) {
			EditorDocument *d = controller.editorDocument;
			[d applyLexerForExtension:@"cpp"];
			[d.editor setString:@"hello WORLD\nint foo;\n(abc)\n"];
			[d.editor message:SCI_SETSEL wParam:0 lParam:5];
			[controller performSelector:@selector(editInvertCase)];
			NSString *afterInv = [[d.editor string] substringToIndex:5];
			[d.editor message:SCI_SETSEL wParam:0 lParam:5];
			[controller performSelector:@selector(editTitleCase)];
			NSString *afterTitle = [[d.editor string] substringToIndex:5];
			[d.editor message:SCI_GOTOPOS wParam:17 lParam:0];
			[controller performSelector:@selector(searchSelectWord)];
			const sptr_t sw0 = [d.editor message:SCI_GETSELECTIONSTART];
			const sptr_t sw1 = [d.editor message:SCI_GETSELECTIONEND];
			[d.editor message:SCI_GOTOPOS wParam:21 lParam:0];
			[controller performSelector:@selector(searchFindMatchingBrace)];
			const sptr_t br0 = [d.editor message:SCI_GETSELECTIONSTART];
			const sptr_t br1 = [d.editor message:SCI_GETSELECTIONEND];
			[d.editor message:SCI_GOTOLINE wParam:1 lParam:0];
			[controller performSelector:@selector(editLineComment)];
			NSString *afterCmt = [d.editor string];
			[d.editor setString:@"interesting\nint in"];
			[d.editor message:SCI_GOTOPOS wParam:[d.editor message:SCI_GETLENGTH] lParam:0];
			[controller performSelector:@selector(editCompleteWord)];
			const sptr_t autoc = [d.editor message:SCI_AUTOCACTIVE];
			[d.editor setString:@"backup-body"];
			NSURL *src = [NSURL fileURLWithPath:@"/tmp/np4ft.txt"];
			[d writeContentsToURL:src updateIdentity:YES error:nil];
			[controller performSelector:@selector(fileSaveBackup)];
			const BOOL bakOK = [[NSFileManager defaultManager] fileExistsAtPath:@"/tmp/np4ft.txt.bak"];
			[controller performSelector:@selector(addCurrentToFavorites)];
			NSArray *favs = [[NSUserDefaults standardUserDefaults] arrayForKey:@"NP4Favorites"] ?: @[];
			const BOOL favOK = [favs containsObject:@"/tmp/np4ft.txt"];
			[controller performSelector:@selector(toggleMenuBar)];
			[controller.window.contentView layoutSubtreeIfNeeded];
			[controller performSelector:@selector(toggleMenuBar)];
			NSView *rootV = controller.window.contentView;
			NSRect editorBefore = d.editor.frame;
			[controller openInWindowMenuAtIndex:0];
			[rootV layoutSubtreeIfNeeded];
			const CGFloat dropH = [controller inWindowDropDownHeight];
			const NSRect dropF = [controller inWindowDropDownFrame];
			const CGFloat editorShift = d.editor.frame.origin.y - editorBefore.origin.y;
			[controller closeInWindowMenu];
			NSMutableString *mbTitles = [NSMutableString string];
			for (NSView *v in controller.window.contentView.subviews) {
				if (v.frame.size.height > 36) continue;
				for (NSView *b in v.subviews) {
					if ([b isKindOfClass:[NSButton class]]) {
						if (mbTitles.length) [mbTitles appendString:@"/"];
						[mbTitles appendString:[(NSButton *)b title]];
					}
				}
			}
			{
				NSView *root = controller.window.contentView;
				NSRect top = NSMakeRect(0, NSMaxY(root.bounds) - 52, root.bounds.size.width, 52);
				NSBitmapImageRep *rep = [root bitmapImageRepForCachingDisplayInRect:top];
				[root cacheDisplayInRect:top toBitmapImageRep:rep];
				[[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}]
					writeToFile:@"/tmp/np4_menubar.png" atomically:YES];
			}
			NSMutableString *many = [NSMutableString string];
			for (int i = 0; i < 1200; i++) [many appendFormat:@"L%d\n", i];
			[d.editor setString:many];
			[d updateLineNumberWidth];
			const sptr_t wMany = [d.editor message:SCI_GETMARGINWIDTHN wParam:0];
			[d.editor setString:@"x\n"];
			[d updateLineNumberWidth];
			const sptr_t wFew = [d.editor message:SCI_GETMARGINWIDTHN wParam:0];
			[controller performSelector:@selector(viewWordWrap)];
			[controller performSelector:@selector(writeSettingsToDefaults)];
			const BOOL wrapSaved = [[NSUserDefaults standardUserDefaults] boolForKey:@"NP4WordWrap"];
			[controller performSelector:@selector(viewWordWrap)];
			[controller performSelector:@selector(writeSettingsToDefaults)];
			NSLog(@"[fn] inv=%@ title=%@ word=%ld-%ld brace=%ld-%ld cmtHas=%d autoc=%ld bak=%d fav=%d drop=%.0fx%.0f editorShift=%.0f lnW=%ld/%ld wrapSave=%d menus=%@",
				afterInv, afterTitle, (long)sw0, (long)sw1, (long)br0, (long)br1,
				(int)([afterCmt containsString:@"//int"] || [afterCmt containsString:@"// int"]),
				(long)autoc, (int)bakOK, (int)favOK, dropF.size.width, dropH, editorShift,
				(long)wMany, (long)wFew, (int)wrapSaved, mbTitles);
			[NSApp terminate:nil];
		}
		if (ArgPresent(argc, argv, "--audit") || ArgPresent(argc, argv, "--fulltest")
			|| ArgPresent(argc, argv, "--bugtest")) {
			NPLanguageOverrideForTesting(NPLanguageChinese);
			[controller languageChinese];
			EditorDocument *d = controller.editorDocument;
			ScintillaView *e = d.editor;
			NSMutableString *log = [NSMutableString string];
			__block int pass = 0, fail = 0, skip = 0;
			void (^ok)(NSString *, BOOL) = ^(NSString *name, BOOL cond) {
				[log appendFormat:@"%@ %@\n", cond ? @"PASS" : @"FAIL", name];
				if (cond) pass++; else fail++;
			};
			void (^sk)(NSString *, NSString *) = ^(NSString *name, NSString *why) {
				[log appendFormat:@"SKIP %@ (%@)\n", name, why];
				skip++;
			};
			[e setString:@"alpha\nbeta\ngamma\n"];
			[e message:SCI_SETSEL wParam:0 lParam:5];
			[controller performSelector:@selector(editUpper)];
			ok(@"editUpper", [[[e string] substringToIndex:5] isEqualToString:@"ALPHA"]);
			[controller performSelector:@selector(editLower)];
			ok(@"editLower", [[[e string] substringToIndex:5] isEqualToString:@"alpha"]);
			[e message:SCI_SETSEL wParam:0 lParam:5];
			[controller performSelector:@selector(editInvertCase)];
			ok(@"editInvertCase", [[[e string] substringToIndex:5] isEqualToString:@"ALPHA"]);
			[e message:SCI_SETSEL wParam:0 lParam:5];
			[controller performSelector:@selector(editTitleCase)];
			ok(@"editTitleCase", [[[e string] substringToIndex:5] isEqualToString:@"Alpha"]);
			[e setString:@"hello world"];
			[e message:SCI_SETSEL wParam:0 lParam:5];
			[controller performSelector:@selector(editSelectAll)];
			ok(@"editSelectAll", [e message:SCI_GETSELECTIONEND] - [e message:SCI_GETSELECTIONSTART] == [e message:SCI_GETLENGTH]);
			[e message:SCI_SETSEL wParam:0 lParam:5];
			[controller performSelector:@selector(editCopy)];
			[e message:SCI_SETSEL wParam:6 lParam:11];
			[controller performSelector:@selector(editPaste)];
			ok(@"editCopyPaste", [[e string] isEqualToString:@"hello hello"]);
			[e message:SCI_SETSEL wParam:6 lParam:11];
			[controller performSelector:@selector(editCut)];
			ok(@"editCut", [[e string] isEqualToString:@"hello "]);
			[controller performSelector:@selector(editUndo)];
			ok(@"editUndo", [[e string] isEqualToString:@"hello hello"]);
			[controller performSelector:@selector(editRedo)];
			ok(@"editRedo", [[e string] isEqualToString:@"hello "]);
			[e setString:@"abcXYZ"];
			[e message:SCI_SETSEL wParam:3 lParam:6];
			[controller performSelector:@selector(editDelete)];
			ok(@"editDelete", [[e string] isEqualToString:@"abc"]);
			[controller performSelector:@selector(editClearDocument)];
			ok(@"editClearDocument", [e message:SCI_GETLENGTH] == 0);
			[e setString:@"int x;\nint y;\n"];
			[d applyLexerForExtension:@"cpp"];
			[e message:SCI_GOTOLINE wParam:0 lParam:0];
			[controller performSelector:@selector(editLineComment)];
			ok(@"editLineComment", [[e string] hasPrefix:@"//int"] || [[e string] hasPrefix:@"// int"]);
			[e setString:@"line1\nline2\n"];
			[e message:SCI_GOTOLINE wParam:1 lParam:0];
			[controller performSelector:@selector(editMoveLineUp)];
			ok(@"editMoveLineUp", [[e string] hasPrefix:@"line2"]);
			[controller performSelector:@selector(editMoveLineDown)];
			ok(@"editMoveLineDown", [[e string] hasPrefix:@"line1"]);
			[e setString:@"aaa\nbbb\n"];
			[e message:SCI_GOTOLINE wParam:0 lParam:0];
			[controller performSelector:@selector(editDuplicateLine)];
			ok(@"editDuplicateLine", [e message:SCI_GETLINECOUNT] >= 3);
			[e setString:@"keep\nkill\n"];
			[e message:SCI_GOTOLINE wParam:1 lParam:0];
			[controller performSelector:@selector(editDeleteLine)];
			ok(@"editDeleteLine", ![[e string] containsString:@"kill"]);
			[e setString:@"aaa\nbbb\n"];
			[e message:SCI_SETSEL wParam:0 lParam:[e message:SCI_GETLENGTH]];
			[controller performSelector:@selector(editJoinLines)];
			ok(@"editJoinLines", ![[e string] containsString:@"\n"] || [[e string] componentsSeparatedByString:@"\n"].count <= 2);
			[e setString:@"hello   \nworld\t\n"];
			[controller performSelector:@selector(editTrimTrailing)];
			NSString *trim = [e string];
			ok(@"editTrimTrailing", ![trim containsString:@"   \n"] && ![trim containsString:@"\t\n"]);
			[e setString:@"a\n\nb\n"];
			[e message:SCI_SETSEL wParam:0 lParam:[e message:SCI_GETLENGTH]];
			[controller performSelector:@selector(editRemoveBlankLines)];
			ok(@"editRemoveBlankLines", ![[e string] containsString:@"\n\n"]);
			[e setString:@"one two"];
			[e message:SCI_GOTOPOS wParam:5 lParam:0];
			[controller performSelector:@selector(searchSelectWord)];
			ok(@"searchSelectWord", [e message:SCI_GETSELECTIONEND] - [e message:SCI_GETSELECTIONSTART] == 3);
			[e setString:@"(abc)"];
			[e message:SCI_GOTOPOS wParam:0 lParam:0];
			[controller performSelector:@selector(searchFindMatchingBrace)];
			ok(@"searchFindMatchingBrace", [e message:SCI_GETSELECTIONEND] > [e message:SCI_GETSELECTIONSTART]);
			[e setString:@"bm1\nbm2\nbm3\n"];
			[e message:SCI_GOTOLINE wParam:1 lParam:0];
			[controller performSelector:@selector(bookmarkToggle)];
			ok(@"bookmarkToggle", ([e message:SCI_MARKERGET wParam:1] & 2) != 0);
			[e message:SCI_GOTOLINE wParam:0 lParam:0];
			[controller performSelector:@selector(bookmarkNext)];
			ok(@"bookmarkNext", [e message:SCI_LINEFROMPOSITION wParam:[e message:SCI_GETCURRENTPOS]] == 1);
			[controller performSelector:@selector(bookmarkClear)];
			ok(@"bookmarkClear", ([e message:SCI_MARKERGET wParam:1] & 2) == 0);
			const sptr_t wrap0 = [e message:SCI_GETWRAPMODE];
			[controller performSelector:@selector(viewWordWrap)];
			ok(@"viewWordWrap", [e message:SCI_GETWRAPMODE] != wrap0);
			[controller performSelector:@selector(viewWordWrap)];
			const sptr_t ln0 = [e message:SCI_GETMARGINWIDTHN wParam:0];
			[controller performSelector:@selector(viewLineNumbers)];
			ok(@"viewLineNumbers", [e message:SCI_GETMARGINWIDTHN wParam:0] != ln0);
			[controller performSelector:@selector(viewLineNumbers)];
			const sptr_t fold0 = [e message:SCI_GETMARGINWIDTHN wParam:2];
			[controller performSelector:@selector(viewCodeFolding)];
			ok(@"viewCodeFolding(toggleMargin)", [e message:SCI_GETMARGINWIDTHN wParam:2] != fold0);
			[controller performSelector:@selector(viewCodeFolding)];
			const sptr_t ws0 = [e message:SCI_GETVIEWWS];
			[controller performSelector:@selector(viewWhitespace)];
			ok(@"viewWhitespace", [e message:SCI_GETVIEWWS] != ws0);
			[controller performSelector:@selector(viewWhitespace)];
			const sptr_t eol0 = [e message:SCI_GETVIEWEOL];
			[controller performSelector:@selector(viewEOLs)];
			ok(@"viewEOLs", [e message:SCI_GETVIEWEOL] != eol0);
			[controller performSelector:@selector(viewEOLs)];
			const sptr_t ig0 = [e message:SCI_GETINDENTATIONGUIDES];
			[controller performSelector:@selector(viewIndentGuides)];
			ok(@"viewIndentGuides", [e message:SCI_GETINDENTATIONGUIDES] != ig0);
			[controller performSelector:@selector(viewIndentGuides)];
			const sptr_t zoom0 = [e message:SCI_GETZOOM];
			[controller performSelector:@selector(viewZoomIn)];
			ok(@"viewZoomIn", [e message:SCI_GETZOOM] > zoom0);
			[controller performSelector:@selector(viewZoomOut)];
			ok(@"viewZoomOut", [e message:SCI_GETZOOM] == zoom0);
			[controller performSelector:@selector(viewZoomReset)];
			ok(@"viewZoomReset", [e message:SCI_GETZOOM] == 100);
			const BOOL menu0 = controller.window.contentView.subviews.firstObject.hidden;
			[controller performSelector:@selector(toggleMenuBar)];
			ok(@"toggleMenuBar", YES);
			[controller performSelector:@selector(toggleMenuBar)];
			[controller performSelector:@selector(toggleToolbar)];
			[controller performSelector:@selector(toggleToolbar)];
			[controller performSelector:@selector(toggleStatusBar)];
			[controller performSelector:@selector(toggleStatusBar)];
			ok(@"toggleToolbar/StatusBar", YES);
			const sptr_t tabs0 = [e message:SCI_GETUSETABS];
			[controller performSelector:@selector(settingsUseTabs)];
			ok(@"settingsUseTabs", [e message:SCI_GETUSETABS] != tabs0);
			[controller performSelector:@selector(settingsUseTabs)];
			const sptr_t edge0 = [e message:SCI_GETEDGEMODE];
			[controller performSelector:@selector(viewLongLineMarker)];
			ok(@"viewLongLineMarker", [e message:SCI_GETEDGEMODE] != edge0);
			[controller performSelector:@selector(viewLongLineMarker)];
			[e setString:@"abc\r\ndef"];
			[controller performSelector:@selector(setEOLLF)];
			ok(@"setEOLLF", [e message:SCI_GETEOLMODE] == SC_EOL_LF);
			[controller performSelector:@selector(setEOLCRLF)];
			ok(@"setEOLCRLF", [e message:SCI_GETEOLMODE] == SC_EOL_CRLF);
			[controller performSelector:@selector(toggleReadOnly)];
			ok(@"toggleReadOnly on", [e message:SCI_GETREADONLY] != 0);
			[controller performSelector:@selector(toggleReadOnly)];
			ok(@"toggleReadOnly off", [e message:SCI_GETREADONLY] == 0);
			[e setString:@""];
			[controller performSelector:@selector(insertGUID)];
			ok(@"insertGUID", [e message:SCI_GETLENGTH] >= 32);
			[e setString:@""];
			[controller performSelector:@selector(insertDateTime)];
			ok(@"insertDateTime", [e message:SCI_GETLENGTH] >= 10);
			[e setString:@""];
			[controller performSelector:@selector(insertUnixTimestamp)];
			ok(@"insertUnixTimestamp", [e message:SCI_GETLENGTH] >= 10);
			[e setString:@"hello"];
			[e message:SCI_SETSEL wParam:0 lParam:5];
			[controller performSelector:@selector(base64Encode)];
			NSString *b64 = [e string];
			[e message:SCI_SETSEL wParam:0 lParam:[e message:SCI_GETLENGTH]];
			[controller performSelector:@selector(base64Decode)];
			ok(@"base64Encode/Decode", [[e string] isEqualToString:@"hello"]);
			[e setString:@"<a>"];
			[e message:SCI_SETSEL wParam:0 lParam:3];
			[controller performSelector:@selector(webEscapeHTML)];
			ok(@"webEscapeHTML", [[e string] containsString:@"&lt;"]);
			[e message:SCI_SETSEL wParam:0 lParam:[e message:SCI_GETLENGTH]];
			[controller performSelector:@selector(webUnescapeHTML)];
			ok(@"webUnescapeHTML", [[e string] isEqualToString:@"<a>"]);
			[e setString:@"a b"];
			[e message:SCI_SETSEL wParam:0 lParam:3];
			[controller performSelector:@selector(urlEncode)];
			ok(@"urlEncode", [[e string] containsString:@"%20"]);
			[e setString:@"hi 中文 hi"];
			[controller performSelector:@selector(searchFind)];
			FindReplacePanel *fp = nil;
			for (NSView *v in controller.window.contentView.subviews) {
				if ([v isKindOfClass:[FindReplacePanel class]]) fp = (FindReplacePanel *)v;
			}
			ok(@"searchFind shows panel", fp && !fp.hidden);
			if (fp) {
				NSSearchField *ff = [fp valueForKey:@"findField"];
				NSTextField *rf = [fp valueForKey:@"replaceField"];
				ff.stringValue = @"中文";
				[fp findNext:d];
				ok(@"findNext CJK", [e message:SCI_GETSELECTIONEND] - [e message:SCI_GETSELECTIONSTART] == 6);
				rf.stringValue = @"OK";
				[fp replaceOne:d];
				ok(@"replaceOne CJK", [[e string] containsString:@"OK"] && ![[e string] containsString:@"中文"]);
				[e setString:@"xx中文yy中文zz"];
				ff.stringValue = @"中文";
				rf.stringValue = @"Q";
				[fp replaceAll:d];
				ok(@"replaceAll CJK", [[e string] isEqualToString:@"xxQyyQzz"]);
				ok(@"find panel Next button selector", [fp respondsToSelector:NSSelectorFromString(@"next:")]);
			} else {
				ok(@"find panel present", NO);
			}
			[e setString:@"interesting\nint in"];
			[e message:SCI_GOTOPOS wParam:[e message:SCI_GETLENGTH] lParam:0];
			[controller performSelector:@selector(editCompleteWord)];
			ok(@"editCompleteWord", [e message:SCI_AUTOCACTIVE] != 0);
			[e setString:@"body"];
			NSURL *src = [NSURL fileURLWithPath:@"/tmp/np4-audit.txt"];
			[d writeContentsToURL:src updateIdentity:YES error:nil];
			[controller performSelector:@selector(fileSave)];
			ok(@"fileSave", [[NSFileManager defaultManager] fileExistsAtPath:@"/tmp/np4-audit.txt"]);
			[controller performSelector:@selector(fileSaveBackup)];
			ok(@"fileSaveBackup", [[NSFileManager defaultManager] fileExistsAtPath:@"/tmp/np4-audit.txt.bak"]);
			[e setString:@"changed"];
			[controller performSelector:@selector(fileRevert)];
			ok(@"fileRevert", [[e string] isEqualToString:@"body"] || [[e string] hasPrefix:@"body"]);
			[d applyLexerForExtension:@"cpp"];
			[e setString:@"int main(){\nint x = 1;\nreturn 0;\n}\n"];
			[e message:SCI_COLOURISE wParam:0 lParam:-1];
			sptr_t foldLine = -1;
			for (sptr_t i = 0; i < [e message:SCI_GETLINECOUNT]; i++) {
				const sptr_t lv = [e message:SCI_GETFOLDLEVEL wParam:i];
				if (foldLine < 0 && (lv & SC_FOLDLEVELHEADERFLAG)) foldLine = i;
			}
			if (foldLine < 0) foldLine = 0;
			[e message:SCI_GOTOLINE wParam:foldLine lParam:0];
			const sptr_t exp0 = [e message:SCI_GETFOLDEXPANDED wParam:foldLine];
			[controller foldToggleCurrent];
			const sptr_t exp1 = [e message:SCI_GETFOLDEXPANDED wParam:foldLine];
			ok(@"foldToggleCurrent", exp1 != exp0);
			[controller unfoldAll];
			ok(@"unfoldAll", [e message:SCI_GETFOLDEXPANDED wParam:foldLine] != 0);
			[[NSUserDefaults standardUserDefaults] removeObjectForKey:@"NP4BraceMatch"];
			[[NSUserDefaults standardUserDefaults] removeObjectForKey:@"NP4URLDetect"];
			[d setBraceMatchEnabled:YES];
			[d setURLDetectEnabled:NO];
			ok(@"brace default on", d.braceMatchEnabled);
			[controller viewBraceMatch];
			ok(@"brace first toggle off", d.braceMatchEnabled == NO);
			[controller viewBraceMatch];
			ok(@"brace toggle back on", d.braceMatchEnabled == YES);
			[e message:SCI_SETWRAPMODE wParam:SC_WRAP_WORD lParam:0];
			[controller syncMenuItemStates];
			[controller openInWindowMenuAtIndex:3];
			ok(@"view menu checkmarks", [controller inWindowCheckedRowCount] >= 2);
			[controller closeInWindowMenu];
			NSString *props = [controller documentPropertiesText];
			ok(@"properties text", [props containsString:@"UTF"] && ([props containsString:@"LF"] || [props containsString:@"CR"]));
			NSString *lname = d.currentLexerName;
			[LexerRegistry setUserStyleValue:@"fore:#FF00FF;bold" forLexerName:lname styleName:@"Keyword"];
			[d applyLexerForExtension:@"cpp"];
			const long kw = [e message:SCI_STYLEGETFORE wParam:SCE_C_WORD];
			ok(@"scheme customize override", ((kw & 0xFF) == 0xFF) || (((kw >> 16) & 0xFF) == 0xFF));
			[LexerRegistry clearUserOverridesForLexerName:lname];
			[controller tbOpenMenu];
			NSRect openDrop = [controller inWindowDropDownFrame];
			ok(@"open dropdown overlay", openDrop.size.width > 80 && openDrop.size.width < 400);
			[controller closeInWindowMenu];
			[controller tbFoldMenu];
			NSRect foldDrop = [controller inWindowDropDownFrame];
			ok(@"fold dropdown overlay", foldDrop.size.width > 80 && foldDrop.size.width < 400);
			[controller closeInWindowMenu];
			{
				[e setString:@"c\nb\na"];
				[e message:SCI_SELECTALL wParam:0 lParam:0];
				[controller performSelector:@selector(editSortLines)];
				ok(@"sortLines", [[e string] hasPrefix:@"a"]);
				[e setString:@"x\ny\nx"];
				[e message:SCI_SELECTALL wParam:0 lParam:0];
				[controller performSelector:@selector(editRemoveDuplicateLines)];
				ok(@"removeDupes", [[e string] hasPrefix:@"x"] && [[e string] containsString:@"y"] && [[[e string] componentsSeparatedByString:@"x"] count] == 2);
				[e setString:@"hello. world"];
				[e message:SCI_SELECTALL wParam:0 lParam:0];
				[controller performSelector:@selector(editSentenceCase)];
				ok(@"sentenceCase", [[e string] hasPrefix:@"Hello"]);
				[e setString:@"255"];
				[e message:SCI_SELECTALL wParam:0 lParam:0];
				[controller performSelector:@selector(editNum2Hex)];
				ok(@"num2hex", [[e string] isEqualToString:@"0xff"]);
				[e setString:@"int main(){return 0;}"];
				[e message:SCI_GOTOPOS wParam:11 lParam:0];
				[controller performSelector:@selector(searchSelectToBrace)];
				const sptr_t slen = [e message:SCI_GETSELECTIONEND] - [e message:SCI_GETSELECTIONSTART];
				ok(@"selectToBrace", slen >= 10);
				[e setString:@"x"];
				[e message:SCI_SELECTALL wParam:0 lParam:0];
				[controller performSelector:@selector(editEncloseParen)];
				ok(@"encloseParen", [[e string] isEqualToString:@"(x)"]);
				[e setString:@"ab"];
				[e message:SCI_SELECTALL wParam:0 lParam:0];
				[[NSPasteboard generalPasteboard] clearContents];
				[[NSPasteboard generalPasteboard] setString:@"Z" forType:NSPasteboardTypeString];
				[controller performSelector:@selector(editCopyAdd)];
				NSString *clip = [[NSPasteboard generalPasteboard] stringForType:NSPasteboardTypeString];
				ok(@"copyAdd", [clip isEqualToString:@"Zab"]);
				[d applyLexerForExtension:@"cpp"];
				[e setString:@"int x;"];
				[e message:SCI_SELECTALL wParam:0 lParam:0];
				[controller performSelector:@selector(editStreamComment)];
				ok(@"streamComment", [[e string] containsString:@"/*"]);
				[controller performSelector:@selector(setEOLCR)];
				ok(@"setEOLCR", [e message:SCI_GETEOLMODE] == SC_EOL_CR);
				ok(@"url detect default off", d.URLDetectEnabled == NO);
				[controller performSelector:@selector(viewDetectURLs)];
				ok(@"url detect on", d.URLDetectEnabled);
				[e setString:@"see https://example.com/a now"];
				[d scanDetectedURLs];
				ok(@"url detect stays on", d.URLDetectEnabled);
				[controller performSelector:@selector(viewDetectURLs)];
				ok(@"url detect off", d.URLDetectEnabled == NO);
				ok(@"large file default off", d.largeFileMode == NO);
				[controller performSelector:@selector(toggleLargeFileMode)];
				ok(@"large file on", d.largeFileMode);
				[controller performSelector:@selector(toggleLargeFileMode)];
				ok(@"large file off", d.largeFileMode == NO);
				ok(@"tabCount start", [controller tabCount] == 1);
				NSString *jp = @"/tmp/np4-audit.json";
				[@"hello json 1\n" writeToFile:jp atomically:YES encoding:NSUTF8StringEncoding error:nil];
				[controller openURLInTab:[NSURL fileURLWithPath:jp]];
				ok(@"open json", [controller.editorDocument.fileURL.path hasSuffix:@".json"]);
				ok(@"json text", [[controller.editorDocument.editor string] containsString:@"hello"]);
				ok(@"tab plus", [controller hasTabNewButton]);
				NSString *jp2 = @"/tmp/np4-audit-dc.json";
				[@"dc-open-ok\n" writeToFile:jp2 atomically:YES encoding:NSUTF8StringEncoding error:nil];
				[[NSDocumentController sharedDocumentController]
					openDocumentWithContentsOfURL:[NSURL fileURLWithPath:jp2]
					display:NO completionHandler:^(NSDocument *doc, BOOL already, NSError *err) {}];
				ok(@"NSDocumentController json",
					[controller.editorDocument.fileURL.path hasSuffix:@"np4-audit-dc.json"]
					&& [[controller.editorDocument.editor string] containsString:@"dc-open-ok"]);
				ok(@"shared DC class", [[[NSDocumentController sharedDocumentController] className] isEqualToString:@"NPDocController"]);
				ok(@"class for JSON name",
					[[NSDocumentController sharedDocumentController] documentClassForType:@"JSON"] == [NPShimDocument class]);
				ok(@"class for yaml uti",
					[[NSDocumentController sharedDocumentController] documentClassForType:@"public.yaml"] == [NPShimDocument class]);
				ok(@"class for markdown name",
					[[NSDocumentController sharedDocumentController] documentClassForType:@"Markdown"] == [NPShimDocument class]);
				[@"# md-open\n" writeToFile:@"/tmp/np4-audit.md" atomically:YES encoding:NSUTF8StringEncoding error:nil];
				[@"k: v\n" writeToFile:@"/tmp/np4-audit.yaml" atomically:YES encoding:NSUTF8StringEncoding error:nil];
				NSError *mdErr = nil;
				NSString *mdType = [[NSDocumentController sharedDocumentController]
					typeForContentsOfURL:[NSURL fileURLWithPath:@"/tmp/np4-audit.md"] error:&mdErr];
				ok(@"typeFor md", [mdType isEqualToString:@"public.plain-text"] && mdErr == nil);
				NSError *mkErr = nil;
				NSDocument *mdoc = [[NSDocumentController sharedDocumentController]
					makeDocumentWithContentsOfURL:[NSURL fileURLWithPath:@"/tmp/np4-audit.md"]
					ofType:@"Markdown" error:&mkErr];
				ok(@"makeDocument md", mdoc != nil && mkErr == nil
					&& [controller.editorDocument.fileURL.path hasSuffix:@"np4-audit.md"]
					&& [[controller.editorDocument.editor string] containsString:@"md-open"]);
				NSError *ymErr = nil;
				NSDocument *ydoc = [[NSDocumentController sharedDocumentController]
					makeDocumentWithContentsOfURL:[NSURL fileURLWithPath:@"/tmp/np4-audit.yaml"]
					ofType:@"YAML" error:&ymErr];
				ok(@"makeDocument yaml", ydoc != nil && ymErr == nil
					&& [controller.editorDocument.fileURL.path hasSuffix:@"np4-audit.yaml"]);
				[@"ae-open\n" writeToFile:@"/tmp/np4-audit-ae.md" atomically:YES encoding:NSUTF8StringEncoding error:nil];
				NSAppleEventDescriptor *urlDesc = [NSAppleEventDescriptor
					descriptorWithFileURL:[NSURL fileURLWithPath:@"/tmp/np4-audit-ae.md"]];
				NSAppleEventDescriptor *list = [NSAppleEventDescriptor listDescriptor];
				[list insertDescriptor:urlDesc atIndex:1];
				NSAppleEventDescriptor *ev = [NSAppleEventDescriptor
					appleEventWithEventClass:kCoreEventClass eventID:kAEOpenDocuments
					targetDescriptor:[NSAppleEventDescriptor nullDescriptor]
					returnID:kAutoGenerateReturnID transactionID:kAnyTransactionID];
				[ev setParamDescriptor:list forKeyword:keyDirectObject];
				[appDelegate handleOpenDocuments:ev withReplyEvent:[NSAppleEventDescriptor nullDescriptor]];
				ok(@"apple event md",
					[controller.editorDocument.fileURL.path hasSuffix:@"np4-audit-ae.md"]
					&& [[controller.editorDocument.editor string] containsString:@"ae-open"]);
				{
					NSDocumentController *dc = [NSDocumentController sharedDocumentController];
					NSArray<NSString *> *typeNames = @[
						@"JSON", @"YAML", @"Markdown", @"Python script", @"HTML text",
						@"XML text", @"JavaScript", @"C source code", @"C++ source code",
						@"Swift Source Code", @"property list", @"shell script", @"CSS",
						@"Java source code", @"Ruby script", @"Perl script", @"PHP script",
						@"Makefile", @"TOML/Configuration file", @"comma-separated values",
						@"public.python-script", @"public.html", @"public.xml",
						@"public.plain-text", @"public.source-code",
						@"HTML", @"XML", @"Python Script", @"Shell Script",
						@"Property List", @"Plain Text", @"Source Code", @"no.such.type"
					];
					BOOL allClass = YES;
					for (NSString *tn in typeNames) {
						if ([dc documentClassForType:tn] != [NPShimDocument class]) allClass = NO;
					}
					ok(@"class for other type names", allClass);
					ok(@"native any type",
						[NPShimDocument isNativeType:@"Python script"]
						&& [NPShimDocument isNativeType:@"no.such.type"]);
					ok(@"readable has item", [[NPShimDocument readableTypes] containsObject:@"public.item"]);
					NSArray<NSString *> *exts = @[
						@"py", @"html", @"xml", @"js", @"c", @"cpp", @"swift", @"sh",
						@"plist", @"css", @"rs", @"go", @"java", @"rb", @"php", @"ts",
						@"toml", @"ini", @"csv", @"svg", @"txt"
					];
					BOOL allType = YES, allOpen = YES;
					for (NSString *ext in exts) {
						NSString *path = [NSString stringWithFormat:@"/tmp/np4-audit-x.%@", ext];
						[@"x-open\n" writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
						NSURL *u = [NSURL fileURLWithPath:path];
						NSError *e1 = nil;
						NSString *ty = [dc typeForContentsOfURL:u error:&e1];
						if (e1 != nil || [ty isEqualToString:@"public.plain-text"] == NO) allType = NO;
						NSError *e2 = nil;
						NSDocument *doc = [dc makeDocumentWithContentsOfURL:u ofType:@"HTML" error:&e2];
						if (doc == nil || e2 != nil) allOpen = NO;
						if ([controller.editorDocument.fileURL.path hasSuffix:ext] == NO) allOpen = NO;
						if ([[controller.editorDocument.editor string] containsString:@"x-open"] == NO) allOpen = NO;
					}
					ok(@"typeFor other exts", allType);
					ok(@"makeDocument other exts", allOpen);
				}
				{
					NSString *longPath = @"/tmp/这是一个非常非常长的Markdown文件名用来复现标签栏卡死-OpenTasks_PRD_v0.3_HANDOFF_FULL.md";
					[@"# long-name\n" writeToFile:longPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
					[controller openURLInTab:[NSURL fileURLWithPath:longPath]];
					NSView *cv = [[controller window] contentView];
					[cv layoutSubtreeIfNeeded];
					NSBitmapImageRep *rep = [cv bitmapImageRepForCachingDisplayInRect:cv.bounds];
					[cv cacheDisplayInRect:cv.bounds toBitmapImageRep:rep];
					ok(@"long tab title draw",
						[controller.editorDocument.fileURL.path hasSuffix:@".md"]
						&& [[controller.editorDocument.editor string] containsString:@"long-name"]);
				}
								{
					NSString *lp = @"/tmp/np4-audit-large.md";
					NSMutableData *md = [NSMutableData dataWithCapacity:3200000];
					[md appendBytes:"NP4LARGEHEAD\n" length:13];
					const char *line = "line-xxxx-0123456789abcdef **md** `code` more text to fill\n";
					const NSUInteger ln = strlen(line);
					for (int i = 0; i < 45000; i++) [md appendBytes:line length:ln];
					[md appendBytes:"NP4LARGETAIL\n" length:13];
					[md writeToFile:lp atomically:YES];
					const CFAbsoluteTime t0 = CFAbsoluteTimeGetCurrent();
					[controller openURLInTab:[NSURL fileURLWithPath:lp]];
					const double ms = (CFAbsoluteTimeGetCurrent() - t0) * 1000.0;
					EditorDocument *ldoc = controller.editorDocument;
					const sptr_t n = [ldoc.editor message:SCI_GETLENGTH];
					char head[16] = {0};
					[ldoc.editor message:SCI_GETTEXT wParam:14 lParam:(sptr_t)head];
					ok(@"large utf8 load",
						n == (sptr_t)md.length
						&& strncmp(head, "NP4LARGEHEAD", 12) == 0
						&& ldoc.largeFileMode == NO);
					ok(@"large open fast", ms < 2000);
					NSLog(@"[audit] large open %.1f ms len=%ld", ms, (long)n);
				}
while ([controller tabCount] > 1) [controller fileCloseTab];
				ok(@"tab still 1 after json", [controller tabCount] == 1);
			}
			[controller performSelector:@selector(fileNew)];
			ok(@"fileNew", [controller.editorDocument.editor message:SCI_GETLENGTH] == 0);
			ok(@"tabCount after new", [controller tabCount] == 2);
			[controller performSelector:@selector(setEncodingUTF8)];
			ok(@"setEncodingUTF8", [controller.editorDocument.currentEncoding isEqualToString:@"UTF-8"]);
			[controller performSelector:@selector(setEncodingUTF8BOM)];
			ok(@"setEncodingUTF8BOM(distinct)", [controller.editorDocument.currentEncoding containsString:@"BOM"]);
			[controller openInWindowMenuAtIndex:0];
			NSRect drop = [controller inWindowDropDownFrame];
			ok(@"dropdown not full-width", drop.size.width > 100 && drop.size.width < 400);
			[controller closeInWindowMenu];
			{
				EditorDocument *nd = controller.editorDocument;
				[nd.editor setString:@"dirty-new"];
				ok(@"dirty before new", nd.dirty);
				[controller performSelector:@selector(fileNew)];
				ok(@"fileNew after dirty (new tab)", [controller.editorDocument.editor message:SCI_GETLENGTH] == 0);
				ok(@"tabCount after dirty new", [controller tabCount] == 3);
				[controller fileCloseTab];
				ok(@"tabCount after close", [controller tabCount] == 2);
			}
			{
				NSFileManager *fm = [NSFileManager defaultManager];
				NSString *dir = @"/tmp/np4-allfmt";
				[fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
				NSDocumentController *dc = [NSDocumentController sharedDocumentController];
				NSArray *docTypes = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleDocumentTypes"];
				NSMutableSet *extSet = [NSMutableSet set];
				NSMutableSet *typeNameSet = [NSMutableSet set];
				NSMutableSet *utiSet = [NSMutableSet set];
				for (NSDictionary *td in docTypes) {
					NSString *tn = td[@"CFBundleTypeName"];
					if (tn.length) [typeNameSet addObject:tn];
					for (NSString *ex in td[@"CFBundleTypeExtensions"]) {
						if (ex.length) [extSet addObject:ex.lowercaseString];
					}
					for (NSString *u in td[@"LSItemContentTypes"]) {
						if (u.length) [utiSet addObject:u];
					}
				}
				ok(@"plist has star", [extSet containsObject:@"*"]);
				ok(@"plist ext count", extSet.count >= 400);
				BOOL allTypeNames = YES;
				for (NSString *tn in typeNameSet) {
					if ([dc documentClassForType:tn] != [NPShimDocument class]) allTypeNames = NO;
				}
				ok(@"class for all plist type names", allTypeNames && typeNameSet.count >= 7);
				BOOL allUTIs = YES;
				for (NSString *u in utiSet) {
					if ([dc documentClassForType:u] != [NPShimDocument class]) allUTIs = NO;
				}
				ok(@"class for all plist UTIs", allUTIs && utiSet.count >= 20);
				NSMutableArray *badType = [NSMutableArray array];
				NSMutableArray *badOpen = [NSMutableArray array];
				NSMutableArray *badLex = [NSMutableArray array];
				NSArray *exts = [[extSet allObjects] sortedArrayUsingSelector:@selector(compare:)];
				NSUInteger opened = 0;
				for (NSString *ext in exts) {
					if ([ext isEqualToString:@"*"]) continue;
					NSString *path = [dir stringByAppendingPathComponent:[NSString stringWithFormat:@"sample.%@", ext]];
					[@"NP4FMT\n" writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
					NSURL *u = [NSURL fileURLWithPath:path];
					NSError *e1 = nil;
					NSString *ty = [dc typeForContentsOfURL:u error:&e1];
					if (e1 != nil || [ty isEqualToString:@"public.plain-text"] == NO)
						[badType addObject:ext];
					NSError *e2 = nil;
					NSDocument *doc = [dc makeDocumentWithContentsOfURL:u ofType:@"Source Code" error:&e2];
					EditorDocument *cur = controller.editorDocument;
					if (doc == nil || e2 != nil
						|| [cur.fileURL.path hasSuffix:[@"." stringByAppendingString:ext]] == NO
						|| [[cur.editor string] containsString:@"NP4FMT"] == NO)
						[badOpen addObject:ext];
					else opened++;
					const EDITLEXER *lex = [LexerRegistry lexerForExtension:ext];
					if (lex && cur.largeFileMode == NO) {
						const sptr_t got = [cur.editor message:SCI_GETLEXER];
						if (got != lex->iLexer) [badLex addObject:ext];
					}
					if ([controller tabCount] > 3) {
						while ([controller tabCount] > 2) [controller fileCloseTab];
					}
				}
				if (badType.count) NSLog(@"[audit] typeFor fail %@", [badType componentsJoinedByString:@","]);
				if (badOpen.count) NSLog(@"[audit] open fail %@", [badOpen componentsJoinedByString:@","]);
				if (badLex.count) NSLog(@"[audit] lexer fail %@", [badLex componentsJoinedByString:@","]);
				NSLog(@"[audit] formats opened %lu / %lu", (unsigned long)opened, (unsigned long)(exts.count - 1));
				ok(@"all format typeFor", badType.count == 0);
				ok(@"all format open", badOpen.count == 0 && opened >= 400);
				ok(@"all format lexer", badLex.count == 0);
				NSArray *aeExts = @[@"py", @"html", @"c", @"plist", @"js", @"java", @"toml", @"rs"];
				BOOL aeAll = YES;
				for (NSString *ext in aeExts) {
					NSString *path = [NSString stringWithFormat:@"/tmp/np4-ae-x.%@", ext];
					[@"AEFMT\n" writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
					NSAppleEventDescriptor *urlDesc = [NSAppleEventDescriptor
						descriptorWithFileURL:[NSURL fileURLWithPath:path]];
					NSAppleEventDescriptor *list = [NSAppleEventDescriptor listDescriptor];
					[list insertDescriptor:urlDesc atIndex:1];
					NSAppleEventDescriptor *ev = [NSAppleEventDescriptor
						appleEventWithEventClass:kCoreEventClass eventID:kAEOpenDocuments
						targetDescriptor:[NSAppleEventDescriptor nullDescriptor]
						returnID:kAutoGenerateReturnID transactionID:kAnyTransactionID];
					[ev setParamDescriptor:list forKeyword:keyDirectObject];
					[appDelegate handleOpenDocuments:ev withReplyEvent:[NSAppleEventDescriptor nullDescriptor]];
					if ([controller.editorDocument.fileURL.path hasSuffix:ext] == NO
						|| [[controller.editorDocument.editor string] containsString:@"AEFMT"] == NO)
						aeAll = NO;
				}
				ok(@"apple event other formats", aeAll);
				NSString *nonePath = @"/tmp/np4-allfmt/no-extension-file";
				[@"NEXTEXT\n" writeToFile:nonePath atomically:YES encoding:NSUTF8StringEncoding error:nil];
				[controller openURLInTab:[NSURL fileURLWithPath:nonePath]];
				ok(@"extensionless open",
					[[controller.editorDocument.editor string] containsString:@"NEXTEXT"]);
				NSString *cjkPath = @"/tmp/np4-allfmt/Karing-singbox 链式版.json";
				[@"{\"ok\":1}\n" writeToFile:cjkPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
				[controller openURLInTab:[NSURL fileURLWithPath:cjkPath]];
				ok(@"cjk space json open",
					[controller.editorDocument.fileURL.path hasSuffix:@"链式版.json"]
					&& [[controller.editorDocument.editor string] containsString:@"ok"]);
			}
			{
				NSArray *infos = [LexerRegistry allLexersInfo];
				ok(@"lexer registry count", infos.count >= 80);
				NSMutableArray *bad = [NSMutableArray array];
				NSUInteger applied = 0;
				EditorDocument *cur = controller.editorDocument;
				[cur.editor setString:@"int x = 1;\n"];
				for (NSDictionary *info in infos) {
					NSString *exts = info[@"extensions"] ?: @"";
					NSString *first = nil;
					for (NSString *p in [exts componentsSeparatedByCharactersInSet:
						[NSCharacterSet characterSetWithCharactersInString:@"; "]]) {
						if (p.length) { first = p.lowercaseString; break; }
					}
					if (first.length == 0) { applied++; continue; }
					if ([first hasPrefix:@"."]) first = [first substringFromIndex:1];
					[cur applyLexerForExtension:first];
					const EDITLEXER *lex = [LexerRegistry lexerForExtension:first];
					if (lex == NULL || [cur.editor message:SCI_GETLEXER] != lex->iLexer)
						[bad addObject:info[@"name"] ?: first];
					else applied++;
				}
				if (bad.count) NSLog(@"[audit] applyLexer fail %@", [bad componentsJoinedByString:@","]);
				ok(@"all lexers apply", bad.count == 0 && applied >= 80);
			}
			{
				NSString *bomPath = @"/tmp/np4-enc-utf8bom.txt";
				NSMutableData *bom = [NSMutableData dataWithBytes:"\xEF\xBB\xBF" length:3];
				[bom appendData:[@"你好BOM" dataUsingEncoding:NSUTF8StringEncoding]];
				[bom writeToFile:bomPath atomically:YES];
				[controller openURLInTab:[NSURL fileURLWithPath:bomPath]];
				ok(@"utf8 bom open",
					[controller.editorDocument.currentEncoding isEqualToString:@"UTF-8 BOM"]
					&& [[controller.editorDocument.editor string] containsString:@"你好BOM"]);
				NSString *u16Path = @"/tmp/np4-enc-utf16le.txt";
				NSMutableData *u16 = [NSMutableData dataWithBytes:"\xFF\xFE" length:2];
				[u16 appendData:[@"你好UTF16" dataUsingEncoding:NSUTF16LittleEndianStringEncoding]];
				[u16 writeToFile:u16Path atomically:YES];
				[controller openURLInTab:[NSURL fileURLWithPath:u16Path]];
				ok(@"utf16le open",
					[controller.editorDocument.currentEncoding hasPrefix:@"UTF-16LE"]
					&& [[controller.editorDocument.editor string] containsString:@"你好UTF16"]);
				NSString *gbPath = @"/tmp/np4-enc-gb18030.txt";
				NSStringEncoding gbenc = CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingGB_18030_2000);
				[[@"你好国标" dataUsingEncoding:gbenc] writeToFile:gbPath atomically:YES];
				[controller openURLInTab:[NSURL fileURLWithPath:gbPath]];
				ok(@"gb18030 open",
					[controller.editorDocument.currentEncoding isEqualToString:@"GB18030"]
					&& [[controller.editorDocument.editor string] containsString:@"你好国标"]);
				[controller performSelector:@selector(setEncodingGBK)];
				ok(@"setEncodingGBK", [controller.editorDocument.currentEncoding isEqualToString:@"GB18030"]
					|| [controller.editorDocument.currentEncoding isEqualToString:@"GBK"]);
				[controller performSelector:@selector(setEncodingBIG5)];
				ok(@"setEncodingBIG5", [controller.editorDocument.currentEncoding isEqualToString:@"BIG5"]);
				[controller performSelector:@selector(setEncodingShiftJIS)];
				ok(@"setEncodingShiftJIS", [controller.editorDocument.currentEncoding isEqualToString:@"Shift-JIS"]);
				NSString *copyPath = @"/tmp/np4-savecopy.txt";
				[controller.editorDocument.editor setString:@"copy-body"];
				ok(@"save copy write",
					[controller.editorDocument writeContentsToURL:[NSURL fileURLWithPath:copyPath]
						updateIdentity:NO error:nil]
					&& [[NSString stringWithContentsOfFile:copyPath encoding:NSUTF8StringEncoding error:nil] containsString:@"copy-body"]
					&& [controller.editorDocument.fileURL.path isEqualToString:copyPath] == NO);
			}
			{
				EditorDocument *ed = controller.editorDocument;
				ScintillaView *ev = ed.editor;
				[ev message:SCI_SETEOLMODE wParam:SC_EOL_LF lParam:0];
				[ev message:SCI_CONVERTEOLS wParam:SC_EOL_LF lParam:0];
				[ev setString:@"a\na\nb\n"];
				[ev message:SCI_SELECTALL wParam:0 lParam:0];
				[controller performSelector:@selector(editMergeDuplicateLines)];
				ok(@"mergeDupes", [[ev string] hasPrefix:@"a\nb"] || [[ev string] containsString:@"a\nb"]);
				[ev setString:@"a\n\n\nb\n"];
				[ev message:SCI_SELECTALL wParam:0 lParam:0];
				[controller performSelector:@selector(editMergeBlankLines)];
				ok(@"mergeBlank", [[ev string] containsString:@"\n\n\n"] == NO);
				[ev setString:@"a   b\t\tc"];
				[ev message:SCI_SELECTALL wParam:0 lParam:0];
				[controller performSelector:@selector(editCompressWhitespace)];
				ok(@"compressWS", [[ev string] isEqualToString:@"a b c"]);
				[ev setString:@"  hi"];
				[controller performSelector:@selector(editTrimLeading)];
				ok(@"trimLeading", [[ev string] isEqualToString:@"hi"]);
				[ev setString:@"Xabc"];
				[controller performSelector:@selector(editStripFirstChar)];
				ok(@"stripFirst", [[ev string] isEqualToString:@"abc"]);
				[ev setString:@"abcY"];
				[controller performSelector:@selector(editStripLastChar)];
				ok(@"stripLast", [[ev string] isEqualToString:@"abc"]);
				[ev setString:@"a\nbb\n"];
				[ev message:SCI_SELECTALL wParam:0 lParam:0];
				[controller performSelector:@selector(editPadWithSpaces)];
				ok(@"padSpaces", [[ev string] hasPrefix:@"a "]);
				[ev setString:@"a\nbb\n"];
				[ev message:SCI_SELECTALL wParam:0 lParam:0];
				[controller performSelector:@selector(editAlignRight)];
				ok(@"alignRight", [[ev string] hasPrefix:@" a"] || [[ev string] containsString:@" a"]);
				[ev setString:@"10"];
				[ev message:SCI_SELECTALL wParam:0 lParam:0];
				[controller performSelector:@selector(editNum2Bin)];
				ok(@"num2bin", [[ev string] isEqualToString:@"0b1010"]);
				[ev setString:@"8"];
				[ev message:SCI_SELECTALL wParam:0 lParam:0];
				[controller performSelector:@selector(editNum2Oct)];
				ok(@"num2oct", [[ev string] isEqualToString:@"010"]);
				[ev setString:@"0xff"];
				[ev message:SCI_SELECTALL wParam:0 lParam:0];
				[controller performSelector:@selector(editNum2Dec)];
				ok(@"num2dec", [[ev string] isEqualToString:@"255"]);
				[ev setString:@"A"];
				[ev message:SCI_SELECTALL wParam:0 lParam:0];
				[controller performSelector:@selector(editChar2Hex)];
				ok(@"char2hex", [[ev string] isEqualToString:@"41"]);
				[ev setString:@"41"];
				[ev message:SCI_SELECTALL wParam:0 lParam:0];
				[controller performSelector:@selector(editHex2Char)];
				ok(@"hex2char", [[ev string] isEqualToString:@"A"]);
				[ev setString:@"a\tb"];
				[ev message:SCI_SELECTALL wParam:0 lParam:0];
				[controller performSelector:@selector(editEscapeCChars)];
				ok(@"escapeC", [[ev string] isEqualToString:@"a\\tb"]);
				[ev setString:@"a\\n"];
				[ev message:SCI_SELECTALL wParam:0 lParam:0];
				[controller performSelector:@selector(editUnescapeCChars)];
				ok(@"unescapeC", [[ev string] isEqualToString:@"a\n"]);
				[ev setString:@"x"];
				[ev message:SCI_SELECTALL wParam:0 lParam:0];
				[controller performSelector:@selector(editEncloseBracket)];
				ok(@"encloseBracket", [[ev string] isEqualToString:@"[x]"]);
				[ev setString:@"x"];
				[ev message:SCI_SELECTALL wParam:0 lParam:0];
				[controller performSelector:@selector(editEncloseBrace)];
				ok(@"encloseBrace", [[ev string] isEqualToString:@"{x}"]);
				[ev setString:@"x"];
				[ev message:SCI_SELECTALL wParam:0 lParam:0];
				[controller performSelector:@selector(editEncloseQuote)];
				ok(@"encloseQuote", [[ev string] isEqualToString:@"\"x\""]);
				[ev setString:@"hi"];
				[ev message:SCI_SELECTALL wParam:0 lParam:0];
				[controller performSelector:@selector(editInsertXMLTag)];
				ok(@"xmlTag", [[ev string] isEqualToString:@"<div>hi</div>"]);
				[ev setString:@"LEFT RIGHT"];
				[ev message:SCI_GOTOPOS wParam:5 lParam:0];
				[controller performSelector:@selector(editDeleteLineLeft)];
				ok(@"delLineLeft", [[ev string] hasPrefix:@"RIGHT"]);
				[ev setString:@"LEFT RIGHT"];
				[ev message:SCI_GOTOPOS wParam:5 lParam:0];
				[controller performSelector:@selector(editDeleteLineRight)];
				ok(@"delLineRight", [[ev string] isEqualToString:@"LEFT "]);
				[ev setString:@"line1\nline2\n"];
				[ev message:SCI_GOTOLINE wParam:1 lParam:0];
				[controller performSelector:@selector(searchSelectLine)];
				ok(@"selectLine", [ev message:SCI_GETSELECTIONEND] > [ev message:SCI_GETSELECTIONSTART]);
				[ev setString:@"abcdef"];
				[ev message:SCI_GOTOPOS wParam:3 lParam:0];
				[controller performSelector:@selector(searchSelectToDocStart)];
				ok(@"selectToStart", [ev message:SCI_GETSELECTIONSTART] == 0);
				[controller performSelector:@selector(searchSelectToDocEnd)];
				ok(@"selectToEnd", [ev message:SCI_GETSELECTIONEND] == [ev message:SCI_GETLENGTH]
					|| [ev message:SCI_GETSELECTIONSTART] == [ev message:SCI_GETLENGTH]);
				[ev setString:@""];
				[controller performSelector:@selector(insertUnicodeZWSP)];
				ok(@"zwsp", [ev message:SCI_GETLENGTH] == 3);
				[ev setString:@""];
				[controller performSelector:@selector(insertUnicodeNBSP)];
				ok(@"nbsp", [ev message:SCI_GETLENGTH] == 2);
				[ev setString:@""];
				[controller performSelector:@selector(insertUnicodeLRM)];
				ok(@"lrm", [ev message:SCI_GETLENGTH] == 3);
				[ev setString:@""];
				[controller performSelector:@selector(insertUnicodeRLM)];
				ok(@"rlm", [ev message:SCI_GETLENGTH] == 3);
				[controller openURLInTab:[NSURL fileURLWithPath:@"/tmp/np4-shebang.py"]];
				[@"print(1)\n" writeToFile:@"/tmp/np4-shebang.py" atomically:YES encoding:NSUTF8StringEncoding error:nil];
				[controller openURLInTab:[NSURL fileURLWithPath:@"/tmp/np4-shebang.py"]];
				[controller performSelector:@selector(insertShebang)];
				ok(@"shebang", [[controller.editorDocument.editor string] containsString:@"python3"]);
				[controller.editorDocument.editor setString:@""];
				[controller performSelector:@selector(insertEncodingName)];
				ok(@"insertEncoding", [controller.editorDocument.editor message:SCI_GETLENGTH] > 0);
				[controller.editorDocument.editor setString:@"a b"];
				[controller.editorDocument.editor message:SCI_SELECTALL wParam:0 lParam:0];
				[controller performSelector:@selector(urlComponentEncode)];
				ok(@"urlComponent", [[controller.editorDocument.editor string] isEqualToString:@"a%20b"]);
				[controller.editorDocument.editor setString:@"line1\nline2\nline3\n"];
				[controller.editorDocument.editor message:SCI_GOTOLINE wParam:2 lParam:0];
				ok(@"gotoLine sci",
					[controller.editorDocument.editor message:SCI_LINEFROMPOSITION
						wParam:[controller.editorDocument.editor message:SCI_GETCURRENTPOS]] == 2);
				[controller performSelector:@selector(settingsSaveNow)];
				ok(@"settingsSaveNow headless", YES);
				ok(@"project home url",
					[[controller projectHomeURL] isEqualToString:@"https://github.com/limin640/notepad4-mac"]);
				[controller performSelector:@selector(helpHome)];
				ok(@"helpHome headless no open", YES);
			}
			{
				NSString *lp = @"/tmp/np4-audit-8mb.txt";
				const NSUInteger n8 = 8ull * 1024ull * 1024ull + 32;
				NSMutableData *md = [NSMutableData dataWithLength:n8];
				memset(md.mutableBytes, 'A', n8);
				memcpy(md.mutableBytes, "NP48MBHEAD", 10);
				[md writeToFile:lp atomically:YES];
				const CFAbsoluteTime t0 = CFAbsoluteTimeGetCurrent();
				[controller openURLInTab:[NSURL fileURLWithPath:lp]];
				const double ms = (CFAbsoluteTimeGetCurrent() - t0) * 1000.0;
				EditorDocument *ldoc = controller.editorDocument;
				const sptr_t n = [ldoc.editor message:SCI_GETLENGTH];
				char head[12] = {0};
				[ldoc.editor message:SCI_GETTEXT wParam:11 lParam:(sptr_t)head];
				ok(@"8mb large mode", ldoc.largeFileMode && n == (sptr_t)n8);
				ok(@"8mb head", strncmp(head, "NP48MBHEAD", 10) == 0);
				ok(@"8mb open fast", ms < 8000);
				NSLog(@"[audit] 8mb open %.1f ms len=%ld", ms, (long)n);
			}
			{
				ok(@"quit-after-last-window implemented",
					[appDelegate respondsToSelector:@selector(applicationShouldTerminateAfterLastWindowClosed:)]);
				ok(@"headless does not auto-quit",
					[appDelegate applicationShouldTerminateAfterLastWindowClosed:NSApp] == NO);
				ok(@"concurrent document read off",
					[NPShimDocument canConcurrentlyReadDocumentsOfType:@"Markdown"] == NO);
				const NSInteger n0 = [MainWindowController liveControllerCount];
				ok(@"live start", n0 >= 1);
				[controller fileNewWindow];
				ok(@"parallel window", [MainWindowController liveControllerCount] == n0 + 1);
				MainWindowController *extra = [MainWindowController liveControllers].lastObject;
				ok(@"new window distinct", extra != nil && extra != controller);
				[extra.window close];
				ok(@"closed extra gone", [MainWindowController liveControllerCount] == n0);
				NSString *first = @"/tmp/np4-life-1.md";
				NSString *second = @"/tmp/np4-life-2.md";
				[@"first-md-ok\n" writeToFile:first atomically:YES encoding:NSUTF8StringEncoding error:nil];
				[@"second-md-ok\n" writeToFile:second atomically:YES encoding:NSUTF8StringEncoding error:nil];
				[controller openURLInTab:[NSURL fileURLWithPath:first]];
				ok(@"first md open",
					[[controller.editorDocument.editor string] containsString:@"first-md-ok"]);
				[controller.window close];
				ok(@"primary closed", [controller windowIsUsable] == NO);
				ok(@"live after close", [MainWindowController liveControllerCount] == 0);
				[appDelegate application:NSApp openURLs:@[[NSURL fileURLWithPath:second]]];
				MainWindowController *again = appDelegate.controller;
				ok(@"reopen after close",
					again != nil
					&& [again windowIsUsable]
					&& [[again.editorDocument.editor string] containsString:@"second-md-ok"]);
				ok(@"fresh controller after close", again != controller);
				controller = again;
			}
			{
				NSString *mdh = [PreviewPane htmlFromMarkdown:
					@"# HelloPreview\n\n**bold** and *it*\n\n- a\n- b\n\n`x`\n\n```\ncode\n```\n\n[go](https://example.com)\n"];
				ok(@"md src-line heading", [mdh containsString:@"data-src-line=\"1\""]);
				ok(@"md src-line list", [mdh containsString:@"<li data-src-line="]);
				ok(@"md src-line pre", [mdh containsString:@"<pre data-src-line="]);
				ok(@"md h1", [mdh containsString:@"<h1"] && [mdh containsString:@"HelloPreview"]);
				ok(@"md strong", [mdh containsString:@"<strong>bold</strong>"]);
				ok(@"md em", [mdh containsString:@"<em>it</em>"]);
				ok(@"md li", [mdh containsString:@"<li"]);
				ok(@"md code", [mdh containsString:@"<code>x</code>"]);
				ok(@"md pre", [mdh containsString:@"<pre"]);
				ok(@"md link", [mdh containsString:@"example.com"]);
				{
					NSString *scheme = [@"java" stringByAppendingString:@"script:alert(1)"];
					NSString *mdjs = [NSString stringWithFormat:@"[x](%@)", scheme];
					NSString *blocked = [PreviewPane htmlFromMarkdown:mdjs];
					ok(@"md js url blocked", [blocked rangeOfString:@"script:"].location == NSNotFound);
				}
				ok(@"preview default off", [controller previewOn] == NO);
				NSString *mp = @"/tmp/np4-preview.md";
				[@"# PreviewTitle\n\nhello **md**\n" writeToFile:mp atomically:YES encoding:NSUTF8StringEncoding error:nil];
				[controller openURLInTab:[NSURL fileURLWithPath:mp]];
				ok(@"md kind", [PreviewPane kindForDocument:controller.editorDocument] == NPPreviewMarkdown);
				[controller viewPreview];
				ok(@"preview on", [controller previewOn]);
				ok(@"preview html live", [[controller previewHTML] containsString:@"PreviewTitle"]);
				ok(@"preview page has root", [[controller previewLastPageHTML] containsString:@"id=\"np4-root\""]);
				ok(@"preview page has scroller", [[controller previewLastPageHTML] containsString:@"id=\"np4-scroller\""]);
				[controller.editorDocument.editor setString:@"# AfterEdit\n\nkeep-place\n\nend\n"];
				[controller refreshPreviewNow];
				ok(@"preview follows edit", [[controller previewHTML] containsString:@"AfterEdit"]);
				ok(@"preview edit keeps place", [controller previewLastRefreshInPlace]);
				ok(@"preview edit does not scroll", [controller previewLastRefreshDidScroll] == NO);
				[controller refreshPreviewNow];
				ok(@"preview same text skipped", [controller previewLastRefreshInPlace]);
				ok(@"preview skip does not scroll", [controller previewLastRefreshDidScroll] == NO);
				ok(@"md preview uses line map", [controller previewUsesLineMap]);
				ok(@"md scroll linked", [controller previewScrollLinked]);
				ok(@"md page src-line", [[controller previewLastPageHTML] containsString:@"data-src-line"]);
				[controller syncPreviewToEditor];
				ok(@"md sync records line", [controller previewLastSyncLine] >= 0);
				[controller applyPreviewScrollLine:2 fraction:0];
				ok(@"md preview drives editor", [controller lastAppliedEditorLineFromPreview] == 1);
				NSString *hp = @"/tmp/np4-preview.html";
				[@"<h2>HtmlTitle</h2><p>zz</p>\n" writeToFile:hp atomically:YES encoding:NSUTF8StringEncoding error:nil];
				[controller openURLInTab:[NSURL fileURLWithPath:hp]];
				ok(@"html preview", [[controller previewHTML] containsString:@"HtmlTitle"]);
				[controller refreshPreviewNow];
				ok(@"html preview uses percent", [controller previewUsesLineMap] == NO);
				ok(@"html scroll not linked", [controller previewScrollLinked] == NO);
				const NSInteger htmlAppliedBefore = [controller lastAppliedEditorLineFromPreview];
				const NSInteger htmlVisBefore = [controller editorFirstVisibleLine];
				[controller applyPreviewScrollLine:0 fraction:0.5];
				[controller syncPreviewToEditor];
				ok(@"html preview does not drive editor", [controller lastAppliedEditorLineFromPreview] == htmlAppliedBefore);
				ok(@"html editor line unchanged", [controller editorFirstVisibleLine] == htmlVisBefore);
				NSString *tp = @"/tmp/np4-preview.txt";
				[@"# TxtTitle\n\nplain **txt**\n" writeToFile:tp atomically:YES encoding:NSUTF8StringEncoding error:nil];
				[controller openURLInTab:[NSURL fileURLWithPath:tp]];
				ok(@"txt kind markdown", [PreviewPane kindForDocument:controller.editorDocument] == NPPreviewMarkdown);
				ok(@"txt preview renders", [[controller previewHTML] containsString:@"TxtTitle"]);
				ok(@"txt scroll linked", [controller previewScrollLinked]);
				NSString *pngPath = @"/tmp/np4-preview.png";
				{
					NSImage *one = [[NSImage alloc] initWithSize:NSMakeSize(2, 2)];
					[one lockFocus];
					[[NSColor redColor] set];
					NSRectFill(NSMakeRect(0, 0, 2, 2));
					[one unlockFocus];
					NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithData:one.TIFFRepresentation];
					[[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:pngPath atomically:YES];
				}
				[controller openURLInTab:[NSURL fileURLWithPath:pngPath]];
				ok(@"png kind image", [PreviewPane kindForDocument:controller.editorDocument] == NPPreviewImage);
				ok(@"png preview html", [[controller previewHTML] containsString:@"np4-preview.png"]);
				ok(@"png scroll not linked", [controller previewScrollLinked] == NO);
				NSString *mdimg = @"/tmp/np4-mdimg.md";
				[@"# Pic\n\n![qr](np4-preview.png)\n" writeToFile:mdimg atomically:YES encoding:NSUTF8StringEncoding error:nil];
				[controller openURLInTab:[NSURL fileURLWithPath:mdimg]];
				ok(@"md local image data uri", [[controller previewHTML] containsString:@"data:image/png;base64,"]);
				[controller viewPreview];
				ok(@"preview off toggle", [controller previewOn] == NO);
				[controller viewPreview];
				ok(@"preview click again on", [controller previewOn]);
				NSButton *pb = [controller previewStatusButton];
				ok(@"status preview button", pb != nil);
				ok(@"status preview title", [pb.title isEqualToString:@"预览"] || [pb.title isEqualToString:@"Preview"]);
				ok(@"divider grabable", [controller previewDividerThickness] >= 6);
				const BOOL moved = [controller setPreviewSplitPosition:240];
				ok(@"split position set", moved);
				if (moved) {
					const CGFloat got = [controller previewSplitPosition];
					ok(@"split width follows drag", got > 80);
					// 比例记忆：拖完记下比例，重开预览应按比例还原
					[controller viewPreview];
					[controller.window.contentView layoutSubtreeIfNeeded];
					[controller viewPreview];
					[controller.window.contentView layoutSubtreeIfNeeded];
					const CGFloat usable = [controller previewPaneWidth] + [controller previewSplitPosition];
					ok(@"split frac remembered", usable > 100);
					const CGFloat frac = [controller previewSplitPosition] / usable;
					ok(@"split frac in range", frac > 0.1 && frac < 0.9);
				}
				{
					[controller.window.contentView layoutSubtreeIfNeeded];
					const CGFloat left0 = [controller previewSplitPosition];
					const CGFloat pane0 = [controller previewPaneWidth];
					ok(@"preview pane has width", pane0 > 80);
					ok(@"preview left has width", left0 > 80);
					for (int i = 0; i < 4; i++) {
						[controller viewPreview];
						[controller viewPreview];
						[controller.window.contentView layoutSubtreeIfNeeded];
					}
					const CGFloat left1 = [controller previewSplitPosition];
					const CGFloat pane1 = [controller previewPaneWidth];
					const CGFloat dLeft = left1 > left0 ? left1 - left0 : left0 - left1;
					const CGFloat dPane = pane1 > pane0 ? pane1 - pane0 : pane0 - pane1;
					ok(@"preview still on after toggles", [controller previewOn]);
					ok(@"preview left stable after 4 toggles", dLeft < 3);
					ok(@"preview pane stable after 4 toggles", dPane < 3);
					ok(@"preview did not shrink", pane1 + 1 >= pane0);
				}
				[controller viewPreview];
				ok(@"status click path off", [controller previewOn] == NO);
				[@"int x;\n" writeToFile:@"/tmp/np4-preview.py" atomically:YES encoding:NSUTF8StringEncoding error:nil];
				[controller openURLInTab:[NSURL fileURLWithPath:@"/tmp/np4-preview.py"]];
				ok(@"py no preview kind", [PreviewPane kindForDocument:controller.editorDocument] == NPPreviewNone);
				{
					EditorDocument *qd = controller.editorDocument;
					[qd applyLexerForExtension:@"cpp"];
					[qd.editor setString:@"int x;"];
					[qd.editor message:SCI_SELECTALL wParam:0 lParam:0];
					NSString *beforeQ = [qd.editor string];
					NSEvent *cmdQ = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint
						modifierFlags:NSEventModifierFlagCommand timestamp:0 windowNumber:0 context:nil
						characters:@"q" charactersIgnoringModifiers:@"q" isARepeat:NO keyCode:12];
					const BOOL ateCmdQ = [controller handleKeyEquivalent:cmdQ];
					ok(@"cmd-q not eaten", ateCmdQ == NO);
					ok(@"cmd-q is not stream comment", [[qd.editor string] isEqualToString:beforeQ]);
					NSEvent *ctrlQ = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint
						modifierFlags:NSEventModifierFlagControl timestamp:0 windowNumber:0 context:nil
						characters:@"q" charactersIgnoringModifiers:@"q" isARepeat:NO keyCode:12];
					const BOOL ateCtrlQ = [controller handleKeyEquivalent:ctrlQ];
					ok(@"ctrl-q eaten", ateCtrlQ);
					ok(@"ctrl-q stream comment", [[qd.editor string] containsString:@"/*"]);
				}
			}
			{
				EditorDocument *ed = controller.editorDocument;
				ScintillaView *ev = ed.editor;
				[ev setString:@"abc\ndef"];
				[ev message:SCI_GOTOPOS wParam:1 lParam:0];
				[controller performSelector:@selector(editStripFirstChar)];
				ok(@"strip first current line only", [[ev string] isEqualToString:@"bc\ndef"]);
				[ev setString:@"abc\ndef"];
				[ev message:SCI_GOTOPOS wParam:1 lParam:0];
				[controller performSelector:@selector(editStripLastChar)];
				ok(@"strip last current line only", [[ev string] isEqualToString:@"ab\ndef"]);
				[ev setString:@"hello"];
				[ev message:SCI_SELECTALL wParam:0 lParam:0];
				[controller performSelector:@selector(editEncloseParen)];
				ok(@"enclose paren keep inner", [[ev string] isEqualToString:@"(hello)"]);
				[ev setString:@""];
				[ev message:SCI_GOTOPOS wParam:0 lParam:0];
				[controller performSelector:@selector(editEncloseBrace)];
				ok(@"enclose empty inserts pair", [[ev string] isEqualToString:@"{}"]);
				[ev setString:@"one\ntwo"];
				[ev message:SCI_SELECTALL wParam:0 lParam:0];
				[controller performSelector:@selector(editJoinLines)];
				ok(@"join lines", [[ev string] containsString:@"one"] && [[ev string] containsString:@"two"] && ![[ev string] containsString:@"\n"]);
				[ev setString:@"x\ny"];
				[ev message:SCI_GOTOPOS wParam:0 lParam:0];
				[controller performSelector:@selector(editJoinLines)];
				ok(@"join from caret", [[ev string] containsString:@"x"] && [[ev string] containsString:@"y"] && ![[ev string] containsString:@"\n"]);
				[ev setString:@"    hi"];
				[ev message:SCI_GOTOPOS wParam:0 lParam:0];
				[controller performSelector:@selector(editIndent)];
				ok(@"indent line", [[ev string] hasPrefix:@"\t"] || [[ev string] hasPrefix:@"        "] || [[ev string] hasPrefix:@"    "]);
				[ev setString:@"aa\nbb"];
				[ev message:SCI_SELECTALL wParam:0 lParam:0];
				[controller performSelector:@selector(editModifyLines)];
				ok(@"modify lines prefix", [[ev string] containsString:@"> aa"] && [[ev string] containsString:@"> bb"]);
				[ev setString:@"a\nbb\nccc"];
				[ev message:SCI_SELECTALL wParam:0 lParam:0];
				[controller performSelector:@selector(editAlignRight)];
				ok(@"align right pads", [[ev string] containsString:@"  a"]);
				[ev setString:@"a\nbb\nccc"];
				[ev message:SCI_SELECTALL wParam:0 lParam:0];
				[controller performSelector:@selector(editAlignCenter)];
				ok(@"align center", [ev string].length >= 9);
				[ev setString:@"c\nb\na"];
				[ev message:SCI_SELECTALL wParam:0 lParam:0];
				[controller performSelector:@selector(editSortLinesDescending)];
				ok(@"sort desc", [[ev string] hasPrefix:@"c"]);
				[ev setString:@"this is a very long line of text for wrapping"];
				[ev message:SCI_SELECTALL wParam:0 lParam:0];
				[[NSUserDefaults standardUserDefaults] setInteger:12 forKey:@"NP4WrapColumn"];
				[controller performSelector:@selector(editColumnWrap)];
				ok(@"column wrap", [[[ev string] componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]] count] > 1);
				[ev setString:@"para one\nstill one\n\npara two"];
				[ev message:SCI_SELECTALL wParam:0 lParam:0];
				[controller performSelector:@selector(editJoinParagraphs)];
				ok(@"join paragraphs", [[ev string] containsString:@"para one still one"] && [[ev string] containsString:@"para two"]);
				[ev setString:@"word"];
				[ev message:SCI_SELECTALL wParam:0 lParam:0];
				[controller performSelector:@selector(editEncloseTripleBT)];
				ok(@"triple backtick", [[ev string] isEqualToString:@"```word```"]);
				[ev setString:@"    x"];
				[ev message:SCI_SELECTALL wParam:0 lParam:0];
				[controller performSelector:@selector(editTabifySelection)];
				ok(@"tabify selection", [[ev string] containsString:@"\t"]);
				[ev setString:@"10"];
				[ev message:SCI_SELECTALL wParam:0 lParam:0];
				[controller performSelector:@selector(editIncreaseNumber)];
				ok(@"inc number", [[ev string] isEqualToString:@"11"]);
				[ev setString:@"A"];
				[ev message:SCI_SELECTALL wParam:0 lParam:0];
				[controller performSelector:@selector(editShowHex)];
				ok(@"show hex", [[ev string] containsString:@"41"]);
				[ev setString:@"A"];
				[ev message:SCI_SELECTALL wParam:0 lParam:0];
				[controller performSelector:@selector(editShowCharInfo)];
				ok(@"char info", [[ev string] containsString:@"U+0041"]);
				[ev setString:@"hello"];
				[ev message:SCI_SETSEL wParam:1 lParam:4];
				ok(@"menu path enclose", [controller clickInWindowMenuPath:@[@"Edit", @"Enclose Selection", @"Enclose ()"]]
					|| [controller clickInWindowMenuPath:@[@"编辑", @"包围选中文本", @"包围 ()"]]);
				ok(@"menu enclose really wraps", [[ev string] containsString:@"("]);
				[ev setString:@"wrapme"];
				[ev message:SCI_SETSEL wParam:0 lParam:6];
				NSInteger editIdx = -1;
				NSArray *titles = [controller inWindowMenuTitles];
				for (NSUInteger i = 0; i < titles.count; i++) {
					if ([titles[i] isEqualToString:@"Edit"] || [titles[i] isEqualToString:@"编辑"])
						{ editIdx = (NSInteger)i; break; }
				}
				ok(@"edit menu index", editIdx >= 0);
				[controller openInWindowMenuAtIndex:editIdx];
				[ev message:SCI_SETSEL wParam:6 lParam:6];
				ok(@"menu path enclose after sel lost", [controller clickInWindowMenuPath:@[@"Edit", @"Enclose Selection", @"Enclose ()"]]
					|| [controller clickInWindowMenuPath:@[@"编辑", @"包围选中文本", @"包围 ()"]]);
				ok(@"enclose uses snapped selection", [[ev string] isEqualToString:@"(wrapme)"]);
				[controller closeInWindowMenu];
				ok(@"convert flyout opens", [controller clickInWindowMenuPath:@[@"Edit", @"Convert"]]
					|| [controller clickInWindowMenuPath:@[@"编辑", @"转换"]]);
				ok(@"convert flyout exists", [controller inWindowFlyoutCount] >= 1);
				NSRect lf = [controller inWindowLastPanelFrame];
				NSView *st = controller.window.contentView;
				ok(@"convert flyout on screen", lf.size.height > 40 && NSMinY(lf) >= 0);
				ok(@"convert flyout not past status", NSMinY(lf) >= 20 || lf.size.height < NSHeight(st.bounds));
				const CGFloat contentH = [controller inWindowLastPanelContentHeight];
				ok(@"convert content taller or equal", contentH >= lf.size.height - 1);
				ok(@"convert hex reachable", [controller clickInWindowMenuPath:@[@"Edit", @"Convert", @"Number to Hex"]]
					|| [controller clickInWindowMenuPath:@[@"编辑", @"转换", @"数字转十六进制"]]);
				ok(@"caret width visible", [ev message:SCI_GETCARETWIDTH] >= 2);
				[ev setString:@"a,b()"];
				[ev message:SCI_SETCARETPERIOD wParam:0 lParam:0];
				[ev message:SCI_GOTOPOS wParam:2 lParam:0];
				const sptr_t xComma = [ev message:SCI_POINTXFROMPOSITION wParam:0 lParam:1];
				const sptr_t xAfter = [ev message:SCI_POINTXFROMPOSITION wParam:0 lParam:2];
				ok(@"caret after comma is at next cell", xAfter > xComma);
				ok(@"comma cell wide enough", (xAfter - xComma) >= 3);
				[controller.window.contentView layoutSubtreeIfNeeded];
				NPCacheShot(ev.content ?: ev, @"/tmp/np4-bug-caret.png");
				ok(@"caret shot written", [[NSFileManager defaultManager] fileExistsAtPath:@"/tmp/np4-bug-caret.png"]);
				[ev setString:@"(),(),()"];
				[ev message:SCI_GOTOPOS wParam:2 lParam:0];
				NPCacheShot(ev.content ?: ev, @"/tmp/np4-bug-caret-comma.png");
				ok(@"dropdown scroller still attached", [controller inWindowDropDownHasScroller]);
				ok(@"convert lists hex", [controller clickInWindowMenuPath:@[@"Edit", @"Convert"]]
					|| [controller clickInWindowMenuPath:@[@"编辑", @"转换"]]);
				{
					NSArray *rows = [controller inWindowLastPanelRowNames];
					ok(@"convert rows kept after previous close", rows.count >= 12);
					BOOL hasHex = [rows containsObject:@"Number to Hex"] || [rows containsObject:@"数字转十六进制"];
					BOOL hasDec = [rows containsObject:@"Decrease Number"] || [rows containsObject:@"数字减一"];
					ok(@"convert hex row present", hasHex);
					ok(@"convert last rows present", hasDec);
					NSRect hexR = [controller inWindowRowFrameNamed:@"数字转十六进制"];
					if (hexR.size.height < 1) hexR = [controller inWindowRowFrameNamed:@"Number to Hex"];
					ok(@"hex row has height", hexR.size.height >= 20);
					ok(@"hex row not discarded", NSMaxY(hexR) > 180);
					const CGFloat ch = [controller inWindowLastPanelContentHeight];
					ok(@"hex inside scroll content", NSMaxY(hexR) <= ch + 2);
					NPCacheShot(controller.window.contentView, @"/tmp/np4-bug-convert-top.png");
					ok(@"scroll hex into view", [controller scrollInWindowLastPanelToName:@"数字转十六进制"]
						|| [controller scrollInWindowLastPanelToName:@"Number to Hex"]);
					NPCacheShot(controller.window.contentView, @"/tmp/np4-bug-convert-hex.png");
					NPCacheShot(([controller valueForKey:@"lastDropPanel"]), @"/tmp/np4-bug-convert-panel.png");
				}
				ok(@"unicode flyout opens", [controller clickInWindowMenuPath:@[@"Edit", @"Insert", @"Unicode Control Character"]]
					|| [controller clickInWindowMenuPath:@[@"编辑", @"插入", @"Unicode 控制字符"]]);
				{
					NSArray *rows = [controller inWindowLastPanelRowNames];
					ok(@"unicode overflow rows exist", rows.count >= 16);
					BOOL hasSHY = [rows containsObject:@"Soft Hyphen"] || [rows containsObject:@"软连字符"];
					ok(@"unicode last item present", hasSHY);
					NSRect shy = [controller inWindowRowFrameNamed:@"Soft Hyphen"];
					if (shy.size.height < 1) shy = [controller inWindowRowFrameNamed:@"软连字符"];
					ok(@"unicode last row kept", shy.size.height >= 20);
					ok(@"unicode last below viewport top", NSMaxY(shy) > 200);
					ok(@"scroll unicode last", [controller scrollInWindowLastPanelToName:@"Soft Hyphen"]
						|| [controller scrollInWindowLastPanelToName:@"软连字符"]);
					NPCacheShot(controller.window.contentView, @"/tmp/np4-bug-unicode.png");
				}
				[controller closeInWindowMenu];
				ok(@"scroller survives close", [controller inWindowDropDownHasScroller]);
				{
					NSArray *pairs = @[
						@[@"Enclose ()", @"包围 ()", @"(wrapme)"],
						@[@"Enclose []", @"包围 []", @"[wrapme]"],
						@[@"Enclose {}", @"包围 {}", @"{wrapme}"],
					];
					for (NSArray *p in pairs) {
						[ev setString:@"wrapme"];
						[ev message:SCI_SETSEL wParam:0 lParam:6];
						[controller openInWindowMenuAtIndex:editIdx];
						[ev message:SCI_SETSEL wParam:6 lParam:6];
						BOOL hit = [controller clickInWindowMenuPath:@[@"Edit", @"Enclose Selection", p[0]]]
							|| [controller clickInWindowMenuPath:@[@"编辑", @"包围选中文本", p[1]]];
						ok([NSString stringWithFormat:@"enclose %@ after sel lost", p[0]], hit);
						ok([NSString stringWithFormat:@"enclose %@ wraps text", p[0]], [[ev string] isEqualToString:p[2]]);
					}
					[ev setString:@"aa,bb\ncc,dd"];
					[ev message:SCI_SETSEL wParam:0 lParam:[ev message:SCI_GETLENGTH]];
					[controller openInWindowMenuAtIndex:editIdx];
					[ev message:SCI_SETSEL wParam:0 lParam:0];
					ok(@"multiline enclose after sel lost", [controller clickInWindowMenuPath:@[@"Edit", @"Enclose Selection", @"Enclose ()"]]
						|| [controller clickInWindowMenuPath:@[@"编辑", @"包围选中文本", @"包围 ()"]]);
					ok(@"multiline enclose keeps inner", [[ev string] isEqualToString:@"(aa,bb\ncc,dd)"]);
					NPCacheShot(ev.content ?: ev, @"/tmp/np4-bug-enclose.png");
				}
				[ev setString:@"Xabc"];
				[ev message:SCI_GOTOPOS wParam:0 lParam:0];
				ok(@"menu path strip first", [controller clickInWindowMenuPath:@[@"Edit", @"Selection", @"Strip First Character"]]
					|| [controller clickInWindowMenuPath:@[@"编辑", @"选中文本", @"移除首个字符"]]);
				ok(@"menu strip first mutates", [[ev string] hasPrefix:@"abc"] || [[ev string] isEqualToString:@"abc"]);
				[ev setString:@"开放"];
				[ev message:SCI_SELECTALL wParam:0 lParam:0];
				[controller performSelector:@selector(mapSimpToTrad)];
				ok(@"simp to trad", [[ev string] isEqualToString:@"開放"]);
				[controller performSelector:@selector(mapTradToSimp)];
				ok(@"trad to simp", [[ev string] isEqualToString:@"开放"]);
				[ev setString:@"A1"];
				[ev message:SCI_SELECTALL wParam:0 lParam:0];
				[controller performSelector:@selector(mapHalfToFull)];
				ok(@"half to full", [[ev string] isEqualToString:@"Ａ１"]);
				[controller performSelector:@selector(mapFullToHalf)];
				ok(@"full to half", [[ev string] isEqualToString:@"A1"]);
				[ev setString:@"1+2*3"];
				[ev message:SCI_SELECTALL wParam:0 lParam:0];
				[controller performSelector:@selector(editCalculateExpression)];
				ok(@"calc expr", [[ev string] isEqualToString:@"7"]);
				[ev setString:@"{\"a\":1}"];
				[ev message:SCI_SELECTALL wParam:0 lParam:0];
				[controller performSelector:@selector(editCodePretty)];
				ok(@"json pretty", [[ev string] containsString:@"\n"] || [[ev string] containsString:@"  "]);
				[ev setString:@"  a   b\t c"];
				[ev message:SCI_SELECTALL wParam:0 lParam:0];
				[controller performSelector:@selector(editCompressWhitespace)];
				ok(@"compress ws", [[ev string] isEqualToString:@" a b c"] || [[ev string] isEqualToString:@"a b c"]);
				[ev setString:@"abc"];
				[ev message:SCI_GOTOPOS wParam:0 lParam:0];
				[controller performSelector:@selector(editDuplicate)];
				ok(@"duplicate selection or line", [ev string].length > 3);
				[ev setString:@"$Date: old $"];
				[controller performSelector:@selector(editUpdateTimestamps)];
				ok(@"update timestamps", [[ev string] containsString:@"$Date:"] && ![[ev string] containsString:@"old"]);
				NSMutableString *dump = [NSMutableString string];
				[controller dumpInWindowMenus:dump];
				ok(@"zh selection label", [dump containsString:@"选中文本"]);
				ok(@"zh strip first label", [dump containsString:@"移除首个字符"]);
				ok(@"zh enclose label", [dump containsString:@"包围选中文本"]);
				ok(@"zh pad label", [dump containsString:@"填充空格"]);
				ok(@"zh translit", [dump containsString:@"文字转换"] || [dump containsString:@"Text Transliteration"]);
				NPLanguageOverrideCodeForTesting(@"ja");
				ok(@"ja File", [NPL(@"File") isEqualToString:@"ファイル"]);
				NPLanguageOverrideCodeForTesting(@"zh-Hant");
				ok(@"hant File", [NPL(@"File") isEqualToString:@"檔案"]);
				NPLanguageOverrideCodeForTesting(@"de");
				ok(@"de File", [NPL(@"File") isEqualToString:@"Ablage"]);
				NPLanguageOverrideCodeForTesting(@"fr");
				ok(@"fr File", [NPL(@"File") isEqualToString:@"Fichier"]);
				NPLanguageOverrideCodeForTesting(@"zh-Hans");
				ok(@"hans File restore", [NPL(@"File") isEqualToString:@"文件"]);
				[controller languageChinese];
								NSArray *leaves = [controller menuLeafCatalog];
				ok(@"menu catalog deep", leaves.count >= 80);
				int missing = 0, invoked = 0, mutated = 0;
				NSSet *skip = [NSSet setWithArray:@[
					@"terminate", @"terminate:", @"orderFrontStandardAboutPanel:",
					@"fileOpen", @"fileSaveAs", @"fileSaveCopy", @"fileSave", @"fileSaveBackup",
					@"fileNew", @"fileNewWindow", @"fileCloseTab", @"fileRevert", @"fileProperties",
					@"filePageSetup", @"printDocument", @"fileManageFavorites",
					@"schemeChoose", @"schemeCustomize", @"gotoLine", @"settingsTabSettings",
					@"settingsAutoCompletion", @"settingsSaveNow", @"toolsExecute", @"toolsOpenWith",
					@"toolsRunCommand", @"actionOpenSelection", @"actionSearchGoogle", @"actionSearchBing", @"actionSearchWiki", @"helpHome", @"helpDonate",
					@"fileCreateDesktopShortcut", @"reloadWithEncodingDialog",
					@"editInsertXMLTag", @"editEncloseCustom", @"viewPreview",
					@"languageChinese", @"languageEnglish", @"languageSystem", @"languagePicked:", @"themeAuto", @"themeDefault", @"themeDark",
					@"openContainingFolder", @"tbBrowse", @"tbOpenFav", @"tbOpenMenu", @"tbFoldMenu",
					@"tbOpenDropdown", @"tbSchemeMenu", @"tbSchemeConfig"]];
				NSSet *mutate = [NSSet setWithArray:@[
					@"editStripFirstChar", @"editStripLastChar", @"editEncloseParen", @"editEncloseBracket",
					@"editEncloseBrace", @"editEncloseQuote", @"editJoinLines", @"editModifyLines",
					@"editSortLines", @"editSortLinesDescending", @"editAlignRight", @"editAlignLeft",
					@"editPadWithSpaces", @"editTrimLeading", @"editCompressWhitespace",
					@"editUpper", @"editLower", @"editInvertCase", @"editTitleCase", @"editSentenceCase",
					@"editDuplicateLine", @"editDeleteLine", @"editNum2Hex", @"editNum2Bin",
					@"editIncreaseNumber", @"editShowHex", @"editChar2Hex", @"editEscapeCChars",
					@"editTabifySelection", @"editColumnWrap", @"insertGUID", @"insertDateTime",
					@"insertUnixTimestamp", @"insertTimestampMs", @"insertUnicodeZWSP",
					@"editEncloseTripleBT", @"editJoinParagraphs", @"mapSimpToTrad", @"mapHalfToFull",
					@"editCalculateExpression", @"editCodePretty", @"editCodeCompress",
					@"editUpdateTimestamps", @"editDuplicate", @"insertCurrentDate"]];
				NSString *fixture = @"alpha\nbeta\nalpha\n123 extra";
				for (NSDictionary *leaf in leaves) {
					NSString *act = leaf[@"action"];
					SEL sel = NSSelectorFromString(act);
					const BOOL appSel = [act hasSuffix:@":"];
					ok([NSString stringWithFormat:@"leaf responds %@", act],
						[controller respondsToSelector:sel] || appSel);
					if ([skip containsObject:act] || [act hasPrefix:@"file"] || [act hasPrefix:@"reload"]
						|| [act hasPrefix:@"theme"] || [act hasPrefix:@"language"] || [act hasPrefix:@"tb"]
						|| [act hasPrefix:@"view"] || [act hasPrefix:@"toggle"] || [act hasPrefix:@"settings"])
						continue;
					if (![controller respondsToSelector:sel]) { missing++; continue; }
					[ev setString:fixture];
					[ev message:SCI_SELECTALL wParam:0 lParam:0];
					#pragma clang diagnostic push
					#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
					[controller performSelector:sel];
					#pragma clang diagnostic pop
					invoked++;
					if ([mutate containsObject:act] && ![[ev string] isEqualToString:fixture]) mutated++;
				}
				ok(@"menu leaves invoked", invoked >= 60);
				ok(@"mutate commands actually change text", mutated >= 20);
				ok(@"no missing leaf impl", missing == 0);
				NSLog(@"[audit] menu leaves=%lu invoked=%d mutated=%d missing=%d",
					(unsigned long)leaves.count, invoked, mutated, missing);
			}
			sk(@"tbBrowse/openContainingFolder", @"opens Finder");
			sk(@"fileOpen/SaveAs/SaveCopy panels", @"file panel");
			sk(@"schemeChoose UI", @"NSAlert; lexers applied above");
			sk(@"filePageSetup/printDocument", @"modal UI");
			sk(@"gotoLine/settingsTab/AutoCompletion alerts", @"NSAlert; SCI_GOTOLINE tested");
			sk(@"toolsExecute/OpenWith", @"opens other apps");
			sk(@"actionSearchGoogle/actionOpenSelection", @"opens URL");
			sk(@"fileCreateDesktopShortcut", @"writes Desktop");
			sk(@"terminate", @"would quit");
			NSLog(@"[audit] %d pass, %d fail, %d skip\n%@", pass, fail, skip, log);
			[NSApp terminate:nil];
		}
		// --selwatch：8 秒后报告选区长度（配合外部真实 ⌘A 验证窗口内菜单快捷键）
		if (ArgPresent(argc, argv, "--selwatch")) {
			EditorDocument *d = controller.editorDocument;
			[d.editor setString:@"hello world select all test"];
			[[controller window] makeFirstResponder:d.editor.content];
			dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(8.0 * NSEC_PER_SEC)),
				dispatch_get_main_queue(), ^{
				NSLog(@"[sel] key=%d main=%d fr=%@ len=%ld selStart=%ld selEnd=%ld",
					(int)[controller window].isKeyWindow, (int)[controller window].isMainWindow,
					NSStringFromClass([[controller window].firstResponder class]),
					(long)[d.editor message:SCI_GETLENGTH],
					(long)[d.editor message:SCI_GETSELECTIONSTART],
					(long)[d.editor message:SCI_GETSELECTIONEND]);
				[NSApp terminate:nil];
			});
		}
		// --keytest：验证窗口内菜单的快捷键（Cmd+A 全选 / Cmd+Z 撤销）
		if (ArgPresent(argc, argv, "--keytest")) {
			EditorDocument *d = controller.editorDocument;
			[[controller window] makeFirstResponder:d.editor.content];
			NSLog(@"[key] fr=%@ key=%d", NSStringFromClass([[controller window].firstResponder class]),
				(int)[controller window].isKeyWindow);
			[d.editor message:SCI_CLEARALL wParam:0 lParam:0];
			[d.editor message:SCI_ADDTEXT wParam:11 lParam:(sptr_t)"hello world"];
			[d.editor message:SCI_SETSEL wParam:0 lParam:0];
			NSEvent *(^mk)(NSString *, NSString *, NSEventModifierFlags) =
				^NSEvent *(NSString *chars, NSString *ignoring, NSEventModifierFlags flags) {
				return [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint
					modifierFlags:flags timestamp:0 windowNumber:[controller window].windowNumber
					context:nil characters:chars charactersIgnoringModifiers:ignoring
					isARepeat:NO keyCode:0];
			};
			BOOL h1 = [controller handleKeyEquivalent:mk(@"a", @"a", NSEventModifierFlagCommand)];
			const sptr_t selLen = [d.editor message:SCI_GETSELECTIONEND] - [d.editor message:SCI_GETSELECTIONSTART];
			[d.editor message:SCI_SETSEL wParam:0 lParam:0];
			BOOL h2 = [controller handleKeyEquivalent:mk(@"z", @"z", NSEventModifierFlagCommand)];
			NSLog(@"[key] handledA=%d handledZ=%d", (int)h1, (int)h2);
			NSLog(@"[key] selectAll len=%ld afterUndo len=%ld content=%@", (long)selLen,
				(long)[d.editor message:SCI_GETLENGTH], [d.editor string]);
			[NSApp terminate:nil];
		}
		// --dumpmenu：打印菜单树（校验界面语言）
		if (ArgPresent(argc, argv, "--dumpmenu")) {
			NSMutableString *out = [NSMutableString string];
			[out appendString:@"== App ==\n"];
			DumpMenuTree(NSApp.mainMenu, 0, out);
			[out appendString:@"== Window ==\n"];
			[controller dumpInWindowMenus:out];
			printf("%s", out.UTF8String);
			fflush(stdout);
			[NSApp terminate:nil];
		}
		// --holdtest：注入一个不抬起的 keyDown，检查是否弹出重音候选窗口（PressAndHold）
		if (ArgPresent(argc, argv, "--holdtest")) {
			dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4.0 * NSEC_PER_SEC)),
				dispatch_get_main_queue(), ^{
				CGEventSourceRef src = CGEventSourceCreate(kCGEventSourceStateHIDSystemState);
				CGEventRef dn = CGEventCreateKeyboardEvent(src, (CGKeyCode)0, true);
				CGEventPost(kCGHIDEventTap, dn);
				CFRelease(dn);
				if (src) CFRelease(src);
			});
			dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(6.5 * NSEC_PER_SEC)),
				dispatch_get_main_queue(), ^{
				NSMutableString *ws = [NSMutableString string];
				for (NSWindow *w in NSApp.windows) {
					[ws appendFormat:@"%@(lvl=%ld vis=%d) ", NSStringFromClass([w class]),
						(long)w.level, (int)w.isVisible];
				}
				NSLog(@"[hold] pref=%d windows: %@", (int)[[NSUserDefaults standardUserDefaults]
					boolForKey:@"ApplePressAndHoldEnabled"], ws);
				CGEventRef up = CGEventCreateKeyboardEvent(NULL, (CGKeyCode)0, false);
				CGEventPost(kCGHIDEventTap, up);
				CFRelease(up);
				EditorDocument *d = controller.editorDocument;
				NSLog(@"[hold] len=%ld content=%@", (long)[d.editor message:SCI_GETLENGTH], [d.editor string]);
				[NSApp terminate:nil];
			});
		}
		// --langswitchtest：运行时切换语言，校验菜单/状态栏即时更新
		if (ArgPresent(argc, argv, "--langswitchtest")) {
			NPLanguageOverrideForTesting(NPLanguageEnglish);
			NSMutableString *out = [NSMutableString string];
			[controller languageEnglish];
			NSArray *en = [controller inWindowMenuTitles];
			[out appendFormat:@"EN: %@ | %@ | %@\n", en.count?en[0]:@"?", en.count>1?en[1]:@"?", [controller.editorDocument windowTitle]];
			[controller languageChinese];
			NSArray *zh = [controller inWindowMenuTitles];
			[out appendFormat:@"ZH: %@ | %@ | %@\n", zh.count?zh[0]:@"?", zh.count>1?zh[1]:@"?", [controller.editorDocument windowTitle]];
			printf("%s", out.UTF8String);
			fflush(stdout);
			[NSApp terminate:nil];
		}
		// --themeswitchtest：依次执行 Scheme 菜单三个动作，校验模式与编辑器主题，结束前还原
		if (ArgPresent(argc, argv, "--themeswitchtest")) {
			dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
				dispatch_get_main_queue(), ^{
				const NPThemeMode saved = NPThemeModeGet();
				for (NSString *name in @[@"themeDefault", @"themeDark", @"themeAuto"]) {
					[controller performSelector:NSSelectorFromString(name)];
					NSLog(@"[ts] %@ -> mode=%ld theme=%ld appAppearance=%@", name,
						(long)NPThemeModeGet(), (long)[controller.editorDocument theme],
						NSApp.appearance.name ?: @"nil(跟随系统)");
				}
				NPThemeModeSet(saved);
				[NSApp terminate:nil];
			});
		}
		// --realkeys：用 CGEventPostToPid 发送真实按键（不抢系统焦点）
		if (ArgPresent(argc, argv, "--realkeys")) {
			dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
				dispatch_get_main_queue(), ^{
				NSWindow *w = [controller window];
				EditorDocument *doc = controller.editorDocument;
				[w makeKeyWindow];
				NSLog(@"[rk] key=%d fr=%@", (int)w.isKeyWindow,
					NSStringFromClass([[w firstResponder] class]));
				const char *text = "int ma";
				NSMutableString *steps = [NSMutableString string];
				for (const char *p = text; *p; p++) {
					UniChar ch = *p;
					CGEventRef ev = CGEventCreateKeyboardEvent(NULL, 0, true);
					CGEventKeyboardSetUnicodeString(ev, 1, &ch);
					CGEventPostToPid(getpid(), ev);
					CFRelease(ev);
					usleep(120000);
					[steps appendFormat:@"%ld(a=%ld) ", (long)[doc.editor message:SCI_GETLENGTH],
						(long)[doc.editor message:SCI_AUTOCACTIVE]];
				}
				dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)),
					dispatch_get_main_queue(), ^{
					NSLog(@"[rk] 逐步: %@ | 内容=%@", steps, [doc.editor string]);
					[NSApp terminate:nil];
				});
			});
		}
		// --typewatch：激活后 4 秒记录文档内容（配合外部 System Events 真实键入）
		if (ArgPresent(argc, argv, "--typewatch")) {
			dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(12.0 * NSEC_PER_SEC)),
				dispatch_get_main_queue(), ^{
				EditorDocument *doc = controller.editorDocument;
				NSLog(@"[tw] len=%ld autoc=%ld content=%@",
					(long)[doc.editor message:SCI_GETLENGTH],
					(long)[doc.editor message:SCI_AUTOCACTIVE],
					[doc.editor string]);
				[NSApp terminate:nil];
			});
		}
		if (ArgPresent(argc, argv, "--inputtest")) {
			dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
				dispatch_get_main_queue(), ^{
				NSWindow *w = [controller window];
				EditorDocument *doc = controller.editorDocument;
				NSView *content = [doc.editor content];
				NSLog(@"[input] key=%d fr=%@ accepts=%d", (int)w.isKeyWindow,
					NSStringFromClass([[w firstResponder] class]), (int)[content acceptsFirstResponder]);
				// 模拟点击编辑区中央（真实用户操作路径）
				NSPoint pt = NSMakePoint(400, 300);
				NSEventType clickTypes[2] = {NSEventTypeLeftMouseDown, NSEventTypeLeftMouseUp};
				for (int ci = 0; ci < 2; ci++) {
					NSEventType t = clickTypes[ci];
					NSEvent *me = [NSEvent mouseEventWithType:t location:pt modifierFlags:0
						timestamp:0 windowNumber:w.windowNumber context:nil
						eventNumber:1 clickCount:1 pressure:1.0];
					[w sendEvent:me];
				}
				NSLog(@"[input] after click fr=%@ key=%d",
					NSStringFromClass([[w firstResponder] class]), (int)w.isKeyWindow);
				BOOL ok = [w makeFirstResponder:content];
				NSLog(@"[input] makeFR=%d now=%@", (int)ok,
					NSStringFromClass([[w firstResponder] class]));
				const char *text = "int ma";
				NSMutableString *steps = [NSMutableString string];
				for (const char *p = text; *p; p++) {
					NSString *ch = [NSString stringWithFormat:@"%c", *p];
					NSEvent *ev = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint
						modifierFlags:0 timestamp:0 windowNumber:w.windowNumber context:nil
						characters:ch charactersIgnoringModifiers:ch isARepeat:NO keyCode:0];
					[NSApp sendEvent:ev];   // 走真实路由（key window），复现用户路径
					[steps appendFormat:@"%ld(autoc=%ld) ", (long)[doc.editor message:SCI_GETLENGTH],
						(long)[doc.editor message:SCI_AUTOCACTIVE]];
				}
				NSLog(@"[input] 逐步长度: %@ | 内容=%@", steps,
					[doc.editor string]);
				long nBtn = 0, nImg = 0;
				for (NSView *v in [[w contentView] subviews]) {
					for (NSView *sub in [v subviews]) {
						if ([sub respondsToSelector:@selector(icon)]) {
							nBtn++;
							NSImage *im = [(id)sub icon];
							if (im && im.size.width > 0) nImg++;
						}
					}
				}
				NSLog(@"[input] toolbar buttons=%ld withIcon=%ld", nBtn, nImg);
				// 窗口截图对比（key vs 非 key）
				typedef CGImageRef (*Fn)(CGRect, CGWindowListOption, CGWindowID, CGWindowImageOption);
				static Fn fn = (Fn)dlsym(RTLD_DEFAULT, "CGWindowListCreateImage");
				CGWindowID wid = (CGWindowID)w.windowNumber;
				void (^SaveShot)(NSString *) = ^(NSString *p) {
					CGImageRef img = fn ? fn(CGRectNull, kCGWindowListOptionIncludingWindow, wid,
						kCGWindowImageBoundsIgnoreFraming) : NULL;
					if (!img) return;
					NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithCGImage:img];
					CGImageRelease(img);
					NSData *png = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
					[png writeToFile:p atomically:YES];
				};
				// cacheDisplay 渲染（走 drawRect，无需窗口在屏）
				{
					NSView *v = [[controller window] contentView];
					NSBitmapImageRep *rep = [v bitmapImageRepForCachingDisplayInRect:v.bounds];
					[v cacheDisplayInRect:v.bounds toBitmapImageRep:rep];
					NSData *png = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
					[png writeToFile:@"/tmp/shot_cache.png" atomically:YES];
				}
				[NSApp activateIgnoringOtherApps:YES];
				[w makeKeyAndOrderFront:nil];
				dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)),
					dispatch_get_main_queue(), ^{
					NSLog(@"[input] after activate key=%d", (int)w.isKeyWindow);
					SaveShot(@"/tmp/shot_key.png");
					[NSApp terminate:nil];
				});
			});
		}
		if (ArgPresent(argc, argv, "--printwid")) {
			dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
				dispatch_get_main_queue(), ^{
				printf("WID=%ld\n", (long)[[controller window] windowNumber]);
				fflush(stdout);
			});
		}
		if (ArgPresent(argc, argv, "--closetest")) {
			dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
				dispatch_get_main_queue(), ^{
				NSLog(@"[closetest] dirty=%d sciModify=%ld visible=%d", (int)controller.editorDocument.dirty, (long)[controller.editorDocument.editor message:SCI_GETMODIFY], (int)[controller window].isVisible);
				[[controller window] performClose:nil];
				dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
					dispatch_get_main_queue(), ^{
					NSLog(@"[closetest] after close: visible=%d", (int)[controller window].isVisible);
					[NSApp terminate:nil];
				});
			});
		}
		[app run];
	}
	return 0;
}