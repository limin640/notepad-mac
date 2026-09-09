#import "EditorDocument.h"
#import "SciLexer.h"
#import "ILexer.h"
#import "LexerModule.h"
#import "LexerPalettes.h"
#import "LexerRegistry.h"
#import "NPTheme.h"
#import "EditLexer.h"
#include <string>
#include "Sci_Position.h"
#include <vector>
#include <cstring>


// 旧 ext->SCLEX 兜底映射已由 LexerRegistry（90 词法器全量）替代


static NSString *DetectEncodingAndDecode(NSData *data, NSString **usedEncoding) {
	// BOM 检测
	if (data.length >= 3) {
		const UInt8 *b = static_cast<const UInt8 *>(data.bytes);
		if (b[0] == 0xEF && b[1] == 0xBB && b[2] == 0xBF) {
			*usedEncoding = @"UTF-8";
			return [[NSString alloc] initWithData:[data subdataWithRange:NSMakeRange(3, data.length - 3)]
				encoding:NSUTF8StringEncoding];
		}
		if (b[0] == 0xFF && b[1] == 0xFE) {
			*usedEncoding = @"UTF-16LE";
			return [[NSString alloc] initWithData:[data subdataWithRange:NSMakeRange(2, data.length - 2)]
				encoding:NSUTF16LittleEndianStringEncoding];
		}
		if (b[0] == 0xFE && b[1] == 0xFF) {
			*usedEncoding = @"UTF-16BE";
			return [[NSString alloc] initWithData:[data subdataWithRange:NSMakeRange(2, data.length - 2)]
				encoding:NSUTF16BigEndianStringEncoding];
		}
	}
	// 无 BOM：先按 UTF-8 严格试
	NSString *s = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
	if (s) {
		*usedEncoding = @"UTF-8";
		return s;
	}
	// 回退 GB18030（中文环境最常见 ANSI）
	s = [[NSString alloc] initWithData:data encoding:CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingGB_18030_2000)];
	if (s) {
		*usedEncoding = @"GB18030";
		return s;
	}
	// 最后 Latin1（永不失败）
	*usedEncoding = @"Latin-1";
	return [[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding];
}

@implementation EditorDocument {
	NSString *_usedEncoding;
	BOOL _dirty;
	NSData *_rawBytes; // 打开时的原始字节（供重解码）
	NSArray<NSString *> *_keywordsForAutoc; // 词表缓存（自动补全）
	const EDITLEXER *_currentLexer;
	NPThemeKind _theme;
}

- (instancetype)initWithNewUntitled:(NSInteger)sequence {
	self = [super init];
	if (self) {
		_fileURL = nil;
		_tabTitle = [NSString stringWithFormat:@"无标题-%ld", (long)sequence];
		_usedEncoding = @"UTF-8";
		[self setupEditor];
	}
	return self;
}

- (instancetype)initWithFileURL:(NSURL *)url contents:(NSString *)contents {
	self = [super init];
	if (self) {
		_fileURL = url;
		_tabTitle = url.lastPathComponent;
		_usedEncoding = @"UTF-8";
		[self setupEditor];
		[self.editor message:SCI_SETTEXT wParam:0 lParam:(sptr_t)contents.UTF8String];
		[self.editor message:SCI_SETSAVEPOINT wParam:0 lParam:0];
		[self applyLexerForExtension:url.pathExtension.lowercaseString];
	}
	return self;
}

