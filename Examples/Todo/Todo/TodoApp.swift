//
//  TodoApp.swift
//  Todo
//
//  Created by Mikhail Apurin on 2026-08-17.
//

import ScopedState
import SwiftUI

@main struct TodoApp: App {
    @State private var container = AppContainer()

    var body: some Scene {
        WindowGroup {
            TodoListView()
                .container(container, scope: \.appScope)
        }
    }
}

struct TodoListView: View {
    @ScopedState(\AppScope.addTodo) private var addTodo

    @ScopedState(\AppScope.todos) private var todos

    var body: some View {
        NavigationStack {
            ZStack {
                if todos.isEmpty {
                    ContentUnavailableView(
                        "No Todos",
                        systemImage: "checkmark.circle",
                        description: Text("Add a todo to get started.")
                    )
                } else {
                    List {
                        ForEach(todos, id: \.self) { id in
                            TodoRow()
                                .scope(\AppScope.todoScope, configuration: id)
                        }
                    }
                }
            }
            .navigationTitle("Todos")
            .toolbar {
                Button("Add Todo", systemImage: "plus", action: addTodo)
            }
        }
    }
}

private struct TodoRow: View {
    @ScopedState(\TodoScope.delete) private var delete

    @ScopedState(\TodoScope.isCompleted) private var isCompleted

    @ScopedState(\TodoScope.title) private var title

    var body: some View {
        Toggle(isOn: $isCompleted) {
            Text(title)
                .foregroundStyle(isCompleted ? .secondary : .primary)
                .strikethrough(isCompleted)
        }
        .swipeActions {
            Button("Delete", systemImage: "trash", role: .destructive, action: delete)
        }
    }
}

#Preview("Sample", traits: .sampleAppScope) {
    TodoListView()
}

#Preview("Empty", traits: .emptyAppScope) {
    TodoListView()
}
