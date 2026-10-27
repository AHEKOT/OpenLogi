import Foundation
import IOKit.hid
import MXMaster4Core

/// The run-loop thread owns IOKit. The condition protects the one pending transaction.
final class HIDConnection: ReportTransport, @unchecked Sendable {
    private let device: IOHIDDevice
    private let condition = NSCondition()
    private let transactionLock = NSLock()
    private var runLoop: CFRunLoop?
    private var ready = false
    private var stopping = false
    private var retired = false
    private var request: HIDPPReport?
    private var response: [UInt8]?
    private var failure: HIDPPError?
    private var writeCompleted = false
    private var output: UnsafeMutablePointer<UInt8>?
    private let finished = DispatchSemaphore(value: 0)
    private var pump: Thread?
    let softwareID: UInt8
    let nodeName: String
    private let lease: HostLock

    init(device: IOHIDDevice, registryID: UInt64) throws {
        self.device = device
        nodeName = HostLock.nodeName(registryID: registryID)
        (softwareID, lease) = try HostLock.softwareID(node: nodeName)
    }

    func open() throws {
        let thread = Thread { [self] in service() }
        thread.name = "MX4 HID reports"
        pump = thread
        thread.start()
        condition.lock()
        let deadline = Date(timeIntervalSinceNow: 3)
        while !ready && failure == nil {
            if !condition.wait(until: deadline) { break }
        }
        let error = failure ?? (ready ? nil : .timeout)
        condition.unlock()
        if let error { close(); throw error }
    }

    func close() {
        condition.lock()
        stopping = true
        retired = true
        let loop = runLoop
        condition.broadcast()
        condition.unlock()
        if let loop { CFRunLoopWakeUp(loop) }
        // A stuck OS open must not freeze the caller; its owning thread retains its buffers.
        _ = finished.wait(timeout: .now() + 3)
    }

    func exchange(_ bytes: [UInt8]) throws -> [UInt8] {
        transactionLock.lock()
        defer { transactionLock.unlock() }
        let message = try HIDPPReport(bytes)
        condition.lock()
        guard !retired, !stopping, let loop = runLoop else {
            condition.unlock(); throw HIDPPError.disconnected
        }
        request = message; response = nil; failure = nil; writeCompleted = false
        CFRunLoopPerformBlock(loop, CFRunLoopMode.defaultMode.rawValue) { [self] in
            condition.lock()
            let active = !stopping && !retired
            condition.unlock()
            guard active, let output else { return }
            output.update(from: bytes, count: bytes.count)
            let status = IOHIDDeviceSetReportWithCallback(device, kIOHIDReportTypeOutput,
                CFIndex(bytes[0]), output, bytes.count, 1.5, { context, status, _, _, _, _, _ in
                    guard let context else { return }
                    let owner = Unmanaged<HIDConnection>.fromOpaque(context).takeUnretainedValue()
                    owner.written(status)
                }, Unmanaged.passUnretained(self).toOpaque())
            if status != kIOReturnSuccess { written(status) }
        }
        CFRunLoopWakeUp(loop)
        let deadline = Date(timeIntervalSinceNow: 2)
        while failure == nil && !stopping && (response == nil || !writeCompleted) {
            if !condition.wait(until: deadline) { break }
        }
        let reply = response
        var error = failure
        if stopping { error = .disconnected }
        if error == nil && (reply == nil || !writeCompleted) { error = .timeout }
        // An ambiguous timeout retires this channel; a late reply cannot answer another ask.
        if error != nil { retired = true }
        request = nil
        condition.unlock()
        if let error { throw error }
        guard let reply else { throw HIDPPError.timeout }
        return reply
    }

    private func written(_ status: IOReturn) {
        condition.lock()
        writeCompleted = true
        if status != kIOReturnSuccess { failure = .transport(String(format: "HID write failed: 0x%08x", status)) }
        condition.broadcast()
        condition.unlock()
    }

    private func received(_ bytes: [UInt8], status: IOReturn) {
        condition.lock()
        defer { condition.unlock() }
        if status != kIOReturnSuccess {
            failure = .disconnected
        } else if let expected = request, let report = try? HIDPPReport(bytes), report.matches(expected) {
            response = bytes
        }
        condition.broadcast()
    }

    private func service() {
        defer { finished.signal() }
        let status = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        guard status == kIOReturnSuccess else {
            condition.lock()
            failure = .transport(String(format: "HID open failed: 0x%08x. Check the agent's Input Monitoring permission and other mouse utilities.", status))
            condition.broadcast(); condition.unlock()
            return
        }
        let input = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)
        let outputBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 20)
        let loop = CFRunLoopGetCurrent()!
        IOHIDDeviceScheduleWithRunLoop(device, loop, CFRunLoopMode.defaultMode.rawValue)
        IOHIDDeviceRegisterInputReportCallback(device, input, 64, { context, status, _, _, _, report, length in
            guard let context, length >= 0, length <= 64 else { return }
            let owner = Unmanaged<HIDConnection>.fromOpaque(context).takeUnretainedValue()
            owner.received(Array(UnsafeBufferPointer(start: report, count: length)), status: status)
        }, Unmanaged.passUnretained(self).toOpaque())
        condition.lock()
        runLoop = loop; output = outputBuffer; ready = true
        condition.broadcast(); condition.unlock()
        while true {
            condition.lock(); let stop = stopping; condition.unlock()
            if stop { break }
            CFRunLoopRunInMode(.defaultMode, 0.05, false)
        }
        IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDDeviceUnscheduleFromRunLoop(device, loop, CFRunLoopMode.defaultMode.rawValue)
        condition.lock(); output = nil; runLoop = nil; condition.unlock()
        input.deallocate(); outputBuffer.deallocate()
    }
}