- (void)setupEditor {
	_editor = [[ScintillaView alloc] initWithFrame:NSMakeRect(0, 0, 100, 100)];
	_editor.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;

	// ---- Notepad4 默认（对照 Styles.cpp / stlDefault.cpp）----
	[_editor message:SCI_SETCODEPAGE wParam:SC_CP_UTF8 lParam:0];

	// 代码字体：Cascadia Mono -> Consolas，macOS 用 Menlo；默认 11pt（Style_DetectBaseFontSize）
	[_editor setStringProperty:SCI_STYLESETFONT parameter:STYLE_DEFAULT value:@"Menlo"];
	[_editor setGeneralProperty:SCI_STYLESETSIZE parameter:STYLE_DEFAULT value:12];
	[_editor message:SCI_STYLECLEARALL wParam:0 lParam:0];

	// 边距：0=行号 1=书签(默认关) 2=折叠(默认开)
	[_editor message:SCI_SETMARGINTYPEN wParam:0 lParam:SC_MARGIN_NUMBER];
	[_editor message:SCI_SETMARGINWIDTHN wParam:1 lParam:0];
	[_editor message:SCI_SETMARGINTYPEN wParam:2 lParam:SC_MARGIN_SYMBOL];
	[_editor message:SCI_SETMARGINMASKN wParam:2 lParam:SC_MASK_FOLDERS];
	[_editor message:SCI_SETMARGINWIDTHN wParam:2 lParam:14];
	[_editor message:SCI_SETMARGINSENSITIVEN wParam:2 lParam:1];

	// 制表符：TAB_WIDTH_4 / INDENT_WIDTH_4
	[_editor setGeneralProperty:SCI_SETUSETABS value:0];
	[_editor setGeneralProperty:SCI_SETTABWIDTH value:4];
	[_editor setGeneralProperty:SCI_SETINDENT value:4];

	// 光标：CARETSTYLE_LINE 宽 1（默认 iCaretStyle）
	[_editor message:SCI_SETCARETSTYLE wParam:CARETSTYLE_LINE lParam:0];

	// 折叠：自动折叠 + 省略号样式（Notepad4.cpp:1806-1807）
	[_editor message:SCI_SETAUTOMATICFOLD
		wParam:(SC_AUTOMATICFOLD_SHOW | SC_AUTOMATICFOLD_CLICK | SC_AUTOMATICFOLD_CHANGE) lParam:0];
	[_editor message:SCI_FOLDDISPLAYTEXTSETSTYLE wParam:SC_FOLDDISPLAYTEXT_BOXED lParam:0];

	// 自动补全
	[_editor message:SCI_AUTOCSETIGNORECASE wParam:1 lParam:0];
	[_editor message:SCI_AUTOCSETCANCELATSTART wParam:1 lParam:0];
	[_editor message:SCI_AUTOCSETDROPRESTOFWORD wParam:1 lParam:0];

	// 主题：默认暗色（对齐 Notepad4 README 首页截图；Scheme 菜单可切换）
	_theme = NPThemeDark;
	NPApplyTheme(_editor, _theme, nullptr);
	[self updateLineNumberWidth];

	_editor.delegate = self;
}

// 行号宽度 = 文本宽度("__" + 最大行号)（UpdateLineNumberWidth）
- (void)updateLineNumberWidth {
	const sptr_t lines = [_editor message:SCI_GETLINECOUNT];
	NSString *sample = [NSString stringWithFormat:@"__%ld", (long)lines];
	const sptr_t w = [_editor message:SCI_TEXTWIDTH wParam:STYLE_LINENUMBER lParam:(sptr_t)sample.UTF8String];
	[_editor message:SCI_SETMARGINWIDTHN wParam:0 lParam:w];
}

- (void)setTheme:(NPThemeKind)theme {
	_theme = theme;
	NPApplyTheme(_editor, theme, _currentLexer);
	[self updateLineNumberWidth];
}

- (NPThemeKind)theme { return _theme; }

// Scintilla 通知回调（ScintillaView 的 informal delegate）
- (void)notification:(SCNotification *)scn {
	if (scn->nmhdr.code == SCN_SAVEPOINTLEFT) {
		_dirty = YES;
		[[NSNotificationCenter defaultCenter] postNotificationName:@"EditorDocumentDirtyChanged" object:self];
	} else if (scn->nmhdr.code == SCN_SAVEPOINTREACHED) {
		_dirty = NO;
		[[NSNotificationCenter defaultCenter] postNotificationName:@"EditorDocumentDirtyChanged" object:self];
	} else if (scn->nmhdr.code == SCN_CHARADDED) {
		[self onCharAdded:scn->ch];
	} else if (scn->nmhdr.code == SCN_AUTOCSELECTION) {
		// 列表选择完成
	}
}

- (void)onCharAdded:(int)ch {
	// 字母/数字/下划线且非自动补全激活时，从词表补全
	if (![self autocEnabled]) return;
	if ([_editor message:SCI_AUTOCACTIVE wParam:0 lParam:0]) return;
	if (!isalnum(ch) && ch != '_') return;
	const sptr_t pos = [_editor message:SCI_GETCURRENTPOS];
	const sptr_t wordStart = [_editor message:SCI_WORDSTARTPOSITION wParam:pos lParam:YES];
	const sptr_t len = pos - wordStart;
	if (len < 2 || len > 64) return;
	NSString *root = [self editorStringFrom:wordStart length:len];
	NSArray *cands = [self autocompleteCandidates:root];
	if (cands.count >= 1) {
		NSString *list = [cands componentsJoinedByString:@" "];
		[_editor message:SCI_AUTOCSHOW wParam:len lParam:(sptr_t)list.UTF8String];
	}
}

- (BOOL)autocEnabled {
	return _keywordsForAutoc != nil;
}

