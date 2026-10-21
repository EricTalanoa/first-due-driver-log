#if os(iOS)
import SwiftUI
import DriverLogCore

/// First Due colors, matching the website.
enum Brand {
    static let red = Color(red: 0xB5 / 255, green: 0x21 / 255, blue: 0x27 / 255)
    static let brightRed = Color(red: 0xCF / 255, green: 0x30 / 255, blue: 0x37 / 255)
    static let darkRed = Color(red: 0x9A / 255, green: 0x1E / 255, blue: 0x24 / 255)
    static let card = Color(red: 0x20 / 255, green: 0x25 / 255, blue: 0x2B / 255)
    static let cardRaised = Color(red: 0x2C / 255, green: 0x32 / 255, blue: 0x3A / 255)
    static let cardLine = Color(red: 0x53 / 255, green: 0x5A / 255, blue: 0x63 / 255)
    static let page = Color(red: 0xF2 / 255, green: 0xF3 / 255, blue: 0xF5 / 255)
    static let paperLine = Color(red: 0xDC / 255, green: 0xE0 / 255, blue: 0xE5 / 255)
    static let ink = Color(red: 0x25 / 255, green: 0x2B / 255, blue: 0x32 / 255)
    static let muted = Color(red: 0x68 / 255, green: 0x71 / 255, blue: 0x7B / 255)
    static let onDark = Color(red: 0xC2 / 255, green: 0xC8 / 255, blue: 0xD0 / 255)
    static let warn = Color(red: 0x8C / 255, green: 0x57 / 255, blue: 0x10 / 255)
    static let warnBackground = Color(red: 0xFF / 255, green: 0xF8 / 255, blue: 0xE7 / 255)

    static func color(for status: Status) -> Color {
        switch status {
        case .offDuty: return Color(red: 0x4F / 255, green: 0x7A / 255, blue: 0x5C / 255)
        case .sleeper: return Color(red: 0x4A / 255, green: 0x5F / 255, blue: 0x8C / 255)
        case .driving: return red
        case .onDuty: return Color(red: 0xB8 / 255, green: 0x7A / 255, blue: 0x1E / 255)
        }
    }

    static func icon(for status: Status) -> String {
        switch status {
        case .offDuty: return "cup.and.saucer"
        case .sleeper: return "bed.double"
        case .driving: return "truck.box"
        case .onDuty: return "clock"
        }
    }
}

/// Small spaced capitals, like the website's eyebrow labels.
struct Eyebrow: View {
    let text: String
    var color: Color = Brand.muted
    init(_ text: String, color: Color = Brand.muted) { self.text = text; self.color = color }
    var body: some View {
        Text(text.uppercased()).font(.caption.weight(.semibold)).tracking(1.4).foregroundStyle(color)
    }
}

/// White rounded card on the gray page.
struct Paper<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Brand.paperLine))
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    var color: Color = Brand.brightRed
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.title3.weight(.bold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 60)
            .background(color.opacity(configuration.isPressed ? 0.8 : 1), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct OutlineButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Brand.ink)
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .background(Color.white.opacity(configuration.isPressed ? 0.7 : 1), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(white: 0.8)))
    }
}

extension View {
    /// A labelled form field in the website's style.
    func field(_ label: String, labelColor: Color = Brand.ink) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.subheadline.weight(.semibold)).foregroundStyle(labelColor)
            self
                .padding(.horizontal, 12)
                .frame(minHeight: 46)
                .foregroundStyle(Brand.ink)
                .background(.white, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(white: 0.8)))
        }
    }
}

func milesText(_ m: Double) -> String { String(format: "%.1f", m) }
#endif
