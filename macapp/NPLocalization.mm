#import "NPLocalization.h"

static NSString *const NPLanguageKey = @"NPLanguage";
static BOOL sLangOverride = NO;
static NSString *sLangOverrideCode = nil;
static NSDictionary<NSString *, NSString *> *sTable;
static NSString *sTableCode;

static NSArray<NSDictionary<NSString *, NSString *> *> *NPCatalog(void) {
	static NSArray *c;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		c = @[
			@{@"code": @"en", @"name": @"English", @"match": @"en"},
			@{@"code": @"zh-Hans", @"name": @"简体中文", @"match": @"zh-hans,zh-cn,zh-sg,zh"},
			@{@"code": @"zh-Hant", @"name": @"繁體中文", @"match": @"zh-hant,zh-tw,zh-hk,zh-mo"},
			@{@"code": @"ja", @"name": @"日本語", @"match": @"ja"},
			@{@"code": @"ko", @"name": @"한국어", @"match": @"ko"},
			@{@"code": @"de", @"name": @"Deutsch", @"match": @"de"},
			@{@"code": @"fr", @"name": @"Français", @"match": @"fr"},
			@{@"code": @"es", @"name": @"Español", @"match": @"es"},
			@{@"code": @"it", @"name": @"Italiano", @"match": @"it"},
			@{@"code": @"pt-BR", @"name": @"Português (Brasil)", @"match": @"pt-br,pt"},
			@{@"code": @"ru", @"name": @"Русский", @"match": @"ru"},
		];
	});
	return c;
}

NSArray<NSDictionary<NSString *, NSString *> *> *NPLanguageCatalog(void) {
	return NPCatalog();
}

static BOOL NPCodeKnown(NSString *code) {
	for (NSDictionary *e in NPCatalog()) {
		if ([e[@"code"] isEqualToString:code]) return YES;
	}
	return NO;
}

static NSString *NPNormalizeCode(NSString *raw) {
	if (raw.length == 0) return @"en";
	NSString *s = raw.lowercaseString;
	if ([s isEqualToString:@"system"]) return @"system";
	if ([s isEqualToString:@"zh"] || [s isEqualToString:@"cn"] || [s isEqualToString:@"zh-cn"]
		|| [s isEqualToString:@"zh-hans"] || [s isEqualToString:@"hans"]) return @"zh-Hans";
	if ([s isEqualToString:@"zh-tw"] || [s isEqualToString:@"zh-hk"] || [s isEqualToString:@"zh-hant"]
		|| [s isEqualToString:@"hant"] || [s isEqualToString:@"tw"]) return @"zh-Hant";
	if ([s isEqualToString:@"pt"] || [s isEqualToString:@"pt-br"] || [s isEqualToString:@"pt_br"]) return @"pt-BR";
	if ([s isEqualToString:@"jp"]) return @"ja";
	if ([s isEqualToString:@"kr"]) return @"ko";
	for (NSDictionary *e in NPCatalog()) {
		NSString *code = e[@"code"];
		if ([code.lowercaseString isEqualToString:s]) return code;
	}
	return raw;
}

static NSString *NPLanguageFromSystem(void) {
	for (NSString *pref in [NSLocale preferredLanguages]) {
		NSString *id_ = pref.lowercaseString;
		if ([id_ hasPrefix:@"zh-hant"] || [id_ hasPrefix:@"zh-tw"] || [id_ hasPrefix:@"zh-hk"]
			|| [id_ hasPrefix:@"zh-mo"]) return @"zh-Hant";
		if ([id_ hasPrefix:@"zh"]) return @"zh-Hans";
		for (NSDictionary *e in NPCatalog()) {
			NSArray *parts = [e[@"match"] componentsSeparatedByString:@","];
			for (NSString *p in parts) {
				if ([id_ hasPrefix:p]) return e[@"code"];
			}
		}
	}
	return @"en";
}

static NSDictionary<NSString *, NSString *> *NPLoadTable(NSString *code) {
	if ([code isEqualToString:@"en"]) return @{};
	NSString *path = [[NSBundle mainBundle] pathForResource:code ofType:@"json" inDirectory:@"locale"];
	if (!path) {
		NSString *res = [[NSBundle mainBundle] resourcePath];
		path = [res stringByAppendingPathComponent:[NSString stringWithFormat:@"locale/%@.json", code]];
	}
	if (![[NSFileManager defaultManager] fileExistsAtPath:path]) return @{};
	NSData *data = [NSData dataWithContentsOfFile:path];
	if (!data) return @{};
	id obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
	return [obj isKindOfClass:[NSDictionary class]] ? obj : @{};
}

