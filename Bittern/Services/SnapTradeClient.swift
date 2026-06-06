//
//  SnapTradeClient.swift
//  Bittern
//

import Foundation
import CryptoKit

enum NetworkServiceError: LocalizedError {
    case invalidURL
    case emptySymbols
    case httpStatus(Int, String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            "The service URL is invalid."
        case .emptySymbols:
            "There are no symbols to quote."
        case .httpStatus(let status, let body):
            "Request failed with HTTP \(status). \(body)"
        }
    }
}

struct SnapTradeClient {
    private let credentials: SnapTradeCredentials
    private let baseURL = URL(string: "https://api.snaptrade.com/api/v1")!
    private let session: URLSession

    init(credentials: SnapTradeCredentials, session: URLSession = .shared) {
        self.credentials = credentials.sanitized
        self.session = session
    }

    func registerUser(userId: String) async throws -> SnapTradeRegisteredUserDTO {
        let body = SnapTradeRegisterUserRequestDTO(userId: userId)
        let data = try await request(
            method: "POST",
            path: "/snapTrade/registerUser",
            queryItems: [],
            body: body
        )
        do {
            return try JSONDecoder().decode(SnapTradeRegisteredUserDTO.self, from: data)
        } catch {
            let bodyPreview = String(data: data, encoding: .utf8) ?? "<not UTF-8>"
            throw NetworkServiceError.httpStatus(
                -1,
                "Decoding registerUser response failed. Body: \(bodyPreview.prefix(500))"
            )
        }
    }

    func listAccounts() async throws -> [SnapTradeAccountDTO] {
        let data = try await request(
            path: "/accounts",
            queryItems: userQueryItems
        )
        return try JSONDecoder().decode([SnapTradeAccountDTO].self, from: data)
    }

    func listConnections() async throws -> [SnapTradeConnectionDTO] {
        let data = try await request(
            path: "/authorizations",
            queryItems: userQueryItems
        )
        return try JSONDecoder().decode([SnapTradeConnectionDTO].self, from: data)
    }

    func listAccounts(connectionID: String) async throws -> [SnapTradeAccountDTO] {
        let data = try await request(
            path: "/authorizations/\(connectionID)/accounts",
            queryItems: userQueryItems
        )
        return try JSONDecoder().decode([SnapTradeAccountDTO].self, from: data)
    }

    func listPositions(accountID: String) async throws -> [SnapTradePositionDTO] {
        let data = try await request(
            path: "/accounts/\(accountID)/positions/all",
            queryItems: userQueryItems
        )
        let response = try JSONDecoder().decode(SnapTradePositionsResponseDTO.self, from: data)
        return response.positions
    }

    func listActivities(accountID: String, types: [String]) async throws -> [SnapTradeActivityDTO] {
        let limit = 1000
        var offset = 0
        var result: [SnapTradeActivityDTO] = []

        while true {
            var queryItems = userQueryItems + [
                URLQueryItem(name: "limit", value: "\(limit)"),
                URLQueryItem(name: "offset", value: "\(offset)")
            ]

            if !types.isEmpty {
                queryItems.append(URLQueryItem(name: "type", value: types.joined(separator: ",")))
            }

            let data = try await request(
                path: "/accounts/\(accountID)/activities",
                queryItems: queryItems
            )
            let page = try JSONDecoder().decode(SnapTradeActivitiesResponseDTO.self, from: data)
            result.append(contentsOf: page.activities)

            offset += page.activities.count
            if page.activities.count < limit {
                break
            }

            if let total = page.total, offset >= total {
                break
            }
        }

        return result
    }

    func connectionPortalURL(darkMode: Bool) async throws -> URL {
        let body = SnapTradeConnectionPortalRequestDTO(
            connectionType: "read",
            showCloseButton: true,
            darkMode: darkMode,
            connectionPortalVersion: "v4"
        )
        let data = try await request(
            method: "POST",
            path: "/snapTrade/login",
            queryItems: userQueryItems,
            body: body
        )
        let response = try JSONDecoder().decode(SnapTradeConnectionPortalResponseDTO.self, from: data)
        guard let url = URL(string: response.redirectURI) else {
            throw NetworkServiceError.invalidURL
        }
        return url
    }

    private func request(path: String, queryItems: [URLQueryItem]) async throws -> Data {
        try await request(
            method: "GET",
            path: path,
            queryItems: queryItems,
            bodyData: nil,
            signatureContent: nil
        )
    }

