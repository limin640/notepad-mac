// 把预览导出为 HTML / PDF / PNG / Word（DOCX）
#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, NPExportFormat) {
	NPExportHTML = 0,
	NPExportPDF,
	NPExportPNG,
	NPExportDOCX,
};

@interface PreviewExport : NSObject
+ (NPExportFormat)formatFromPath:(NSString *)path;
+ (NSData *)dataFromMarkdown:(NSString *)markdown html:(NSString *)html
	format:(NPExportFormat)fmt dark:(BOOL)dark;
+ (BOOL)writeData:(NSData *)data toURL:(NSURL *)url error:(NSError **)err;
+ (BOOL)copyPreviewLibrariesBesideHTMLURL:(NSURL *)url error:(NSError **)err;
@end
