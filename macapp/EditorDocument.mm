#import "EditorDocument.h"
#import "SciLexer.h"
#import "Scintilla.h"
#import "ILexer.h"
#import "LexerModule.h"
#import "LexerPalettes.h"
#import "LexerRegistry.h"
#import "NPTheme.h"
#import "NPLocalization.h"
#import "EditLexer.h"
#include <string>
#include "Sci_Position.h"
#include <vector>
#include <cstring>


// 旧 ext->SCLEX 兜底映射已由 LexerRegistry（90 词法器全量）替代


static BOOL NPPrefBool(NSString *key, BOOL fallback) {
	NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
	return [d objectForKey:key] ? [d boolForKey:key] : fallback;
}
static NSInteger NPPrefInt(NSString *key, NSInteger fallback) {
	NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
	return [d objectForKey:key] ? [d integerForKey:key] : fallback;
}

// 对照 Windows EditLoadFile / EditSetNewText：
// UTF-8 不经 NSString（避免整文件 UTF-16 往返）；SCI_APPENDTEXT + 预分配；大文件跳过全文着色。
static const NSUInteger kNP4ColouriseAllLimit = 256ull * 1024ull;
static const NSUInteger kNP4LargeFileBytes = 8ull * 1024ull * 1024ull;
static const NSUInteger kNP4KeepRawBytesLimit = 1024ull * 1024ull;

static BOOL NPIsUTF8(const UInt8 *s, size_t n) {
	size_t i = 0;
	while (i < n) {
		const UInt8 c = s[i];
		if (c < 0x80) { i++; continue; }
		size_t need = 0;
		if ((c & 0xE0) == 0xC0) need = 2;
		else if ((c & 0xF0) == 0xE0) need = 3;
		else if ((c & 0xF8) == 0xF0) need = 4;
		else return NO;
		if (i + need > n) return NO;
		for (size_t j = 1; j < need; j++) {
			if ((s[i + j] & 0xC0) != 0x80) return NO;
		}
		i += need;
	}
	return YES;
}

static NSUInteger NPCountLines(const char *s, NSUInteger n) {
	NSUInteger lines = 1;
	for (NSUInteger i = 0; i < n; i++) {
		if (s[i] == '\n') lines++;
	}
	return lines;
}

static NSData *NPRecodeToUTF8(NSData *src, NSStringEncoding enc, NSUInteger skip) {
	if (src == nil) return nil;
	if (skip > src.length) return nil;
	NSData *slice = (skip == 0) ? src : [src subdataWithRange:NSMakeRange(skip, src.length - skip)];
	NSString *s = [[NSString alloc] initWithData:slice encoding:enc];
	if (s == nil) return nil;
	return [s dataUsingEncoding:NSUTF8StringEncoding];
}

// GB18030 几乎总能解出字，必须和 BIG5 / Shift-JIS 打分，不能谁先成功用谁
static NSInteger NPScoreDecoded(NSString *s, NSString *kind) {
	if (s.length == 0) return -1;
	NSInteger cjk = 0, kana = 0, pua = 0, ctrl = 0;
	const NSUInteger lim = s.length < 8000 ? s.length : 8000;
	for (NSUInteger i = 0; i < lim; i++) {
		const unichar c = [s characterAtIndex:i];
		if (c == 0xFFFD) { pua += 4; continue; }
		if (c < 32 && c != 9 && c != 10 && c != 13) { ctrl++; continue; }
		if (c >= 0xE000 && c <= 0xF8FF) { pua++; continue; }
		if (c >= 0x3040 && c <= 0x30FF) kana++;
		else if ((c >= 0x4E00 && c <= 0x9FFF) || (c >= 0x3400 && c <= 0x4DBF)) cjk++;
	}
	NSInteger score = cjk * 3 + kana * 8 - pua * 80 - ctrl * 20;
	if (kana > 0 && cjk > kana && ![kind isEqualToString:@"Shift-JIS"])
		score -= kana * 10;
	if ([kind isEqualToString:@"BIG5"] && kana > 0)
		score -= kana * 6;
	return score;
}

typedef struct {
	NSData *keepAlive;
	const char *bytes;
	NSUInteger length;
	NSString *encoding;
} NPLoadBuf;

