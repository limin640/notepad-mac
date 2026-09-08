// 主窗口控制器：标签页 + 编辑器容器 + 菜单栏
#import <Cocoa/Cocoa.h>
#import "EditorDocument.h"

@interface MainWindowController : NSWindowController <NSTabViewDelegate, NSWindowDelegate>

- (void)newTab;
- (void)openDocument;
- (BOOL)saveDocument;
- (BOOL)saveDocumentAs;
- (void)closeTab;
- (void)refreshStatus;
- (nullable EditorDocument *)currentDocument;

@end