static void NPEnsureTable(NSString *code) {
	if (sTable && [sTableCode isEqualToString:code]) return;
	sTable = NPLoadTable(code);
	sTableCode = [code copy];
}

static NSString *NPResolvedCode(void) {
	NSString *pref = NPLanguagePreferenceCode();
	if ([pref isEqualToString:@"system"]) return NPLanguageFromSystem();
	return pref;
}

NSString *NPLanguagePreferenceCode(void) {
	if (sLangOverride) return sLangOverrideCode ?: @"en";
	NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
	id v = [d objectForKey:NPLanguageKey];
	if (v == nil) return @"system";
	if ([v isKindOfClass:[NSString class]]) {
		NSString *n = NPNormalizeCode(v);
		if ([n isEqualToString:@"system"] || NPCodeKnown(n)) return n;
		return @"system";
	}
	if ([v isKindOfClass:[NSNumber class]]) {
		NSInteger i = [v integerValue];
		if (i == NPLanguageEnglish) return @"en";
		if (i == NPLanguageSystem) return @"system";
		return @"zh-Hans";
	}
	return @"system";
}

NSString *NPLanguageCodeGet(void) {
	return NPResolvedCode();
}

BOOL NPLanguageIsCJK(void) {
	NSString *c = NPLanguageCodeGet();
	return [c hasPrefix:@"zh"] || [c isEqualToString:@"ja"] || [c isEqualToString:@"ko"];
}

void NPLanguageSetCode(NSString *code) {
	NSString *n = NPNormalizeCode(code);
	if (sLangOverride) {
		sLangOverrideCode = [n copy];
		sTable = nil;
		sTableCode = nil;
		return;
	}
	NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
	if ([n isEqualToString:@"system"]) [d removeObjectForKey:NPLanguageKey];
	else [d setObject:n forKey:NPLanguageKey];
	sTable = nil;
	sTableCode = nil;
}

NPLanguage NPLanguagePreference(void) {
	NSString *p = NPLanguagePreferenceCode();
	if ([p isEqualToString:@"system"]) return NPLanguageSystem;
	if ([p isEqualToString:@"en"]) return NPLanguageEnglish;
	if ([p isEqualToString:@"zh-Hans"]) return NPLanguageChinese;
	return NPLanguageEnglish;
}

NPLanguage NPLanguageGet(void) {
	NSString *c = NPLanguageCodeGet();
	if ([c isEqualToString:@"zh-Hans"]) return NPLanguageChinese;
	if ([c isEqualToString:@"en"]) return NPLanguageEnglish;
	return NPLanguageEnglish;
}

void NPLanguageSet(NPLanguage lang) {
	if (lang == NPLanguageSystem) NPLanguageSetCode(@"system");
	else if (lang == NPLanguageEnglish) NPLanguageSetCode(@"en");
	else NPLanguageSetCode(@"zh-Hans");
}

void NPLanguageOverrideForTesting(NPLanguage lang) {
	if (lang == NPLanguageSystem) NPLanguageOverrideCodeForTesting(@"system");
	else if (lang == NPLanguageEnglish) NPLanguageOverrideCodeForTesting(@"en");
	else NPLanguageOverrideCodeForTesting(@"zh-Hans");
}

void NPLanguageOverrideCodeForTesting(NSString *code) {
	sLangOverride = YES;
	sLangOverrideCode = [NPNormalizeCode(code) copy];
	sTable = nil;
	sTableCode = nil;
}

NSString *NPL(NSString *english) {
	if (english.length == 0) return english ?: @"";
	NSString *code = NPLanguageCodeGet();
	if ([code isEqualToString:@"en"]) return english;
	NPEnsureTable(code);
	NSString *hit = sTable[english];
	if (hit.length) return hit;
	const NSRange tab = [english rangeOfString:@"\t"];
	if (tab.location != NSNotFound) {
		NSString *base = [english substringToIndex:tab.location];
		NSString *suffix = [english substringFromIndex:tab.location];
		NSString *tr = sTable[base];
		if (tr.length) return [tr stringByAppendingString:suffix];
	}
	return english;
}
