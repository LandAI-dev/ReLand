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
