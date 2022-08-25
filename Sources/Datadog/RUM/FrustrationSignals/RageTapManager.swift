/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
import UIKit


internal class RageTapManager{
    struct Constants {
        static let rageTapWindowTimeout : TimeInterval = 1 // 1 second
        static let maximumTouchDistance : Double = 48*2  // ~9mm
        static let minimumRageClicksPerSecond = 3
    }
    
    class RageTapChain {
        var lastTapPosition = CGPoint()
        var actionCommands = [RUMAddUserActionCommand]()
        var chainTimeout : DispatchWorkItem?
        var workQueue : DispatchQueue?
        
    }
    
    var rageTapChainPerUIElement = [ObjectIdentifier:RageTapChain]()
    var identifyRageTaps = true //TODO - Add API/property to change this
    
    
    func canAcceptTapIntoChain(chain: RageTapChain, tapLocation: CGPoint) -> Bool{
        if chain.actionCommands.count == 0 {
            return true
        }
        
        let sqDistanceX = (chain.lastTapPosition.x - tapLocation.x) * (chain.lastTapPosition.x - tapLocation.x)
        let sqDistanceY = (chain.lastTapPosition.y - tapLocation.y) * (chain.lastTapPosition.y - tapLocation.y)

        if (sqDistanceX + sqDistanceY) <= (RageTapManager.Constants.maximumTouchDistance * RageTapManager.Constants.maximumTouchDistance){
            return true;
        }
        
        return false
    }
    
    func tryToFinalizeChain(identifier: ObjectIdentifier){
        guard let chain = rageTapChainPerUIElement[identifier] else {
            return
        }
        
        guard let subscriber = subscriber else {
            return
        }
        
        var tapsWithinTimeout = [TimeInterval]()
        
        for tap in chain.actionCommands
        {
            tapsWithinTimeout.append(tap.time.timeIntervalSince1970)

            if(tapsWithinTimeout.count == RageTapManager.Constants.minimumRageClicksPerSecond){
                guard let firstTapTime = tapsWithinTimeout.first?.toInt64Milliseconds else {
                    break
                }
                guard let lastTapTime = tapsWithinTimeout.last?.toInt64Milliseconds else {
                    break
                }
                
                let timeDiff = lastTapTime - firstTapTime
                if (timeDiff < RageTapManager.Constants.rageTapWindowTimeout.toInt64Milliseconds)
                {
                    // Create rage tap at the last tap of the chain,
                    // even though we already had matching conditions before that
                    guard var lastCommand = chain.actionCommands.last else {
                        break
                    }
                    lastCommand.isRage = true

                    subscriber.process(command: lastCommand)
                    return
                    
                }else{
                    tapsWithinTimeout.remove(at: 0)
                }
            }
        }
        
        // Failed to identify chain, send withholded events
        for tap in chain.actionCommands
        {
            subscriber.process(command: tap)
        }
    }
    
    func addCommandIntoChain(command:RUMAddUserActionCommand, chain: RageTapChain, touch: UITouch){
        chain.actionCommands.append(command)
        chain.lastTapPosition = touch.location(in:nil)
    }
    
    func startTimeoutTimerForChain(chain: RageTapChain, identifier:ObjectIdentifier){
        let workItem = DispatchWorkItem { self.tryToFinalizeChain(identifier: identifier) }
        chain.chainTimeout = workItem
        DispatchQueue.global().asyncAfter(deadline: .now() + RageTapManager.Constants.rageTapWindowTimeout, execute: workItem)
    }
    
    func processActionCommand(command: RUMAddUserActionCommand, event: UIEvent) -> Bool {
        guard let targetView = command.targetView else {
            return false
        }
        guard let touch = event.allTouches?.first else {
            return false
        }
        
        if !identifyRageTaps {
            return false
        }
        let identifier = ObjectIdentifier(targetView)

        // Check if we already have an ongoing chain for this object
        if let rageTapChain = rageTapChainPerUIElement[identifier] {
            rageTapChain.chainTimeout?.cancel()
            
            if canAcceptTapIntoChain(chain: rageTapChain, tapLocation: touch.location(in: nil)){
                addCommandIntoChain(command: command, chain: rageTapChain, touch: touch)

                startTimeoutTimerForChain(chain: rageTapChain, identifier: identifier)
            } else{
                // Touch was outside of acceptance distance for current object.
                // Try to finalize the current chain and start a new one

                tryToFinalizeChain(identifier: identifier)
                
                rageTapChain.actionCommands.removeAll()
                addCommandIntoChain(command: command, chain: rageTapChain, touch: touch)
                startTimeoutTimerForChain(chain: rageTapChain, identifier: identifier)

            }
        }else{
            let newChain = RageTapChain()
            addCommandIntoChain(command: command, chain: newChain, touch: touch)
            rageTapChainPerUIElement[identifier] = newChain
            
            startTimeoutTimerForChain(chain: newChain, identifier: identifier)
        }
        
        return true

    }
    
    // TODO - Handle app closing (flush events)

    weak var subscriber: RUMCommandSubscriber?

    init(){}
}
