// Protocol.swift — parse raw DTK-2100 reports into typed samples.
// See PROTOCOL.md for the reverse-engineered wire format (from a live capture).
//
// Every report is 10 bytes; byte 0 is the report ID.
//   0x02 = pen, 0x0c = pad (ExpressKeys / Touch Strips).

import Foundation

struct PenSample {
    var x: Int          // raw tablet units
    var y: Int          // raw tablet units
    var pressure: Int   // 0..2047
    var tiltX: Int      // -64..63
    var tiltY: Int      // -64..63
    var barrel1: Bool
    var barrel2: Bool
}

// Reverse-engineered from a timestamped labelled capture of the DTK-2100.
struct PadSample {
    var leftKeys: UInt8   // d6, bit 0 = top … bit 7 = bottom (L1..L8)
    var rightKeys: UInt8  // d8, bit 0 = top … bit 7 = bottom (R1..R8)
    var leftToggle: Bool  // d5 bit 0
    var rightToggle: Bool // d7 bit 0
    var leftStrip: Int    // one-hot position across d1:d2, 0..15 (-1 = untouched)
    var rightStrip: Int   // one-hot position across d3:d4, 0..15 (-1 = untouched)
}

// Which end of the pen is in range. Decoded from the tool id in the
// proximity-enter packet; apps switch to the eraser tool when told the pointer
// is an eraser.
enum WacomTool {
    case pen
    case eraser
}

enum WacomReport {
    case penData(PenSample)
    case proximityIn(WacomTool)
    case proximityOut
    case pad(PadSample)
    case other
}

enum WacomProtocol {
    // Raw pressure resolution of the 21UX2.
    static let pressureMax = 2047

    /// `bytes[0]` is the report ID.
    static func parse(_ bytes: [UInt8]) -> WacomReport {
        guard bytes.count >= 10 else { return .other }
        let d = bytes

        switch d[0] {
        case 0x02: return parsePen(d)
        case 0x0c: return parsePad(d)
        default:   return .other
        }
    }

    private static func parsePen(_ d: [UInt8]) -> WacomReport {
        // Packet subtype lives in d[1] & 0xb8.
        let kind = d[1] & 0xb8
        if kind == 0xa0 {
            let x = (Int(d[2]) << 9) | (Int(d[3]) << 1) | ((Int(d[9]) >> 1) & 1)
            let y = (Int(d[4]) << 9) | (Int(d[5]) << 1) | (Int(d[9]) & 1)
            let pressure = (Int(d[6]) << 3) | ((Int(d[7]) & 0xC0) >> 5) | (Int(d[1]) & 0x01)
            let tiltX = (((Int(d[7]) << 1) & 0x7E) | (Int(d[8]) >> 7)) - 64
            let tiltY = (Int(d[8]) & 0x7F) - 64
            let sample = PenSample(
                x: x, y: y, pressure: pressure,
                tiltX: tiltX, tiltY: tiltY,
                barrel1: (d[1] & 0x02) != 0,
                barrel2: (d[1] & 0x04) != 0)
            return .penData(sample)
        }
        // Non-pen-data: tool entering vs leaving proximity.
        // Enter carries a tool id (d[1]==0xc2); leave is the all-zero payload.
        if d[1] == 0x80 && d[2] == 0 && d[3] == 0 && d[4] == 0 && d[5] == 0 {
            return .proximityOut
        }
        return .proximityIn(toolFromEnterPacket(d))
    }

    /// Decode the tool id from a proximity-enter packet ((d[1] & 0xfc) == 0xc0)
    /// and classify it as pen or eraser. Formula matches Linux `input-wacom`
    /// `wacom_intuos_inout()`. Every Wacom eraser id ends in nibble 0xa
    /// (0x82a, 0x84a, 0x85a, 0x91a, 0xd1a, 0x0fa); pens end in other nibbles
    /// (this device's Grip Pen reports 0x802).
    private static func toolFromEnterPacket(_ d: [UInt8]) -> WacomTool {
        guard (d[1] & 0xfc) == 0xc0 else { return .pen }
        let id = (Int(d[2]) << 4)
            | (Int(d[3]) >> 4)
            | ((Int(d[7]) & 0x0f) << 20)
            | ((Int(d[8]) & 0xf0) << 12)
        return (id & 0x0f) == 0x0a ? .eraser : .pen
    }

    private static func parsePad(_ d: [UInt8]) -> WacomReport {
        // Strip position is a one-hot bit across a 16-bit field; return the set
        // bit's index (highest if a transition briefly sets two), or -1 if off.
        func oneHot(_ hi: UInt8, _ lo: UInt8) -> Int {
            let v = (UInt16(hi) << 8) | UInt16(lo)
            return v == 0 ? -1 : 15 - v.leadingZeroBitCount
        }
        return .pad(PadSample(
            leftKeys: d[6],
            rightKeys: d[8],
            leftToggle: d[5] & 0x01 != 0,
            rightToggle: d[7] & 0x01 != 0,
            leftStrip: oneHot(d[1], d[2]),
            rightStrip: oneHot(d[3], d[4])))
    }
}
