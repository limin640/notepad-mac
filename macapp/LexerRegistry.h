// 词法器注册表：桥接 notepad4 的 EDITLEXER 数据（lexers_def/）到 ScintillaView
// 词表 -> SCI_SETKEYWORDS；样式 -> SCI_STYLESETFORE/BACK/BOLD/ITALIC
#pragma once

#import <Cocoa/Cocoa.h>
#import "ScintillaView.h"

struct EDITLEXER;

@interface LexerRegistry : NSObject

// 按扩展名找 EDITLEXER（无匹配返回 nil）；ext 不含点，大小写不敏感
+ (nullable const EDITLEXER *)lexerForExtension:(NSString *)ext;

// 对 editor 应用 EDITLEXER：设词法器、注词表、应用默认样式
+ (void)applyLexer:(const EDITLEXER *)lex toEditor:(ScintillaView *)editor;
+ (void)applyLexer:(const EDITLEXER *)lex toEditor:(ScintillaView *)editor darkMode:(BOOL)dark;

// 生成扩展名 -> 词法器 调试清单
+ (NSArray<NSDictionary *> *)allLexersInfo;
+ (NSString *)displayNameForLexer:(nullable const EDITLEXER *)lex;
+ (NSArray<NSDictionary *> *)styleDescriptorsForLexer:(nullable const EDITLEXER *)lex;
+ (void)setUserStyleValue:(NSString *)val forLexerName:(NSString *)name styleName:(NSString *)styleName;
+ (void)clearUserOverridesForLexerName:(NSString *)name;
+ (nullable NSString *)userStyleValueForLexerName:(NSString *)name styleName:(NSString *)styleName;

@end
