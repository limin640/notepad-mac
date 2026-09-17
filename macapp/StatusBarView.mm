// 状态栏：复刻 Notepad4 的 IDS_STATUSITEM_FORMAT
// 左下角「预览」按钮 + Ln / Col / Ch / Sel / 词法器 / 编码 / EOL / INS / 缩放 / 大小
#import "StatusBarView.h"
#import "NPLocalization.h"
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

@interface NPStatusPreviewButton : NSButton
@property (nonatomic) BOOL previewOn;
@end
@implementation NPStatusPreviewButton
- (BOOL)isFlipped { return YES; }
- (void)drawRect:(NSRect)dirtyRect {
	(void)dirtyRect;
	NSRect r = NSInsetRect(self.bounds, 1, 2);
	if (self.previewOn) {
		[[[NSColor controlAccentColor] colorWithAlphaComponent:0.28] setFill];
		[[NSBezierPath bezierPathWithRoundedRect:r xRadius:4 yRadius:4] fill];
	} else if (self.highlighted) {
		[[[NSColor selectedContentBackgroundColor] colorWithAlphaComponent:0.22] setFill];
		[[NSBezierPath bezierPathWithRoundedRect:r xRadius:4 yRadius:4] fill];
	}
	NSColor *c = self.previewOn ? [NSColor controlAccentColor] : [NSColor labelColor];
	NSDictionary *attrs = @{
		NSFontAttributeName: [NSFont systemFontOfSize:11],
		NSForegroundColorAttributeName: c
	};
	NSString *title = self.title ?: @"";
	NSSize sz = [title sizeWithAttributes:attrs];
	[title drawAtPoint:NSMakePoint(NSMidX(self.bounds) - sz.width / 2.0,
		NSMidY(self.bounds) - sz.height / 2.0 + 1.0) withAttributes:attrs];
}
@end

@interface StatusBarView ()
@property (nonatomic, strong) NSMutableArray<NSTextField *> *cells;
@property (nonatomic, strong) NPStatusPreviewButton *previewBtn;
@property (nonatomic, strong) NPStatusPreviewButton *treeBtn;
@property (nonatomic, strong) NPStatusPreviewButton *outlineBtn;
@property (nonatomic, weak) id previewTarget;
@property (nonatomic) BOOL previewOn;
@property (nonatomic) BOOL fileTreeOn;
@property (nonatomic) BOOL outlineOn;
@end

@implementation StatusBarView

- (void)drawRect:(NSRect)dirtyRect {
	(void)dirtyRect;
	[[NSColor windowBackgroundColor] setFill];
	NSRectFill(self.bounds);
	[[NSColor separatorColor] setFill];
	NSRectFill(NSMakeRect(0, self.bounds.size.height - 1, self.bounds.size.width, 1));
}

- (instancetype)initWithFrame:(NSRect)frame {
	self = [super initWithFrame:frame];
	if (self) {
		self.wantsLayer = YES;
		_cells = [NSMutableArray array];
		[self buildCells];
	}
	return self;
}

- (NSArray<NSNumber *> *)widthsForLanguage {
	if (NPLanguageIsCJK()) {
		return @[@0, @80, @104, @86, @66, @56, @0, @110, @56, @44, @34, @40, @56];
	}
	return @[@0, @64, @64, @64, @52, @44, @0, @110, @56, @44, @34, @40, @56];
}

- (NPStatusPreviewButton *)makeToggle:(NSString *)title action:(SEL)act on:(BOOL)on {
	NPStatusPreviewButton *b = [[NPStatusPreviewButton alloc] initWithFrame:NSZeroRect];
	b.bordered = NO;
	b.buttonType = NSButtonTypeMomentaryChange;
	b.focusRingType = NSFocusRingTypeNone;
	b.title = title;
	b.toolTip = title;
	b.target = _previewTarget;
	b.action = act;
	b.previewOn = on;
	b.translatesAutoresizingMaskIntoConstraints = NO;
	[self addSubview:b];
	[b.centerYAnchor constraintEqualToAnchor:self.centerYAnchor].active = YES;
	[b.heightAnchor constraintEqualToConstant:18].active = YES;
	[b.widthAnchor constraintGreaterThanOrEqualToConstant:44].active = YES;
	return b;
}

