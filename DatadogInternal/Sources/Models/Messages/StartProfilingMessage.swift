public struct StartProfilingMessage {
    let name: String
    let operationKey: String?
    let attributes: [AttributeKey: AttributeValue]
    
    public init(
        name: String,
        operationKey: String?,
        attributes: [AttributeKey: AttributeValue]
    ) {
        self.name = name
        self.operationKey = operationKey
        self.attributes = attributes
    }
}
