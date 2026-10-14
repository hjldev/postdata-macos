import Foundation
import Testing
@testable import PostDataKit

@Suite("VariableResolver")
struct VariableResolverTests {
    @Test func moreSpecificScopeWins() {
        let resolver = VariableResolver(
            globals: [KeyValue(key: "host", value: "global"), KeyValue(key: "g", value: "1")],
            collection: [KeyValue(key: "host", value: "collection")],
            environment: [KeyValue(key: "host", value: "env")]
        )
        #expect(resolver.resolve("{{host}}/{{g}}") == "env/1")
    }

    @Test func disabledVariablesAreIgnored() {
        let resolver = VariableResolver(
            globals: [KeyValue(key: "a", value: "global")],
            environment: [KeyValue(key: "a", value: "env", isEnabled: false)]
        )
        #expect(resolver.resolve("{{a}}") == "global")
    }

    @Test func nestedVariablesExpand() {
        let resolver = VariableResolver(environment: [
            KeyValue(key: "base", value: "https://{{host}}"),
            KeyValue(key: "host", value: "api.example.com"),
        ])
        #expect(resolver.resolve("{{base}}/v1") == "https://api.example.com/v1")
    }

    @Test func cyclesTerminate() {
        let resolver = VariableResolver(environment: [
            KeyValue(key: "a", value: "{{b}}"),
            KeyValue(key: "b", value: "{{a}}"),
        ])
        let result = resolver.resolve("{{a}}")
        #expect(result.contains("{{"))
    }

    @Test func unresolvedNamesAreReportedAndKept() {
        let resolver = VariableResolver(environment: [KeyValue(key: "known", value: "k")])
        let result = resolver.resolveDetailed("{{known}} {{ missing }} {{missing}} {{other}}")
        #expect(result.text == "k {{ missing }} {{missing}} {{other}}")
        #expect(result.unresolved == ["missing", "other"])
    }

    @Test func dynamicVariables() {
        let resolver = VariableResolver.empty
        let guid = resolver.resolve("{{$guid}}")
        #expect(UUID(uuidString: guid) != nil)
        let timestamp = resolver.resolve("{{$timestamp}}")
        #expect(Int(timestamp) != nil)
        let iso = resolver.resolve("{{$isoTimestamp}}")
        #expect(iso.hasSuffix("Z") && iso.contains("T"))
        #expect(resolver.resolveDetailed("{{$randomInt}}").unresolved.isEmpty)
        #expect(resolver.resolveDetailed("{{$nope}}").unresolved == ["$nope"])
    }

    @Test func nestedBracesPickInnermost() {
        let resolver = VariableResolver(environment: [KeyValue(key: "b", value: "B")])
        #expect(resolver.resolve("{{a{{b}}") == "{{aB")
        #expect(VariableResolver.referencedNames(in: "x {{a}} {{b}} {{a}}") == ["a", "b"])
    }
}

@Suite("URLQuerySync")
struct URLQuerySyncTests {
    @Test func splitsURL() {
        let parts = URLQuerySync.split("{{base}}/p?a=1&b#frag")
        #expect(parts.base == "{{base}}/p")
        #expect(parts.query == "a=1&b")
        #expect(parts.fragment == "frag")
    }

    @Test func urlEditUpdatesParamsKeepingDisabledAndIDs() {
        var request = HTTPRequest(url: "https://x.dev/?a=1&b=2")
        let firstID = request.queryParams[0].id
        request.setQueryParams(request.queryParams + [KeyValue(key: "off", value: "1", isEnabled: false)])
        #expect(request.url == "https://x.dev/?a=1&b=2")

        request.setURL("https://x.dev/?a=10&b=2&c=3")
        #expect(request.queryParams.map(\.key) == ["a", "b", "off", "c"])
        #expect(request.queryParams[0].id == firstID)
        #expect(request.queryParams[0].value == "10")
        #expect(request.queryParams[2].isEnabled == false)
    }

    @Test func paramEditRewritesQuery() {
        var request = HTTPRequest(url: "https://x.dev/path?a=1#top")
        var params = request.queryParams
        params[0].isEnabled = false
        params.append(KeyValue(key: "q", value: "{{term}}"))
        params.append(KeyValue(key: "flag"))
        request.setQueryParams(params)
        #expect(request.url == "https://x.dev/path?q={{term}}&flag#top")
    }

    @Test func removingAllParamsDropsQuestionMark() {
        var request = HTTPRequest(url: "https://x.dev/?a=1")
        request.setQueryParams([])
        #expect(request.url == "https://x.dev/")
    }
}

@Suite("KeyValueBulkFormat")
struct BulkFormatTests {
    @Test func roundTrip() {
        let items = [
            KeyValue(key: "Accept", value: "application/json"),
            KeyValue(key: "X-Off", value: "1", isEnabled: false),
            KeyValue(key: "Time", value: "12:30"),
        ]
        let text = KeyValueBulkFormat.serialize(items)
        #expect(text == "Accept:application/json\n//X-Off:1\nTime:12:30")
        let parsed = KeyValueBulkFormat.parse(text, existing: items)
        #expect(parsed == items)
    }
}
