import AppKit
import Testing
@testable import CodexMeter

@MainActor
struct UpdateReleaseNotesTests {
    private func notes() -> NSAttributedString {
        let result = NSMutableAttributedString(string: """
        Version 1.10.0
        Latest changes. 🐛
        Version 1.9.0
        Earlier changes.
        Version 1.2.0
        Already installed.
        View full release history on GitHub
        """, attributes: [.font: NSFont.systemFont(ofSize: 13)])
        let footer = (result.string as NSString).range(of: "View full release history on GitHub")
        result.addAttribute(.link, value: UpdateReleaseNotes.historyURL, range: footer)
        let emphasis = (result.string as NSString).range(of: "Latest changes.")
        result.addAttribute(.font, value: NSFont.boldSystemFont(ofSize: 13), range: emphasis)
        return result
    }

    @Test
    func skippedReleasesAreIncludedWithFormattingAndFooterIntact() {
        let filtered = UpdateReleaseNotes.relevantNotes(notes(), installedVersion: "1.2.0")
        #expect(filtered.string.contains("Version 1.10.0"))
        #expect(filtered.string.contains("Version 1.9.0"))
        #expect(!filtered.string.contains("Version 1.2.0"))
        #expect(!filtered.string.contains("Already installed."))
        let emphasis = (filtered.string as NSString).range(of: "Latest changes.")
        #expect(filtered.attribute(.font, at: emphasis.location, effectiveRange: nil) as? NSFont == NSFont.boldSystemFont(ofSize: 13))
        let footer = (filtered.string as NSString).range(of: "View full release history on GitHub")
        #expect(filtered.attribute(.link, at: footer.location, effectiveRange: nil) as? URL == UpdateReleaseNotes.historyURL)
    }

    @Test
    func versionComparisonIsNumericAndExcludesInstalledVersion() {
        let filtered = UpdateReleaseNotes.relevantNotes(notes(), installedVersion: "1.9.0")
        #expect(filtered.string.contains("Version 1.10.0"))
        #expect(!filtered.string.contains("Version 1.9.0"))
        #expect(!filtered.string.contains("Version 1.2.0"))
        #expect(filtered.string.hasSuffix("View full release history on GitHub"))
    }

    @Test
    func notesWithoutGeneratedVersionHeadingsRemainUnchanged() {
        let original = NSAttributedString(string: "A single release’s notes.")
        #expect(UpdateReleaseNotes.relevantNotes(original, installedVersion: "1.2.0").isEqual(to: original))
    }

    @Test
    func footerSurvivesWhenNoReleaseIsNewer() {
        #expect(UpdateReleaseNotes.relevantNotes(notes(), installedVersion: "1.10.0").string == "View full release history on GitHub")
    }

    @Test
    func missingFooterStillFiltersOlderSections() {
        let notes = NSAttributedString(string: "Version 1.3.1\nNew.\nVersion 1.3.0\nOld.")
        #expect(UpdateReleaseNotes.relevantNotes(notes, installedVersion: "1.3.0").string == "Version 1.3.1\nNew.\n")
    }
}
