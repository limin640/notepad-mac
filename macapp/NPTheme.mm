#import "NPTheme.h"
#import "EditorDocument.h"
#import "ScintillaView.h"
#import "Scintilla.h"
#import "SciLexer.h"
#import "LexerRegistry.h"

const NPThemeColors *NPThemeColorsFor(NPThemeKind kind) {
	return (kind == NPThemeDark) ? &kNPThemeDark : &kNPThemeLight;
}

// 0xRRGGBB -> Scintilla 的 0x00BBGGRR（Windows COLORREF）
static inline sptr_t ScRGB(uint32_t rgb) {
	return (sptr_t)(((rgb & 0xFF) << 16) | (rgb & 0xFF00) | ((rgb >> 16) & 0xFF));
}
// colouralpha = 0xAABBGGRR
static inline sptr_t ScRGBA(uint32_t rgb, uint32_t alpha) {
	return (sptr_t)((alpha << 24) | (uint32_t)ScRGB(rgb));
}

static NSString *const NPThemeModeKey = @"NPThemeMode";
static BOOL sModeOverride = NO;
static NPThemeMode sModeOverrideValue = NPThemeModeAuto;

// 主题模式（默认跟随系统）
NPThemeMode NPThemeModeGet(void) {
	if (sModeOverride) return sModeOverrideValue;
	NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
	if ([d objectForKey:NPThemeModeKey] == nil) return NPThemeModeAuto;
	const NSInteger v = [d integerForKey:NPThemeModeKey];
	return (v == NPThemeModeLight || v == NPThemeModeDark) ? (NPThemeMode)v : NPThemeModeAuto;
}

// 只应用外观（nil = 跟随系统）
static void NPThemeAppearanceApply(NPThemeMode mode) {
	switch (mode) {
	case NPThemeModeLight:
		NSApp.appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
		break;
	case NPThemeModeDark:
		NSApp.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
		break;
	default:
		NSApp.appearance = nil;
		break;
	}
}

// 写盘 + 应用外观
void NPThemeModeSet(NPThemeMode mode) {
	[[NSUserDefaults standardUserDefaults] setInteger:mode forKey:NPThemeModeKey];
	NPThemeAppearanceApply(mode);
}

void NPThemeModeOverrideForTesting(NPThemeMode mode) {
	sModeOverride = YES;
	sModeOverrideValue = mode;
	NPThemeAppearanceApply(mode);
}

// 按模式解析出实际生效的编辑器主题
NPThemeKind NPThemeResolve(NPThemeMode mode) {
	if (mode == NPThemeModeLight) return NPThemeDefault;
	if (mode == NPThemeModeDark) return NPThemeDark;
	NSAppearance *eff = NSApp.effectiveAppearance ?: NSAppearance.currentDrawingAppearance;
	NSString *best = [eff bestMatchFromAppearancesWithNames:
		@[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]];
	return [best isEqualToString:NSAppearanceNameDarkAqua] ? NPThemeDark : NPThemeDefault;
}

