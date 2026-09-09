// 主窗口控制器（单文档，复刻 Windows 版 Notepad4 布局）
#import <Cocoa/Cocoa.h>
#import "EditorDocument.h"

@interface MainWindowController : NSWindowController <NSWindowDelegate>

@property (nonatomic, strong) EditorDocument *editorDocument;

- (void)refreshStatus;
- (void)updateWindowTitle;

@end
