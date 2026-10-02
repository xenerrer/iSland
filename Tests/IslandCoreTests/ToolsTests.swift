import Foundation
import Testing
@testable import IslandCore

@Suite("New chat in a folder") struct NewChatTests {
    let root: URL
    let folder: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("island-folders-\(UUID().uuidString)", isDirectory: true)
        folder = root.appendingPathComponent("account/org", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    func directory(_ name: String) throws -> String {
        let url = root.appendingPathComponent("work/\(name)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url.path
    }

    func record(_ id: String, cwd: String, origin: String? = nil, age: TimeInterval) throws {
        let originPart = origin.map { "\"originCwd\":\"\($0)\"," } ?? ""
        let json = "{\"sessionId\":\"local_\(id)\",\"cliSessionId\":\"cli-\(id)\",\"cwd\":\"\(cwd)\",\(originPart)\"lastActivityAt\":1,\"enabledMcpTools\":{}}"
        let url = folder.appendingPathComponent("local_\(id).json")
        try Data(json.utf8).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -age)], ofItemAtPath: url.path)
    }

    @Test func listsFoldersNewestFirstWithoutRepeats() throws {
        let a = try directory("a"), b = try directory("b"), c = try directory("c")
        try record("1", cwd: a, age: 300)
        try record("2", cwd: b, age: 100)
        try record("3", cwd: a, age: 10) // a again, and the newest activity there
        try record("4", cwd: c, age: 200)
        #expect(DesktopChatIndex(root: root).recentFolders() == [a, b, c]) // a (10 s ago), b (100), c (200)
    }

    @Test func aWorktreeCountsAsItsOriginalFolder() throws {
        let origin = try directory("project"), worktree = try directory("project-wt")
        try record("w", cwd: worktree, origin: origin, age: 5)
        #expect(DesktopChatIndex(root: root).recentFolders() == [origin])
    }

    @Test func foldersThatAreGoneAndTheLimitAreRespected() throws {
        try record("x", cwd: "/definitely/not/here", age: 1)
        for i in 0..<5 { try record("f\(i)", cwd: try directory("dir\(i)"), age: TimeInterval(10 + i)) }
        let folders = DesktopChatIndex(root: root).recentFolders(limit: 3)
        #expect(folders.count == 3)
        #expect(!folders.contains("/definitely/not/here"))
    }

    @Test func pathsWithAccentsAndSpacesSurvive() throws {
        let odd = try directory("00. Áudios & mais")
        try record("o", cwd: odd, age: 1)
        #expect(DesktopChatIndex(root: root).recentFolders() == [odd])
    }

    @Test func buildsTheNewChatLinkAndRefusesOddPaths() throws {
        let link = try #require(ClaudeDesktop.newChatLink(inFolder: "/Users/me/00. Áudios & mais+1"))
        #expect(link.scheme == "claude" && link.host == "code" && link.path == "/new")
        // the folder must come back exactly, whatever characters it has
        #expect(URLComponents(url: link, resolvingAgainstBaseURL: false)?.queryItems?.first?.value == "/Users/me/00. Áudios & mais+1")
        #expect(link.absoluteString.hasPrefix("claude://code/new?folder=/Users/me/00."))
        for bad in ["", "relative/path", "~/x", "/a\u{0}b", "/a\nb"] { #expect(ClaudeDesktop.newChatLink(inFolder: bad) == nil, "\(bad)") }
    }
}

@Suite("Mirror photos") struct PhotoFilesTests {
    @Test func namesPhotosByTheMomentTheyWereTaken() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = Date(timeIntervalSince1970: 1_790_000_000)
        #expect(PhotoFiles.fileName(for: date, calendar: calendar) == "iSland 2026-09-21 14.13.20.jpg")
    }

    @Test func neverOverwritesAnEarlierPhoto() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("island-photos-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = Date(timeIntervalSince1970: 1_790_000_000)
        let first = PhotoFiles.uniqueURL(in: folder, for: date, calendar: calendar)
        try Data([1]).write(to: first)
        let second = PhotoFiles.uniqueURL(in: folder, for: date, calendar: calendar)
        try Data([2]).write(to: second)
        let third = PhotoFiles.uniqueURL(in: folder, for: date, calendar: calendar)
        #expect(first.lastPathComponent == "iSland 2026-09-21 14.13.20.jpg")
        #expect(second.lastPathComponent == "iSland 2026-09-21 14.13.20 2.jpg")
        #expect(third.lastPathComponent == "iSland 2026-09-21 14.13.20 3.jpg")
    }
}

@Suite("Full screen") struct FullscreenTests {
    let screen = WindowRect(x: 0, y: 0, width: 1512, height: 982)

    @Test func aWindowOverTheWholeScreenIsFullScreen() {
        let video = WindowRect(x: 0, y: 0, width: 1512, height: 982, layer: 0, ownerPID: 50)
        #expect(Fullscreen.isActive(windows: [video], screen: screen, ignoring: 1))
    }

    @Test func aMaximisedWindowLeavesTheMenuBarSoItDoesNotCount() {
        let maximised = WindowRect(x: 0, y: 37, width: 1512, height: 945, layer: 0, ownerPID: 50)
        let smaller = WindowRect(x: 100, y: 80, width: 900, height: 700, layer: 0, ownerPID: 51)
        #expect(!Fullscreen.isActive(windows: [maximised, smaller], screen: screen, ignoring: 1))
    }

    @Test func iSlandsOwnWindowsAndHigherLayersAreIgnored() {
        let own = WindowRect(x: 0, y: 0, width: 1512, height: 982, layer: 0, ownerPID: 1)
        let overlay = WindowRect(x: 0, y: 0, width: 1512, height: 982, layer: 25, ownerPID: 70) // a menu bar, a screen saver, an overlay
        #expect(!Fullscreen.isActive(windows: [own, overlay], screen: screen, ignoring: 1))
        #expect(!Fullscreen.isActive(windows: [], screen: screen, ignoring: 1))
    }

    @Test func anotherScreensFullScreenIsNotThisScreens() {
        let external = WindowRect(x: 1512, y: 0, width: 1920, height: 1080, layer: 0, ownerPID: 50)
        #expect(!Fullscreen.isActive(windows: [external], screen: screen, ignoring: 1))
        #expect(Fullscreen.isActive(windows: [external], screen: WindowRect(x: 1512, y: 0, width: 1920, height: 1080), ignoring: 1))
    }
}