- (void)rebuildPreviewButton {
	if (_previewBtn) [_previewBtn removeFromSuperview];
	if (_treeBtn) [_treeBtn removeFromSuperview];
	if (_outlineBtn) [_outlineBtn removeFromSuperview];
	_previewBtn = [self makeToggle:NPL(@"Preview") action:@selector(viewPreview) on:_previewOn];
	[_previewBtn.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:4].active = YES;
	_treeBtn = [self makeToggle:NPL(@"Files") action:@selector(viewFileTree) on:_fileTreeOn];
	[_treeBtn.leadingAnchor constraintEqualToAnchor:_previewBtn.trailingAnchor constant:4].active = YES;
	_outlineBtn = [self makeToggle:NPL(@"Outline") action:@selector(viewOutline) on:_outlineOn];
	[_outlineBtn.leadingAnchor constraintEqualToAnchor:_treeBtn.trailingAnchor constant:4].active = YES;
}

- (void)buildCells {
	for (NSView *v in [self.subviews copy]) [v removeFromSuperview];
	[_cells removeAllObjects];
	[self rebuildPreviewButton];

	NSArray<NSNumber *> *widths = [self widthsForLanguage];
	NSView *prev = _outlineBtn ?: _treeBtn ?: _previewBtn;
	NSView *sep0 = [[NSView alloc] initWithFrame:NSZeroRect];
	sep0.wantsLayer = YES;
	sep0.layer.backgroundColor = [NSColor separatorColor].CGColor;
	sep0.translatesAutoresizingMaskIntoConstraints = NO;
	[self addSubview:sep0];
	[sep0.widthAnchor constraintEqualToConstant:1].active = YES;
	[sep0.heightAnchor constraintEqualToConstant:14].active = YES;
	[sep0.centerYAnchor constraintEqualToAnchor:self.centerYAnchor].active = YES;
	[prev.trailingAnchor constraintEqualToAnchor:sep0.leadingAnchor constant:-4].active = YES;
	prev = sep0;

	for (NSUInteger i = 0; i < widths.count; i++) {
		NSTextField *f = [NSTextField labelWithString:@""];
		f.font = [NSFont monospacedDigitSystemFontOfSize:11 weight:NSFontWeightRegular];
		f.textColor = [NSColor labelColor];
		f.alignment = NSTextAlignmentCenter;
		f.lineBreakMode = NSLineBreakByClipping;
		f.translatesAutoresizingMaskIntoConstraints = NO;
		[self addSubview:f];
		[f.centerYAnchor constraintEqualToAnchor:self.centerYAnchor].active = YES;
		[f.heightAnchor constraintEqualToConstant:16].active = YES;
		if (widths[i].doubleValue > 0) {
			[f.widthAnchor constraintEqualToConstant:widths[i].doubleValue].active = YES;
		}
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
			prev = f;
		} else {
			[f.leadingAnchor constraintEqualToAnchor:prev.trailingAnchor constant:4].active = YES;
			prev = f;
		}
		[_cells addObject:f];
	}
	[self.trailingAnchor constraintGreaterThanOrEqualToAnchor:prev.trailingAnchor constant:6].active = YES;
}

- (void)applyLanguage {
	[self buildCells];
}

- (void)setPreviewTarget:(id)target {
	_previewTarget = target;
	_previewBtn.target = target;
	_previewBtn.action = @selector(viewPreview);
	_treeBtn.target = target;
	_treeBtn.action = @selector(viewFileTree);
	_outlineBtn.target = target;
	_outlineBtn.action = @selector(viewOutline);
}

- (void)setPreviewActive:(BOOL)on {
	_previewOn = on;
	_previewBtn.previewOn = on;
	_previewBtn.needsDisplay = YES;
}

