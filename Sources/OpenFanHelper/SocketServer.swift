import Foundation
import OpenFanCore

struct SocketServerError: Error, CustomStringConvertible {
    let description: String
}

/// Writes every byte or reports failure. The fd is non-blocking, so a peer that never reads gets
/// dropped instead of stalling the daemon queue.
private func writeAll(_ fd: Int32, _ bytes: [UInt8]) -> Bool {
    var offset = 0
    while offset < bytes.count {
        let written = bytes[offset...].withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
        if written > 0 {
            offset += written
        } else if written < 0 && errno == EINTR {
            continue
        } else {
            return false
        }
    }
    return true
}

private func errnoText() -> String {
    String(cString: strerror(errno))
}

/// One authorized client. All members are touched on the daemon queue only.
final class ClientConnection {
    let id: Int
    let uid: uid_t
    fileprivate let fd: Int32
    fileprivate var source: DispatchSourceRead?
    fileprivate var buffer: [UInt8] = []
    fileprivate(set) var isClosed = false
    fileprivate weak var server: SocketServer?

    fileprivate init(id: Int, uid: uid_t, fd: Int32, server: SocketServer) {
        self.id = id
        self.uid = uid
        self.fd = fd
        self.server = server
    }

    /// Sends one reply line. A failed write closes the connection.
    func send(_ line: String) {
        guard !isClosed else { return }
        if !writeAll(fd, Array((line + "\n").utf8)) {
            server?.close(self, reason: "write failed")
        }
    }

    func close(_ reason: String) {
        server?.close(self, reason: reason)
    }
}

/// Unix-domain socket front end: accept, peer-uid gate, line framing and command parsing.
/// Everything runs on the queue handed to init.
final class SocketServer {
    /// Bounds memory and keeps accept() far away from fd exhaustion.
    private static let maxConnections = 32

    private let path: String
    private let allowedUIDs: Set<uid_t>
    private let queue: DispatchQueue
    private var listenFD: Int32 = -1
    private var acceptSource: DispatchSourceRead?
    private var nextID = 1
    private var connections: [Int: ClientConnection] = [:]

    /// A fully parsed command from an authorized peer.
    var onCommand: ((ClientConnection, HelperCommand) -> Void)?
    /// Fired exactly once per accepted connection, after it is closed.
    var onClose: ((ClientConnection, String) -> Void)?

    init(path: String, allowedUIDs: Set<uid_t>, queue: DispatchQueue) {
        self.path = path
        self.allowedUIDs = allowedUIDs
        self.queue = queue
    }

    func start() throws {
        let capacity = MemoryLayout.size(ofValue: sockaddr_un().sun_path)
        guard path.utf8.count < capacity else {
            throw SocketServerError(description: "socket path is too long (\(path.utf8.count) bytes, limit \(capacity - 1)): \(path)")
        }

        unlink(path)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw SocketServerError(description: "socket() failed: \(errnoText())")
        }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        withUnsafeMutableBytes(of: &address.sun_path) { raw in
            for (offset, byte) in path.utf8.enumerated() { raw[offset] = byte }
            raw[path.utf8.count] = 0
        }
        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0 else {
            let reason = errnoText()
            Darwin.close(fd)
            throw SocketServerError(description: "cannot bind \(path): \(reason)")
        }
        // The socket is world-connectable on purpose; getpeereid is the actual gate.
        guard chmod(path, 0o666) == 0 else {
            let reason = errnoText()
            Darwin.close(fd)
            unlink(path)
            throw SocketServerError(description: "chmod 0666 \(path) failed: \(reason)")
        }
        guard listen(fd, 8) == 0 else {
            let reason = errnoText()
            Darwin.close(fd)
            unlink(path)
            throw SocketServerError(description: "listen() failed: \(reason)")
        }
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
        _ = fcntl(fd, F_SETFD, FD_CLOEXEC)

