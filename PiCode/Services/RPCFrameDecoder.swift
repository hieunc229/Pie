//
//  RPCFrameDecoder.swift
//  PiCode
//
//  Reassembles Oh My Pi protocol-v2 `rpc_chunk` records into the logical JSON
//  response they carry. Physical records stay below OMP's 1 MiB JSONL limit.
//

import Foundation

enum RPCFrameDecoderError: LocalizedError {
    case invalidMetadata
    case invalidPayload
    case interrupted
    case sequenceMismatch
    case lengthMismatch
    case invalidJSON

    var errorDescription: String? {
        switch self {
        case .invalidMetadata: return "OMP sent invalid RPC chunk metadata."
        case .invalidPayload: return "OMP sent an invalid RPC chunk payload."
        case .interrupted: return "OMP interrupted a chunked RPC response."
        case .sequenceMismatch: return "OMP sent RPC response chunks out of sequence."
        case .lengthMismatch: return "OMP's chunked RPC response length did not match its metadata."
        case .invalidJSON: return "OMP's reassembled RPC response was not valid JSON."
        }
    }
}

final class RPCFrameDecoder {
    private static let maximumFrameBytes = 1024 * 1024
    private static let maximumReassembledBytes = 64 * 1024 * 1024
    private static let maximumChunkBytes = 256 * 1024

    private struct Pending {
        var id: String
        var count: Int
        var byteLength: Int
        var nextIndex: Int
        var data: Data
    }

    private var pending: Pending?

    func push(_ value: JSONValue) throws -> JSONValue? {
        guard value.string("type") == "rpc_chunk" else {
            guard pending == nil else {
                pending = nil
                throw RPCFrameDecoderError.interrupted
            }
            return value
        }

        guard let id = value.string("chunkId"), !id.isEmpty, id.count <= 128,
              let index = value.int("index"),
              let count = value.int("count"),
              let byteLength = value.int("byteLength"),
              index >= 0, count >= 2, index < count,
              byteLength >= Self.maximumFrameBytes,
              byteLength <= Self.maximumReassembledBytes,
              count <= (Self.maximumReassembledBytes + Self.maximumChunkBytes - 1) / Self.maximumChunkBytes else {
            pending = nil
            throw RPCFrameDecoderError.invalidMetadata
        }

        guard let encoded = value.string("data"), !encoded.isEmpty,
              let chunk = Data(base64Encoded: encoded),
              chunk.base64EncodedString() == encoded,
              chunk.count <= Self.maximumChunkBytes else {
            pending = nil
            throw RPCFrameDecoderError.invalidPayload
        }

        if pending == nil {
            guard index == 0 else { throw RPCFrameDecoderError.sequenceMismatch }
            pending = Pending(id: id, count: count, byteLength: byteLength, nextIndex: 0, data: Data())
            pending?.data.reserveCapacity(byteLength)
        }

        guard var sequence = pending,
              sequence.id == id,
              sequence.count == count,
              sequence.byteLength == byteLength,
              sequence.nextIndex == index else {
            pending = nil
            throw RPCFrameDecoderError.sequenceMismatch
        }

        sequence.data.append(chunk)
        sequence.nextIndex += 1
        guard sequence.data.count <= sequence.byteLength else {
            pending = nil
            throw RPCFrameDecoderError.lengthMismatch
        }
        guard sequence.nextIndex == sequence.count else {
            pending = sequence
            return nil
        }

        pending = nil
        guard sequence.data.count == sequence.byteLength else {
            throw RPCFrameDecoderError.lengthMismatch
        }
        guard let decoded = try? JSONCoding.decode(sequence.data),
              decoded.objectValue != nil else {
            throw RPCFrameDecoderError.invalidJSON
        }
        return decoded
    }
}
