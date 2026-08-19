//  Arm64DDC.swift
//  外接显示器 DDC/CI 通信（Apple Silicon，IOAVService 路线）
//
//  改写自 MonitorControl 项目的 Arm64DDC.swift
//  Copyright © MonitorControl. @JoniVR, @theOneyouseek, @waydabber and others
//  (MIT License, https://github.com/MonitorControl/MonitorControl)
//
//  与原实现的差异：私有符号改为 dlsym 动态加载（符号缺失时整体降级），
//  读回复补充 VCP opcode 校验，支持 MCDP29xx HDMI 转换芯片的 0xB7 地址。

import CoreGraphics
import Foundation
import IOKit
import os

/// IOAVService / CoreDisplay 私有符号的 dlsym 封装
final class DDCPrivateAPI {
    static let shared = DDCPrivateAPI()

    typealias CreateWithServiceFunc = @convention(c) (UnsafeRawPointer?, io_service_t) -> UnsafeMutableRawPointer?
    typealias ReadI2CFunc = @convention(c) (UnsafeMutableRawPointer?, UInt32, UInt32, UnsafeMutableRawPointer, UInt32) -> Int32
    typealias WriteI2CFunc = @convention(c) (UnsafeMutableRawPointer?, UInt32, UInt32, UnsafeMutableRawPointer, UInt32) -> Int32
    typealias DisplayInfoDictFunc = @convention(c) (CGDirectDisplayID) -> UnsafeMutableRawPointer?

    private(set) var createWithService: CreateWithServiceFunc?
    private(set) var readI2C: ReadI2CFunc?
    private(set) var writeI2C: WriteI2CFunc?
    private(set) var displayInfoDict: DisplayInfoDictFunc?

    var isAvailable: Bool {
        createWithService != nil && readI2C != nil && writeI2C != nil && displayInfoDict != nil
    }

    private init() {
        guard let iokit = dlopen("/System/Library/Frameworks/IOKit.framework/Versions/A/IOKit", RTLD_LAZY),
              let coreDisplay = dlopen("/System/Library/Frameworks/CoreDisplay.framework/Versions/A/CoreDisplay", RTLD_LAZY) else {
            AppLog.brightness.error("DDC: unable to dlopen IOKit/CoreDisplay")
            return
        }
        if let p = dlsym(iokit, "IOAVServiceCreateWithService") {
            createWithService = unsafeBitCast(p, to: CreateWithServiceFunc.self)
        }
        if let p = dlsym(iokit, "IOAVServiceReadI2C") {
            readI2C = unsafeBitCast(p, to: ReadI2CFunc.self)
        }
        if let p = dlsym(iokit, "IOAVServiceWriteI2C") {
            writeI2C = unsafeBitCast(p, to: WriteI2CFunc.self)
        }
        if let p = dlsym(coreDisplay, "CoreDisplay_DisplayCreateInfoDictionary") {
            displayInfoDict = unsafeBitCast(p, to: DisplayInfoDictFunc.self)
        }
        if !isAvailable {
            AppLog.brightness.error("DDC: IOAVService/CoreDisplay symbols missing, DDC disabled")
        }
    }

    /// CoreDisplay_DisplayCreateInfoDictionary 的托管包装
    func displayInfo(for displayID: CGDirectDisplayID) -> NSDictionary? {
        guard let fn = displayInfoDict, let raw = fn(displayID) else { return nil }
        return Unmanaged<CFDictionary>.fromOpaque(raw).takeRetainedValue() as NSDictionary
    }
}

enum Arm64DDC {
    static let standardChipAddress: UInt32 = 0x37
    static let mcdp29xxChipAddress: UInt32 = 0xB7
    private static let dataAddress: UInt32 = 0x51
    static let maxMatchScore = 20

    struct IOregService {
        var edidUUID = ""
        var productName = ""
        var serialNumber: Int64 = 0
        var ioDisplayLocation = ""
        var location = ""
        var isMCDP29xx = false
        var service: UnsafeMutableRawPointer?
        var serviceLocation = 0
    }

    struct MatchedService {
        var displayID: CGDirectDisplayID
        var service: UnsafeMutableRawPointer
        var chipAddress: UInt32
        var productName: String
        var matchScore: Int
    }

