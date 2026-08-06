import Combine
import Foundation
import Observation
import ScopedState
import SwiftUI

@main struct ExampleApp: App {
    var body: some Scene {
        WindowGroup {
            AppRootView()
        }
    }
}

private struct AppRootView: View {
    @State private var container = AppContainer()

    var body: some View {
        ContentView()
            .container(container, scope: \.appScope)
            .container(container, scope: \.diagnosticsScope)
    }
}

// MARK: - Demo views

struct ContentView: View {
    @State private var pricingMode = PricingMode.standard

    @State private var productID = 100

    @State private var isProductScopeMounted = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Container-scoped state")
                    .font(.largeTitle.bold())

                Text("The window exposes scopes from its container. This product subtree connects a child scope whose live state retains its ID-aware container.")
                    .foregroundStyle(.secondary)

                AppContainerDiagnostics()

                ScopeControls(
                    productID: $productID,
                    pricingMode: $pricingMode,
                    isProductScopeMounted: $isProductScopeMounted
                )

                if isProductScopeMounted {
                    ProductDetailDemo()
                        .scope(\AppScope.productDetail, input: input)
                }
            }
            .padding(24)
            .frame(maxWidth: 640, alignment: .leading)
        }
    }

    private var input: ProductDetailInput {
        ProductDetailInput(productID: productID, pricingMode: pricingMode)
    }
}

private struct AppContainerDiagnostics: View {
    @ScopedState(\AppDiagnosticsScope.containerID) private var containerID

    var body: some View {
        LabeledContent("Root container", value: String(containerID.uuidString.prefix(8)))
            .monospaced()
    }
}

private struct ScopeControls: View {
    @Binding var productID: Int

    @Binding var pricingMode: PricingMode

    @Binding var isProductScopeMounted: Bool

    var body: some View {
        GroupBox("Scope input") {
            VStack(alignment: .leading, spacing: 16) {
                Toggle("Mount product subtree", isOn: $isProductScopeMounted)

                Stepper("Product ID: \(productID)", value: $productID, in: 100 ... 103)

                Picker("Pricing", selection: $pricingMode) {
                    ForEach(PricingMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue)
                    }
                }
                .pickerStyle(.segmented)
            }
            .padding(.vertical, 4)
        }
    }
}

private struct ProductDetailDemo: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ProductOrderButton()

            ProductConnectionSemantics()

            ProductContainerDiagnostics()
        }
    }
}

private struct ProductOrderButton: View {
    @ScopedState(\ProductScope.orderState) private var orderState

    var body: some View {
        Button {
            $orderState.wrappedValue = orderState == .inCart ? .notInCart : .inCart
        } label: {
            Label(buttonTitle, systemImage: orderState == .inCart ? "cart.badge.minus" : "cart.badge.plus")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }

    private var buttonTitle: String {
        orderState == .inCart ? "Remove from cart" : "Add to cart"
    }
}

private struct ProductConnectionSemantics: View {
    @ScopedState(\ProductScope.isAvailable) private var isAvailable

    @ScopedState(\ProductScope.isFavorite) private var isFavorite

    @ScopedState(\ProductScope.options) private var options

    var body: some View {
        GroupBox("Connection semantics") {
            VStack(alignment: .leading, spacing: 12) {
                LabeledContent("Read-only Bool", value: isAvailable ? "Available" : "Unavailable")

                Toggle("Favorite", isOn: $isFavorite)

                Toggle("Not favorite (writable key-path projection)", isOn: $isFavorite.inverted)

                Divider()

                Text("Read-only object reference")
                    .font(.headline)

                Toggle("Gift wrap", isOn: $options.includesGiftWrap)

                Stepper("Quantity: \(options.quantity)", value: $options.quantity, in: 1 ... 10)
            }
            .padding(.vertical, 4)
        }
    }
}

private struct ProductContainerDiagnostics: View {
    @ScopedState(\ProductScope.snapshot) private var snapshot

