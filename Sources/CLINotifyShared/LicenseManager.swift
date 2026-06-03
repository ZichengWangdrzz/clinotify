import Foundation

public enum LicenseState: String, Codable, Equatable, Sendable {
    case free
    case activeSubscription
    case lifetime
    case expired
}

public struct LicenseCapabilities: Equatable, Sendable {
    public let mascotAnimation: Bool
    public let sessionBubble: Bool
    public let customSounds: Bool
    public let displaySelection: Bool

    // The base overlay — anchored glass + default animation + default bubble (with the session
    // label) + default sound on the primary display — is free for everyone. Only swappable premium
    // content (animation/bubble skins, premium catalog sounds, gated per-entry by ownership),
    // user-supplied custom sound files (`customSounds`), and multi-display selection
    // (`displaySelection`) require a paid license.
    public static let free = LicenseCapabilities(
        mascotAnimation: true,
        sessionBubble: true,
        customSounds: false,
        displaySelection: false
    )

    public static let paid = LicenseCapabilities(
        mascotAnimation: true,
        sessionBubble: true,
        customSounds: true,
        displaySelection: true
    )
}

public struct LicenseRecord: Codable, Equatable, Sendable {
    public var state: LicenseState
    public var licenseKey: String?
    public var licenseKeyTail: String?
    public var instanceID: String?
    public var activatedAt: Date?
    public var expiresAt: Date?
    public var nextCheckAt: Date?

    public init(
        state: LicenseState = .free,
        licenseKey: String? = nil,
        licenseKeyTail: String? = nil,
        instanceID: String? = nil,
        activatedAt: Date? = nil,
        expiresAt: Date? = nil,
        nextCheckAt: Date? = nil
    ) {
        self.state = state
        self.licenseKey = licenseKey
        self.licenseKeyTail = licenseKeyTail
        self.instanceID = instanceID
        self.activatedAt = activatedAt
        self.expiresAt = expiresAt
        self.nextCheckAt = nextCheckAt
    }
}

public final class LicenseManager {
    public private(set) var record: LicenseRecord
    private let cacheURL: URL

    public init(cacheURL: URL = ApplicationPaths.licenseURL) {
        self.cacheURL = cacheURL
        self.record = Self.load(cacheURL: cacheURL)
    }

    public var capabilities: LicenseCapabilities {
        switch record.state {
        case .activeSubscription, .lifetime:
            return .paid
        case .free, .expired:
            return .free
        }
    }

    public func reloadFromDisk() {
        record = Self.load(cacheURL: cacheURL)
    }

    public func cache(_ record: LicenseRecord) throws {
        try ApplicationPaths.ensureApplicationSupportDirectory()
        let data = try JSONEncoder.clinotify.encode(record)
        try data.write(to: cacheURL, options: .atomic)
        self.record = record
    }

    public func activateCached(key: String, state: LicenseState) throws {
        let now = Date()
        let tail = String(key.suffix(6))
        try cache(LicenseRecord(
            state: state,
            licenseKey: key,
            licenseKeyTail: tail.isEmpty ? nil : tail,
            activatedAt: now,
            expiresAt: state == .activeSubscription ? Calendar.current.date(byAdding: .month, value: 1, to: now) : nil,
            nextCheckAt: Calendar.current.date(byAdding: .day, value: 3, to: now)
        ))
    }

    public func activateOnline(
        key: String,
        instanceName: String,
        client: LemonSqueezyLicenseClient = LemonSqueezyLicenseClient()
    ) async throws {
        let response = try await client.activate(licenseKey: key, instanceName: instanceName)
        guard response.activated == true else {
            throw LemonSqueezyLicenseError.activationRejected(response.error ?? "Activation failed.")
        }
        try cache(Self.record(from: response, licenseKey: key, now: Date()))
    }

    public func validateOnline(client: LemonSqueezyLicenseClient = LemonSqueezyLicenseClient()) async throws {
        guard let licenseKey = record.licenseKey else {
            throw LemonSqueezyLicenseError.missingCachedLicenseKey
        }
        let response = try await client.validate(licenseKey: licenseKey, instanceID: record.instanceID)
        guard response.valid == true else {
            try cache(LicenseRecord(state: .expired, licenseKey: licenseKey, licenseKeyTail: record.licenseKeyTail))
            return
        }
        try cache(Self.record(from: response, licenseKey: licenseKey, now: Date()))
    }

    public func resetToFree() throws {
        try cache(LicenseRecord(state: .free))
    }

    private static func load(cacheURL: URL) -> LicenseRecord {
        guard let data = try? Data(contentsOf: cacheURL),
              let record = try? JSONDecoder.clinotify.decode(LicenseRecord.self, from: data) else {
            return LicenseRecord()
        }
        return record
    }

    public static func record(from response: LemonSqueezyLicenseResponse, licenseKey: String, now: Date) -> LicenseRecord {
        let expiresAt = response.licenseKey.expiresAt.flatMap(DateParser.parse)
        let state: LicenseState
        if response.licenseKey.status == "expired" {
            state = .expired
        } else if expiresAt == nil {
            state = .lifetime
        } else if let expiresAt, expiresAt < now {
            state = .expired
        } else {
            state = .activeSubscription
        }
        return LicenseRecord(
            state: state,
            licenseKey: licenseKey,
            licenseKeyTail: String(licenseKey.suffix(6)),
            instanceID: response.instance?.id,
            activatedAt: response.instance?.createdAt.flatMap(DateParser.parse) ?? now,
            expiresAt: expiresAt,
            nextCheckAt: Calendar.current.date(byAdding: .day, value: 3, to: now)
        )
    }
}

private enum DateParser {
    static func parse(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) {
            return date
        }
        return ISO8601DateFormatter().date(from: value)
    }
}
