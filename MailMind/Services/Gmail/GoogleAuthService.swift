import Foundation
import UIKit
import GoogleSignIn

struct GoogleSignInResult {
    let email: String
    let tokens: GmailTokens
}

enum GoogleAuthError: Error, LocalizedError {
    case userCancelled
    case missingEmail
    case missingPresenter
    case signInFailed(Error)

    var errorDescription: String? {
        switch self {
        case .userCancelled:
            return "Sign-in cancelled."
        case .missingEmail:
            return "Google didn't return an email address."
        case .missingPresenter:
            return "Couldn't find a window to present the sign-in sheet."
        case .signInFailed(let error):
            return error.localizedDescription
        }
    }
}

final class GoogleAuthService {
    private let gmailReadonlyScope = "https://www.googleapis.com/auth/gmail.readonly"
    private let emailScope = "email"

    @MainActor
    func signIn(presenting viewController: UIViewController, hint: String? = nil) async throws -> GoogleSignInResult {
        let scopes = [gmailReadonlyScope, emailScope]

        let result: GIDSignInResult
        do {
            result = try await GIDSignIn.sharedInstance.signIn(
                withPresenting: viewController,
                hint: hint,
                additionalScopes: scopes
            )
        } catch {
            if (error as NSError).code == GIDSignInError.canceled.rawValue {
                throw GoogleAuthError.userCancelled
            }
            throw GoogleAuthError.signInFailed(error)
        }

        return try makeResult(from: result.user)
    }

    @MainActor
    func restorePreviousSignIn() async -> GoogleSignInResult? {
        guard let user = try? await GIDSignIn.sharedInstance.restorePreviousSignIn() else {
            return nil
        }
        return try? makeResult(from: user)
    }

    private func makeResult(from user: GIDGoogleUser) throws -> GoogleSignInResult {
        guard let email = user.profile?.email else {
            throw GoogleAuthError.missingEmail
        }

        let tokens = GmailTokens(
            accessToken: user.accessToken.tokenString,
            refreshToken: user.refreshToken.tokenString,
            accessTokenExpiresAt: user.accessToken.expirationDate ?? Date().addingTimeInterval(3300),
            scope: gmailReadonlyScope,
            email: email
        )

        return GoogleSignInResult(email: email.lowercased(), tokens: tokens)
    }
}
