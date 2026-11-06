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

# The example application, built on Windows and Linux. examples/ has the shared main and a host for each platform.
option(WEBVIEW_WINDOW_BUILD_EXAMPLE "Build the example application" ON)
if(WEBVIEW_WINDOW_BUILD_EXAMPLE)
    add_subdirectory(examples)
endif()
