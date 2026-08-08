//
//  Connection.swift
//  ScopedState
//
//  Created by Mikhail Apurin on 2026-08-08.
//

import Combine

public typealias Connection<WrappedValue> = ConnectionDefinition<Void, ReadOnlyConnectedValue<WrappedValue>>

extension Connection {
    public typealias Configuration<NewConfiguration> = ConnectionDefinition<NewConfiguration, Connected>

    public typealias Writable = ConnectionDefinition<Configuration, WritableConnectedValue<Connected.WrappedValue>>
}

/// The generic implementation underlying the public `Connection<Value>` family.
@MainActor public struct ConnectionDefinition<Configuration, Connected: ConnectedValue> {
    /// A live handle created for one position in the SwiftUI view tree.
    /// Its closures retain any implementation object needed to keep the value alive.
    @MainActor public struct Handle {
        let currentValue: @MainActor () -> Connected.WrappedValue

        let updates: any Publisher<Connected.WrappedValue, Never>

        let setValue: (@MainActor (Connected.WrappedValue) -> Void)?

        let updateConfiguration: @MainActor (Configuration) -> Void

        public init<WrappedValue>(
            currentValue: @escaping @MainActor () -> WrappedValue,
            updates: any Publisher<WrappedValue, Never>,
            updateConfiguration: @escaping @MainActor (Configuration) -> Void = { _ in }
        ) where Connected == ReadOnlyConnectedValue<WrappedValue> {
            self.currentValue = currentValue
            self.updates = updates
            self.setValue = nil
            self.updateConfiguration = updateConfiguration
        }

        public init<WrappedValue>(
            currentValue: @escaping @MainActor () -> WrappedValue,
            updates: any Publisher<WrappedValue, Never>,
            setValue: @escaping @MainActor (WrappedValue) -> Void,
            updateConfiguration: @escaping @MainActor (Configuration) -> Void = { _ in }
        ) where Connected == WritableConnectedValue<WrappedValue> {
            self.currentValue = currentValue
            self.updates = updates
            self.setValue = setValue
            self.updateConfiguration = updateConfiguration
        }
    }

    let makeHandle: @MainActor (Configuration) -> Handle

    let configurationsEqual: @MainActor (Configuration, Configuration) -> Bool

    public init(
        makeHandle: @escaping @MainActor (Configuration) -> Handle,
        configurationsEqual: @escaping @MainActor (Configuration, Configuration) -> Bool
    ) {
        self.configurationsEqual = configurationsEqual
        self.makeHandle = makeHandle
    }
}

extension ConnectionDefinition where Configuration: Equatable {
    public init(
        makeHandle: @escaping @MainActor (Configuration) -> Handle
    ) {
        self.init(
            makeHandle: makeHandle,
            configurationsEqual: { $0 == $1 }
        )
    }
}

extension ConnectionDefinition where Configuration == Void {
    public init(
        makeHandle: @escaping @MainActor () -> Handle
    ) {
        self.init(
            makeHandle: { _ in makeHandle() },
            configurationsEqual: { _, _ in true }
        )
    }

    public init<WrappedValue>(
        currentValue: @escaping @MainActor () -> WrappedValue,
        updates: any Publisher<WrappedValue, Never>
    ) where Connected == ReadOnlyConnectedValue<WrappedValue> {
        self.init {
            Handle(
                currentValue: currentValue,
                updates: updates
            )
        }
    }

    public init<WrappedValue>(
        currentValue: @escaping @MainActor () -> WrappedValue,
        updates: any Publisher<WrappedValue, Never>,
        setValue: @escaping @MainActor (WrappedValue) -> Void
    ) where Connected == WritableConnectedValue<WrappedValue> {
        self.init {
            Handle(
                currentValue: currentValue,
                updates: updates,
                setValue: setValue
            )
        }
    }
}
