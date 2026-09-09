#import "LexerRegistry.h"
#import "EditLexer.h"
#import "Scintilla.h"
#import "SciLexer.h"
#include <cwchar>
#include <vector>
#include <string>
#include <unordered_map>

static NSString *WStr(const wchar_t *ws) {
	if (!ws) return @"";
	std::wstring w(ws);
	return [[NSString alloc] initWithBytes:w.data() length:w.size()*sizeof(wchar_t)
		encoding:NSUTF32LittleEndianStringEncoding];
}

// ---- 83 个 EDITLEXER 定义（lexers_def/stl*.cpp）----
extern EDITLEXER lexABAQUS;
extern EDITLEXER lexAPDL;
extern EDITLEXER lexActionScript;
extern EDITLEXER lexASM;
extern EDITLEXER lexAsymptote;
extern EDITLEXER lexAutoHotkey;
extern EDITLEXER lexAutoIt3;
extern EDITLEXER lexAviSynth;
extern EDITLEXER lexAwk;
extern EDITLEXER lexBash;
extern EDITLEXER lexBatch;
extern EDITLEXER lexBlockdiag;
extern EDITLEXER lexCIL;
extern EDITLEXER lexCMake;
extern EDITLEXER lexCPP;
extern EDITLEXER lexCSS;
extern EDITLEXER lexCSharp;
extern EDITLEXER lexCangjie;
extern EDITLEXER lexCoffeeScript;
extern EDITLEXER lexDLang;
extern EDITLEXER lexDart;
extern EDITLEXER lexGlobal;
extern EDITLEXER lexTextFile;
extern EDITLEXER lex2ndTextFile;
extern EDITLEXER lexANSI;
extern EDITLEXER lexConfig;
extern EDITLEXER lexCSV;
extern EDITLEXER lexDiff;
extern EDITLEXER lexINI;
extern EDITLEXER lexElixir;
extern EDITLEXER lexErlang;
extern EDITLEXER lexFSharp;
extern EDITLEXER lexFortran;
extern EDITLEXER lexGN;
extern EDITLEXER lexGo;
extern EDITLEXER lexGradle;
extern EDITLEXER lexGraphViz;
extern EDITLEXER lexGroovy;
extern EDITLEXER lexHTML;
extern EDITLEXER lexHaskell;
extern EDITLEXER lexHaxe;
extern EDITLEXER lexInnoSetup;
extern EDITLEXER lexJSON;
extern EDITLEXER lexJamfile;
extern EDITLEXER lexJava;
extern EDITLEXER lexJavaScript;
extern EDITLEXER lexJulia;
extern EDITLEXER lexKotlin;
extern EDITLEXER lexLLVM;
extern EDITLEXER lexLaTeX;
extern EDITLEXER lexLisp;
extern EDITLEXER lexLua;
extern EDITLEXER lexMakefile;
extern EDITLEXER lexMarkdown;
extern EDITLEXER lexMathematica;
extern EDITLEXER lexMatlab;
extern EDITLEXER lexNim;
extern EDITLEXER lexNsis;
extern EDITLEXER lexOCaml;
extern EDITLEXER lexPHP;
extern EDITLEXER lexPascal;
extern EDITLEXER lexPerl;
extern EDITLEXER lexPowerBuilder;
extern EDITLEXER lexPowerShell;
extern EDITLEXER lexPython;
extern EDITLEXER lexRLang;
extern EDITLEXER lexRebol;
extern EDITLEXER lexResourceScript;
extern EDITLEXER lexRuby;
extern EDITLEXER lexRust;
extern EDITLEXER lexSAS;
extern EDITLEXER lexSQL;
extern EDITLEXER lexScala;
extern EDITLEXER lexSmali;
extern EDITLEXER lexSwift;
extern EDITLEXER lexTOML;
extern EDITLEXER lexTcl;
extern EDITLEXER lexTexinfo;
extern EDITLEXER lexTypeScript;
extern EDITLEXER lexTypst;
extern EDITLEXER lexVisualBasic;
extern EDITLEXER lexVBScript;
extern EDITLEXER lexVHDL;
extern EDITLEXER lexVerilog;
extern EDITLEXER lexVim;
extern EDITLEXER lexWASM;
extern EDITLEXER lexWinHex;
extern EDITLEXER lexXML;
extern EDITLEXER lexYAML;
extern EDITLEXER lexZig;

// 扩展名匹配顺序：常用优先