static NPLoadBuf NPPrepareUTF8Load(NSData *data) {
	NPLoadBuf r;
	r.keepAlive = data;
	r.bytes = "";
	r.length = 0;
	r.encoding = @"UTF-8";
	if (data == nil || data.length == 0) return r;
	const UInt8 *b = static_cast<const UInt8 *>(data.bytes);
	const NSUInteger n = data.length;
	if (n >= 3 && b[0] == 0xEF && b[1] == 0xBB && b[2] == 0xBF) {
		r.bytes = reinterpret_cast<const char *>(b + 3);
		r.length = n - 3;
		r.encoding = @"UTF-8 BOM";
		return r;
	}
	if (n >= 2 && b[0] == 0xFF && b[1] == 0xFE) {
		NSData *c = NPRecodeToUTF8(data, NSUTF16LittleEndianStringEncoding, 2);
		r.keepAlive = c ?: data;
		r.encoding = @"UTF-16LE";
		r.bytes = c ? static_cast<const char *>(c.bytes) : "";
		r.length = c ? c.length : 0;
		return r;
	}
	if (n >= 2 && b[0] == 0xFE && b[1] == 0xFF) {
		NSData *c = NPRecodeToUTF8(data, NSUTF16BigEndianStringEncoding, 2);
		r.keepAlive = c ?: data;
		r.encoding = @"UTF-16BE";
		r.bytes = c ? static_cast<const char *>(c.bytes) : "";
		r.length = c ? c.length : 0;
		return r;
	}
	if (NPIsUTF8(b, n)) {
		r.bytes = reinterpret_cast<const char *>(b);
		r.length = n;
		return r;
	}

	struct { NSString *name; CFStringEncoding cf; } cands[] = {
		{@"GB18030", kCFStringEncodingGB_18030_2000},
		{@"BIG5", kCFStringEncodingBig5},
		{@"Shift-JIS", kCFStringEncodingShiftJIS},
	};
	NSInteger bestScore = 0;
	NPLoadBuf best = r;
	BOOL hit = NO;
	for (size_t i = 0; i < sizeof(cands) / sizeof(cands[0]); i++) {
		NSStringEncoding enc = CFStringConvertEncodingToNSStringEncoding(cands[i].cf);
		NSData *utf8 = NPRecodeToUTF8(data, enc, 0);
		if (utf8.length == 0) continue;
		NSString *s = [[NSString alloc] initWithData:utf8 encoding:NSUTF8StringEncoding];
		const NSInteger sc = NPScoreDecoded(s, cands[i].name);
		if (sc > bestScore) {
			bestScore = sc;
			best.keepAlive = utf8;
			best.encoding = cands[i].name;
			best.bytes = static_cast<const char *>(utf8.bytes);
			best.length = utf8.length;
			hit = YES;
		}
	}
	if (hit) return best;

	NSData *lat = NPRecodeToUTF8(data, NSISOLatin1StringEncoding, 0);
	r.keepAlive = lat ?: data;
	r.encoding = @"Latin-1";
	r.bytes = lat ? static_cast<const char *>(lat.bytes) : "";
	r.length = lat ? lat.length : 0;
	return r;
}

@interface EditorDocument (FastLoad)
- (void)applyUTF8Bytes:(const char *)bytes length:(NSUInteger)len;
@end

@implementation EditorDocument {
	NSString *_usedEncoding;
	BOOL _dirty;
	BOOL _braceMatchOn;
	BOOL _urlDetectOn;
	BOOL _largeFileMode;
	NSData *_rawBytes; // 打开时的原始字节（供重解码）
	NSArray<NSString *> *_keywordsForAutoc; // 词表缓存（自动补全）
	const EDITLEXER *_currentLexer;
	NPThemeKind _theme;
	NSInteger _untitledSequence;
	BOOL _showLineNumbers;
}

- (instancetype)initWithNewUntitled:(NSInteger)sequence {
	self = [super init];
	if (self) {
		_fileURL = nil;
		_untitledSequence = sequence;
		_usedEncoding = @"UTF-8";
		_tabTitle = [NSString stringWithFormat:@"%@-%ld", NPL(@"Untitled"), (long)sequence];
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
		const char *utf8 = contents.UTF8String ?: "";
		[self applyUTF8Bytes:utf8 length:strlen(utf8)];
		[self applyLexerForExtension:url.pathExtension.lowercaseString];
	}
	return self;
}

