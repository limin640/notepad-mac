cmake_minimum_required(VERSION 3.20)
project(Notepad4Mac OBJCXX CXX C)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_OBJCXX_STANDARD 20)

# ---------------------------------------------------------------------------
# Scintilla 内核 + 官方 Cocoa 后端（5.6.6，与 notepad4 fork 同版本零漂移）
# ---------------------------------------------------------------------------
set(SCI_ROOT "${CMAKE_SOURCE_DIR}/scintilla_upstream")

# 平台无关内核
file(GLOB SCI_CORE_SRCS "${SCI_ROOT}/src/*.cxx")

# Cocoa 平台层（官方 scintilla 5.6.6 cocoa/）
set(SCI_COCOA_SRCS
    "${SCI_ROOT}/cocoa/PlatCocoa.mm"
    "${SCI_ROOT}/cocoa/ScintillaCocoa.mm"
    "${SCI_ROOT}/cocoa/ScintillaView.mm"
    "${SCI_ROOT}/cocoa/PortMacOSBatch.mm"
)

set_source_files_properties(${SCI_COCOA_SRCS} PROPERTIES COMPILE_FLAGS "-fobjc-arc")

add_library(scintilla STATIC ${SCI_CORE_SRCS} ${SCI_COCOA_SRCS})


target_compile_definitions(scintilla PRIVATE
    USE_STD_ASYNC_FUTURE=1
    USE_WIN32_PTP_WORK=0
)
target_include_directories(scintilla PUBLIC
    "${SCI_ROOT}/include"
    "${SCI_ROOT}/src"
    "${SCI_ROOT}/cocoa"
    "${SCI_ROOT}/lexlib"
)

# 词法器（notepad4 fork 内置 lexers/ + lexlib 目录）
file(GLOB LEXER_SRCS "${SCI_ROOT}/lexers/*.cxx" "${SCI_ROOT}/lexlib/*.cxx")
target_sources(scintilla PRIVATE ${LEXER_SRCS})


# notepad4 词法器数据（词表+样式，纯数据模块）
file(GLOB LEXDEF_SRCS "${CMAKE_SOURCE_DIR}/lexers_def/stl*.cpp")
add_library(lexers_def STATIC ${LEXDEF_SRCS})
target_include_directories(lexers_def PUBLIC
    "${CMAKE_SOURCE_DIR}/lexers_def"
    "${SCI_ROOT}/include"
)
find_library(APPKIT_F AppKit REQUIRED)
find_library(QUARTZCORE_F QuartzCore REQUIRED)
find_library(CARBON_F Carbon REQUIRED)

target_link_libraries(scintilla PUBLIC
    ${APPKIT_F}
    ${QUARTZCORE_F}
    ${CARBON_F}
)

# ---------------------------------------------------------------------------
# 目标 1：Scintilla Cocoa 测试程序（验证内核+cocoa 后端编译链接通过）
add_executable(sci_test tests/sci_test.mm)
target_link_libraries(sci_test PRIVATE scintilla)

# ---------------------------------------------------------------------------
# 目标 2：Notepad4.app（AppKit 壳）
# ---------------------------------------------------------------------------
add_executable(Notepad4 MACOSX_BUNDLE
    macapp/main.mm
    macapp/MainWindowController.mm
    macapp/EditorDocument.mm
    macapp/LexerRegistry.mm
    macapp/FindReplacePanel.mm
    macapp/StatusBarView.mm
    macapp/NPTheme.mm
)
set_source_files_properties(
    macapp/main.mm macapp/MainWindowController.mm macapp/EditorDocument.mm
    macapp/LexerRegistry.mm macapp/FindReplacePanel.mm macapp/StatusBarView.mm
    macapp/NPTheme.mm
    PROPERTIES COMPILE_FLAGS "-fobjc-arc"
)
target_include_directories(Notepad4 PRIVATE
    "${CMAKE_SOURCE_DIR}/lexers_def"
    "${SCI_ROOT}/include"
    "${SCI_ROOT}/src"
    "${SCI_ROOT}/cocoa"
    "${SCI_ROOT}/lexlib"
    ${CMAKE_SOURCE_DIR}/macapp
)
target_link_libraries(Notepad4 PRIVATE scintilla lexers_def)
set_target_properties(Notepad4 PROPERTIES
    MACOSX_BUNDLE_BUNDLE_NAME "Notepad4"
    MACOSX_BUNDLE_GUI_IDENTIFIER "com.ethan.notepad4mac"
    MACOSX_BUNDLE_BUNDLE_VERSION "0.1.0"
    MACOSX_BUNDLE_SHORT_VERSION_STRING "0.1.0"
    MACOSX_BUNDLE_INFO_STRING "Notepad4 for macOS"
    MACOSX_BUNDLE_ICON_FILE "Notepad4.icns"
    MACOSX_BUNDLE_LONG_VERSION_STRING "0.1.0 (Notepad4-mac port)"
)
# 图标拷入 bundle
add_custom_command(TARGET Notepad4 POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
        "${CMAKE_SOURCE_DIR}/macapp/Resources/Notepad4.icns"
        "$<TARGET_BUNDLE_DIR:Notepad4>/Contents/Resources/Notepad4.icns"
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
        "${CMAKE_SOURCE_DIR}/macapp/Resources/Notepad4 DarkTheme.ini"
        "$<TARGET_BUNDLE_DIR:Notepad4>/Contents/Resources/Notepad4 DarkTheme.ini"
    COMMAND /usr/bin/rsync -a "${CMAKE_SOURCE_DIR}/macapp/ToolbarIcons/"
        "$<TARGET_BUNDLE_DIR:Notepad4>/Contents/Resources/"
    COMMAND touch "$<TARGET_BUNDLE_DIR:Notepad4>"
    COMMENT "Copying app icon, toolbar icons, dark theme")
