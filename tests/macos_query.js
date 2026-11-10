// Reads the window and display state the macOS tests check against, from the system's own records rather than the example's report.
// Usage: osascript -l JavaScript macos_query.js windows <pid>   the example's on-screen windows, as [{"bounds":[x,y,width,height]}]
//        osascript -l JavaScript macos_query.js all <pid>       every window the example owns, on screen or not, as
//                                                              [{"bounds":[x,y,width,height],"onscreen":true,"layer":0}]
//        osascript -l JavaScript macos_query.js scale           the main display's backing scale (1 or 2)
// Windows come from CoreGraphics' window list, which needs no permission. Bounds are in points, with the top left at the origin.
ObjC.import('CoreGraphics');
ObjC.import('AppKit');

function run(argv) {
  if (argv[0] === 'scale') {
    return String($.NSScreen.mainScreen.backingScaleFactor);
  }
  if (argv[0] === 'all') {
    const pid = parseInt(argv[1], 10);
    const list = ObjC.deepUnwrap(ObjC.castRefToObject($.CGWindowListCopyWindowInfo($.kCGWindowListOptionAll, $.kCGNullWindowID)));
    const every = [];
    for (const window of list) {
      if (window.kCGWindowOwnerPID !== pid) continue;
      const b = window.kCGWindowBounds;
      every.push({bounds: [b.X, b.Y, b.Width, b.Height], onscreen: !!window.kCGWindowIsOnscreen, layer: window.kCGWindowLayer});
    }
    return JSON.stringify(every);
  }
  if (argv[0] === 'windows') {
    const pid = parseInt(argv[1], 10);
    const list = ObjC.deepUnwrap(ObjC.castRefToObject($.CGWindowListCopyWindowInfo($.kCGWindowListOptionAll, $.kCGNullWindowID)));
    const shown = [];
    for (const window of list) {
      if (window.kCGWindowOwnerPID !== pid || !window.kCGWindowIsOnscreen || window.kCGWindowLayer !== 0) continue;
      const b = window.kCGWindowBounds;
      if (b.Width <= 0 || b.Height <= 0) continue;
      shown.push({bounds: [b.X, b.Y, b.Width, b.Height]});
    }
    return JSON.stringify(shown);
  }
  return 'usage: macos_query.js windows <pid> | scale';
}
