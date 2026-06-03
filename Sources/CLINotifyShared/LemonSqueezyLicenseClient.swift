import Foundation

public enum LemonSqueezyLicenseError: Error, Equatable {
    case invalidResponse
    case activationRejected(String)
    case missingCachedLicenseKey
}

public struct LemonSqueezyLicenseClient: Sendable {
    public var baseURL: URL
    private let session: URLSession

    public init(
        baseURL: URL = URL(string: "https://api.lemonsqueezy.com")!,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.session = session
    }

    public func activate(licenseKey: String, instanceName: String) async throws -> LemonSqueezyLicenseResponse {
        try await post(
            path: "/v1/licenses/activate",
            form: [
                "license_key": licenseKey,
                "instance_name": instanceName
            ]
        )
    }

    public func validate(licenseKey: String, instanceID: String?) async throws -> LemonSqueezyLicenseResponse {
        var form = ["license_key": licenseKey]
        if let instanceID, !instanceID.isEmpty {
            form["instance_id"] = instanceID
        }
        return try await post(path: "/v1/licenses/validate", form: form)
    }

    private func post(path: String, form: [String: String]) async throws -> LemonSqueezyLicenseResponse {
        let normalizedPath = path.hasPrefix("/") ? String(path.dropFirst()) : path
        var request = URLRequest(url: baseURL.appendingPathComponent(normalizedPath))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = form
            .map { key, value in "\(Self.escape(key))=\(Self.escape(value))" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw LemonSqueezyLicenseError.invalidResponse
        }
        return try JSONDecoder().decode(LemonSqueezyLicenseResponse.self, from: data)
    }

    private static func escape(_ value: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}

public struct LemonSqueezyLicenseResponse: Codable, Equatable, Sendable {
    public var activated: Bool?
    public var valid: Bool?
    public var error: String?
    public var licenseKey: LemonSqueezyLicenseKey
    public var instance: LemonSqueezyLicenseInstance?
    public var meta: LemonSqueezyLicenseMeta?

    public init(
        activated: Bool? = nil,
        valid: Bool? = nil,
        error: String? = nil,
        licenseKey: LemonSqueezyLicenseKey,
        instance: LemonSqueezyLicenseInstance? = nil,
        meta: LemonSqueezyLicenseMeta? = nil
    ) {
        self.activated = activated
        self.valid = valid
        self.error = error
        self.licenseKey = licenseKey
        self.instance = instance
        self.meta = meta
    }

    public var activatedOrValid: Bool {
        activated ?? valid ?? false
    }

    enum CodingKeys: String, CodingKey {
        case activated
        case valid
        case error
        case licenseKey = "license_key"
        case instance
        case meta
    }
}

public struct LemonSqueezyLicenseKey: Codable, Equatable, Sendable {
    public var id: Int?
    public var status: String
    public var key: String?
    public var activationLimit: Int?
    public var activationUsage: Int?
    public var createdAt: String?
    public var expiresAt: String?

    public init(
        id: Int? = nil,
        status: String,
        key: String? = nil,
        activationLimit: Int? = nil,
        activationUsage: Int? = nil,
        createdAt: String? = nil,
        expiresAt: String? = nil
    ) {
        self.id = id
        self.status = status
        self.key = key
        self.activationLimit = activationLimit
        self.activationUsage = activationUsage
        self.createdAt = createdAt
        self.expiresAt = expiresAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case status
        case key
        case activationLimit = "activation_limit"
        case activationUsage = "activation_usage"
        case createdAt = "created_at"
        case expiresAt = "expires_at"
    }
}

public struct LemonSqueezyLicenseInstance: Codable, Equatable, Sendable {
    public var id: String
    public var name: String?
    public var createdAt: String?

    public init(id: String, name: String? = nil, createdAt: String? = nil) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case createdAt = "created_at"
    }
}

public struct LemonSqueezyLicenseMeta: Codable, Equatable, Sendable {
    public var productID: Int?
    public var productName: String?
    public var variantID: Int?
    public var variantName: String?

    public init(productID: Int? = nil, productName: String? = nil, variantID: Int? = nil, variantName: String? = nil) {
        self.productID = productID
        self.productName = productName
        self.variantID = variantID
        self.variantName = variantName
    }

    enum CodingKeys: String, CodingKey {
        case productID = "product_id"
        case productName = "product_name"
        case variantID = "variant_id"
        case variantName = "variant_name"
    }
}