    private func request<Body: Encodable>(
        method: String,
        path: String,
        queryItems: [URLQueryItem],
        body: Body
    ) async throws -> Data {
        let bodyData = try JSONEncoder().encode(body)
        let signatureContent = try JSONSerialization.jsonObject(with: bodyData)
        return try await request(
            method: method,
            path: path,
            queryItems: queryItems,
            bodyData: bodyData,
            signatureContent: signatureContent
        )
    }

    private func request(
        method: String,
        path: String,
        queryItems: [URLQueryItem],
        bodyData: Data?,
        signatureContent: Any?
    ) async throws -> Data {
        let normalizedPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        var components = URLComponents(
            url: baseURL.appendingPathComponent(normalizedPath),
            resolvingAgainstBaseURL: false
        )
        let timestamp = String(Int(Date().timeIntervalSince1970))
        components?.queryItems = queryItems + [
            URLQueryItem(name: "clientId", value: credentials.clientId),
            URLQueryItem(name: "timestamp", value: timestamp)
        ]

        guard let url = components?.url else {
            throw NetworkServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let bodyData {
            request.httpBody = bodyData
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        request.setValue(
            try signature(
                path: "/api/v1/\(normalizedPath)",
                query: components?.percentEncodedQuery ?? "",
                content: signatureContent
            ),
            forHTTPHeaderField: "Signature"
        )

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            return data
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw NetworkServiceError.httpStatus(httpResponse.statusCode, body)
        }

        return data
    }

    private func signature(path: String, query: String, content: Any?) throws -> String {
        let signaturePayload: [String: Any] = [
            "content": content ?? NSNull(),
            "path": path,
            "query": query
        ]
        let payloadData = try JSONSerialization.data(
            withJSONObject: signaturePayload,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )
        let key = SymmetricKey(data: Data(credentials.consumerKey.utf8))
        let digest = HMAC<SHA256>.authenticationCode(for: payloadData, using: key)
        return Data(digest).base64EncodedString()
    }

    private var userQueryItems: [URLQueryItem] {
        [
            URLQueryItem(name: "userId", value: credentials.userId),
            URLQueryItem(name: "userSecret", value: credentials.userSecret)
        ]
    }
}

struct SnapTradeRegisteredUserDTO: Decodable {
    let userId: String
    let userSecret: String

    // MARK: Coding Keys for both naming conventions

    private enum CamelCaseKeys: String, CodingKey {
        case userId
        case userSecret
    }

    private enum SnakeCaseKeys: String, CodingKey {
        case userId = "user_id"
        case userSecret = "user_secret"
    }

    init(from decoder: Decoder) throws {
        // Try camelCase keys first, then fall back to snake_case.
        // This handles both API response formats without breaking either.
        let container = try decoder.container(keyedBy: CamelCaseKeys.self)

        if let userId = try? container.decode(String.self, forKey: .userId),
           let userSecret = try? container.decode(String.self, forKey: .userSecret) {
            self.userId = userId
            self.userSecret = userSecret
            return
        }

        let snakeContainer = try decoder.container(keyedBy: SnakeCaseKeys.self)
        userId = try snakeContainer.decode(String.self, forKey: .userId)
        userSecret = try snakeContainer.decode(String.self, forKey: .userSecret)
    }
}

private struct SnapTradeRegisterUserRequestDTO: Encodable {
    let userId: String
}

struct SnapTradeConnectionDTO: Decodable, Identifiable {
    let id: String
    let name: String?
    let disabled: Bool?
    let brokerage: SnapTradeBrokerageDTO?

    var displayName: String {
        brokerage?.displayName ?? brokerage?.name ?? name ?? "SnapTrade"
    }

    var logoURL: URL? {
        brokerage?.squareLogoURL ?? brokerage?.logoURL
    }
}

struct SnapTradeBrokerageDTO: Decodable {
    let name: String?
    let displayName: String?
    let logoURL: URL?
    let squareLogoURL: URL?

    enum CodingKeys: String, CodingKey {
        case name
        case displayName = "display_name"
        case logoURL = "aws_s3_logo_url"
        case squareLogoURL = "aws_s3_square_logo_url"
    }
}

private struct SnapTradeConnectionPortalRequestDTO: Encodable {
    let connectionType: String
    let showCloseButton: Bool
    let darkMode: Bool
    let connectionPortalVersion: String
}

private struct SnapTradeConnectionPortalResponseDTO: Decodable {
    let redirectURI: String
}

struct SnapTradeAccountDTO: Decodable {
    let id: String
    let name: String?
    let number: String?
    let institutionName: String?
    let brokerageAuthorization: SnapTradeBrokerageAuthorizationDTO?
    let balance: SnapTradeAccountBalanceDTO?

