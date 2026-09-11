#import "PreviewPane.h"
#import "EditorDocument.h"
#import "ScintillaView.h"
#import "Scintilla.h"
#import "NPLocalization.h"
#import "NPTheme.h"
#import <WebKit/WebKit.h>

static const NSUInteger kNPPreviewMaxChars = 1500u * 1024u;

static NSString *NPEscapeHTML(NSString *s) {
	if (s.length == 0) return @"";
	NSMutableString *o = [s mutableCopy];
	[o replaceOccurrencesOfString:@"&" withString:@"&amp;" options:0 range:NSMakeRange(0, o.length)];
	[o replaceOccurrencesOfString:@"<" withString:@"&lt;" options:0 range:NSMakeRange(0, o.length)];
	[o replaceOccurrencesOfString:@">" withString:@"&gt;" options:0 range:NSMakeRange(0, o.length)];
	[o replaceOccurrencesOfString:@"\"" withString:@"&quot;" options:0 range:NSMakeRange(0, o.length)];
	return o;
}

static BOOL NPSafeURL(NSString *u) {
	NSString *s = u.lowercaseString ?: @"";
	if ([s hasPrefix:@"javascript:"] || [s hasPrefix:@"vbscript:"]) return NO;
	if ([s hasPrefix:@"data:text/html"]) return NO;
	return YES;
}

static NSString *NPApplyInline(NSString *line);

static NSRange NPFindCloser(NSString *s, NSUInteger from, NSString *tok) {
	if (from >= s.length) return NSMakeRange(NSNotFound, 0);
	return [s rangeOfString:tok options:0 range:NSMakeRange(from, s.length - from)];
}

static NSString *NPApplyInline(NSString *line) {
	if (line.length == 0) return @"";
	NSMutableString *out = [NSMutableString string];
	const NSUInteger n = line.length;
	NSUInteger i = 0;
	while (i < n) {
		unichar c = [line characterAtIndex:i];
		if (c == '`') {
			NSRange end = NPFindCloser(line, i + 1, @"`");
			if (end.location != NSNotFound) {
				NSString *code = [line substringWithRange:NSMakeRange(i + 1, end.location - i - 1)];
				[out appendFormat:@"<code>%@</code>", NPEscapeHTML(code)];
				i = end.location + 1;
				continue;
			}
		}
		if (c == '!' && i + 1 < n && [line characterAtIndex:i + 1] == '[') {
			NSRange rb = NPFindCloser(line, i + 2, @"](");
			if (rb.location != NSNotFound) {
				NSRange rp = NPFindCloser(line, rb.location + 2, @")");
				if (rp.location != NSNotFound) {
					NSString *alt = [line substringWithRange:NSMakeRange(i + 2, rb.location - i - 2)];
					NSString *url = [line substringWithRange:NSMakeRange(rb.location + 2, rp.location - rb.location - 2)];
					if (NPSafeURL(url))
						[out appendFormat:@"<img alt=\"%@\" src=\"%@\">", NPEscapeHTML(alt), NPEscapeHTML(url)];
					else
						[out appendString:NPEscapeHTML(alt)];
					i = rp.location + 1;
					continue;
				}
			}
		}
		if (c == '[') {
			NSRange rb = NPFindCloser(line, i + 1, @"](");
			if (rb.location != NSNotFound) {
				NSRange rp = NPFindCloser(line, rb.location + 2, @")");
				if (rp.location != NSNotFound) {
					NSString *text = [line substringWithRange:NSMakeRange(i + 1, rb.location - i - 1)];
					NSString *url = [line substringWithRange:NSMakeRange(rb.location + 2, rp.location - rb.location - 2)];
					if (NPSafeURL(url))
						[out appendFormat:@"<a href=\"%@\">%@</a>", NPEscapeHTML(url), NPApplyInline(text)];
					else
						[out appendString:NPApplyInline(text)];
					i = rp.location + 1;
					continue;
				}
			}
		}
		if ((c == '*' || c == '_') && i + 1 < n && [line characterAtIndex:i + 1] == c) {
			NSString *tok = (c == '*') ? @"**" : @"__";
			NSRange end = NPFindCloser(line, i + 2, tok);
			if (end.location != NSNotFound) {
				NSString *inner = [line substringWithRange:NSMakeRange(i + 2, end.location - i - 2)];
				[out appendFormat:@"<strong>%@</strong>", NPApplyInline(inner)];
				i = end.location + 2;
				continue;
			}
		}
		if (c == '*' || c == '_') {
			NSString *tok = (c == '*') ? @"*" : @"_";
			NSRange end = NPFindCloser(line, i + 1, tok);
			if (end.location != NSNotFound && (end.location + 1 >= n || [line characterAtIndex:end.location + 1] != c)) {
				NSString *inner = [line substringWithRange:NSMakeRange(i + 1, end.location - i - 1)];
				[out appendFormat:@"<em>%@</em>", NPApplyInline(inner)];
				i = end.location + 1;
				continue;
			}
		}
		if (c == '~' && i + 1 < n && [line characterAtIndex:i + 1] == '~') {
			NSRange end = NPFindCloser(line, i + 2, @"~~");
			if (end.location != NSNotFound) {
				NSString *inner = [line substringWithRange:NSMakeRange(i + 2, end.location - i - 2)];
				[out appendFormat:@"<del>%@</del>", NPApplyInline(inner)];
				i = end.location + 2;
				continue;
			}
		}
		[out appendString:NPEscapeHTML([line substringWithRange:NSMakeRange(i, 1)])];
		i += 1;
	}
	return out;
}

