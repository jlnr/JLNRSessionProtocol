//
//  JLNRSessionProtocolTests.swift
//  JLNRSessionProtocolTests
//
//  Created by Julian Raschke on 05.10.18.
//  Copyright © 2018 Raschke & Ludwig GbR. All rights reserved.
//

import XCTest

let testPort = 9595

// A dummy web service with three endpoints (no parameters, all POST for simplicity):
// GET /login, which returns a valid session token.
// GET /ping, which returns "PONG" if the X-API-Token header contains a valid session token.
// GET /logout, which invalidates the token in the X-API-Token header.
class TestWebService {
    
    private let ws = GCDWebServer()
    
    private (set) var validTokens = Set<String>()
    private (set) var loginCount = 0
    private (set) var pingCount = 0
    private (set) var logoutCount = 0
    
    init() {
        ws.addHandler(forMethod: "POST", path: "/login", request: GCDWebServerRequest.self) { _ in
            self.loginCount += 1
            let newToken = "Token-\(self.loginCount)"
            self.validTokens.insert(newToken)
            return GCDWebServerDataResponse(text: newToken)
        }
        
        ws.addHandler(forMethod: "POST", path: "/ping", request: GCDWebServerRequest.self) { request in
            guard let token = request.headers["X-API-Token"] as? String,
                self.validTokens.contains(token)
            else {
                return GCDWebServerResponse(statusCode: 401)
            }
            
            self.pingCount += 1
            return GCDWebServerDataResponse(text: "PONG")
        }

        ws.addHandler(forMethod: "POST", path: "/logout", request: GCDWebServerRequest.self) { request in
            guard let token = request.headers["X-API-Token"] as? String,
                self.validTokens.contains(token)
            else {
                return GCDWebServerResponse(statusCode: 401)
            }
            
            self.validTokens.remove(token)
            self.logoutCount += 1
            return GCDWebServerResponse(statusCode: 200)
        }
        
        ws.start(withPort: 9595, bonjourName: "GCD Web Server")
    }
    
    deinit {
        ws.stop()
    }
    
}

// To use JLNRSessionProtocol, you need to create a class that conforms to JLNRSession.
// You would then typically register an instance of this class when the user logs in.
class TestSession: JLNRSession {
    
    // The most recent API token that we have received.
    private (set) var secret: String?

    private let loginRequest: URLRequest = {
        var request = URLRequest(url: URL(string: "http://localhost:\(testPort)/login")!)
        request.httpMethod = "POST"
        // Usually you would encode user credentials in request.httpBody here ...
        return request
    }()

    // This method can be used to skip automatic session management for requests that do not require
    // authorization, e.g. unprotected static assets.
    func shouldHandle(_ request: URLRequest) -> Bool {
        return true
    }
    
    // This method is called before each request, and if this session *knows* that its secret is
    // not yet valid, or has expired, it should return a login request.
    func loginRequest(before request: URLRequest) -> URLRequest? {
        // In this case, we don't know when our token expires; but we know that if we don't have
        // any token, we definitely need to send a login request.
        return secret == nil ? loginRequest : nil
    }
    
    // This method is called before the given response is passed on to the rest of the app.
    // If the response indicates a session timeout (e.g. statusCode 401), this method should return
    // a login request, in which case JLNRSessionProtocol will discard this response, perform a
    // login request, and then retry the request.
    func loginRequest(after response: HTTPURLResponse, data: Data) -> URLRequest? {
        return response.statusCode == 401 ? loginRequest : nil
    }
    
    // This is called before sending requests, and gives the session a chance to attach its current
    // secret (if any) to the request.
    func applySecret(to request: NSMutableURLRequest) {
        if let apiToken = secret {
            request.setValue(apiToken, forHTTPHeaderField: "X-API-Token")
        }
    }
    
    // This method is called after a login request was performed on behalf of this session.
    // Its job is to store the returned session secret (cookie, JSON data, ...) to make this a
    // valid session.
    // If nothing useful has been returned from the login request, this method must return false,
    // in which case the outer request/task will fail.
    func storeSecret(from response: HTTPURLResponse, data: Data) -> Bool {
        guard response.statusCode == 200, data.count > 0 else { return false }
        secret = String(data: data, encoding: .utf8)!
        return true
    }
    
}

class JLNRSessionProtocolTests: XCTestCase {

    func testSessionProtocol() {
        let webService = TestWebService()

        XCTAssertEqual([], webService.validTokens)
        XCTAssertEqual(0, webService.loginCount)
        XCTAssertEqual(0, webService.pingCount)
        XCTAssertEqual(0, webService.logoutCount)
        
        // Login must work without a token.
        AssertResponseStatus(200, path: "/login")
        // API call must not work without a token.
        AssertResponseStatus(401, path: "/ping")
        // Logout must not work without a token.
        AssertResponseStatus(401, path: "/logout")

        XCTAssertEqual(["Token-1"], webService.validTokens)
        XCTAssertEqual(1, webService.loginCount)
        XCTAssertEqual(0, webService.pingCount)
        XCTAssertEqual(0, webService.logoutCount)
        
        // ...now start using our session...
        let session = TestSession()
        JLNRSessionProtocol.register(session)
        defer { JLNRSessionProtocol.invalidateSession(session) }

        // API call must now work automatically - TestSession should handle the login.
        AssertResponseStatus(200, path: "/ping")
        XCTAssertEqual("Token-2", session.secret)
        XCTAssertEqual(["Token-1", "Token-2"], webService.validTokens)
        XCTAssertEqual(2, webService.loginCount)
        XCTAssertEqual(1, webService.pingCount)
        XCTAssertEqual(0, webService.logoutCount)

        // A second API call must not trigger another login.
        AssertResponseStatus(200, path: "/ping")
        XCTAssertEqual("Token-2", session.secret)
        XCTAssertEqual(["Token-1", "Token-2"], webService.validTokens)
        XCTAssertEqual(2, webService.loginCount)
        XCTAssertEqual(2, webService.pingCount)
        XCTAssertEqual(0, webService.logoutCount)

        // The logout should work thanks to the attached API token.
        AssertResponseStatus(200, path: "/logout")
        XCTAssertEqual(["Token-1"], webService.validTokens)
        XCTAssertEqual(2, webService.loginCount)
        XCTAssertEqual(2, webService.pingCount)
        XCTAssertEqual(1, webService.logoutCount)
        
        // This third API call must trigger a second login.
        AssertResponseStatus(200, path: "/ping")
        XCTAssertEqual("Token-3", session.secret)
        XCTAssertEqual(["Token-1", "Token-3"], webService.validTokens)
        XCTAssertEqual(3, webService.loginCount)
        XCTAssertEqual(3, webService.pingCount)
        XCTAssertEqual(1, webService.logoutCount)
    }

    private func AssertResponseStatus(_ expectedStatus: Int, path: String,
                                      file: StaticString = #file, line: UInt = #line) {
        let expectation = self.expectation(description: path)
        var request = URLRequest(url: URL(string: "http://localhost:\(9595)\(path)")!)
        request.httpMethod = "POST"
        var actualStatus = -1
        let task = URLSession.shared.dataTask(with: request) { _, response, _ in
            if let response = response as? HTTPURLResponse {
                actualStatus = response.statusCode
            }
            expectation.fulfill()
        }
        task.resume()
        wait(for: [expectation], timeout: 60)
        XCTAssertEqual(expectedStatus, actualStatus,
                       "\(path) returned \(actualStatus) instead of \(expectedStatus)",
                       file: file, line: line)
    }
    
}
