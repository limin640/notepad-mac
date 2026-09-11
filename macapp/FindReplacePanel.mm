#import "FindReplacePanel.h"
#import "NPLocalization.h"
#import "EditorDocument.h"
#import "ScintillaView.h"
#import "Scintilla.h"
#include <cstring>

@interface FindReplacePanel () <NSSearchFieldDelegate, NSTextFieldDelegate>
@end

// Scintilla 正则 flag（SCFIND_REGEXP 等在 Scintilla.h）
@interface FindReplacePanel ()

@property (nonatomic, strong) NSSearchField *findField;
@property (nonatomic, strong) NSTextField *replaceField;
@property (nonatomic, strong) NSButton *caseCheck;
@property (nonatomic, strong) NSButton *wordCheck;
@property (nonatomic, strong) NSButton *regexCheck;
@property (nonatomic, strong) NSStackView *replaceRow;
@property (nonatomic, unsafe_unretained) NSWindow *hostWindow;

@end

@implementation FindReplacePanel

- (instancetype)initWithFrame:(NSRect)frame {
	self = [super initWithFrame:frame];
	if (self) {
		[self buildUI];
		self.hidden = YES;
	}
	return self;
}

- (void)buildUI {
	self.wantsLayer = YES;
	self.layer.backgroundColor = [[NSColor controlBackgroundColor] colorWithAlphaComponent:0.98].CGColor;

	NSStackView *stack = [NSStackView stackViewWithViews:@[]];
	stack.orientation = NSUserInterfaceLayoutOrientationVertical;
	stack.alignment = NSLayoutAttributeLeading;
	stack.edgeInsets = NSEdgeInsetsMake(8, 12, 8, 12);
	stack.spacing = 6;
	stack.translatesAutoresizingMaskIntoConstraints = NO;
	[self addSubview:stack];
	[self.leadingAnchor constraintEqualToAnchor:stack.leadingAnchor].active = YES;
	[self.trailingAnchor constraintEqualToAnchor:stack.trailingAnchor].active = YES;
	[self.topAnchor constraintEqualToAnchor:stack.topAnchor].active = YES;
	[self.bottomAnchor constraintEqualToAnchor:stack.bottomAnchor].active = YES;

	// 查找行
	self.findField = [[NSSearchField alloc] init];
	self.findField.placeholderString = NPL(@"Find");
	self.findField.delegate = self;
	self.findField.translatesAutoresizingMaskIntoConstraints = NO;
	[self.findField.widthAnchor constraintEqualToConstant:320].active = YES;

	self.caseCheck = [NSButton checkboxWithTitle:NPL(@"Match Case") target:self action:@selector(refind:)];
	self.wordCheck = [NSButton checkboxWithTitle:NPL(@"Whole Word") target:self action:@selector(refind:)];
	self.regexCheck = [NSButton checkboxWithTitle:[NPL(@"Regex") stringByAppendingString:@" ⌥⌘R"] target:self action:@selector(refind:)];

	NSButton *prevBtn = [NSButton buttonWithTitle:NPL(@"Previous") target:self action:@selector(prev:)];
	NSButton *nextBtn = [NSButton buttonWithTitle:NPL(@"Next") target:self action:@selector(next:)];
	nextBtn.keyEquivalent = @"\r";

	NSStackView *row1 = [NSStackView stackViewWithViews:@[self.findField, prevBtn, nextBtn,
		self.caseCheck, self.wordCheck, self.regexCheck]];
	row1.spacing = 8;

	// 替换行
	self.replaceField = [[NSTextField alloc] init];
	self.replaceField.placeholderString = NPL(@"Replace With");
	self.replaceField.translatesAutoresizingMaskIntoConstraints = NO;
	[self.replaceField.widthAnchor constraintEqualToConstant:320].active = YES;

	NSButton *repOne = [NSButton buttonWithTitle:NPL(@"Replace") target:self action:@selector(clickReplaceOne:)];
	NSButton *repAll = [NSButton buttonWithTitle:NPL(@"Replace All") target:self action:@selector(clickReplaceAll:)];
	self.replaceRow = [NSStackView stackViewWithViews:@[self.replaceField, repOne, repAll]];
	self.replaceRow.spacing = 8;

	[stack addArrangedSubview:row1];
	[stack addArrangedSubview:self.replaceRow];
	for (NSView *v in stack.arrangedSubviews) { [stack setVisibilityPriority:NSStackViewVisibilityPriorityMustHold forView:v]; }
}

