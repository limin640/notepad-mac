#import "EditCommands.h"
#import "EditorDocument.h"
#import "LexerRegistry.h"
#import "NPLocalization.h"
#import "EditLexer.h"
#import "SciLexer.h"
#import "Scintilla.h"

#include <stdlib.h>
#include <string.h>
#include <math.h>

@interface MainWindowController (PrivateHooks)
- (void)persistSettings;
- (void)openToolbarMenu:(NSMenu *)menu fromView:(NSView *)anchor;
@end

static NSString *NPEOL(ScintillaView *e) {
	const sptr_t m = [e message:SCI_GETEOLMODE];
	if (m == SC_EOL_CRLF) return @"\r\n";
	if (m == SC_EOL_CR) return @"\r";
	return @"\n";
}

static BOOL NPHeadless(void) {
	return [[[NSProcessInfo processInfo] arguments] containsObject:@"--headless"]
		|| getenv("NP4_HEADLESS") != NULL;
}

static void NPLineRange(ScintillaView *e, sptr_t *first, sptr_t *last) {
	const sptr_t a = [e message:SCI_GETSELECTIONSTART];
	const sptr_t b = [e message:SCI_GETSELECTIONEND];
	*first = [e message:SCI_LINEFROMPOSITION wParam:a];
	*last = [e message:SCI_LINEFROMPOSITION wParam:b];
	if (a != b && *first != *last) {
		if (b > 0 && [e message:SCI_POSITIONFROMLINE wParam:*last] == b && *last > *first)
			(*last)--;
	}
}

static void NPLineSpan(ScintillaView *e, sptr_t *start, sptr_t *end) {
	sptr_t first = 0, last = 0;
	NPLineRange(e, &first, &last);
	*start = [e message:SCI_POSITIONFROMLINE wParam:first];
	if (last + 1 < [e message:SCI_GETLINECOUNT])
		*end = [e message:SCI_POSITIONFROMLINE wParam:last + 1];
	else
		*end = [e message:SCI_GETLENGTH];
}

static NSString *NPLineText(ScintillaView *e, sptr_t line) {
	const sptr_t ls = [e message:SCI_POSITIONFROMLINE wParam:line];
	const sptr_t le = [e message:SCI_GETLINEENDPOSITION wParam:line];
	if (le <= ls) return @"";
	const char *p = (const char *)[e message:SCI_GETRANGEPOINTER wParam:ls lParam:(le - ls)];
	if (!p) return @"";
	return [[NSString alloc] initWithBytes:p length:(NSUInteger)(le - ls) encoding:NSUTF8StringEncoding] ?: @"";
}

static void NPReplaceLines(ScintillaView *e, sptr_t first, sptr_t last, NSArray<NSString *> *lines) {
	const sptr_t start = [e message:SCI_POSITIONFROMLINE wParam:first];
	const sptr_t end = [e message:SCI_GETLINEENDPOSITION wParam:last];
	NSString *joined = [lines componentsJoinedByString:NPEOL(e)];
	[e message:SCI_SETTARGETSTART wParam:start lParam:0];
	[e message:SCI_SETTARGETEND wParam:end lParam:0];
	[e message:SCI_REPLACETARGET wParam:-1 lParam:(sptr_t)joined.UTF8String];
}

static NSArray<NSString *> *NPCollectLines(ScintillaView *e, sptr_t first, sptr_t last) {
	NSMutableArray *a = [NSMutableArray array];
	for (sptr_t i = first; i <= last; i++) [a addObject:NPLineText(e, i)];
	return a;
}

static void NPReplaceSel(ScintillaView *e, NSString *s) {
	if (!s) return;
	const char *u = s.UTF8String ?: "";
	[e message:SCI_REPLACESEL wParam:0 lParam:(sptr_t)u];
}

static void NPReplaceTargetStr(ScintillaView *e, NSString *s) {
	const char *u = (s ?: @"").UTF8String ?: "";
	[e message:SCI_REPLACETARGET wParam:(sptr_t)strlen(u) lParam:(sptr_t)u];
}

static void NPInsertAt(ScintillaView *e, sptr_t pos, NSString *s) {
	[e message:SCI_SETTARGETSTART wParam:pos lParam:0];
	[e message:SCI_SETTARGETEND wParam:pos lParam:0];
	NPReplaceTargetStr(e, s);
}

static void NPEnclose(ScintillaView *e, NSString *L, NSString *R) {
	if (!e) return;
	const sptr_t a = [e message:SCI_GETSELECTIONSTART];
	const sptr_t b = [e message:SCI_GETSELECTIONEND];
	const char *lu = (L ?: @"").UTF8String ?: "";
	const char *ru = (R ?: @"").UTF8String ?: "";
	const sptr_t ln = (sptr_t)strlen(lu);
	[e message:SCI_BEGINUNDOACTION wParam:0 lParam:0];
	if (ln) {
		[e message:SCI_SETTARGETSTART wParam:a lParam:0];
		[e message:SCI_SETTARGETEND wParam:a lParam:0];
		[e message:SCI_REPLACETARGET wParam:ln lParam:(sptr_t)lu];
	}
	if (ru[0]) {
		[e message:SCI_SETTARGETSTART wParam:b + ln lParam:0];
		[e message:SCI_SETTARGETEND wParam:b + ln lParam:0];
		[e message:SCI_REPLACETARGET wParam:(sptr_t)strlen(ru) lParam:(sptr_t)ru];
	}
	if (a == b) [e message:SCI_SETSEL wParam:a + ln lParam:a + ln];
	else [e message:SCI_SETSEL wParam:a + ln lParam:b + ln];
	[e message:SCI_ENDUNDOACTION wParam:0 lParam:0];
}

static void NPStripLineChars(ScintillaView *e, BOOL firstChar) {
	const sptr_t selA = [e message:SCI_GETSELECTIONSTART];
	const sptr_t selB = [e message:SCI_GETSELECTIONEND];
	sptr_t first = [e message:SCI_LINEFROMPOSITION wParam:selA];
	sptr_t last = [e message:SCI_LINEFROMPOSITION wParam:selB];
	if (first != last) {
		if (selA > [e message:SCI_POSITIONFROMLINE wParam:first]) first++;
		if (selB <= [e message:SCI_POSITIONFROMLINE wParam:last] && last > first) last--;
	}
	[e message:SCI_BEGINUNDOACTION wParam:0 lParam:0];
	for (sptr_t l = first; l <= last; l++) {
		const sptr_t ls = [e message:SCI_POSITIONFROMLINE wParam:l];
		const sptr_t le = [e message:SCI_GETLINEENDPOSITION wParam:l];
		if (le <= ls) continue;
		if (firstChar) {
			const sptr_t after = [e message:SCI_POSITIONAFTER wParam:ls];
			[e message:SCI_DELETERANGE wParam:ls lParam:after - ls];
		} else {
			const sptr_t before = [e message:SCI_POSITIONBEFORE wParam:le];
			[e message:SCI_DELETERANGE wParam:before lParam:le - before];
		}
	}
	[e message:SCI_ENDUNDOACTION wParam:0 lParam:0];
}

