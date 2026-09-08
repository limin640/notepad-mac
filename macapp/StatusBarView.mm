#import "StatusBarView.h"
#import "EditorDocument.h"
#import "ScintillaView.h"
#import "Scintilla.h"
#import "EditLexer.h"
#include <cwchar>

static NSString *FormatCount(long n) {
	static NSNumberFormatter *fmt;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		fmt = [[NSNumberFormatter alloc] init];
		fmt.numberStyle = NSNumberFormatterDecimalStyle;
	});
	return [fmt stringFromNumber:@(n)];
}

@interface StatusBarView ()
@property (nonatomic, strong) NSTextField *posField;
@property (nonatomic, strong) NSTextField *lexerField;
@property (nonatomic, strong) NSTextField *zoomField;
@property (nonatomic, strong) NSTextField *sizeField;
@property (nonatomic, strong) NSTextField *encField;
@property (nonatomic, strong) NSTextField *eolField;
@end

@implementation StatusBarView

- (instancetype)initWithFrame:(NSRect)frame {
	self = [super initWithFrame:frame];
	if (self) {
		self.wantsLayer = YES;
		self.layer.backgroundColor = [NSColor controlBackgroundColor].CGColor;

		NSTextField * (^MakeField)(void) = ^NSTextField *(void) {
			NSTextField *f = [NSTextField labelWithString:@""];
			f.font = [NSFont monospacedDigitSystemFontOfSize:11 weight:NSFontWeightRegular];
			f.textColor = [NSColor secondaryLabelColor];
			f.alignment = NSTextAlignmentCenter;
			f.lineBreakMode = NSLineBreakByClipping;
			f.translatesAutoresizingMaskIntoConstraints = NO;
			f.cell.truncatesLastVisibleLine = YES;
			return f;
		};
		_posField = MakeField();
		_lexerField = MakeField();
		_zoomField = MakeField();
		_sizeField = MakeField();
		_encField = MakeField();
		_eolField = MakeField();

		NSDictionary *views = @{@"pos": _posField, @"lex": _lexerField, @"zoom": _zoomField,
			@"size": _sizeField, @"enc": _encField, @"eol": _eolField};
		for (NSString *key in views.allKeys) {
			[self addSubview:views[key]];
		}
		// 锚点布局：右起 eol/enc/size/zoom/lex 固定宽，pos 占剩余
		NSView *prev = self;
		NSString *prevAnchor = @"trailingAnchor";
		NSArray *rightItems = @[@{@"v": _eolField, @"w": @46}, @{@"v": _encField, @"w": @64},
			@{@"v": _sizeField, @"w": @64}, @{@"v": _zoomField, @"w": @48}, @{@"v": _lexerField, @"w": @120}];
		[self.leadingAnchor constraintEqualToAnchor:_posField.leadingAnchor constant:-4].active = YES;
		[self.trailingAnchor constraintEqualToAnchor:_lexerField.trailingAnchor constant:4].active = YES;
		NSView *left = _posField;
		for (NSDictionary *it in rightItems) {
			NSView *v = it[@"v"];
			[left.trailingAnchor constraintEqualToAnchor:v.leadingAnchor constant:-2].active = YES;
			[v.widthAnchor constraintEqualToConstant:[it[@"w"] doubleValue]].active = YES;
			[v.centerYAnchor constraintEqualToAnchor:self.centerYAnchor].active = YES;
			[v.heightAnchor constraintEqualToConstant:18].active = YES;
			left = v;
		}
		[_posField.centerYAnchor constraintEqualToAnchor:self.centerYAnchor].active = YES;
		[_posField.heightAnchor constraintEqualToConstant:18].active = YES;
		for (NSTextField *f in @[_lexerField, _zoomField, _sizeField, _encField, _eolField]) {
			[f.centerYAnchor constraintEqualToAnchor:self.centerYAnchor].active = YES;
		}
	}
	return self;
}

- (void)updateForDocument:(EditorDocument *)doc {
	if (!doc) {
		self.posField.stringValue = @"";
		self.lexerField.stringValue = @"";
		self.encField.stringValue = @"";
		return;
	}
	ScintillaView *e = doc.editor;
	const sptr_t pos = [e message:SCI_GETCURRENTPOS];
	const sptr_t line = [e message:SCI_LINEFROMPOSITION wParam:pos];
	const sptr_t lines = [e message:SCI_GETLINECOUNT];
	const sptr_t lineStart = [e message:SCI_POSITIONFROMLINE wParam:line];
	const sptr_t colBytes = pos - lineStart;

	// 选择统计
	const sptr_t selStart = [e message:SCI_GETSELECTIONSTART];
	const sptr_t selEnd = [e message:SCI_GETSELECTIONEND];
	NSString *selBytesStr = @"0";
	if (selEnd > selStart) {
		const sptr_t selBytes = [e message:SCI_GETSELTEXT] - 1;
		selBytesStr = FormatCount(selBytes);
	}

	self.posField.stringValue = [NSString stringWithFormat:@"Ln %@ / %@   Col %@   Ch %@   Sel %@",
		FormatCount(line + 1), FormatCount(lines), FormatCount(colBytes + 1),
		FormatCount(pos + 1), selBytesStr];

	// 词法器名
	NSString *lexName = NSLocalizedString(@"普通文本", nil);
	const EDITLEXER *lex = doc.currentLexer;
	if (lex && lex->pszName) {
		NSString *n = [[NSString alloc] initWithBytes:lex->pszName
			length:wcslen(lex->pszName)*sizeof(wchar_t)
			encoding:NSUTF32LittleEndianStringEncoding];
		lexName = n;
	}
	self.lexerField.stringValue = lexName;

	// 缩放
	self.zoomField.stringValue = [NSString stringWithFormat:@"%ld%%",
		(long)(([e message:SCI_GETZOOM]) * 100 / 100)];

	// 大小
	const sptr_t len = [e message:SCI_GETLENGTH];
	NSString *sizeStr = nil;
	if (len < 1024) sizeStr = [NSString stringWithFormat:@"%ld B", (long)len];
	else if (len < 1024*1024) sizeStr = [NSString stringWithFormat:@"%.1f KB", len/1024.0];
	else sizeStr = [NSString stringWithFormat:@"%.1f MB", len/1048576.0];
	self.sizeField.stringValue = sizeStr;

	// 编码
	self.encField.stringValue = doc.currentEncoding ?: @"UTF-8";

	// EOL
	const sptr_t eol = [e message:SCI_GETEOLMODE];
	self.eolField.stringValue = (eol == SC_EOL_CRLF) ? @"CRLF" : @"LF";
}

@end
