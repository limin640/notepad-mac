#import <Cocoa/Cocoa.h>
#import "ScintillaView.h"
#import "NPTheme.h"

struct EDITLEXER;

@interface EditorDocument : NSObject <ScintillaNotificationProtocol>

@property (nonatomic, strong, readonly) ScintillaView *editor;
@property (nonatomic, copy, nullable) NSURL *fileURL;
@property (nonatomic, readonly) BOOL dirty;
@property (nonatomic, copy) NSString *tabTitle;

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithNewUntitled:(NSInteger)sequence;
- (instancetype)initWithFileURL:(NSURL *)url contents:(NSString *)contents;

- (BOOL)loadFromURL:(NSURL *)url error:(NSError * _Nullable * _Nullable)error;
- (BOOL)saveToURL:(NSURL *)url error:(NSError * _Nullable * _Nullable)error;
// updateIdentity=NO：备份/副本写出，不改当前路径
- (BOOL)writeContentsToURL:(NSURL *)url updateIdentity:(BOOL)update error:(NSError * _Nullable * _Nullable)error;
- (void)completeWord;

- (void)applyLexerForExtension:(nullable NSString *)ext;

// 编码：重解码（保留未保存修改则确认丢弃）/ 设保存编码
- (void)reloadWithEncoding:(NSString *)encodingName;
- (void)setSaveEncoding:(NSString *)encodingName;
- (NSString *)currentEncoding;
- (void)setTheme:(NPThemeKind)theme;
- (NPThemeKind)theme;
@property (nonatomic, readonly, nullable) const EDITLEXER *currentLexer;
- (NSString *)windowTitle;

@end
