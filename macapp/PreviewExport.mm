#import "PreviewExport.h"
#import "PreviewPane.h"
#import <AppKit/AppKit.h>
#import <CoreText/CoreText.h>

typedef NS_ENUM(NSInteger, NPBlockKind) {
	NPBlockP = 0,
	NPBlockH,
	NPBlockLI,
	NPBlockPre,
	NPBlockQuote,
	NPBlockMath,
};

@interface NPExportBlock : NSObject
@property (nonatomic) NPBlockKind kind;
@property (nonatomic) NSInteger level;
@property (nonatomic, copy) NSString *text;
@end
@implementation NPExportBlock
@end

static NSString *NPUnescapeHTML(NSString *s) {
	if (s.length == 0) return @"";
	NSMutableString *o = [s mutableCopy];
	[o replaceOccurrencesOfString:@"&lt;" withString:@"<" options:0 range:NSMakeRange(0, o.length)];
	[o replaceOccurrencesOfString:@"&gt;" withString:@">" options:0 range:NSMakeRange(0, o.length)];
	[o replaceOccurrencesOfString:@"&quot;" withString:@"\"" options:0 range:NSMakeRange(0, o.length)];
	[o replaceOccurrencesOfString:@"&amp;" withString:@"&" options:0 range:NSMakeRange(0, o.length)];
	return o;
}

static NSString *NPStripTags(NSString *s) {
	if (s.length == 0) return @"";
	NSMutableString *o = [s mutableCopy];
	[o replaceOccurrencesOfString:@"<br>" withString:@"\n" options:NSCaseInsensitiveSearch range:NSMakeRange(0, o.length)];
	[o replaceOccurrencesOfString:@"<br/>" withString:@"\n" options:NSCaseInsensitiveSearch range:NSMakeRange(0, o.length)];
	[o replaceOccurrencesOfString:@"<br />" withString:@"\n" options:NSCaseInsensitiveSearch range:NSMakeRange(0, o.length)];
	NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"<[^>]+>" options:0 error:nil];
	if (re) o = [[re stringByReplacingMatchesInString:o options:0 range:NSMakeRange(0, o.length) withTemplate:@""] mutableCopy];
	return NPUnescapeHTML(o);
}

static NSString *NPXMLEscape(NSString *s) {
	if (s.length == 0) return @"";
	NSMutableString *o = [s mutableCopy];
	[o replaceOccurrencesOfString:@"&" withString:@"&amp;" options:0 range:NSMakeRange(0, o.length)];
	[o replaceOccurrencesOfString:@"<" withString:@"&lt;" options:0 range:NSMakeRange(0, o.length)];
	[o replaceOccurrencesOfString:@">" withString:@"&gt;" options:0 range:NSMakeRange(0, o.length)];
	[o replaceOccurrencesOfString:@"\"" withString:@"&quot;" options:0 range:NSMakeRange(0, o.length)];
	return o;
}

static NSArray<NPExportBlock *> *NPBlocksFromHTML(NSString *html) {
	NSMutableArray *out = [NSMutableArray array];
	if (html.length == 0) return out;
	NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:
		@"<(h([1-6])|p|li|pre|blockquote|div)\\b([^>]*)>([\\s\\S]*?)</\\1>"
		options:NSRegularExpressionCaseInsensitive error:nil];
	if (!re) return out;
	NSArray *ms = [re matchesInString:html options:0 range:NSMakeRange(0, html.length)];
	for (NSTextCheckingResult *m in ms) {
		if (m.numberOfRanges < 5) continue;
		NSString *tag = [[html substringWithRange:[m rangeAtIndex:1]] lowercaseString];
		NSString *inner = [html substringWithRange:[m rangeAtIndex:4]];
		NSString *attrs = [html substringWithRange:[m rangeAtIndex:3]];
		NPExportBlock *b = [NPExportBlock new];
		if ([tag hasPrefix:@"h"]) {
			b.kind = NPBlockH;
			b.level = [[html substringWithRange:[m rangeAtIndex:2]] integerValue];
		} else if ([tag isEqualToString:@"li"]) {
			b.kind = NPBlockLI;
		} else if ([tag isEqualToString:@"pre"]) {
			b.kind = NPBlockPre;
		} else if ([tag isEqualToString:@"blockquote"]) {
			b.kind = NPBlockQuote;
		} else if ([tag isEqualToString:@"div"] && [attrs containsString:@"np4-math"]) {
			b.kind = NPBlockMath;
		} else if ([tag isEqualToString:@"p"]) {
			b.kind = NPBlockP;
		} else {
			continue;
		}
		b.text = NPStripTags(inner);
		if (b.text.length == 0) continue;
		[out addObject:b];
	}
	if (out.count == 0 && html.length) {
		NPExportBlock *b = [NPExportBlock new];
		b.kind = NPBlockP;
		b.text = NPStripTags(html);
		if (b.text.length) [out addObject:b];
	}
	return out;
}

