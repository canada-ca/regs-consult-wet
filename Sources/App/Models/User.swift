//
//  User.swift
//  Consultation
//
//  Created by Steve Hume on 2017-01-31.
//
//

import Foundation
import Vapor
import Turnstile
import Fluent
import Auth
import BCrypt

final class User: Model {
    var id: Node?
    var name: String
    var username: String
    var password: String
    var resetPasswordRequired: Bool = false
    var admin: Bool
//    var receive: Bool
//    var analyze: Bool
//    var review: Bool
    // used by fluent internally
    var exists: Bool = false
    static var entity = "users"   //db table name

    init(name: String, username: String, password: String) {
        self.id = nil
        self.name = name
        self.username = username.lowercased()
        self.password = password
        self.admin = false
//        self.receive = false
//        self.analyze = false
//        self.review = false

    }

    init(node: Node, in context: Context) throws {
        id = try node.extract("id")
         name = try node.extract("name")
        username = try node.extract("username")
        password = try node.extract("password")
        resetPasswordRequired = try node.extract("reset_password_required")
        self.admin = try node.extract("admin")
//        self.receive = try node.extract("receive")
//        self.analyze = try node.extract("analyze")
//        self.review = try node.extract("review")
    }

    func makeNode(context: Context) throws -> Node {
        return try Node(node: [
            "id": id,
            "name": name,
            "username": username,
            "password": password,
            "reset_password_required": resetPasswordRequired,
            "admin": admin
//            "receive": receive,
//            "analyze": analyze,
//            "review": review
            ])
    }
}

extension User: Preparation {
    static func prepare(_ database: Database) throws {
        try database.create(entity, closure: { (user) in
            user.id()
            user.string("name")
            user.string("username")
            user.string("password")
            user.bool("reset_password_required")
            user.bool("admin")
//            user.bool("receive")
//            user.bool("analyze")
//            user.bool("review")
        })
    }

    static func revert(_ database: Database) throws {
        try database.delete(entity)
    }
}
struct UserCredentials: Credentials {

    let username: String
    let name: String?
    let password: String

    public init(username: String, password: String, name: String? = nil) {
        self.username = username.lowercased()
        self.password = password
        self.name = name
    }
}
extension User: Auth.User {
    convenience init(credentials: UserCredentials) throws {
        self.init(name: credentials.name ?? "", username: credentials.username, password: try BCrypt.digest(password: credentials.password))
    }
    static func register(credentials: Credentials) throws -> Auth.User {
        guard let usernamePassword = credentials as? UserCredentials else {
            throw Abort.custom(status: .forbidden, message: "Unsupported credentials type \(type(of: credentials))")
        }

        let user = try User(credentials: usernamePassword)
        return user
    }

    static func authenticate(credentials: Credentials) throws -> Auth.User {
        switch credentials {
        case let usernamePassword as UserCredentials:
            guard let user = try User.query().filter("username", usernamePassword.username).first() else {
                throw Abort.custom(status: .networkAuthenticationRequired, message: "Invalid username or password")
            }
            if try BCrypt.verify(password: usernamePassword.password, matchesHash: user.password) {
                return user
            }
            else {
                throw Abort.custom(status: .networkAuthenticationRequired, message: "Invalid username or password")
            }
        case let id as Identifier:
            guard let user = try User.find(id.id) else {
                throw Abort.custom(status: .forbidden, message: "Invalid user identifier")
            }
            return user
        default:
            throw Abort.custom(status: .forbidden, message: "Unsupported credentials type \(type(of: credentials))")
        }
    }
//
//    static func authenticate(credentials: Credentials) throws -> Auth.User {
//        switch credentials {
//        case let id as Identifier:
//            guard let user = try User.find(id.id) else {
//                throw Abort.custom(status: .forbidden, message: "Invalid user identifier.")
//            }
//
//            return user
//
//        case let usernamePassword as UsernamePassword:
//            let fetchedUser = try User.query().filter("username", usernamePassword.username).first()
//            guard let user = fetchedUser else {
//                throw Abort.custom(status: .networkAuthenticationRequired, message: "Invalid user name or password.")
//            }
//            if try BCrypt.verify(password: usernamePassword.password, matchesHash: fetchedUser!.password) {
//                return user
//            } else {
//                throw Abort.custom(status: .networkAuthenticationRequired, message: "Invalid user name or password.")
//            }
//
//        default:
//            let type = type(of: credentials)
//            throw Abort.custom(status: .forbidden, message: "Unsupported credential type: \(type).")
//        }
//    }
//    static func register(credentials: Credentials) throws -> Auth.User {
//        let usernamePassword = credentials as? UsernamePassword
//
//        guard let creds = usernamePassword else {
//            let type = type(of: credentials)
//            throw Abort.custom(status: .forbidden, message: "Unsupported credential type: \(type).")
//        }
//
//        if let user = try? User(username: creds.username, password: BCrypt.digest(password: creds.password, salt: BCryptSalt(workFactor:10))) {
//            return user
//        } else {
//            throw Abort.custom(status: .forbidden, message: "digest problem")
//        }
//    }
}
