import Foundation
import Testing
@testable import Bittern

extension NetworkTests {
    /// Expected signatures were computed independently with Python's `hmac`
    /// and SnapTrade's canonical JSON (sorted keys, no whitespace).
    @Suite struct SnapTradeSigningTests {
        private let credentials = SnapTradeCredentials(
            clientId: "client-1",
            consumerKey: "test-consumer-key",
            userId: "user-1",
            userSecret: "secret-1"
        )
        private let fixedDate = Date(timeIntervalSince1970: 1_793_923_200)

        private func client(respondingWith body: String) -> SnapTradeClient {
            let session = StubURLProtocol.session { _ in (200, Data(body.utf8)) }
            let date = fixedDate
            return SnapTradeClient(credentials: credentials, session: session, currentDate: { date })
        }

        @Test func signsAndSendsCommasAsPercent2C() async throws {
            let client = client(respondingWith: #"{"data":[],"pagination":{"total":0}}"#)

            _ = try await client.listActivities(accountID: "acct-1", types: ["DIVIDEND", "REI"])

            let request = try #require(StubURLProtocol.requests.first)
            let query = try #require(request.url?.query(percentEncoded: true))
            #expect(
                query == "userId=user-1&userSecret=secret-1&limit=1000&offset=0&type=DIVIDEND%2CREI&clientId=client-1&timestamp=1793923200"
            )
            #expect(
                request.value(forHTTPHeaderField: "Signature")
                    == "CXMYA1o8k1tPQ1xQyO34erDtYrDiSkzBNlW8pc2vGEE="
            )
        }

        @Test func signsTheRequestBodyAsContent() async throws {
            let client = client(respondingWith: #"{"userId":"user-1","userSecret":"secret-1"}"#)

            _ = try await client.registerUser(userId: "user-1")

            let request = try #require(StubURLProtocol.requests.first)
            #expect(request.httpMethod == "POST")
            #expect(
                request.value(forHTTPHeaderField: "Signature")
                    == "Mu6Gc1R7KXVJHUFvLNS8ZvygNwsa7/B8WmHEYCI7xPQ="
            )
        }
    }
}