- (void)setupEditor {
	_editor = [[ScintillaView alloc] initWithFrame:NSMakeRect(0, 0, 100, 100)];
	_editor.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;

	// ---- Notepad4 默认（对照 Styles.cpp / stlDefault.cpp）----
	[_editor message:SCI_SETCODEPAGE wParam:SC_CP_UTF8 lParam:0];
	[_editor message:SCI_SETWORDCHARS wParam:0
		lParam:(sptr_t)"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_"];

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

	// 光标：竖线插在字符之间，宽 2，不盖住逗号/括号
	[_editor message:SCI_SETCARETSTYLE wParam:CARETSTYLE_LINE lParam:0];
	[_editor message:SCI_SETCARETWIDTH wParam:2 lParam:0];

	// 折叠：自动折叠 + 省略号样式（Notepad4.cpp:1806-1807）
	[_editor message:SCI_SETAUTOMATICFOLD
		wParam:(SC_AUTOMATICFOLD_SHOW | SC_AUTOMATICFOLD_CLICK | SC_AUTOMATICFOLD_CHANGE) lParam:0];
	[_editor message:SCI_FOLDDISPLAYTEXTSETSTYLE wParam:SC_FOLDDISPLAYTEXT_BOXED lParam:0];

	// 自动补全
	[_editor message:SCI_AUTOCSETIGNORECASE wParam:1 lParam:0];
	[_editor message:SCI_AUTOCSETCANCELATSTART wParam:1 lParam:0];
	[_editor message:SCI_AUTOCSETDROPRESTOFWORD wParam:1 lParam:0];

	// 主题按 Scheme 菜单选择解析：跟随系统 / 强制亮 / 强制暗
	_theme = NPThemeResolve(NPThemeModeGet());
	NPApplyTheme(_editor, _theme, nullptr);
	[_editor message:SCI_SETIDLESTYLING wParam:SC_IDLESTYLING_ALL lParam:0];
	_showLineNumbers = YES;
	[self applyPersistedEditorSettings];

	// 初始状态未修改（新建空文档不该显示为已修改）
	[_editor message:SCI_SETSAVEPOINT wParam:0 lParam:0];
	_dirty = NO;

	_editor.delegate = self;
}

- (void)dealloc {
	_editor.delegate = nil;
}

