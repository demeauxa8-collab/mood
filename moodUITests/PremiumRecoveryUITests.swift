import XCTest

/// These tests launch only account-free fixtures, and only on the dedicated X simulator.
@MainActor
final class PremiumRecoveryUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        guard ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] == "Mood X iPhone" else {
            throw XCTSkip("Premium UI checks require the dedicated Mood X iPhone simulator.")
        }
    }

    private func launch(_ screen: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiPreview", "-uiPreviewScreen", "premium-" + screen]
        app.launch()
        return app
    }

    private func capture(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testUndoRestoresTheMessageInTheConversation() {
        let app = launch("undo")
        let undo = app.buttons["Annuler"].firstMatch
        XCTAssertTrue(undo.waitForExistence(timeout: 4))
        capture("undo-before-tap", app: app)
        undo.tap()
        XCTAssertFalse(app.staticTexts["Message supprimé"].exists)
        XCTAssertTrue(app.staticTexts["Oui ! Je vous rejoins avec les photos."].exists)
        capture("undo-after-tap", app: app)
        app.terminate()
    }

    func testFailedMessageOffersRetryAndDiscardAtTheMessage() {
        var app = launch("failed")
        let retry = app.buttons["Renvoyer"].firstMatch
        XCTAssertTrue(retry.waitForExistence(timeout: 5))
        retry.tap()
        XCTAssertTrue(app.staticTexts["Envoi en cours…"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.staticTexts["Échec de l’envoi"].exists)
        capture("failed-after-retry", app: app)
        app.terminate()
        app = launch("failed")
        let discard = app.buttons["Supprimer"].firstMatch
        XCTAssertTrue(discard.waitForExistence(timeout: 5))
        discard.tap()
        XCTAssertFalse(app.staticTexts["Oui ! Je vous rejoins avec les photos."].exists)
        XCTAssertFalse(app.staticTexts["Échec de l’envoi"].exists)
        capture("failed-after-discard", app: app)
        app.terminate()
    }

    func testConnectionCapsuleOpensRecoveryWithoutHidingTheConversation() {
        let app = launch("offline")
        let capsule = app.buttons["conversation-connection"]
        XCTAssertTrue(capsule.waitForExistence(timeout: 6))
        XCTAssertTrue(app.staticTexts["En attente · partira tout seul"].firstMatch.exists)
        XCTAssertFalse(app.staticTexts["En ligne - 4"].exists)
        capture("offline-capsule", app: app)
        capsule.tap()
        XCTAssertTrue(app.buttons["Réessayer"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["2 messages en attente"].exists)
        capture("offline-details", app: app)
        app.buttons["Fermer"].tap()
        XCTAssertTrue(capsule.waitForExistence(timeout: 3))
        app.terminate()
    }

    func testExpiredSessionOpensLoginAfterClosingTheDetailsSheet() {
        let app = launch("session")
        let capsule = app.buttons["conversation-connection"]
        XCTAssertTrue(capsule.waitForExistence(timeout: 6))
        capsule.tap()
        let reconnect = app.buttons["Se reconnecter"]
        XCTAssertTrue(reconnect.waitForExistence(timeout: 3))
        reconnect.tap()
        XCTAssertTrue(app.buttons["Annuler"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Homeserver avancé"].exists)
        XCTAssertFalse(app.staticTexts["Propulsé par  [matrix]"].exists)
        capture("session-login", app: app)
        app.buttons["Annuler"].firstMatch.tap()
        XCTAssertTrue(capsule.waitForExistence(timeout: 3))
        app.terminate()
    }

    func testWaitingMessagesConfirmDeliveryOnceThenClearTheConfirmation() {
        let app = launch("recovered")
        let confirmation = app.staticTexts["message-sent"].firstMatch
        XCTAssertTrue(confirmation.waitForExistence(timeout: 8))
        capture("recovered-message-checkmarks", app: app)
        XCTAssertTrue(confirmation.waitForNonExistence(timeout: 4))
        XCTAssertFalse(app.staticTexts["En attente · partira tout seul"].exists)
        capture("recovered-settled", app: app)
        app.terminate()
    }

    func testOversizedPhotoRecoveryOpensTheRealAttachmentPicker() {
        let app = launch("large-photo")
        let choose = app.buttons["Choisir un fichier"].firstMatch
        XCTAssertTrue(choose.waitForExistence(timeout: 5))
        choose.tap()
        XCTAssertTrue(app.buttons["Fichiers"].waitForExistence(timeout: 3))
        capture("large-photo-file-picker", app: app)
        app.terminate()
    }
}
