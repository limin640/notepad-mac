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
		[win makeKeyAndOrderFront:nil];
		[win orderFrontRegardless];
		[controller showWindow:nil];
		[app activateIgnoringOtherApps:YES];

		InjectTestContent(argc, argv, controller);

		if (argc >= 3 && strcmp(argv[1], "--shot") == 0) {
			double delay = 3.0;
			if (const char *d = ArgValue(argc, argv, "--delay")) delay = atof(d);
			dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)),
				dispatch_get_main_queue(), ^{
				NSString *path = [NSString stringWithUTF8String:argv[2]];
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
		if (argc >= 2 && strcmp(argv[1], "--printwid") == 0) {
			dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
				dispatch_get_main_queue(), ^{
				printf("WID=%ld\n", (long)[[controller window] windowNumber]);
				fflush(stdout);
			});
		}
		if (argc >= 2 && strcmp(argv[1], "--closetest") == 0) {
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
