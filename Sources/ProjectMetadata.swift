import Cocoa

// MARK: - Tech stack detection

enum TechStack {
    case ios, expo, nextjs, vite, unknown
}

func detectTechStack(at path: String) -> TechStack {
    let fm = FileManager.default
    let contents = (try? fm.contentsOfDirectory(atPath: path)) ?? []

    // iOS / Swift
    if contents.contains("Package.swift") || contents.contains(where: { $0.hasSuffix(".xcodeproj") }) || contents.contains(where: { $0.hasSuffix(".xcworkspace") }) {
        return .ios
    }
    // Expo / React Native
    if contents.contains("app.json") || contents.contains("app.config.js") || contents.contains("app.config.ts") {
        return .expo
    }
    // Next.js
    if contents.contains(where: { $0.hasPrefix("next.config") }) {
        return .nextjs
    }
    // Vite
    if contents.contains(where: { $0.hasPrefix("vite.config") }) {
        return .vite
    }
    return .unknown
}

func techStackIcons(for stack: TechStack) -> [String] {
    switch stack {
    case .ios: return ["apple-finder-solid-sharp.svg", "ai-phone-01-solid-sharp.svg"]
    case .expo: return ["ai-phone-01-solid-sharp.svg"]
    case .nextjs: return ["jsx-02"]  // keep as HugeIcon font glyph
    case .vite: return ["zap"]       // keep as HugeIcon font glyph
    case .unknown: return []
    }
}

// MARK: - HugeIcons glyphs

let jsxGlyph: UInt32 = 989796
let zapGlyph: UInt32 = 992297

func hugeIconString(_ unicode: UInt32, size: CGFloat, alpha: CGFloat = 0.4) -> NSAttributedString {
    guard let fontName = iconFontName,
          let font = NSFont(name: fontName, size: size),
          let scalar = Unicode.Scalar(unicode) else {
        return NSAttributedString(string: "")
    }
    return NSAttributedString(string: String(scalar), attributes: [
        .foregroundColor: creamColor.withAlphaComponent(alpha),
        .font: font
    ])
}

// MARK: - Git status

enum GitStatus {
    case none, gitOnly, github
}

func checkGitStatus(at path: String) -> GitStatus {
    let gitDir = (path as NSString).appendingPathComponent(".git")
    guard FileManager.default.fileExists(atPath: gitDir) else { return .none }

    let configPath = (gitDir as NSString).appendingPathComponent("config")
    guard let config = try? String(contentsOfFile: configPath, encoding: .utf8) else { return .gitOnly }
    return config.contains("github.com") ? .github : .gitOnly
}