static uint32_t NPCRC32(NSData *d) {
	uint32_t crc = 0xffffffffu;
	const uint8_t *p = (const uint8_t *)d.bytes;
	const NSUInteger n = d.length;
	for (NSUInteger i = 0; i < n; i++) {
		crc ^= p[i];
		for (int k = 0; k < 8; k++)
			crc = (crc >> 1) ^ (0xEDB88320u & (uint32_t)(-(int)(crc & 1)));
	}
	return crc ^ 0xffffffffu;
}

static void NPAppendU16(NSMutableData *o, uint16_t v) {
	uint8_t b[2] = { (uint8_t)(v & 0xff), (uint8_t)((v >> 8) & 0xff) };
	[o appendBytes:b length:2];
}
static void NPAppendU32(NSMutableData *o, uint32_t v) {
	uint8_t b[4] = { (uint8_t)(v & 0xff), (uint8_t)((v >> 8) & 0xff),
		(uint8_t)((v >> 16) & 0xff), (uint8_t)((v >> 24) & 0xff) };
	[o appendBytes:b length:4];
}

static NSData *NPZipStore(NSDictionary<NSString *, NSData *> *files) {
	NSMutableData *out = [NSMutableData data];
	NSMutableData *central = [NSMutableData data];
	NSArray *names = [[files allKeys] sortedArrayUsingSelector:@selector(compare:)];
	uint16_t n = 0;
	for (NSString *name in names) {
		NSData *body = files[name];
		if (body == nil) continue;
		NSData *nameData = [name dataUsingEncoding:NSUTF8StringEncoding];
		uint32_t crc = NPCRC32(body);
		uint32_t sz = (uint32_t)body.length;
		uint32_t off = (uint32_t)out.length;
		NPAppendU32(out, 0x04034b50);
		NPAppendU16(out, 20);
		NPAppendU16(out, 0);
		NPAppendU16(out, 0);
		NPAppendU16(out, 0);
		NPAppendU16(out, 0);
		NPAppendU32(out, crc);
		NPAppendU32(out, sz);
		NPAppendU32(out, sz);
		NPAppendU16(out, (uint16_t)nameData.length);
		NPAppendU16(out, 0);
		[out appendData:nameData];
		[out appendData:body];
		NPAppendU32(central, 0x02014b50);
		NPAppendU16(central, 20);
		NPAppendU16(central, 20);
		NPAppendU16(central, 0);
		NPAppendU16(central, 0);
		NPAppendU16(central, 0);
		NPAppendU16(central, 0);
		NPAppendU32(central, crc);
		NPAppendU32(central, sz);
		NPAppendU32(central, sz);
		NPAppendU16(central, (uint16_t)nameData.length);
		NPAppendU16(central, 0);
		NPAppendU16(central, 0);
		NPAppendU16(central, 0);
		NPAppendU16(central, 0);
		NPAppendU32(central, 0);
		NPAppendU32(central, off);
		[central appendData:nameData];
		n += 1;
	}
	uint32_t centralOff = (uint32_t)out.length;
	[out appendData:central];
	uint32_t centralSz = (uint32_t)central.length;
	NPAppendU32(out, 0x06054b50);
	NPAppendU16(out, 0);
	NPAppendU16(out, 0);
	NPAppendU16(out, n);
	NPAppendU16(out, n);
	NPAppendU32(out, centralSz);
	NPAppendU32(out, centralOff);
	NPAppendU16(out, 0);
	return out;
}

