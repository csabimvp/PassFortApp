import Foundation
internal import PFCrypto

/// The single place `pf::BytesResult` -> `Data` marshaling lives (architecture §6.3).
/// Copies the bytes out and frees the C++ handle (which zeroizes it).
func consume(_ r: pf.BytesResult) throws -> Data {
  guard r.status == pf.Status.Ok, let handle = r.handle else {
    throw PassFortError(r.status)
  }
  defer { pf.pf_bytes_free(handle) }
  guard let base = pf.pf_bytes_data(handle) else { return Data() }
  return Data(bytes: base, count: pf.pf_bytes_size(handle))
}

/// Unwrap an opaque session handle, or throw. The caller owns the handle and
/// must eventually `pf_session_close` it.
func consume(_ r: pf.SessionResult) throws -> OpaquePointer {
  guard r.status == pf.Status.Ok, let handle = r.handle else {
    throw PassFortError(r.status)
  }
  return handle
}

/// Unwrap an opaque manifest-MAC handle, or throw. The caller must `pf_mac_free`.
func consume(_ r: pf.MacResult) throws -> OpaquePointer {
  guard r.status == pf.Status.Ok, let handle = r.handle else {
    throw PassFortError(r.status)
  }
  return handle
}

/// Unwrap the POD `KdfParams` from a calibrate result. Nothing to free.
func consume(_ r: pf.KdfResult) throws -> pf.KdfParams {
  guard r.status == pf.Status.Ok else { throw PassFortError(r.status) }
  return r.params
}

/// M0 smoke test of the seam: bytes in, identical bytes out, via a C++ round trip.
public func echo(_ input: Data) throws -> Data {
  try input.withUnsafeBytes { raw in
    try consume(pf.pf_echo(raw.bindMemory(to: UInt8.self).baseAddress, raw.count))
  }
}

/// Phase 3 link probe: proves Botan is compiled in and reachable through the seam.
public func botanVersion() throws -> String {
  String(decoding: try consume(pf.pf_botan_version()), as: UTF8.self)
}
