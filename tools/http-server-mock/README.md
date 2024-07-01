# HTTPServerMock

> Swift interface to interact with Python server. Handy toolset to run intergation tests on physical iOS device and host the HTTP server process on separate machine in the same local network. 

This package provides Swift interface for interacting with HTTP mock server written in Python. This server records all received requests and exposes `GET /inspect` endpoint to retrieve them back.

## Usage

To start Python server from command line:
```
$ ./python/start_mock_server_py
```

The server will listen on private IP in local network (if available) or localhost (otherwise). To discover the server IP, `server_address.py` can be used:
```
$ ./python/server_address.py
127.0.0.1:8000
```

To verify the server state from Swift code:
```
import HTTPServerMock

let serverProcessRunner = ServerProcessRunner(serverURL: "127.0.0.1:8000")
guard let serverProcess = serverProcessRunner.waitUntilServerIsReachable() else {
    fatalError("Cannot reach the server.")
}

let server = ServerMock(serverProcess: serverProcess)
let session = server.obtainUniqueRecordingSession()

# now, from client's code send some request(s) to `session.recordingURL`
# e.g. `POST http://127.0.0.1:8000/resource/1` with "hello world" HTTP body

let recordedRequests = try session.getRecordedRequests()
XCTAssertTrue(recordedRequests[0].path.hasSuffix("/resource/1"))
XCTAssertEqual(recordedRequests[0].httpBody, "hello world".data(using: .utf8)!)
```

By obtaining separate `ServerSession` with `server.obtainUniqueRecordingSession()` for each test, there is no need to restart the server each time to reset its state.

## License

[Apache License, v2.0](../../LICENSE)
