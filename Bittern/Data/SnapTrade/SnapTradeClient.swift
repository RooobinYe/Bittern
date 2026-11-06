//
//  SnapTradeClient.swift
//  Bittern
//

import Foundation
import CryptoKit
import OSLog

enum SnapTradeError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpStatus(Int, String)
    case decodingFailed(operation: String, reason: String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            "The SnapTrade service URL is invalid."
        case .invalidResponse:
            "SnapTrade returned a non-HTTP response."
        case .httpStatus(let status, let body):
            "SnapTrade request failed with HTTP \(status). \(body)"
        case .decodingFailed(let operation, let reason):
            "SnapTrade's \(operation) response couldn’t be read. \(reason)"
        }
    }
}

struct SnapTradeClient {
    private let credentials: SnapTradeCredentials
    private let baseURL = URL(string: "https://api.snaptrade.com/api/v1")!
    private let session: URLSession
    private let currentDate: @Sendable () -> Date

    init(
        credentials: SnapTradeCredentials,
        session: URLSession = .shared,
        currentDate: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.credentials = credentials.sanitized
        self.session = session
        self.currentDate = currentDate
    }

    func registerUser(userId: String) async throws -> SnapTradeRegisteredUserDTO {
        let body = SnapTradeRegisterUserRequestDTO(userId: userId)
        let data = try await request(
            method: "POST",
            path: "/snapTrade/registerUser",
            queryItems: [],
            body: body
        )
        return try decode(SnapTradeRegisteredUserDTO.self, from: data, operation: "registerUser")
    }

    func listAccounts() async throws -> [SnapTradeAccountDTO] {
        let data = try await request(
            path: "/accounts",
            queryItems: userQueryItems
        )
        return try decode([SnapTradeAccountDTO].self, from: data, operation: "listAccounts")
    }

    func listConnections() async throws -> [SnapTradeConnectionDTO] {
        let data = try await request(
            path: "/authorizations",
            queryItems: userQueryItems
        )
        return try decode([SnapTradeConnectionDTO].self, from: data, operation: "listConnections")
    }

    func listAccounts(connectionID: String) async throws -> [SnapTradeAccountDTO] {
        let data = try await request(
            path: "/authorizations/\(connectionID)/accounts",
            queryItems: userQueryItems
        )
        return try decode([SnapTradeAccountDTO].self, from: data, operation: "listAccounts(connectionID:)")
    }

    func listPositions(accountID: String) async throws -> [SnapTradePositionDTO] {
        let data = try await request(
            path: "/accounts/\(accountID)/positions/all",
            queryItems: userQueryItems
        )
        let response = try decode(SnapTradePositionsResponseDTO.self, from: data, operation: "listPositions")
        let instrumentSummary = response.results.map { position in
            let symbol = position.resolvedSymbol ?? "<missing-symbol>"
            let kind = position.instrument?.kind ?? "<missing-kind>"
            return "\(symbol):\(kind)"
        }
        .joined(separator: ",")
        AppLog.snapTrade.debug(
            "Positions decoded count=\(response.results.count, privacy: .public) instruments=[\(instrumentSummary)]"
        )
        return response.results
    }

    func accountBalanceHistory(accountID: String) async throws -> SnapTradeAccountBalanceHistoryDTO {
        let data = try await request(
            path: "/accounts/\(accountID)/balanceHistory",
            queryItems: userQueryItems
        )
        return try decode(SnapTradeAccountBalanceHistoryDTO.self, from: data, operation: "accountBalanceHistory")
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
            let page = try decode(SnapTradeActivitiesResponseDTO.self, from: data, operation: "listActivities")
            result.append(contentsOf: page.data)

            offset += page.data.count
            if page.data.count < limit {
                break
            }

            if let total = page.pagination?.total, offset >= total {
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
        let response = try decode(SnapTradeConnectionPortalResponseDTO.self, from: data, operation: "connectionPortalURL")
        guard let url = URL(string: response.redirectURI) else {
            throw SnapTradeError.invalidURL
        }
        return url
    }

    private func decode<Value: Decodable>(
        _ type: Value.Type,
        from data: Data,
        operation: String
    ) throws -> Value {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            let bodyPreview = String(data: data, encoding: .utf8) ?? "<not UTF-8>"
            AppLog.snapTrade.error(
                "Decoding \(operation, privacy: .public) failed: \(AppLog.describe(error)) body=\(bodyPreview.prefix(500))"
            )
            throw SnapTradeError.decodingFailed(
                operation: operation,
                reason: AppLog.describe(error)
            )
        }
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
        let timestamp = String(Int(currentDate().timeIntervalSince1970))
        components?.queryItems = queryItems + [
            URLQueryItem(name: "clientId", value: credentials.clientId),
            URLQueryItem(name: "timestamp", value: timestamp)
        ]
        // URLComponents leaves commas unescaped in query-item values, while
        // SnapTrade canonicalizes them as %2C before verifying the request
        // signature. Sign and send the same explicit encoding so comma-separated
        // filters (for example activity types) authenticate successfully.
        if let percentEncodedQuery = components?.percentEncodedQuery {
            components?.percentEncodedQuery = percentEncodedQuery
                .replacingOccurrences(of: ",", with: "%2C")
        }

        guard let url = components?.url else {
            throw SnapTradeError.invalidURL
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

        let requestID = String(UUID().uuidString.prefix(8))
        let startedAt = Date()
        let logPath = redactedLogPath(normalizedPath)
        AppLog.snapTrade.debug(
            "Request \(requestID, privacy: .public) \(method, privacy: .public) \(logPath, privacy: .public) started taskCancelled=\(Task.isCancelled, privacy: .public)"
        )

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            AppLog.snapTrade.error(
                "Request \(requestID, privacy: .public) \(method, privacy: .public) \(logPath, privacy: .public) transport failed: \(AppLog.describe(error)) duration=\(AppLog.duration(since: startedAt), privacy: .public)"
            )
            throw error
        }

        let duration = AppLog.duration(since: startedAt)
        guard let httpResponse = response as? HTTPURLResponse else {
            AppLog.snapTrade.error(
                "Request \(requestID, privacy: .public) \(method, privacy: .public) \(logPath, privacy: .public) completed without HTTP response bytes=\(data.count, privacy: .public) duration=\(duration, privacy: .public)"
            )
            throw SnapTradeError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            AppLog.snapTrade.error(
                "Request \(requestID, privacy: .public) \(method, privacy: .public) \(logPath, privacy: .public) failed status=\(httpResponse.statusCode, privacy: .public) bytes=\(data.count, privacy: .public) duration=\(duration, privacy: .public)"
            )
            let body = String(data: data, encoding: .utf8) ?? ""
            throw SnapTradeError.httpStatus(httpResponse.statusCode, body)
        }

        AppLog.snapTrade.debug(
            "Request \(requestID, privacy: .public) \(method, privacy: .public) \(logPath, privacy: .public) succeeded status=\(httpResponse.statusCode, privacy: .public) bytes=\(data.count, privacy: .public) duration=\(duration, privacy: .public)"
        )
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

    private func redactedLogPath(_ normalizedPath: String) -> String {
        var components = normalizedPath.split(separator: "/").map(String.init)
        for index in components.indices where index > 0 {
            if components[index - 1] == "accounts" || components[index - 1] == "authorizations" {
                components[index] = "<id>"
            }
        }
        return "/" + components.joined(separator: "/")
    }
}
