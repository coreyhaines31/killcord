import Foundation

/// Setup steps for the services in `ProviderInfo.moreBalanceProviders`, kept apart so `ProviderGuide.swift` stays
/// short and the two provider lists don't collide.
extension ProviderInfo {
    var moreSetupSteps: [SetupStep] {
        func open(_ title: String) -> (String, URL)? { keyURL.map { (title, $0) } }
        switch id {
        case .runpod:
            return [
                SetupStep("Open Credentials in the Runpod console", "On the API Keys tab.",
                          link: open("Open Runpod Keys")),
                SetupStep("Create a Read Only key and copy it", "Or a Restricted key with only the billing:read "
                    + "scope. Don't use an All key: it can start Pods and workers on your balance.")
            ]
        case .deepinfra:
            return [
                SetupStep("Open API Keys in the DeepInfra dashboard", "Create a new key for Kill Cord.",
                          link: open("Open DeepInfra Keys")),
                SetupStep("Choose Scoped and leave only billing:read, then copy the key", "A new key starts "
                    + "with inference, models:read, account:read, lora:read and voice:read. Untick them all.")
            ]
        case .xapi:
            return [
                SetupStep("Open your app in the X Developer Console", "Pick the app, then Keys and tokens.",
                          link: open("Open X Developer Console")),
                SetupStep("Copy the app's Bearer token", "Kill Cord reads your credit balance with it. Use an "
                    + "app made just for Kill Cord, so you can regenerate its token on its own.")
            ]
        case .bfl:
            return [
                SetupStep("Open your project in the BFL dashboard", "Then API › Keys.",
                          link: open("Open BFL Dashboard")),
                SetupStep("Add a key for Kill Cord and copy it", "It starts with bfl_. BFL shows the full key only "
                    + "once.")
            ]
        case .digitalocean:
            return [
                SetupStep("Open API in the DigitalOcean control panel", "Applications & API › Tokens, then "
                    + "Generate New Token.", link: open("Open DigitalOcean Tokens")),
                SetupStep("Choose Custom Scopes, tick only billing:read, and copy the token", "Pick an expiration "
                    + "too. DigitalOcean doesn't let you change a token's scopes later.")
            ]
        default:
            return []
        }
    }
}
