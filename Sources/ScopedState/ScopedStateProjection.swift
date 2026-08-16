//
//  ScopedStateProjection.swift
//  ScopedState
//
//  Created by Mikhail Apurin on 2026-08-16.
//

import SwiftUI

@MainActor @dynamicMemberLookup public struct ScopedStateProjection<Base> {
    let base: Binding<Base>

    public subscript<Value>(dynamicMember keyPath: ReferenceWritableKeyPath<Base, Value>) -> Binding<Value> {
        base[dynamicMember: keyPath]
    }
}

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
