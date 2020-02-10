import Foundation

/// Based on `OutputListener` from https://github.com/mas-cli/mas project (MIT).
class ConsoleOutputInterceptor {
    /// Max length of output log to notify. Content exceeding this length will be truncated at beginning.
    private let maxContentsLength = 2_048

    private let inputPipe = Pipe()
    private let outputPipe = Pipe()

    private var stdoutFileDescriptor: Int32 { FileHandle.standardOutput.fileDescriptor }
    private var stderrFileDescriptor: Int32 { FileHandle.standardError.fileDescriptor }

    private var contents: String = "" {
        didSet {
            DispatchQueue.main.async { self.notifyContentsChange?(self.contents) }
        }
    }

    var notifyContentsChange: ((String) -> Void)?

    init() {
        inputPipe.fileHandleForReading.readabilityHandler = { [weak self] fileHandle in
            guard let self = self else { return }

            let data = fileHandle.availableData
            if let string = String(data: data, encoding: String.Encoding.utf8) {
                self.process(newLog: string)
            }

            // Write input back to stdout
            self.outputPipe.fileHandleForWriting.write(data)
        }

        var dup2Status: Int32

        dup2Status = dup2(stdoutFileDescriptor, outputPipe.fileHandleForWriting.fileDescriptor)
        assert(dup2Status == outputPipe.fileHandleForWriting.fileDescriptor)

        dup2Status = dup2(inputPipe.fileHandleForWriting.fileDescriptor, stdoutFileDescriptor)
        assert(dup2Status == stdoutFileDescriptor)
    }

    deinit {
        freopen("/dev/stdout", "a", stdout)

        [inputPipe.fileHandleForReading, outputPipe.fileHandleForWriting].forEach { file in
            file.closeFile()
        }
    }

    private func process(newLog: String) {
        let newContents = contents + newLog
        contents = String(newContents.suffix(maxContentsLength))
    }
}
