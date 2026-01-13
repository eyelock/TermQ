import SwiftUI
import TermQCore

struct ColumnEditorView: View {
    @ObservedObject var column: Column
    let onSave: () -> Void
    let onCancel: () -> Void

    @State private var name: String = ""
    @State private var description: String = ""
    @State private var selectedColor: Color = .gray

    private let presetColors: [(Color, String)] = [
        (Color(hex: "#6B7280") ?? .gray, "Gray"),
        (Color(hex: "#3B82F6") ?? .blue, "Blue"),
        (Color(hex: "#10B981") ?? .green, "Green"),
        (Color(hex: "#EF4444") ?? .red, "Red"),
        (Color(hex: "#F59E0B") ?? .yellow, "Yellow"),
        (Color(hex: "#8B5CF6") ?? .purple, "Purple"),
        (Color(hex: "#EC4899") ?? .pink, "Pink"),
        (Color(hex: "#06B6D4") ?? .cyan, "Cyan"),
    ]

    var body: some View {
        VStack(spacing: 16) {
            Text("Edit Column")
                .font(.headline)

            TextField("Column Name", text: $name)
                .textFieldStyle(.roundedBorder)

            TextField("Description (optional)", text: $description, axis: .vertical)
                .lineLimit(2...4)
                .textFieldStyle(.roundedBorder)

            // Color picker
            VStack(alignment: .leading, spacing: 8) {
                Text("Color")
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack(spacing: 8) {
                    // Preset color options
                    ForEach(Array(presetColors.enumerated()), id: \.offset) { _, colorPair in
                        Circle()
                            .fill(colorPair.0)
                            .frame(width: 24, height: 24)
                            .overlay(
                                Circle()
                                    .stroke(Color.primary, lineWidth: colorsMatch(selectedColor, colorPair.0) ? 2 : 0)
                            )
                            .onTapGesture {
                                selectedColor = colorPair.0
                            }
                            .help(colorPair.1)
                    }

                    Divider()
                        .frame(height: 24)

                    // Custom color picker
                    ColorPicker("", selection: $selectedColor, supportsOpacity: false)
                        .labelsHidden()
                        .help("Custom color")
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
                    column.description = description
                    column.color = selectedColor.toHex() ?? "#6B7280"
                    onSave()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 320)
        .onAppear {
            name = column.name
            description = column.description
            selectedColor = Color(hex: column.color) ?? .gray
        }
    }

    /// Check if two colors are approximately equal
    private func colorsMatch(_ c1: Color, _ c2: Color) -> Bool {
        guard let hex1 = c1.toHex(), let hex2 = c2.toHex() else { return false }
        return hex1 == hex2
    }
}

// MARK: - Color to Hex Extension

extension Color {
    func toHex() -> String? {
        guard let components = NSColor(self).usingColorSpace(.deviceRGB) else { return nil }
        let r = Int(components.redComponent * 255)
        let g = Int(components.greenComponent * 255)
        let b = Int(components.blueComponent * 255)
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
