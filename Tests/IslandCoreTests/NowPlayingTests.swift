import Foundation
import Testing
@testable import IslandCore

@Suite("NowPlaying") struct NowPlayingTests {
    // The shape the adapter really prints (captured on macOS 27), with invented content.
    static let full = #"{"type":"data","diff":false,"payload":{"playbackRate":1,"album":"Hurry Up","elapsedTime":83.5,"timestamp":"2026-10-01T15:43:55Z","bundleIdentifier":"com.spotify.client","processIdentifier":5175,"artworkData":"AAEC","title":"Midnight City","artworkMimeType":"image/jpeg","duration":244.2,"artist":"M83","playing":true}}"#

    func line(_ json: String) -> Data { Data(json.utf8) }

    @Test func aFullMessageSetsEverything() {
        var decoder = NowPlayingDecoder()
        let changed1 = decoder.ingest(line: line(Self.full))
        #expect(changed1)
        let state = decoder.state
        #expect(state.title == "Midnight City")
        #expect(state.artist == "M83")
        #expect(state.album == "Hurry Up")
        #expect(state.bundleID == "com.spotify.client")
        #expect(state.isPlaying)
        #expect(state.duration == 244.2)
        #expect(state.elapsed == 83.5)
        #expect(state.artworkBase64 == "AAEC")
        #expect(state.hasTrack)
        #expect(state.timestamp != nil)
    }

    @Test func aDiffMergesOnlyWhatChanged() {
        var decoder = NowPlayingDecoder()
        decoder.ingest(line: line(Self.full))
        let changed1 = decoder.ingest(line: line(#"{"type":"data","diff":true,"payload":{"playing":false,"elapsedTime":90}}"#))
        #expect(changed1)
        #expect(decoder.state.title == "Midnight City") // untouched
        #expect(decoder.state.isPlaying == false)
        #expect(decoder.state.elapsed == 90)
    }

    @Test func nullClearsAKey() {
        var decoder = NowPlayingDecoder()
        decoder.ingest(line: line(Self.full))
        decoder.ingest(line: line(#"{"type":"data","diff":true,"payload":{"artworkData":null,"album":null}}"#))
        #expect(decoder.state.artworkBase64 == nil)
        #expect(decoder.state.album == "")
        #expect(decoder.state.title == "Midnight City")
    }

    @Test func anEmptyMessageMeansNothingIsPlaying() {
        var decoder = NowPlayingDecoder()
        decoder.ingest(line: line(Self.full))
        let changed1 = decoder.ingest(line: line(#"{"type":"data","diff":false}"#))
        #expect(changed1)
        #expect(!decoder.state.hasTrack)
        #expect(!decoder.state.isPlaying)
        let comesBack = decoder.ingest(line: line(Self.full)) // and it can come back
        #expect(comesBack)
        let changed2 = decoder.ingest(line: line(#"{"type":"data","diff":false,"payload":{}}"#))
        #expect(changed2)
        #expect(!decoder.state.hasTrack)
    }

    @Test func malformedAndForeignLinesAreIgnored() {
        var decoder = NowPlayingDecoder()
        decoder.ingest(line: line(Self.full))
        for junk in ["", "not json", "{", #"{"type":"log","payload":{"title":"x"}}"#, "[1,2,3]"] {
            let changed = decoder.ingest(line: line(junk))
            #expect(!changed)
        }
        #expect(decoder.state.title == "Midnight City")
    }

    @Test func repeatingTheSameMessageIsNotAChange() {
        var decoder = NowPlayingDecoder()
        let changed1 = decoder.ingest(line: line(Self.full))
        #expect(changed1)
        let changed2 = decoder.ingest(line: line(Self.full))
        #expect(!changed2)
    }

    @Test func theClockKeepsRunningWhilePlayingAndStopsWhenPaused() throws {
        var decoder = NowPlayingDecoder()
        decoder.ingest(line: line(Self.full))
        let reported = try #require(decoder.state.timestamp)
        #expect(decoder.state.elapsedNow(at: reported.addingTimeInterval(10)) == 93.5)
        #expect(decoder.state.elapsedNow(at: reported.addingTimeInterval(10_000)) == 244.2) // never past the end
        decoder.ingest(line: line(#"{"type":"data","diff":true,"payload":{"playing":false}}"#))
        #expect(decoder.state.elapsedNow(at: reported.addingTimeInterval(10)) == 83.5)
    }

    @Test func fractionalTimestampsParseToo() {
        var decoder = NowPlayingDecoder()
        decoder.ingest(line: line(#"{"type":"data","diff":false,"payload":{"title":"x","timestamp":"2026-10-01T15:43:55.250Z"}}"#))
        #expect(decoder.state.timestamp != nil)
    }
}
