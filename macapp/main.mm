// 程序入口
#import <Cocoa/Cocoa.h>
#import "MainWindowController.h"
#import "EditorDocument.h"

#import <memory>

int main(int argc, const char *argv[]) {
	@autoreleasepool {
		NSApplication *app = [NSApplication sharedApplication];
		[app setActivationPolicy:NSApplicationActivationPolicyRegular];
		// 强引用：窗口控制器必须活过 run loop
		static MainWindowController *controller;
		controller = [[MainWindowController alloc] init];
		[controller window].collectionBehavior = NSWindowCollectionBehaviorFullScreenAuxiliary;
		[[controller window] makeKeyAndOrderFront:nil];
		[controller showWindow:nil];

		[app activateIgnoringOtherApps:YES];

		// 调试钩子：--shot <path> [--code] 3 秒后自截窗口再退出
		if (argc >= 3 && strcmp(argv[1], "--shot") == 0) {
			if (argc >= 5 && strcmp(argv[3], "--code") == 0) {
				EditorDocument *doc = [controller currentDocument];
				[doc.editor setString:[NSString stringWithUTF8String:argv[4]]];
				[doc applyLexerForExtension:@"cpp"];
			}
			dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)),
				dispatch_get_main_queue(), ^{
				NSData *tiff = [[[controller window] contentView] dataWithPDFInsideRect:[[[controller window] contentView] bounds]];
				[tiff writeToFile:[NSString stringWithUTF8String:argv[2]] atomically:YES];
				[NSApp terminate:nil];
			});
		}
		[app run];
	}
	return 0;
}
