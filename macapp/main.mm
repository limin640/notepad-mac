// 程序入口
#import <Cocoa/Cocoa.h>
#import <CoreGraphics/CoreGraphics.h>
#include <dlfcn.h>
#import "MainWindowController.h"
#import "EditorDocument.h"
#import "NPTheme.h"

#import <memory>


static void DumpViewTree(NSView *v, int depth, NSMutableString *tree) {
	[tree appendFormat:@"%@%@ f=%@ tam=%d\n", [[NSString alloc] initWithFormat:@"%*s", depth*2, ""],
		NSStringFromClass(v.class), NSStringFromRect(v.frame), (int)v.translatesAutoresizingMaskIntoConstraints];
	for (NSView *sub in v.subviews) DumpViewTree(sub, depth + 1, tree);
}

int main(int argc, const char *argv[]) {
	@autoreleasepool {
		NSApplication *app = [NSApplication sharedApplication];
		[app setActivationPolicy:NSApplicationActivationPolicyRegular];
		// 强引用：窗口控制器必须活过 run loop
		static MainWindowController *controller;
		controller = [[MainWindowController alloc] init];
		NSWindow *win = [controller window];
		win.collectionBehavior = NSWindowCollectionBehaviorMoveToActiveSpace;
		// 固定主屏左上角，避免 offscreen
		NSRect sf = [NSScreen mainScreen].visibleFrame;
		NSRect wf = win.frame;
		[win setFrameTopLeftPoint:NSMakePoint(sf.origin.x + 80, sf.origin.y + sf.size.height - 40)];
		[win makeKeyAndOrderFront:nil];
		[win orderFrontRegardless];
		[controller showWindow:nil];

		[app activateIgnoringOtherApps:YES];

		// 调试钩子：--shot <path> [--code] 3 秒后自截窗口再退出
		if (argc >= 3 && strcmp(argv[1], "--shot") == 0) {
			NSLog(@"[hook] shot mode, argc=%d", argc);
			if (argc >= 5 && strcmp(argv[3], "--code") == 0) {
				NSLog(@"[hook] injecting code ext=%s", (argc >= 7) ? argv[6] : "(default cpp)");
				EditorDocument *doc = [controller document];
				[doc.editor setString:[NSString stringWithUTF8String:argv[4]]];
				NSString *ext = @"cpp";
				// --code <src> [--ext py] [--find needle]
				NSString *needle = nil;
				BOOL darkTheme = NO;
				for (int i = 5; i < argc - 1; i++) {
					if (strcmp(argv[i], "--ext") == 0) ext = [NSString stringWithUTF8String:argv[i+1]];
					if (strcmp(argv[i], "--find") == 0) needle = [NSString stringWithUTF8String:argv[i+1]];
					if (strcmp(argv[i], "--theme") == 0) darkTheme = (strcmp(argv[i+1], "dark") == 0);
				}
				if (darkTheme) [doc setTheme:NPThemeDark];
				[doc applyLexerForExtension:ext];
				[controller refreshStatus];
				NSLog(@"[diag] codepage=%ld len=%ld", (long)[doc.editor message:SCI_GETCODEPAGE], (long)[doc.editor message:SCI_GETLENGTH]);
				if (needle.length) {
					// 模拟 ⌘F 面板查找（直接走 target 搜索）
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
			dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)),
				dispatch_get_main_queue(), ^{
				// CGWindowListCreateImage 抓整窗（含工具栏/标签页渲染）
				NSString *path = [NSString stringWithUTF8String:argv[2]];
				if ([path.pathExtension isEqualToString:@"txt"]) {
					NSMutableString *tree = [NSMutableString string];
					DumpViewTree([[controller window] contentView], 0, tree);
					[tree writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
				} else if ([path hasSuffix:@".png"]) {
					// 按窗口 ID 抓图（不受遮挡影响）；CGWindowListCreateImage 在 macOS 15 标记弃用，用 dlsym 取符号
					typedef CGImageRef (*Fn)(CGRect, CGWindowListOption, CGWindowID, CGWindowImageOption);
					static Fn fn = (Fn)dlsym(RTLD_DEFAULT, "CGWindowListCreateImage");
					CGWindowID wid = (CGWindowID)[[controller window] windowNumber];
					CGImageRef img = fn ? fn(CGRectNull, kCGWindowListOptionIncludingWindow, wid, kCGWindowImageDefault) : NULL;
					if (img) {
						NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithCGImage:img];
						CGImageRelease(img);
						NSData *png = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
						[png writeToFile:path atomically:YES];
					}
				} else if ([path hasSuffix:@".pdf"]) {
					NSView *v = [[controller window] contentView];
					NSBitmapImageRep *rep = [v bitmapImageRepForCachingDisplayInRect:v.bounds];
					[v cacheDisplayInRect:v.bounds toBitmapImageRep:rep];
					NSData *png = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
					[png writeToFile:path atomically:YES];
				}
				[NSApp terminate:nil];
			});
		}
		[app run];
	}
	return 0;
}