- (void)setFileTreeActive:(BOOL)on {
	_fileTreeOn = on;
	_treeBtn.previewOn = on;
	_treeBtn.needsDisplay = YES;
}

- (void)setOutlineActive:(BOOL)on {
	_outlineOn = on;
	_outlineBtn.previewOn = on;
	_outlineBtn.needsDisplay = YES;
}

- (NSButton *)previewButton { return _previewBtn; }
- (NSButton *)fileTreeButton { return _treeBtn; }
- (NSButton *)outlineButton { return _outlineBtn; }
- (NSString *)cellTextAtIndex:(NSUInteger)i {
	return [self cellAt:i].stringValue ?: @"";
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
	const sptr_t lineEnd = [e message:SCI_GETLINEENDPOSITION wParam:line];
	const sptr_t col = [e message:SCI_GETCOLUMN wParam:pos];
	const sptr_t lineLen = [e message:SCI_GETCOLUMN wParam:lineEnd];
	const sptr_t chPos = [e message:SCI_COUNTCHARACTERS wParam:0 lParam:pos];
	const sptr_t chLen = [e message:SCI_COUNTCHARACTERS wParam:0 lParam:[e message:SCI_GETLENGTH]];

	const sptr_t selStart = [e message:SCI_GETSELECTIONSTART];
	const sptr_t selEnd = [e message:SCI_GETSELECTIONEND];
	const sptr_t selBytes = (selEnd > selStart) ? (selEnd - selStart) : 0;
	const sptr_t selChars = (selEnd > selStart) ? [e message:SCI_COUNTCHARACTERS wParam:selStart lParam:selEnd] : 0;
	sptr_t selLines = 0;
	if (selEnd > selStart) {
		selLines = [e message:SCI_LINEFROMPOSITION wParam:selEnd]
			- [e message:SCI_LINEFROMPOSITION wParam:selStart] + 1;
	}

	[self cellAt:0].stringValue = [NSString stringWithFormat:NPL(@"Ln %@ / %@"),
		Num(line + 1), Num(lines)];
	[self cellAt:1].stringValue = [NSString stringWithFormat:NPL(@"Col %@ / %@"),
		Num(col + 1), Num(lineLen + 1)];
	[self cellAt:2].stringValue = [NSString stringWithFormat:NPL(@"Ch %@ / %@"),
		Num(chPos + 1), Num(chLen + 1)];
	[self cellAt:3].stringValue = [NSString stringWithFormat:NPL(@"Sel %@ / %@"),
		Num(selBytes), Num(selChars)];
	[self cellAt:4].stringValue = [NSString stringWithFormat:NPL(@"SelLn %@"), Num(selLines)];
	[self cellAt:5].stringValue = NPL(@"Fnd 0");

	const EDITLEXER *lex = doc.currentLexer;
	[self cellAt:6].stringValue = lex ? WStr2(lex->pszName) : NPL(@"Text File");
	[self cellAt:7].stringValue = doc.currentEncoding ?: @"UTF-8";
	const sptr_t eol = [e message:SCI_GETEOLMODE];
	[self cellAt:8].stringValue = (eol == SC_EOL_CRLF) ? @"CR+LF"
		: (eol == SC_EOL_CR) ? @"CR" : @"LF";
	const BOOL ovr = [e message:SCI_GETOVERTYPE];
	[self cellAt:9].stringValue = ovr ? NPL(@"OVR") : NPL(@"INS");
	const long zoom = [e message:SCI_GETZOOM];
	[self cellAt:10].stringValue = [NSString stringWithFormat:@"%ld%%", zoom > 0 ? zoom : 100];
	const sptr_t len = [e message:SCI_GETLENGTH];
	NSString *sizeStr;
	if (len < 1024) sizeStr = [NSString stringWithFormat:@"%ld B", (long)len];
	else if (len < 1024*1024) sizeStr = [NSString stringWithFormat:@"%.1f KB", len/1024.0];
	else sizeStr = [NSString stringWithFormat:@"%.1f MB", len/1048576.0];
	[self cellAt:11].stringValue = sizeStr;
}

@end
