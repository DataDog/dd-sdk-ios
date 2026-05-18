/*
   * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
   * This product includes software developed at Datadog (https://www.datadoghq.com/).
   * Copyright 2019-Present Datadog, Inc.
   */

  import XCTest
  import TestUtilities

  private struct ThrowingEncodable: Encodable {
      func encode(to encoder: Encoder) throws {
          throw NSError(domain: "test", code: 0)
      }
  }

  class DDAssertDiffTests: XCTestCase {
      func testIdenticalValues_returnEmptyDiff() {
          struct Foo: Encodable {
              let a: Int
              let b: String
          }
          let value = Foo(a: 1, b: "hello")

          DDAssertDiff(value, value) { diffs in
              XCTAssertEqual(diffs.differentKeyPaths, [])
              XCTAssertEqual(diffs.addedKeyPaths, [])
              XCTAssertEqual(diffs.removedKeyPaths, [])
          }
      }

      func testOneFieldChanged_appearsInDifferentKeyPaths() {
           struct Foo: Encodable {
               let a: Int
               let b: String
           }
           let value1 = Foo(a: 1, b: "hello")
           let value2 = Foo(a: 1, b: "world")

           DDAssertDiff(value1, value2) { diffs in
               XCTAssertEqual(diffs.differentKeyPaths, ["b"])
               XCTAssertEqual(diffs.addedKeyPaths, [])
               XCTAssertEqual(diffs.removedKeyPaths, [])
           }
       }

      func testNestedFieldAdded_appearsInAddedKeyPaths() {
            struct Nested: Encodable {
                let x: Int
            }
            struct Foo: Encodable {
                let a: Int
                let nested: Nested?
            }
            let value1 = Foo(a: 1, nested: nil)
            let value2 = Foo(a: 1, nested: Nested(x: 5))

            DDAssertDiff(value1, value2) { diffs in
                XCTAssertEqual(diffs.differentKeyPaths, [])
                XCTAssertEqual(diffs.addedKeyPaths, ["nested.x"])
                XCTAssertEqual(diffs.removedKeyPaths, [])
            }
        }

      func testNestedFieldRemoved_appearsInRemovedKeyPaths() {
            struct Nested: Encodable {
                let x: Int
            }
            struct Foo: Encodable {
                let a: Int
                let nested: Nested?
            }
            let value1 = Foo(a: 1, nested: Nested(x: 5))
            let value2 = Foo(a: 1, nested: nil)

            DDAssertDiff(value1, value2) { diffs in
                XCTAssertEqual(diffs.differentKeyPaths, [])
                XCTAssertEqual(diffs.addedKeyPaths, [])
                XCTAssertEqual(diffs.removedKeyPaths, ["nested.x"])
            }
        }

      func testArrayElementDiffers_appearsInDifferentKeyPaths() {
           struct Item: Encodable {
               let x: Int
           }
           struct Foo: Encodable {
               let arr: [Item]
           }
           let value1 = Foo(arr: [Item(x: 1), Item(x: 2)])
           let value2 = Foo(arr: [Item(x: 99), Item(x: 2)])

           DDAssertDiff(value1, value2) { diffs in
               XCTAssertEqual(diffs.differentKeyPaths, ["arr.0.x"])
               XCTAssertEqual(diffs.addedKeyPaths, [])
               XCTAssertEqual(diffs.removedKeyPaths, [])
           }
       }

      func testArrayLengthDiffers_extraIndicesAppearInAddedKeyPaths() {
           struct Item: Encodable {
               let x: Int
           }
           struct Foo: Encodable {
               let arr: [Item]
           }
           let value1 = Foo(arr: [Item(x: 1)])
           let value2 = Foo(arr: [Item(x: 1), Item(x: 2)])

           DDAssertDiff(value1, value2) { diffs in
               XCTAssertEqual(diffs.differentKeyPaths, [])
               XCTAssertEqual(diffs.addedKeyPaths, ["arr.1.x"])
               XCTAssertEqual(diffs.removedKeyPaths, [])
           }
       }

      func testEmptyArrayVsNonEmpty_appearsInRemovedAndAdded() {
            struct Foo: Encodable {
                let arr: [Int]
            }
            let value1 = Foo(arr: [])
            let value2 = Foo(arr: [1, 2])

            DDAssertDiff(value1, value2) { diffs in
                XCTAssertEqual(diffs.differentKeyPaths, [])
                XCTAssertEqual(diffs.removedKeyPaths, ["arr"])
                XCTAssertEqual(diffs.addedKeyPaths, ["arr.0", "arr.1"])
            }
        }

      func testEmptyObjectVsNonEmpty_appearsInRemovedAndAdded() {
           struct Foo: Encodable {
               let nested: [String: Int]
           }
           let value1 = Foo(nested: [:])
           let value2 = Foo(nested: ["x": 5])

           DDAssertDiff(value1, value2) { diffs in
               XCTAssertEqual(diffs.differentKeyPaths, [])
               XCTAssertEqual(diffs.removedKeyPaths, ["nested"])
               XCTAssertEqual(diffs.addedKeyPaths, ["nested.x"])
           }
       }

      func testBoolVsIntLeaf_areDistinguished() {
            enum Toggle: Encodable {
                case asBool(Bool)
                case asInt(Int)

                func encode(to encoder: Encoder) throws {
                    var container = encoder.singleValueContainer()
                    switch self {
                    case .asBool(let b):
                        try container.encode(b)
                    case .asInt(let i):
                        try container.encode(i)
                    }
                }
            }
            struct Foo: Encodable {
                let value: Toggle
            }
            let value1 = Foo(value: .asBool(true))
            let value2 = Foo(value: .asInt(1))

            DDAssertDiff(value1, value2) { diffs in
                XCTAssertEqual(diffs.differentKeyPaths, ["value"])
                XCTAssertEqual(diffs.addedKeyPaths, [])
                XCTAssertEqual(diffs.removedKeyPaths, [])
            }
        }

      func testEncoderThrows_failsAtCallSite() {
           var verifyClosureCalled = false
           XCTExpectFailure("DDAssertDiff should fail when the encoder throws") {
               DDAssertDiff(ThrowingEncodable(), ThrowingEncodable()) { _ in
                   verifyClosureCalled = true
               }
           }
           XCTAssertFalse(verifyClosureCalled, "verify closure should not be called when encoder throws")
       }

      func testNonObjectRoot_failsAtCallSite() {
           var verifyClosureCalled = false
           XCTExpectFailure("DDAssertDiff should fail when the encoded value is not a JSON object") {
               DDAssertDiff([1, 2, 3], [4, 5, 6]) { _ in
                   verifyClosureCalled = true
               }
           }
           XCTAssertFalse(verifyClosureCalled, "verify closure should not be called for non-object root")
       }

      func testArrayLengthDiffers_extraIndicesAppearInRemovedKeyPaths() {
            struct Foo: Encodable {
                let arr: [Int]
            }
            let value1 = Foo(arr: [1, 2])
            let value2 = Foo(arr: [1])

            DDAssertDiff(value1, value2) { diffs in
                XCTAssertEqual(diffs.differentKeyPaths, [])
                XCTAssertEqual(diffs.addedKeyPaths, [])
                XCTAssertEqual(diffs.removedKeyPaths, ["arr.1"])
            }
        }
  }
