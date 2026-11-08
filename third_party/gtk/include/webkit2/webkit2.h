// The WebKitGTK types the launcher uses. Matches the upstream WebKitGTK 4.1 headers' ABI. See ../README.md.
#pragma once

#include "../gtk/gtk.h"

typedef struct _WebKitWebView WebKitWebView;
typedef struct _WebKitWebContext WebKitWebContext;
typedef struct _WebKitUserContentManager WebKitUserContentManager;
typedef struct _WebKitUserMessage WebKitUserMessage;
typedef struct _WebKitSettings WebKitSettings;
typedef struct _WebKitWebInspector WebKitWebInspector;
// The requests a permission-request signal carries. The launcher only passes them on to the functions that answer them.
typedef struct _WebKitPermissionRequest WebKitPermissionRequest;
typedef struct _WebKitUserMediaPermissionRequest WebKitUserMediaPermissionRequest;
typedef struct _WebKitNotificationPermissionRequest WebKitNotificationPermissionRequest;

// The JavaScriptCore value a script message carries, from the JavaScriptCore part of WebKitGTK.
typedef struct _JSCValue JSCValue;

// The load progress a load-changed signal reports.
typedef enum {
    WEBKIT_LOAD_STARTED,
    WEBKIT_LOAD_REDIRECTED,
    WEBKIT_LOAD_COMMITTED,
    WEBKIT_LOAD_FINISHED
} WebKitLoadEvent;

// The hardware acceleration policy a settings object takes.
typedef enum {
    WEBKIT_HARDWARE_ACCELERATION_POLICY_ON_DEMAND,
    WEBKIT_HARDWARE_ACCELERATION_POLICY_ALWAYS,
    WEBKIT_HARDWARE_ACCELERATION_POLICY_NEVER
} WebKitHardwareAccelerationPolicy;
