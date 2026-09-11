// 界面语言：跟随系统或指定语种。英文原文作为键，NPL() 返回当前语言文本。
#pragma once
#import <Cocoa/Cocoa.h>

typedef NS_ENUM(NSInteger, NPLanguage) {
	NPLanguageChinese = 0,   // zh-Hans（兼容旧测试）
	NPLanguageEnglish = 1,
	NPLanguageSystem = 2,
};

NSString *NPLanguageCodeGet(void);
NSString *NPLanguagePreferenceCode(void);
NSArray<NSDictionary<NSString *, NSString *> *> *NPLanguageCatalog(void);
BOOL NPLanguageIsCJK(void);
void NPLanguageSetCode(NSString *code);

NPLanguage NPLanguageGet(void);
NPLanguage NPLanguagePreference(void);
void NPLanguageSet(NPLanguage lang);
NSString *NPL(NSString *english);
void NPLanguageOverrideForTesting(NPLanguage lang);
void NPLanguageOverrideCodeForTesting(NSString *code);
