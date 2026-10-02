import Foundation

/// Wire format: one JSON message per connection, terminated by a newline.
/// A hook either fires and forgets (`send`), or asks and waits for one JSON line back (`request`).
public enum UnixSocket {
    static func address(for path: String) -> sockaddr_un {
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8CString)
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            for (i, b) in bytes.prefix(raw.count - 1).enumerated() { raw[i] = UInt8(bitPattern: b) }
        }
        return addr
    }

    static func connectSocket(to url: URL) -> Int32 {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return -1 }
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        var addr = address(for: url.path)
        let result = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard result == 0 else { close(fd); return -1 }
        return fd
    }

    static func writeAll(_ fd: Int32, _ data: Data) -> Bool {
        data.withUnsafeBytes { raw -> Bool in
            guard let base = raw.baseAddress else { return true }
            var offset = 0
            while offset < raw.count {
                let written = write(fd, base + offset, raw.count - offset)
                if written < 0 {
                    if errno == EINTR { continue }
                    return false
                }
                offset += written
            }
            return true
        }
    }

    static func framed(_ data: Data) -> Data {
        data.last == 0x0A ? data : data + Data([0x0A])
    }

    /// Fire and forget. Returns false when the app is not listening.
    @discardableResult
    public static func send(_ data: Data, to url: URL = IslandPaths.socketURL) -> Bool {
        let fd = connectSocket(to: url)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        return writeAll(fd, framed(data))
    }

    /// Sends one message and waits for one line back.
    /// Returns nil when the app is not running, drops the connection, or does not answer within `timeout` seconds.
    public static func request(_ data: Data, timeout: TimeInterval, to url: URL = IslandPaths.socketURL) -> Data? {
        let fd = connectSocket(to: url)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        guard writeAll(fd, framed(data)) else { return nil }

        let deadline = Date().addingTimeInterval(timeout)
        var received = Data()
        var chunk = [UInt8](repeating: 0, count: 4096)
        while true {
            let remaining = deadline.timeIntervalSinceNow
            if remaining <= 0 { return nil }
            var descriptor = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            let ready = poll(&descriptor, 1, Int32(min(remaining * 1000, 1_000_000)))
            if ready < 0 {
                if errno == EINTR { continue }
                return nil
            }
            if ready == 0 { return nil }
            let count = read(fd, &chunk, chunk.count)
            if count > 0 {
                received.append(chunk, count: count)
                if let newline = received.firstIndex(of: 0x0A) { return Data(received[..<newline]) }
            } else if count == 0 {
                return received.isEmpty ? nil : received
            } else if errno != EINTR && errno != EAGAIN {
                return nil
            }
        }
    }
}

/// Answers one pending request: writes a single JSON line to the hook that is waiting, then closes the connection.
public final class Responder: @unchecked Sendable {
    fileprivate let connection: ClientConnection
    fileprivate init(_ connection: ClientConnection) { self.connection = connection }

    /// Runs if the hook goes away before we answered: it timed out, was killed, or the user answered in the agent's own terminal.
    /// Set it inside the event handler, before returning.
    public var onDisconnect: (@Sendable () -> Void)? {
        get { connection.peerGoneHandler }
        set { connection.peerGoneHandler = newValue }
    }

    /// Sends the answer and closes the connection. Only the first call has any effect.
    public func reply(_ reply: DecisionReply) {
        guard let data = try? JSONEncoder().encode(reply) else { connection.close(); return }
        connection.send(data)
    }
}

/// One accepted connection. All work happens on the server's serial queue.
final class ClientConnection: @unchecked Sendable {
    private let fd: Int32
    private let queue: DispatchQueue
    private var source: DispatchSourceRead?
    private var buffer = Data()
    private var delivered = false
    private var finished = false
    private var answered = false
    private let lock = NSLock()
    private var _peerGoneHandler: (@Sendable () -> Void)?
    private let deliver: (Data, ClientConnection) -> Void
    var expectsReply = false
    var onFinished: ((ClientConnection) -> Void)?

    var peerGoneHandler: (@Sendable () -> Void)? {
        get { lock.lock(); defer { lock.unlock() }; return _peerGoneHandler }
        set { lock.lock(); _peerGoneHandler = newValue; lock.unlock() }
    }

    private let idleTimeout: TimeInterval

    init(fd: Int32, queue: DispatchQueue, idleTimeout: TimeInterval = 10, deliver: @escaping (Data, ClientConnection) -> Void) {
        self.fd = fd
        self.queue = queue
        self.idleTimeout = idleTimeout
        self.deliver = deliver
    }

