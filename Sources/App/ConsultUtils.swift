//
//  ConsultUtils.swift
//  Consultation
//
//  Created by Steve Hume on 2017-01-31.
//
//

import Foundation
import Random
import Base62
import Node
import HTTP

struct ConsultConstants {
    static let cookieComment = "consult-comment"
    static let cookieUser = "consult-user"
    }

func UniqueIDBase62String() -> String {
        return encode(integer: UInt64(UniqueID32())) //    32 bits to match INT(10) mysql id

}
func Base62ToID(string: String) -> UInt {
    let intg = decode(string: string)
    let max = UInt64(UInt32.max)
    if intg < max {
        return UInt(intg)
    }
    return 0 //    32 bits to match INT(10) mysql id

}
func Base62ToNode(string: String?) -> Node {
    if (string ?? "").isEmpty {
        return Node(UInt(0))
    }
    return Node(Base62ToID(string:  string!)) //    32 bits to match INT(10) mysql id

}
func UniqueID32() -> UInt {
    return UInt(URandom().uint32) //    32 bits to match INT(10) mysql id

}
func languageDetect(_ request: Request) -> String {
    if let referer = request.headers[HeaderKey.referrer] {
        if referer.range(of: "-fra.html") != nil {
            return "fra"
        }
    }
    return "eng"
}
func addAdminUser (){
    
}
