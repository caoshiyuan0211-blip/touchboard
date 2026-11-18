import CoreGraphics

/// One key on the virtual keyboard. `frame` is in key units (1 = one letter key), origin top-left.
struct KeyDef: Identifiable, Equatable {
    enum Kind: Equatable {
        case character(String)
        case backspace
        case enter
        case space
        case arrow
        case switchLanguage
    }

    let id: String
    let label: String
    let kind: Kind
    let keyCode: CGKeyCode
    let frame: CGRect
}

/// QWERTY layout:
///   1 2 3 4 5 6 7 8 9 0 ⌫
///    q w e r t y u i o p
///     a s d f g h j k l ⏎
///       z x c v b n m , . ↑
/// 🌐   [   space   ] ← ↓ →
enum KeyboardLayout {
    static let width: CGFloat = 11.5
    static let height: CGFloat = 5

    static let keys: [KeyDef] = build()

    /// macOS virtual key codes (ANSI layout).
    private static let keyCodes: [Character: CGKeyCode] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9,
        "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17,
        "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "9": 25, "7": 26, "8": 28, "0": 29,
        "o": 31, "u": 32, "i": 34, "p": 35, "l": 37, "j": 38, "k": 40,
        ",": 43, "n": 45, "m": 46, ".": 47,
    ]

    private static func build() -> [KeyDef] {
        var keys: [KeyDef] = []

        func addRow(_ chars: String, row: Int, startX: CGFloat) {
            for (i, ch) in chars.enumerated() {
                let s = String(ch)
                keys.append(KeyDef(id: s,
                                   label: s.uppercased(),
                                   kind: .character(s),
                                   keyCode: keyCodes[ch]!,
                                   frame: CGRect(x: startX + CGFloat(i), y: CGFloat(row), width: 1, height: 1)))
            }
        }

        addRow("1234567890", row: 0, startX: 0)
        keys.append(KeyDef(id: "backspace", label: "⌫", kind: .backspace, keyCode: 51,
                           frame: CGRect(x: 10, y: 0, width: 1.5, height: 1)))

        addRow("qwertyuiop", row: 1, startX: 0.5)

        addRow("asdfghjkl", row: 2, startX: 0.75)
        keys.append(KeyDef(id: "enter", label: "return", kind: .enter, keyCode: 36,
                           frame: CGRect(x: 9.75, y: 2, width: 1.75, height: 1)))

        addRow("zxcvbnm,.", row: 3, startX: 1.25)

        // Up arrow fills the space to the right of "."
        keys.append(KeyDef(id: "up", label: "↑", kind: .arrow, keyCode: 126,
                           frame: CGRect(x: 10.25, y: 3, width: 1.25, height: 1)))

        // Switches back to the previously used input source (e.g. ABC ⇄ Pinyin).
        keys.append(KeyDef(id: "language", label: "🌐", kind: .switchLanguage, keyCode: 0,
                           frame: CGRect(x: 0, y: 4, width: 1.5, height: 1)))

        keys.append(KeyDef(id: "space", label: "space", kind: .space, keyCode: 49,
                           frame: CGRect(x: 1.5, y: 4, width: 6.75, height: 1)))

        let bottomArrows: [(id: String, label: String, code: CGKeyCode)] = [
            ("left", "←", 123), ("down", "↓", 125), ("right", "→", 124),
        ]
        for (i, arrow) in bottomArrows.enumerated() {
            keys.append(KeyDef(id: arrow.id, label: arrow.label, kind: .arrow, keyCode: arrow.code,
                               frame: CGRect(x: 8.5 + CGFloat(i), y: 4, width: 1, height: 1)))
        }
        return keys
    }

    /// Maps a normalized trackpad position (origin bottom-left) to keyboard units (origin top-left).
    /// A small margin at the trackpad edges makes the outer keys easy to reach.
    static func point(fromTrackpadX x: Double, y: Double) -> CGPoint {
        let margin = 0.04
        func norm(_ v: Double) -> Double { min(max((v - margin) / (1 - 2 * margin), 0), 1) }
        return CGPoint(x: CGFloat(norm(x)) * width, y: CGFloat(1 - norm(y)) * height)
    }

    /// The key under a point, or the nearest key if the point is in a gap.
    static func key(at point: CGPoint) -> KeyDef? {
        keys.min { distance(point, $0.frame) < distance(point, $1.frame) }
    }

    private static func distance(_ p: CGPoint, _ r: CGRect) -> CGFloat {
        let dx = max(r.minX - p.x, 0, p.x - r.maxX)
        let dy = max(r.minY - p.y, 0, p.y - r.maxY)
        return hypot(dx, dy)
    }
}
