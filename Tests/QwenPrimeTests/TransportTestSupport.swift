import Foundation
import Testing
@testable import QwenPrime

// MARK: - Mock URLProtocol for Transport Contract Testing

final class TransportTestURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var _requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    nonisolated(unsafe) private static var _capturedRequests: [URLRequest] = []

    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _requestHandler
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _requestHandler = newValue
        }
    }

    static var capturedRequests: [URLRequest] {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _capturedRequests
        }
    }

    static func reset() {
        lock.lock()
        _requestHandler = nil
        _capturedRequests.removeAll()
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        TransportTestURLProtocol.lock.lock()
        TransportTestURLProtocol._capturedRequests.append(request)
        let handler = TransportTestURLProtocol._requestHandler
        TransportTestURLProtocol.lock.unlock()

        guard let handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

// MARK: - Test Helpers

enum TransportTestHelpers {
    static func makeTestSession() -> URLSession {
        TransportTestURLProtocol.reset()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [TransportTestURLProtocol.self]
        return URLSession(configuration: config)
    }

    static func extractRequestBodyData(from request: URLRequest) -> Data? {
        if let body = request.httpBody {
            return body
        }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: bufferSize)
            if read > 0 {
                data.append(buffer, count: read)
            } else {
                break
            }
        }
        return data.isEmpty ? nil : data
    }
}
