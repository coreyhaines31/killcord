import Foundation

/// Settings copy for the services in `ProviderInfo.batch3Providers`, kept apart so `ProviderGuide.swift` stays
/// readable. `ProviderGuide.swift` routes each of these providers here.
extension ProviderInfo {
    var batch3ConsoleName: String {
        switch id {
        case .stability: "Stability AI platform"
        case .moonshot: "Kimi console"
        case .exa: "Exa dashboard"
        case .scrapingbee: "ScrapingBee dashboard"
        case .scrapfly: "Scrapfly dashboard"
        case .kie: "Kie.ai dashboard"
        case .bland: "Bland dashboard"
        case .llamacloud: "LlamaCloud settings"
        default: "service's site"
        }
    }

    /// None of these providers says how far behind its numbers run yet.
    var batch3DelaySummary: String? {
        switch id {
        case .stability: nil
        case .exa: "Runs up to 5 minutes behind."
        case .scrapingbee: "Usage is live."
        default: nil
        }
    }

    var batch3Requirement: String? {
        switch id {
        case .moonshot: "Global platform (platform.kimi.ai) accounts only, in dollars."
        case .exa: "Needs Exa's Team Management API, which Exa turns on per team on request."
        case .scrapfly: "Shows the plan's scrape credits for the whole account."
        case .llamacloud: "Shows this billing period's invoice so far. Plans without User API Keys can't connect."
        default: nil
        }
    }

    var batch3KeyPowerSummary: String? {
        switch id {
        case .stability: "Stability AI has no read-only key. This key can run generations on your credits."
        case .moonshot: "Use an Admin key with only billing:read: it can't call models. An inference key can spend."
        case .exa: "A service key can also create and delete your API keys. Exa has no read-only one."
        case .scrapingbee: "ScrapingBee has no read-only key. This key can run scrapes on your plan's credits."
        case .scrapfly: "Scrapfly has no read-only key. This key can run scrapes on your plan's credits."
        case .kie: "Kie.ai has no read-only key. This key can run generations on your credits. Give it small caps."
        case .bland: "Use a restricted key with only Analytics read. A full-access key can place calls."
        case .llamacloud: "A user key does what its owner can. Make it from the member with the least access."
        default: nil
        }
    }

    var batch3SetupSteps: [SetupStep] {
        func open(_ title: String) -> (String, URL)? { keyURL.map { (title, $0) } }
        switch id {
        case .stability:
            return [
                SetupStep("Open API Keys on the Stability AI platform", "Sign in at platform.stability.ai.",
                          link: open("Open Stability Keys")),
                SetupStep("Create a key just for Kill Cord and copy it", "Stability AI keys have no scopes, so "
                    + "revoke it there if it leaks.")
            ]
        case .moonshot:
            return [
                SetupStep("Open Admin API Keys in the Kimi console", "Under Organization › Admin API Keys. Kimi "
                    + "offers Admin keys to organizations that have completed verification.",
                          link: open("Open Kimi Console")),
                SetupStep("Create an Admin key with only the billing:read scope and copy it", "It starts with "
                    + "sk-admin-. Kimi says Admin keys can't call any inference endpoint."),
                SetupStep("No Admin keys? Use an inference API key instead", "From API Keys in the same console. "
                    + "It works, but it can make paid model calls on your balance.")
            ]
        case .exa:
            return [
                SetupStep("Open the Service keys tab on API Keys", "In the Exa dashboard. If there's no such "
                    + "tab, ask support@exa.ai to turn on the Team Management API: Exa enables it per team.",
                          link: open("Open Exa API Keys")),
                SetupStep("Create a service key and copy it", "It can manage your API keys, so keep it to Kill "
                    + "Cord. A search API key won't work.")
            ]
        case .scrapingbee:
            return [
                SetupStep("Open your API key in the ScrapingBee dashboard", "Under Account › Manage › API key.",
                          link: open("Open ScrapingBee Key")),
                SetupStep("Copy the API key", "Kill Cord reads your plan's credit usage. ScrapingBee keys have no "
                    + "scopes, so regenerate it there if it leaks.")
            ]
        case .scrapfly:
            return [
                SetupStep("Open Projects in the Scrapfly dashboard", "Pick a project and its LIVE environment.",
                          link: open("Open Scrapfly Projects")),
                SetupStep("Copy the LIVE API key", "Kill Cord reads your account's credit usage with it. It "
                    + "travels in the request address, as Scrapfly requires, and Kill Cord strips it from errors.")
            ]
        case .kie:
            return [
                SetupStep("Open API Key on kie.ai", "Sign in to Kie.ai.", link: open("Open Kie.ai Keys")),
                SetupStep("Create a key for Kill Cord with small usage caps and copy it", "Kie.ai keys have no "
                    + "scopes, but each can carry hourly, daily and total usage caps.")
            ]
        case .bland:
            return [
                SetupStep("Open Settings › API keys in Bland", "An owner or admin creates keys.",
                          link: open("Open Bland Settings")),
                SetupStep("Create a restricted key with only Analytics read and copy it", "Under Permissions, "
                    + "choose Restricted, then Analytics and Read. It starts with org_s_. Bland says every "
                    + "restricted key can read the balance."),
                SetupStep("No Restricted option? Use a full-access key", "Bland is rolling restricted keys out by "
                    + "organization. A full-access key works, but it can place calls on your credits.")
            ]
        case .llamacloud:
            return [
                SetupStep("Open API Key in LlamaCloud", "Pick your region's site if your account is in Europe.",
                          link: open("Open LlamaCloud Keys")),
                SetupStep("Create a key under User API Keys and copy it", "Not under Project API Keys: a project "
                    + "key can't read organization usage. If there's no User API Keys table, your plan doesn't "
                    + "offer one."),
                SetupStep("Add the organization ID if the key sees more than one", "It's on Organization Settings. "
                    + "With one organization, Kill Cord finds it.")
            ]
        default:
            return []
        }
    }
}