// 行号宽度随行数变：Windows UpdateLineNumberWidth = TEXTWIDTH("__" + 行数)
- (void)updateLineNumberWidth {
	if (!_showLineNumbers) {
		[_editor message:SCI_SETMARGINWIDTHN wParam:0 lParam:0];
		return;
	}
	const sptr_t lines = [_editor message:SCI_GETLINECOUNT];
	NSString *sample = [NSString stringWithFormat:@"__%ld", (long)(lines < 1 ? 1 : lines)];
	sptr_t w = [_editor message:SCI_TEXTWIDTH wParam:STYLE_LINENUMBER lParam:(sptr_t)sample.UTF8String];
	if (w < 28) w = 28;
	[_editor message:SCI_SETMARGINWIDTHN wParam:0 lParam:w];
}
- (BOOL)lineNumbersVisible { return _showLineNumbers; }
- (void)setLineNumbersVisible:(BOOL)visible {
	_showLineNumbers = visible;
	[self updateLineNumberWidth];
}
- (void)applyPersistedEditorSettings {
	NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
	_showLineNumbers = NPPrefBool(@"NP4ShowLineNumbers", YES);
	if (NPPrefBool(@"NP4WordWrap", NO))
		[_editor message:SCI_SETWRAPMODE wParam:SC_WRAP_WORD lParam:0];
	else
		[_editor message:SCI_SETWRAPMODE wParam:SC_WRAP_NONE lParam:0];
	[_editor message:SCI_SETMARGINWIDTHN wParam:2 lParam:(NPPrefBool(@"NP4ShowCodeFolding", YES) ? 14 : 0)];
	[_editor message:SCI_SETMARGINWIDTHN wParam:1 lParam:(NPPrefBool(@"NP4ShowBookmarkMargin", NO) ? 16 : 0)];
	[_editor message:SCI_SETINDENTATIONGUIDES wParam:(NPPrefBool(@"NP4ShowIndentGuides", NO) ? SC_IV_LOOKBOTH : SC_IV_NONE) lParam:0];
	[_editor message:SCI_SETVIEWWS wParam:(NPPrefBool(@"NP4ViewWhiteSpace", NO) ? SCWS_VISIBLEALWAYS : SCWS_INVISIBLE) lParam:0];
	[_editor message:SCI_SETVIEWEOL wParam:(NPPrefBool(@"NP4ViewEOLs", NO) ? 1 : 0) lParam:0];
	if ([d objectForKey:@"NP4UseTabs"])
		[_editor message:SCI_SETUSETABS wParam:(NPPrefBool(@"NP4UseTabs", NO) ? 1 : 0) lParam:0];
	const NSInteger tabW = NPPrefInt(@"NP4TabWidth", 4);
	if (tabW > 0) [_editor message:SCI_SETTABWIDTH wParam:tabW lParam:0];
	const NSInteger indW = NPPrefInt(@"NP4IndentWidth", 4);
	if (indW > 0) [_editor message:SCI_SETINDENT wParam:indW lParam:0];
	if ([d objectForKey:@"NP4Zoom"])
		[_editor message:SCI_SETZOOM wParam:NPPrefInt(@"NP4Zoom", 100) lParam:0];
	if (NPPrefBool(@"NP4LongLineMarker", NO)) {
		[_editor message:SCI_SETEDGECOLUMN wParam:80 lParam:0];
		[_editor message:SCI_SETEDGEMODE wParam:EDGE_LINE lParam:0];
	}
	_braceMatchOn = NPPrefBool(@"NP4BraceMatch", YES);
	_urlDetectOn = NPPrefBool(@"NP4URLDetect", NO);
	[self updateLineNumberWidth];
	[self updateBraceHighlight];
	if (_urlDetectOn) [self scanDetectedURLs];
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
		[self onCharAdded:scn->ch source:(int)scn->characterSource];
	} else if (scn->nmhdr.code == SCN_AUTOCSELECTION) {
		// 列表选择完成
	} else if (scn->nmhdr.code == SCN_UPDATEUI) {
		if (scn->updated & SC_UPDATE_LINE_COUNT)
			[self updateLineNumberWidth];
		if (scn->updated & (SC_UPDATE_SELECTION | SC_UPDATE_CONTENT)) {
			[self updateBraceHighlight];
			if (_urlDetectOn && (scn->updated & SC_UPDATE_CONTENT)
				&& [_editor message:SCI_GETLENGTH] < 262144)
				[self scanDetectedURLs];
			[[NSNotificationCenter defaultCenter] postNotificationName:@"EditorDocumentCaretChanged" object:self];
		}
		if (scn->updated & SC_UPDATE_V_SCROLL)
			[[NSNotificationCenter defaultCenter] postNotificationName:@"EditorDocumentScrolled" object:self];
	} else if (scn->nmhdr.code == SCN_INDICATORCLICK) {
		[self openDetectedURLAt:[_editor string] bytePos:scn->position];
	}
}

