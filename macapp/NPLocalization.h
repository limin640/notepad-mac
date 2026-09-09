// 界面语言：中文 / English，存 NSUserDefaults，默认中文
// 用法：菜单/状态栏/对话框里的英文原文作为键，NPL() 返回当前语言的文本
#pragma once
#import <Cocoa/Cocoa.h>

typedef NS_ENUM(NSInteger, NPLanguage) {
	NPLanguageChinese = 0,   // 默认
	NPLanguageEnglish = 1,
};

NPLanguage NPLanguageGet(void);
void NPLanguageSet(NPLanguage lang);
// 英文原文 → 当前语言；无译文时原样返回
NSString *NPL(NSString *english);
// 测试用：进程内覆盖，不写盘
void NPLanguageOverrideForTesting(NPLanguage lang);
