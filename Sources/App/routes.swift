import Vapor

enum MutexConstants: String {
    case filePath = "/mutex_logs/"
    case locked = "locked"
    case success = "success"
    case error = "error"
    case uuid = "uuid"
}

typealias MutexData = [String: Any]

enum MutexError: String, Error {
    case badRequestBodyData = "Could not get data from request body"
    case badRequestJSON = "Culd not parse the data from the request body"
    case badRequestUUID = "Could not get UUID from request body"
}

class MutexManager {
    var fileManager: FileManager
    var logger: Logger
    
    init(fileManager: FileManager, logger: Logger) {
        self.fileManager = fileManager
        self.logger = logger
    }
    
    func getDataForFile(_ file: URL) -> MutexData? {
        do {
            let data = try Data(contentsOf: file)
            return try JSONSerialization.jsonObject(with: data) as? MutexData
        } catch {
            logger.error("Unable to get data for file \(file.path) with error: \(error)")
            return nil
        }
    }
    
    func logDirectoryPath() -> URL {
        // For XCTests
        if fileManager.currentDirectoryPath.isEmpty {
            var filePath = URL(fileURLWithPath: #file).pathComponents
            filePath.removeFirst(1) // "/"
            filePath.removeLast(3) // "Sources/App/routes.swift"
            return URL(fileURLWithPath: "/\(String(filePath.joined(by: "/")))\(MutexConstants.filePath.rawValue)")
        }
        
        return URL(fileURLWithPath: fileManager.currentDirectoryPath + MutexConstants.filePath.rawValue)
    }
    
    func filePathForUUID(_ uuid: String) -> URL {
        URL(fileURLWithPath: logDirectoryPath().appendingPathComponent(uuid).path)
    }
    
    func findFileForUUID(_ uuid: String) -> MutexData? {
        let filePath = filePathForUUID(uuid)
        logger.info("Querying \(filePath.path) for mutex...")
        
        return fileManager.fileExists(atPath: filePath.path) ? getDataForFile(filePath) : nil
    }
    
    // Returns (found?, found mutex or original data)
    func parseData(_ body: Request.Body) throws -> (Bool, MutexData) {
        do {
            guard let data = body.data else {
                throw MutexError.badRequestBodyData
            }
            
            guard let mutex = try JSONSerialization.jsonObject(with: data) as? MutexData else {
                throw MutexError.badRequestJSON
            }
            
            logger.info("Recieved data: \(mutex)")
            
            guard let uuid = mutex[MutexConstants.uuid.rawValue] as? String else {
                throw MutexError.badRequestUUID
            }
            
            if var foundFile = findFileForUUID(uuid) {
                var copyMutex = mutex
                copyMutex.removeValue(forKey: MutexConstants.locked.rawValue)
                copyMutex.removeValue(forKey: MutexConstants.success.rawValue)
                
                foundFile.merge(copyMutex) { (_, new) in new }
                
                return (true, foundFile)
            } else {
                return (false, mutex)
            }
        } catch {
            logger.error("Error finding status: \(error)")
            throw Abort(.badRequest)
        }
    }
    
    func encodeData(_ mutex: MutexData) throws -> String {
        let jsonData = try JSONSerialization.data(withJSONObject: mutex)
        return String(data: jsonData, encoding: .ascii)!
    }
    
    func writeData(_ mutex: MutexData) throws {
        guard let uuid = mutex[MutexConstants.uuid.rawValue] as? String else {
            throw MutexError.badRequestUUID
        }
        
        let filePath = filePathForUUID(uuid)
        
        if !fileManager.fileExists(atPath: logDirectoryPath().path) {
            try fileManager.createDirectory(atPath: logDirectoryPath().path, withIntermediateDirectories: false)
        }
        
        if !fileManager.fileExists(atPath: filePath.path) {
            fileManager.createFile(atPath: filePath.path, contents: nil, attributes: nil)
        }
        
        var copyMutex = mutex
        copyMutex.removeValue(forKey: MutexConstants.success.rawValue)
        
        let jsonData = try JSONSerialization.data(withJSONObject: copyMutex)
        try jsonData.write(to: filePath)
    }
    
    func deleteData(_ mutex: MutexData) -> Bool {
        guard let uuid = mutex[MutexConstants.uuid.rawValue] as? String else {
            return false
        }
        
        do {
            try fileManager.removeItem(atPath: filePathForUUID(uuid).path)
            return true
        } catch {
            return false
        }
    }
    
    func errorForMutex(_ mutex: MutexData) -> [String: String] {
        [MutexConstants.error.rawValue: "Could not find mutex for UUID: \(mutex[MutexConstants.uuid.rawValue]!)"]
    }
}

enum MutexRoutes: String {
    case health = "health"
    case new = "new"
    case status = "status"
    case lock = "lock"
    case unlock = "unlock"
    case delete = "delete"
    
    var path: PathComponent {
        return PathComponent(stringLiteral: self.rawValue)
    }
}
    

func routes(_ app: Application) throws {
    let manager = MutexManager(fileManager: FileManager.default, logger: app.logger)
    
    app.get(MutexRoutes.health.path) { req async -> String in
        "OK"
    }
    
    app.get(MutexRoutes.new.path) { req async -> [String: String] in
        return [MutexConstants.uuid.rawValue: UUID().uuidString]
    }
    
    app.post(MutexRoutes.status.path) { req async throws -> String in
        let (result, mutex) = try manager.parseData(req.body)
        
        return try manager.encodeData(result ? mutex : manager.errorForMutex(mutex))
    }
    
    app.post(MutexRoutes.lock.path) { req async throws -> String in
        var (result, mutex) = try manager.parseData(req.body)
    
        if !result {
            app.logger.info("Could not find, creating")
            mutex[MutexConstants.success.rawValue] = true
        } else {
            mutex[MutexConstants.success.rawValue] = mutex[MutexConstants.locked.rawValue] as? Bool == false
        }
        
        mutex[MutexConstants.locked.rawValue] = true
        
        try manager.writeData(mutex)
 
        return try manager.encodeData(mutex)
    }
    
    app.post(MutexRoutes.unlock.path) { req async throws -> String in
        var (result, mutex) = try manager.parseData(req.body)
    
        if !result {
            app.logger.info("Could not find mutex for UUID, creating...")
            mutex[MutexConstants.success.rawValue] = false
        } else {
            mutex[MutexConstants.success.rawValue] = mutex[MutexConstants.locked.rawValue] as? Bool == true
        }
        
        mutex[MutexConstants.locked.rawValue] = false
        
        try manager.writeData(mutex)
 
        return try manager.encodeData(mutex)
    }
    
    app.post(MutexRoutes.delete.path) { req async throws -> String in
        var (result, mutex) = try manager.parseData(req.body)
        
        if !result {
            return try manager.encodeData(manager.errorForMutex(mutex))
        }
        
        mutex[MutexConstants.locked.rawValue] = false
        mutex[MutexConstants.success.rawValue] = manager.deleteData(mutex)
        
        return try manager.encodeData(mutex)
    }
}