    func start() {
        // A hook speaks at once. A connection that stays silent is holding a descriptor for nothing: drop it.
        queue.asyncAfter(deadline: .now() + idleTimeout) { [weak self] in
            guard let self, !self.delivered else { return }
            self.finish(peerGone: false)
        }
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in self?.readAvailable() }
        let descriptor = fd
        source.setCancelHandler { Darwin.close(descriptor) } // not self.close(): that one only finishes the connection
        source.resume()
        self.source = source
    }

    private func readAvailable() {
        var chunk = [UInt8](repeating: 0, count: 65_536)
        let count = read(fd, &chunk, chunk.count)
        if count > 0 {
            // After the first message only EOF matters: it tells us the hook went away.
            guard !delivered else { return }
            buffer.append(chunk, count: count)
            if let newline = buffer.firstIndex(of: 0x0A) {
                deliverMessage(Data(buffer[..<newline]))
            } else if buffer.count > 1_000_000 {
                finish(peerGone: false)
            }
        } else if count == 0 {
            if !delivered, !buffer.isEmpty { deliverMessage(buffer) } // a sender that closed without a newline
            finish(peerGone: true)
        } else if errno != EINTR && errno != EAGAIN {
            finish(peerGone: true)
        }
    }

    private func deliverMessage(_ data: Data) {
        delivered = true
        buffer.removeAll()
        deliver(data, self)
        if !expectsReply { finish(peerGone: false) }
    }

    func send(_ data: Data) {
        queue.async { [self] in
            lock.lock()
            let proceed = !finished && !answered
            answered = true
            lock.unlock()
            guard proceed else { return }
            _ = UnixSocket.writeAll(fd, UnixSocket.framed(data))
            finish(peerGone: false)
        }
    }

    func close() {
        queue.async { [self] in finish(peerGone: false) }
    }

    /// Must run on the server queue.
    func finish(peerGone: Bool) {
        lock.lock()
        if finished { lock.unlock(); return }
        finished = true
        let callback = (peerGone && !answered) ? _peerGoneHandler : nil
        lock.unlock()
        source?.cancel() // the cancel handler closes the descriptor
        source = nil
        callback?()
        onFinished?(self)
    }
}

public final class SocketServer: @unchecked Sendable {
    /// `responder` is non-nil when the hook is waiting for an answer.
    public typealias Handler = @Sendable (AgentEvent, Responder?) -> Void

    private let url: URL
    private let queue = DispatchQueue(label: "island.socket")
    private var source: DispatchSourceRead?
    private var connections: [ObjectIdentifier: ClientConnection] = [:]
    private let onEvent: Handler
    private let idleTimeout: TimeInterval
    /// More than this many open connections at once are refused: each one holds a file descriptor (an app launched from the
    /// Finder starts with only 256), and a flood must not starve the rest of the app.
    static let maxConnections = 160

    public init(url: URL = IslandPaths.socketURL, idleTimeout: TimeInterval = 10, onEvent: @escaping Handler) {
        self.url = url
        self.idleTimeout = idleTimeout
        self.onEvent = onEvent
    }

    public func start() throws {
        let folder = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        // A folder that already existed keeps whatever permissions it had: it must be ours, and closed to everyone else.
        let owner = (try? FileManager.default.attributesOfItem(atPath: folder.path))?[.ownerAccountID] as? NSNumber
        guard owner?.uint32Value == geteuid() else { throw POSIXError(.EPERM) }
        chmod(folder.path, 0o700)
        unlink(url.path)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }
        var addr = UnixSocket.address(for: url.path)
        // The socket file is born owner-only: with the usual umask it would exist, readable by others, until the chmod below.
        let previousMask = umask(0o177)
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        umask(previousMask)
        guard bound == 0, listen(fd, 128) == 0 else {
            let code = POSIXError.Code(rawValue: errno) ?? .EIO
            close(fd)
            throw POSIXError(code)
        }
        chmod(url.path, 0o600)
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in self?.acceptOne(on: fd) }
        source.setCancelHandler { close(fd) }
        source.resume()
        self.source = source
    }

    public func stop() {
        queue.sync {
            source?.cancel()
            source = nil
            for connection in Array(connections.values) { connection.finish(peerGone: false) }
            connections.removeAll()
        }
        unlink(url.path)
    }

    private func acceptOne(on listener: Int32) {
        let client = accept(listener, nil, nil)
        guard client >= 0 else { return }
        // Only this user's own programs may talk to us, whatever the file permissions turn out to be.
        var uid: uid_t = 0, gid: gid_t = 0
        guard getpeereid(client, &uid, &gid) == 0, uid == geteuid(), connections.count < Self.maxConnections else {
            Darwin.close(client)
            return
        }
        let connection = ClientConnection(fd: client, queue: queue, idleTimeout: idleTimeout) { [weak self] data, connection in
            self?.handle(data, from: connection)
        }
        connection.onFinished = { [weak self] finished in self?.connections[ObjectIdentifier(finished)] = nil }
        connections[ObjectIdentifier(connection)] = connection
        connection.start()
    }

    private func handle(_ data: Data, from connection: ClientConnection) {
        guard let event = try? AgentEvent.makeDecoder().decode(AgentEvent.self, from: data) else { return }
        if event.permission != nil {
            connection.expectsReply = true
            onEvent(event, Responder(connection))
        } else {
            onEvent(event, nil)
        }
    }
}