        listenFD = fd
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in self?.acceptPending() }
        source.setCancelHandler { Darwin.close(fd) }
        source.resume()
        acceptSource = source
    }

    /// Stops accepting and removes the socket file. Open connections die with the process.
    func stop() {
        acceptSource?.cancel()
        acceptSource = nil
        unlink(path)
    }

    // MARK: Accept

    private func acceptPending() {
        while true {
            let fd = accept(listenFD, nil, nil)
            if fd < 0 {
                if errno == EINTR { continue }
                return
            }
            adopt(fd)
        }
    }

    private func adopt(_ fd: Int32) {
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
        _ = fcntl(fd, F_SETFD, FD_CLOEXEC)
        var one: Int32 = 1
        _ = setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))

        var uid: uid_t = 0
        var gid: gid_t = 0
        guard getpeereid(fd, &uid, &gid) == 0 else {
            logLine("connection refused: getpeereid failed (\(errnoText()))")
            Darwin.close(fd)
            return
        }
        guard allowedUIDs.contains(uid) else {
            _ = writeAll(fd, Array("ERR unauthorized\n".utf8))
            logLine("connection refused: uid \(uid) is not allowed")
            Darwin.close(fd)
            return
        }
        guard connections.count < SocketServer.maxConnections else {
            _ = writeAll(fd, Array("ERR busy\n".utf8))
            logLine("connection refused: \(SocketServer.maxConnections) connections already open")
            Darwin.close(fd)
            return
        }

        let connection = ClientConnection(id: nextID, uid: uid, fd: fd, server: self)
        nextID += 1
        connections[connection.id] = connection
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self, weak connection] in
            guard let self, let connection else { return }
            self.readable(connection)
        }
        source.setCancelHandler { Darwin.close(fd) }
        connection.source = source
        source.resume()
        logLine("connection \(connection.id) accepted (uid \(uid))")
    }

    // MARK: Read and framing

    private func readable(_ connection: ClientConnection) {
        guard !connection.isClosed else { return }
        var chunk = [UInt8](repeating: 0, count: 1024)
        let count = read(connection.fd, &chunk, chunk.count)
        if count > 0 {
            connection.buffer.append(contentsOf: chunk[0..<count])
            drain(connection)
        } else if count == 0 {
            close(connection, reason: "peer closed")
        } else if errno != EAGAIN && errno != EINTR {
            close(connection, reason: "read error: \(errnoText())")
        }
    }

    /// Splits the buffer on 0x0A. Several lines per read and partial lines both work; a line longer than
    /// HelperPaths.maxLineBytes (complete or still growing) gets "ERR too long" and the connection closes.
    private func drain(_ connection: ClientConnection) {
        while !connection.isClosed, let newline = connection.buffer.firstIndex(of: 0x0A) {
            let lineBytes = Array(connection.buffer[connection.buffer.startIndex..<newline])
            connection.buffer.removeSubrange(connection.buffer.startIndex...newline)
            if lineBytes.count > HelperPaths.maxLineBytes {
                rejectTooLong(connection)
                return
            }
            let line = String(decoding: lineBytes, as: UTF8.self)
            do {
                let command = try HelperCommand.parse(line)
                onCommand?(connection, command)
            } catch {
                connection.send("ERR \(error)")
            }
        }
        if !connection.isClosed, connection.buffer.count > HelperPaths.maxLineBytes {
            rejectTooLong(connection)
        }
    }

    private func rejectTooLong(_ connection: ClientConnection) {
        connection.send("ERR too long")
        close(connection, reason: "line longer than \(HelperPaths.maxLineBytes) bytes")
    }

    fileprivate func close(_ connection: ClientConnection, reason: String) {
        guard !connection.isClosed else { return }
        connection.isClosed = true
        connection.source?.cancel()
        connection.source = nil
        connections[connection.id] = nil
        logLine("connection \(connection.id) closed (\(reason))")
        onClose?(connection, reason)
    }
}
