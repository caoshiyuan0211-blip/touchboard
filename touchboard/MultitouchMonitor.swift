import Foundation
import CoreFoundation
import os

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

/// Decides, on the trackpad's own thread, which frames are worth sending to the main thread.
/// Normal mouse use (1–3 fingers with the keyboard closed) is dropped here, so the app stays idle.
final class TrackpadFrameGate: @unchecked Sendable {
    private struct State {
        var keyboardOpen = false
        /// Devices whose latest forwarded frame had fingers down, so their "all lifted" frame still goes through.
        var devicesWithFingersDown: Set<Int> = []
    }

    private let lock = OSAllocatedUnfairLock(initialState: State())

    func setKeyboardOpen(_ open: Bool) {
        lock.withLock { $0.keyboardOpen = open }
    }

    func shouldForward(device: Int, touching: Int) -> Bool {
        lock.withLock { state in
            let wanted = state.keyboardOpen || touching >= 4 || state.devicesWithFingersDown.contains(device)
            guard wanted else { return false }
            if touching > 0 {
                state.devicesWithFingersDown.insert(device)
            } else {
                state.devicesWithFingersDown.remove(device)
            }
            return true
        }
    }
}

let trackpadFrameGate = TrackpadFrameGate()

private let contactFrameCallback: MTContactCallback = { device, data, count, _, _ in
    let deviceID = device.map { Int(bitPattern: $0) } ?? 0
    let fingers = data.map { $0.bindMemory(to: MTFinger.self, capacity: Int(max(count, 0))) }

    // Count fingers first without allocating anything, and stop early when the frame isn't needed.
    var touching = 0
    if let fingers {
        for i in 0..<Int(max(count, 0)) where touchingStates.contains(fingers[i].state) { touching += 1 }
    }
    guard trackpadFrameGate.shouldForward(device: deviceID, touching: touching) else { return 0 }

    var contacts: [TrackpadContact] = []
    contacts.reserveCapacity(touching)
    if let fingers {
        for i in 0..<Int(max(count, 0)) {
            let finger = fingers[i]
            guard touchingStates.contains(finger.state) else { continue }
            contacts.append(TrackpadContact(id: Int(finger.identifier),
                                            x: Double(finger.normalized.pos.x),
                                            y: Double(finger.normalized.pos.y)))
        }
    }
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