- (NSString *)editorStringFrom:(sptr_t)start length:(sptr_t)len {
	struct TextRangeFull {
		long cpMin, cpMax;
		char *lpstrText;
	};
	std::vector<char> buf(len + 1);
	TextRangeFull tr{static_cast<long>(start), static_cast<long>(start + len), buf.data()};
	[_editor message:SCI_GETTEXTRANGEFULL wParam:0 lParam:(sptr_t)&tr];
	return [NSString stringWithUTF8String:buf.data()];
}

- (NSArray *)autocompleteCandidates:(NSString *)root {
	NSMutableArray *out = [NSMutableArray array];
	NSString *lower = root.lowercaseString;
	for (NSString *kw in _keywordsForAutoc) {
		if (kw.length > root.length) {
			NSString *prefix = [kw.lowercaseString substringToIndex:root.length];
			if ([prefix isEqualToString:lower]) {
				[out addObject:kw];
			}
		}
	}
	return out;
}

- (BOOL)loadFromURL:(NSURL *)url error:(NSError **)error {
	NSError *readErr = nil;
	NSData *data = [NSData dataWithContentsOfURL:url options:0 error:&readErr];
	if (!data) {
		if (error) *error = readErr;
		return NO;
	}
	NSString *enc = nil;
	NSString *text = DetectEncodingAndDecode(data, &enc);
	_rawBytes = data;
	if (!text) {
		if (error) {
			*error = [NSError errorWithDomain:@"Notepad4Mac" code:1
				userInfo:@{NSLocalizedDescriptionKey: @"无法解码文件内容"}];
		}
		return NO;
	}
	_usedEncoding = enc;
	_fileURL = url;
	_tabTitle = url.lastPathComponent;
	[_editor message:SCI_SETTEXT wParam:0 lParam:(sptr_t)text.UTF8String];
	[_editor message:SCI_EMPTYUNDOBUFFER wParam:0 lParam:0];
	[_editor message:SCI_SETSAVEPOINT wParam:0 lParam:0];
	[self applyLexerForExtension:url.pathExtension.lowercaseString];
	return YES;
}

- (BOOL)saveToURL:(NSURL *)url error:(NSError **)error {
	NSString *text = [self.editor string];
	NSData *data = nil;
	if ([_usedEncoding isEqualToString:@"UTF-8"]) {
		data = [text dataUsingEncoding:NSUTF8StringEncoding];
	} else if ([_usedEncoding isEqualToString:@"UTF-16LE"]) {
	 NSData *body = [text dataUsingEncoding:NSUTF16LittleEndianStringEncoding];
	 data = [[[NSData alloc] initWithBytes:"\xFF\xFE" length:2] mutableCopy];
	 NSMutableData *md = [NSMutableData dataWithBytes:"\xFF\xFE" length:2];
	 [md appendData:body];
	 data = md;
	} else if ([_usedEncoding isEqualToString:@"UTF-16BE"]) {
	 NSMutableData *md = [NSMutableData dataWithBytes:"\xFE\xFF" length:2];
	 [md appendData:[text dataUsingEncoding:NSUTF16BigEndianStringEncoding]];
	 data = md;
	} else if ([_usedEncoding isEqualToString:@"GB18030"]) {
	 data = [text dataUsingEncoding:CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingGB_18030_2000)];
	} else if ([_usedEncoding isEqualToString:@"BIG5"]) {
	 data = [text dataUsingEncoding:CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingBig5)];
	} else if ([_usedEncoding isEqualToString:@"Shift-JIS"]) {
	 data = [text dataUsingEncoding:CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingShiftJIS)];
	} else {
	 data = [text dataUsingEncoding:NSISOLatin1StringEncoding];
	}
	if (!data) {
		if (error) {
			*error = [NSError errorWithDomain:@"Notepad4Mac" code:2
				userInfo:@{NSLocalizedDescriptionKey: @"按当前编码写出失败"}];
		}
		return NO;
	}
	NSError *writeErr = nil;
	BOOL ok = [data writeToURL:url options:NSAtomicWrite error:&writeErr];
	if (ok) {
		_fileURL = url;
		_tabTitle = url.lastPathComponent;
		[_editor message:SCI_SETSAVEPOINT wParam:0 lParam:0];
	} else if (error) {
		*error = writeErr;
	}
	return ok;
}

