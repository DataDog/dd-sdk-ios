//
//  DdRumImplementation.swift
//  DatadogSDK
//
//  Created by Xavier Gouchet on 30/11/2020.
//

import Foundation

class DdRumImplementation: DdRum {
    func startView(key: NSString, name: NSString, timestamp: Int64, context: NSDictionary) {
        print("DdRumImplementation.startView")
    }
    
    func stopView(key: NSString, timestamp: Int64, context: NSDictionary) {
        print("DdRumImplementation.stopView")
    }
    
    func startAction(type: NSString, name: NSString, timestamp: Int64, context: NSDictionary) {
        print("DdRumImplementation.startAction")
    }
    
    func stopAction(timestamp: Int64, context: NSDictionary) {
        print("DdRumImplementation.stopAction")
    }
    
    func addAction(type: NSString, name: NSString, timestamp: Int64, context: NSDictionary) {
        print("DdRumImplementation.addAction")
    }
    
    func startResource(key: NSString, method: NSString, url: NSString, timestamp: Int64, context: NSDictionary) {
        print("DdRumImplementation.startResource")
    }
    
    func stopResource(key: NSString, statusCode: Int64, kind: NSString, timestamp: Int64, context: NSDictionary) {
        print("DdRumImplementation.stopResource")
    }
    
    func addError(message: NSString, source: NSString, stacktrace: NSString, timestamp: Int64, context: NSDictionary) {
        print("DdRumImplementation.addError")
    }
    
    
}