static void NPAlignLines(ScintillaView *e, NSInteger mode) {
	sptr_t first = 0, last = 0;
	NPLineRange(e, &first, &last);
	NSArray *lines = NPCollectLines(e, first, last);
	NSUInteger maxLen = 0;
	for (NSString *s in lines) if (s.length > maxLen) maxLen = s.length;
	NSMutableArray *out = [NSMutableArray array];
	for (NSString *raw in lines) {
		NSString *s = [raw stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
		if (s.length == 0) { [out addObject:@""]; continue; }
		if (mode == 0) [out addObject:s];
		else if (mode == 1) {
			NSUInteger pad = maxLen > s.length ? maxLen - s.length : 0;
			[out addObject:[[@"" stringByPaddingToLength:pad withString:@" " startingAtIndex:0] stringByAppendingString:s]];
		} else if (mode == 2) {
			NSUInteger pad = maxLen > s.length ? maxLen - s.length : 0;
			NSUInteger left = pad / 2;
			[out addObject:[[[ @"" stringByPaddingToLength:left withString:@" " startingAtIndex:0] stringByAppendingString:s]
				stringByPaddingToLength:maxLen withString:@" " startingAtIndex:0]];
		} else {
			NSArray *words = [s componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
			NSMutableArray *w = [NSMutableArray array];
			for (NSString *x in words) if (x.length) [w addObject:x];
			if (w.count <= 1) { [out addObject:s]; continue; }
			NSUInteger letters = 0;
			for (NSString *x in w) letters += x.length;
			NSInteger gaps = (NSInteger)w.count - 1;
			NSInteger extra = (NSInteger)maxLen - (NSInteger)letters;
			if (extra < gaps) extra = gaps;
			NSMutableString *line = [NSMutableString string];
			for (NSUInteger i = 0; i < w.count; i++) {
				[line appendString:w[i]];
				if (i + 1 == w.count) break;
				NSInteger n = extra / gaps + (i < (NSUInteger)(extra % gaps) ? 1 : 0);
				if (n < 1) n = 1;
				[line appendString:[@"" stringByPaddingToLength:(NSUInteger)n withString:@" " startingAtIndex:0]];
			}
			[out addObject:line];
		}
	}
	[e message:SCI_BEGINUNDOACTION wParam:0 lParam:0];
	NPReplaceLines(e, first, last, out);
	[e message:SCI_ENDUNDOACTION wParam:0 lParam:0];
}

static BOOL NPParseNumber(NSString *s, long long *outVal) {
	NSString *t = [s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if (t.length == 0) return NO;
	const char *c = t.UTF8String;
	char *end = NULL;
	if ([t hasPrefix:@"0x"] || [t hasPrefix:@"0X"])
		*outVal = strtoll(c + 2, &end, 16);
	else if ([t hasPrefix:@"0b"] || [t hasPrefix:@"0B"])
		*outVal = strtoll(c + 2, &end, 2);
	else if (t.length > 1 && [t hasPrefix:@"0"] && [[NSCharacterSet characterSetWithCharactersInString:@"01234567"] characterIsMember:[t characterAtIndex:1]])
		*outVal = strtoll(c, &end, 8);
	else
		*outVal = strtoll(c, &end, 10);
	return end && *end == 0;
}

static NSArray<NSString *> *NPStreamPair(const EDITLEXER *lex) {
	if (lex && (lex->lexerAttr & LexerAttr_NoBlockComment)) return nil;
	const int lexer = lex ? lex->iLexer : SCLEX_NULL;
	switch (lexer) {
		case SCLEX_HTML: case SCLEX_XML:
			return @[@"<!-- ", @" -->"];
		case SCLEX_PYTHON:
			return @[@"\"\"\"", @"\"\"\""];
		case SCLEX_LUA:
			return @[@"--[[", @"]]"];
		case SCLEX_NULL:
			return nil;
		default:
			return @[@"/* ", @" */"];
	}
}

static sptr_t NPBraceAtCaret(ScintillaView *e) {
	const sptr_t pos = [e message:SCI_GETCURRENTPOS];
	if (pos > 0) {
		const char ch = (char)[e message:SCI_GETCHARAT wParam:pos - 1];
		if (ch == '(' || ch == ')' || ch == '[' || ch == ']' || ch == '{' || ch == '}')
			return pos - 1;
	}
	const char ch = (char)[e message:SCI_GETCHARAT wParam:pos];
	if (ch == '(' || ch == ')' || ch == '[' || ch == ']' || ch == '{' || ch == '}')
		return pos;
	return -1;
}

@implementation MainWindowController (EditCommands)

- (void)editCopyAdd {
	NSString *sel = [self.editorDocument.editor selectedString];
	if (sel.length == 0) return;
	NSPasteboard *pb = [NSPasteboard generalPasteboard];
	NSString *old = [pb stringForType:NSPasteboardTypeString] ?: @"";
	[pb clearContents];
	[pb setString:[old stringByAppendingString:sel] forType:NSPasteboardTypeString];
}

- (void)editStreamComment {
	NSArray<NSString *> *pair = NPStreamPair(self.editorDocument.currentLexer);
	if (pair.count != 2) return;
	ScintillaView *e = self.editorDocument.editor;
	NSString *sel = [e selectedString] ?: @"";
	NSString *L = pair[0], *R = pair[1];
	if (sel.length >= L.length + R.length && [sel hasPrefix:L] && [sel hasSuffix:R]) {
		NSString *inner = [sel substringWithRange:NSMakeRange(L.length, sel.length - L.length - R.length)];
		NPReplaceSel(e, inner);
	} else {
		NPEnclose(e, L, R);
	}
}

- (void)editSortLines {
	ScintillaView *e = self.editorDocument.editor;
	sptr_t first = 0, last = 0;
	NPLineRange(e, &first, &last);
	NSArray *lines = NPCollectLines(e, first, last);
	NSArray *sorted = [lines sortedArrayUsingSelector:@selector(localizedCompare:)];
	[e message:SCI_BEGINUNDOACTION wParam:0 lParam:0];
	NPReplaceLines(e, first, last, sorted);
	[e message:SCI_ENDUNDOACTION wParam:0 lParam:0];
}
- (void)editSortLinesDescending {
	ScintillaView *e = self.editorDocument.editor;
	sptr_t first = 0, last = 0;
	NPLineRange(e, &first, &last);
	NSArray *lines = NPCollectLines(e, first, last);
	NSArray *sorted = [[lines sortedArrayUsingSelector:@selector(localizedCompare:)] reverseObjectEnumerator].allObjects;
	[e message:SCI_BEGINUNDOACTION wParam:0 lParam:0];
	NPReplaceLines(e, first, last, sorted);
	[e message:SCI_ENDUNDOACTION wParam:0 lParam:0];
}

- (void)editRemoveDuplicateLines {
	ScintillaView *e = self.editorDocument.editor;
	sptr_t first = 0, last = 0;
	NPLineRange(e, &first, &last);
	NSMutableArray *out = [NSMutableArray array];
	NSMutableSet *seen = [NSMutableSet set];
	for (NSString *line in NPCollectLines(e, first, last)) {
		if ([seen containsObject:line]) continue;
		[seen addObject:line];
		[out addObject:line];
	}
	[e message:SCI_BEGINUNDOACTION wParam:0 lParam:0];
	NPReplaceLines(e, first, last, out);
	[e message:SCI_ENDUNDOACTION wParam:0 lParam:0];
}

- (void)editMergeDuplicateLines {
	ScintillaView *e = self.editorDocument.editor;
	sptr_t first = 0, last = 0;
	NPLineRange(e, &first, &last);
	NSArray *lines = NPCollectLines(e, first, last);
	NSMutableArray *out = [NSMutableArray array];
	NSString *prev = nil;
	for (NSString *line in lines) {
		if (prev && [prev isEqualToString:line]) continue;
		[out addObject:line];
		prev = line;
	}
	[e message:SCI_BEGINUNDOACTION wParam:0 lParam:0];
	NPReplaceLines(e, first, last, out);
	[e message:SCI_ENDUNDOACTION wParam:0 lParam:0];
}

- (void)editMergeBlankLines {
	ScintillaView *e = self.editorDocument.editor;
	sptr_t first = 0, last = 0;
	NPLineRange(e, &first, &last);
	NSMutableArray *out = [NSMutableArray array];
	BOOL prevBlank = NO;
	for (NSString *line in NPCollectLines(e, first, last)) {
		NSString *trim = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
		const BOOL blank = trim.length == 0;
		if (blank && prevBlank) continue;
		[out addObject:line];
		prevBlank = blank;
	}
	[e message:SCI_BEGINUNDOACTION wParam:0 lParam:0];
	NPReplaceLines(e, first, last, out);
	[e message:SCI_ENDUNDOACTION wParam:0 lParam:0];
}

- (void)editCompressWhitespace {
	ScintillaView *e = self.editorDocument.editor;
	NSString *sel = [e selectedString];
	const BOOL whole = (sel.length == 0);
	NSString *src = whole ? ([e string] ?: @"") : sel;
	if (src.length == 0) return;
	NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"[ \t]+" options:0 error:nil];
	NSString *out = [re stringByReplacingMatchesInString:src options:0 range:NSMakeRange(0, src.length) withTemplate:@" "];
	if (whole) [e setString:out];
	else NPReplaceSel(e, out);
}

- (void)editTrimLeading {
	ScintillaView *e = self.editorDocument.editor;
	sptr_t first = 0, last = 0;
	NPLineRange(e, &first, &last);
	[e message:SCI_BEGINUNDOACTION wParam:0 lParam:0];
	for (sptr_t l = first; l <= last; l++) {
		const sptr_t ls = [e message:SCI_POSITIONFROMLINE wParam:l];
		const sptr_t le = [e message:SCI_GETLINEENDPOSITION wParam:l];
		sptr_t p = ls;
		while (p < le) {
			const char c = (char)[e message:SCI_GETCHARAT wParam:p];
			if (c != ' ' && c != '\t') break;
			p++;
		}
		if (p > ls) {
			[e message:SCI_SETTARGETSTART wParam:ls lParam:0];
			[e message:SCI_SETTARGETEND wParam:p lParam:0];
			[e message:SCI_REPLACETARGET wParam:0 lParam:(sptr_t)""];
		}
	}
	[e message:SCI_ENDUNDOACTION wParam:0 lParam:0];
}

- (void)editStripFirstChar { NPStripLineChars(self.editorDocument.editor, YES); }
- (void)editStripLastChar { NPStripLineChars(self.editorDocument.editor, NO); }

- (void)editPadWithSpaces {
	ScintillaView *e = self.editorDocument.editor;
	sptr_t first = 0, last = 0;
	NPLineRange(e, &first, &last);
	if (first == last) {
		first = 0;
		last = [e message:SCI_GETLINECOUNT] - 1;
	}
	NSArray *lines = NPCollectLines(e, first, last);
	NSUInteger maxLen = 0;
	for (NSString *s in lines) if (s.length > maxLen) maxLen = s.length;
	NSMutableArray *out = [NSMutableArray array];
	for (NSString *s in lines) {
		if (s.length >= maxLen) [out addObject:s];
		else [out addObject:[s stringByPaddingToLength:maxLen withString:@" " startingAtIndex:0]];
	}
	[e message:SCI_BEGINUNDOACTION wParam:0 lParam:0];
	NPReplaceLines(e, first, last, out);
	[e message:SCI_ENDUNDOACTION wParam:0 lParam:0];
}

- (void)editAlignLeft { NPAlignLines(self.editorDocument.editor, 0); }
- (void)editAlignRight { NPAlignLines(self.editorDocument.editor, 1); }
- (void)editAlignCenter { NPAlignLines(self.editorDocument.editor, 2); }
- (void)editAlignJustify { NPAlignLines(self.editorDocument.editor, 3); }

- (void)editSentenceCase {
	ScintillaView *e = self.editorDocument.editor;
	NSString *sel = [e selectedString];
	if (sel.length == 0) return;
	NSMutableString *out = [sel.lowercaseString mutableCopy];
	BOOL cap = YES;
	for (NSUInteger i = 0; i < out.length; ) {
		const NSRange r = [out rangeOfComposedCharacterSequenceAtIndex:i];
		NSString *ch = [out substringWithRange:r];
		if (cap && [[NSCharacterSet letterCharacterSet] characterIsMember:[ch characterAtIndex:0]]) {
			[out replaceCharactersInRange:r withString:ch.uppercaseString];
			cap = NO;
		}
		const unichar c = [ch characterAtIndex:0];
		if (c == '.' || c == '!' || c == '?' || c == '\n' || c == '\r') cap = YES;
		i = NSMaxRange(r);
	}
	NPReplaceSel(e, out);
}

- (void)editConvertNumberToBase:(int)base prefix:(NSString *)prefix {
	ScintillaView *e = self.editorDocument.editor;
	NSString *sel = [e selectedString];
	long long v = 0;
	if (sel.length == 0 || NPParseNumber(sel, &v) == NO) return;
	if (base == 10) {
		NPReplaceSel(e, [NSString stringWithFormat:@"%lld", v]);
		return;
	}
	unsigned long long u = (unsigned long long)v;
	NSMutableString *digits = [NSMutableString string];
	if (u == 0) [digits appendString:@"0"];
	const char *alpha = "0123456789abcdef";
	while (u) {
		[digits insertString:[NSString stringWithFormat:@"%c", alpha[u % (unsigned)base]] atIndex:0];
		u /= (unsigned)base;
	}
	NPReplaceSel(e, [prefix stringByAppendingString:digits]);
}
- (void)editNum2Bin { [self editConvertNumberToBase:2 prefix:@"0b"]; }
- (void)editNum2Oct { [self editConvertNumberToBase:8 prefix:@"0"]; }
- (void)editNum2Dec { [self editConvertNumberToBase:10 prefix:@""]; }
- (void)editNum2Hex { [self editConvertNumberToBase:16 prefix:@"0x"]; }

- (void)editChar2Hex {
	ScintillaView *e = self.editorDocument.editor;
	NSString *sel = [e selectedString];
	if (sel.length == 0) return;
	NSMutableArray *parts = [NSMutableArray array];
	for (NSUInteger i = 0; i < sel.length; ) {
		const NSRange r = [sel rangeOfComposedCharacterSequenceAtIndex:i];
		NSString *ch = [sel substringWithRange:r];
		const uint32_t cp = [ch characterAtIndex:0];
		if (r.length > 1) {
			const uint32_t hi = [ch characterAtIndex:0];
			const uint32_t lo = [ch characterAtIndex:1];
			const uint32_t u = 0x10000 + ((hi - 0xD800) << 10) + (lo - 0xDC00);
			[parts addObject:[NSString stringWithFormat:@"U+%04X", u]];
		} else if (cp > 0x7F) {
			[parts addObject:[NSString stringWithFormat:@"U+%04X", cp]];
		} else {
			[parts addObject:[NSString stringWithFormat:@"%02X", cp]];
		}
		i = NSMaxRange(r);
	}
	NPReplaceSel(e, [parts componentsJoinedByString:@" "]);
}

- (void)editHex2Char {
	ScintillaView *e = self.editorDocument.editor;
	NSString *sel = [[e selectedString] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if (sel.length == 0) return;
	NSMutableString *out = [NSMutableString string];
	NSArray *toks = [sel componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	for (NSString *raw in toks) {
		if (raw.length == 0) continue;
		NSString *t = raw;
		if ([t hasPrefix:@"U+"] || [t hasPrefix:@"u+"]) t = [t substringFromIndex:2];
		else if ([t hasPrefix:@"0x"] || [t hasPrefix:@"0X"]) t = [t substringFromIndex:2];
		unsigned int v = 0;
		NSScanner *sc = [NSScanner scannerWithString:t];
		if ([sc scanHexInt:&v] == NO) continue;
		if (v <= 0xFFFF) {
			unichar c = (unichar)v;
			[out appendString:[NSString stringWithCharacters:&c length:1]];
		} else if (v <= 0x10FFFF) {
			const uint32_t u = v - 0x10000;
			unichar pair[2] = { (unichar)(0xD800 + (u >> 10)), (unichar)(0xDC00 + (u & 0x3FF)) };
			[out appendString:[NSString stringWithCharacters:pair length:2]];
		}
	}
	if (out.length) NPReplaceSel(e, out);
}

- (void)editEscapeCChars {
	ScintillaView *e = self.editorDocument.editor;
	NSString *sel = [e selectedString];
	if (sel.length == 0) return;
	NSMutableString *out = [NSMutableString string];
	for (NSUInteger i = 0; i < sel.length; i++) {
		const unichar c = [sel characterAtIndex:i];
		if (c == '\\') [out appendString:@"\\\\"];
		else if (c == '\"') [out appendString:@"\\\""];
		else if (c == '\'') [out appendString:@"\\'"];
		else if (c == '\n') [out appendString:@"\\n"];
		else if (c == '\r') [out appendString:@"\\r"];
		else if (c == '\t') [out appendString:@"\\t"];
		else [out appendFormat:@"%C", c];
	}
	NPReplaceSel(e, out);
}

- (void)editUnescapeCChars {
	ScintillaView *e = self.editorDocument.editor;
	NSString *sel = [e selectedString];
	if (sel.length == 0) return;
	NSMutableString *out = [NSMutableString string];
	for (NSUInteger i = 0; i < sel.length; i++) {
		unichar c = [sel characterAtIndex:i];
		if (c == '\\' && i + 1 < sel.length) {
			const unichar n = [sel characterAtIndex:++i];
			if (n == 'n') [out appendString:@"\n"];
			else if (n == 'r') [out appendString:@"\r"];
			else if (n == 't') [out appendString:@"\t"];
			else if (n == '\\') [out appendString:@"\\"];
			else if (n == '"') [out appendString:@"\""];
			else if (n == '\'') [out appendString:@"'"];
			else [out appendFormat:@"%C", n];
		} else {
			[out appendFormat:@"%C", c];
		}
	}
	NPReplaceSel(e, out);
}

- (void)editEncloseParen { NPEnclose(self.editorDocument.editor, @"(", @")"); }
- (void)editEncloseBracket { NPEnclose(self.editorDocument.editor, @"[", @"]"); }
- (void)editEncloseBrace { NPEnclose(self.editorDocument.editor, @"{", @"}"); }
- (void)editEncloseAngle { NPEnclose(self.editorDocument.editor, @"<", @">"); }
- (void)editEncloseQuote { NPEnclose(self.editorDocument.editor, @"\"", @"\""); }
- (void)editEncloseSingleQuote { NPEnclose(self.editorDocument.editor, @"'", @"'"); }
- (void)editEncloseBacktick { NPEnclose(self.editorDocument.editor, @"`", @"`"); }
- (void)editEncloseTripleSQ { NPEnclose(self.editorDocument.editor, @"'''", @"'''"); }
- (void)editEncloseTripleDQ { NPEnclose(self.editorDocument.editor, @"\"\"\"", @"\"\"\""); }
- (void)editEncloseTripleBT { NPEnclose(self.editorDocument.editor, @"```", @"```"); }
- (void)editInsertXMLTag {
	ScintillaView *e = self.editorDocument.editor;
	NSString *sel = [e selectedString] ?: @"";
	NSString *tag = @"div";
	if ([[[NSProcessInfo processInfo] arguments] containsObject:@"--headless"] == NO) {
		NSAlert *a = [[NSAlert alloc] init];
		a.messageText = NPL(@"Insert XML/HTML Tag");
		NSTextField *input = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 200, 24)];
		input.stringValue = @"div";
		a.accessoryView = input;
		[a addButtonWithTitle:NPL(@"OK")];
		[a addButtonWithTitle:NPL(@"Cancel")];
		[a beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse r) {
			if (r != NSAlertFirstButtonReturn) return;
			NSString *t = input.stringValue.length ? input.stringValue : @"div";
			NPReplaceSel(self.editorDocument.editor, [NSString stringWithFormat:@"<%@>%@</%@>", t, sel, t]);
		}];
		return;
	}
	NPReplaceSel(e, [NSString stringWithFormat:@"<%@>%@</%@>", tag, sel, tag]);
}

- (void)editDeleteLineLeft { [self.editorDocument.editor message:SCI_DELLINELEFT wParam:0 lParam:0]; }
- (void)editDeleteLineRight { [self.editorDocument.editor message:SCI_DELLINERIGHT wParam:0 lParam:0]; }

- (void)searchSelectToBrace {
	ScintillaView *e = self.editorDocument.editor;
	const sptr_t brace = NPBraceAtCaret(e);
	if (brace < 0) return;
	const sptr_t match = [e message:SCI_BRACEMATCH wParam:brace lParam:0];
	if (match < 0) return;
	const sptr_t a = brace < match ? brace : match;
	const sptr_t b = brace < match ? match : brace;
	[e message:SCI_SETSEL wParam:a lParam:b + 1];
}

- (void)searchSelectLine {
	ScintillaView *e = self.editorDocument.editor;
	const sptr_t line = [e message:SCI_LINEFROMPOSITION wParam:[e message:SCI_GETCURRENTPOS]];
	const sptr_t a = [e message:SCI_POSITIONFROMLINE wParam:line];
	sptr_t b = [e message:SCI_GETLINEENDPOSITION wParam:line];
	if (line < [e message:SCI_GETLINECOUNT] - 1)
		b = [e message:SCI_POSITIONFROMLINE wParam:line + 1];
	[e message:SCI_SETSEL wParam:a lParam:b];
}

- (void)searchSelectToDocStart {
	ScintillaView *e = self.editorDocument.editor;
	[e message:SCI_SETSEL wParam:[e message:SCI_GETCURRENTPOS] lParam:0];
}

- (void)searchSelectToDocEnd {
	ScintillaView *e = self.editorDocument.editor;
	[e message:SCI_SETSEL wParam:[e message:SCI_GETCURRENTPOS] lParam:[e message:SCI_GETLENGTH]];
}

- (void)insertUnicodeZWSP { NPReplaceSel(self.editorDocument.editor, @"\u200B"); }
- (void)insertUnicodeNBSP { NPReplaceSel(self.editorDocument.editor, @"\u00A0"); }
- (void)insertUnicodeLRM { NPReplaceSel(self.editorDocument.editor, @"\u200E"); }
- (void)insertUnicodeRLM { NPReplaceSel(self.editorDocument.editor, @"\u200F"); }

- (void)insertShebang {
	NSString *ext = self.editorDocument.fileURL.pathExtension.lowercaseString ?: @"";
	NSString *line = @"#!/usr/bin/env bash";
	if ([ext isEqualToString:@"py"] || [ext isEqualToString:@"pyw"]) line = @"#!/usr/bin/env python3";
	else if ([ext isEqualToString:@"rb"]) line = @"#!/usr/bin/env ruby";
	else if ([ext isEqualToString:@"pl"]) line = @"#!/usr/bin/env perl";
	else if ([ext isEqualToString:@"js"]) line = @"#!/usr/bin/env node";
	ScintillaView *e = self.editorDocument.editor;
	[e message:SCI_GOTOPOS wParam:0 lParam:0];
	NPReplaceSel(e, [line stringByAppendingString:NPEOL(e)]);
}

- (void)insertEncodingName {
	NSString *enc = self.editorDocument.currentEncoding ?: @"UTF-8";
	NPReplaceSel(self.editorDocument.editor, enc);
}

- (void)urlComponentEncode {
	NSString *sel = [self.editorDocument.editor selectedString];
	if (sel.length == 0) return;
	NSMutableCharacterSet *allowed = [NSMutableCharacterSet alphanumericCharacterSet];
	[allowed addCharactersInString:@"-._~"];
	NSString *enc = [sel stringByAddingPercentEncodingWithAllowedCharacters:allowed];
	if (enc) NPReplaceSel(self.editorDocument.editor, enc);
}

- (void)setEOLCR {
	ScintillaView *e = self.editorDocument.editor;
	[e message:SCI_SETEOLMODE wParam:SC_EOL_CR lParam:0];
	[e message:SCI_CONVERTEOLS wParam:SC_EOL_CR lParam:0];
	[self refreshStatus];
}

- (void)setEncodingGBK { [self.editorDocument setSaveEncoding:@"GBK"]; [self refreshStatus]; }
- (void)setEncodingBIG5 { [self.editorDocument setSaveEncoding:@"BIG5"]; [self refreshStatus]; }
- (void)setEncodingShiftJIS { [self.editorDocument setSaveEncoding:@"Shift-JIS"]; [self refreshStatus]; }
- (void)reloadBIG5 { [self.editorDocument reloadWithEncoding:@"BIG5"]; [self refreshStatus]; }
- (void)reloadShiftJIS { [self.editorDocument reloadWithEncoding:@"Shift-JIS"]; [self refreshStatus]; }

- (void)viewDetectURLs {
	const BOOL on = self.editorDocument.URLDetectEnabled ? NO : YES;
	[self.editorDocument setURLDetectEnabled:on];
	[[NSUserDefaults standardUserDefaults] setBool:on forKey:@"NP4URLDetect"];
	[self persistSettings];
}

- (void)toggleLargeFileMode {
	const BOOL on = self.editorDocument.largeFileMode ? NO : YES;
	[self.editorDocument setLargeFileMode:on];
	[self refreshStatus];
}

- (void)fileCreateDesktopShortcut {
	NSString *src = self.editorDocument.fileURL.path;
	if (src.length == 0) return;
	NSString *desk = [NSHomeDirectory() stringByAppendingPathComponent:@"Desktop"];
	NSString *dest = [desk stringByAppendingPathComponent:src.lastPathComponent];
	NSError *err = nil;
	[[NSFileManager defaultManager] createSymbolicLinkAtPath:dest withDestinationPath:src error:&err];
}

- (void)fileManageFavorites {
	NSMenu *m = [[NSMenu alloc] init];
	NSArray *list = [[NSUserDefaults standardUserDefaults] arrayForKey:@"NP4Favorites"] ?: @[];
	if (list.count == 0) {
		NSMenuItem *empty = [m addItemWithTitle:NPL(@"No favorites") action:nil keyEquivalent:@""];
		empty.enabled = NO;
	} else {
		for (NSString *path in list) {
			NSMenuItem *it = [m addItemWithTitle:[NSString stringWithFormat:@"✕  %@", path.lastPathComponent]
				action:@selector(removeFavorite:) keyEquivalent:@""];
			it.target = self;
			it.representedObject = path;
			it.toolTip = path;
		}
		[m addItem:[NSMenuItem separatorItem]];
		NSMenuItem *clr = [m addItemWithTitle:NPL(@"Clear Favorites") action:@selector(clearFavorites) keyEquivalent:@""];
		clr.target = self;
	}
	if ([self respondsToSelector:@selector(openToolbarMenu:fromView:)]) {
		[self performSelector:@selector(openToolbarMenu:fromView:) withObject:m withObject:self.window.contentView];
	}
}

- (void)removeFavorite:(NSMenuItem *)item {
	NSString *path = item.representedObject;
	if (path.length == 0) return;
	NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
	NSMutableArray *list = [([d arrayForKey:@"NP4Favorites"] ?: @[]) mutableCopy];
	[list removeObject:path];
	[d setObject:list forKey:@"NP4Favorites"];
}

- (void)clearFavorites {
	[[NSUserDefaults standardUserDefaults] setObject:@[] forKey:@"NP4Favorites"];
}


- (void)editEncloseCustom {
	NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
	NSString *L = [d stringForKey:@"NP4EncloseOpen"] ?: @"(";
	NSString *R = [d stringForKey:@"NP4EncloseClose"] ?: @")";
	if (!NPHeadless() && self.window) {
		NSAlert *a = [[NSAlert alloc] init];
		a.messageText = NPL(@"Enclose Selection");
		NSView *box = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 260, 54)];
		NSTextField *o = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 28, 120, 24)];
		NSTextField *c = [[NSTextField alloc] initWithFrame:NSMakeRect(130, 28, 120, 24)];
		o.stringValue = L; c.stringValue = R;
		[box addSubview:o]; [box addSubview:c];
		a.accessoryView = box;
		[a addButtonWithTitle:NPL(@"OK")];
		[a addButtonWithTitle:NPL(@"Cancel")];
		if ([a runModal] != NSAlertFirstButtonReturn) return;
		L = o.stringValue ?: @""; R = c.stringValue ?: @"";
		[d setObject:L forKey:@"NP4EncloseOpen"];
		[d setObject:R forKey:@"NP4EncloseClose"];
	}
	NPEnclose(self.editorDocument.editor, L, R);
}

