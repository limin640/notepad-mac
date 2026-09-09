// 状态栏：复刻 Windows 版分区（Ln, Col, Ch, Sel, Lexer, Zoom, Size, Enc, EOL）
#import <Cocoa/Cocoa.h>

@class EditorDocument;

@interface StatusBarView : NSView

- (void)applyLanguage;   // 切换界面语言后重建文本
- (void)updateForDocument:(nullable EditorDocument *)doc;

@property (nonatomic, readonly) NSTextField *posField;      // 行,列 (字符,选择)
@property (nonatomic, readonly) NSTextField *lexerField;    // 词法器名
@property (nonatomic, readonly) NSTextField *zoomField;     // 缩放%
@property (nonatomic, readonly) NSTextField *sizeField;     // 文档大小
@property (nonatomic, readonly) NSTextField *encField;      // 编码
@property (nonatomic, readonly) NSTextField *eolField;      // CRLF/LF

@end
