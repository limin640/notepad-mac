// 状态栏：复刻 Notepad4 的 IDS_STATUSITEM_FORMAT
// "Ln %s / %s \nCol %s / %s \nCh %s / %s \nSel %s / %s \nSelLn %s \nFnd %s "
// 后续格：词法器 | 编码 | EOL | INS/OVR | 缩放 | 文档大小
#import "StatusBarView.h"
#import "EditorDocument.h"
#import "ScintillaView.h"
#import "Scintilla.h"
#import "EditLexer.h"
#include <cwchar>

static NSString *Num(long n) {
	static NSNumberFormatter *fmt;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		fmt = [[NSNumberFormatter alloc] init];
		fmt.numberStyle = NSNumberFormatterDecimalStyle;
	});
	return [fmt stringFromNumber:@(n)];
}

static NSString *WStr2(const wchar_t *ws) {
	if (!ws) return @"";
	return [[NSString alloc] initWithBytes:ws length:wcslen(ws)*sizeof(wchar_t)
		encoding:NSUTF32LittleEndianStringEncoding];
}

@interface StatusBarView ()
@property (nonatomic, strong) NSMutableArray<NSTextField *> *cells;
@end

@implementation StatusBarView

- (void)drawRect:(NSRect)dirtyRect {
	[[NSColor windowBackgroundColor] setFill];
	NSRectFill(dirtyRect);
	// 顶部 1px 描边（Windows 状态栏上沿）
	[[NSColor separatorColor] setFill];
	NSRectFill(NSMakeRect(0, self.bounds.size.height - 1, self.bounds.size.width, 1));
}

- (instancetype)initWithFrame:(NSRect)frame {
	self = [super initWithFrame:frame];
	if (self) {
		self.wantsLayer = YES;
		_cells = [NSMutableArray array];

		// 12 格：6 位置 + 词法器 + 编码 + EOL + INS + 缩放 + 大小
		NSArray<NSNumber *> *widths = @[@0, @64, @64, @64, @52, @44, @0, @110, @56, @44, @34, @40, @56];
		NSView *prev = nil;
		for (NSUInteger i = 0; i < widths.count; i++) {
			NSTextField *f = [NSTextField labelWithString:@""];
			f.font = [NSFont monospacedDigitSystemFontOfSize:11 weight:NSFontWeightRegular];
			f.textColor = [NSColor labelColor];
			f.alignment = (i == 6 || i == 7) ? NSTextAlignmentCenter : NSTextAlignmentCenter;
			f.lineBreakMode = NSLineBreakByClipping;
			f.translatesAutoresizingMaskIntoConstraints = NO;
			[self addSubview:f];
			[f.centerYAnchor constraintEqualToAnchor:self.centerYAnchor].active = YES;
			[f.heightAnchor constraintEqualToConstant:16].active = YES;
			if (widths[i].doubleValue > 0) {
				[f.widthAnchor constraintEqualToConstant:widths[i].doubleValue].active = YES;
			}
			// 分隔线（Windows 状态栏格线）
			if (i > 0) {
				NSView *sep = [[NSView alloc] initWithFrame:NSZeroRect];
				sep.wantsLayer = YES;
				sep.layer.backgroundColor = [NSColor separatorColor].CGColor;
				sep.translatesAutoresizingMaskIntoConstraints = NO;
				[self addSubview:sep];
				[sep.widthAnchor constraintEqualToConstant:1].active = YES;
				[sep.heightAnchor constraintEqualToConstant:14].active = YES;
				[sep.centerYAnchor constraintEqualToAnchor:self.centerYAnchor].active = YES;
				[prev.trailingAnchor constraintEqualToAnchor:sep.leadingAnchor constant:-2].active = YES;
				[f.leadingAnchor constraintEqualToAnchor:sep.trailingAnchor constant:2].active = YES;
			}
			if (!prev) {
				[self.leadingAnchor constraintEqualToAnchor:f.leadingAnchor constant:-6].active = YES;
			}
			[_cells addObject:f];
			prev = f;
		}
		[self.trailingAnchor constraintGreaterThanOrEqualToAnchor:prev.trailingAnchor constant:6].active = YES;
	}
	return self;
}

