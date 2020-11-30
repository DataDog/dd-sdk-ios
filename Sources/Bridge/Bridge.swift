//
//  Bridge.swift
//  Datadog
//
//  Created by Xavier Gouchet on 27/11/2020.
//  Copyright © 2020 Datadog. All rights reserved.
//

import Foundation

public enum Bridge {
    
  public static func getDdLogs() -> DdLogs {
     return DdLogsImplementation()
  }
    
    
  public static func getDdRum() -> DdRum {
     return DdRumImplementation()
  }
    
  public static func getDdTrace() -> DdTrace {
     return DdTraceImpementation()
  }
    
  public static func getDdSdk() -> DdSdk {
     return DdSdkImplementation()
  }
}
