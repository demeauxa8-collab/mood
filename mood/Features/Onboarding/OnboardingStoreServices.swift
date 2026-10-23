import Foundation

@MainActor
extension OnboardingServices {
    static func live(account: AccountStore, matrix: MatrixStore) -> Self {
        func connected() async throws {
            guard account.isSignedIn else { throw OnboardingError.invalidLogin }
            if !account.matrixReady { await account.connectMood(matrixStore: matrix) }
            guard account.matrixReady, matrix.userId != nil else {
                throw AccountError.server(account.provisioningError ?? "Impossible de joindre Mood. Réessaie.")
            }
        }
        func matrixFailure() -> AccountError {
            .server(matrix.errorMessage ?? "Cette action n’a pas pu être enregistrée. Réessaie.")
        }
        return Self(
            checkUsername: { name in
                try await account.isUsernameAvailable(name)
            },
            register: { email, password in
                try await account.registerForOnboarding(email: email, password: password)
            },
            confirm: { code, email in
                if !account.isSignedIn { try await account.confirmSignup(code: code, email: email) }
                guard let session = account.session,
                      session.user.email?.lowercased() == email.lowercased() else { throw OnboardingError.invalidLogin }
                return session.user.id.uuidString
            },
            resend: { email in
                guard let client = account.client else { throw AccountError.notConfigured }
                try await client.resendConfirmation(email: email)
            },
            login: { email, password in
                try await account.signIn(email: email, password: password)
                guard let id = account.session?.user.id else { throw AccountError.invalidResponse }
                return id.uuidString
            },
            resetPassword: { email in try await account.sendRecoveryCode(email: email) },
            setUsername: { name in
                do { try await account.setUsername(name) }
                catch AccountError.usernameTaken { throw OnboardingError.usernameTaken }
            },
            setDisplayName: { name in
                try await connected()
                matrix.errorMessage = nil
                guard await matrix.updateDisplayName(name) else { throw matrixFailure() }
            },
            setAvatar: { data in
                let photo = try OnboardingAvatar.photo(data)
                try await connected()
                matrix.errorMessage = nil
                guard await matrix.updateAvatar(imageData: photo, filename: "avatar.jpg") else { throw matrixFailure() }
            },
            setAvatarEmoji: { emoji in
                let image = try OnboardingAvatar.emoji(emoji)
                try await connected()
                matrix.errorMessage = nil
                guard await matrix.updateAvatar(imageData: image, filename: "avatar.png") else { throw matrixFailure() }
            },
            searchUser: { username in
                try await connected()
                let results = await matrix.searchMoodUsername(username)
                if let error = matrix.errorMessage { throw AccountError.server(error) }
                guard let result = results.first else { return nil }
                return matrix.makeUser(result.userId, displayName: result.displayName, avatarMxc: result.avatarUrl)
            },
            addFriend: { user in
                try await connected()
                guard let id = user.matrixId, await matrix.openOrCreateDM(with: id) != nil else { throw matrixFailure() }
            },
            openDM: { user in
                try await connected()
                guard let id = user.matrixId, let conversation = await matrix.openOrCreateDM(with: id) else { throw matrixFailure() }
                matrix.openAccountConversation(conversation)
            },
            joinServer: { code in
                try await connected()
                matrix.errorMessage = nil
                guard await matrix.joinServer(fromInvite: code) != nil else { throw matrixFailure() }
            },
            createServer: { name, template in
                try await connected()
                matrix.errorMessage = nil
                guard await matrix.createOnboardingServer(name: name, template: template) != nil else { throw matrixFailure() }
            },
            requestNotifications: {
                try await connected()
                await matrix.setNotificationsEnabled(true)
            },
            finish: { try await connected() }
        )
    }
}
