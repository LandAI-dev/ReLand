import Foundation
import XCTest
@testable import ReLandCore
@testable import ReLandHostCore

final class RemoteSessionIntegrationTests: XCTestCase, @unchecked Sendable {
    func testPairingIssuesDeviceCredentialAndConnects() throws {
        let pairingCredential = try PSKCredential.generate(
            name: "Pairing",
            isPairingCredential: true
        )
        let deviceCredential = try PSKCredential.generate(name: "Test Phone")
        let port: UInt16 = 45_459
        let server = RemoteHostServer(
            frameSource: SyntheticJPEGFrameSource(
                width: 320,
                height: 180,
                fps: 2
            ),
            inputSink: RecordingInputSink()
        )
        let paired = expectation(description: "Pairing accepted")
        let connected = expectation(description: "Device connected")
        let userActivity = expectation(
            description: "Remote user activity"
        )
        userActivity.expectedFulfillmentCount = 2
        let sessions = SessionBag()

        server.onUserActivity = {
            userActivity.fulfill()
        }
        server.onPairingAccepted = { credential in
            XCTAssertEqual(credential, deviceCredential)
        }
        server.onStateChange = { state in
            guard case .ready = state, sessions.isEmpty else {
                return
            }
            do {
                let pairingSession = try RemoteClientSession(
                    address: "127.0.0.1",
                    port: port,
                    credential: pairingCredential,
                    mode: .pair(
                        newDeviceCredential: deviceCredential
                    )
                )
                pairingSession.onPaired = { accepted, credential in
                    XCTAssertEqual(accepted.hostID, "integration-host")
                    XCTAssertEqual(credential, deviceCredential)
                    paired.fulfill()
                    do {
                        let session = try RemoteClientSession(
                            address: "127.0.0.1",
                            port: port,
                            credential: deviceCredential
                        )
                        session.onSessionReady = { ready in
                            XCTAssertEqual(
                                ready.protocolVersion,
                                ReLandConstants.protocolVersion
                            )
                            XCTAssertEqual(
                                ready.capabilities,
                                [
                                    .screen,
                                    .input,
                                    .captureTargets,
                                    .hostStatus,
                                ]
                            )
                        }
                        session.onStateChange = { state in
                            if state == .connected {
                                connected.fulfill()
                                session.send(
                                    input: .pointerDelta(
                                        x: 1,
                                        y: 1
                                    )
                                )
                            }
                        }
                        sessions.append(session)
                        session.connect()
                    } catch {
                        XCTFail(error.localizedDescription)
                    }
                }
                sessions.append(pairingSession)
                pairingSession.connect()
            } catch {
                XCTFail(error.localizedDescription)
            }
        }

        server.start(
            configuration: RemoteHostConfiguration(
                hostID: "integration-host",
                hostName: "Integration Host",
                port: port,
                credentials: [pairingCredential]
            )
        )

        wait(
            for: [paired, connected, userActivity],
            timeout: 10
        )
        for session in sessions.all {
            session.disconnect()
        }
        server.stop()
    }

    func testConcurrentPairingCredentialsBothComplete() throws {
        let firstPairing = try PSKCredential.generate(
            name: "First pairing",
            isPairingCredential: true
        )
        let secondPairing = try PSKCredential.generate(
            name: "Second pairing",
            isPairingCredential: true
        )
        let firstDevice = try PSKCredential.generate(name: "First phone")
        let secondDevice = try PSKCredential.generate(name: "Second phone")
        let port: UInt16 = 45_460
        let server = RemoteHostServer(
            frameSource: SyntheticJPEGFrameSource(
                width: 320,
                height: 180,
                fps: 2
            ),
            inputSink: RecordingInputSink()
        )
        let firstPaired = expectation(description: "First device paired")
        let secondPaired = expectation(description: "Second device paired")
        let sessions = SessionBag()
        let didStart = LockedFlag()

        server.onStateChange = { state in
            guard case .ready = state, didStart.claim() else {
                return
            }
            do {
                let firstSession = try RemoteClientSession(
                    address: "127.0.0.1",
                    port: port,
                    credential: firstPairing,
                    mode: .pair(newDeviceCredential: firstDevice)
                )
                firstSession.onPaired = { _, credential in
                    XCTAssertEqual(credential, firstDevice)
                    firstPaired.fulfill()
                }

                let secondSession = try RemoteClientSession(
                    address: "127.0.0.1",
                    port: port,
                    credential: secondPairing,
                    mode: .pair(newDeviceCredential: secondDevice)
                )
                secondSession.onPaired = { _, credential in
                    XCTAssertEqual(credential, secondDevice)
                    secondPaired.fulfill()
                }

                sessions.append(firstSession)
                sessions.append(secondSession)
                firstSession.connect()
                secondSession.connect()
            } catch {
                XCTFail(error.localizedDescription)
            }
        }

        server.start(
            configuration: RemoteHostConfiguration(
                hostID: "concurrent-pairing-host",
                hostName: "Concurrent Pairing Host",
                port: port,
                credentials: [firstPairing, secondPairing]
            )
        )

        wait(for: [firstPaired, secondPaired], timeout: 10)
        for session in sessions.all {
            session.disconnect()
        }
        server.stop()
    }

