import Foundation
import Testing
@testable import CodexMeter

@MainActor
struct CLIInstallServiceTests {
    @Test
    func installsAndRemovesOwnedSymlink() throws {
        let fixture = try CLIInstallFixture()
        defer { fixture.cleanUp() }

        #expect(fixture.service.status(for: fixture.location).state == .notInstalled)
        try fixture.service.install(in: fixture.location)
        #expect(fixture.service.status(for: fixture.location).state == .installed)
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: fixture.linkURL.path) == fixture.cliURL.path)

        try fixture.service.remove(from: fixture.location)
        #expect(fixture.service.status(for: fixture.location).state == .notInstalled)
    }

    @Test
    func neverOverwritesRegularFileOrForeignSymlink() throws {
        let fileFixture = try CLIInstallFixture()
        defer { fileFixture.cleanUp() }
        FileManager.default.createFile(atPath: fileFixture.linkURL.path, contents: Data())

        #expect(fileFixture.service.status(for: fileFixture.location).state == .existingFile)
        #expect(throws: CLIInstallServiceError.existingFile(fileFixture.linkURL.path)) {
            try fileFixture.service.install(in: fileFixture.location)
        }

        let linkFixture = try CLIInstallFixture()
        defer { linkFixture.cleanUp() }
        try FileManager.default.createSymbolicLink(
            at: linkFixture.linkURL,
            withDestinationURL: linkFixture.rootURL.appending(path: "other")
        )

        #expect(linkFixture.service.status(for: linkFixture.location).state == .foreignSymlink)
        #expect(throws: CLIInstallServiceError.foreignSymlink(linkFixture.linkURL.path)) {
            try linkFixture.service.install(in: linkFixture.location)
        }
    }

    @Test
    func updatesOnlyRecognizableStaleCodexMeterSymlink() throws {
        let fixture = try CLIInstallFixture()
        defer { fixture.cleanUp() }
        let oldCLI = fixture.rootURL
            .appending(path: "Old")
            .appending(path: "CodexMeter.app")
            .appending(path: "Contents/Helpers/codexmeter")
        try FileManager.default.createSymbolicLink(at: fixture.linkURL, withDestinationURL: oldCLI)

        #expect(fixture.service.status(for: fixture.location).state == .staleCodexMeterSymlink)
        try fixture.service.install(in: fixture.location)
        #expect(fixture.service.status(for: fixture.location).state == .installed)
    }

    @Test
    func reportsMissingBundledCommandAndBuildsNonForcingManualCommand() throws {
        let fixture = try CLIInstallFixture(createCLI: false)
        defer { fixture.cleanUp() }

        #expect(fixture.service.status(for: fixture.location).state == .missingBundledCLI)
        #expect(throws: CLIInstallServiceError.missingBundledCLI) {
            try fixture.service.install(in: fixture.location)
        }
        #expect(fixture.service.manualInstallCommand(for: fixture.location) ==
            "ln -s '\(fixture.cliURL.path)' '\(fixture.linkURL.path)'")
    }
}

private struct CLIInstallFixture {
    let rootURL: URL
    let binURL: URL
    let cliURL: URL
    let location: CLIInstallLocation
    let service: CLIInstallService

    var linkURL: URL {
        binURL.appending(path: "codexmeter")
    }

    init(createCLI: Bool = true) throws {
        rootURL = FileManager.default.temporaryDirectory
            .appending(path: "CodexMeterCLIInstallTests")
            .appending(path: UUID().uuidString)
        binURL = rootURL.appending(path: "bin")
        cliURL = rootURL.appending(path: "codexmeter")
        location = CLIInstallLocation(path: binURL.path)
        service = CLIInstallService(cliURL: cliURL)

        try FileManager.default.createDirectory(at: binURL, withIntermediateDirectories: true)

        if createCLI {
            FileManager.default.createFile(atPath: cliURL.path, contents: Data())
        }
    }

    func cleanUp() {
        try? FileManager.default.removeItem(at: rootURL)
    }
}