static BOOL NPIsTableSep(NSString *line) {
	NSString *t = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if (t.length < 3 || ![t containsString:@"-"]) return NO;
	for (NSUInteger i = 0; i < t.length; i++) {
		unichar c = [t characterAtIndex:i];
		if (c != '|' && c != '-' && c != ':' && c != ' ' && c != '\t') return NO;
	}
	return YES;
}

static NSArray<NSString *> *NPTableCells(NSString *line) {
	NSString *t = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if ([t hasPrefix:@"|"]) t = [t substringFromIndex:1];
	if ([t hasSuffix:@"|"]) t = [t substringToIndex:t.length - 1];
	NSMutableArray *cells = [NSMutableArray array];
	for (NSString *c in [t componentsSeparatedByString:@"|"])
		[cells addObject:[c stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]];
	return cells;
}

static BOOL NPIsUL(NSString *line, NSString **rest) {
	NSString *t = line;
	NSUInteger i = 0;
	while (i < t.length && ([t characterAtIndex:i] == ' ' || [t characterAtIndex:i] == '\t')) i++;
	if (i >= t.length) return NO;
	unichar c = [t characterAtIndex:i];
	if ((c == '-' || c == '*' || c == '+') && i + 1 < t.length &&
		([t characterAtIndex:i + 1] == ' ' || [t characterAtIndex:i + 1] == '\t')) {
		if (rest) *rest = [t substringFromIndex:i + 2];
		return YES;
	}
	return NO;
}

static BOOL NPIsOL(NSString *line, NSString **rest) {
	NSString *t = line;
	NSUInteger i = 0;
	while (i < t.length && ([t characterAtIndex:i] == ' ' || [t characterAtIndex:i] == '\t')) i++;
	NSUInteger j = i;
	while (j < t.length && [[NSCharacterSet decimalDigitCharacterSet] characterIsMember:[t characterAtIndex:j]]) j++;
	if (j == i || j >= t.length || [t characterAtIndex:j] != '.') return NO;
	if (j + 1 < t.length && ([t characterAtIndex:j + 1] == ' ' || [t characterAtIndex:j + 1] == '\t')) {
		if (rest) *rest = [t substringFromIndex:j + 2];
		return YES;
	}
	return NO;
}

