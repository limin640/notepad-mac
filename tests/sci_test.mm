// 最小验证程序：实例化 ScintillaView，跑通 内核+cocoa 静态库 链接。
#import <Cocoa/Cocoa.h>
#import "ScintillaView.h"
#import "ILexer.h"
#import "LexerModule.h"
// notepad4 fork 的词法器模块（lmCPP 在 LexCPP.cxx）
extern const Lexilla::LexerModule lmCPP;

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        [app setActivationPolicy:NSApplicationActivationPolicyRegular];

        NSWindow *win = [[NSWindow alloc]
            initWithContentRect:NSMakeRect(0, 0, 900, 600)
            styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                       NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable)
            backing:NSBackingStoreBuffered defer:NO];
        win.title = @"Scintilla Cocoa Smoke Test";

        ScintillaView *editor = [[ScintillaView alloc] initWithFrame:NSMakeRect(0, 0, 900, 600)];
        [editor message:SCI_SETILEXER wParam:0 lParam:(sptr_t)lmCPP.Create()];
        [editor message:SCI_SETTEXT wParam:0 lParam:(sptr_t)
            "// Notepad4-mac smoke test\n#include <stdio.h>\nint main() { return 0; }\n"];
        win.contentView = editor;

        [win makeKeyAndOrderFront:nil];
        [app activateIgnoringOtherApps:YES];
        [app run];
    }
    return 0;
}