// 切换语言：保留当前输入内容重建控件
- (void)applyLanguage {
	NSString *f = self.findField.stringValue;
	NSString *r = self.replaceField.stringValue;
	for (NSView *v in [self.subviews copy]) [v removeFromSuperview];
	[self buildUI];
	self.findField.stringValue = f ?: @"";
	self.replaceField.stringValue = r ?: @"";
}

- (NSString *)currentFindText { return self.findField.stringValue ?: @""; }

- (void)attachToWindow:(NSWindow *)window {
	self.hostWindow = window;
	self.translatesAutoresizingMaskIntoConstraints = NO;
	[window.contentView addSubview:self positioned:NSWindowAbove relativeTo:nil];
	[self.widthAnchor constraintEqualToAnchor:window.contentView.widthAnchor].active = YES;
	[self.heightAnchor constraintEqualToConstant:84].active = YES;
	// 底部贴边（显示时编辑区让位由主控制器处理）

	[self.leadingAnchor constraintEqualToAnchor:window.contentView.leadingAnchor].active = YES;
	self.hidden = YES;
}

- (void)showFind:(BOOL)replaceVisible {
	self.hidden = NO;
	self.replaceRow.hidden = !replaceVisible;
	[self.findField.window makeFirstResponder:self.findField];
}

- (void)toggle {
	if (self.hidden) {
		[self showFind:NO];
	} else {
		self.hidden = YES;
		[self.hostWindow makeFirstResponder:nil];
	}
}

#pragma mark - 搜索执行

- (int)searchFlags {
	int flags = 0;
	if (self.caseCheck.state == NSControlStateValueOn) flags |= SCFIND_MATCHCASE;
	if (self.wordCheck.state == NSControlStateValueOn) flags |= SCFIND_WHOLEWORD;
	if (self.regexCheck.state == NSControlStateValueOn) flags |= SCFIND_REGEXP;
	return flags;
}

- (void)refind:(id)sender {
	// 参数变化即重新定位当前命中
	NSWindow *win = self.hostWindow;
	NSResponder *fr = [win firstResponder];
	if ([fr isKindOfClass:[SCIContentView class]]) {
		SCIContentView *cv = (SCIContentView *)fr;
		// 通过 ScintillaView 找回文档逻辑简化：主控制器持有
	}
}

- (EditorDocument *)hostDocument {
	id wc = self.hostWindow.windowController;
	if ([wc respondsToSelector:@selector(editorDocument)])
		return [wc performSelector:@selector(editorDocument)];
	return nil;
}

- (void)next:(id)sender {
	EditorDocument *doc = [self hostDocument];
	if (doc) [self findNext:doc];
}

- (void)prev:(id)sender {
	EditorDocument *doc = [self hostDocument];
	if (doc) [self findPrevious:doc];
}

- (void)clickReplaceOne:(id)sender {
	EditorDocument *doc = [self hostDocument];
	if (doc) [self replaceOne:doc];
}

- (void)clickReplaceAll:(id)sender {
	EditorDocument *doc = [self hostDocument];
	if (doc) [self replaceAll:doc];
}

- (void)replaceOne:(EditorDocument *)doc {
	NSString *find = self.findField.stringValue;
	NSString *repl = self.replaceField.stringValue ?: @"";
	if (!find.length || !doc) return;
	[doc.editor message:SCI_REPLACESEL wParam:0 lParam:(sptr_t)repl.UTF8String];
	[self findInDoc:doc backwards:NO];
}

