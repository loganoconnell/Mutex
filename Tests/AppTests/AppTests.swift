@testable import App
import XCTVapor

final class AppTests: XCTestCase {
    var app: Application? = nil
    var testByteData: ByteBuffer? = nil
    
    override func setUp() async throws {
        if app == nil {
            app = Application(.testing)
            try await configure(app!)
        }
        
        if testByteData == nil {
            let mutex = ["uuid": UUID().uuidString]
            let jsonData = try JSONSerialization.data(withJSONObject: mutex)
            let byteData = ByteBuffer(data: jsonData)
            testByteData = byteData
        }
    }
    
    override func tearDown() {
        app!.shutdown()
    }
    
    func parseResponse(_ body: ByteBuffer?) -> MutexData {
        guard let data = body else {
            return MutexData()
        }
        
        guard let mutex = try? JSONSerialization.jsonObject(with: data) as? MutexData else {
            return MutexData()
        }
                
        return mutex
    }
    
    func testHealth() async throws {
        try app!.test(.GET, MutexRoutes.health.rawValue, afterResponse: { res in
            XCTAssertEqual(res.status, .ok)
            XCTAssertEqual(res.body.string, "OK")
        })
    }
    
    func testNew() async throws {
        try app!.test(.GET, MutexRoutes.new.rawValue, afterResponse: { res in
            XCTAssertEqual(res.status, .ok)
            XCTAssertNotNil(parseResponse(res.body)[MutexConstants.uuid.rawValue])
        })
    }
    
    func testStatusError() async throws {
        try app!.test(.POST, MutexRoutes.status.rawValue, body: testByteData!, afterResponse: { res in
            XCTAssertEqual(res.status, .ok)
            XCTAssertNotNil(parseResponse(res.body)[MutexConstants.error.rawValue])
        })
    }
    
    func testStatus() async throws {
        try app!.test(.POST, MutexRoutes.lock.rawValue, body: testByteData!, afterResponse: { res in
            XCTAssertEqual(res.status, .ok)
            XCTAssertEqual(parseResponse(res.body)[MutexConstants.locked.rawValue] as! Int, 1)
        })
        
        try app!.test(.POST, MutexRoutes.status.rawValue, body: testByteData!, afterResponse: { res in
            XCTAssertEqual(res.status, .ok)
            XCTAssertNotNil(parseResponse(res.body)[MutexConstants.uuid.rawValue])
        })
    }
    
    func testLock() async throws {
        try app!.test(.POST, MutexRoutes.lock.rawValue, body: testByteData!, afterResponse: { res in
            XCTAssertEqual(res.status, .ok)
            XCTAssertEqual(parseResponse(res.body)[MutexConstants.locked.rawValue] as! Int, 1)
        })
        
        try app!.test(.POST, MutexRoutes.lock.rawValue, body: testByteData!, afterResponse: { res in
            XCTAssertEqual(res.status, .ok)
            XCTAssertEqual(parseResponse(res.body)[MutexConstants.locked.rawValue] as! Int, 1)
            XCTAssertEqual(parseResponse(res.body)[MutexConstants.success.rawValue] as! Int, 0)
        })
    }
    
    func testUnlock() async throws {
        try app!.test(.POST, MutexRoutes.lock.rawValue, body: testByteData!, afterResponse: { res in
            XCTAssertEqual(res.status, .ok)
            XCTAssertEqual(parseResponse(res.body)[MutexConstants.locked.rawValue] as! Int, 1)
        })
        
        try app!.test(.POST, MutexRoutes.unlock.rawValue, body: testByteData!, afterResponse: { res in
            XCTAssertEqual(res.status, .ok)
            XCTAssertEqual(parseResponse(res.body)[MutexConstants.locked.rawValue] as! Int, 0)
            XCTAssertEqual(parseResponse(res.body)[MutexConstants.success.rawValue] as! Int, 1)
        })
        
        try app!.test(.POST, MutexRoutes.unlock.rawValue, body: testByteData!, afterResponse: { res in
            XCTAssertEqual(res.status, .ok)
            XCTAssertEqual(parseResponse(res.body)[MutexConstants.locked.rawValue] as! Int, 0)
            XCTAssertEqual(parseResponse(res.body)[MutexConstants.success.rawValue] as! Int, 0)
        })
    }
    
    func testDelete() async throws {
        try app!.test(.POST, MutexRoutes.lock.rawValue, body: testByteData!, afterResponse: { res in
            XCTAssertEqual(res.status, .ok)
            XCTAssertEqual(parseResponse(res.body)[MutexConstants.locked.rawValue] as! Int, 1)
        })
        
        try app!.test(.POST, MutexRoutes.delete.rawValue, body: testByteData!, afterResponse: { res in
            XCTAssertEqual(res.status, .ok)
            XCTAssertEqual(parseResponse(res.body)[MutexConstants.success.rawValue] as! Int, 1)
        })
        
        try app!.test(.POST, MutexRoutes.status.rawValue, body: testByteData!, afterResponse: { res in
            XCTAssertEqual(res.status, .ok)
            XCTAssertNotNil(parseResponse(res.body)[MutexConstants.error.rawValue])
        })
    }
}
