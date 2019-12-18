import XCTest

extension XCTestCase {
    func assertThat(serializedLogData: Data, fullyMatches jsonString: String, file: StaticString = #file, line: UInt = #line) {
        guard let jsonStringData = jsonString.data(using: .utf8) else {
            XCTFail("Cannot encode data from given json string.", file: file, line: line)
            return
        }

        guard let jsonObjectFromSerializedData = try? JSONSerialization.jsonObject(with: serializedLogData, options: []) as? NSArray else {
            XCTFail("Cannot decode JSON object from given `serializedLogData`.", file: file, line: line)
            return
        }
        guard let jsonObjectFromJSONString = try? JSONSerialization.jsonObject(with: jsonStringData, options: []) as? NSArray else {
            XCTFail("Cannot encode JSON object from given `jsonString`.", file: file, line: line)
            return
        }
        
        XCTAssertEqual(jsonObjectFromSerializedData, jsonObjectFromJSONString, file: file, line: line)
    }
    
    func assertThat<T: Equatable>(serializedLogData: Data, matchesValue value: T, onKeyPath keyPath: String, file: StaticString = #file, line: UInt = #line) {
        guard let jsonObjectFromSerializedData = try? JSONSerialization.jsonObject(with: serializedLogData, options: []) as? NSArray else {
            XCTFail("Cannot decode JSON object from given `serializedLogData`.", file: file, line: line)
            return
        }
        
        guard let jsonObjectValue = jsonObjectFromSerializedData.value(forKeyPath: keyPath) as? T else {
            XCTFail("Cannot access or cast value of type \(T.self) on key path \(keyPath).", file: file, line: line)
            return
        }
        
        XCTAssertEqual(jsonObjectValue, value, file: file, line: line)
    }
}