static EDITLEXER * const kLexers[] = {
	&lexABAQUS, &lexAPDL, &lexActionScript, &lexASM, &lexAsymptote, &lexAutoHotkey, &lexAutoIt3, &lexAviSynth, &lexAwk, &lexBash, &lexBatch, &lexBlockdiag, &lexCIL, &lexCMake, &lexCPP, &lexCSS, &lexCSharp, &lexCangjie, &lexCoffeeScript, &lexDLang, &lexDart, &lexGlobal, &lexTextFile, &lex2ndTextFile, &lexANSI, &lexConfig, &lexCSV, &lexDiff, &lexINI, &lexElixir, &lexErlang, &lexFSharp, &lexFortran, &lexGN, &lexGo, &lexGradle, &lexGraphViz, &lexGroovy, &lexHTML, &lexHaskell, &lexHaxe, &lexInnoSetup, &lexJSON, &lexJamfile, &lexJava, &lexJavaScript, &lexJulia, &lexKotlin, &lexLLVM, &lexLaTeX, &lexLisp, &lexLua, &lexMakefile, &lexMarkdown, &lexMathematica, &lexMatlab, &lexNim, &lexNsis, &lexOCaml, &lexPHP, &lexPascal, &lexPerl, &lexPowerBuilder, &lexPowerShell, &lexPython, &lexRLang, &lexRebol, &lexResourceScript, &lexRuby, &lexRust, &lexSAS, &lexSQL, &lexScala, &lexSmali, &lexSwift, &lexTOML, &lexTcl, &lexTexinfo, &lexTypeScript, &lexTypst, &lexVisualBasic, &lexVBScript, &lexVHDL, &lexVerilog, &lexVim, &lexWASM, &lexWinHex, &lexXML, &lexYAML, &lexZig,
};

// ---- 暗色主题覆盖表（Notepad4 DarkTheme.ini）----
// 结构: @{ 词法器名: @{ 样式名: "fore:#xxx; back:#yyy; ..." } }
static NSDictionary<NSString *, NSDictionary<NSString *, NSString *> *> *gThemeOverrides;

