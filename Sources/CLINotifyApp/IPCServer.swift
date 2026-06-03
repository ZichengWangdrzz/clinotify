import CLINotifyShared
import Darwin
import Foundation

final class IPCServer {
    private let registry: SessionRegistry
    private let overrideStore: SessionOverrideStore
    private let eventRouter: EventRouter
    private var serverFD: Int32 = -1
    private var source: DispatchSourceRead?
    private let queue = DispatchQueue(label: "app.clinotify.ipc-server")

    init(registry: SessionRegistry, overrideStore: SessionOverrideStore, eventRouter: EventRouter) {
        self.registry = registry
        self.overrideStore = overrideStore
        self.eventRouter = eventRouter
    }

    func start() throws {
        try ApplicationPaths.ensureApplicationSupportDirectory()
        unlink(ApplicationPaths.socketPath)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }
        serverFD = fd

        var address = try sockaddrUnix(path: ApplicationPaths.socketPath)
        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockAddr in
                bind(fd, sockAddr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindResult == 0 else { throw POSIXError(.init(rawValue: errno) ?? .EADDRINUSE) }
        guard listen(fd, 64) == 0 else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }

        let flags = fcntl(fd, F_GETFL, 0)
        _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)

        let readSource = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        readSource.setEventHandler { [weak self] in self?.acceptConnections() }
        readSource.setCancelHandler { close(fd) }
        readSource.resume()
        source = readSource
    }

    func stop() {
        source?.cancel()
        source = nil
        if serverFD >= 0 {
            close(serverFD)
            serverFD = -1
        }
        unlink(ApplicationPaths.socketPath)
    }

    private func acceptConnections() {
        while true {
            let clientFD = accept(serverFD, nil, nil)
            if clientFD < 0 {
                if errno == EWOULDBLOCK || errno == EAGAIN { return }
                return
            }
            handle(clientFD: clientFD)
        }
    }

    private func handle(clientFD: Int32) {
        let data = readAll(from: clientFD)
        let response: IPCResponse
        do {
            let envelope = try JSONDecoder.clinotify.decode(IPCEnvelope.self, from: data)
            response = try handle(envelope)
        } catch {
            response = IPCResponse(ok: false, message: error.localizedDescription)
        }

        if let responseData = try? JSONEncoder.clinotify.encode(response) {
            _ = try? writeAll(responseData, to: clientFD)
        }
        close(clientFD)
    }

    private func handle(_ envelope: IPCEnvelope) throws -> IPCResponse {
        switch envelope.command {
        case .register:
            guard let registration = envelope.registration else {
                return IPCResponse(ok: false, message: "Missing registration.")
            }
            try registry.register(registration)
            return IPCResponse(ok: true, message: "Registered \(registration.tty).")
        case .unregister:
            guard let tty = envelope.tty else {
                return IPCResponse(ok: false, message: "Missing tty.")
            }
            try registry.unregister(tty: tty)
            // Prune the per-terminal override exactly when its session unregisters.
            try? overrideStore.clear(tty: tty)
            return IPCResponse(ok: true, message: "Unregistered \(tty).")
        case .list:
            return IPCResponse(ok: true, sessions: registry.allSessions())
        case .event:
            guard let event = envelope.event else {
                return IPCResponse(ok: false, message: "Missing event.")
            }
            // Routing touches AppKit/AVFoundation (overlay, sound, system notification). This handler
            // runs on the background IPC queue, so hop to the main thread before any UI work — off-main
            // AppKit is undefined behavior. The reply ("received") is sent immediately below.
            DispatchQueue.main.async { [eventRouter] in
                eventRouter.route(event, bypassRegistry: envelope.bypassRegistry)
            }
            return IPCResponse(ok: true)
        case .dismiss:
            guard let session = envelope.session, !session.isEmpty else {
                return IPCResponse(ok: false, message: "Missing session.")
            }
            DispatchQueue.main.async { [eventRouter] in
                eventRouter.dismiss(sessionID: session)
            }
            return IPCResponse(ok: true, message: "Dismissed \(session).")
        case .setOverride:
            guard let tty = envelope.tty else {
                return IPCResponse(ok: false, message: "Missing tty.")
            }
            guard let delta = envelope.override else {
                return IPCResponse(ok: false, message: "Missing override.")
            }
            let merged = try overrideStore.merge(tty: tty, delta: delta)
            return IPCResponse(ok: true, message: "Updated override for \(tty).", override: merged)
        case .getOverride:
            guard let tty = envelope.tty else {
                return IPCResponse(ok: false, message: "Missing tty.")
            }
            return IPCResponse(ok: true, override: overrideStore.override(for: tty) ?? SessionPreferenceOverride())
        }
    }

    private func sockaddrUnix(path: String) throws -> sockaddr_un {
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

    private func readAll(from fd: Int32) -> Data {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = read(fd, &buffer, buffer.count)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }

    private func writeAll(_ data: Data, to fd: Int32) throws {
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
}
