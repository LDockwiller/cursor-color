import QtQuick
import QtQuick.Shapes

// HSV color disk: hue goes around the circle, saturation from the center
// (white) to the edge (pure hue), and `value` darkens the whole disk.
// Built from two GPU gradients so it stays sharp at any scale:
//   conical hue gradient  +  radial white -> transparent  +  black at 1 - value
// which is exactly color = value * (white * (1 - s) + hue * s).
//
// Hovering previews (`hovered`), pressing/dragging moves the selection
// (`moved`), releasing commits it (`committed`).
Item {
  id: root

  property real hue: 0
  property real saturation: 0
  property real value: 1
  property color borderColor: "#888888"

  readonly property real radius: Math.min(width, height) / 2
  readonly property color selectedColor: Qt.hsva(root.hue, root.saturation, root.value, 1)

  signal hovered(color c)
  signal hoverEnded()
  signal moved()
  signal committed()

  // Screen-space angle, counter-clockwise from 3 o'clock, as the conical
  // gradient draws it.
  function hsAt(x, y) {
    var dx = x - width / 2
    var dy = height / 2 - y
    var dist = Math.min(1, Math.sqrt(dx * dx + dy * dy) / root.radius)
    var angle = Math.atan2(dy, dx) / (2 * Math.PI)
    if (angle < 0) angle += 1
    return { h: angle, s: dist }
  }

  function pick(x, y) {
    var hs = hsAt(x, y)
    root.hue = hs.h
    root.saturation = hs.s
    root.moved()
  }

  Shape {
    anchors.fill: parent
    preferredRendererType: Shape.CurveRenderer

    ShapePath {
      strokeWidth: 0
      strokeColor: "transparent"
      fillGradient: ConicalGradient {
        centerX: root.width / 2
        centerY: root.height / 2
        angle: 0
        GradientStop { position: 0 / 6; color: "#ff0000" }
        GradientStop { position: 1 / 6; color: "#ffff00" }
        GradientStop { position: 2 / 6; color: "#00ff00" }
        GradientStop { position: 3 / 6; color: "#00ffff" }
        GradientStop { position: 4 / 6; color: "#0000ff" }
        GradientStop { position: 5 / 6; color: "#ff00ff" }
        GradientStop { position: 6 / 6; color: "#ff0000" }
      }
      PathAngleArc {
        centerX: root.width / 2; centerY: root.height / 2
        radiusX: root.radius; radiusY: root.radius
        startAngle: 0; sweepAngle: 360
      }
    }

    ShapePath {
      strokeWidth: 0
      strokeColor: "transparent"
      fillGradient: RadialGradient {
        centerX: root.width / 2; centerY: root.height / 2; centerRadius: root.radius
        focalX: centerX; focalY: centerY
        GradientStop { position: 0; color: "#ffffffff" }
        GradientStop { position: 1; color: "#00ffffff" }
      }
      PathAngleArc {
        centerX: root.width / 2; centerY: root.height / 2
        radiusX: root.radius; radiusY: root.radius
        startAngle: 0; sweepAngle: 360
      }
    }

    ShapePath {
      strokeWidth: 1
      strokeColor: root.borderColor
      fillColor: Qt.rgba(0, 0, 0, 1 - root.value)
      PathAngleArc {
        centerX: root.width / 2; centerY: root.height / 2
        radiusX: root.radius - 0.5; radiusY: root.radius - 0.5
        startAngle: 0; sweepAngle: 360
      }
    }
  }

  // Selection marker.
  Rectangle {
    readonly property real angle: root.hue * 2 * Math.PI
    readonly property real dist: root.saturation * root.radius
    width: 14
    height: 14
    radius: 7
    x: root.width / 2 + Math.cos(angle) * dist - width / 2
    y: root.height / 2 - Math.sin(angle) * dist - height / 2
    color: root.selectedColor
    border.width: 2
    border.color: root.value > 0.55 ? "#000000" : "#ffffff"
  }

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.CrossCursor
    preventStealing: true

    function inside(mouse) {
      var dx = mouse.x - root.width / 2
      var dy = mouse.y - root.height / 2
      return dx * dx + dy * dy <= root.radius * root.radius
    }

    onPositionChanged: function(mouse) {
      if (pressed) {
        root.pick(mouse.x, mouse.y)
      } else if (inside(mouse)) {
        var hs = root.hsAt(mouse.x, mouse.y)
        root.hovered(Qt.hsva(hs.h, hs.s, root.value, 1))
      } else {
        root.hoverEnded()
      }
    }
    onExited: root.hoverEnded()
    onPressed: function(mouse) {
      if (!inside(mouse)) {
        mouse.accepted = false
        return
      }
      root.pick(mouse.x, mouse.y)
    }
    onReleased: root.committed()
  }
}