    var displayName: String {
        name ?? number ?? "Brokerage Account"
    }

    var brokerageAuthorizationID: String? {
        brokerageAuthorization?.id
    }

    var displayInstitution: String {
        institutionName ?? brokerageAuthorization?.name ?? "SnapTrade"
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case number
        case institutionName = "institution_name"
        case brokerageAuthorization = "brokerage_authorization"
        case balance
    }
}

struct SnapTradeBrokerageAuthorizationDTO: Decodable {
    let id: String?
    let name: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let id = try? container.decode(String.self) {
            self.id = id
            self.name = nil
            return
        }

        let keyed = try decoder.container(keyedBy: CodingKeys.self)
        id = try keyed.decodeIfPresent(String.self, forKey: .id)
        name = try keyed.decodeIfPresent(String.self, forKey: .name)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
    }
}

struct SnapTradeAccountBalanceDTO: Decodable {
    let total: SnapTradeMoneyDTO?
}

struct SnapTradeMoneyDTO: Decodable {
    let amount: Double?
    let currency: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        amount = try container.decodeFlexibleDoubleIfPresent(forKey: .amount)
        currency = try container.decodeIfPresent(String.self, forKey: .currency)
    }

    enum CodingKeys: String, CodingKey {
        case amount
        case currency
    }
}

struct SnapTradePositionsResponseDTO: Decodable {
    let positions: [SnapTradePositionDTO]

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let positions = try? container.decode([SnapTradePositionDTO].self) {
            self.positions = positions
            return
        }

        let keyed = try decoder.container(keyedBy: CodingKeys.self)
        if let positions = try keyed.decodeIfPresent([SnapTradePositionDTO].self, forKey: .positions) {
            self.positions = positions
        } else if let data = try keyed.decodeIfPresent([SnapTradePositionDTO].self, forKey: .data) {
            self.positions = data
        } else {
            self.positions = try keyed.decodeIfPresent([SnapTradePositionDTO].self, forKey: .results) ?? []
        }
    }

    enum CodingKeys: String, CodingKey {
        case positions
        case data
        case results
    }
}

struct SnapTradeActivitiesResponseDTO: Decodable {
    let activities: [SnapTradeActivityDTO]
    let total: Int?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let activities = try? container.decode([SnapTradeActivityDTO].self) {
            self.activities = activities
            total = activities.count
            return
        }

        let keyed = try decoder.container(keyedBy: CodingKeys.self)
        if let activities = try keyed.decodeIfPresent([SnapTradeActivityDTO].self, forKey: .data) {
            self.activities = activities
        } else if let activities = try keyed.decodeIfPresent([SnapTradeActivityDTO].self, forKey: .activities) {
            self.activities = activities
        } else {
            self.activities = try keyed.decodeIfPresent([SnapTradeActivityDTO].self, forKey: .results) ?? []
        }
        total = try keyed.decodeIfPresent(SnapTradePaginationDTO.self, forKey: .pagination)?.total
    }

    enum CodingKeys: String, CodingKey {
        case activities
        case data
        case results
        case pagination
    }
}

struct SnapTradePaginationDTO: Decodable {
    let total: Int?
}

struct SnapTradeActivityDTO: Decodable {
    let symbol: String?
    let amount: Double?
    let currency: String?
    let type: String?
    let tradeDate: Date?

    var resolvedSymbol: String? {
        symbol
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        symbol = try container.decodeSymbolTextIfPresent(forKey: .symbol)
        if let rawAmount = try container.decodeFlexibleDoubleIfPresent(forKey: .amount) {
            amount = rawAmount
        } else {
            amount = try container.decodeIfPresent(SnapTradeMoneyDTO.self, forKey: .amount)?.amount
        }
        if let rawCurrency = try container.decodeCurrencyCodeIfPresent(forKey: .currency) {
            currency = rawCurrency
        } else {
            currency = try container.decodeIfPresent(SnapTradeMoneyDTO.self, forKey: .amount)?.currency
        }
        type = try container.decodeIfPresent(String.self, forKey: .type)
        tradeDate = try container.decodeDateIfPresent(forKey: .tradeDate)
    }

    enum CodingKeys: String, CodingKey {
        case symbol
        case amount
        case currency
        case type
        case tradeDate = "trade_date"
    }
}