    func testRejectsSecondActiveController() throws {
        let firstCredential = try PSKCredential.generate(
            name: "First phone"
        )
        let secondCredential = try PSKCredential.generate(
            name: "Second phone"
        )
        let port: UInt16 = 45_461
        let server = RemoteHostServer(
            frameSource: SyntheticJPEGFrameSource(
                width: 320,
                height: 180,
                fps: 2
            ),
            inputSink: RecordingInputSink()
        )
        let firstConnected = expectation(
            description: "First controller connected"
        )
        let secondRejected = expectation(
            description: "Second controller rejected"
        )
        let sessions = SessionBag()
        let didStart = LockedFlag()
        let didConnectSecond = LockedFlag()

        server.onStateChange = { state in
            guard case .ready = state, didStart.claim() else {
                return
            }
            do {
                let first = try RemoteClientSession(
                    address: "127.0.0.1",
                    port: port,
                    credential: firstCredential
                )
                first.onStateChange = { state in
                    guard
                        state == .connected,
                        didConnectSecond.claim()
                    else {
                        return
                    }
                    firstConnected.fulfill()
                    do {
                        let second = try RemoteClientSession(
                            address: "127.0.0.1",
                            port: port,
                            credential: secondCredential
                        )
                        second.onRemoteError = { error in
                            XCTAssertEqual(error.code, .hostBusy)
                            secondRejected.fulfill()
                        }
                        sessions.append(second)
                        second.connect()
                    } catch {
                        XCTFail(error.localizedDescription)
                    }
                }
                sessions.append(first)
                first.connect()
            } catch {
                XCTFail(error.localizedDescription)
            }
        }

        server.start(
            configuration: RemoteHostConfiguration(
                hostID: "single-controller-host",
                hostName: "Single Controller Host",
                port: port,
                credentials: [
                    firstCredential,
                    secondCredential,
                ]
            )
        )

        wait(for: [firstConnected, secondRejected], timeout: 10)
        for session in sessions.all {
            session.disconnect()
        }
        server.stop()
    }

    func testSameCredentialReconnectReplacesStaleController() throws {
        let credential = try PSKCredential.generate(name: "Phone")
        let port: UInt16 = 45_464
        let server = RemoteHostServer(
            frameSource: SyntheticJPEGFrameSource(
                width: 320,
                height: 180,
                fps: 2
            ),
            inputSink: RecordingInputSink()
        )
        let firstRevoked = expectation(
            description: "Stale controller revoked"
        )
        let reconnectConnected = expectation(
            description: "Same device reconnected"
        )
        let sessions = SessionBag()
        let didStart = LockedFlag()
        let didReconnect = LockedFlag()

        server.onStateChange = { state in
            guard case .ready = state, didStart.claim() else {
                return
            }
            do {
                let first = try RemoteClientSession(
                    address: "127.0.0.1",
                    port: port,
                    credential: credential
                )
                first.onRemoteError = { error in
                    XCTAssertEqual(error.code, .sessionTakenOver)
                    firstRevoked.fulfill()
                }
                first.onStateChange = { state in
                    guard
                        state == .connected,
                        didReconnect.claim()
                    else {
                        return
                    }
                    do {
                        let reconnect = try RemoteClientSession(
                            address: "127.0.0.1",
                            port: port,
                            credential: credential
                        )
                        reconnect.onStateChange = { state in
                            if state == .connected {
                                reconnectConnected.fulfill()
                            }
                        }
                        sessions.append(reconnect)
                        reconnect.connect()
                    } catch {
                        XCTFail(error.localizedDescription)
                    }
                }
                sessions.append(first)
                first.connect()
            } catch {
                XCTFail(error.localizedDescription)
            }
        }

        server.start(
            configuration: RemoteHostConfiguration(
                hostID: "resume-host",
                hostName: "Resume Host",
                port: port,
                credentials: [credential]
            )
        )

        wait(
            for: [firstRevoked, reconnectConnected],
            timeout: 10
        )
        for session in sessions.all {
            session.disconnect()
        }
        server.stop()
    }

