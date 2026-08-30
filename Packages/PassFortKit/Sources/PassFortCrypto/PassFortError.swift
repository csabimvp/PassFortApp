internal import PFCrypto   // `internal` keeps pf.* out of this module's public API,
                           // which is what stops interop mode going viral downstream.

/// Swift-side view of a `pf::Status`. Deliberately carries no C++ type.
public enum PassFortError: Error, Equatable {
    case badInput, locked, authFailed, notFound, unsupported, unexpected

    init(_ status: pf.Status) {
        switch status {
        case .BadInput:    self = .badInput
        case .Locked:      self = .locked
        case .AuthFailed:  self = .authFailed
        case .NotFound:    self = .notFound
        case .Unsupported: self = .unsupported
        default:           self = .unexpected
        }
    }
}
