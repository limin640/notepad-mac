// 当前文件所在目录的可开关文件树，点击打开
#import <Cocoa/Cocoa.h>

@interface FileTreePane : NSView
@property (nonatomic, copy) void (^onOpenFile)(NSURL *url);
- (void)showDirectory:(NSURL *)dir selected:(NSURL *)file;
- (NSURL *)rootURL;
- (NSArray<NSString *> *)visibleNames;
- (BOOL)selectAndOpenName:(NSString *)name;
@end
