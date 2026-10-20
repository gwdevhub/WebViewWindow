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
    target_link_libraries(webview_window PUBLIC user32 gdi32 ole32 shell32 advapi32 uuid d3d11 dxgi dcomp)
else()
    find_package(Threads REQUIRED)
    target_sources(webview_window PRIVATE platform/linux/WebViewWindow.cpp)
    # GTK and WebKitGTK are opened at runtime, so only their headers are needed to build.
    target_include_directories(webview_window PRIVATE third_party/gtk/include)
    target_link_libraries(webview_window PUBLIC ${CMAKE_DL_LIBS} Threads::Threads)
endif()

# The example shows the smallest host: it defines the desktop functions and opens one window.
option(WEBVIEW_WINDOW_BUILD_EXAMPLE "Build the example application" ON)
if(WEBVIEW_WINDOW_BUILD_EXAMPLE)
    add_executable(webview_window_example example/main.cpp example/Host.cpp)
    target_link_libraries(webview_window_example PRIVATE webview_window)
    if(WIN32)
        target_link_options(webview_window_example PRIVATE -static -mwindows)
        # WebView2 is loaded at runtime from WebView2Loader.dll, which must sit beside the executable.
        add_custom_command(TARGET webview_window_example POST_BUILD
            COMMAND ${CMAKE_COMMAND} -E copy_if_different
                    "${CMAKE_CURRENT_SOURCE_DIR}/third_party/webview2/bin/x64/WebView2Loader.dll" "$<TARGET_FILE_DIR:webview_window_example>"
            VERBATIM)
    endif()
endif()
