#import <Cocoa/Cocoa.h>
#import "ScintillaView.h"

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
- (NSString *)windowTitle;

@end