// 应用主题：全局样式 + 边距 + 光标 + 折叠 + 当前行，并重刷词法器配色
void NPApplyTheme(ScintillaView *e, NPThemeKind kind, const EDITLEXER *lex) {
	const NPThemeColors *c = NPThemeColorsFor(kind);

	// 1. 默认样式
	[e setColorProperty:SCI_STYLESETFORE parameter:STYLE_DEFAULT fromHTML:
		[NSString stringWithFormat:@"#%06X", c->defFore]];
	[e setColorProperty:SCI_STYLESETBACK parameter:STYLE_DEFAULT fromHTML:
		[NSString stringWithFormat:@"#%06X", c->defBack]];
	[e message:SCI_STYLECLEARALL wParam:0 lParam:0];

	// 2. 行号边距：size:-2
	[e setColorProperty:SCI_STYLESETFORE parameter:STYLE_LINENUMBER fromHTML:
		[NSString stringWithFormat:@"#%06X", c->marginFore]];
	[e setColorProperty:SCI_STYLESETBACK parameter:STYLE_LINENUMBER fromHTML:
		[NSString stringWithFormat:@"#%06X", c->marginBack]];
	const long baseSize = [e getGeneralProperty:SCI_STYLEGETSIZE parameter:STYLE_DEFAULT];
	[e setGeneralProperty:SCI_STYLESETSIZE parameter:STYLE_LINENUMBER value:baseSize - 2];

	// 3. 光标：SC_ELEMENT_CARET = fore
	[e message:SCI_SETELEMENTCOLOUR wParam:SC_ELEMENT_CARET
		lParam:ScRGBA(c->caretFore, 0xFF)];

	// 4. 当前行：outline frame（Notepad4 默认 HighlightCurrentLine = subline + OutlineFrame）
	// 对照 Notepad4 Style_HighlightCurrentLine()：OutlineFrame 模式取 fore 色 + outline 透明度，
	// 并置于 SC_LAYER_UNDER_TEXT，否则 Scintilla 把边框画成不透明实色（暗色下即一条白带）
	[e message:SCI_SETCARETLINEVISIBLEALWAYS wParam:1 lParam:0];
	[e message:SCI_SETCARETLINEFRAME wParam:2 lParam:0];
	[e message:SCI_SETCARETLINEHIGHLIGHTSUBLINE wParam:1 lParam:0];
	[e message:SCI_SETCARETLINELAYER wParam:SC_LAYER_UNDER_TEXT lParam:0];
	[e message:SCI_SETELEMENTCOLOUR wParam:SC_ELEMENT_CARET_LINE_BACK
		lParam:ScRGBA(c->caretLineFrame, c->caretLineAlpha)];

	// 5. 缩进线 / 空白 / 行尾（默认关，仅设颜色）
	[e message:SCI_SETINDENTATIONGUIDES wParam:SC_IV_NONE lParam:0];
	[e setColorProperty:SCI_STYLESETFORE parameter:STYLE_INDENTGUIDE fromHTML:
		[NSString stringWithFormat:@"#%06X", c->indentGuide]];
	[e message:SCI_SETELEMENTCOLOUR wParam:SC_ELEMENT_WHITE_SPACE
		lParam:ScRGBA(c->whitespace, 0xFF)];
	[e message:SCI_SETVIEWWS wParam:SCWS_INVISIBLE lParam:0];
	[e message:SCI_SETVIEWEOL wParam:0 lParam:0];

		// 折叠边距背景：默认取平台 chrome 色（浅灰棋盘），必须覆盖为文档背景
	// 对照 Styles.cpp:1674-1675 SetFoldMarginColor/SetFoldMarginHiColor
	[e message:SCI_SETFOLDMARGINCOLOUR wParam:1 lParam:ScRGB(c->defBack)];
	[e message:SCI_SETFOLDMARGINHICOLOUR wParam:1 lParam:ScRGB(c->defBack)];
	[e message:SCI_MARKERDEFINE wParam:SC_MARKNUM_FOLDEROPEN lParam:SC_MARK_BOXMINUS];
	[e message:SCI_MARKERDEFINE wParam:SC_MARKNUM_FOLDER lParam:SC_MARK_BOXPLUS];
	[e message:SCI_MARKERDEFINE wParam:SC_MARKNUM_FOLDERSUB lParam:SC_MARK_VLINE];
	[e message:SCI_MARKERDEFINE wParam:SC_MARKNUM_FOLDERTAIL lParam:SC_MARK_LCORNER];
	[e message:SCI_MARKERDEFINE wParam:SC_MARKNUM_FOLDEREND lParam:SC_MARK_BOXPLUSCONNECTED];
	[e message:SCI_MARKERDEFINE wParam:SC_MARKNUM_FOLDEROPENMID lParam:SC_MARK_BOXMINUSCONNECTED];
	[e message:SCI_MARKERDEFINE wParam:SC_MARKNUM_FOLDERMIDTAIL lParam:SC_MARK_TCORNER];
	// 对照 Styles.cpp: MarkerSetBack(foreColor) / MarkerSetFore(backColor)
	for (int m = SC_MARKNUM_FOLDEREND; m <= SC_MARKNUM_FOLDEROPEN; m++) {
		[e message:SCI_MARKERSETBACKTRANSLUCENT wParam:m lParam:ScRGBA(c->foldFore, 0xFF)];
		[e message:SCI_MARKERSETFORETRANSLUCENT wParam:m lParam:ScRGBA(c->foldBack, 0xFF)];
	}
	[e message:SCI_MARKERSETFORETRANSLUCENT wParam:SC_MARKNUM_FOLDERSUB lParam:ScRGBA(c->foldLine, 0xFF)];
	[e message:SCI_MARKERSETBACKTRANSLUCENT wParam:SC_MARKNUM_FOLDERSUB lParam:ScRGBA(c->foldLine, 0xFF)];
	[e message:SCI_MARKERSETFORETRANSLUCENT wParam:SC_MARKNUM_FOLDERTAIL lParam:ScRGBA(c->foldLine, 0xFF)];
	[e message:SCI_MARKERSETBACKTRANSLUCENT wParam:SC_MARKNUM_FOLDERTAIL lParam:ScRGBA(c->foldLine, 0xFF)];
	[e message:SCI_MARKERSETFORETRANSLUCENT wParam:SC_MARKNUM_FOLDERMIDTAIL lParam:ScRGBA(c->foldLine, 0xFF)];
	[e message:SCI_MARKERSETBACKTRANSLUCENT wParam:SC_MARKNUM_FOLDERMIDTAIL lParam:ScRGBA(c->foldLine, 0xFF)];
	[e message:SCI_SETFOLDFLAGS wParam:0 lParam:0];

	// 7. 折叠省略号
	[e setColorProperty:SCI_STYLESETFORE parameter:STYLE_FOLDDISPLAYTEXT fromHTML:
		[NSString stringWithFormat:@"#%06X", c->foldEllipsis]];
	[e setGeneralProperty:SCI_STYLESETBOLD parameter:STYLE_FOLDDISPLAYTEXT value:1];

	// 8. 选区
	[e message:SCI_SETELEMENTCOLOUR wParam:SC_ELEMENT_SELECTION_BACK
		lParam:ScRGBA(c->selBack, 0xFF)];

	// 9. 长行标记 / 链接
	[e message:SCI_SETEDGECOLOUR wParam:ScRGB(c->longLine) lParam:0];
	[e setColorProperty:SCI_STYLESETFORE parameter:STYLE_LINK fromHTML:
		[NSString stringWithFormat:@"#%06X", c->link]];

	// 10. 词法器样式（含 per-lexer 颜色；暗色主题下 stl 定义的白底黑字需要反相）
	if (lex) {
		[LexerRegistry applyLexer:lex toEditor:e darkMode:(kind == NPThemeDark)];
	}
	[e message:SCI_COLOURISE wParam:0 lParam:-1];
	[e setNeedsDisplay:YES];
}
