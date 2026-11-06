//
//  SnapTradeDTOs.swift
//  Bittern
//
//  Response and request shapes of the SnapTrade API.
//

import Foundation

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

struct SnapTradeRegisterUserRequestDTO: Encodable {
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

struct SnapTradeConnectionPortalRequestDTO: Encodable {
    let connectionType: String
    let showCloseButton: Bool
    let darkMode: Bool
    let connectionPortalVersion: String
}

struct SnapTradeConnectionPortalResponseDTO: Decodable {
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

// The DTOs below follow SnapTrade's published OpenAPI schema. A response of any
// other shape fails to decode: an account must never read as having no positions
// because its payload wasn't understood.

struct SnapTradeAccountBalanceHistoryDTO: Decodable {
    let history: [SnapTradeAccountBalanceHistoryPointDTO]
    let currency: String?
}

struct SnapTradeAccountBalanceHistoryPointDTO: Decodable {
    let date: Date?
    let totalValue: Double?

    init(date: Date?, totalValue: Double?) {
        self.date = date
        self.totalValue = totalValue
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        date = try container.decodeDateOnlyIfPresent(forKey: .date)
        totalValue = try container.decodeFlexibleDoubleIfPresent(forKey: .totalValue)
    }

    enum CodingKeys: String, CodingKey {
        case date
        case totalValue = "total_value"
    }
}

struct SnapTradePositionsResponseDTO: Decodable {
    let results: [SnapTradePositionDTO]
}

struct SnapTradeActivitiesResponseDTO: Decodable {
    let data: [SnapTradeActivityDTO]
    let pagination: SnapTradePaginationDTO?
}

struct SnapTradePaginationDTO: Decodable {
    let total: Int?
}

struct SnapTradeActivityDTO: Decodable {
    let symbol: SnapTradeActivitySymbolDTO?
    let amount: Double?
    let currency: SnapTradeCurrencyDTO?

    var resolvedSymbol: String? {
        symbol?.symbol ?? symbol?.rawSymbol
    }

    var currencyCode: String? {
        currency?.code
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        symbol = try container.decodeIfPresent(SnapTradeActivitySymbolDTO.self, forKey: .symbol)
        amount = try container.decodeFlexibleDoubleIfPresent(forKey: .amount)
        currency = try container.decodeIfPresent(SnapTradeCurrencyDTO.self, forKey: .currency)
    }

    enum CodingKeys: String, CodingKey {
        case symbol
        case amount
        case currency
    }
}

struct SnapTradeActivitySymbolDTO: Decodable {
    let symbol: String?
    let rawSymbol: String?

    enum CodingKeys: String, CodingKey {
        case symbol
        case rawSymbol = "raw_symbol"
    }
}

struct SnapTradeCurrencyDTO: Decodable {
    let code: String?
}

struct SnapTradePositionDTO: Decodable {
    let instrument: SnapTradeInstrumentDTO?
    let units: Double?
    let unitsDisplay: String?
    /// SnapTrade's "book price or average purchase price": a price per unit,
    /// not the position's total cost. Zero means the broker doesn't know it.
    let costBasis: Double?
    let currency: String?

    var resolvedSymbol: String? {
        instrument?.symbol ?? instrument?.rawSymbol
    }

    var resolvedName: String? {
        instrument?.description ?? instrument?.symbol
    }

    var resolvedAverageCost: Double? {
        costBasis.flatMap { $0 > 0 ? $0 : nil }
    }

    var resolvedCurrency: String? {
        currency ?? instrument?.currency
    }

    /// A cash balance reported as a position. Bittern has no cash concept
    /// (see CONTEXT.md), so this isn't a holding.
    var isCash: Bool {
        instrument?.kind == "cash"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        instrument = try container.decodeIfPresent(SnapTradeInstrumentDTO.self, forKey: .instrument)
        units = try container.decodeFlexibleDoubleIfPresent(forKey: .units)
        unitsDisplay = try container.decodeFlexibleNumberTextIfPresent(forKey: .units)
        costBasis = try container.decodeFlexibleDoubleIfPresent(forKey: .costBasis)
        currency = try container.decodeIfPresent(String.self, forKey: .currency)
    }

    enum CodingKeys: String, CodingKey {
        case instrument
        case units
        case costBasis = "cost_basis"
        case currency
    }
}

struct SnapTradeInstrumentDTO: Decodable {
    let id: String?
    let kind: String?
    let symbol: String?
    let rawSymbol: String?
    let description: String?
    let currency: String?

    enum CodingKeys: String, CodingKey {
        case id
        case kind
        case symbol
        case rawSymbol = "raw_symbol"
        case description
        case currency
    }
}
