//
//  DdTraceImpementation.swift
//  DatadogSDK
//
//  Created by Xavier Gouchet on 30/11/2020.
//

import Foundation

class DdTraceImpementation: DdTrace {
    func startSpan(operation: NSString, timestamp: Int64, context: NSDictionary) -> NSString {
        print("DdTraceImpementation.startSpan")
        return ""
    }
    
    func finishSpan(spanId: NSString, timestamp: Int64, context: NSDictionary) {
        print("DdTraceImpementation.finishSpan")
    }
    
    
}
