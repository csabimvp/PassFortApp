import Foundation

/// JSON encode/decode of `AccountPayload`, with §14.7 length-bucket padding so
/// `sealed.count` stops leaking note length.
///
/// Wire form: `u32 BE length ‖ JSON ‖ zero padding` to the next multiple of 256.
/// JSON for M2 (open decision 5) — zero dependencies; `schema_version` in the AAD
/// makes it swappable for CBOR later. Dates are milliseconds since 1970.
public enum PayloadCodec {
  static let bucket = 256

  public enum Failure: Error, Equatable {
    case truncated
    case lengthOverflow
  }

  public static func encode(_ payload: AccountPayload) throws -> Data {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .millisecondsSince1970
    encoder.outputFormatting = [.sortedKeys]  // deterministic bytes for the same payload
    let json = try encoder.encode(payload)

    guard json.count <= UInt32.max else { throw Failure.lengthOverflow }

    var out = Data(capacity: 4 + json.count + bucket)
    var prefix = UInt32(json.count).bigEndian
    withUnsafeBytes(of: &prefix) { out.append(contentsOf: $0) }
    out.append(json)

    let remainder = out.count % bucket
    if remainder != 0 { out.append(Data(count: bucket - remainder)) }
    return out
  }

  public static func decode(_ data: Data) throws -> AccountPayload {
    let bytes = Data(data)  // normalise slice indices to 0-based
    guard bytes.count >= 4 else { throw Failure.truncated }

    let length = bytes.prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
    let end = 4 + Int(length)
    guard end <= bytes.count else { throw Failure.truncated }

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .millisecondsSince1970
    return try decoder.decode(AccountPayload.self, from: bytes.subdata(in: 4..<end))
  }
}
