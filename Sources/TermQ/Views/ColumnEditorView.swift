import SwiftUI
import TermQCore

struct ColumnEditorView: View {
    @ObservedObject var column: Column
    let onSave: () -> Void
    let onCancel: () -> Void

    @State private var name: String = ""
    @State private var selectedColor: String = "#6B7280"

    private let colorOptions = [
        ("#6B7280", "Gray"),
        ("#3B82F6", "Blue"),
        ("#10B981", "Green"),
        ("#EF4444", "Red"),
        ("#F59E0B", "Yellow"),
        ("#8B5CF6", "Purple"),
        ("#EC4899", "Pink"),
        ("#06B6D4", "Cyan"),
    ]

    var body: some View {
        VStack(spacing: 16) {
            Text("Edit Column")
                .font(.headline)

            TextField("Column Name", text: $name)
                .textFieldStyle(.roundedBorder)

            // Color picker
            VStack(alignment: .leading, spacing: 8) {
                Text("Color")
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack(spacing: 8) {
                    ForEach(colorOptions, id: \.0) { (hex, _) in
                        Circle()
                            .fill(Color(hex: hex) ?? .gray)
                            .frame(width: 24, height: 24)
                            .overlay(
                                Circle()
                                    .stroke(Color.primary, lineWidth: selectedColor == hex ? 2 : 0)
                            )
                            .onTapGesture {
                                selectedColor = hex
                            }
                    }
                }
            }

            HStack {
                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Save") {
                    column.name = name
                    column.color = selectedColor
                    onSave()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 300)
        .onAppear {
            name = column.name
            selectedColor = column.color
        }
    }
}
