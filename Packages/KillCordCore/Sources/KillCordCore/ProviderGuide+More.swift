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
        case .telnyx:
            return [
                SetupStep("Open API Keys in the Telnyx portal", "In Mission Control Portal.",
                          link: open("Open Telnyx API Keys")),
                SetupStep("Create a key for Kill Cord and copy it", "Telnyx keys reach the whole account, so make "
                    + "one just for Kill Cord that you can revoke on its own.")
            ]
        case .luma:
            return [
                SetupStep("Open the Luma developer dashboard", "On the Luma API Platform.",
                          link: open("Open Luma Platform")),
                SetupStep("Create an API key for Kill Cord and copy it", "It starts with luma-api-. Luma shows it "
                    + "only once.")
            ]
        case .heygen:
            return [
                SetupStep("Open API keys on the HeyGen platform", "Create a new key for Kill Cord.",
                          link: open("Open HeyGen API Keys")),
                SetupStep("Restrict it to account:read and copy it", "That's the only scope GET /v3/users/me "
                    + "needs. A full-access key (*:*) can make videos on your balance.")
            ]
        case .browseruse:
            return [
                SetupStep("Open API Keys in Browser Use Cloud", "Select the project whose credits you want.",
                          link: open("Open Browser Use Settings")),
                SetupStep("Create a key for Kill Cord and copy it", "Give it a small monthly spending cap: Kill Cord "
                    + "only reads the balance.")
            ]
        default:
            return []
        }
    }

    /// What the provider's console is called.
    var moreConsoleName: String {
        switch id {
        case .runpod: "Runpod console"
        case .deepinfra: "DeepInfra dashboard"
        case .xapi: "X Developer Console"
        case .bfl: "BFL dashboard"
        case .digitalocean: "DigitalOcean control panel"
        case .telnyx: "Telnyx Mission Control Portal"
        case .luma: "Luma developer dashboard"
        case .heygen: "HeyGen API dashboard"
        case .browseruse: "Browser Use Cloud dashboard"
        default: "service's site"
        }
    }

    /// How far behind the numbers run.
    var moreDelaySummary: String? {
        switch id {
        case .runpod: "Runpod bills every 5 minutes."
        case .deepinfra: "DeepInfra doesn't say how far behind usage runs."
        case .xapi: "Credits are deducted as requests are made."
        case .bfl: nil
        case .digitalocean: "Usage is as of the time DigitalOcean last generated it."
        case .telnyx: nil
        case .luma: "Credits held for running generations are already taken out."
        case .heygen: nil
        case .browseruse: nil
        default: nil
        }
    }

    /// What the account needs, or what the numbers leave out.
    var moreRequirement: String? {
        switch id {
        case .xapi: "Pay-per-use accounts only. Shows prepaid and free credits together."
        case .bfl: "BFL prices 1 credit at $0.01, so the dollar figure is an estimate from that."
        case .telnyx: "Shows available credit: your balance plus Telnyx's credit limit."
        case .luma: "Shows your team's whole credit balance. Luma sets no fixed dollar rate, so it stays in credits."
        case .heygen: "Shows a prepaid wallet, what's left under a usage-based spending cap, or plan credits."
        case .browseruse: "Shows the credits of the key's project. Each project has its own balance."
        default: nil
        }
    }

    /// The key-power warning in one short line.
    var moreKeyPowerSummary: String? {
        switch id {
        case .runpod: "Use a Read Only key. An All key can start Pods and workers on your balance."
        case .deepinfra: "Give the key only billing:read. New keys start with inference, so untick it."
        case .xapi: "The X API has no read-only token. This Bearer token can make paid reads on your credits."
        case .bfl: "BFL has no read-only key. A project key can generate images on your credits."
        case .digitalocean: "Use a custom-scoped token with only billing:read. It can't change anything."
        case .telnyx: "Telnyx has no read-only key. This key can send messages, buy numbers and change the account."
        case .luma: "Luma has no read-only key for the balance. This API key can start generations on your credits."
        case .heygen: "Restrict the key to account:read. A full-access key can make videos on your balance."
        case .browseruse: "Browser Use has no read-only key. This key can run agents and browsers on the project's credits."
        default: nil
        }
    }
}
