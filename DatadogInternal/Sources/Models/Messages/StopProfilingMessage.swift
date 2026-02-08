public struct StopProfilingMessage {
    let name: String
    let operationKey: String?
    let failureReason: String?
    let attributes: [AttributeKey: AttributeValue]

    public init(
        name: String,
        operationKey: String?,
        failureReason: String?,
        attributes: [AttributeKey: AttributeValue]
    ) {
        self.name = name
        self.operationKey = operationKey
        self.failureReason = failureReason
        self.attributes = attributes
    }
}
