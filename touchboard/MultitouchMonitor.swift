import Foundation
import CoreFoundation

/// One finger currently pressing the trackpad.
/// `x` and `y` are normalized 0...1, origin at the bottom-left of the trackpad.
struct TrackpadContact {
    let id: Int
    let x: Double
    let y: Double
}

// Memory layout of a contact as delivered by Apple's private MultitouchSupport framework.
// Field order and types must match the C struct exactly (96 bytes).
private struct MTPoint { var x: Float; var y: Float }
private struct MTReadout { var pos: MTPoint; var vel: MTPoint }
private struct MTFinger {
    var frame: Int32
    var timestamp: Double
    var identifier: Int32
    var state: Int32
    var unknown1: Int32
    var unknown2: Int32
    var normalized: MTReadout
    var size: Float
    var zero1: Int32
    var angle: Float
    var majorAxis: Float
    var minorAxis: Float
    var millimeters: MTReadout
    var zero2: (Int32, Int32)
    var unknown3: Float
}

private typealias MTDeviceRef = UnsafeMutableRawPointer
private typealias MTContactCallback = @convention(c) (MTDeviceRef?, UnsafeMutableRawPointer?, Int32, Double, Int32) -> Int32

/// MultitouchSupport finger states: 3 = touch began, 4 = touching.
private let touchingStates: Set<Int32> = [3, 4]

private let contactFrameCallback: MTContactCallback = { device, data, count, _, _ in
    var contacts: [TrackpadContact] = []
    if let data, count > 0 {
        let fingers = data.bindMemory(to: MTFinger.self, capacity: Int(count))
        for i in 0..<Int(count) {
            let finger = fingers[i]
            guard touchingStates.contains(finger.state) else { continue }
            contacts.append(TrackpadContact(id: Int(finger.identifier),
                                            x: Double(finger.normalized.pos.x),
                                            y: Double(finger.normalized.pos.y)))
        }
    }
    let deviceID = device.map { Int(bitPattern: $0) } ?? 0
    DispatchQueue.main.async {
        MainActor.assumeIsolated {
            MultitouchMonitor.shared.onFrame?(deviceID, contacts)
        }
    }
    return 0
}

/// Reads raw finger positions from every trackpad, even while another app is in front.
/// Uses the private MultitouchSupport framework (the same approach tools like BetterTouchTool use).
@MainActor
final class MultitouchMonitor {
    static let shared = MultitouchMonitor()

    /// Called on the main thread for every trackpad frame: (device id, fingers touching).
    var onFrame: ((Int, [TrackpadContact]) -> Void)?

    private var deviceList: CFArray?
    private(set) var deviceCount = 0

    /// Returns true when at least one trackpad was found and started.
    @discardableResult
    func start() -> Bool {
        if deviceCount > 0 { return true }
        assert(MemoryLayout<MTFinger>.stride == 96, "MTFinger layout mismatch")

        let path = "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport"
        guard let handle = dlopen(path, RTLD_NOW),
              let createListSym = dlsym(handle, "MTDeviceCreateList"),
              let registerSym = dlsym(handle, "MTRegisterContactFrameCallback"),
              let startSym = dlsym(handle, "MTDeviceStart") else {
            return false
        }

        typealias CreateListFn = @convention(c) () -> Unmanaged<CFArray>?
        typealias RegisterFn = @convention(c) (MTDeviceRef, MTContactCallback) -> Void
        typealias StartFn = @convention(c) (MTDeviceRef, Int32) -> Void

        let createList = unsafeBitCast(createListSym, to: CreateListFn.self)
        let register = unsafeBitCast(registerSym, to: RegisterFn.self)
        let startDevice = unsafeBitCast(startSym, to: StartFn.self)

        guard let list = createList()?.takeRetainedValue() else { return false }
        deviceList = list // keep the devices alive

        let count = CFArrayGetCount(list)
        for i in 0..<count {
            guard let raw = CFArrayGetValueAtIndex(list, i) else { continue }
            let device = UnsafeMutableRawPointer(mutating: raw)
            register(device, contactFrameCallback)
            startDevice(device, 0)
        }
        deviceCount = count
        return count > 0
    }
}
