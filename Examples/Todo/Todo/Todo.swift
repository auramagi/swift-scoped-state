//
//  Todo.swift
//  Todo
//
//  Created by Mikhail Apurin on 2026-08-17.
//

import Foundation
import Observation

@MainActor @Observable final class Todo: Identifiable {
    let id: UUID

    var title: String

    var isCompleted: Bool

    init(
        id: UUID = UUID(),
        title: String,
        isCompleted: Bool = false
    ) {
        self.id = id
        self.title = title
        self.isCompleted = isCompleted
    }
}

extension Todo {
    static var samples: [Todo] {
        [
            Todo(title: "Try ScopedState"),
            Todo(title: "Review the Todo example", isCompleted: true),
            Todo(title: "Build something scoped"),
        ]
    }
}
