import Testing
import Foundation
@testable import QwenPrime

@Suite("JSONValue Representation Contract Tests")
struct JSONValueContractTests {

    @Test("JSONValue supports recursive typed encoding, decoding, and value equality without Any")
    func testJSONValueRepresentation() throws {
        let nestedObject: JSONValue = .object([
            "stringKey": .string("hello"),
            "numberKey": .number(42.5),
            "boolKey": .bool(true),
            "nullKey": .null,
            "arrayKey": .array([
                .string("first"),
                .number(1.0),
                .bool(false)
            ]),
            "nestedObjectKey": .object([
                "inner": .string("value")
            ])
        ])

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(nestedObject)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(JSONValue.self, from: data)

        #expect(decoded == nestedObject)

        // Equatable assertions across distinct variants
        #expect(JSONValue.string("a") != JSONValue.string("b"))
        #expect(JSONValue.number(1.0) != JSONValue.number(2.0))
        #expect(JSONValue.bool(true) != JSONValue.bool(false))
        #expect(JSONValue.null == JSONValue.null)
        #expect(JSONValue.array([.number(1.0)]) != JSONValue.array([.number(2.0)]))
        #expect(JSONValue.object(["a": .string("1")]) != JSONValue.object(["a": .string("2")]))
    }
}
