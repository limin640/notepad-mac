// Notepad4 主题：颜色值全部取自源码
//   亮色 = EditLexers/stlDefault.cpp 的 Styles_Global
//   暗色 = doc/Notepad4 DarkTheme.ini
#pragma once
#import <Cocoa/Cocoa.h>

typedef NS_ENUM(NSInteger, NPThemeKind) {
	NPThemeDefault = 0,   // StyleTheme_Default
	NPThemeDark = 1,      // StyleTheme_Dark
};

typedef struct NPThemeColors {
	uint32_t defFore, defBack;          // Default Code Style
	uint32_t marginFore, marginBack;    // Margin and Line Number (size:-2)
	uint32_t caretFore;                 // SC_ELEMENT_CARET
	uint32_t caretLineFrame;            // Current Line (outline frame)
	uint32_t foldFore, foldBack;        // Folding Marker
	uint32_t foldLine;                  // Code Folding fore
	uint32_t indentGuide;               // Indentation Guide
	uint32_t whitespace;                // Whitespace
	uint32_t controlCharFore, controlCharBack;
	uint32_t selBack;                   // Selected Text (alpha:95 outline:50)
	uint32_t longLine;                  // Long Line Marker
	uint32_t link;                      // Link
	uint32_t foldEllipsis;              // Fold Ellipsis fore
} NPThemeColors;

// 亮色：stlDefault.cpp Styles_Global
static const NPThemeColors kNPThemeLight = {
	.defFore = 0x000000, .defBack = 0xFFFFFF,
	.marginFore = 0x2B91AF, .marginBack = 0xFFFFFF,
	.caretFore = 0x000000,
	.caretLineFrame = 0xC2C0C3,
	.foldFore = 0x8080FF, .foldBack = 0xADD8E6,
	.foldLine = 0x808080,
	.indentGuide = 0xFF8000,
	.whitespace = 0xFF4000,
	.controlCharFore = 0x108010, .controlCharBack = 0x228B22,
	.selBack = 0x3399FF,
	.longLine = 0xFFC000,
	.link = 0x648000,
	.foldEllipsis = 0x808080,
};

// 暗色：Notepad4 DarkTheme.ini
static const NPThemeColors kNPThemeDark = {
	.defFore = 0xD4D4D4, .defBack = 0x1E1E1E,
	.marginFore = 0xA0A0A0, .marginBack = 0x2A2A2E,
	.caretFore = 0xFFFFFF,
	.caretLineFrame = 0xC2C0C3,
	.foldFore = 0x808080, .foldBack = 0x606060,
	.foldLine = 0xFF8000,
	.indentGuide = 0x605F63,
	.whitespace = 0xFF4000,
	.controlCharFore = 0x108010, .controlCharBack = 0x228B22,
	.selBack = 0x264F78,
	.longLine = 0x605F63,
	.link = 0x648000,
	.foldEllipsis = 0x606060,
};

#ifdef __cplusplus
extern "C" {
#endif
const NPThemeColors *NPThemeColorsFor(NPThemeKind kind);
#ifdef __cplusplus
}
#endif

@class ScintillaView;
struct EDITLEXER;
// 应用主题到编辑器（lex 可为 NULL）
void NPApplyTheme(ScintillaView *editor, NPThemeKind kind, const struct EDITLEXER *lex);
