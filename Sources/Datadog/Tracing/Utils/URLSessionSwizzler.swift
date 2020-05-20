/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

// TODO: RUMM-300 plug DDTracer into swizzled methods

internal class URLSessionSwizzler {
    static let subjectClass = URLSession.self

    private typealias CompletionHandler = (Data?, URLResponse?, Error?) -> Void

    static let sel_DataTaskWithURL = #selector(URLSession.dataTask(with:) as (URLSession) -> (URL) -> URLSessionDataTask)
    static let sel_DataTaskWithRequest = #selector(URLSession.dataTask(with:) as (URLSession) -> (URLRequest) -> URLSessionDataTask)
    static let sel_DataTaskWithURLCompletion = #selector(URLSession.dataTask(with:completionHandler:) as (URLSession) -> (URL, @escaping CompletionHandler) -> URLSessionDataTask)
    static let sel_DataTaskWithRequestCompletion = #selector(URLSession.dataTask(with:completionHandler:) as (URLSession) -> (URLRequest, @escaping CompletionHandler) -> URLSessionDataTask)

    private static let swizzler = MethodSwizzler.shared

    private typealias DataTaskWithURL_C = @convention(c) (AnyObject, Selector, URL) -> URLSessionDataTask
    private typealias DataTaskWithURL_Block = @convention(block) (AnyObject, URL) -> URLSessionDataTask
    private typealias DataTaskWithRequest_C = @convention(c) (AnyObject, Selector, URLRequest) -> URLSessionDataTask
    private typealias DataTaskWithRequest_Block = @convention(block) (AnyObject, URLRequest) -> URLSessionDataTask

    private typealias DataTaskWithURLCompletion_C = @convention(c) (AnyObject, Selector, URL, @escaping CompletionHandler) -> URLSessionDataTask
    private typealias DataTaskWithURLCompletion_Block = @convention(block) (AnyObject, URL, @escaping CompletionHandler) -> URLSessionDataTask
    private typealias DataTaskWithRequestCompletion_C = @convention(c) (AnyObject, Selector, URLRequest, @escaping CompletionHandler) -> URLSessionDataTask
    private typealias DataTaskWithRequestCompletion_Block = @convention(block) (AnyObject, URLRequest, @escaping CompletionHandler) -> URLSessionDataTask

    static func swizzle() throws {
        try swizzleDataTaskWithURL()
        try swizzleDataTaskWithRequest()
        try swizzleDataTaskWithURLCompletionHandler()
        try swizzleDataTaskWithRequestCompletionHandler()
    }

    static func unswizzle() throws {
        try swizzler.unswizzle(selector: sel_DataTaskWithURL, in: subjectClass)
        try swizzler.unswizzle(selector: sel_DataTaskWithRequest, in: subjectClass)
        try swizzler.unswizzle(selector: sel_DataTaskWithURLCompletion, in: subjectClass)
        try swizzler.unswizzle(selector: sel_DataTaskWithRequestCompletion, in: subjectClass)
    }

    static func swizzleDataTaskWithURL() throws {
        // typealiases cannot be generic as C/block conventions don't support generics
        // note that _Block doesn't have Selector parameter
        typealias TypedIMP = DataTaskWithURL_C
        typealias TypedBlockIMP = DataTaskWithURL_Block

        let sel = sel_DataTaskWithURL
        let typedOriginalImp: TypedIMP = try swizzler.currentImplementation(of: sel, in: subjectClass)

        let newImpBlock: TypedBlockIMP = { [impSelector = sel] impSelf, impURL -> URLSessionDataTask in
            return typedOriginalImp(impSelf, impSelector, impURL)
        }
        let newImp: IMP = imp_implementationWithBlock(newImpBlock)
        try swizzler.swizzle(selector: sel, in: subjectClass, with: newImp)
    }

    static func swizzleDataTaskWithRequest() throws {
        typealias TypedIMP = DataTaskWithRequest_C
        typealias TypedBlockIMP = DataTaskWithRequest_Block

        let sel = sel_DataTaskWithRequest
        let typedOriginalImp: TypedIMP = try swizzler.currentImplementation(of: sel, in: subjectClass)

        let newImpBlock: TypedBlockIMP = { [impSelector = sel] impSelf, impURLRequest -> URLSessionDataTask in
            return typedOriginalImp(impSelf, impSelector, impURLRequest)
        }
        let newImp: IMP = imp_implementationWithBlock(newImpBlock)
        try swizzler.swizzle(selector: sel, in: subjectClass, with: newImp)
    }

    static func swizzleDataTaskWithURLCompletionHandler() throws {
        typealias TypedIMP = DataTaskWithURLCompletion_C
        typealias TypedBlockIMP = DataTaskWithURLCompletion_Block

        let sel = sel_DataTaskWithURLCompletion
        let typedOriginalImp: TypedIMP = try swizzler.currentImplementation(of: sel, in: subjectClass)

        let newImpBlock: TypedBlockIMP = { [impSelector = sel] impSelf, impURL, impCompletion -> URLSessionDataTask in
            return typedOriginalImp(impSelf, impSelector, impURL, impCompletion)
        }
        let newImp: IMP = imp_implementationWithBlock(newImpBlock)
        try swizzler.swizzle(selector: sel, in: subjectClass, with: newImp)
    }

    static func swizzleDataTaskWithRequestCompletionHandler() throws {
        typealias TypedIMP = DataTaskWithRequestCompletion_C
        typealias TypedBlockIMP = DataTaskWithRequestCompletion_Block

        let sel = sel_DataTaskWithRequestCompletion
        let typedOriginalImp: TypedIMP = try swizzler.currentImplementation(of: sel, in: subjectClass)

        let newImpBlock: TypedBlockIMP = { [impSelector = sel] impSelf, impURLRequest, impCompletion -> URLSessionDataTask in
            return typedOriginalImp(impSelf, impSelector, impURLRequest, impCompletion)
        }
        let newImp: IMP = imp_implementationWithBlock(newImpBlock)
        try swizzler.swizzle(selector: sel, in: subjectClass, with: newImp)
    }
}
