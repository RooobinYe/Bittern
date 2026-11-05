import Foundation
import Testing
@testable import Bittern

/// Fixtures follow SnapTrade's published OpenAPI schema and examples
/// (github.com/passiv/snaptrade-sdks), with invented identifiers and amounts.
@Suite
struct SnapTradeDecodingTests {
    private func decode<Value: Decodable>(_ type: Value.Type, _ json: String) throws -> Value {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    @Test func decodesPositions() throws {
        let response = try JSONDecoder().decode(
            SnapTradePositionsResponseDTO.self,
            from: Fixture.data("snaptrade-positions")
        )

        #expect(response.results.count == 3)

        let stock = response.results[0]
        #expect(stock.resolvedSymbol == "AAPL")
        #expect(stock.resolvedName == "Apple Inc.")
        #expect(stock.units == 10.5)
        #expect(stock.unitsDisplay == "10.5")
        #expect(stock.resolvedCurrency == "USD")
        #expect(stock.instrument?.kind == "stock")
        // `cost_basis` is a per-unit price, not the position's total cost.
        #expect(stock.resolvedAverageCost == 118.2)

        #expect(response.results[1].resolvedAverageCost == nil)
        #expect(response.results[2].instrument?.kind == "cash")
    }

    @Test func zeroCostBasisIsUnknown() throws {
        let position = try decode(
            SnapTradePositionDTO.self,
            #"{"instrument":{"kind":"stock","id":"1","symbol":"AAPL"},"units":"1","cost_basis":"0","currency":"USD"}"#
        )

        #expect(position.resolvedAverageCost == nil)
    }

    @Test(arguments: [
        #"{"positions":[]}"#,
        #"{"data":[]}"#,
        #"{}"#,
        #"[]"#
    ])
    func unknownPositionsStructureFails(json: String) {
        #expect(throws: DecodingError.self) {
            try decode(SnapTradePositionsResponseDTO.self, json)
        }
    }

    @Test func decodesActivities() throws {
        let response = try JSONDecoder().decode(
            SnapTradeActivitiesResponseDTO.self,
            from: Fixture.data("snaptrade-activities")
        )

        #expect(response.data.count == 1)
        #expect(response.pagination?.total == 1)
        #expect(response.data[0].resolvedSymbol == "AAPL")
        #expect(response.data[0].amount == 26.5)
        #expect(response.data[0].currencyCode == "USD")
    }

    @Test(arguments: [#"{"activities":[]}"#, #"{}"#, #"[]"#])
    func unknownActivitiesStructureFails(json: String) {
        #expect(throws: DecodingError.self) {
            try decode(SnapTradeActivitiesResponseDTO.self, json)
        }
    }

    @Test func decodesBalanceHistory() throws {
        let response = try JSONDecoder().decode(
            SnapTradeAccountBalanceHistoryDTO.self,
            from: Fixture.data("snaptrade-balance-history")
        )

        #expect(response.currency == "USD")
        #expect(response.history.map(\.totalValue) == [15_363.23, 15_401.10])
        #expect(response.history.allSatisfy { $0.date != nil })
    }

    @Test(arguments: [#"{"data":[]}"#, #"{"currency":"USD"}"#])
    func unknownBalanceHistoryStructureFails(json: String) {
        #expect(throws: DecodingError.self) {
            try decode(SnapTradeAccountBalanceHistoryDTO.self, json)
        }
    }

    @Test(arguments: ["\"abc\"", "\"\"", "\"NaN\"", "\"inf\"", "true", "{}"])
    func unparseableNumberFails(value: String) {
        #expect(throws: DecodingError.self) {
            try decode(SnapTradeMoneyDTO.self, #"{"amount":\#(value),"currency":"USD"}"#)
        }
    }

    @Test(arguments: [("12.5", 12.5), ("\"12.5\"", 12.5), ("\" 12.5 \"", 12.5), ("3", 3.0)])
    func flexibleNumbersStillParse(value: String, expected: Double) throws {
        let money = try decode(SnapTradeMoneyDTO.self, #"{"amount":\#(value),"currency":"USD"}"#)
        #expect(money.amount == expected)
    }

    @Test func absentAndNullNumbersAreNil() throws {
        #expect(try decode(SnapTradeMoneyDTO.self, #"{"currency":"USD"}"#).amount == nil)
        #expect(try decode(SnapTradeMoneyDTO.self, #"{"amount":null,"currency":"USD"}"#).amount == nil)
    }

    @Test func unparseableHistoryDateFails() {
        #expect(throws: DecodingError.self) {
            try decode(
                SnapTradeAccountBalanceHistoryDTO.self,
                #"{"currency":"USD","history":[{"date":"last tuesday","total_value":"1"}]}"#
            )
        }
    }
}