    /// 枚举 IORegistry 中的外接 DCPAVServiceProxy 并与 CGDirectDisplayID 打分匹配
    static func getServiceMatches(displayIDs: [CGDirectDisplayID]) -> [MatchedService] {
        guard DDCPrivateAPI.shared.isAvailable else { return [] }
        let ioregServices = getIoregServices()
        var scored: [Int: [(CGDirectDisplayID, IOregService)]] = [:]
        for displayID in displayIDs {
            for svc in ioregServices where svc.service != nil {
                let score = matchScore(displayID: displayID, service: svc)
                scored[score, default: []].append((displayID, svc))
            }
        }
        var matches: [MatchedService] = []
        var takenDisplayIDs: Set<CGDirectDisplayID> = []
        var takenLocations: Set<Int> = []
        for score in stride(from: maxMatchScore, to: 0, by: -1) {
            for (displayID, svc) in scored[score] ?? [] where !takenDisplayIDs.contains(displayID) && !takenLocations.contains(svc.serviceLocation) {
                takenDisplayIDs.insert(displayID)
                takenLocations.insert(svc.serviceLocation)
                matches.append(MatchedService(
                    displayID: displayID,
                    service: svc.service!,
                    chipAddress: svc.isMCDP29xx ? mcdp29xxChipAddress : standardChipAddress,
                    productName: svc.productName,
                    matchScore: score
                ))
            }
        }
        // 未匹配到的 service 释放引用
        let usedServices = Set(matches.map { UInt(bitPattern: $0.service) })
        for svc in ioregServices {
            if let ptr = svc.service, !usedServices.contains(UInt(bitPattern: ptr)) {
                Unmanaged<AnyObject>.fromOpaque(ptr).release()
            }
        }
        return matches
    }

    static func releaseService(_ ptr: UnsafeMutableRawPointer) {
        Unmanaged<AnyObject>.fromOpaque(ptr).release()
    }

    /// 读 VCP 特性，返回 (当前值, 最大值)
    static func read(service: UnsafeMutableRawPointer, chipAddress: UInt32 = standardChipAddress, command: UInt8) -> (current: UInt16, max: UInt16)? {
        var send: [UInt8] = [command]
        var reply = [UInt8](repeating: 0, count: 11)
        guard performDDCCommunication(service: service, chipAddress: chipAddress, send: &send, reply: &reply) else { return nil }
        // 校验回复中的 VCP opcode，防止跨进程回复交错
        guard reply[4] == command else { return nil }
        let maxValue = UInt16(reply[6]) * 256 + UInt16(reply[7])
        let current = UInt16(reply[8]) * 256 + UInt16(reply[9])
        return (current, maxValue)
    }

    /// 写 VCP 特性
    static func write(service: UnsafeMutableRawPointer, chipAddress: UInt32 = standardChipAddress, command: UInt8, value: UInt16) -> Bool {
        var send: [UInt8] = [command, UInt8(value >> 8), UInt8(value & 255)]
        var reply: [UInt8] = []
        return performDDCCommunication(service: service, chipAddress: chipAddress, send: &send, reply: &reply)
    }

    // MARK: - DDC 通信

    private static func performDDCCommunication(
        service: UnsafeMutableRawPointer,
        chipAddress: UInt32,
        send: inout [UInt8],
        reply: inout [UInt8],
        writeSleepTime: UInt32 = 10000,
        numOfWriteCycles: Int = 2,
        readSleepTime: UInt32 = 50000,
        numOfRetryAttemps: Int = 4,
        retrySleepTime: UInt32 = 20000
    ) -> Bool {
        guard let writeFn = DDCPrivateAPI.shared.writeI2C, let readFn = DDCPrivateAPI.shared.readI2C else { return false }
        var success = false
        var packet: [UInt8] = [UInt8(0x80 | (send.count + 1)), UInt8(send.count)] + send + [0]
        let seed: UInt8 = send.count == 1
            ? UInt8(truncatingIfNeeded: chipAddress << 1)
            : UInt8(truncatingIfNeeded: chipAddress << 1) ^ UInt8(dataAddress)
        packet[packet.count - 1] = checksum(seed: seed, data: packet, start: 0, end: packet.count - 2)
        for _ in 1 ... numOfRetryAttemps + 1 {
            for _ in 1 ... max(numOfWriteCycles, 1) {
                usleep(writeSleepTime)
                success = writeFn(service, chipAddress, dataAddress, &packet, UInt32(packet.count)) == 0
            }
            if !reply.isEmpty {
                usleep(readSleepTime)
                if readFn(service, chipAddress, 0, &reply, UInt32(reply.count)) == 0 {
                    success = checksum(seed: 0x50, data: reply, start: 0, end: reply.count - 2) == reply[reply.count - 1]
                } else {
                    success = false
                }
            }
            if success {
                return true
            }
            usleep(retrySleepTime)
        }
        return false
    }

    private static func checksum(seed: UInt8, data: [UInt8], start: Int, end: Int) -> UInt8 {
        var chk = seed
        for i in start ... end {
            chk ^= data[i]
        }
        return chk
    }

    // MARK: - IORegistry 枚举

