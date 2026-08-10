//
//  Connection+SwiftUI.swift
//  ScopedState
//
//  Created by Mikhail Apurin on 2026-08-10.
//

import SwiftUI

extension GenericConnection where Configuration == Void {
    /// Creates a read-only connection backed by a SwiftUI binding.
    public static func binding<WrappedValue>(
        _ binding: Binding<WrappedValue>
    ) -> Connection<WrappedValue> {
        Connection<WrappedValue> { yield in
            yield(binding.wrappedValue)
        }
    }

    /// Creates a writable connection backed by a SwiftUI binding.
    public static func binding<WrappedValue>(
        _ binding: Binding<WrappedValue>
    ) -> Connection<WrappedValue>.Writable {
        let connection: Connection<WrappedValue> = .binding(binding)
        return connection.set { binding.wrappedValue = $0 }
    }
}