- (void)applyLexerForExtension:(NSString *)ext {
	const EDITLEXER *lex = [LexerRegistry lexerForExtension:ext];
	if (lex) {
		[LexerRegistry applyLexer:lex toEditor:_editor darkMode:(_theme == NPThemeDark)];
		// 缓存词表给自动补全（词集0 = 关键字）
		NSMutableArray *kws = [NSMutableArray array];
		for (unsigned i = 0; i < lex->keywordCount && i < 9; i++) {
			const char *kw = lex->pszKeyWords[i];
			if (kw && *kw) {
				[[NSString stringWithUTF8String:kw] enumerateSubstringsInRange:NSMakeRange(0, strlen(kw))
					options:NSStringEnumerationByWords
					usingBlock:^(NSString *word, NSRange, NSRange, BOOL *stop) {
						if (word.length > 1) [kws addObject:word];
					}];
			}
		}
		_keywordsForAutoc = kws.count ? kws : nil;
		_currentLexer = lex;
	} else {
		// 未注册扩展：纯文本
		[_editor setGeneralProperty:SCI_SETLEXER value:SCLEX_NULL];
		[_editor message:SCI_COLOURISE wParam:0 lParam:-1];
	}
}

- (BOOL)dirty {
	return _dirty;
}

- (void)reloadWithEncoding:(NSString *)encodingName {
	NSString *enc = nil;
	NSString *text = nil;
	if (_rawBytes) {
		if ([encodingName isEqualToString:@"UTF-8"]) {
			enc = @"UTF-8";
			text = [[NSString alloc] initWithData:_rawBytes encoding:NSUTF8StringEncoding];
			if (!text && _rawBytes.length >= 3) {
				const UInt8 *b = static_cast<const UInt8 *>(_rawBytes.bytes);
				if (b[0]==0xEF && b[1]==0xBB && b[2]==0xBF) {
					text = [[NSString alloc] initWithData:[_rawBytes subdataWithRange:NSMakeRange(3,_rawBytes.length-3)] encoding:NSUTF8StringEncoding];
				}
			}
		} else if ([encodingName isEqualToString:@"UTF-16LE"]) {
			enc = @"UTF-16LE";
			text = [[NSString alloc] initWithData:_rawBytes encoding:NSUTF16LittleEndianStringEncoding];
		} else if ([encodingName isEqualToString:@"UTF-16BE"]) {
			enc = @"UTF-16BE";
			text = [[NSString alloc] initWithData:_rawBytes encoding:NSUTF16BigEndianStringEncoding];
		} else if ([encodingName isEqualToString:@"GBK"]) {
			enc = @"GB18030";
			text = [[NSString alloc] initWithData:_rawBytes encoding:CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingGB_18030_2000)];
		} else if ([encodingName isEqualToString:@"BIG5"]) {
			enc = @"BIG5";
			text = [[NSString alloc] initWithData:_rawBytes encoding:CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingBig5)];
		} else if ([encodingName isEqualToString:@"Shift-JIS"]) {
			enc = @"Shift-JIS";
			text = [[NSString alloc] initWithData:_rawBytes encoding:CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingShiftJIS)];
		} else if ([encodingName isEqualToString:@"Latin-1"]) {
			enc = @"Latin-1";
			text = [[NSString alloc] initWithData:_rawBytes encoding:NSISOLatin1StringEncoding];
		}
	}
	if (text) {
		_usedEncoding = enc;
		[_editor message:SCI_SETTEXT wParam:0 lParam:(sptr_t)text.UTF8String];
		[_editor message:SCI_SETSAVEPOINT wParam:0 lParam:0];
	}
}

- (void)setSaveEncoding:(NSString *)encodingName {
	if ([encodingName isEqualToString:@"UTF-8"]) _usedEncoding = @"UTF-8";
	else if ([encodingName isEqualToString:@"UTF-16LE"]) _usedEncoding = @"UTF-16LE";
	else if ([encodingName isEqualToString:@"UTF-16BE"]) _usedEncoding = @"UTF-16BE";
	else if ([encodingName isEqualToString:@"GBK"]) _usedEncoding = @"GB18030";
	else if ([encodingName isEqualToString:@"BIG5"]) _usedEncoding = @"BIG5";
	else if ([encodingName isEqualToString:@"Shift-JIS"]) _usedEncoding = @"Shift-JIS";
	else if ([encodingName isEqualToString:@"Latin-1"]) _usedEncoding = @"Latin-1";
}

- (NSString *)currentEncoding {
	return _usedEncoding;
}

- (const EDITLEXER *)currentLexer {
	return _currentLexer;
}

- (NSString *)windowTitle {
	NSString *base = _fileURL ? _fileURL.lastPathComponent : _tabTitle;
	return _dirty ? [base stringByAppendingString:@" — 已修改"] : base;
}

@end
