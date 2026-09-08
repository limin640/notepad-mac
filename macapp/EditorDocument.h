#import <Cocoa/Cocoa.h>
#import "ScintillaView.h"

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

- (void)applyLexerForExtension:(nullable NSString *)ext;

// 编码：重解码（保留未保存修改则确认丢弃）/ 设保存编码
- (void)reloadWithEncoding:(NSString *)encodingName;
- (void)setSaveEncoding:(NSString *)encodingName;
- (NSString *)currentEncoding;
@property (nonatomic, readonly, nullable) const EDITLEXER *currentLexer;
- (NSString *)windowTitle;

@end
