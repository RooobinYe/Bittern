//
//  MarketDataServerView.swift
//  Bittern
//
//  Where market data comes from: TradingView itself, or the user's own
//  server that forwards it. A server is tested before it is used, since one
//  that doesn't answer leaves every price out of date.
//

import SwiftUI

@Observable
final class MarketDataServerModel {
    enum CheckState: Equatable {
        case idle
        case checking
        case passed(TradingViewServerCheck)
        case failed(String)
    }

    /// The host as typed. Empty means TradingView itself.
    var draft: String {
        didSet {
            if draft != oldValue { checkState = .idle }
        }
    }
    private(set) var current: TradingViewServer
    private(set) var checkState: CheckState = .idle
    private(set) var isSaving = false

    init(current: TradingViewServer) {
        self.current = current
        draft = current.isTradingView ? "" : current.host
    }

    /// The server the draft names, or nil when it names none.
    var draftServer: TradingViewServer? {
        draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? .tradingView
            : TradingViewServer(draft)
    }

    var isBusy: Bool {
        isSaving || checkState == .checking
    }

    var canSave: Bool {
        guard let draftServer, !isBusy else { return false }
        return draftServer != current
    }

    func test(using repository: any PortfolioRepository) async {
        guard let server = draftServer else {
            checkState = .failed("Enter a host such as data.example.com.")
            return
        }
        checkState = .checking
        do {
            checkState = .passed(try await repository.checkMarketDataServer(server))
        } catch {
            checkState = .failed(Self.message(for: error))
        }
    }

    /// Tests the draft and uses it only if it answers. Returns whether it
    /// was saved.
    func save(using repository: any PortfolioRepository) async -> Bool {
        guard let server = draftServer, server != current else { return false }
        isSaving = true
        defer { isSaving = false }

        await test(using: repository)
        guard case .passed = checkState else { return false }
        await repository.useMarketDataServer(server)
        current = server
        return true
    }

    func useTradingView(using repository: any PortfolioRepository) async {
        await repository.useMarketDataServer(.tradingView)
        current = .tradingView
        draft = ""
    }

    private static func message(for error: any Error) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .badServerResponse:
                return "The server didn’t accept a WebSocket connection at /socket.io/websocket."
            case .cannotFindHost, .dnsLookupFailed:
                return "The host couldn’t be found."
            case .notConnectedToInternet:
                return "No internet connection."
            case .timedOut:
                return "The server didn’t answer in time."
            case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate,
                 .serverCertificateNotYetValid, .serverCertificateHasUnknownRoot:
                return "A secure connection to the server couldn’t be made."
            default:
                return urlError.localizedDescription
            }
        }
        if case TradingViewError.timedOut = error {
            return "The server connected but sent no quote in time. Check that it forwards to data.tradingview.com."
        }
        return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}

struct MarketDataServerView: View {
    @State private var model: MarketDataServerModel
    @Environment(\.portfolioRepository) private var repository
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isEditing: Bool

    init(current: TradingViewServer) {
        _model = State(initialValue: MarketDataServerModel(current: current))
    }

    var body: some View {
        Form {
            Section {
                TextField(TradingViewServer.tradingView.host, text: $model.draft)
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .focused($isEditing)
                    .accessibilityLabel("Server")
            } header: {
                Text("Server")
            } footer: {
                Text(serverFooter)
            }

            Section {
                Button {
                    isEditing = false
                    Task { await model.test(using: repository) }
                } label: {
                    HStack {
                        Text("Test Connection")
                        if model.checkState == .checking {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(model.isBusy || model.draftServer == nil)

                checkResult
            }

            if !model.current.isTradingView {
                Section {
                    Button("Use TradingView Directly") {
                        Task { await model.useTradingView(using: repository) }
                    }
                    .disabled(model.isBusy)
                } footer: {
                    Text("Now using \(model.current.host).")
                }
            }
        }
        .navigationTitle("Market Data")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if model.isSaving {
                    ProgressView()
                } else {
                    Button("Save") {
                        isEditing = false
                        Task {
                            if await model.save(using: repository) {
                                dismiss()
                            }
                        }
                    }
                    .disabled(!model.canSave)
                }
            }
        }
    }

    private var serverFooter: String {
        if model.draftServer == nil {
            return "Enter a host such as data.example.com, without a path."
        }
        return "Leave empty to connect to TradingView directly. Your own server must forward wss://<host>/socket.io/websocket to TradingView. Saving tests it first."
    }

    @ViewBuilder
    private var checkResult: some View {
        switch model.checkState {
        case .idle, .checking:
            EmptyView()
        case .passed(let check):
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Connected in \(Self.seconds(check.duration))")
                    Text("BTC \(PortfolioFormat.price(check.price, currencyCode: check.currencyCode ?? "USD")) · \(check.isRealTime ? "Real-time" : "Delayed")")
                        .font(.subheadline)
                        .foregroundStyle(BitternTheme.secondaryInk)
                }
            } icon: {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(BitternTheme.positivePerformance)
            }
        case .failed(let message):
            Label {
                Text(message)
            } icon: {
                Image(systemName: "xmark.octagon.fill")
                    .foregroundStyle(BitternTheme.negativePerformance)
            }
        }
    }

    private static func seconds(_ duration: Duration) -> String {
        let components = duration.components
        let seconds = Double(components.seconds) + Double(components.attoseconds) / 1e18
        return seconds.formatted(.number.precision(.fractionLength(2))) + " s"
    }
}

/// The settings row that leads to `MarketDataServerView`.
struct MarketDataServerSection: View {
    @Environment(\.portfolioRepository) private var repository
    /// Read so the row follows a change made on the next page.
    @AppStorage(AppSettingKey.marketDataServer) private var savedHost = ""

    var body: some View {
        let server = repository.marketDataServer
        Section {
            NavigationLink {
                MarketDataServerView(current: server)
            } label: {
                LabeledContent("Server", value: server.isTradingView ? "TradingView" : server.host)
            }
            .id(savedHost)
        } header: {
            Text("Market Data")
        } footer: {
            Text("Prices and charts stream from TradingView, directly or through your own server.")
        }
    }
}