- (void)onCharAdded:(int)ch source:(int)source {
	// 对照 Notepad4.cpp:4755：IME 输入（非直接键入）不触发自动补全
	if (source != SC_CHARACTERSOURCE_DIRECT_INPUT) return;
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
	// 设置 > 自动补全设置：输入时自动补全（默认开）
	if (![[NSUserDefaults standardUserDefaults] objectForKey:@"NP4AutoCompleteOnTyping"])
		return _keywordsForAutoc != nil;
	return _keywordsForAutoc != nil
		&& [[NSUserDefaults standardUserDefaults] boolForKey:@"NP4AutoCompleteOnTyping"];
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

- (void)applyUTF8Bytes:(const char *)bytes length:(NSUInteger)len {
	if (bytes == NULL) { bytes = ""; len = 0; }
	ScintillaView *e = _editor;
	const NSUInteger lines = NPCountLines(bytes, len);
	if (len >= kNP4LargeFileBytes) _largeFileMode = YES;
	const sptr_t mask = [e message:SCI_GETMODEVENTMASK];
	[e message:SCI_SETMODEVENTMASK wParam:0 lParam:0];
	[e message:SCI_SETUNDOCOLLECTION wParam:0 lParam:0];
	[e message:SCI_EMPTYUNDOBUFFER wParam:0 lParam:0];
	[e message:SCI_CLEARALL wParam:0 lParam:0];
	if (len > 0) {
		[e message:SCI_ALLOCATE wParam:(sptr_t)(len + 1) lParam:0];
		[e message:SCI_ALLOCATELINES wParam:(sptr_t)lines lParam:0];
		[e message:SCI_APPENDTEXT wParam:(sptr_t)len lParam:(sptr_t)bytes];
	}
	[e message:SCI_EMPTYUNDOBUFFER wParam:0 lParam:0];
	[e message:SCI_SETSAVEPOINT wParam:0 lParam:0];
	[e message:SCI_SETUNDOCOLLECTION wParam:1 lParam:0];
	[e message:SCI_SETMODEVENTMASK wParam:mask lParam:0];
	_dirty = NO;
	if (_largeFileMode) {
		[e message:SCI_SETWRAPMODE wParam:SC_WRAP_NONE lParam:0];
		[e message:SCI_SETMARGINWIDTHN wParam:2 lParam:0];
	}
}

- (BOOL)loadFromURL:(NSURL *)url error:(NSError **)error {
	NSError *readErr = nil;
	NSData *data = [NSData dataWithContentsOfURL:url
		options:NSDataReadingMappedIfSafe error:&readErr];
	if (data == nil) {
		if (error) *error = readErr;
		return NO;
	}
	const NPLoadBuf buf = NPPrepareUTF8Load(data);
	_usedEncoding = buf.encoding ?: @"UTF-8";
	_fileURL = url;
	_tabTitle = url.lastPathComponent;
	if (data.length >= kNP4LargeFileBytes) _largeFileMode = YES;
	_rawBytes = (data.length <= kNP4KeepRawBytesLimit) ? data : nil;
	[self applyUTF8Bytes:buf.bytes length:buf.length];
	[self applyLexerForExtension:url.pathExtension.lowercaseString];
	return YES;
}

- (BOOL)writeContentsToURL:(NSURL *)url updateIdentity:(BOOL)update error:(NSError **)error {
	NSString *text = [self.editor string];
	NSData *data = nil;
	if ([_usedEncoding isEqualToString:@"UTF-8 BOM"]) {
		NSMutableData *md = [NSMutableData dataWithBytes:"\xEF\xBB\xBF" length:3];
		[md appendData:[text dataUsingEncoding:NSUTF8StringEncoding]];
		data = md;
	} else if ([_usedEncoding isEqualToString:@"UTF-8"]) {
		data = [text dataUsingEncoding:NSUTF8StringEncoding];
	} else if ([_usedEncoding isEqualToString:@"UTF-16LE"]) {
		NSData *body = [text dataUsingEncoding:NSUTF16LittleEndianStringEncoding];
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
				userInfo:@{NSLocalizedDescriptionKey: NPL(@"Failed to write with current encoding")}];
		}
		return NO;
	}
	NSError *writeErr = nil;
	BOOL ok = [data writeToURL:url options:NSAtomicWrite error:&writeErr];
	if (ok && update) {
		_fileURL = url;
		_tabTitle = url.lastPathComponent;
		_rawBytes = data;
		[_editor message:SCI_SETSAVEPOINT wParam:0 lParam:0];
	} else if (!ok && error) {
		*error = writeErr;
	}
	return ok;
}

- (BOOL)saveToURL:(NSURL *)url error:(NSError **)error {
	return [self writeContentsToURL:url updateIdentity:YES error:error];
}