    func testExpiresInactiveControllerLease() throws {
        let credential = try PSKCredential.generate(name: "Phone")
        let port: UInt16 = 45_462
        let server = RemoteHostServer(
            frameSource: SyntheticJPEGFrameSource(
                width: 320,
                height: 180,
                fps: 2
            ),
            inputSink: RecordingInputSink(),
            controllerLeaseDuration: 0.15,
            livenessCheckInterval: 0.05
        )
        let expired = expectation(
            description: "Inactive controller lease expired"
        )
        let sessions = SessionBag()
        let didStart = LockedFlag()

        server.onStateChange = { state in
            guard case .ready = state, didStart.claim() else {
                return
            }
            do {
                let session = try RemoteClientSession(
                    address: "127.0.0.1",
                    port: port,
                    credential: credential
                )
                session.onRemoteError = { error in
                    XCTAssertEqual(error.code, .sessionExpired)
                    expired.fulfill()
                }
                sessions.append(session)
                session.connect()
            } catch {
                XCTFail(error.localizedDescription)
            }
        }

        server.start(
            configuration: RemoteHostConfiguration(
                hostID: "lease-host",
                hostName: "Lease Host",
                port: port,
                credentials: [credential]
            )
        )

        wait(for: [expired], timeout: 2)
        for session in sessions.all {
            session.disconnect()
        }
        server.stop()
    }

    func testAuthenticatedTakeoverReplacesController() throws {
        let credential = try PSKCredential.generate(name: "Phone")
        let port: UInt16 = 45_463
        let server = RemoteHostServer(
            frameSource: SyntheticJPEGFrameSource(
                width: 320,
                height: 180,
                fps: 2
            ),
            inputSink: RecordingInputSink()
        )
        let firstRevoked = expectation(
            description: "First controller revoked"
        )
        let takeoverConnected = expectation(
            description: "Takeover controller connected"
        )
        let sessions = SessionBag()
        let didStart = LockedFlag()
        let didConnectTakeover = LockedFlag()

        server.onStateChange = { state in
            guard case .ready = state, didStart.claim() else {
                return
            }
            do {
                let first = try RemoteClientSession(
                    address: "127.0.0.1",
                    port: port,
                    credential: credential
                )
                first.onRemoteError = { error in
                    XCTAssertEqual(error.code, .sessionTakenOver)
                    firstRevoked.fulfill()
                }
                first.onStateChange = { state in
                    guard
                        state == .connected,
                        didConnectTakeover.claim()
                    else {
                        return
                    }
                    do {
                        let takeover = try RemoteClientSession(
                            address: "127.0.0.1",
                            port: port,
                            credential: credential,
                            requestsControllerTakeover: true
                        )
                        takeover.onStateChange = { state in
                            if state == .connected {
                                takeoverConnected.fulfill()
                            }
                        }
                        sessions.append(takeover)
                        takeover.connect()
                    } catch {
                        XCTFail(error.localizedDescription)
                    }
                }
                sessions.append(first)
                first.connect()
            } catch {
                XCTFail(error.localizedDescription)
            }
        }

        server.start(
            configuration: RemoteHostConfiguration(
                hostID: "takeover-host",
                hostName: "Takeover Host",
                port: port,
                credentials: [credential]
            )
        )

        wait(
            for: [firstRevoked, takeoverConnected],
            timeout: 10
        )
        for session in sessions.all {
            session.disconnect()
        }
        server.stop()
    }

