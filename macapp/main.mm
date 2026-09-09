// 程序入口 + 调试钩子
// 钩子（仅测试用）：
//   --code <src> [--ext cpp] [--find needle] [--theme dark]   注入文本并应用词法器
//   --appearance light|dark                                    强制外观（验证两种模式）
//   --shot <path.(png|pdf|txt)> [--delay N]                    延迟后自截窗口并退出
//   --printwid                                                 打印窗口号（外部 screencapture -l 用）
//   --closetest                                                验证关闭窗口行为
#import <Cocoa/Cocoa.h>
#import <CoreGraphics/CoreGraphics.h>
#include <dlfcn.h>
#import "MainWindowController.h"
#import "EditorDocument.h"
#import "NPTheme.h"
#import "NPLocalization.h"

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
		NSApplication *app = [NSApplication sharedApplication];
		[app setActivationPolicy:NSApplicationActivationPolicyRegular];

		// 关闭 macOS「按住键出重音候选」：否则按住字母键只出一个字（数字不受影响）
		// 与 VS Code / iTerm 等做法一致，只写本应用域，不动全局设置
		NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
		if ([ud objectForKey:@"ApplePressAndHoldEnabled"] == nil) {
			[ud setBool:NO forKey:@"ApplePressAndHoldEnabled"];
		}

		// --lang zh|en：进程内覆盖界面语言，不写盘（测试用）
		if (const char *lg = ArgValue(argc, argv, "--lang")) {
			NPLanguageOverrideForTesting(strcmp(lg, "en") == 0 ? NPLanguageEnglish : NPLanguageChinese);
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
		NSWindow *win = [controller window];
		win.collectionBehavior = NSWindowCollectionBehaviorMoveToActiveSpace;
		NSRect sf = [NSScreen mainScreen].visibleFrame;
		[win setFrameTopLeftPoint:NSMakePoint(sf.origin.x + 80, sf.origin.y + sf.size.height - 40)];
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
			NSMutableString *mbTitles = [NSMutableString string];
			for (NSView *v in controller.window.contentView.subviews) {
				if (v.frame.size.height > 24) continue;
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
			NSLog(@"[fn] inv=%@ title=%@ word=%ld-%ld brace=%ld-%ld cmtHas=%d autoc=%ld bak=%d fav=%d menus=%@",
				afterInv, afterTitle, (long)sw0, (long)sw1, (long)br0, (long)br1,
				(int)([afterCmt containsString:@"//int"] || [afterCmt containsString:@"// int"]),
				(long)autoc, (int)bakOK, (int)favOK, mbTitles);
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