- (void)editModifyLines {
	NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
	NSString *pre = [d stringForKey:@"NP4ModifyPrefix"] ?: @"> ";
	NSString *suf = [d stringForKey:@"NP4ModifySuffix"] ?: @"";
	if (!NPHeadless() && self.window) {
		NSAlert *a = [[NSAlert alloc] init];
		a.messageText = NPL(@"Modify Lines");
		NSView *box = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 280, 54)];
		NSTextField *o = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 28, 130, 24)];
		NSTextField *c = [[NSTextField alloc] initWithFrame:NSMakeRect(140, 28, 130, 24)];
		o.stringValue = pre; c.stringValue = suf;
		[box addSubview:o]; [box addSubview:c];
		a.accessoryView = box;
		[a addButtonWithTitle:NPL(@"OK")];
		[a addButtonWithTitle:NPL(@"Cancel")];
		if ([a runModal] != NSAlertFirstButtonReturn) return;
		pre = o.stringValue ?: @""; suf = c.stringValue ?: @"";
		[d setObject:pre forKey:@"NP4ModifyPrefix"];
		[d setObject:suf forKey:@"NP4ModifySuffix"];
	}
	ScintillaView *e = self.editorDocument.editor;
	sptr_t first = 0, last = 0;
	NPLineRange(e, &first, &last);
	NSArray *lines = NPCollectLines(e, first, last);
	NSMutableArray *out = [NSMutableArray array];
	NSInteger n = 1;
	for (sptr_t i = first; i <= last; i++, n++) {
		NSString *line = lines[(NSUInteger)(i - first)];
		NSMutableString *p = [pre mutableCopy];
		NSMutableString *s = [suf mutableCopy];
		NSString *L = [NSString stringWithFormat:@"%ld", (long)(i + 1)];
		NSString *N = [NSString stringWithFormat:@"%ld", (long)n];
		NSString *I = [NSString stringWithFormat:@"%ld", (long)(n - 1)];
		for (NSMutableString *x in @[p, s]) {
			[x replaceOccurrencesOfString:@"$(L)" withString:L options:0 range:NSMakeRange(0, x.length)];
			[x replaceOccurrencesOfString:@"$(N)" withString:N options:0 range:NSMakeRange(0, x.length)];
			[x replaceOccurrencesOfString:@"$(I)" withString:I options:0 range:NSMakeRange(0, x.length)];
		}
		[out addObject:[NSString stringWithFormat:@"%@%@%@", p, line, s]];
	}
	[e message:SCI_BEGINUNDOACTION wParam:0 lParam:0];
	NPReplaceLines(e, first, last, out);
	[e message:SCI_ENDUNDOACTION wParam:0 lParam:0];
}