    func testRecoverableTerminalErrorKeepsConnectionActive() throws {
        let credential = try PSKCredential.generate(name: "Phone")
        let port: UInt16 = 45_465
        let server = RemoteHostServer(
            frameSource: SyntheticJPEGFrameSource(
                width: 320,
                height: 180,
                fps: 2
            ),
            inputSink: RecordingInputSink(),
            terminalService: FailingTerminalService()
        )
        let connected = expectation(description: "Controller connected")
        let terminalError = expectation(
            description: "Terminal error received"
        )
        let connectionFailed = expectation(
            description: "Connection did not fail"
        )
        connectionFailed.isInverted = true
        let sessions = SessionBag()
        let didStart = LockedFlag()
        let didCreateTerminal = LockedFlag()

        server.onStateChange = { state in
            guard case .ready = state, didStart.claim() else {
                return
            }
            do {
                let session = try RemoteClientSession(
                    address: "127.0.0.1",
                    port: port,
                    credential: credential
                )
                session.onRemoteError = { error in
                    XCTAssertEqual(error.code, .internalError)
                    XCTAssertTrue(error.isRecoverable)
                    terminalError.fulfill()
                }
                session.onStateChange = { state in
                    switch state {
                    case .connected:
                        guard didCreateTerminal.claim() else {
                            return
                        }
                        connected.fulfill()
                        session.createTerminalSession(
                            preferredName: "failing-terminal"
                        )
                    case .failed:
                        connectionFailed.fulfill()
                    default:
                        break
                    }
                }
                sessions.append(session)
                session.connect()
            } catch {
                XCTFail(error.localizedDescription)
            }
        }

        server.start(
            configuration: RemoteHostConfiguration(
                hostID: "recoverable-error-host",
                hostName: "Recoverable Error Host",
                port: port,
                credentials: [credential]
            )
        )

        wait(
            for: [connected, terminalError, connectionFailed],
            timeout: 2
        )
        for session in sessions.all {
            session.disconnect()
        }
        server.stop()
    }

    func testRecoverableCaptureErrorsKeepConnectionActive() throws {
        let credential = try PSKCredential.generate(name: "Phone")
        let port: UInt16 = 45_466
        let server = RemoteHostServer(
            frameSource: FailingCaptureSource(),
            inputSink: RecordingInputSink()
        )
        let connected = expectation(description: "Controller connected")
        let captureErrors = expectation(
            description: "Capture errors received"
        )
        captureErrors.expectedFulfillmentCount = 2
        let connectionFailed = expectation(
            description: "Connection did not fail"
        )
        connectionFailed.isInverted = true
        let sessions = SessionBag()
        let didStart = LockedFlag()
        let didRequestTargets = LockedFlag()
        let errorCount = LockedCounter()

        server.onStateChange = { state in
            guard case .ready = state, didStart.claim() else {
                return
            }
            do {
                let session = try RemoteClientSession(
                    address: "127.0.0.1",
                    port: port,
                    credential: credential
                )
                session.onRemoteError = { error in
                    XCTAssertEqual(error.code, .internalError)
                    XCTAssertTrue(error.isRecoverable)
                    if errorCount.increment() == 1 {
                        session.selectCaptureTarget(id: "missing-window")
                    }
                    captureErrors.fulfill()
                }
                session.onStateChange = { state in
                    switch state {
                    case .connected:
                        guard didRequestTargets.claim() else {
                            return
                        }
                        connected.fulfill()
                        session.requestCaptureTargets()
                    case .failed:
                        connectionFailed.fulfill()
                    default:
                        break
                    }
                }
                sessions.append(session)
                session.connect()
            } catch {
                XCTFail(error.localizedDescription)
            }
        }

        server.start(
            configuration: RemoteHostConfiguration(
                hostID: "recoverable-capture-error-host",
                hostName: "Recoverable Capture Error Host",
                port: port,
                credentials: [credential]
            )
        )

        wait(
            for: [connected, captureErrors, connectionFailed],
            timeout: 2
        )
        for session in sessions.all {
            session.disconnect()
        }
        server.stop()
    }

    func testRecoverableFrameErrorKeepsConnectionActive() throws {
        let credential = try PSKCredential.generate(name: "Phone")
        let port: UInt16 = 45_467
        let server = RemoteHostServer(
            frameSource: FailingFrameSource(),
            inputSink: RecordingInputSink()
        )
        let connected = expectation(description: "Controller connected")
        let frameError = expectation(description: "Frame error received")
        let connectionFailed = expectation(
            description: "Connection did not fail"
        )
        connectionFailed.isInverted = true
        let sessions = SessionBag()
        let didStart = LockedFlag()

        server.onStateChange = { state in
            guard case .ready = state, didStart.claim() else {
                return
            }
            do {
                let session = try RemoteClientSession(
                    address: "127.0.0.1",
                    port: port,
                    credential: credential
                )
                session.onRemoteError = { error in
                    XCTAssertEqual(error.code, .internalError)
                    XCTAssertTrue(error.isRecoverable)
                    frameError.fulfill()
                }
                session.onStateChange = { state in
                    switch state {
                    case .connected:
                        connected.fulfill()
                    case .failed:
                        connectionFailed.fulfill()
                    default:
                        break
                    }
                }
                sessions.append(session)
                session.connect()
            } catch {
                XCTFail(error.localizedDescription)
            }
        }

        server.start(
            configuration: RemoteHostConfiguration(
                hostID: "recoverable-frame-error-host",
                hostName: "Recoverable Frame Error Host",
                port: port,
                credentials: [credential]
            )
        )

        wait(
            for: [connected, frameError, connectionFailed],
            timeout: 2
        )
        for session in sessions.all {
            session.disconnect()
        }
        server.stop()
    }
}

