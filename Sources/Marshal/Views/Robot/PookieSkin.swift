import SwiftUI

/// A colour scheme for Pookie. Everything that is "Pookie-coloured" comes
/// from here; mood colours (amber, red, green beacons) are global and live in
/// `RobotPalette` so they mean the same thing on every skin.
struct PookieSkin: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let shellLight: Color
    let shellDark: Color
    let bodyLight: Color
    let bodyDark: Color
    let screen: Color
    let eye: Color
    let accent: Color
    let metal: Color

    static let indigo = PookieSkin(
        id: "indigo", name: "Indigo",
        shellLight: Color(red: 0.49, green: 0.56, blue: 1.0),
        shellDark: Color(red: 0.36, green: 0.28, blue: 0.92),
        bodyLight: Color(red: 0.42, green: 0.46, blue: 0.95),
        bodyDark: Color(red: 0.27, green: 0.21, blue: 0.76),
        screen: Color(red: 0.06, green: 0.08, blue: 0.19),
        eye: Color(red: 0.45, green: 0.95, blue: 1.0),
        accent: Color(red: 1.0, green: 0.62, blue: 0.35),
        metal: Color(red: 0.72, green: 0.76, blue: 0.9)
    )

    static let mint = PookieSkin(
        id: "mint", name: "Mint",
        shellLight: Color(red: 0.58, green: 0.95, blue: 0.82),
        shellDark: Color(red: 0.16, green: 0.70, blue: 0.58),
        bodyLight: Color(red: 0.42, green: 0.86, blue: 0.72),
        bodyDark: Color(red: 0.10, green: 0.55, blue: 0.46),
        screen: Color(red: 0.05, green: 0.13, blue: 0.13),
        eye: Color(red: 1.0, green: 0.97, blue: 0.70),
        accent: Color(red: 1.0, green: 0.52, blue: 0.45),
        metal: Color(red: 0.78, green: 0.86, blue: 0.84)
    )

    static let sunset = PookieSkin(
        id: "sunset", name: "Sunset",
        shellLight: Color(red: 1.0, green: 0.72, blue: 0.45),
        shellDark: Color(red: 0.93, green: 0.33, blue: 0.42),
        bodyLight: Color(red: 0.98, green: 0.60, blue: 0.40),
        bodyDark: Color(red: 0.80, green: 0.25, blue: 0.38),
        screen: Color(red: 0.16, green: 0.06, blue: 0.10),
        eye: Color(red: 1.0, green: 0.96, blue: 0.80),
        accent: Color(red: 0.55, green: 0.85, blue: 1.0),
        metal: Color(red: 0.92, green: 0.80, blue: 0.74)
    )

    static let graphite = PookieSkin(
        id: "graphite", name: "Graphite",
        shellLight: Color(red: 0.58, green: 0.61, blue: 0.68),
        shellDark: Color(red: 0.22, green: 0.24, blue: 0.30),
        bodyLight: Color(red: 0.46, green: 0.49, blue: 0.56),
        bodyDark: Color(red: 0.15, green: 0.17, blue: 0.22),
        screen: Color(red: 0.03, green: 0.04, blue: 0.06),
        eye: Color(red: 0.55, green: 1.0, blue: 0.65),
        accent: Color(red: 1.0, green: 0.80, blue: 0.25),
        metal: Color(red: 0.80, green: 0.82, blue: 0.86)
    )

    static let rose = PookieSkin(
        id: "rose", name: "Rose",
        shellLight: Color(red: 1.0, green: 0.74, blue: 0.86),
        shellDark: Color(red: 0.88, green: 0.34, blue: 0.60),
        bodyLight: Color(red: 0.98, green: 0.62, blue: 0.78),
        bodyDark: Color(red: 0.76, green: 0.26, blue: 0.50),
        screen: Color(red: 0.14, green: 0.05, blue: 0.11),
        eye: Color(red: 0.80, green: 0.96, blue: 1.0),
        accent: Color(red: 0.60, green: 0.95, blue: 0.70),
        metal: Color(red: 0.92, green: 0.82, blue: 0.88)
    )

    static let ocean = PookieSkin(
        id: "ocean", name: "Ocean",
        shellLight: Color(red: 0.45, green: 0.80, blue: 1.0),
        shellDark: Color(red: 0.10, green: 0.44, blue: 0.85),
        bodyLight: Color(red: 0.35, green: 0.70, blue: 0.95),
        bodyDark: Color(red: 0.07, green: 0.33, blue: 0.68),
        screen: Color(red: 0.03, green: 0.08, blue: 0.16),
        eye: Color(red: 0.95, green: 1.0, blue: 0.60),
        accent: Color(red: 1.0, green: 0.55, blue: 0.30),
        metal: Color(red: 0.76, green: 0.84, blue: 0.92)
    )

    static let all: [PookieSkin] = [indigo, mint, sunset, graphite, rose, ocean]
    static let `default` = indigo

    static func named(_ id: String) -> PookieSkin {
        all.first { $0.id == id } ?? .default
    }
}
