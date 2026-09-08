#import "EditorDocument.h"
#import "SciLexer.h"
#import "ILexer.h"
#import "LexerModule.h"

#import <unordered_map>

// 扩展名 -> SCLEX_* 词法器（常用子集；完整映射后续接入 EditLexer 表）
static const std::unordered_map<NSString *, int> gLexerByExt = {
	{@"cpp", SCLEX_CPP}, {@"cxx", SCLEX_CPP}, {@"cc", SCLEX_CPP}, {@"c", SCLEX_CPP},
	{@"h", SCLEX_CPP}, {@"hpp", SCLEX_CPP}, {@"hh", SCLEX_CPP}, {@"hxx", SCLEX_CPP},
	{@"m", SCLEX_CPP}, {@"mm", SCLEX_CPP},
	{@"swift", SCLEX_SWIFT},
	{@"go", SCLEX_GO},
	{@"rs", SCLEX_RUST},
	{@"py", SCLEX_PYTHON}, {@"pyw", SCLEX_PYTHON},
	{@"rb", SCLEX_RUBY},
	{@"js", SCLEX_JAVASCRIPT}, {@"mjs", SCLEX_JAVASCRIPT}, {@"jsx", SCLEX_JAVASCRIPT},
	{@"ts", SCLEX_JAVASCRIPT}, {@"tsx", SCLEX_JAVASCRIPT},
	{@"java", SCLEX_JAVA},
	{@"cs", SCLEX_CSHARP},
	{@"sh", SCLEX_BASH}, {@"bash", SCLEX_BASH}, {@"zsh", SCLEX_BASH},
	{@"json", SCLEX_JSON},
	{@"xml", SCLEX_XML}, {@"html", SCLEX_HTML}, {@"htm", SCLEX_HTML}, {@"svg", SCLEX_XML},
	{@"css", SCLEX_CSS},
	{@"md", SCLEX_MARKDOWN}, {@"markdown", SCLEX_MARKDOWN},
	{@"sql", SCLEX_SQL},
	{@"yaml", SCLEX_YAML}, {@"yml", SCLEX_YAML},
	{@"toml", SCLEX_TOML},
	{@"cmake", SCLEX_CMAKE}, {@"mk", SCLEX_MAKEFILE},
	{@"ini", SCLEX_PROPERTIES}, {@"cfg", SCLEX_PROPERTIES}, {@"conf", SCLEX_PROPERTIES},
	{@"tex", SCLEX_LATEX},
	{@"lua", SCLEX_LUA},
	{@"php", SCLEX_PHPSCRIPT},
	{@"vim", SCLEX_VIM},
	{@"pl", SCLEX_PERL}, {@"pm", SCLEX_PERL},
	{@"bat", SCLEX_BATCH}, {@"cmd", SCLEX_BATCH},
	{@"ps1", SCLEX_POWERSHELL},
	{@"asm", SCLEX_ASM}, {@"s", SCLEX_ASM},
	{@"d", SCLEX_DLANG},
	{@"zig", SCLEX_ZIG},
	{@"txt", SCLEX_NULL},
};


// 通用浅色主题（对齐 notepad4 默认 C 配色核心）
static void ApplyDefaultPalette(ScintillaView *e) {
	// C 系（cpp/objc/java/js/ts/csharp 等 SCE_C_* 共用编号体系）
	struct StyleColor { int style; const char *fore; BOOL italic; };
	static const StyleColor cColors[] = {
		{SCE_C_COMMENT,       "#008000", YES},
		{SCE_C_COMMENTLINE,   "#008000", YES},
		{SCE_C_COMMENTDOC,    "#008000", YES},
		{SCE_C_COMMENTLINEDOC,"#008000", YES},
		{SCE_C_WORD,          "#0000FF", NO},
		{SCE_C_WORD2,         "#0000FF", NO},
		{SCE_C_PREPROCESSOR,  "#804000", NO},
		{SCE_C_DIRECTIVE,     "#804000", NO},
		{SCE_C_STRING,        "#A31515", NO},
		{SCE_C_CHARACTER,     "#A31515", NO},
		{SCE_C_STRINGRAW,     "#A31515", NO},
		{SCE_C_STRINGEOL,     "#A31515", NO},
		{SCE_C_ESCAPECHAR,    "#A31515", NO},
		{SCE_C_NUMBER,        "#B8860B", NO},
		{SCE_C_OPERATOR,      "#404040", NO},
		{SCE_C_IDENTIFIER,    "#000000", NO},
	};
	for (const auto &sc : cColors) {
		[e setColorProperty:SCI_STYLESETFORE parameter:sc.style fromHTML:@(sc.fore)];
		if (sc.italic) {
			[e setGeneralProperty:SCI_STYLESETITALIC parameter:sc.style value:sc.italic];
		}
	}
}

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
	// 基础编辑体验：行号边距 + 等宽字体 + Tab 宽 4
	[_editor message:SCI_SETMARGINTYPEN wParam:0 lParam:SC_MARGIN_NUMBER];
	[_editor message:SCI_SETMARGINWIDTHN wParam:0 lParam:48];
	[_editor setGeneralProperty:SCI_SETUSETABS value:NO];
	[_editor setGeneralProperty:SCI_SETTABWIDTH value:4];
	[_editor setGeneralProperty:SCI_SETINDENTATIONGUIDES value:SC_IV_LOOKBOTH];
	[_editor setStringProperty:SCI_STYLESETFONT parameter:STYLE_DEFAULT value:@"Menlo"];
	[_editor setGeneralProperty:SCI_STYLESETSIZE parameter:STYLE_DEFAULT value:13];
	[_editor message:SCI_STYLECLEARALL wParam:0 lParam:0];
	// 修改标记：SCN_SAVEPOINTLEFT -> dirty
	_editor.delegate = self;
}

// Scintilla 通知回调（ScintillaView 的 informal delegate）
- (void)notification:(SCNotification *)scn {
	if (scn->nmhdr.code == SCN_SAVEPOINTLEFT) {
		_dirty = YES;
		[[NSNotificationCenter defaultCenter] postNotificationName:@"EditorDocumentDirtyChanged" object:self];
	} else if (scn->nmhdr.code == SCN_SAVEPOINTREACHED) {
		_dirty = NO;
		[[NSNotificationCenter defaultCenter] postNotificationName:@"EditorDocumentDirtyChanged" object:self];
	}
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
	const auto it = gLexerByExt.find(ext);
	const int lexer = (it != gLexerByExt.end()) ? it->second : SCLEX_NULL;
	[_editor setGeneralProperty:SCI_SETLEXER value:lexer];
	ApplyDefaultPalette(_editor);
	// 强制重着色
	[_editor message:SCI_COLOURISE wParam:0 lParam:-1];
}

- (BOOL)dirty {
	return _dirty;
}

- (NSString *)windowTitle {
	NSString *base = _fileURL ? _fileURL.lastPathComponent : _tabTitle;
	return _dirty ? [base stringByAppendingString:@" — 已修改"] : base;
}

@end
