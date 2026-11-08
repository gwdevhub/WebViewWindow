cmake_minimum_required(VERSION 3.20)
project(WebViewWindow CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

# A frameless window with a WebView2 (Windows) or WebKitGTK (Linux) page. The host application defines the desktop functions
# declared in include/WebViewWindow.h: showError, cursorPosition, workArea and workAreaAt.
add_library(webview_window STATIC src/WebViewWindow.cpp src/Messages.cpp)
target_include_directories(webview_window PUBLIC include third_party/nlohmann/include)
target_compile_options(webview_window PRIVATE -Wall -Wextra)

if(WIN32)
    target_sources(webview_window PRIVATE
        platform/windows/Composition.cpp
        platform/windows/WebView2.cpp
        platform/windows/WebViewWindow.cpp)
    target_include_directories(webview_window PRIVATE third_party/webview2/include platform/windows/compat)
    # The Windows code uses Windows 10 calls (GetDpiForWindow, WS_EX_NOREDIRECTIONBITMAP), so the API level is set here rather than left
    # to each toolchain's default, which older MinGW builds keep at Windows 7 or 8.
    target_compile_definitions(webview_window PRIVATE _WIN32_WINNT=0x0A00 WINVER=0x0A00)
    target_link_libraries(webview_window PUBLIC user32 gdi32 ole32 shell32 advapi32 uuid d3d11 dxgi dcomp)

    # WebView2Loader.dll is written beside the executable at start, from resource 2 of the program. A program calls this with its
    # target to embed the loader there, so its release can be the executable alone.
    set(WEBVIEW_WINDOW_LOADER_DLL "${CMAKE_CURRENT_SOURCE_DIR}/third_party/webview2/bin/x64/WebView2Loader.dll" CACHE INTERNAL "")
    function(webview_window_embed_loader target)
        enable_language(RC)
        set(rc "${CMAKE_CURRENT_BINARY_DIR}/${target}_webview2_loader.rc")
        file(WRITE "${rc}" "2 RCDATA \"${WEBVIEW_WINDOW_LOADER_DLL}\"\n")
        set_source_files_properties("${rc}" PROPERTIES OBJECT_DEPENDS "${WEBVIEW_WINDOW_LOADER_DLL}")
        target_sources(${target} PRIVATE "${rc}")
    endfunction()
elseif(APPLE)
    # The macOS window is Objective-C++, so the project needs that language, and it links AppKit and WebKit.
    enable_language(OBJCXX)
    find_package(Threads REQUIRED)
    target_sources(webview_window PRIVATE platform/macos/WebViewWindow.mm)
    target_link_libraries(webview_window PUBLIC "-framework AppKit" "-framework WebKit" Threads::Threads)
else()
    find_package(Threads REQUIRED)
    target_sources(webview_window PRIVATE platform/linux/WebViewWindow.cpp)
    # GTK and WebKitGTK are opened at runtime, so only their headers are needed to build.
    target_include_directories(webview_window PRIVATE third_party/gtk/include)
    target_link_libraries(webview_window PUBLIC ${CMAKE_DL_LIBS} Threads::Threads)
endif()

# The example application, built on Windows and Linux. examples/ has the shared main and a host for each platform.
option(WEBVIEW_WINDOW_BUILD_EXAMPLE "Build the example application" ON)
if(WEBVIEW_WINDOW_BUILD_EXAMPLE)
    add_subdirectory(examples)
endif()
