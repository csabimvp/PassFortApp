#if canImport(Security)
  import Foundation
  import Security

  /// The `URLSession` delegate for sync traffic: server trust (normal evaluation, then the pins)
  /// and redirects (refused). Loopback hosts skip pinning -- that is the local `npm run dev` loop.
  ///
  /// It handles trust at the **task** level (no session-level challenge method), so a pinning
  /// failure is recorded against the task that hit it and `HTTPSyncAPI` can report `.pinningFailed`
  /// rather than a bare cancellation.
  final class PinnedTransport: NSObject, URLSessionTaskDelegate, Sendable {
    private let pins: PinSet
    private let pinFailures = Locked(initialState: Set<Int>())

    init(pins: PinSet) {
      self.pins = pins
    }

    /// True once, if `taskIdentifier` was cancelled because its server failed trust or the pins.
    func takePinFailure(_ taskIdentifier: Int) -> Bool {
      pinFailures.withLock { $0.remove(taskIdentifier) != nil }
    }

    // MARK: URLSessionTaskDelegate

    func urlSession(
      _ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge,
      completionHandler:
        @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
      let space = challenge.protectionSpace
      guard space.authenticationMethod == NSURLAuthenticationMethodServerTrust else {
        return completionHandler(.performDefaultHandling, nil)
      }
      if PinSet.isLoopback(host: space.host) {
        return completionHandler(.performDefaultHandling, nil)
      }
      guard let trust = space.serverTrust, Self.evaluate(trust, pins: pins) else {
        pinFailures.withLock { _ = $0.insert(task.taskIdentifier) }
        return completionHandler(.cancelAuthenticationChallenge, nil)
      }
      completionHandler(.useCredential, URLCredential(trust: trust))
    }

    /// Never follow a redirect: the API doesn't issue them, and one could move the request -- and
    /// its token -- to another host or scheme. The `3xx` itself comes back as the response.
    func urlSession(
      _ session: URLSession, task: URLSessionTask,
      willPerformHTTPRedirection response: HTTPURLResponse,
      newRequest request: URLRequest,
      completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
      completionHandler(nil)
    }

    // MARK: The decision

    /// Trust the chain the system way first (`SecTrustEvaluateWithError`: anchors, validity, the
    /// hostname, revocation as configured), then require at least one certificate in it whose SPKI
    /// hash is pinned. An empty pin set trusts nothing.
    static func evaluate(_ trust: SecTrust, pins: PinSet) -> Bool {
      guard !pins.isEmpty, SecTrustEvaluateWithError(trust, nil),
        let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate]
      else { return false }
      return chain.contains { certificate in
        PinSet.spkiHash(of: SecCertificateCopyData(certificate) as Data)
          .map(pins.hashes.contains) ?? false
      }
    }
  }
#endif