- (void)completeWord {
	const sptr_t pos = [_editor message:SCI_GETCURRENTPOS];
	const sptr_t wordStart = [_editor message:SCI_WORDSTARTPOSITION wParam:pos lParam:YES];
	sptr_t len = pos - wordStart;
	if (len < 0) len = 0;
	NSString *root = (len > 0) ? [self editorStringFrom:wordStart length:len] : @"";
	NSMutableOrderedSet *set = [NSMutableOrderedSet orderedSet];
	if (root.length) [set addObjectsFromArray:[self autocompleteCandidates:root]];
	else if (_keywordsForAutoc.count) [set addObjectsFromArray:_keywordsForAutoc];
	NSString *all = @"";
	if ([_editor message:SCI_GETLENGTH] < 512 * 1024)
		all = [_editor string] ?: @"";
	if (all.length) {
		NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"[A-Za-z_][A-Za-z0-9_]*"
			options:0 error:nil];
		[re enumerateMatchesInString:all options:0 range:NSMakeRange(0, all.length)
			usingBlock:^(NSTextCheckingResult *m, NSMatchingFlags, BOOL *stop) {
				NSString *w = [all substringWithRange:m.range];
				if (w.length <= root.length) return;
				if (root.length && ![w.lowercaseString hasPrefix:root.lowercaseString]) return;
				[set addObject:w];
			}];
	}
	NSArray *cands = set.array;
	if (cands.count > 40) cands = [cands subarrayWithRange:NSMakeRange(0, 40)];
	if (cands.count < 1) return;
	NSString *list = [cands componentsJoinedByString:@" "];
	[_editor message:SCI_AUTOCSHOW wParam:len lParam:(sptr_t)list.UTF8String];
}

- (void)applyLexerForExtension:(NSString *)ext {
	if (_largeFileMode) {
		[_editor setGeneralProperty:SCI_SETLEXER value:SCLEX_NULL];
		_keywordsForAutoc = nil;
		if (ext.length) _currentLexer = [LexerRegistry lexerForExtension:ext];
		[_editor message:SCI_SETWRAPMODE wParam:SC_WRAP_NONE lParam:0];
		[_editor message:SCI_SETMARGINWIDTHN wParam:2 lParam:0];
		[self updateLineNumberWidth];
		return;
	}
	const EDITLEXER *lex = [LexerRegistry lexerForExtension:ext];
	if (lex) {
		[LexerRegistry applyLexer:lex toEditor:_editor darkMode:(_theme == NPThemeDark)];
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
		[_editor setGeneralProperty:SCI_SETLEXER value:SCLEX_NULL];
	}
	[self updateLineNumberWidth];
	if (_urlDetectOn) [self scanDetectedURLs];
}

- (BOOL)dirty {
	return _dirty;
}

