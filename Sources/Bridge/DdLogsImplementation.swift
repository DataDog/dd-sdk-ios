//
//  DdLogsImplementation.swift
//  DatadogSDK
//
//  Created by Xavier Gouchet on 30/11/2020.
//

import Foundation

class DdLogsImplementation: DdLogs {
    func debug(message: NSString, context: NSDictionary) {
        print("DdLogsImplementation.debug")
    }
    
    func info(message: NSString, context: NSDictionary) {
        print("DdLogsImplementation.info")
    }
    
    func warn(message: NSString, context: NSDictionary) {
        print("DdLogsImplementation.warn")
    }
    
    func error(message: NSString, context: NSDictionary) {
        print("DdLogsImplementation.error")
    }
}
