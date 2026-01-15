import SwiftUI
import TermQCore

struct ColumnEditorView: View {
    @ObservedObject var column: Column
    let onSave: () -> Void
    let onCancel: () -> Void

    @State private var name: String = ""
    @State private var description: String = ""
    @State private var selectedColor: Color = .gray

    private var presetColors: [(Color, String)] {
        Constants.ColorPalette.columnColors.map { (Color(hex: $0.hex) ?? .gray, $0.name) }
    }

    var body: some View {
        VStack(spacing: 16) {
            Text(Strings.ColumnEditor.titleEdit)
                .font(.headline)

            TextField(Strings.ColumnEditor.fieldName, text: $name)
                .textFieldStyle(.roundedBorder)

            TextField(Strings.ColumnEditor.fieldDescription, text: $description, axis: .vertical)
                .lineLimit(2...4)
                .textFieldStyle(.roundedBorder)

            // Color picker
            VStack(alignment: .leading, spacing: 8) {
                Text(Strings.ColumnEditor.fieldColor)
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
                        .help(Strings.ColumnEditor.fieldColor)
                }
            }

            HStack {
                Button(Strings.ColumnEditor.cancel) {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button(Strings.ColumnEditor.save) {
                    column.name = name
                    column.description = description
                    column.color = selectedColor.toHex() ?? Constants.Columns.defaultColor
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
