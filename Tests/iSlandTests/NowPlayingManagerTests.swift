import Testing
@testable import iSland

@Suite("Media adapter orphans") struct NowPlayingManagerTests {
    let framework = "/Applications/iSland.app/Contents/Frameworks/MediaRemoteAdapter.framework"

    @Test func onlyAdaptersAdoptedByLaunchdAreOrphans() {
        let list = """
          101     1 /usr/bin/perl /Applications/iSland.app/Contents/Resources/mediaremote-adapter.pl \(framework) stream --debounce=120
          102   500 /usr/bin/perl /Applications/iSland.app/Contents/Resources/mediaremote-adapter.pl \(framework) stream --debounce=120
          103     1 /usr/bin/perl /Applications/iSland.app/Contents/Resources/mediaremote-adapter.pl \(framework) send 2
          104     1 /usr/bin/perl /some/other/script.pl
          105     1 /Applications/Safari.app/Contents/MacOS/Safari
        """
        // 102 still has a living parent (another iSland); 103 is a one-off command; the rest are unrelated
        #expect(NowPlayingManager.orphanedAdapterPIDs(inProcessList: list) == [101])
    }

    @Test func garbageIsIgnored() {
        #expect(NowPlayingManager.orphanedAdapterPIDs(inProcessList: "").isEmpty)
        #expect(NowPlayingManager.orphanedAdapterPIDs(inProcessList: "not a process list\n\n  x y").isEmpty)
        #expect(NowPlayingManager.orphanedAdapterPIDs(inProcessList: "abc 1 mediaremote-adapter.pl x stream").isEmpty)
    }
}