NSString *NPMarkdownToHTML(NSString *markdown) {
	if (markdown.length == 0) return @"";
	NSString *src = [markdown stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\n"];
	src = [src stringByReplacingOccurrencesOfString:@"\r" withString:@"\n"];
	NSArray<NSString *> *lines = [src componentsSeparatedByString:@"\n"];
	NSMutableString *html = [NSMutableString string];
	NSUInteger i = 0;
	const NSUInteger n = lines.count;
	BOOL fence = NO;
	NSUInteger fenceLine = 0;
	NSMutableString *code = [NSMutableString string];
	__block NSString *listTag = nil;
	void (^closeList)(void) = ^{
		if (listTag) {
			[html appendFormat:@"</%@>", listTag];
			listTag = nil;
		}
	};
	void (^openList)(NSString *) = ^(NSString *tag) {
		if ([listTag isEqualToString:tag]) return;
		closeList();
		listTag = tag;
		[html appendFormat:@"<%@>", tag];
	};
	while (i < n) {
		NSString *line = lines[i];
		if (fence) {
			NSString *t = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
			if ([t hasPrefix:@"```"]) {
				[html appendFormat:@"<pre data-src-line=\"%lu\"><code>%@</code></pre>", (unsigned long)(fenceLine + 1), NPEscapeHTML(code)];
				[code setString:@""];
				fence = NO;
			} else {
				if (code.length) [code appendString:@"\n"];
				[code appendString:line];
			}
			i += 1;
			continue;
		}
		NSString *trim = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
		if ([trim hasPrefix:@"```"]) {
			closeList();
			fence = YES;
			fenceLine = i;
			[code setString:@""];
			i += 1;
			continue;
		}
		if (trim.length == 0) {
			closeList();
			i += 1;
			continue;
		}
		if ([trim isEqualToString:@"---"] || [trim isEqualToString:@"***"] || [trim isEqualToString:@"___"]
			|| [trim isEqualToString:@"- - -"] || [trim isEqualToString:@"* * *"]) {
			closeList();
			[html appendFormat:@"<hr data-src-line=\"%lu\">", (unsigned long)(i + 1)];
			i += 1;
			continue;
		}
		if ([trim hasPrefix:@"#"]) {
			closeList();
			NSUInteger hashes = 0;
			while (hashes < trim.length && [trim characterAtIndex:hashes] == '#' && hashes < 6) hashes++;
			if (hashes > 0 && hashes < trim.length && [trim characterAtIndex:hashes] == ' ') {
				NSString *title = [[trim substringFromIndex:hashes + 1]
					stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
				[html appendFormat:@"<h%lu data-src-line=\"%lu\">%@</h%lu>", (unsigned long)hashes, (unsigned long)(i + 1), NPApplyInline(title), (unsigned long)hashes];
				i += 1;
				continue;
			}
		}
		if ([trim hasPrefix:@">"]) {
			closeList();
			NSUInteger qline = i;
			[html appendFormat:@"<blockquote data-src-line=\"%lu\">", (unsigned long)(qline + 1)];
			NSMutableArray *qs = [NSMutableArray array];
			while (i < n) {
				NSString *q = [lines[i] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
				if (![q hasPrefix:@">"]) break;
				NSString *body = [q substringFromIndex:1];
				if ([body hasPrefix:@" "]) body = [body substringFromIndex:1];
				[qs addObject:body];
				i += 1;
			}
			[html appendString:NPApplyInline([qs componentsJoinedByString:@" "])];
			[html appendString:@"</blockquote>"];
			continue;
		}
		if (i + 1 < n && [trim containsString:@"|"] && NPIsTableSep(lines[i + 1])) {
			closeList();
			NSArray *heads = NPTableCells(line);
			[html appendFormat:@"<table data-src-line=\"%lu\"><thead><tr>", (unsigned long)(i + 1)];
			for (NSString *c in heads) [html appendFormat:@"<th>%@</th>", NPApplyInline(c)];
			[html appendString:@"</tr></thead><tbody>"];
			i += 2;
			while (i < n) {
				NSString *row = [lines[i] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
				if (row.length == 0 || ![row containsString:@"|"]) break;
				if (NPIsTableSep(row)) { i += 1; continue; }
				[html appendFormat:@"<tr data-src-line=\"%lu\">", (unsigned long)(i + 1)];
				for (NSString *c in NPTableCells(lines[i]))
					[html appendFormat:@"<td>%@</td>", NPApplyInline(c)];
				[html appendString:@"</tr>"];
				i += 1;
			}
			[html appendString:@"</tbody></table>"];
			continue;
		}
		NSString *item = nil;
		if (NPIsUL(line, &item)) {
			openList(@"ul");
			[html appendFormat:@"<li data-src-line=\"%lu\">%@</li>", (unsigned long)(i + 1), NPApplyInline(item)];
			i += 1;
			continue;
		}
		if (NPIsOL(line, &item)) {
			openList(@"ol");
			[html appendFormat:@"<li data-src-line=\"%lu\">%@</li>", (unsigned long)(i + 1), NPApplyInline(item)];
			i += 1;
			continue;
		}
		closeList();
		if ([trim hasPrefix:@"<"] && [trim hasSuffix:@">"] && trim.length > 2) {
			[html appendFormat:@"<div data-src-line=\"%lu\">%@</div>", (unsigned long)(i + 1), line];
			i += 1;
			continue;
		}
		NSUInteger pline = i;
		NSMutableArray *para = [NSMutableArray arrayWithObject:trim];
		i += 1;
		while (i < n) {
			NSString *nx = lines[i];
			NSString *nt = [nx stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
			NSString *dummy = nil;
			if (nt.length == 0 || [nt hasPrefix:@"#"] || [nt hasPrefix:@">"] || [nt hasPrefix:@"```"]
				|| NPIsUL(nx, &dummy) || NPIsOL(nx, &dummy) || [nt isEqualToString:@"---"])
				break;
			[para addObject:nt];
			i += 1;
		}
		[html appendFormat:@"<p data-src-line=\"%lu\">%@</p>", (unsigned long)(pline + 1), NPApplyInline([para componentsJoinedByString:@" "])];
	}
	closeList();
	if (fence) [html appendFormat:@"<pre data-src-line=\"%lu\"><code>%@</code></pre>", (unsigned long)(fenceLine + 1), NPEscapeHTML(code)];
	return html;
}

static NSString *NPHTMLBodyInner(NSString *src) {
	if (src.length == 0) return @"";
	NSString *low = src.lowercaseString;
	NSRange b = [low rangeOfString:@"<body"];
	if (b.location == NSNotFound) return src;
	NSRange gt = [src rangeOfString:@">" options:0 range:NSMakeRange(b.location, src.length - b.location)];
	if (gt.location == NSNotFound) return src;
	NSUInteger from = gt.location + 1;
	NSRange e = [low rangeOfString:@"</body>"];
	if (e.location == NSNotFound || e.location < from) return [src substringFromIndex:from];
	return [src substringWithRange:NSMakeRange(from, e.location - from)];
}

static NSString *NPHTMLKeptHead(NSString *src) {
	if (src.length == 0) return @"";
	NSString *low = src.lowercaseString;
	NSMutableString *out = [NSMutableString string];
	NSUInteger i = 0;
	while (i < low.length) {
		NSRange st = [low rangeOfString:@"<style" options:0 range:NSMakeRange(i, low.length - i)];
		if (st.location == NSNotFound) break;
		NSRange end = [low rangeOfString:@"</style>" options:0 range:NSMakeRange(st.location, low.length - st.location)];
		if (end.location == NSNotFound) break;
		[out appendString:[src substringWithRange:NSMakeRange(st.location, end.location + 8 - st.location)]];
		i = end.location + 8;
	}
	return out;
}

static NSString *NPWrapPreview(NSString *body, BOOL dark, NPPreviewKind kind, BOOL editable) {
	NSString *bg = dark ? @"#1e1e1e" : @"#ffffff";
	NSString *fg = dark ? @"#e6e6e6" : @"#222222";
	NSString *codebg = dark ? @"#2a2a2a" : @"#f4f4f4";
	NSString *link = dark ? @"#6cb6ff" : @"#0b57d0";
	NSString *syncJS =
		@"(function(){var s=document.getElementById('np4-scroller');if(s==null)return;"
		@"var kind=parseInt(document.body.getAttribute('data-np4-kind')||'0',10);"
		@"if(kind!=1){window.np4ScrollToLine=function(){};return;}"
		@"window._np4IgnoreScroll=false;"
		@"function nodeY(el){var sr=s.getBoundingClientRect();var er=el.getBoundingClientRect();return er.top-sr.top+s.scrollTop;}"
		@"function anchors(){var nodes=s.querySelectorAll('[data-src-line]');var out=[];"
		@"for(var i=0;i<nodes.length;i++){var line=parseInt(nodes[i].getAttribute('data-src-line'),10);if(line>0)out.push({line:line,y:nodeY(nodes[i])});}return out;}"
		@"window.np4ScrollToLine=function(line,lineCount){window._np4IgnoreScroll=true;"
		@"var max=s.scrollHeight-s.clientHeight;if(max<0)max=0;var a=anchors();var y=0;"
		@"if(a.length<1){var den=lineCount>1?(lineCount-1):1;y=max*((line-1)/den);}"
		@"else if(line<=a[0].line){y=a[0].y;}"
		@"else if(line>=a[a.length-1].line){y=a[a.length-1].y;}"
		@"else{var i=0;while(i+1<a.length&&a[i+1].line<=line)i++;var p=a[i],n=a[i+1];"
		@"var t=(n.line==p.line)?0:(line-p.line)/(n.line-p.line);y=p.y+(n.y-p.y)*t;}"
		@"if(y<0)y=0;if(y>max)y=max;s.scrollTop=y;"
		@"requestAnimationFrame(function(){window._np4IgnoreScroll=false;});};"
		@"s.addEventListener('scroll',function(){if(window._np4IgnoreScroll)return;"
		@"if(window._np4ScrollT)cancelAnimationFrame(window._np4ScrollT);"
		@"window._np4ScrollT=requestAnimationFrame(function(){"
		@"var max=s.scrollHeight-s.clientHeight;if(max<1)max=1;var frac=s.scrollTop/max;var a=anchors();var line=0;var top=s.scrollTop;"
		@"if(a.length>=1){if(top<=a[0].y)line=a[0].line;else if(top>=a[a.length-1].y)line=a[a.length-1].line;"
		@"else{var i=0;while(i+1<a.length&&a[i+1].y<=top)i++;var p=a[i],n=a[i+1];"
		@"var t=(n.y==p.y)?0:(top-p.y)/(n.y-p.y);line=Math.round(p.line+(n.line-p.line)*t);}}"
		@"if(window.webkit&&window.webkit.messageHandlers&&window.webkit.messageHandlers.np4preview)"
		@"window.webkit.messageHandlers.np4preview.postMessage({kind:'scroll',frac:frac,line:line});});},{passive:true});})();";
	NSString *editJS = @"";
	if (editable) {
		editJS =
			@"document.getElementById('np4-root').contentEditable='true';"
			@"document.getElementById('np4-root').spellcheck=false;"
			@"var _t=null;document.getElementById('np4-root').addEventListener('input',function(){"
			@"if(_t)clearTimeout(_t);_t=setTimeout(function(){"
			@"var r=document.getElementById('np4-root');"
			@"var html=r?r.innerHTML:'';"
			@"if(window.webkit&&window.webkit.messageHandlers&&window.webkit.messageHandlers.np4preview)"
			@"window.webkit.messageHandlers.np4preview.postMessage({html:html});"
			@"},180);});";
	}
	NSString *allJS = [syncJS stringByAppendingString:editJS];
	return [NSString stringWithFormat:
		@"<!doctype html><html><head><meta charset=\"utf-8\">"
		@"<style>html,body{height:100%%;margin:0;padding:0;overflow:hidden;overflow-anchor:none;background:%@;color:%@;}"
		@"#np4-scroller{height:100%%;overflow:auto;overflow-anchor:none;}"
		@"#np4-root{font:14px/1.55 -apple-system,BlinkMacSystemFont,sans-serif;padding:12px 16px;min-height:100%%;}"
		@"h1,h2,h3{line-height:1.25} pre{background:%@;padding:10px;overflow:auto;border-radius:6px;}"
		@"code{font-family:Menlo,monospace;font-size:12px} pre code{font-size:12px}"
		@"a{color:%@} img{max-width:100%%} table{border-collapse:collapse}"
		@"th,td{border:1px solid rgba(127,127,127,.45);padding:4px 8px}"
		@"blockquote{margin:0 0 0 8px;padding-left:10px;border-left:3px solid rgba(127,127,127,.5);color:inherit;opacity:.9}"
		@".np4-empty{opacity:.55;margin-top:36px;text-align:center}</style></head>"
		@"<body class=\"%@\" data-np4-kind=\"%ld\"><div id=\"np4-scroller\"><div id=\"np4-root\">%@</div></div><script>%@</script></body></html>",
		bg, fg, codebg, link, dark ? @"dark" : @"light", (long)kind, body, allJS];
}

static NSString *NPJSONString(NSString *s) {
	if (s == nil) s = @"";
	NSData *d = [NSJSONSerialization dataWithJSONObject:@[s] options:0 error:nil];
	if (d == nil) return @"\"\"";
	NSString *arr = [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
	if (arr.length < 2) return @"\"\"";
	return [arr substringWithRange:NSMakeRange(1, arr.length - 2)];
}

@interface PreviewPane () <WKScriptMessageHandler, WKNavigationDelegate>
@end

static BOOL NPIsImageExt(NSString *ext) {
	return [@[@"png", @"jpg", @"jpeg", @"gif", @"webp", @"bmp", @"tif", @"tiff",
		@"ico", @"icns", @"heic", @"heif", @"svg"] containsObject:ext.lowercaseString ?: @""];
}

static NSString *NPMimeForImageExt(NSString *ext) {
	ext = ext.lowercaseString ?: @"";
	if ([ext isEqualToString:@"jpg"] || [ext isEqualToString:@"jpeg"]) return @"image/jpeg";
	if ([ext isEqualToString:@"gif"]) return @"image/gif";
	if ([ext isEqualToString:@"webp"]) return @"image/webp";
	if ([ext isEqualToString:@"bmp"]) return @"image/bmp";
	if ([ext isEqualToString:@"svg"]) return @"image/svg+xml";
	if ([ext isEqualToString:@"tif"] || [ext isEqualToString:@"tiff"]) return @"image/tiff";
	if ([ext isEqualToString:@"ico"]) return @"image/x-icon";
	if ([ext isEqualToString:@"heic"] || [ext isEqualToString:@"heif"]) return @"image/heic";
	return @"image/png";
}

static NSString *NPDataURIForLocalImage(NSString *src, NSURL *baseDir) {
	if (src.length == 0 || baseDir == nil) return nil;
	NSString *t = [src stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	NSString *low = t.lowercaseString;
	if ([low hasPrefix:@"data:"] || [low hasPrefix:@"http://"] || [low hasPrefix:@"https://"]
		|| [low hasPrefix:@"mailto:"] || [low hasPrefix:@"javascript:"]) return nil;
	NSURL *u = nil;
	if ([low hasPrefix:@"file:"]) u = [NSURL URLWithString:t];
	else if ([t hasPrefix:@"/"]) u = [NSURL fileURLWithPath:t];
	else {
		NSString *rel = [t stringByRemovingPercentEncoding] ?: t;
		u = [[baseDir URLByAppendingPathComponent:rel] URLByStandardizingPath];
	}
	if (!u.isFileURL) return nil;
	NSString *path = u.path;
	if (!NPIsImageExt(path.pathExtension)) return nil;
	if (![[NSFileManager defaultManager] fileExistsAtPath:path]) return nil;
	NSData *d = [NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:nil];
	if (d.length == 0 || d.length > 8ull * 1024ull * 1024ull) return nil;
	return [NSString stringWithFormat:@"data:%@;base64,%@", NPMimeForImageExt(path.pathExtension),
		[d base64EncodedStringWithOptions:0]];
}

static NSString *NPEmbedLocalImages(NSString *html, NSURL *fileURL) {
	if (html.length == 0 || fileURL.path.length == 0) return html;
	NSURL *base = fileURL.URLByDeletingLastPathComponent;
	NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"\\bsrc=(['\"])([^'\"]+)\\1"
		options:0 error:nil];
	if (!re) return html;
	NSArray<NSTextCheckingResult *> *matches = [re matchesInString:html options:0 range:NSMakeRange(0, html.length)];
	if (matches.count == 0) return html;
	NSMutableString *out = [html mutableCopy];
	for (NSTextCheckingResult *m in [matches reverseObjectEnumerator]) {
		if (m.numberOfRanges < 3) continue;
		NSString *data = NPDataURIForLocalImage([html substringWithRange:[m rangeAtIndex:2]], base);
		if (!data) continue;
		NSString *q = [html substringWithRange:[m rangeAtIndex:1]];
		[out replaceCharactersInRange:m.range withString:[NSString stringWithFormat:@"src=%@%@%@", q, data, q]];
	}
	return out;
}

@implementation PreviewPane {
	WKWebView *_web;
	NSImageView *_imageView;
	NSTextField *_hint;
	NSString *_lastHTML;
	NSString *_lastPage;
	NSString *_lastSrc;
	NSString *_loadedPath;
	BOOL _headless;
	BOOL _pageReady;
	BOOL _lastRefreshInPlace;
	BOOL _lastRefreshDidScroll;
	BOOL _loadedDark;
	NPPreviewKind _loadedKind;
	NSInteger _loadGen;
	NSInteger _lastSyncLine;
	CGFloat _lastSyncFrac;
	NSInteger _pendingLine;
	NSInteger _pendingCount;
}

- (instancetype)initWithFrame:(NSRect)frame {
	self = [super initWithFrame:frame];
	if (self) {
		_headless = [[[NSProcessInfo processInfo] arguments] containsObject:@"--headless"]
			|| getenv("NP4_HEADLESS") != NULL;
		self.wantsLayer = YES;
		self.layer.backgroundColor = [NSColor textBackgroundColor].CGColor;
		_hint = [NSTextField labelWithString:@""];
		_hint.font = [NSFont systemFontOfSize:11];
		_hint.textColor = [NSColor secondaryLabelColor];
		_hint.translatesAutoresizingMaskIntoConstraints = NO;
		[self addSubview:_hint];
		[self.leadingAnchor constraintEqualToAnchor:_hint.leadingAnchor constant:-8].active = YES;
		[self.trailingAnchor constraintEqualToAnchor:_hint.trailingAnchor constant:8].active = YES;
		[self.topAnchor constraintEqualToAnchor:_hint.topAnchor constant:-4].active = YES;
		[_hint.heightAnchor constraintEqualToConstant:18].active = YES;
		[self setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
		[self setContentCompressionResistancePriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
	}
	return self;
}

- (void)pinPreviewView:(NSView *)v {
	v.translatesAutoresizingMaskIntoConstraints = NO;
	[v setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
	[v setContentCompressionResistancePriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
	[v setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationVertical];
	[v setContentCompressionResistancePriority:1 forOrientation:NSLayoutConstraintOrientationVertical];
	[self addSubview:v];
	[self.leadingAnchor constraintEqualToAnchor:v.leadingAnchor].active = YES;
	[self.trailingAnchor constraintEqualToAnchor:v.trailingAnchor].active = YES;
	[_hint.bottomAnchor constraintEqualToAnchor:v.topAnchor constant:-2].active = YES;
	[self.bottomAnchor constraintEqualToAnchor:v.bottomAnchor].active = YES;
}

- (void)ensureWeb {
	if (_headless || _web) return;
	WKWebViewConfiguration *cfg = [[WKWebViewConfiguration alloc] init];
	cfg.websiteDataStore = [WKWebsiteDataStore nonPersistentDataStore];
	[cfg.userContentController addScriptMessageHandler:self name:@"np4preview"];
	@try { [cfg.preferences setValue:@YES forKey:@"allowFileAccessFromFileURLs"]; } @catch (id e) {}
	_web = [[WKWebView alloc] initWithFrame:NSZeroRect configuration:cfg];
	_web.navigationDelegate = self;
	[self pinPreviewView:_web];
}

- (void)ensureImageView {
	if (_headless || _imageView) return;
	_imageView = [[NSImageView alloc] initWithFrame:NSZeroRect];
	_imageView.imageScaling = NSImageScaleProportionallyUpOrDown;
	_imageView.imageAlignment = NSImageAlignCenter;
	_imageView.wantsLayer = YES;
	[self pinPreviewView:_imageView];
}

- (void)shutdown {
	if (_web) {
		[_web.configuration.userContentController removeScriptMessageHandlerForName:@"np4preview"];
		[_web removeFromSuperview];
		_web = nil;
	}
	if (_imageView) {
		[_imageView removeFromSuperview];
		_imageView = nil;
	}
	self.onHTMLEdited = nil;
}

- (NSString *)lastHTML { return _lastHTML ?: @""; }
- (NSString *)lastPageHTML { return _lastPage ?: @""; }
- (BOOL)lastRefreshInPlace { return _lastRefreshInPlace; }
- (BOOL)lastRefreshDidScroll { return _lastRefreshDidScroll; }
- (BOOL)previewUsesLineMap {
	return _loadedKind == NPPreviewMarkdown && [_lastHTML containsString:@"data-src-line"];
}
- (NSInteger)lastSyncLine { return _lastSyncLine; }
- (CGFloat)lastSyncFrac { return _lastSyncFrac; }
- (void)applyPendingPreviewScroll {
	if (_headless || _web == nil || _pageReady == NO) return;
	if (_pendingCount <= 0) return;
	NSInteger line1 = _pendingLine + 1;
	NSString *js = [NSString stringWithFormat:@"if(window.np4ScrollToLine)np4ScrollToLine(%ld,%ld);",
		(long)line1, (long)_pendingCount];
	[_web evaluateJavaScript:js completionHandler:nil];
}
- (void)scrollPreviewToSourceLine:(NSInteger)line lineCount:(NSInteger)lineCount {
	if (_loadedKind != NPPreviewMarkdown) return;
	if (line < 0) line = 0;
	if (lineCount < 1) lineCount = 1;
	_lastSyncLine = line;
	_lastSyncFrac = (lineCount > 1) ? ((CGFloat)line / (CGFloat)(lineCount - 1)) : 0;
	_pendingLine = line;
	_pendingCount = lineCount;
	if (_headless) return;
	[self applyPendingPreviewScroll];
}

+ (NPPreviewKind)kindForDocument:(EditorDocument *)doc {
	if (!doc) return NPPreviewNone;
	NSString *ext = doc.fileURL.pathExtension.lowercaseString ?: @"";
	if ([@[@"md", @"markdown", @"mdown", @"mkd", @"mkdn", @"txt", @"text", @"plain"] containsObject:ext]) return NPPreviewMarkdown;
	if ([@[@"html", @"htm", @"xhtml"] containsObject:ext]) return NPPreviewHTML;
	if (NPIsImageExt(ext)) return NPPreviewImage;
	NSString *name = (doc.currentLexerName ?: @"").lowercaseString;
	if ([name containsString:@"markdown"]) return NPPreviewMarkdown;
	if ([name containsString:@"html"]) return NPPreviewHTML;
	return NPPreviewNone;
}

+ (NSString *)htmlFromMarkdown:(NSString *)markdown {
	return NPMarkdownToHTML(markdown ?: @"");
}

+ (NSString *)htmlForDocument:(EditorDocument *)doc {
	if (!doc) return @"";
	NSString *src = [doc.editor string] ?: @"";
	NPPreviewKind kind = [self kindForDocument:doc];
	if (kind == NPPreviewMarkdown) {
		NSString *h = [self htmlFromMarkdown:src];
		if (doc.fileURL) h = NPEmbedLocalImages(h, doc.fileURL);
		return h;
	}
	if (kind == NPPreviewHTML) return src;
	if (kind == NPPreviewImage) {
		NSString *path = doc.fileURL.path ?: @"";
		return [NSString stringWithFormat:@"<img alt=\"\" src=\"%@\">", NPEscapeHTML(path)];
	}
	return @"";
}

- (void)refreshDocument:(EditorDocument *)doc dark:(BOOL)dark {
	NPPreviewKind kind = [PreviewPane kindForDocument:doc];
	NSString *src = (kind == NPPreviewImage) ? @"" : ([doc.editor string] ?: @"");
	NSString *path = doc.fileURL.path ?: @"(untitled)";
	if (kind == NPPreviewImage) {
		if (_loadedKind == NPPreviewImage && dark == _loadedDark && [_loadedPath isEqualToString:path]) {
			_lastRefreshDidScroll = NO;
			return;
		}
	} else if (_lastSrc != nil && [_lastSrc isEqualToString:src] && kind == _loadedKind && dark == _loadedDark
		&& [_loadedPath isEqualToString:path]) {
		_lastRefreshDidScroll = NO;
		return;
	}
	NSString *hint = NPL(@"Preview is for Markdown, HTML, text and images.");
	NSString *body = nil;
	BOOL editable = NO;
	NSImage *raster = nil;
	if (kind != NPPreviewImage && [doc.editor message:SCI_GETLENGTH] > (sptr_t)kNPPreviewMaxChars) {
		hint = NPL(@"File too large for preview.");
		body = [NSString stringWithFormat:@"<p class=\"np4-empty\">%@</p>", NPEscapeHTML(hint)];
		kind = NPPreviewNone;
	} else if (kind == NPPreviewMarkdown) {
		hint = NPL(@"Edit on the left. Preview updates as you type.");
		body = [PreviewPane htmlFromMarkdown:src];
		if (doc.fileURL) body = NPEmbedLocalImages(body, doc.fileURL);
		if (body.length == 0)
			body = [NSString stringWithFormat:@"<p class=\"np4-empty\">%@</p>", NPEscapeHTML(NPL(@"Empty document"))];
	} else if (kind == NPPreviewHTML) {
		hint = NPL(@"The preview is editable; changes write back to the source.");
		editable = YES;
		NSString *low = src.lowercaseString;
		if ([low containsString:@"<html"] || [low containsString:@"<!doctype"]) {
			NSString *kept = NPHTMLKeptHead(src);
			body = [kept stringByAppendingString:NPHTMLBodyInner(src)];
			if (body.length == 0)
				body = [NSString stringWithFormat:@"<p class=\"np4-empty\">%@</p>", NPEscapeHTML(NPL(@"Empty document"))];
		} else {
			body = src.length ? src : [NSString stringWithFormat:@"<p class=\"np4-empty\">%@</p>", NPEscapeHTML(NPL(@"Empty document"))];
		}
	} else if (kind == NPPreviewImage) {
		hint = NPL(@"Image preview");
		NSURL *url = doc.fileURL;
		raster = url ? [[NSImage alloc] initWithContentsOfURL:url] : nil;
		if (raster == nil || (raster.size.width <= 0 && raster.representations.count == 0)) {
			raster = nil;
			hint = NPL(@"Cannot preview this image.");
			body = [NSString stringWithFormat:@"<p class=\"np4-empty\">%@</p>", NPEscapeHTML(hint)];
		} else {
			body = [PreviewPane htmlForDocument:doc];
		}
	} else {
		body = [NSString stringWithFormat:@"<p class=\"np4-empty\">%@</p>", NPEscapeHTML(hint)];
	}
	_hint.stringValue = hint;
	NSString *page = NPWrapPreview(body ?: @"", dark, kind, editable);
	_lastHTML = [PreviewPane htmlForDocument:doc];
	_lastPage = page;
	_lastSrc = [src copy];
	const BOOL sameDoc = [_loadedPath isEqualToString:path];
	const BOOL sameShell = _pageReady && sameDoc && _loadedKind == kind && _loadedDark == dark
		&& kind != NPPreviewImage;
	_lastRefreshDidScroll = NO;
	if (_headless) {
		_lastRefreshInPlace = sameShell;
		_pageReady = YES;
		_loadedKind = kind;
		_loadedDark = dark;
		_loadedPath = [path copy];
		return;
	}
	_loadGen += 1;
	const NSInteger gen = _loadGen;
	if (kind == NPPreviewImage && raster) {
		[self ensureImageView];
		_imageView.image = raster;
		_imageView.hidden = NO;
		if (_web) _web.hidden = YES;
		_lastRefreshInPlace = sameDoc && _loadedKind == NPPreviewImage;
		_pageReady = YES;
		_loadedKind = kind;
		_loadedDark = dark;
		_loadedPath = [path copy];
		return;
	}
	if (_imageView) {
		_imageView.hidden = YES;
		_imageView.image = nil;
	}
	[self ensureWeb];
	_web.hidden = NO;
	NSURL *base = doc.fileURL.URLByDeletingLastPathComponent;
	if (sameShell) {
		_lastRefreshInPlace = YES;
		NSString *js = [NSString stringWithFormat:
			@"(function(){var r=document.getElementById('np4-root');if(!r)return '0';"
			@"r.innerHTML=%@;return '1';})()", NPJSONString(body)];
		__weak typeof(self) weakSelf = self;
		[_web evaluateJavaScript:js completionHandler:^(id res, NSError *err) {
			(void)err;
			PreviewPane *s = weakSelf;
			if (s == nil || gen != s->_loadGen) return;
			BOOL ok = [res isKindOfClass:[NSString class]] && [res isEqualToString:@"1"];
			if (ok == NO) {
				s->_lastRefreshInPlace = NO;
				[s->_web loadHTMLString:page baseURL:base];
			}
		}];
		return;
	}
	_lastRefreshInPlace = NO;
	_pageReady = NO;
	_loadedKind = kind;
	_loadedDark = dark;
	_loadedPath = [path copy];
	[_web loadHTMLString:page baseURL:base];
}

- (void)userContentController:(WKUserContentController *)c didReceiveScriptMessage:(WKScriptMessage *)message {
	(void)c;
	id body = message.body;
	if ([body isKindOfClass:[NSDictionary class]]) {
		if ([body[@"kind"] isEqualToString:@"scroll"] || body[@"frac"] != nil) {
			if (_loadedKind != NPPreviewMarkdown) return;
			NSInteger srcLine = [body[@"line"] integerValue];
			CGFloat frac = [body[@"frac"] doubleValue];
			if (srcLine > 0) _lastSyncLine = srcLine - 1;
			_lastSyncFrac = frac;
			if (self.onPreviewScroll) self.onPreviewScroll(srcLine, frac);
			return;
		}
		if (_headless) return;
		NSString *html = body[@"html"];
		if (html.length && self.onHTMLEdited) self.onHTMLEdited(html);
		return;
	}
	if (_headless) return;
	if ([body isKindOfClass:[NSString class]] && [(NSString *)body length] && self.onHTMLEdited)
		self.onHTMLEdited(body);
}

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
	(void)webView; (void)navigation;
	_pageReady = YES;
	[self applyPendingPreviewScroll];
}

- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)action
	decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
	(void)webView;
	if (action.navigationType == WKNavigationTypeLinkActivated) {
		decisionHandler(WKNavigationActionPolicyCancel);
		return;
	}
	decisionHandler(WKNavigationActionPolicyAllow);
}

@end
