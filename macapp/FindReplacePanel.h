// 查找替换面板（挂主窗口底部，⌘F/⌥⌘F）
#import <Cocoa/Cocoa.h>

@class EditorDocument;

@interface FindReplacePanel : NSView <NSTextFieldDelegate>

- (void)attachToWindow:(NSWindow *)window;
- (void)applyLanguage;   // 切换界面语言后重建文本
- (void)showFind:(BOOL)replaceVisible;
- (void)toggle;

// 查找方向控制
- (void)findNext:(EditorDocument *)doc;
- (void)findPrevious:(EditorDocument *)doc;
- (void)replaceAll:(EditorDocument *)doc;
- (void)replaceOne:(EditorDocument *)doc;

@end