    var body: some View {
        GroupBox("Resolved container") {
            Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 8) {
                diagnosticRow("App instance", snapshot.appContainerID.uuidString.prefix(8))

                diagnosticRow("Product instance", snapshot.containerID.uuidString.prefix(8))

                diagnosticRow("Product", snapshot.productID)

                diagnosticRow("Pricing", snapshot.pricingMode.rawValue)

                diagnosticRow("In-place updates", snapshot.updateCount)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
    }

    private func diagnosticRow(_ label: String, _ value: some CustomStringConvertible) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)

            Text(value.description)
                .monospaced()
                .textSelection(.enabled)
        }
    }
}

// MARK: - Demo scope and container

enum OrderState: String {
    case inCart = "In cart"
    
    case notInCart = "Not in cart"
}

enum PricingMode: String, CaseIterable {
    case standard = "Standard"
    
    case member = "Member"
}

extension Bool {
    var inverted: Bool {
        get { !self }
        set { self = !newValue }
    }
}

struct ProductDetailInput: Equatable {
    var productID: Int

    var pricingMode: PricingMode
}

struct ProductDetailSnapshot: Equatable {
    let appContainerID: UUID

    let containerID: UUID

    let productID: Int

    let pricingMode: PricingMode

    let updateCount: Int
}

@MainActor struct AppScope {
    let productDetail: ConnectionFactory<ProductDetailInput, ProductScope>
}

@MainActor struct AppDiagnosticsScope {
    let containerID: Connection<UUID>
}

@MainActor final class AppContainer {
    let containerID = UUID()

    private var orderSubjects: [Int: CurrentValueSubject<OrderState, Never>] = [:]

    private var favoriteSubjects: [Int: CurrentValueSubject<Bool, Never>] = [:]

    var appScope: AppScope {
        AppScope(
            productDetail: ConnectionFactory { input in
                let container = ProductDetailContainer(appContainer: self, input: input)
                let scope = container.scope
                return ConnectionSession(
                    currentValue: { scope },
                    updates: Empty<ProductScope, Never>(completeImmediately: false),
                    updateInput: { container.update(input: $0) }
                )
            }
        )
    }

    var diagnosticsScope: AppDiagnosticsScope {
        AppDiagnosticsScope(
            containerID: Connection(
                currentValue: { self.containerID },
                updates: Empty<UUID, Never>(completeImmediately: false)
            )
        )
    }

    func buy(id productID: Int) {
        orderSubject(for: productID).send(.inCart)
    }

    func removeFromCart(id productID: Int) {
        orderSubject(for: productID).send(.notInCart)
    }

    func setFavorite(_ isFavorite: Bool, id productID: Int) {
        favoriteSubject(for: productID).send(isFavorite)
    }

    func orderState(id productID: Int) -> OrderState {
        orderSubject(for: productID).value
    }

    func orderUpdates(id productID: Int) -> some Publisher<OrderState, Never> {
        orderSubject(for: productID)
    }

    func isFavorite(id productID: Int) -> Bool {
        favoriteSubject(for: productID).value
    }

    func favoriteUpdates(id productID: Int) -> some Publisher<Bool, Never> {
        favoriteSubject(for: productID)
    }

    private func orderSubject(for productID: Int) -> CurrentValueSubject<OrderState, Never> {
        if let subject = orderSubjects[productID] {
            return subject
        }

        let subject = CurrentValueSubject<OrderState, Never>(.notInCart)
        orderSubjects[productID] = subject
        return subject
    }

    private func favoriteSubject(for productID: Int) -> CurrentValueSubject<Bool, Never> {
        if let subject = favoriteSubjects[productID] {
            return subject
        }

        let subject = CurrentValueSubject<Bool, Never>(false)
        favoriteSubjects[productID] = subject
        return subject
    }
}

@MainActor @Observable final class ProductOptions {
    var includesGiftWrap = false

    var quantity = 1
}

@MainActor struct ProductScope {
    let orderState: WritableConnection<OrderState>

