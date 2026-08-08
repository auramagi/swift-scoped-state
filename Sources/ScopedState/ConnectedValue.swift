//
//  ConnectedValue.swift
//  ScopedState
//
//  Created by Mikhail Apurin on 2026-08-08.
//

import SwiftUI

public protocol ConnectedValue: SendableMetatype {
    associatedtype WrappedValue

    associatedtype Projection

    @MainActor static func transformProjection(_ projection: ScopedStateProjection<WrappedValue>) -> Projection
}

public enum ReadOnlyConnectedValue<WrappedValue>: ConnectedValue {
    @MainActor public static func transformProjection(_ projection: ScopedStateProjection<WrappedValue>) -> ScopedStateProjection<WrappedValue> {
        projection
    }
}

public enum WritableConnectedValue<WrappedValue>: ConnectedValue {
    @MainActor public static func transformProjection(_ projection: ScopedStateProjection<WrappedValue>) -> Binding<WrappedValue> {
        projection.base
    }
}
