import Foundation
import HTTP
import Core

public final class UACompatibleMiddleware: Middleware {

    public init() {}

    public func respond(to request: Request, chainingTo next: Responder) throws -> Response {
        let response = try next.respond(to: request)

        response.headers["X-UA-Compatible"] = "IE=Edge" //used to make WET-BOEW work on IE9

        return response
    }
}