    private static func getIoregServices() -> [IOregService] {
        var results: [IOregService] = []
        var serviceLocation = 0
        guard let createFn = DDCPrivateAPI.shared.createWithService else { return results }
        let root = IORegistryGetRootEntry(kIOMainPortDefault)
        defer { IOObjectRelease(root) }
        var iterator = io_iterator_t()
        guard IORegistryEntryCreateIterator(root, "IOService", IOOptionBits(kIORegistryIterateRecursively), &iterator) == KERN_SUCCESS else {
            return results
        }
        defer { IOObjectRelease(iterator) }

        var current = IOregService()
        let framebufferNames = ["AppleCLCD2", "IOMobileFramebufferShim"]
        let nameBuf = UnsafeMutablePointer<CChar>.allocate(capacity: MemoryLayout<io_name_t>.size)
        defer { nameBuf.deallocate() }

        while true {
            let entry = IOIteratorNext(iterator)
            guard entry != IO_OBJECT_NULL else { break }
            defer { IOObjectRelease(entry) }
            guard IORegistryEntryGetName(entry, nameBuf) == KERN_SUCCESS else { continue }
            let name = String(cString: nameBuf)

            if framebufferNames.contains(name) {
                current = IOregService()
                if let s = registryString(entry, "EDID UUID") {
                    current.edidUUID = s
                }
                let pathBuf = UnsafeMutablePointer<CChar>.allocate(capacity: MemoryLayout<io_string_t>.size)
                if IORegistryEntryGetPath(entry, "IOService", pathBuf) == KERN_SUCCESS {
                    current.ioDisplayLocation = String(cString: pathBuf)
                }
                pathBuf.deallocate()
                if let u = IORegistryEntryCreateCFProperty(entry, "DisplayAttributes" as CFString, kCFAllocatorDefault, 0),
                   let attrs = u.takeRetainedValue() as? NSDictionary,
                   let product = attrs["ProductAttributes"] as? NSDictionary {
                    current.productName = product["ProductName"] as? String ?? ""
                    current.serialNumber = (product["SerialNumber"] as? Int64) ?? 0
                }
                serviceLocation += 1
                current.serviceLocation = serviceLocation
            } else if name == "DCPAVServiceProxy" {
                if let location = registryString(entry, "Location") {
                    current.location = location
                    if location == "External" {
                        current.service = createFn(nil, entry)
                        var parent = io_service_t()
                        if IORegistryEntryGetParentEntry(entry, "IOService", &parent) == KERN_SUCCESS {
                            if let epic = registryString(parent, "EPICProviderClass"), epic == "AppleDCPMCDP29XX" {
                                current.isMCDP29xx = true
                            }
                            IOObjectRelease(parent)
                        }
                    }
                }
                results.append(current)
                current.service = nil
            }
        }
        return results
    }

    private static func registryString(_ entry: io_service_t, _ key: String) -> String? {
        guard let u = IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0) else { return nil }
        return u.takeRetainedValue() as? String
    }

    // MARK: - 匹配打分（EDID UUID 分段 4×1 分、IODisplayLocation 全等 10 分、产品名 1 分、序列号 1 分）

    private static func matchScore(displayID: CGDirectDisplayID, service svc: IOregService) -> Int {
        var score = 0
        guard let dict = DDCPrivateAPI.shared.displayInfo(for: displayID) else { return 0 }
        if let year = dict["DisplayYearOfManufacture"] as? Int64,
           let week = dict["DisplayWeekOfManufacture"] as? Int64,
           let vendor = dict["DisplayVendorID"] as? Int64,
           let product = dict["DisplayProductID"] as? Int64,
           let vsize = dict["DisplayVerticalImageSize"] as? Int64,
           let hsize = dict["DisplayHorizontalImageSize"] as? Int64 {
            let productWord = UInt16(max(0, min(product, 65535)))
            let keys: [(key: String, loc: Int)] = [
                (String(format: "%04x", UInt16(max(0, min(vendor, 65535)))).uppercased(), 0),
                (String(format: "%02x%02x", UInt8(productWord & 0xFF), UInt8(productWord >> 8)).uppercased(), 4),
                (String(format: "%02x%02x", UInt8(max(0, min(week, 255))), UInt8(max(0, min(year - 1990, 255)))).uppercased(), 19),
                (String(format: "%02x%02x", UInt8(max(0, min(hsize / 10, 255))), UInt8(max(0, min(vsize / 10, 255)))).uppercased(), 30),
            ]
            for (key, loc) in keys where key != "0000" && key == svc.edidUUID.prefix(loc + 4).suffix(4) {
                score += 1
            }
        }
        if !svc.ioDisplayLocation.isEmpty, let loc = dict["IODisplayLocation"] as? String, loc == svc.ioDisplayLocation {
            score += 10
        }
        if !svc.productName.isEmpty, let names = dict["DisplayProductName"] as? [String: String],
           let name = names["en_US"] ?? names.first?.value, name.lowercased() == svc.productName.lowercased() {
            score += 1
        }
        if svc.serialNumber != 0, let serial = dict["DisplaySerialNumber"] as? Int64, serial == svc.serialNumber {
            score += 1
        }
        return score
    }
}
