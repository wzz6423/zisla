import Foundation

@objc(ZislaPowerHelperProtocol)
public protocol PowerHelperProtocol {
    func openSession(reply: @escaping (FileHandle?, NSError?) -> Void)
}
