//
//  ConsultUtils.swift
//  Consultation
//
//  Created by Steve Hume on 2017-01-31.

import Foundation
import Base62
import Node
import HTTP

struct ConsultConstants {
    static let cookieComment = "consult-comment"
    static let cookieUser = "consult-user"
    }

func uniqueIDBase62String() -> String {
        return encode(integer: UInt64(uniqueID32())) //    32 bits to match INT(10) mysql id

}
func base62ToID(string: String) -> UInt {
    let intg = decode(string: string)
    let max = UInt64(UInt32.max)
    if intg < max {
        return UInt(intg)
    }
    return 0 //    32 bits to match INT(10) mysql id

}
func base62ToNode(string: String?) -> Node {
    if (string ?? "").isEmpty {
        return Node(UInt(0))
    }
    return Node(base62ToID(string:  string!)) //    32 bits to match INT(10) mysql id

}
func uniqueID32() -> UInt {
    return UInt(arc4random()) //    32 bits to match INT(10) mysql id

}
func languageDetect(_ request: Request) -> String {
    if let referer = request.headers[HeaderKey.referrer] {
        if referer.range(of: "-fra.html") != nil {
            return "fra"
        }
    }
    return "eng"
}
func addAdminUser () {

}