- (void)reloadWithEncoding:(NSString *)encodingName {
	if (_fileURL) {
		NSData *disk = [NSData dataWithContentsOfURL:_fileURL];
		if (disk) _rawBytes = disk;
	}
	NSString *enc = nil;
	NSString *text = nil;
	if (_rawBytes) {
		if ([encodingName isEqualToString:@"UTF-8"] || [encodingName isEqualToString:@"UTF-8 BOM"]) {
			enc = encodingName;
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
		const char *utf8 = text.UTF8String ?: "";
		[self applyUTF8Bytes:utf8 length:strlen(utf8)];
	}
}

- (void)setSaveEncoding:(NSString *)encodingName {
	if ([encodingName isEqualToString:@"UTF-8 BOM"]) _usedEncoding = @"UTF-8 BOM";
	else if ([encodingName isEqualToString:@"UTF-8"]) _usedEncoding = @"UTF-8";
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

- (NSString *)currentLexerName {
	return [LexerRegistry displayNameForLexer:_currentLexer];
}

- (BOOL)braceMatchEnabled { return _braceMatchOn; }
- (void)setBraceMatchEnabled:(BOOL)on {
	_braceMatchOn = on;
	[self updateBraceHighlight];
}

- (void)updateBraceHighlight {
	if (!_editor) return;
	if (!_braceMatchOn) {
		[_editor message:SCI_BRACEHIGHLIGHT wParam:(sptr_t)-1 lParam:(sptr_t)-1];
		[_editor message:SCI_BRACEBADLIGHT wParam:(sptr_t)-1 lParam:0];
		return;
	}
	const sptr_t pos = [_editor message:SCI_GETCURRENTPOS];
	sptr_t brace = -1;
	if (pos > 0) {
		const char ch = (char)[_editor message:SCI_GETCHARAT wParam:pos - 1];
		if (ch == '(' || ch == ')' || ch == '[' || ch == ']' || ch == '{' || ch == '}')
			brace = pos - 1;
	}
	if (brace < 0) {
		const char ch = (char)[_editor message:SCI_GETCHARAT wParam:pos];
		if (ch == '(' || ch == ')' || ch == '[' || ch == ']' || ch == '{' || ch == '}')
			brace = pos;
	}
	if (brace < 0) {
		[_editor message:SCI_BRACEHIGHLIGHT wParam:(sptr_t)-1 lParam:(sptr_t)-1];
		[_editor message:SCI_BRACEBADLIGHT wParam:(sptr_t)-1 lParam:0];
		return;
	}
	const sptr_t match = [_editor message:SCI_BRACEMATCH wParam:brace lParam:0];
	if (match >= 0) {
		[_editor message:SCI_BRACEBADLIGHT wParam:(sptr_t)-1 lParam:0];
		[_editor message:SCI_BRACEHIGHLIGHT wParam:brace lParam:match];
	} else {
		[_editor message:SCI_BRACEHIGHLIGHT wParam:(sptr_t)-1 lParam:(sptr_t)-1];
		[_editor message:SCI_BRACEBADLIGHT wParam:brace lParam:0];
	}
}

- (NSString *)windowTitle {
	NSString *base = _fileURL ? _fileURL.lastPathComponent
		: [NSString stringWithFormat:@"%@-%ld", NPL(@"Untitled"), (long)_untitledSequence];
	return _dirty ? [base stringByAppendingString:NPL(@" — Modified")] : base;
}

- (BOOL)URLDetectEnabled { return _urlDetectOn; }
- (void)setURLDetectEnabled:(BOOL)on {
	_urlDetectOn = on;
	[self scanDetectedURLs];
}
- (BOOL)largeFileMode { return _largeFileMode; }
- (void)setLargeFileMode:(BOOL)on {
	_largeFileMode = on;
	if (on == NO) [self applyPersistedEditorSettings];
	NSString *ext = _fileURL.pathExtension.lowercaseString;
	[self applyLexerForExtension:ext.length ? ext : @"txt"];
}

- (void)scanDetectedURLs {
	if (!_editor) return;
	const int indic = 20;
	[_editor message:SCI_INDICSETSTYLE wParam:indic lParam:INDIC_PLAIN];
	[_editor message:SCI_INDICSETFORE wParam:indic lParam:0xE97D2B];
	[_editor message:SCI_INDICSETUNDER wParam:indic lParam:1];
	[_editor message:SCI_SETINDICATORCURRENT wParam:indic lParam:0];
	const sptr_t len = [_editor message:SCI_GETLENGTH];
	[_editor message:SCI_INDICATORCLEARRANGE wParam:0 lParam:len];
	if (!_urlDetectOn || len == 0 || len > 2 * 1024 * 1024) return;
	NSString *text = [_editor string];
	if (text.length == 0) return;
	NSDataDetector *det = [NSDataDetector dataDetectorWithTypes:NSTextCheckingTypeLink error:nil];
	if (!det) return;
	[det enumerateMatchesInString:text options:0 range:NSMakeRange(0, text.length)
		usingBlock:^(NSTextCheckingResult *m, NSMatchingFlags flags, BOOL *stop) {
			if (!m || m.range.length == 0) return;
			NSString *pre = [text substringToIndex:m.range.location];
			NSString *body = [text substringWithRange:m.range];
			const sptr_t start = (sptr_t)[pre lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
			const sptr_t n = (sptr_t)[body lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
			[_editor message:SCI_INDICATORFILLRANGE wParam:start lParam:n];
		}];
}

- (void)openDetectedURLAt:(NSString *)text bytePos:(sptr_t)pos {
	if (!_urlDetectOn || text.length == 0 || pos < 0) return;
	NSDataDetector *det = [NSDataDetector dataDetectorWithTypes:NSTextCheckingTypeLink error:nil];
	if (!det) return;
	[det enumerateMatchesInString:text options:0 range:NSMakeRange(0, text.length)
		usingBlock:^(NSTextCheckingResult *m, NSMatchingFlags flags, BOOL *stop) {
			if (!m.URL) return;
			NSString *pre = [text substringToIndex:m.range.location];
			NSString *body = [text substringWithRange:m.range];
			const sptr_t start = (sptr_t)[pre lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
			const sptr_t n = (sptr_t)[body lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
			if (pos >= start && pos < start + n) {
				if ([[[NSProcessInfo processInfo] arguments] containsObject:@"--headless"] == NO)
					[[NSWorkspace sharedWorkspace] openURL:m.URL];
				*stop = YES;
			}
		}];
}

@end