- (NSTextField *)cellAt:(NSUInteger)i {
	return (i < _cells.count) ? _cells[i] : nil;
}

- (void)updateForDocument:(EditorDocument *)doc {
	if (!doc) return;
	ScintillaView *e = doc.editor;

	const sptr_t pos = [e message:SCI_GETCURRENTPOS];
	const sptr_t line = [e message:SCI_LINEFROMPOSITION wParam:pos];
	const sptr_t lines = [e message:SCI_GETLINECOUNT];
	const sptr_t lineStart = [e message:SCI_POSITIONFROMLINE wParam:line];
	const sptr_t lineEnd = [e message:SCI_GETLINEENDPOSITION wParam:line];
	const sptr_t col = pos - lineStart;
	const sptr_t lineLen = lineEnd - lineStart;

	const sptr_t selStart = [e message:SCI_GETSELECTIONSTART];
	const sptr_t selEnd = [e message:SCI_GETSELECTIONEND];
	const sptr_t selBytes = (selEnd > selStart) ? (selEnd - selStart) : 0;
	const sptr_t selChars = (selEnd > selStart) ? [e message:SCI_COUNTCHARACTERS wParam:selStart lParam:selEnd] : 0;
	sptr_t selLines = 0;
	if (selEnd > selStart) {
		selLines = [e message:SCI_LINEFROMPOSITION wParam:selEnd]
			- [e message:SCI_LINEFROMPOSITION wParam:selStart] + 1;
	}

	// Ln / Col / Ch / Sel / SelLn / Fnd
	[self cellAt:0].stringValue = [NSString stringWithFormat:@"Ln %@ / %@",
		Num(line + 1), Num(lines)];
	[self cellAt:1].stringValue = [NSString stringWithFormat:@"Col %@ / %@",
		Num(col + 1), Num(lineLen + 1)];
	[self cellAt:2].stringValue = [NSString stringWithFormat:@"Ch %@ / %@",
		Num(pos + 1), Num([e message:SCI_GETLENGTH] + 1)];
	[self cellAt:3].stringValue = [NSString stringWithFormat:@"Sel %@ / %@",
		Num(selBytes), Num(selChars)];
	[self cellAt:4].stringValue = [NSString stringWithFormat:@"SelLn %@", Num(selLines)];
	[self cellAt:5].stringValue = @"Fnd 0";

	// 词法器名
	const EDITLEXER *lex = doc.currentLexer;
	[self cellAt:6].stringValue = lex ? WStr2(lex->pszName) : @"Text File";

	// 编码
	[self cellAt:7].stringValue = doc.currentEncoding ?: @"UTF-8";

	// EOL
	const sptr_t eol = [e message:SCI_GETEOLMODE];
	[self cellAt:8].stringValue = (eol == SC_EOL_CRLF) ? @"CR+LF"
		: (eol == SC_EOL_CR) ? @"CR" : @"LF";

	// INS/OVR
	const BOOL ovr = [e message:SCI_GETOVERTYPE];
	[self cellAt:9].stringValue = ovr ? @"OVR" : @"INS";

	// 缩放
	const long zoom = [e message:SCI_GETZOOM];   // fork: 百分比（100 = 默认）
	[self cellAt:10].stringValue = [NSString stringWithFormat:@"%ld%%", zoom > 0 ? zoom : 100];

	// 大小
	const sptr_t len = [e message:SCI_GETLENGTH];
	NSString *sizeStr;
	if (len < 1024) sizeStr = [NSString stringWithFormat:@"%ld B", (long)len];
	else if (len < 1024*1024) sizeStr = [NSString stringWithFormat:@"%.1f KB", len/1024.0];
	else sizeStr = [NSString stringWithFormat:@"%.1f MB", len/1048576.0];
	[self cellAt:11].stringValue = sizeStr;
}

@end
