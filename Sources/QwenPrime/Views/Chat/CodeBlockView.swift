import SwiftUI
import AppKit

public struct CodeBlockView: View {
    public let language: String
    public let code: String

    @State private var isCopied: Bool = false
    @State private var isHovered: Bool = false

    public init(language: String = "", code: String) {
        self.language = language.isEmpty ? "text" : language.lowercased()
        self.code = code
    }

    private var languageColor: Color {
        switch language {
        case "python", "py":
            return Color(red: 0.29, green: 0.56, blue: 0.85)
        case "swift":
            return Color(red: 0.98, green: 0.40, blue: 0.18)
        case "rust", "rs":
            return Color(red: 0.87, green: 0.35, blue: 0.22)
        case "javascript", "js", "typescript", "ts":
            return Color(red: 0.95, green: 0.80, blue: 0.20)
        case "sh", "bash", "zsh", "shell":
            return Color(red: 0.30, green: 0.80, blue: 0.45)
        case "json", "yaml", "yml", "toml":
            return Color(red: 0.85, green: 0.65, blue: 0.30)
        case "html", "css":
            return Color(red: 0.88, green: 0.42, blue: 0.65)
        case "c", "cpp", "c++", "h":
            return Color(red: 0.38, green: 0.60, blue: 0.90)
        default:
            return Color.cyan
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header Bar
            HStack {
                HStack(spacing: 6) {
                    Circle()
                        .fill(languageColor)
                        .frame(width: 7, height: 7)

                    Text(language.uppercased())
                        .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    copyToClipboard()
                } label: {
                    HStack(spacing: 4.5) {
                        Image(systemName: isCopied ? "checkmark" : "square.on.square")
                            .font(.system(size: 10.5, weight: .semibold))
                        Text(isCopied ? "Copied" : "Copy Code")
                            .font(.system(size: 10.5, weight: .medium))
                    }
                    .foregroundStyle(isCopied ? .green : .primary.opacity(0.85))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(isHovered ? 0.12 : 0.07), in: RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.75))

            Divider()
                .opacity(0.2)

            // Code Content
            ScrollView(.horizontal, showsIndicators: true) {
                Text(code)
                    .font(.system(size: 12.5, weight: .regular, design: .monospaced))
                    .foregroundStyle(Color.primary.opacity(0.95))
                    .lineSpacing(4)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color.black.opacity(0.45))
        }
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .onHover { isHovered = $0 }
    }

    private func copyToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code, forType: .string)
        withAnimation(.easeInOut(duration: 0.2)) {
            isCopied = true
        }
        Task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation(.easeInOut(duration: 0.2)) {
                isCopied = false
            }
        }
    }
}