- (void)editJoinParagraphs {
	ScintillaView *e = self.editorDocument.editor;
	sptr_t start = 0, end = 0;
	NPLineSpan(e, &start, &end);
	if (end <= start) return;
	const char *raw = (const char *)[e message:SCI_GETRANGEPOINTER wParam:start lParam:end - start];
	if (!raw) return;
	NSString *src = [[NSString alloc] initWithBytes:raw length:(NSUInteger)(end - start) encoding:NSUTF8StringEncoding] ?: @"";
	src = [src stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\n"];
	src = [src stringByReplacingOccurrencesOfString:@"\r" withString:@"\n"];
	NSArray *paras = [src componentsSeparatedByString:@"\n\n"];
	NSMutableArray *out = [NSMutableArray array];
	for (NSString *p in paras) {
		NSString *one = [[p stringByReplacingOccurrencesOfString:@"\n" withString:@" "]
			stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
		[out addObject:one];
	}
	NSString *joined = [out componentsJoinedByString:[NPEOL(e) stringByAppendingString:NPEOL(e)]];
	[e message:SCI_SETTARGETSTART wParam:start lParam:0];
	[e message:SCI_SETTARGETEND wParam:end lParam:0];
	NPReplaceTargetStr(e, joined);
}

- (void)editColumnWrap {
	NSInteger col = [[NSUserDefaults standardUserDefaults] integerForKey:@"NP4WrapColumn"];
	if (col < 8) col = 80;
	if (!NPHeadless() && self.window) {
		NSAlert *a = [[NSAlert alloc] init];
		a.messageText = NPL(@"Column Wrap");
		NSTextField *f = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 80, 24)];
		f.stringValue = [NSString stringWithFormat:@"%ld", (long)col];
		a.accessoryView = f;
		[a addButtonWithTitle:NPL(@"OK")];
		[a addButtonWithTitle:NPL(@"Cancel")];
		if ([a runModal] != NSAlertFirstButtonReturn) return;
		col = MAX(8, f.integerValue);
		[[NSUserDefaults standardUserDefaults] setInteger:col forKey:@"NP4WrapColumn"];
	}
	ScintillaView *e = self.editorDocument.editor;
	sptr_t first = 0, last = 0;
	NPLineRange(e, &first, &last);
	NSMutableArray *out = [NSMutableArray array];
	for (NSString *line in NPCollectLines(e, first, last)) {
		NSString *rest = line;
		if (rest.length == 0) { [out addObject:@""]; continue; }
		while (rest.length > (NSUInteger)col) {
			NSUInteger cut = (NSUInteger)col;
			NSRange sp = [rest rangeOfString:@" " options:NSBackwardsSearch range:NSMakeRange(0, cut)];
			if (sp.location != NSNotFound && sp.location > (NSUInteger)col / 3) cut = sp.location;
			[out addObject:[rest substringToIndex:cut]];
			rest = [[rest substringFromIndex:cut] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
		}
		[out addObject:rest];
	}
	[e message:SCI_BEGINUNDOACTION wParam:0 lParam:0];
	NPReplaceLines(e, first, last, out);
	[e message:SCI_ENDUNDOACTION wParam:0 lParam:0];
}

- (void)editTabifySelection {
	ScintillaView *e = self.editorDocument.editor;
	NSString *sel = [e selectedString];
	if (sel.length == 0) return;
	const NSInteger tw = MAX(1, [e message:SCI_GETTABWIDTH]);
	NSMutableString *out = [NSMutableString string];
	__block NSInteger col = 0;
	__block NSInteger spaces = 0;
	void (^flush)(void) = ^{
		while (spaces >= tw) { [out appendString:@"\t"]; spaces -= tw; }
		while (spaces > 0) { [out appendString:@" "]; spaces--; }
	};
	for (NSUInteger i = 0; i < sel.length; i++) {
		unichar c = [sel characterAtIndex:i];
		if (c == ' ') { spaces++; col++; }
		else if (c == '\t') { spaces += tw - (col % tw); col += tw - (col % tw); }
		else {
			flush();
			[out appendFormat:@"%C", c];
			if (c == '\n' || c == '\r') col = 0;
			else col++;
		}
	}
	flush();
	NPReplaceSel(e, out);
}

- (void)editUntabifySelection {
	ScintillaView *e = self.editorDocument.editor;
	NSString *sel = [e selectedString];
	if (sel.length == 0) return;
	const NSInteger tw = MAX(1, [e message:SCI_GETTABWIDTH]);
	NSMutableString *out = [NSMutableString string];
	NSInteger col = 0;
	for (NSUInteger i = 0; i < sel.length; i++) {
		unichar c = [sel characterAtIndex:i];
		if (c == '\t') {
			NSInteger n = tw - (col % tw);
			[out appendString:[@"" stringByPaddingToLength:(NSUInteger)n withString:@" " startingAtIndex:0]];
			col += n;
		} else {
			[out appendFormat:@"%C", c];
			if (c == '\n' || c == '\r') col = 0;
			else col++;
		}
	}
	NPReplaceSel(e, out);
}

- (void)editDeleteWordLeft { [self.editorDocument.editor message:SCI_DELWORDLEFT wParam:0 lParam:0]; }
- (void)editDeleteWordRight { [self.editorDocument.editor message:SCI_DELWORDRIGHT wParam:0 lParam:0]; }

- (void)editBumpNumber:(BOOL)up {
	ScintillaView *e = self.editorDocument.editor;
	NSString *sel = [[e selectedString] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if (sel.length == 0) return;
	long long v = 0;
	if (!NPParseNumber(sel, &v)) return;
	v += up ? 1 : -1;
	NPReplaceSel(e, [NSString stringWithFormat:@"%lld", v]);
}
- (void)editIncreaseNumber { [self editBumpNumber:YES]; }
- (void)editDecreaseNumber { [self editBumpNumber:NO]; }

- (void)editShowHex {
	NSString *sel = [self.editorDocument.editor selectedString];
	if (sel.length == 0) return;
	NSMutableString *out = [NSMutableString string];
	const char *u = sel.UTF8String ?: "";
	for (size_t i = 0; u[i]; i++) [out appendFormat:@"%02X ", (unsigned char)u[i]];
	if (out.length) [out deleteCharactersInRange:NSMakeRange(out.length - 1, 1)];
	NPReplaceSel(self.editorDocument.editor, out);
}

- (void)editShowCharInfo {
	NSString *sel = [self.editorDocument.editor selectedString];
	if (sel.length == 0) return;
	const NSRange r = [sel rangeOfComposedCharacterSequenceAtIndex:0];
	NSString *ch = [sel substringWithRange:r];
	uint32_t cp = [ch characterAtIndex:0];
	if (r.length > 1) {
		uint32_t hi = [ch characterAtIndex:0], lo = [ch characterAtIndex:1];
		cp = 0x10000 + ((hi - 0xD800) << 10) + (lo - 0xDC00);
	}
	NPReplaceSel(self.editorDocument.editor, [NSString stringWithFormat:@"U+%04X", cp]);
}

- (void)insertUnicodeZWJ { NPReplaceSel(self.editorDocument.editor, @"\u200D"); }
- (void)insertUnicodeZWNJ { NPReplaceSel(self.editorDocument.editor, @"\u200C"); }
- (void)insertUnicodeWJ { NPReplaceSel(self.editorDocument.editor, @"\u2060"); }
- (void)insertUnicodeSHY { NPReplaceSel(self.editorDocument.editor, @"\u00AD"); }
- (void)insertUnicodeLS { NPReplaceSel(self.editorDocument.editor, @"\u2028"); }
- (void)insertUnicodePS { NPReplaceSel(self.editorDocument.editor, @"\u2029"); }

- (void)insertPathName {
	NSString *path = self.editorDocument.fileURL.path ?: NPL(@"Untitled");
	NPReplaceSel(self.editorDocument.editor, path);
}
- (void)insertFileNameAndExt {
	NSString *name = self.editorDocument.fileURL.lastPathComponent ?: NPL(@"Untitled");
	NPReplaceSel(self.editorDocument.editor, name);
}
- (void)insertShortDate {
	NSDateFormatter *f = [[NSDateFormatter alloc] init];
	f.dateStyle = NSDateFormatterShortStyle;
	f.timeStyle = NSDateFormatterNoStyle;
	NPReplaceSel(self.editorDocument.editor, [f stringFromDate:[NSDate date]]);
}
- (void)insertUTCDateTime {
	NSDateFormatter *f = [[NSDateFormatter alloc] init];
	f.timeZone = [NSTimeZone timeZoneWithAbbreviation:@"UTC"];
	f.dateFormat = @"yyyy-MM-dd HH:mm:ss'Z'";
	NPReplaceSel(self.editorDocument.editor, [f stringFromDate:[NSDate date]]);
}
- (void)insertTimestampMs {
	long long ms = (long long)([[NSDate date] timeIntervalSince1970] * 1000.0);
	NPReplaceSel(self.editorDocument.editor, [NSString stringWithFormat:@"%lld", ms]);
}
- (void)copyFileNameAndExt {
	NSString *name = self.editorDocument.fileURL.lastPathComponent;
	if (!name.length) return;
	NSPasteboard *pb = [NSPasteboard generalPasteboard];
	[pb clearContents];
	[pb setString:name forType:NSPasteboardTypeString];
}
- (void)copyWinPos {
	NSRect r = self.window.frame;
	NSString *s = [NSString stringWithFormat:@"%.0f, %.0f, %.0f, %.0f", r.origin.x, r.origin.y, r.size.width, r.size.height];
	NSPasteboard *pb = [NSPasteboard generalPasteboard];
	[pb clearContents];
	[pb setString:s forType:NSPasteboardTypeString];
}


static NSString *NPTransformSel(NSString *s, NSString *name, BOOL reverse) {
	if (s.length == 0) return s;
	NSMutableString *m = [s mutableCopy];
	CFStringTransform((__bridge CFMutableStringRef)m, NULL, (__bridge CFStringRef)name, reverse);
	return m;
}
static void NPApplySelOrDoc(ScintillaView *e, NSString *(^fn)(NSString *)) {
	if (!e || !fn) return;
	NSString *sel = [e selectedString];
	if (sel.length) {
		NPReplaceSel(e, fn(sel));
		return;
	}
	NSString *all = [e string] ?: @"";
	if (all.length == 0) return;
	[e setString:fn(all)];
}
static unichar NPFullwidth(unichar c) {
	if (c == 0x20) return 0x3000;
	if (c >= 0x21 && c <= 0x7E) return (unichar)(c + 0xFEE0);
	return c;
}
static unichar NPHalfwidth(unichar c) {
	if (c == 0x3000) return 0x20;
	if (c >= 0xFF01 && c <= 0xFF5E) return (unichar)(c - 0xFEE0);
	return c;
}
static NSString *NPMapWidth(NSString *s, BOOL toFull) {
	NSMutableString *o = [NSMutableString stringWithCapacity:s.length];
	for (NSUInteger i = 0; i < s.length; i++) {
		unichar c = [s characterAtIndex:i];
		[o appendFormat:@"%C", toFull ? NPFullwidth(c) : NPHalfwidth(c)];
	}
	return o;
}

static int NPPrec(unichar c) {
	if (c == '*' || c == '/') return 2;
	if (c == '+' || c == '-') return 1;
	return 0;
}
static BOOL NPEvalExpr(NSString *src, double *outVal) {
	NSString *s = [[src stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]
		stringByReplacingOccurrencesOfString:@"×" withString:@"*"];
	s = [s stringByReplacingOccurrencesOfString:@"÷" withString:@"/"];
	if (s.length == 0) return NO;
	NSMutableArray *vals = [NSMutableArray array];
	NSMutableArray *ops = [NSMutableArray array];
	void (^apply)(void) = ^{
		if (vals.count < 2 || ops.count == 0) return;
		double b = [vals.lastObject doubleValue]; [vals removeLastObject];
		double a = [vals.lastObject doubleValue]; [vals removeLastObject];
		unichar op = (unichar)[ops.lastObject integerValue]; [ops removeLastObject];
		double r = 0;
		if (op == '+') r = a + b;
		else if (op == '-') r = a - b;
		else if (op == '*') r = a * b;
		else if (op == '/') r = (b == 0) ? 0 : a / b;
		[vals addObject:@(r)];
	};
	NSUInteger i = 0;
	BOOL expectNum = YES;
	while (i < s.length) {
		unichar c = [s characterAtIndex:i];
		if (c == ' ' || c == '\t') { i++; continue; }
		if ((c >= '0' && c <= '9') || c == '.' || (expectNum && (c == '-' || c == '+'))) {
			NSInteger sign = 1;
			if (c == '-' || c == '+') { if (c == '-') sign = -1; i++; }
			NSUInteger start = i;
			while (i < s.length) {
				unichar d = [s characterAtIndex:i];
				if ((d >= '0' && d <= '9') || d == '.') i++;
				else break;
			}
			if (i == start) return NO;
			double v = [[s substringWithRange:NSMakeRange(start, i - start)] doubleValue] * sign;
			[vals addObject:@(v)];
			expectNum = NO;
			continue;
		}
		if (c == '(') { [ops addObject:@(c)]; expectNum = YES; i++; continue; }
		if (c == ')') {
			while (ops.count && [ops.lastObject integerValue] != '(') apply();
			if (ops.count == 0) return NO;
			[ops removeLastObject];
			expectNum = NO; i++; continue;
		}
		if (c == '+' || c == '-' || c == '*' || c == '/') {
			while (ops.count && NPPrec((unichar)[ops.lastObject integerValue]) >= NPPrec(c)) apply();
			[ops addObject:@(c)];
			expectNum = YES; i++; continue;
		}
		return NO;
	}
	while (ops.count) {
		if ([ops.lastObject integerValue] == '(') return NO;
		apply();
	}
	if (vals.count != 1) return NO;
	*outVal = [vals[0] doubleValue];
	return YES;
}

static NSString *NPPrettyJSON(NSString *s) {
	NSData *d = [s dataUsingEncoding:NSUTF8StringEncoding];
	if (!d) return nil;
	NSError *err = nil;
	id obj = [NSJSONSerialization JSONObjectWithData:d options:NSJSONReadingFragmentsAllowed error:&err];
	if (!obj) return nil;
	NSData *o = [NSJSONSerialization dataWithJSONObject:obj options:NSJSONWritingPrettyPrinted error:&err];
	if (!o) return nil;
	return [[NSString alloc] initWithData:o encoding:NSUTF8StringEncoding];
}
static NSString *NPCompressJSON(NSString *s) {
	NSData *d = [s dataUsingEncoding:NSUTF8StringEncoding];
	if (!d) return nil;
	NSError *err = nil;
	id obj = [NSJSONSerialization JSONObjectWithData:d options:NSJSONReadingFragmentsAllowed error:&err];
	if (!obj) return nil;
	NSData *o = [NSJSONSerialization dataWithJSONObject:obj options:0 error:&err];
	if (!o) return nil;
	return [[NSString alloc] initWithData:o encoding:NSUTF8StringEncoding];
}
static NSString *NPCompressCode(NSString *s) {
	NSString *json = NPCompressJSON(s);
	if (json) return json;
	NSMutableString *o = [NSMutableString string];
	BOOL inStr = NO; unichar q = 0; BOOL esc = NO;
	BOOL space = NO;
	for (NSUInteger i = 0; i < s.length; i++) {
		unichar c = [s characterAtIndex:i];
		if (inStr) {
			[o appendFormat:@"%C", c];
			if (esc) esc = NO;
			else if (c == '\\') esc = YES;
			else if (c == q) inStr = NO;
			continue;
		}
		if (c == '"' || c == '\'') { inStr = YES; q = c; space = NO; [o appendFormat:@"%C", c]; continue; }
		if (c == ' ' || c == '\t' || c == '\n' || c == '\r') { space = YES; continue; }
		if (space && o.length) {
			unichar prev = [o characterAtIndex:o.length - 1];
			if (!strchr("{}[]():;,+-=<>!&|", (int)prev) && !strchr("{}[]():;,+-=<>!&|", (int)c))
				[o appendString:@" "];
		}
		space = NO;
		[o appendFormat:@"%C", c];
	}
	return o;
}
static NSString *NPPrettyCode(NSString *s) {
	NSString *json = NPPrettyJSON(s);
	if (json) return json;
	NSMutableString *o = [NSMutableString string];
	int indent = 0;
	BOOL inStr = NO; unichar q = 0; BOOL esc = NO;
	for (NSUInteger i = 0; i < s.length; i++) {
		unichar c = [s characterAtIndex:i];
		if (inStr) {
			[o appendFormat:@"%C", c];
			if (esc) esc = NO;
			else if (c == '\\') esc = YES;
			else if (c == q) inStr = NO;
			continue;
		}
		if (c == '"' || c == '\'') { inStr = YES; q = c; [o appendFormat:@"%C", c]; continue; }
		if (c == '}') {
			indent = indent > 0 ? indent - 1 : 0;
			[o appendString:@"\n"];
			for (int k = 0; k < indent; k++) [o appendString:@"\t"];
			[o appendString:@"}"];
			continue;
		}
		if (c == '{') {
			[o appendString:@" {\n"];
			indent++;
			for (int k = 0; k < indent; k++) [o appendString:@"\t"];
			continue;
		}
		if (c == ';') {
			[o appendString:@";\n"];
			for (int k = 0; k < indent; k++) [o appendString:@"\t"];
			continue;
		}
		if (c == '\n' || c == '\r') continue;
		[o appendFormat:@"%C", c];
	}
	return o;
}

static void NPSearchSel(ScintillaView *e, BOOL forward) {
	NSString *needle = [e selectedString];
	if (needle.length == 0) {
		[e message:SCI_WORDLEFTEXTEND wParam:0 lParam:0];
		needle = [e selectedString];
	}
	if (needle.length == 0) return;
	const char *u = needle.UTF8String ?: "";
	const sptr_t selA = [e message:SCI_GETSELECTIONSTART];
	const sptr_t selB = [e message:SCI_GETSELECTIONEND];
	const sptr_t n = [e message:SCI_GETLENGTH];
	if (forward) {
		[e message:SCI_SETTARGETSTART wParam:selB lParam:0];
		[e message:SCI_SETTARGETEND wParam:n lParam:0];
	} else {
		[e message:SCI_SETTARGETSTART wParam:selA lParam:0];
		[e message:SCI_SETTARGETEND wParam:0 lParam:0];
	}
	const sptr_t hit = [e message:SCI_SEARCHINTARGET wParam:(sptr_t)strlen(u) lParam:(sptr_t)u];
	if (hit >= 0) [e message:SCI_SETSEL wParam:hit lParam:hit + (sptr_t)strlen(u)];
}

static sptr_t NPFoldHeader(ScintillaView *e, sptr_t line) {
	const sptr_t lvl = [e message:SCI_GETFOLDLEVEL wParam:line];
	if (lvl & SC_FOLDLEVELHEADERFLAG) return line;
	return [e message:SCI_GETFOLDPARENT wParam:line];
}
static void NPGotoLine(ScintillaView *e, sptr_t line) {
	if (line < 0) return;
	const sptr_t pos = [e message:SCI_POSITIONFROMLINE wParam:line];
	[e message:SCI_GOTOPOS wParam:pos lParam:0];
}
static sptr_t NPNextHeader(ScintillaView *e, sptr_t from, BOOL back, int wantLevel) {
	const sptr_t n = [e message:SCI_GETLINECOUNT];
	if (back) {
		for (sptr_t l = from - 1; l >= 0; l--) {
			const sptr_t lvl = [e message:SCI_GETFOLDLEVEL wParam:l];
			if (!(lvl & SC_FOLDLEVELHEADERFLAG)) continue;
			if (wantLevel < 0 || (int)(lvl & SC_FOLDLEVELNUMBERMASK) == wantLevel) return l;
		}
	} else {
		for (sptr_t l = from + 1; l < n; l++) {
			const sptr_t lvl = [e message:SCI_GETFOLDLEVEL wParam:l];
			if (!(lvl & SC_FOLDLEVELHEADERFLAG)) continue;
			if (wantLevel < 0 || (int)(lvl & SC_FOLDLEVELNUMBERMASK) == wantLevel) return l;
		}
	}
	return -1;
}

- (void)insertUnicodeLRE { NPReplaceSel(self.editorDocument.editor, @"\u202A"); }
- (void)insertUnicodeRLE { NPReplaceSel(self.editorDocument.editor, @"\u202B"); }
- (void)insertUnicodeLRO { NPReplaceSel(self.editorDocument.editor, @"\u202D"); }
- (void)insertUnicodeRLO { NPReplaceSel(self.editorDocument.editor, @"\u202E"); }
- (void)insertUnicodeLRI { NPReplaceSel(self.editorDocument.editor, @"\u2066"); }
- (void)insertUnicodeRLI { NPReplaceSel(self.editorDocument.editor, @"\u2067"); }
- (void)insertUnicodeFSI { NPReplaceSel(self.editorDocument.editor, @"\u2068"); }
- (void)insertUnicodePDI { NPReplaceSel(self.editorDocument.editor, @"\u2069"); }
- (void)insertUnicodePDF { NPReplaceSel(self.editorDocument.editor, @"\u202C"); }
- (void)insertUnicodeALM { NPReplaceSel(self.editorDocument.editor, @"\u061C"); }
- (void)insertUnicodeRS { NPReplaceSel(self.editorDocument.editor, @"\u001E"); }
- (void)insertUnicodeUS { NPReplaceSel(self.editorDocument.editor, @"\u001F"); }
- (void)insertCurrentDate {
	NSDateFormatter *f = [[NSDateFormatter alloc] init];
	f.dateFormat = @"yyyy-MM-dd";
	NPReplaceSel(self.editorDocument.editor, [f stringFromDate:[NSDate date]]);
}
- (void)insertLongDate {
	NSDateFormatter *f = [[NSDateFormatter alloc] init];
	f.dateStyle = NSDateFormatterFullStyle;
	f.timeStyle = NSDateFormatterMediumStyle;
	NPReplaceSel(self.editorDocument.editor, [f stringFromDate:[NSDate date]]);
}
- (void)insertTimestampUs {
	long long us = (long long)([[NSDate date] timeIntervalSince1970] * 1000000.0);
	NPReplaceSel(self.editorDocument.editor, [NSString stringWithFormat:@"%lld", us]);
}
- (void)insertTimestampNs {
	long long ns = (long long)([[NSDate date] timeIntervalSince1970] * 1000000000.0);
	NPReplaceSel(self.editorDocument.editor, [NSString stringWithFormat:@"%lld", ns]);
}
- (void)editUpdateTimestamps {
	ScintillaView *e = self.editorDocument.editor;
	NSString *src = [e string] ?: @"";
	NSDateFormatter *f = [[NSDateFormatter alloc] init];
	f.dateFormat = @"yyyy/MM/dd HH:mm:ss";
	NSString *now = [f stringFromDate:[NSDate date]];
	NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"\\$Date:[^$]*\\$" options:0 error:nil];
	NSString *out = [re stringByReplacingMatchesInString:src options:0 range:NSMakeRange(0, src.length)
		withTemplate:[NSString stringWithFormat:@"$Date: %@ $", now]];
	if ([out isEqualToString:src]) {
		NSDateFormatter *iso = [[NSDateFormatter alloc] init];
		iso.dateFormat = @"yyyy-MM-dd HH:mm:ss";
		NSString *isoNow = [iso stringFromDate:[NSDate date]];
		re = [NSRegularExpression regularExpressionWithPattern:@"\\d{4}-\\d{2}-\\d{2} \\d{2}:\\d{2}:\\d{2}" options:0 error:nil];
		out = [re stringByReplacingMatchesInString:src options:0 range:NSMakeRange(0, src.length) withTemplate:isoNow];
	}
	if (![out isEqualToString:src]) [e setString:out];
}
- (void)searchSelectLineBlock {
	ScintillaView *e = self.editorDocument.editor;
	const sptr_t pos = [e message:SCI_GETCURRENTPOS];
	const sptr_t line = [e message:SCI_LINEFROMPOSITION wParam:pos];
	sptr_t head = NPFoldHeader(e, line);
	if (head < 0) head = line;
	const sptr_t last = [e message:SCI_GETLASTCHILD wParam:head lParam:-1];
	const sptr_t a = [e message:SCI_POSITIONFROMLINE wParam:head];
	const sptr_t b = (last + 1 < [e message:SCI_GETLINECOUNT])
		? [e message:SCI_POSITIONFROMLINE wParam:last + 1]
		: [e message:SCI_GETLENGTH];
	[e message:SCI_SETSEL wParam:a lParam:b];
}
- (void)searchSelectToNext { NPSearchSel(self.editorDocument.editor, YES); }
- (void)searchSelectToPrev { NPSearchSel(self.editorDocument.editor, NO); }
- (void)bookmarkSelectAll {
	ScintillaView *e = self.editorDocument.editor;
	const sptr_t n = [e message:SCI_GETLINECOUNT];
	BOOL first = YES;
	for (sptr_t l = 0; l < n; l++) {
		if (([e message:SCI_MARKERGET wParam:l] & 2) == 0) continue;
		const sptr_t a = [e message:SCI_POSITIONFROMLINE wParam:l];
		const sptr_t b = [e message:SCI_GETLINEENDPOSITION wParam:l];
		if (first) { [e message:SCI_SETSELECTION wParam:a lParam:b]; first = NO; }
		else [e message:SCI_ADDSELECTION wParam:a lParam:b];
	}
}
- (void)gotoBlockStart {
	ScintillaView *e = self.editorDocument.editor;
	const sptr_t line = [e message:SCI_LINEFROMPOSITION wParam:[e message:SCI_GETCURRENTPOS]];
	NPGotoLine(e, NPFoldHeader(e, line));
}
- (void)gotoBlockEnd {
	ScintillaView *e = self.editorDocument.editor;
	const sptr_t line = [e message:SCI_LINEFROMPOSITION wParam:[e message:SCI_GETCURRENTPOS]];
	sptr_t head = NPFoldHeader(e, line);
	if (head < 0) head = line;
	NPGotoLine(e, [e message:SCI_GETLASTCHILD wParam:head lParam:-1]);
}
- (void)gotoPreviousBlock {
	ScintillaView *e = self.editorDocument.editor;
	const sptr_t line = [e message:SCI_LINEFROMPOSITION wParam:[e message:SCI_GETCURRENTPOS]];
	NPGotoLine(e, NPNextHeader(e, line, YES, -1));
}
- (void)gotoNextBlock {
	ScintillaView *e = self.editorDocument.editor;
	const sptr_t line = [e message:SCI_LINEFROMPOSITION wParam:[e message:SCI_GETCURRENTPOS]];
	NPGotoLine(e, NPNextHeader(e, line, NO, -1));
}
- (void)gotoPrevSiblingBlock {
	ScintillaView *e = self.editorDocument.editor;
	const sptr_t line = [e message:SCI_LINEFROMPOSITION wParam:[e message:SCI_GETCURRENTPOS]];
	sptr_t head = NPFoldHeader(e, line);
	if (head < 0) head = line;
	const int lvl = (int)([e message:SCI_GETFOLDLEVEL wParam:head] & SC_FOLDLEVELNUMBERMASK);
	NPGotoLine(e, NPNextHeader(e, head, YES, lvl));
}
- (void)gotoNextSiblingBlock {
	ScintillaView *e = self.editorDocument.editor;
	const sptr_t line = [e message:SCI_LINEFROMPOSITION wParam:[e message:SCI_GETCURRENTPOS]];
	sptr_t head = NPFoldHeader(e, line);
	if (head < 0) head = line;
	const int lvl = (int)([e message:SCI_GETFOLDLEVEL wParam:head] & SC_FOLDLEVELNUMBERMASK);
	NPGotoLine(e, NPNextHeader(e, head, NO, lvl));
}
- (void)gotoSelStart {
	ScintillaView *e = self.editorDocument.editor;
	[e message:SCI_GOTOPOS wParam:[e message:SCI_GETSELECTIONSTART] lParam:0];
}
- (void)gotoSelEnd {
	ScintillaView *e = self.editorDocument.editor;
	[e message:SCI_GOTOPOS wParam:[e message:SCI_GETSELECTIONEND] lParam:0];
}
- (void)actionSearchBing {
	if (NPHeadless()) return;
	NSString *sel = [self.editorDocument.editor selectedString];
	if (!sel.length) return;
	NSString *q = [sel stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
	[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:[@"https://www.bing.com/search?q=" stringByAppendingString:q ?: @""]]];
}
- (void)actionSearchWiki {
	if (NPHeadless()) return;
	NSString *sel = [self.editorDocument.editor selectedString];
	if (!sel.length) return;
	NSString *q = [sel stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
	[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:[@"https://wikipedia.org/wiki/Special:Search?search=" stringByAppendingString:q ?: @""]]];
}
- (void)base64HTMLEmbed {
	ScintillaView *e = self.editorDocument.editor;
	NSString *sel = [e selectedString];
	if (!sel.length) return;
	NSString *b64 = [[sel dataUsingEncoding:NSUTF8StringEncoding] base64EncodedStringWithOptions:0];
	NSString *ext = self.editorDocument.fileURL.pathExtension.lowercaseString ?: @"png";
	if (![@[@"png", @"jpg", @"jpeg", @"gif", @"webp", @"svg"] containsObject:ext]) ext = @"png";
	if ([ext isEqualToString:@"jpg"]) ext = @"jpeg";
	NPReplaceSel(e, [NSString stringWithFormat:@"<img src=\"data:image/%@;base64,%@\">", ext, b64]);
}
- (void)base64DecodeHex {
	NSString *sel = [self.editorDocument.editor selectedString];
	if (!sel.length) return;
	NSData *d = [[NSData alloc] initWithBase64EncodedString:sel options:NSDataBase64DecodingIgnoreUnknownCharacters];
	if (!d) return;
	const unsigned char *b = (const unsigned char *)d.bytes;
	NSMutableString *o = [NSMutableString string];
	for (NSUInteger i = 0; i < d.length; i++) [o appendFormat:@"%02X", b[i]];
	NPReplaceSel(self.editorDocument.editor, o);
}
- (void)mapHalfToFull { NPApplySelOrDoc(self.editorDocument.editor, ^NSString *(NSString *s) { return NPMapWidth(s, YES); }); }
- (void)mapFullToHalf { NPApplySelOrDoc(self.editorDocument.editor, ^NSString *(NSString *s) { return NPMapWidth(s, NO); }); }
- (void)mapTradToSimp { NPApplySelOrDoc(self.editorDocument.editor, ^NSString *(NSString *s) { return NPTransformSel(s, @"Hant-Hans", NO); }); }
- (void)mapSimpToTrad { NPApplySelOrDoc(self.editorDocument.editor, ^NSString *(NSString *s) { return NPTransformSel(s, @"Hans-Hant", NO); }); }
- (void)mapKataToHira { NPApplySelOrDoc(self.editorDocument.editor, ^NSString *(NSString *s) { return NPTransformSel(s, (__bridge NSString *)kCFStringTransformHiraganaKatakana, YES); }); }
- (void)mapHiraToKata { NPApplySelOrDoc(self.editorDocument.editor, ^NSString *(NSString *s) { return NPTransformSel(s, (__bridge NSString *)kCFStringTransformHiraganaKatakana, NO); }); }
- (void)mapHanjaToHangul { NPApplySelOrDoc(self.editorDocument.editor, ^NSString *(NSString *s) { return NPTransformSel(s, @"Hanja-Hangul", NO); }); }
- (void)mapHangulDecomp { NPApplySelOrDoc(self.editorDocument.editor, ^NSString *(NSString *s) { return [s decomposedStringWithCanonicalMapping]; }); }
- (void)mapBengaliLatin { NPApplySelOrDoc(self.editorDocument.editor, ^NSString *(NSString *s) { return NPTransformSel(s, @"Bengali-Latin", NO); }); }
- (void)mapCyrillicLatin { NPApplySelOrDoc(self.editorDocument.editor, ^NSString *(NSString *s) { return NPTransformSel(s, @"Cyrillic-Latin", NO); }); }
- (void)mapDevanagariLatin { NPApplySelOrDoc(self.editorDocument.editor, ^NSString *(NSString *s) { return NPTransformSel(s, @"Devanagari-Latin", NO); }); }
- (void)mapMalayalamLatin { NPApplySelOrDoc(self.editorDocument.editor, ^NSString *(NSString *s) { return NPTransformSel(s, @"Malayalam-Latin", NO); }); }
- (void)editCalculateExpression {
	ScintillaView *e = self.editorDocument.editor;
	NSString *sel = [e selectedString];
	if (sel.length == 0) return;
	double v = 0;
	if (!NPEvalExpr(sel, &v)) return;
	if (fabs(v - llround(v)) < 1e-9)
		NPReplaceSel(e, [NSString stringWithFormat:@"%lld", (long long)llround(v)]);
	else
		NPReplaceSel(e, [NSString stringWithFormat:@"%.8g", v]);
}
- (void)editCodeCompress {
	NPApplySelOrDoc(self.editorDocument.editor, ^NSString *(NSString *s) { return NPCompressCode(s); });
}
- (void)editCodePretty {
	NPApplySelOrDoc(self.editorDocument.editor, ^NSString *(NSString *s) { return NPPrettyCode(s); });
}

@end