- (void)replaceAll:(EditorDocument *)doc {
	NSString *find = self.findField.stringValue;
	NSString *repl = self.replaceField.stringValue ?: @"";
	if (!find.length || !doc) return;
	const int flags = [self searchFlags];
	const char *findC = find.UTF8String;
	const char *replC = repl.UTF8String;
	const sptr_t findN = (sptr_t)strlen(findC);
	const sptr_t replN = (sptr_t)strlen(replC);
	[doc.editor message:SCI_SETSEARCHFLAGS wParam:flags lParam:0];
	long total = 0;
	sptr_t pos = 0;
	while (1) {
		[doc.editor message:SCI_SETTARGETSTART wParam:pos lParam:0];
		[doc.editor message:SCI_SETTARGETEND wParam:(sptr_t)[doc.editor message:SCI_GETLENGTH] lParam:0];
		const sptr_t found = [doc.editor message:SCI_SEARCHINTARGET wParam:findN lParam:(sptr_t)findC];
		if (found < 0) break;
		[doc.editor message:SCI_REPLACETARGET wParam:replN lParam:(sptr_t)replC];
		total++;
		pos = [doc.editor message:SCI_GETTARGETEND];
		if (pos >= (sptr_t)[doc.editor message:SCI_GETLENGTH]) break;
	}
	if ([[[NSProcessInfo processInfo] arguments] containsObject:@"--headless"]) return;
	NSAlert *a = [[NSAlert alloc] init];
	a.messageText = total ? [NSString stringWithFormat:NPL(@"Replaced %ld occurrences"), total] : NPL(@"No matches found");
	[a addButtonWithTitle:NPL(@"OK")];
	if (self.hostWindow)
		[a beginSheetModalForWindow:self.hostWindow completionHandler:^(NSModalResponse r) {}];
	else
		[a runModal];
}

- (void)findInDoc:(EditorDocument *)doc backwards:(BOOL)backwards {
	NSString *find = self.findField.stringValue;
	if (!find.length) return;
	const int flags = [self searchFlags];
	ScintillaView *e = doc.editor;
	const sptr_t len = [e message:SCI_GETLENGTH];
	sptr_t start = [e message:SCI_GETSELECTIONEND];
	sptr_t end = len;
	if (backwards) {
		start = [e message:SCI_GETSELECTIONSTART];
		end = 0;
	}
	[e message:SCI_SETSEARCHFLAGS wParam:flags lParam:0];
	[e message:SCI_SETTARGETSTART wParam:start lParam:0];
	[e message:SCI_SETTARGETEND wParam:end lParam:0];
	const char *findC = find.UTF8String;
	const sptr_t findN = (sptr_t)strlen(findC);
	const sptr_t found = [e message:SCI_SEARCHINTARGET wParam:findN lParam:(sptr_t)findC];
	if (found >= 0) {
		const sptr_t fEnd = [e message:SCI_GETTARGETEND];
		[e message:SCI_SETSELECTION wParam:found lParam:fEnd];
		[e message:SCI_SCROLLCARET wParam:0 lParam:0];
	} else if (!backwards && start > 0) {
		// wrap 到头重找
		[e message:SCI_SETTARGETSTART wParam:0 lParam:0];
		[e message:SCI_SETTARGETEND wParam:len lParam:0];
		const sptr_t f2 = [e message:SCI_SEARCHINTARGET wParam:findN lParam:(sptr_t)findC];
		if (f2 >= 0) {
			const sptr_t f2e = [e message:SCI_GETTARGETEND];
			[e message:SCI_SETSELECTION wParam:f2 lParam:f2e];
			[e message:SCI_SCROLLCARET wParam:0 lParam:0];
		}
	}
}

- (void)findNext:(EditorDocument *)doc {
	[self findInDoc:doc backwards:NO];
}

- (void)findPrevious:(EditorDocument *)doc {
	[self findInDoc:doc backwards:YES];
}

@end
