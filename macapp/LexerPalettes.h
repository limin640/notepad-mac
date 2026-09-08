// 分词法器族的默认配色（对齐 notepad4 浅色主题）
// 每族一份 {样式号 -> 颜色/斜体} 表；未覆盖的样式号继承 STYLE_DEFAULT（黑）
#import <Cocoa/Cocoa.h>
#import "ScintillaView.h"
#import "SciLexer.h"

namespace Palette {

struct StyleColor {
	int style;
	const char *fore;
	BOOL italic;
	BOOL bold;
};

// --- C 族（cpp objc java csharp javascript go rust swift zig kotlin scala d groovy ...）---
static const StyleColor kC[] = {
	{SCE_C_COMMENT, "#008000", YES, NO},
	{SCE_C_COMMENTLINE, "#008000", YES, NO},
	{SCE_C_COMMENTDOC, "#008000", YES, NO},
	{SCE_C_COMMENTLINEDOC, "#008000", YES, NO},
	{SCE_C_WORD, "#0000FF", NO, NO},
	{SCE_C_WORD2, "#0000FF", NO, NO},
	{SCE_C_PREPROCESSOR, "#804000", NO, NO},
	{SCE_C_DIRECTIVE, "#804000", NO, NO},
	{SCE_C_STRING, "#A31515", NO, NO},
	{SCE_C_CHARACTER, "#A31515", NO, NO},
	{SCE_C_STRINGRAW, "#A31515", NO, NO},
	{SCE_C_STRINGEOL, "#A31515", NO, NO},
	{SCE_C_ESCAPECHAR, "#A31515", NO, NO},
	{SCE_C_NUMBER, "#B8860B", NO, NO},
	{SCE_C_OPERATOR, "#404040", NO, NO},
};

// --- Python 族（python nim）---
static const StyleColor kPy[] = {
	{SCE_PY_COMMENTLINE, "#008000", YES, NO},
	{SCE_PY_COMMENTBLOCK, "#008000", YES, NO},
	{SCE_PY_TASKMARKER, "#008000", YES, NO},
	{SCE_PY_WORD, "#0000FF", NO, NO},
	{SCE_PY_WORD2, "#0000FF", NO, NO},
	{SCE_PY_DECORATOR, "#804000", NO, NO},
	{SCE_PY_BUILTIN_FUNCTION, "#7A3E9D", NO, NO},
	{SCE_PY_BUILTIN_CONSTANT, "#7A3E9D", NO, NO},
	{SCE_PY_CLASS, "#2B91AF", NO, NO},
	{SCE_PY_FUNCTION_DEFINITION, "#7A3E9D", NO, NO},
	{SCE_PY_NUMBER, "#B8860B", NO, NO},
	{SCE_PY_OPERATOR, "#404040", NO, NO},
	{SCE_PY_STRING_SQ, "#A31515", NO, NO},
	{SCE_PY_STRING_DQ, "#A31515", NO, NO},
	{SCE_PY_TRIPLE_STRING_SQ, "#A31515", NO, NO},
	{SCE_PY_TRIPLE_STRING_DQ, "#A31515", NO, NO},
	{SCE_PY_RAWSTRING_SQ, "#A31515", NO, NO},
	{SCE_PY_RAWSTRING_DQ, "#A31515", NO, NO},
	{SCE_PY_TRIPLE_RAWSTRING_SQ, "#A31515", NO, NO},
	{SCE_PY_TRIPLE_RAWSTRING_DQ, "#A31515", NO, NO},
	{SCE_PY_FMTSTRING_SQ, "#A31515", NO, NO},
	{SCE_PY_FMTSTRING_DQ, "#A31515", NO, NO},
	{SCE_PY_TRIPLE_FMTSTRING_SQ, "#A31515", NO, NO},
	{SCE_PY_TRIPLE_FMTSTRING_DQ, "#A31515", NO, NO},
	{SCE_PY_BYTES_SQ, "#A31515", NO, NO},
	{SCE_PY_BYTES_DQ, "#A31515", NO, NO},
};

// --- JSON ---
static const StyleColor kJson[] = {
	{SCE_JSON_LINECOMMENT, "#008000", YES, NO},
	{SCE_JSON_BLOCKCOMMENT, "#008000", YES, NO},
	{SCE_JSON_PROPERTYNAME, "#0451A5", NO, NO},
	{SCE_JSON_STRING_DQ, "#A31515", NO, NO},
	{SCE_JSON_STRING_SQ, "#A31515", NO, NO},
	{SCE_JSON_ESCAPECHAR, "#A31515", NO, NO},
	{SCE_JSON_NUMBER, "#B8860B", NO, NO},
	{SCE_JSON_KEYWORD, "#0000FF", NO, NO},
	{SCE_JSON_OPERATOR, "#404040", NO, NO},
};

// --- YAML ---
static const StyleColor kYaml[] = {
	{SCE_YAML_COMMENT, "#008000", YES, NO},
	{SCE_YAML_IDENTIFIER, "#0451A5", NO, NO},
	{SCE_YAML_KEYWORD, "#0000FF", NO, NO},
	{SCE_YAML_NUMBER, "#B8860B", NO, NO},
	{SCE_YAML_STRING_SQ, "#A31515", NO, NO},
	{SCE_YAML_STRING_DQ, "#A31515", NO, NO},
	{SCE_YAML_ESCAPECHAR, "#A31515", NO, NO},
	{SCE_YAML_DIRECTIVE, "#804000", NO, NO},
	{SCE_YAML_ANCHOR, "#7A3E9D", NO, NO},
	{SCE_YAML_ALIAS, "#7A3E9D", NO, NO},
	{SCE_YAML_TAG, "#7A3E9D", NO, NO},
	{SCE_YAML_OPERATOR, "#404040", NO, NO},
	{SCE_YAML_ERROR, "#FF0000", NO, NO},
};

// --- Markdown（标题加粗蓝，强调斜体，代码红）---
static const StyleColor kMd[] = {
	{SCE_MARKDOWN_HEADER1, "#1F4E9C", NO, YES},
	{SCE_MARKDOWN_HEADER2, "#1F4E9C", NO, YES},
	{SCE_MARKDOWN_HEADER3, "#1F4E9C", NO, YES},
	{SCE_MARKDOWN_HEADER4, "#1F4E9C", NO, NO},
	{SCE_MARKDOWN_HEADER5, "#1F4E9C", NO, NO},
	{SCE_MARKDOWN_HEADER6, "#1F4E9C", NO, NO},
	{SCE_MARKDOWN_SETEXT_H1, "#1F4E9C", NO, YES},
	{SCE_MARKDOWN_SETEXT_H2, "#1F4E9C", NO, YES},
	{SCE_MARKDOWN_HRULE, "#404040", NO, NO},
	{SCE_MARKDOWN_EM_ASTERISK, "#000000", YES, NO},
	{SCE_MARKDOWN_EM_UNDERSCORE, "#000000", YES, NO},
	{SCE_MARKDOWN_STRONG_ASTERISK, "#000000", NO, YES},
	{SCE_MARKDOWN_STRONG_UNDERSCORE, "#000000", NO, YES},
	{SCE_MARKDOWN_STRIKEOUT, "#808080", NO, NO},
	{SCE_MARKDOWN_CODE_SPAN, "#A31515", NO, NO},
	{SCE_MARKDOWN_LINK_TEXT, "#0451A5", NO, NO},
	{SCE_MARKDOWN_PLAIN_LINK, "#0451A5", NO, NO},
	{SCE_MARKDOWN_ANGLE_LINK, "#0451A5", NO, NO},
	{SCE_MARKDOWN_PAREN_LINK, "#0451A5", NO, NO},
	{SCE_MARKDOWN_BLOCKQUOTE, "#008000", NO, NO},
	{SCE_MARKDOWN_BULLET_LIST, "#404040", NO, NO},
	{SCE_MARKDOWN_ORDERED_LIST, "#404040", NO, NO},
};

// --- Shell 族（bash powershell）通用：1=注释 3/4/5=字符串---
static const StyleColor kShell[] = {
	{1, "#008000", YES, NO}, // comment
	{2, "#008000", YES, NO},
	{3, "#A31515", NO, NO}, // string
	{4, "#A31515", NO, NO},
	{5, "#A31515", NO, NO},
	{6, "#0000FF", NO, NO}, // keyword
	{7, "#0000FF", NO, NO},
	{8, "#B8860B", NO, NO}, // number
	{9, "#7A3E9D", NO, NO}, // builtin
	{10, "#804000", NO, NO}, // variable/directive
};

static void ApplyList(ScintillaView *e, const StyleColor *list, size_t n) {
	for (size_t i = 0; i < n; i++) {
		const StyleColor &sc = list[i];
		[e setColorProperty:SCI_STYLESETFORE parameter:sc.style fromHTML:@(sc.fore)];
		if (sc.italic) [e setGeneralProperty:SCI_STYLESETITALIC parameter:sc.style value:sc.italic];
		if (sc.bold) [e setGeneralProperty:SCI_STYLESETBOLD parameter:sc.style value:sc.bold];
	}
}

} // namespace Palette