static NSAttributedString *NPAttrFromBlocks(NSArray<NPExportBlock *> *blocks, BOOL dark) {
	NSMutableAttributedString *a = [[NSMutableAttributedString alloc] init];
	NSColor *fg = dark ? [NSColor colorWithWhite:0.9 alpha:1] : [NSColor colorWithWhite:0.12 alpha:1];
	for (NPExportBlock *b in blocks) {
		CGFloat size = 12;
		BOOL bold = NO;
		if (b.kind == NPBlockH) {
			size = (CGFloat)MAX(14, 26 - b.level * 2);
			bold = YES;
		} else if (b.kind == NPBlockPre || b.kind == NPBlockMath) {
			size = 11;
		}
		NSFont *font = bold ? [NSFont boldSystemFontOfSize:size]
			: ((b.kind == NPBlockPre || b.kind == NPBlockMath)
				? [NSFont fontWithName:@"Menlo" size:size] ?: [NSFont monospacedSystemFontOfSize:size weight:NSFontWeightRegular]
				: [NSFont systemFontOfSize:size]);
		NSString *prefix = (b.kind == NPBlockLI) ? @"• " : (b.kind == NPBlockQuote ? @"| " : @"");
		NSString *line = [NSString stringWithFormat:@"%@%@\n", prefix, b.text];
		NSDictionary *attrs = @{
			NSFontAttributeName: font,
			NSForegroundColorAttributeName: fg,
		};
		[a appendAttributedString:[[NSAttributedString alloc] initWithString:line attributes:attrs]];
	}
	return a;
}

static NSData *NPPDFFromBlocks(NSArray<NPExportBlock *> *blocks, BOOL dark) {
	NSAttributedString *attr = NPAttrFromBlocks(blocks, dark);
	const CGFloat W = 612, H = 792, inset = 48;
	NSMutableData *data = [NSMutableData data];
	CGDataConsumerRef cons = CGDataConsumerCreateWithCFData((CFMutableDataRef)data);
	CGRect box = CGRectMake(0, 0, W, H);
	CGContextRef ctx = CGPDFContextCreate(cons, &box, NULL);
	CGDataConsumerRelease(cons);
	if (!ctx) return [@"%PDF-1.4\n%%EOF\n" dataUsingEncoding:NSASCIIStringEncoding];
	CTFramesetterRef fs = CTFramesetterCreateWithAttributedString((CFAttributedStringRef)attr);
	CFIndex start = 0;
	const CFIndex total = (CFIndex)attr.length;
	NSColor *bg = dark ? [NSColor colorWithWhite:0.12 alpha:1] : [NSColor whiteColor];
	while (start < total) {
		CGPDFContextBeginPage(ctx, NULL);
		CGContextSetFillColorWithColor(ctx, bg.CGColor);
		CGContextFillRect(ctx, box);
		CGContextSaveGState(ctx);
		CGContextTranslateCTM(ctx, 0, H);
		CGContextScaleCTM(ctx, 1, -1);
		CGRect textBox = CGRectMake(inset, inset, W - inset * 2, H - inset * 2);
		CGMutablePathRef path = CGPathCreateMutable();
		CGPathAddRect(path, NULL, textBox);
		CTFrameRef frame = CTFramesetterCreateFrame(fs, CFRangeMake(start, 0), path, NULL);
		CTFrameDraw(frame, ctx);
		CFRange vis = CTFrameGetVisibleStringRange(frame);
		CFRelease(frame);
		CGPathRelease(path);
		CGContextRestoreGState(ctx);
		CGPDFContextEndPage(ctx);
		if (vis.length == 0) break;
		start += vis.length;
	}
	CFRelease(fs);
	CGPDFContextClose(ctx);
	CGContextRelease(ctx);
	return data;
}

