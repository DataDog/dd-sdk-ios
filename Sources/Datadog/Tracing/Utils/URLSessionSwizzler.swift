/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

// TODO: RUMM-300 plug DDTracer into swizzled methods

internal class URLSessionSwizzler {
    enum Selectors {
        static let DataTaskWithURL = #selector(URLSession.dataTask(with:) as (URLSession) -> (URL) -> URLSessionDataTask)
        static let DataTaskWithRequest = #selector(URLSession.dataTask(with:) as (URLSession) -> (URLRequest) -> URLSessionDataTask)
        static let DataTaskWithURLCompletion = #selector(URLSession.dataTask(with:completionHandler:) as (URLSession) -> (URL, @escaping CompletionHandler) -> URLSessionDataTask)
        static let DataTaskWithRequestCompletion = #selector(URLSession.dataTask(with:completionHandler:) as (URLSession) -> (URLRequest, @escaping CompletionHandler) -> URLSessionDataTask)
    }

    typealias CompletionHandler = (Data?, URLResponse?, Error?) -> Void
    enum TypedIMPs {
        typealias DataTaskWithURL = @convention(c) (URLSession, Selector, URL) -> URLSessionDataTask
        typealias DataTaskWithRequest = @convention(c) (URLSession, Selector, URLRequest) -> URLSessionDataTask
        typealias DataTaskWithURLCompletion = @convention(c) (URLSession, Selector, URL, @escaping CompletionHandler) -> URLSessionDataTask
        typealias DataTaskWithURLRequestCompletion = @convention(c) (URLSession, Selector, URLRequest, @escaping CompletionHandler) -> URLSessionDataTask
    }
    enum TypedBlocks {
        typealias DataTaskWithURL = @convention(block) (URLSession, URL) -> URLSessionDataTask
        typealias DataTaskWithRequest = @convention(block) (URLSession, URLRequest) -> URLSessionDataTask
        typealias DataTaskWithURLCompletion = @convention(block) (URLSession, URL, @escaping CompletionHandler) -> URLSessionDataTask
        typealias DataTaskWithRequestCompletion = @convention(block) (URLSession, URLRequest, @escaping CompletionHandler) -> URLSessionDataTask
    }

    static let subjectClass = URLSession.self
    private static let swizzler = MethodSwizzler.shared

    static func swizzle() throws {
        try swizzleDataTaskWithURL()
        try swizzleDataTaskWithRequest()
        try swizzleDataTaskWithURLCompletionHandler()
        try swizzleDataTaskWithRequestCompletionHandler()
    }

    static func unswizzle() throws {
        try swizzler.unswizzle(selector: Selectors.DataTaskWithURL, in: subjectClass)
        try swizzler.unswizzle(selector: Selectors.DataTaskWithRequest, in: subjectClass)
        try swizzler.unswizzle(selector: Selectors.DataTaskWithURLCompletion, in: subjectClass)
        try swizzler.unswizzle(selector: Selectors.DataTaskWithRequestCompletion, in: subjectClass)
    }

    static func swizzleDataTaskWithURL() throws {
        // typealiases cannot be generic as C/block conventions don't support generics
        // note that _Block doesn't have Selector parameter
        typealias TypedIMP = TypedIMPs.DataTaskWithURL
        typealias TypedBlockIMP = TypedBlocks.DataTaskWithURL
        let sel = Selectors.DataTaskWithURL

        let typedOriginalImp: TypedIMP = try swizzler.currentImplementation(of: sel, in: subjectClass)

        let newImpBlock: TypedBlockIMP = { [impSelector = sel] impSelf, impURL -> URLSessionDataTask in
            return typedOriginalImp(impSelf, impSelector, impURL)
        }
        let newImp: IMP = imp_implementationWithBlock(newImpBlock)
        try swizzler.swizzle(selector: sel, in: subjectClass, with: newImp)
    }

    static func swizzleDataTaskWithRequest() throws {
        typealias TypedIMP = TypedIMPs.DataTaskWithRequest
        typealias TypedBlockIMP = TypedBlocks.DataTaskWithRequest
        let sel = Selectors.DataTaskWithRequest

        let typedOriginalImp: TypedIMP = try swizzler.currentImplementation(of: sel, in: subjectClass)

        let newImpBlock: TypedBlockIMP = { [impSelector = sel] impSelf, impURLRequest -> URLSessionDataTask in
            return typedOriginalImp(impSelf, impSelector, impURLRequest)
        }
        let newImp: IMP = imp_implementationWithBlock(newImpBlock)
        try swizzler.swizzle(selector: sel, in: subjectClass, with: newImp)
    }

    static func swizzleDataTaskWithURLCompletionHandler() throws {
        typealias TypedIMP = TypedIMPs.DataTaskWithURLCompletion
        typealias TypedBlockIMP = TypedBlocks.DataTaskWithURLCompletion
        let sel = Selectors.DataTaskWithURLCompletion

        let typedOriginalImp: TypedIMP = try swizzler.currentImplementation(of: sel, in: subjectClass)

        let newImpBlock: TypedBlockIMP = { [impSelector = sel] impSelf, impURL, impCompletion -> URLSessionDataTask in
            return typedOriginalImp(impSelf, impSelector, impURL, impCompletion)
        }
        let newImp: IMP = imp_implementationWithBlock(newImpBlock)
        try swizzler.swizzle(selector: sel, in: subjectClass, with: newImp)
    }

    static func swizzleDataTaskWithRequestCompletionHandler() throws {
        typealias TypedIMP = TypedIMPs.DataTaskWithURLRequestCompletion
        typealias TypedBlockIMP = TypedBlocks.DataTaskWithRequestCompletion
        let sel = Selectors.DataTaskWithRequestCompletion

        let typedOriginalImp: TypedIMP = try swizzler.currentImplementation(of: sel, in: subjectClass)

        let newImpBlock: TypedBlockIMP = { [impSelector = sel] impSelf, impURLRequest, impCompletion -> URLSessionDataTask in
            return typedOriginalImp(impSelf, impSelector, impURLRequest, impCompletion)
        }
        let newImp: IMP = imp_implementationWithBlock(newImpBlock)
        try swizzler.swizzle(selector: sel, in: subjectClass, with: newImp)
    }
}