struct SnapTradePositionDTO: Decodable {
    let id: String?
    let symbol: String?
    let description: String?
    let units: Double?
    let unitsDisplay: String?
    let price: Double?
    let averagePurchasePrice: Double?
    let costBasis: Double?
    let currency: String?
    let instrument: SnapTradeInstrumentDTO?

    var resolvedSymbol: String? {
        symbol ?? instrument?.symbol ?? instrument?.rawSymbol
    }

    var resolvedName: String? {
        description ?? instrument?.description ?? instrument?.symbol
    }

    var resolvedAverageCost: Double? {
        [averagePurchasePrice, costBasis]
            .compactMap { $0 }
            .first { $0 > 0 }
    }

    var resolvedCurrency: String? {
        currency ?? instrument?.currency?.code ?? instrument?.currencyCode
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id)
        symbol = try container.decodeIfPresent(String.self, forKey: .symbol)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        units = try container.decodeFlexibleDoubleIfPresent(forKey: .units)
        unitsDisplay = try container.decodeFlexibleNumberTextIfPresent(forKey: .units)
        price = try container.decodeFlexibleDoubleIfPresent(forKey: .price)
        averagePurchasePrice = try container.decodeFlexibleDoubleIfPresent(forKey: .averagePurchasePrice)
        costBasis = try container.decodeFlexibleDoubleIfPresent(forKey: .costBasis)
        currency = try container.decodeCurrencyCodeIfPresent(forKey: .currency)
        instrument = try container.decodeIfPresent(SnapTradeInstrumentDTO.self, forKey: .instrument)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case symbol
        case description
        case units
        case price
        case averagePurchasePrice = "average_purchase_price"
        case costBasis = "cost_basis"
        case currency
        case instrument
    }
}

struct SnapTradeInstrumentDTO: Decodable {
    let id: String?
    let symbol: String?
    let rawSymbol: String?
    let description: String?
    let currency: SnapTradeInstrumentCurrencyDTO?
    let currencyCode: String?

    enum CodingKeys: String, CodingKey {
        case id
        case symbol
        case rawSymbol = "raw_symbol"
        case description
        case currency
        case currencyCode = "currency_code"
    }
}

struct SnapTradeInstrumentCurrencyDTO: Decodable {
    let code: String?

    init(from decoder: Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        if let code = try? singleValueContainer.decode(String.self) {
            self.code = code
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        code = try container.decodeIfPresent(String.self, forKey: .code)
    }

    enum CodingKeys: String, CodingKey {
        case code
    }
}

extension KeyedDecodingContainer {
    func decodeFlexibleDoubleIfPresent(forKey key: Key) throws -> Double? {
        if let value = try? decodeIfPresent(Double.self, forKey: key) {
            return value
        }

        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return Double(value)
        }

        if let string = try? decodeIfPresent(String.self, forKey: key) {
            return Double(string.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        return nil
    }

    func decodeCurrencyCodeIfPresent(forKey key: Key) throws -> String? {
        if let code = try? decodeIfPresent(String.self, forKey: key) {
            return code
        }

        if let currency = try? decodeIfPresent(SnapTradeInstrumentCurrencyDTO.self, forKey: key) {
            return currency.code
        }

        return nil
    }

    func decodeDateIfPresent(forKey key: Key) throws -> Date? {
        guard let value = try? decodeIfPresent(String.self, forKey: key) else {
            return nil
        }

        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: value) {
            return date
        }

        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value)
    }

    func decodeFlexibleNumberTextIfPresent(forKey key: Key) throws -> String? {
        if let string = try? decodeIfPresent(String.self, forKey: key) {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }

        if let intValue = try? decodeIfPresent(Int.self, forKey: key) {
            return String(intValue)
        }

        if let doubleValue = try? decodeIfPresent(Double.self, forKey: key) {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.usesGroupingSeparator = false
            formatter.maximumFractionDigits = 12
            formatter.minimumFractionDigits = 0
            return formatter.string(from: NSNumber(value: doubleValue)) ?? "\(doubleValue)"
        }

        return nil
    }

    func decodeSymbolTextIfPresent(forKey key: Key) throws -> String? {
        if let string = try? decodeIfPresent(String.self, forKey: key) {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }

        if let instrument = try? decodeIfPresent(SnapTradeInstrumentDTO.self, forKey: key) {
            return instrument.symbol ?? instrument.rawSymbol
        }

        return nil
    }
}