    let snapshot: Connection<ProductDetailSnapshot>

    let isAvailable: Connection<Bool>

    let isFavorite: WritableConnection<Bool>

    let options: Connection<ProductOptions>
}

@MainActor final class ProductDetailContainer {
    let appContainerID: UUID

    let containerID: UUID

    private let appContainer: AppContainer

    private var input: ProductDetailInput

    private var updateCount = 0

    private let orderSubject: CurrentValueSubject<OrderState, Never>

    private let availabilitySubject: CurrentValueSubject<Bool, Never>

    private let favoriteSubject: CurrentValueSubject<Bool, Never>

    private let options: ProductOptions

    private let snapshotSubject: CurrentValueSubject<ProductDetailSnapshot, Never>

    private var orderSubscription: AnyCancellable?

    private var favoriteSubscription: AnyCancellable?

    init(appContainer: AppContainer, input: ProductDetailInput) {
        let containerID = UUID()

        self.appContainerID = appContainer.containerID
        self.containerID = containerID
        self.appContainer = appContainer
        self.input = input
        self.orderSubject = CurrentValueSubject(appContainer.orderState(id: input.productID))
        self.availabilitySubject = CurrentValueSubject(Self.isAvailable(productID: input.productID))
        self.favoriteSubject = CurrentValueSubject(appContainer.isFavorite(id: input.productID))
        self.options = ProductOptions()
        self.snapshotSubject = CurrentValueSubject(
            ProductDetailSnapshot(
                appContainerID: appContainer.containerID,
                containerID: containerID,
                productID: input.productID,
                pricingMode: input.pricingMode,
                updateCount: 0
            )
        )

        connectToAppContainer()
    }

    func update(input: ProductDetailInput) {
        let productChanged = self.input.productID != input.productID
        self.input = input
        updateCount += 1

        if productChanged {
            connectToAppContainer()
            availabilitySubject.send(Self.isAvailable(productID: input.productID))
        }

        snapshotSubject.send(snapshot)
    }

    var scope: ProductScope {
        ProductScope(
            orderState: WritableConnection(
                currentValue: { self.orderSubject.value },
                updates: orderSubject,
                setValue: { self.setOrderState($0) }
            ),
            snapshot: Connection(
                currentValue: { self.snapshot },
                updates: snapshotSubject
            ),
            isAvailable: Connection(
                currentValue: { self.availabilitySubject.value },
                updates: availabilitySubject
            ),
            isFavorite: WritableConnection(
                currentValue: { self.favoriteSubject.value },
                updates: favoriteSubject,
                setValue: { self.setFavorite($0) }
            ),
            options: Connection(
                currentValue: { self.options },
                updates: Empty(completeImmediately: false)
            )
        )
    }

    func buy() {
        appContainer.buy(id: input.productID)
    }

    func removeFromCart() {
        appContainer.removeFromCart(id: input.productID)
    }

    private var snapshot: ProductDetailSnapshot {
        ProductDetailSnapshot(
            appContainerID: appContainerID,
            containerID: containerID,
            productID: input.productID,
            pricingMode: input.pricingMode,
            updateCount: updateCount
        )
    }

    private func setOrderState(_ value: OrderState) {
        switch value {
        case .inCart:
            buy()
        case .notInCart:
            removeFromCart()
        }
    }

    private func setFavorite(_ value: Bool) {
        appContainer.setFavorite(value, id: input.productID)
    }

    private func connectToAppContainer() {
        orderSubscription?.cancel()
        favoriteSubscription?.cancel()

        orderSubscription = appContainer.orderUpdates(id: input.productID)
            .sink { [weak self] value in
                self?.orderSubject.send(value)
            }
        favoriteSubscription = appContainer.favoriteUpdates(id: input.productID)
            .sink { [weak self] value in
                self?.favoriteSubject.send(value)
            }
    }

    private static func isAvailable(productID: Int) -> Bool {
        !productID.isMultiple(of: 3)
    }
}

#Preview {
    AppRootView()
}