private final class SessionBag: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [RemoteClientSession] = []

    var isEmpty: Bool {
        lock.lock()
        defer { lock.unlock() }
        return storage.isEmpty
    }

    var all: [RemoteClientSession] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(_ session: RemoteClientSession) {
        lock.lock()
        storage.append(session)
        lock.unlock()
    }
}

private final class LockedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !value else {
            return false
        }
        value = true
        return true
    }
}

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func increment() -> Int {
        lock.lock()
        defer { lock.unlock() }
        value += 1
        return value
    }
}

private struct FailingTerminalService: RemoteTerminalService {
    func listSessions() throws -> [TerminalSessionInfo] {
        []
    }

    func createSession(
        preferredName: String?,
        launchProfile: TerminalLaunchProfile,
        launchArguments: [String],
        workingDirectory: URL?
    ) throws -> TerminalSessionInfo {
        throw FailingTerminalError.creationFailed
    }

    func attach(
        attachmentID: UUID,
        sessionID: String,
        columns: Int,
        rows: Int,
        outputHandler: @escaping @Sendable (Data) -> Void,
        terminationHandler: @escaping @Sendable () -> Void
    ) throws -> any RemoteTerminalAttachment {
        throw FailingTerminalError.creationFailed
    }

    func openOnMac(sessionID: String) throws {
        throw FailingTerminalError.creationFailed
    }

    func killSession(sessionID: String) throws {
        throw FailingTerminalError.creationFailed
    }

    func listArtifacts(
        sessionID: String
    ) throws -> [TerminalArtifactInfo] {
        throw FailingTerminalError.creationFailed
    }

    func readArtifact(
        request: TerminalArtifactReadRequest
    ) throws -> TerminalArtifactChunk {
        throw FailingTerminalError.creationFailed
    }
}

private enum FailingTerminalError: LocalizedError {
    case creationFailed

    var errorDescription: String? {
        "The test terminal could not be created"
    }
}

private final class FailingCaptureSource:
    RemoteCaptureTargetSource,
    @unchecked Sendable
{
    private let source = SyntheticJPEGFrameSource(
        width: 320,
        height: 180,
        fps: 2
    )

    var displayInformation: DisplayInformation {
        source.displayInformation
    }

    func start(
        frameHandler: @escaping @Sendable (Data) -> Void,
        errorHandler: @escaping @Sendable (Error) -> Void
    ) {
        source.start(
            frameHandler: frameHandler,
            errorHandler: errorHandler
        )
    }

    func stop() {
        source.stop()
    }

    func listCaptureTargets(
        completion: @escaping @Sendable (
            Result<
                RemoteCaptureTargetListResponse,
                RemoteCaptureTargetSourceError
            >
        ) -> Void
    ) {
        completion(.failure(.message("Capture target list failed")))
    }

    func selectCaptureTarget(
        id: String,
        completion: @escaping @Sendable (
            Result<
                RemoteCaptureTargetSelected,
                RemoteCaptureTargetSourceError
            >
        ) -> Void
    ) {
        completion(.failure(.message("Capture target selection failed")))
    }

    func currentInputBounds() -> CGRect? {
        nil
    }

    func focusSelectedTarget() {}
}

private struct FailingFrameSource: RemoteFrameSource {
    let displayInformation = DisplayInformation(
        width: 320,
        height: 180,
        framesPerSecond: 2
    )

    func start(
        frameHandler: @escaping @Sendable (Data) -> Void,
        errorHandler: @escaping @Sendable (Error) -> Void
    ) {
        errorHandler(FailingFrameError.captureFailed)
    }

    func stop() {}
}

private enum FailingFrameError: LocalizedError {
    case captureFailed

    var errorDescription: String? {
        "The test frame source failed"
    }
}
