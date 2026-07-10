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

struct PadSample {
    var keyBits: UInt16 // ExpressKey bitmask (d3 low byte, d4 high byte)
    var strip1: Int     // touch strip position (d8)
    var strip2: Int     // touch strip position (d9)
}

enum WacomReport {
    case penData(PenSample)
    case proximityIn
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
        return .proximityIn
    }

    private static func parsePad(_ d: [UInt8]) -> WacomReport {
        let bits = UInt16(d[3]) | (UInt16(d[4]) << 8)
        return .pad(PadSample(keyBits: bits, strip1: Int(d[8]), strip2: Int(d[9])))
    }
}