static NSData *NPPNGFromBlocks(NSArray<NPExportBlock *> *blocks, BOOL dark) {
	NSAttributedString *attr = NPAttrFromBlocks(blocks, dark);
	const CGFloat W = 720, inset = 24, maxH = 12000;
	CGRect bounds = [attr boundingRectWithSize:NSMakeSize(W - inset * 2, maxH)
		options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading context:nil];
	CGFloat H = MIN(maxH, ceil(bounds.size.height) + inset * 2);
	if (H < 64) H = 64;
	NSBitmapImageRep *rep = [[NSBitmapImageRep alloc]
		initWithBitmapDataPlanes:NULL pixelsWide:(NSInteger)W pixelsHigh:(NSInteger)H
		bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
		colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
	NSGraphicsContext *gc = [NSGraphicsContext graphicsContextWithBitmapImageRep:rep];
	[NSGraphicsContext saveGraphicsState];
	[NSGraphicsContext setCurrentContext:gc];
	[(dark ? [NSColor colorWithWhite:0.12 alpha:1] : [NSColor whiteColor]) setFill];
	NSRectFill(NSMakeRect(0, 0, W, H));
	[attr drawWithRect:NSMakeRect(inset, inset, W - inset * 2, H - inset * 2)
		options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading];
	[NSGraphicsContext restoreGraphicsState];
	return [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] ?: [NSData data];
}

static NSData *NPDOCXFromBlocks(NSArray<NPExportBlock *> *blocks) {
	NSMutableString *body = [NSMutableString string];
	for (NPExportBlock *b in blocks) {
		NSString *style = @"Normal";
		if (b.kind == NPBlockH && b.level >= 1 && b.level <= 6)
			style = [NSString stringWithFormat:@"Heading%ld", (long)b.level];
		else if (b.kind == NPBlockPre || b.kind == NPBlockMath)
			style = @"Code";
		else if (b.kind == NPBlockQuote)
			style = @"Quote";
		else if (b.kind == NPBlockLI)
			style = @"List";
		NSString *t = NPXMLEscape(b.text);
		[t enumerateLinesUsingBlock:^(NSString *line, BOOL *stop) {
			(void)stop;
			[body appendFormat:
				@"<w:p><w:pPr><w:pStyle w:val=\"%@\"/></w:pPr><w:r><w:t xml:space=\"preserve\">%@</w:t></w:r></w:p>",
				style, line];
		}];
	}
	if (body.length == 0)
		[body appendString:@"<w:p><w:r><w:t></w:t></w:r></w:p>"];
	NSString *doc = [NSString stringWithFormat:
		@"<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>"
		@"<w:document xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\">"
		@"<w:body>%@<w:sectPr><w:pgSz w:w=\"12240\" w:h=\"15840\"/></w:sectPr></w:body></w:document>",
		body];
	NSString *types =
		@"<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>"
		@"<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\">"
		@"<Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/>"
		@"<Default Extension=\"xml\" ContentType=\"application/xml\"/>"
		@"<Override PartName=\"/word/document.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml\"/>"
		@"<Override PartName=\"/word/styles.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml\"/>"
		@"</Types>";
	NSString *rels =
		@"<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>"
		@"<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">"
		@"<Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument\" Target=\"word/document.xml\"/>"
		@"</Relationships>";
	NSString *docRels =
		@"<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>"
		@"<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">"
		@"<Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles\" Target=\"styles.xml\"/>"
		@"</Relationships>";
	NSString *styles =
		@"<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>"
		@"<w:styles xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\">"
		@"<w:style w:type=\"paragraph\" w:default=\"1\" w:styleId=\"Normal\"><w:name w:val=\"Normal\"/></w:style>"
		@"<w:style w:type=\"paragraph\" w:styleId=\"Heading1\"><w:name w:val=\"heading 1\"/><w:rPr><w:b/><w:sz w:val=\"32\"/></w:rPr></w:style>"
		@"<w:style w:type=\"paragraph\" w:styleId=\"Heading2\"><w:name w:val=\"heading 2\"/><w:rPr><w:b/><w:sz w:val=\"28\"/></w:rPr></w:style>"
		@"<w:style w:type=\"paragraph\" w:styleId=\"Heading3\"><w:name w:val=\"heading 3\"/><w:rPr><w:b/><w:sz w:val=\"24\"/></w:rPr></w:style>"
		@"<w:style w:type=\"paragraph\" w:styleId=\"Heading4\"><w:name w:val=\"heading 4\"/><w:rPr><w:b/></w:rPr></w:style>"
		@"<w:style w:type=\"paragraph\" w:styleId=\"Heading5\"><w:name w:val=\"heading 5\"/><w:rPr><w:b/></w:rPr></w:style>"
		@"<w:style w:type=\"paragraph\" w:styleId=\"Heading6\"><w:name w:val=\"heading 6\"/><w:rPr><w:b/></w:rPr></w:style>"
		@"<w:style w:type=\"paragraph\" w:styleId=\"Code\"><w:name w:val=\"Code\"/><w:rPr><w:rFonts w:ascii=\"Menlo\" w:hAnsi=\"Menlo\"/></w:rPr></w:style>"
		@"<w:style w:type=\"paragraph\" w:styleId=\"Quote\"><w:name w:val=\"Quote\"/><w:pPr><w:ind w:left=\"720\"/></w:pPr></w:style>"
		@"<w:style w:type=\"paragraph\" w:styleId=\"List\"><w:name w:val=\"List\"/><w:pPr><w:ind w:left=\"360\"/></w:pPr></w:style>"
		@"</w:styles>";
	NSDictionary *files = @{
		@"[Content_Types].xml": [types dataUsingEncoding:NSUTF8StringEncoding],
		@"_rels/.rels": [rels dataUsingEncoding:NSUTF8StringEncoding],
		@"word/document.xml": [doc dataUsingEncoding:NSUTF8StringEncoding],
		@"word/_rels/document.xml.rels": [docRels dataUsingEncoding:NSUTF8StringEncoding],
		@"word/styles.xml": [styles dataUsingEncoding:NSUTF8StringEncoding],
	};
	return NPZipStore(files);
}

@implementation PreviewExport

+ (NPExportFormat)formatFromPath:(NSString *)path {
	NSString *ext = path.pathExtension.lowercaseString ?: @"";
	if ([ext isEqualToString:@"pdf"]) return NPExportPDF;
	if ([ext isEqualToString:@"png"] || [ext isEqualToString:@"jpg"] || [ext isEqualToString:@"jpeg"])
		return NPExportPNG;
	if ([ext isEqualToString:@"docx"]) return NPExportDOCX;
	return NPExportHTML;
}

+ (NSData *)dataFromMarkdown:(NSString *)markdown html:(NSString *)html
	format:(NPExportFormat)fmt dark:(BOOL)dark {
	NSString *md = markdown ?: @"";
	NSString *inner = html.length ? html : [PreviewPane htmlFromMarkdown:md];
	if (fmt == NPExportHTML) {
		if (md.length)
			return [[PreviewPane pageHTMLFromMarkdown:md dark:dark outline:YES] dataUsingEncoding:NSUTF8StringEncoding];
		return [[PreviewPane wrapPreviewBody:inner dark:dark kind:NPPreviewHTML editable:NO outline:NO] dataUsingEncoding:NSUTF8StringEncoding];
	}
	NSArray *blocks = NPBlocksFromHTML(inner);
	if (fmt == NPExportPDF) return NPPDFFromBlocks(blocks, dark);
	if (fmt == NPExportPNG) return NPPNGFromBlocks(blocks, dark);
	return NPDOCXFromBlocks(blocks);
}

+ (BOOL)writeData:(NSData *)data toURL:(NSURL *)url error:(NSError **)err {
	if (data == nil || url == nil) {
		if (err) *err = [NSError errorWithDomain:@"PreviewExport" code:1
			userInfo:@{NSLocalizedDescriptionKey: @"empty export"}];
		return NO;
	}
	return [data writeToURL:url options:NSDataWritingAtomic error:err];
}

@end
