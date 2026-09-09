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

static void DumpViewTree(NSView *v, int depth, NSMutableString *tree) {
	[tree appendFormat:@"%@%@ f=%@ tam=%d\n", [[NSString alloc] initWithFormat:@"%*s", depth*2, ""],
		NSStringFromClass(v.class), NSStringFromRect(v.frame), (int)v.translatesAutoresizingMaskIntoConstraints];
	for (NSView *sub in v.subviews) DumpViewTree(sub, depth + 1, tree);
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
					}
				} else if ([path hasSuffix:@".pdf"]) {
					NSView *v = [[controller window] contentView];
					NSData *pdf = [v dataWithPDFInsideRect:v.bounds];
					[pdf writeToFile:path atomically:YES];
				}
				[NSApp terminate:nil];
			});
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
