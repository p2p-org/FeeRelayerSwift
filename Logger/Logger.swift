import Foundation

public enum FeeRelayerSwiftLoggerLogLevel: String {
    case info
    case error
    case warning
    case debug
}

public protocol FeeRelayerSwiftLogger {
    func log(event: String, data: String?, logLevel: FeeRelayerSwiftLoggerLogLevel)
}

public class Logger {
    
    private static var loggers: [FeeRelayerSwiftLogger] = []
    
    // MARK: -
    
    static let shared = Logger()
    
    private init() {}
    
    // MARK: -
    
    public static func setLoggers(_ loggers: [FeeRelayerSwiftLogger]) {
        self.loggers = loggers
    }
    
    public static func log(event: String, message: String?, logLevel: FeeRelayerSwiftLogger = .info) {
        loggers.forEach { $0.log(event: event, data: message, logLevel: logLevel) }
    }

}
