// Markdown / HTML 预览：左侧源码可编辑，右侧即时渲染
// HTML 预览可直接改并写回源码；Markdown 预览只读（所见即所得回写会丢掉源码）
#import <Cocoa/Cocoa.h>

@class EditorDocument;

typedef NS_ENUM(NSInteger, NPPreviewKind) {
	NPPreviewNone = 0,
	NPPreviewMarkdown,
	NPPreviewHTML,
	NPPreviewImage,
};

@interface PreviewPane : NSView
@property (nonatomic, copy) void (^onHTMLEdited)(NSString *html);
@property (nonatomic, copy) void (^onPreviewScroll)(NSInteger srcLine, CGFloat frac);
@property (nonatomic, copy) void (^onOutlineToggle)(BOOL on);
+ (NPPreviewKind)kindForDocument:(EditorDocument *)doc;
+ (NSString *)htmlFromMarkdown:(NSString *)markdown;
+ (NSString *)htmlForDocument:(EditorDocument *)doc;
+ (NSString *)pageHTMLFromMarkdown:(NSString *)markdown dark:(BOOL)dark outline:(BOOL)outline;
+ (NSString *)wrapPreviewBody:(NSString *)body dark:(BOOL)dark kind:(NPPreviewKind)kind
	editable:(BOOL)editable outline:(BOOL)outline;
+ (NSArray<NSDictionary *> *)outlineFromMarkdown:(NSString *)markdown;
+ (NSURL *)previewLibraryURL;
+ (NSURL *)previewBaseURLForDocument:(EditorDocument *)doc;
+ (NSString *)inPlaceRefreshJavaScriptWithBody:(NSString *)body;
+ (BOOL)hasLocalPreviewLibraries;
- (void)refreshDocument:(EditorDocument *)doc dark:(BOOL)dark;
- (void)setOutlineVisible:(BOOL)on;
- (BOOL)outlineVisible;
- (void)foldPreviewOutline:(BOOL)fold;
- (NSString *)lastHTML;
- (NSString *)lastPageHTML;
- (NSURL *)lastPreviewBaseURL;
- (BOOL)lastRefreshInPlace;
- (BOOL)lastRefreshDidScroll;
- (BOOL)previewUsesLineMap;
- (NSInteger)lastSyncLine;
- (CGFloat)lastSyncFrac;
- (void)scrollPreviewToSourceLine:(NSInteger)line lineCount:(NSInteger)lineCount;
- (void)scrollPreviewToFraction:(CGFloat)frac;
- (void)shutdown;
@end
