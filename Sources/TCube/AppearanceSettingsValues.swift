import CubeCore

/// Only the appearance page's values; applying defaults must preserve user content.
struct AppearanceSettingsValues: Equatable {
    var appearance: CubeAppearance
    var scale: Double
    var themeID: String
    var cycle: CubeThemeCycle
    var hover: CubeHoverSettings
    var expandsFacesOnClick: Bool
    var autoRotatesWhenIdle: Bool

    func apply(to configuration: inout CubeConfiguration) {
        configuration.appearance = appearance
        configuration.scale = scale
        configuration.themeID = themeID
        configuration.themeCycle = cycle
        configuration.hover = hover
        configuration.expandsFacesOnClick = expandsFacesOnClick
        configuration.autoRotatesWhenIdle = autoRotatesWhenIdle
    }
}

extension AppearanceSettingsValues {
    init(configuration: CubeConfiguration) {
        self.init(appearance: configuration.appearance, scale: configuration.scale,
                  themeID: configuration.themeID, cycle: configuration.themeCycle,
                  hover: configuration.hover, expandsFacesOnClick: configuration.expandsFacesOnClick,
                  autoRotatesWhenIdle: configuration.autoRotatesWhenIdle)
    }
}