static void LoadDarkThemeOverrides(void) {
	if (gThemeOverrides) return;
	NSMutableDictionary *all = [NSMutableDictionary dictionary];
	NSString *path = [[NSBundle mainBundle] pathForResource:@"Notepad4 DarkTheme" ofType:@"ini"];
	if (!path) { gThemeOverrides = all; return; }
	NSData *data = [NSData dataWithContentsOfFile:path];
	NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF16StringEncoding];
	if (!text) text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
	if (!text) { gThemeOverrides = all; return; }

	NSMutableDictionary *cur = nil;
	for (NSString *rawLine in [text componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]]) {
		NSString *line = [rawLine stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
		if (line.length == 0 || [line hasPrefix:@";"]) continue;
		if ([line hasPrefix:@"["] && [line hasSuffix:@"]"]) {
			NSString *sec = [line substringWithRange:NSMakeRange(1, line.length - 2)];
			if ([sec isEqualToString:@"Global Styles"] || [sec isEqualToString:@"Custom Colors"]) {
				cur = nil;
			} else {
				cur = [NSMutableDictionary dictionary];
				all[sec] = cur;
			}
			continue;
		}
		if (!cur) continue;
		NSRange eq = [line rangeOfString:@"="];
		if (eq.location == NSNotFound) continue;
		NSString *key = [[line substringToIndex:eq.location] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
		NSString *val = [[line substringFromIndex:eq.location + 1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
		if (key.length) cur[key] = val;
	}
	gThemeOverrides = all;
}

@implementation LexerRegistry

+ (NSArray *)allLexers {
	static NSArray *all;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		NSMutableArray *arr = [NSMutableArray array];
		for (EDITLEXER *lex : kLexers) [arr addObject:[NSValue valueWithPointer:lex]];
		all = arr;
	});
	return all;
}

+ (const EDITLEXER *)lexerForExtension:(NSString *)ext {
	if (ext.length == 0) return nullptr;
	NSString *want = ext.lowercaseString;
	for (EDITLEXER *lex : kLexers) {
		NSString *exts = WStr(lex->pszDefExt);
		NSArray *parts = [exts componentsSeparatedByCharactersInSet:
			[NSCharacterSet characterSetWithCharactersInString:@"; "]];
		for (__strong NSString *e in parts) {
			if (e.length && [e.lowercaseString isEqualToString:want]) return lex;
		}
	}
	return nullptr;
}

+ (void)applyLexer:(const EDITLEXER *)lex toEditor:(ScintillaView *)editor {
	[self applyLexer:lex toEditor:editor darkMode:NO];
}

+ (void)applyLexer:(const EDITLEXER *)lex toEditor:(ScintillaView *)editor darkMode:(BOOL)dark {
	if (!lex) return;

	// 1. 词法器
	[editor setGeneralProperty:SCI_SETLEXER value:lex->iLexer];
	// 2. 代码折叠（对照 Styles.cpp: SetProperty("fold","1")）
	[editor setLexerProperty:@"fold" value:@"1"];

	// 2. 词表
	for (unsigned i = 0; i < lex->keywordCount && i < 9; i++) {
		const char *kw = lex->pszKeyWords[i];
		if (kw && *kw) {
			NSString *kwStr = [NSString stringWithUTF8String:kw];
			[editor setReferenceProperty:SCI_SETKEYWORDS parameter:i value:kwStr.UTF8String];
		}
	}

	// 3. 暗色覆盖（按词法器名+样式名匹配）
	NSDictionary *overrides = nil;
	if (dark) {
		LoadDarkThemeOverrides();
		overrides = gThemeOverrides[WStr(lex->pszName)];
	}

	// 4. 样式：先用 stl 默认值，再用主题覆盖
	for (unsigned i = 0; i < lex->iStyleCount; i++) {
		const EDITSTYLE &es = lex->Styles[i];
		NSString *override = overrides ? overrides[WStr(es.pszName)] : nil;
		NSString *val = override.length ? override : WStr(es.pszDefault);
		[self applyStyleValue:val toStyle:es.iStyle editor:editor];
	}

	// 5. 强制重着色
	[editor message:SCI_COLOURISE wParam:0 lParam:-1];
}

+ (void)applyEditStyle:(const EDITSTYLE &)es toEditor:(ScintillaView *)editor {
	[self applyStyleValue:WStr(es.pszDefault) toStyle:es.iStyle editor:editor];
}

+ (void)applyStyleValue:(NSString *)val toStyle:(unsigned long)styleId editor:(ScintillaView *)editor {
	if (val.length == 0) return;
	// MULTI_STYLE 打包样式号逐字节解包
	std::vector<unsigned> styles;
	unsigned long sid = styleId;
	if (sid <= STYLE_MAX) {
		styles.push_back(static_cast<unsigned>(sid));
	} else {
		while (sid) {
			const unsigned char b = sid & 0xff;
			if (b) styles.push_back(b);
			sid >>= 8;
		}
	}
	if (styles.empty()) return;

	for (NSString *rawTok in [val componentsSeparatedByString:@";"]) {
		NSString *tok = [rawTok stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
		if (tok.length == 0) continue;
		for (unsigned st : styles) {
			if ([tok hasPrefix:@"fore:"]) {
				[editor setColorProperty:SCI_STYLESETFORE parameter:st
					fromHTML:[tok substringFromIndex:5]];
			} else if ([tok hasPrefix:@"back:"]) {
				[editor setColorProperty:SCI_STYLESETBACK parameter:st
					fromHTML:[tok substringFromIndex:5]];
			} else if ([tok isEqualToString:@"bold"]) {
				[editor setGeneralProperty:SCI_STYLESETBOLD parameter:st value:1];
			} else if ([tok isEqualToString:@"italic"]) {
				[editor setGeneralProperty:SCI_STYLESETITALIC parameter:st value:1];
			} else if ([tok isEqualToString:@"eolfilled"]) {
				[editor setGeneralProperty:SCI_STYLESETEOLFILLED parameter:st value:1];
			} else if ([tok hasPrefix:@"size:"]) {
				int sz = [tok substringFromIndex:5].intValue;
				if (sz > 0) [editor setGeneralProperty:SCI_STYLESETSIZE parameter:st value:sz];
			} else if ([tok hasPrefix:@"font:"]) {
				NSString *fname = [tok substringFromIndex:5];
				if (![fname hasPrefix:@"$("]) {
					[editor setStringProperty:SCI_STYLESETFONT parameter:st value:fname];
				}
			}
		}
	}
}

+ (NSArray<NSDictionary *> *)allLexersInfo {
	NSMutableArray *out = [NSMutableArray array];
	for (EDITLEXER *lex : kLexers) {
		[out addObject:@{@"name": WStr(lex->pszName),
			@"extensions": WStr(lex->pszDefExt),
			@"sclex": @(lex->iLexer)}];
	}
	return out;
}

@end
