# The example application. main.cpp is the same on every platform; the desktop functions it needs come from the host for the platform.
if(WIN32)
    set(WEBVIEW_WINDOW_EXAMPLE_HOST Host.windows.cpp)
elseif(APPLE)
    set(WEBVIEW_WINDOW_EXAMPLE_HOST Host.macos.mm)
else()
    set(WEBVIEW_WINDOW_EXAMPLE_HOST Host.linux.cpp)
endif()

add_executable(webview_window_example main.cpp ${WEBVIEW_WINDOW_EXAMPLE_HOST})
target_link_libraries(webview_window_example PRIVATE webview_window)

if(WIN32)
    target_link_options(webview_window_example PRIVATE -static -mwindows)
    # WebView2 is loaded at runtime from WebView2Loader.dll, which must sit beside the executable.
    add_custom_command(TARGET webview_window_example POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy_if_different
                "${PROJECT_SOURCE_DIR}/third_party/webview2/bin/x64/WebView2Loader.dll" "$<TARGET_FILE_DIR:webview_window_example>"
        VERBATIM)
endif()
