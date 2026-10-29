#if canImport(Security)
  import Foundation

  /// `SyncTransport` over `URLSession` with `PinnedTransport` as its delegate (`m5-sync.md` 7.2):
  /// pinned TLS 1.3, the request timeout, no cache, no cookies, no credentials, and nothing logged
  /// -- bodies carry `k_auth`, tokens and sealed blobs.
  final class URLSessionTransport: SyncTransport {
    private let session: URLSession
    private let delegate: PinnedTransport

    /// - Parameter configuration: `.ephemeral` in use; tests pass one with stub `protocolClasses`.
    init(pins: PinSet, configuration: URLSessionConfiguration = .ephemeral) {
      delegate = PinnedTransport(pins: pins)
      configuration.timeoutIntervalForRequest = HTTPSyncAPI.requestTimeout
      configuration.urlCache = nil
      configuration.httpCookieStorage = nil
      configuration.httpShouldSetCookies = false
      configuration.urlCredentialStorage = nil
      configuration.tlsMinimumSupportedProtocolVersion = .TLSv13  // §9.4
      session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
    }

    deinit {
      // The session holds its delegate strongly until invalidated.
      session.finishTasksAndInvalidate()
    }

    func send(_ request: SyncHTTPRequest) async throws -> SyncHTTPResponse {
      var urlRequest = URLRequest(url: request.url)
      urlRequest.httpMethod = request.method
      for (name, value) in request.headers { urlRequest.setValue(value, forHTTPHeaderField: name) }
      urlRequest.httpBody = request.body

      let (data, response) = try await perform(urlRequest)
      var headers: [String: String] = [:]
      for case (let name as String, let value as String) in response.allHeaderFields {
        headers[name] = value
      }
      return SyncHTTPResponse(status: response.statusCode, headers: headers, body: data)
    }

    /// `dataTask` rather than `data(for:)`: the task's identifier is what tells a pinning failure
    /// apart from any other cancellation.
    private func perform(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
      let box = TaskBox()
      return try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation { continuation in
          let task = session.dataTask(with: request) { [delegate] data, response, error in
            if let error {
              continuation.resume(
                throwing: Self.error(for: error, pinFailed: delegate.takePinFailure(box.identifier))
              )
            } else if let response = response as? HTTPURLResponse {
              continuation.resume(returning: (data ?? Data(), response))
            } else {
              continuation.resume(throwing: SyncError.invalidResponse)
            }
          }
          box.task = task
          task.resume()
        }
      } onCancel: {
        box.task?.cancel()
      }
    }

    // MARK: - Error mapping

    static func error(for error: any Error, pinFailed: Bool) -> any Error {
      if pinFailed { return SyncError.pinningFailed }
      guard let urlError = error as? URLError else { return SyncError.offline }
      switch urlError.code {
      case .cancelled:
        return CancellationError()
      case .serverCertificateUntrusted, .serverCertificateHasBadDate,
        .serverCertificateHasUnknownRoot,
        .serverCertificateNotYetValid:
        return SyncError.pinningFailed
      default:
        return SyncError.offline
      }
    }
  }

  /// The in-flight task, for cancellation and for its identifier in the completion handler.
  private final class TaskBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: URLSessionDataTask?
    var task: URLSessionDataTask? {
      get { lock.withLock { stored } }
      set { lock.withLock { stored = newValue } }
    }
    var identifier: Int { task?.taskIdentifier ?? -1 }
  }
#endif
