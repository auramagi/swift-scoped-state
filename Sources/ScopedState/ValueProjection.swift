//
//  ValueProjection.swift
//  ScopedState
//
//  Created by Mikhail Apurin on 2026-08-16.
//

import SwiftUI

public protocol ValueProjection<Value>: SendableMetatype {
    associatedtype Value

    associatedtype ProjectedValue

    @MainActor static func transformProjection(_ projection: ScopedStateProjection<Value>) -> ProjectedValue
}

public enum ReadOnlyValueProjection<Value>: ValueProjection {
    @MainActor public static func transformProjection(_ projection: ScopedStateProjection<Value>) -> ScopedStateProjection<Value> {
        projection
    }
}

public enum ReadWriteValueProjection<Value>: ValueProjection {
    @MainActor public static func transformProjection(_ projection: ScopedStateProjection<Value>) -> Binding<Value> {
        projection.base
    }
}
