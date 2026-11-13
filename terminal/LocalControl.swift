import Foundation
import Darwin

enum ControlError: LocalizedError {
    case invalid(String)
    var errorDescription: String? { if case .invalid(let text) = self { return text }; return nil }
}

func socketAddress(_ path: String) throws -> sockaddr_un {
    var address = sockaddr_un()
    let bytes = Array(path.utf8) + [0]
    guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else { throw ControlError.invalid("Socket path too long") }
    address.sun_family = sa_family_t(AF_UNIX)
    address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
    withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: bytes) }
    return address
}

func socketTimeout(_ fd: Int32) {
    var timeout = timeval(tv_sec: 10, tv_usec: 0)
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
    setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
    var yes: Int32 = 1
    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &yes, socklen_t(MemoryLayout<Int32>.size))
}

func readControl(_ fd: Int32) throws -> Data {
    var data = Data(), chunk = [UInt8](repeating: 0, count: 8192)
    while data.count <= 1_048_576 {
        let count = Darwin.read(fd, &chunk, chunk.count)
        if count < 0 && errno == EINTR { continue }
        guard count > 0 else { throw ControlError.invalid("Connection ended or timed out") }
        if let end = chunk.prefix(count).firstIndex(of: 10) {
            guard data.count + end <= 1_048_576 else { throw ControlError.invalid("Request too large") }
            data.append(contentsOf: chunk[..<end]); return data
        }
        data.append(contentsOf: chunk.prefix(count))
    }
    throw ControlError.invalid("Request too large")
}

func writeControl(_ fd: Int32, _ data: Data) throws {
    var framed = data; framed.append(10)
    try framed.withUnsafeBytes { bytes in
        var offset = 0
        while offset < bytes.count {
            let count = Darwin.write(fd, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
            if count < 0 && errno == EINTR { continue }
            guard count > 0 else { throw ControlError.invalid("Could not write response") }
            offset += count
        }
    }
}

func processAncestors(_ pid: Int32) -> Set<Int32> {
    var current = pid, result = Set<Int32>()
    while current > 1, result.count < 64, result.insert(current).inserted {
        var info = proc_bsdinfo()
        guard proc_pidinfo(current, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdinfo>.size)) == MemoryLayout<proc_bsdinfo>.size else { break }
        current = Int32(info.pbi_ppid)
    }
    return result
}

final class LocalControl: @unchecked Sendable {
    let path: String
    private let directory: String
    private let source: DispatchSourceRead

    init(handler: @escaping @Sendable (Data) async -> Data) throws {
        directory = "/tmp/boterm-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        path = directory + "/control.sock"
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { try? FileManager.default.removeItem(atPath: directory); throw ControlError.invalid("Could not create local control socket") }
        var address = try socketAddress(path)
        let bound = withUnsafePointer(to: &address) { p in
            p.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard bound == 0, chmod(path, 0o600) == 0, listen(fd, 8) == 0 else {
            Darwin.close(fd); try? FileManager.default.removeItem(atPath: directory)
            throw ControlError.invalid("Could not start local control")
        }
        _ = fcntl(fd, F_SETFD, FD_CLOEXEC)
        _ = fcntl(fd, F_SETFL, O_NONBLOCK)
        source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: DispatchQueue(label: "boterm.control"))
        source.setEventHandler {
            let client = accept(fd, nil, nil)
            guard client >= 0 else { return }
            _ = fcntl(client, F_SETFD, FD_CLOEXEC)
            _ = fcntl(client, F_SETFL, 0)
            socketTimeout(client)
            // Serial bounded requests avoid an unbounded queue of client tasks.
            defer { Darwin.close(client) }
            do {
                let data = try readControl(client)
                var peer: Int32 = 0, size = socklen_t(MemoryLayout<Int32>.size)
                guard getsockopt(client, SOL_LOCAL, LOCAL_PEERPID, &peer, &size) == 0,
                      var object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw ControlError.invalid("Invalid local peer or request") }
                object["peerPID"] = peer
                let request = try JSONSerialization.data(withJSONObject: object)
                let response = ControlResponse()
                let done = DispatchSemaphore(value: 0)
                Task { response.data = await handler(request); done.signal() }
                guard done.wait(timeout: .now() + 10) == .success else { return }
                try writeControl(client, response.data)
            } catch {
                let data = try? JSONSerialization.data(withJSONObject: ["error": error.localizedDescription])
                if let data { try? writeControl(client, data) }
            }
        }
        source.setCancelHandler { Darwin.close(fd) }
        source.resume()
    }

    deinit { source.cancel(); try? FileManager.default.removeItem(atPath: directory) }
}

private final class ControlResponse: @unchecked Sendable { var data = Data() }
