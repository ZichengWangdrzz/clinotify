import Darwin
import Foundation

public enum UnixSocketClient {
    public static func send(
        _ envelope: IPCEnvelope,
        socketPath: String = ApplicationPaths.socketPath,
        waitForResponse: Bool
    ) throws -> IPCResponse? {
        try ApplicationPaths.ensureApplicationSupportDirectory()
        let data = try JSONEncoder.clinotify.encode(envelope)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }
        defer { close(fd) }

        var address = try sockaddrUnix(path: socketPath)
        let connected = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockAddr in
                connect(fd, sockAddr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else { throw POSIXError(.init(rawValue: errno) ?? .ECONNREFUSED) }

        try writeAll(data, to: fd)
        shutdown(fd, SHUT_WR)

        guard waitForResponse else { return nil }
        let responseData = readAll(from: fd)
        guard !responseData.isEmpty else { return nil }
        return try JSONDecoder.clinotify.decode(IPCResponse.self, from: responseData)
    }

    private static func sockaddrUnix(path: String) throws -> sockaddr_un {
        var address = sockaddr_un()
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = path.utf8CString.map { UInt8(bitPattern: $0) }
        guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else {
            throw POSIXError(.ENAMETOOLONG)
        }
        withUnsafeMutableBytes(of: &address.sun_path) { (rawBuffer: UnsafeMutableRawBufferPointer) in
            for index in bytes.indices {
                rawBuffer[index] = bytes[index]
            }
        }
        return address
    }

    private static func writeAll(_ data: Data, to fd: Int32) throws {
        try data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return }
            var sent = 0
            while sent < data.count {
                let result = write(fd, baseAddress.advanced(by: sent), data.count - sent)
                if result < 0 {
                    throw POSIXError(.init(rawValue: errno) ?? .EIO)
                }
                sent += result
            }
        }
    }

    private static func readAll(from fd: Int32) -> Data {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = read(fd, &buffer, buffer.count)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }
}