// 按词法器 id 应用对应族配色
static void ApplyPaletteForLexer(ScintillaView *e, int lexer) {
	using namespace Palette;
	switch (lexer) {
	case SCLEX_CPP: case SCLEX_CSHARP: case SCLEX_JAVA: case SCLEX_JAVASCRIPT:
	case SCLEX_GO: case SCLEX_RUST: case SCLEX_SWIFT: case SCLEX_ZIG:
	case SCLEX_KOTLIN: case SCLEX_SCALA: case SCLEX_DLANG: case SCLEX_GROOVY:
	case SCLEX_HAXE: case SCLEX_CANGJIE: case SCLEX_DART:
		ApplyList(e, kC, sizeof(kC)/sizeof(kC[0]));
		break;
	case SCLEX_PYTHON: case SCLEX_NIM:
		ApplyList(e, kPy, sizeof(kPy)/sizeof(kPy[0]));
		break;
	case SCLEX_JSON:
		ApplyList(e, kJson, sizeof(kJson)/sizeof(kJson[0]));
		break;
	case SCLEX_YAML:
		ApplyList(e, kYaml, sizeof(kYaml)/sizeof(kYaml[0]));
		break;
	case SCLEX_MARKDOWN:
		ApplyList(e, kMd, sizeof(kMd)/sizeof(kMd[0]));
		break;
	case SCLEX_BASH: case SCLEX_POWERSHELL:
		ApplyList(e, kShell, sizeof(kShell)/sizeof(kShell[0]));
		break;
	default:
		// 其余 70+ 词法器：通用兜底（1=注释绿 2=注释绿 3-5=字符串红 6-8=关键字蓝）
		static const StyleColor kGeneric[] = {
			{1, "#008000", YES, NO}, {2, "#008000", YES, NO},
			{3, "#A31515", NO, NO}, {4, "#A31515", NO, NO}, {5, "#A31515", NO, NO},
			{6, "#0000FF", NO, NO}, {7, "#0000FF", NO, NO}, {8, "#0000FF", NO, NO},
		};
		ApplyList(e, kGeneric, sizeof(kGeneric)/sizeof(kGeneric[0]));
		break;
	}
}
