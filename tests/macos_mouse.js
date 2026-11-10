// Posts a mouse event at a point on the screen, in points with the top left at the origin, as the pointer would.
// Usage: osascript -l JavaScript macos_mouse.js <move|down|drag|up|rightdown|rightup> <x> <y>
//   move: the pointer moves. down / up: the primary button is pressed or released. drag: the pointer moves with the button held.
//   rightdown / rightup: the secondary button is pressed or released.
ObjC.import('CoreGraphics');

function run(argv) {
  const kinds = {
    move: [$.kCGEventMouseMoved, $.kCGMouseButtonLeft],
    down: [$.kCGEventLeftMouseDown, $.kCGMouseButtonLeft],
    drag: [$.kCGEventLeftMouseDragged, $.kCGMouseButtonLeft],
    up: [$.kCGEventLeftMouseUp, $.kCGMouseButtonLeft],
    rightdown: [$.kCGEventRightMouseDown, $.kCGMouseButtonRight],
    rightup: [$.kCGEventRightMouseUp, $.kCGMouseButtonRight],
  };
  const kind = argv[0];
  if (!(kind in kinds)) {
    return 'usage: macos_mouse.js move|down|drag|up <x> <y>';
  }
  const point = $.CGPointMake(parseFloat(argv[1]), parseFloat(argv[2]));
  const [type, button] = kinds[kind];
  const event = $.CGEventCreateMouseEvent(null, type, point, button);
  $.CGEventPost($.kCGHIDEventTap, event);
  return kind;
}
