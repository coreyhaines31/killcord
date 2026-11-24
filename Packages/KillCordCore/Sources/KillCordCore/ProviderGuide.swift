import Foundation

/// One step in connecting a provider, shown before the paste field.
public struct SetupStep: Sendable, Equatable {
    public let title: String
    public let detail: String
    /// A button that opens the exact console page the step is about. Every URL comes from the provider's docs.
    public let link: Link?

    public struct Link: Sendable, Equatable {
        public let title: String
        public let url: URL
    }

    init(_ title: String, _ detail: String, link: (String, URL)? = nil) {
        self.title = title
        self.detail = detail
        self.link = link.map { Link(title: $0.0, url: $0.1) }
    }
}

/// The words Settings uses to explain a provider before and after connecting. Short on purpose: the long
/// notes in `ProviderInfo` stay available behind a disclosure.
extension ProviderInfo {
    /// What the provider's console is called: "Claude Console".
    public var consoleName: String {
        switch id {
        case .anthropic: "Claude Console"
        case .google: "Google Cloud console"
        case .openai: "OpenAI dashboard"
        case .vercel: "Vercel dashboard"
        case .cloudflare: "Cloudflare dashboard"
        case .twilio: "Twilio Console"
        case .neon: "Neon Console"
        case .supabase: "Supabase dashboard"
        case .openrouter: "OpenRouter settings"
        case .dataforseo: "DataForSEO dashboard"
        case .ahrefs: "Ahrefs app"
        case .firecrawl: "Firecrawl dashboard"
        case .treg: "treg dashboard"
        case .monid: "Monid dashboard"
        case .fal: "fal dashboard"
        case .elevenlabs: "ElevenLabs settings"
        case .xai: "xAI Console"
        case .deepseek: "DeepSeek Platform"
        case .apify: "Apify Console"
        case .tavily: "Tavily dashboard"
        case .deepgram: "Deepgram Console"
        case .runway: "Runway developer portal"
        case .serpapi: "SerpApi dashboard"
        case .custom: "service's site"
        case .manual: "service's site"
        }
    }

    /// A chip next to the name: what kind of number Kill Cord can show.
    public var capabilityLabel: String {
        switch capability {
        case .dollars: "Dollar spend"
        case .requiresSetup: "Dollar spend, needs setup"
        case .usageUnitsOnly: "Usage units only"
        case .noUsageAPI: "Caps only"
        case .balance: "Balance left"
        case .enteredByHand: "Entered by you"
        }
    }

    /// One line on what Kill Cord shows for this provider, with its reporting delay and any plan limits.
    public var overview: String {
        let shows: String = switch capability {
        case .dollars: "Shows today's and this month's spend."
        case .requiresSetup: "Shows spend from your Cloud Billing export in BigQuery."
        case .usageUnitsOnly: "Shows this month's usage. \(name) doesn't report dollars."
        case .noUsageAPI: "\(name) has no spend API, so there's nothing to connect. Turn on its Spend Cap in Caps Audit."
        case .balance(let spend) where spend == [.today, .month]:
            "Shows the balance left, and today's and this month's spend."
        case .balance(let spend) where spend.contains(.today): "Shows the balance left, and today's spend."
        case .balance: "Shows the balance left. It's not spend, so it isn't in your totals."
        case .enteredByHand: "For a service with no API: the plan, price and renewal date you enter, with a "
            + "reminder before it renews. It isn't live and isn't in your totals."
        }
        return [shows, delaySummary, requirement].compactMap { $0 }.joined(separator: " ")
    }

    /// How far behind the provider's numbers run, in a few words.
    public var delaySummary: String? {
        switch id {
        case .anthropic: "Runs about 5 minutes behind."
        case .google: "Runs hours behind, up to a day."
        case .openai: "OpenAI doesn't say how far behind it runs."
        case .vercel: "Reported by day, so today may be missing."
        case .cloudflare: "Updated once a day."
        case .twilio: "Runs a few minutes behind."
        case .neon: "Runs about 15 minutes behind."
        case .openrouter: "Recent requests settle after a short delay."
        case .treg: "The balance is live."
        case .supabase, .dataforseo, .ahrefs, .firecrawl, .monid, .fal, .elevenlabs, .xai, .deepseek, .apify,
             .tavily, .deepgram, .runway, .serpapi: nil
        case .custom: "Checked every 15 minutes at most."
        case .manual: nil
        }
    }

    /// What the account needs, or what the numbers leave out.
    public var requirement: String? {
        switch id {
        case .anthropic: "Priority Tier costs aren't included."
        case .cloudflare: "Pay-as-you-go accounts only."
        case .neon: "Launch, Scale, and Agent plans only."
        case .openrouter: "Reads this key only, not the whole account."
        case .ahrefs: "Shows the workspace's API units. Plans without API access can't connect."
        case .custom: "Kill Cord can't verify a custom service's numbers: they're whatever its reply says."
        case .deepseek: "If the account holds both dollars and yuan, shows the dollar balance."
        case .apify: "What's left is what you can spend before your usage limit, when Apify suspends its services."
        case .tavily: "Shows your plan's credits. Pay-as-you-go credits aren't included."
        default: nil
        }
    }

    /// The key-power warning in one short line. The full `keyPowerWarning` sits behind "Why?".
    public var keyPowerSummary: String? {
        switch id {
        case .anthropic: "No Anthropic key is read-only. A key can do what its linked account's role allows."
        case .google: "Give the account read roles only. Your organization may block service account keys."
        case .openai: "Admin keys cover your whole organization. Choose read-only if it's offered."
        case .vercel: "A token acts as you on the teams it covers. Scope it to one team and set an expiry."
        case .twilio: "Twilio has no read-only key. A Standard API key can also send messages and calls."
        case .neon: "Neon has no read-only key. This one can manage every project in the organization."
        case .openrouter: "An API key can spend up to its limit. Make one for Kill Cord with a small limit."
        case .dataforseo: "No read-only credential. The API password can run paid calls on your balance."
        case .ahrefs: "No read-only key is documented. Give this key a small unit limit."
        case .firecrawl: "No read-only key is documented. This key can run scrapes on your credits."
        case .treg: "Every treg token can call tools on the balance. Use a limited agent token."
        case .monid: "No read-only key is documented. This key can start paid runs."
        case .fal: "Use a BILLING-preset key: fal lists only billing reads for it. A FULL key can run models."
        case .elevenlabs: "Limit the key to User read access, so it can't call the speech endpoints."
        case .xai: "xAI has no read-only management key. This one can also create keys and change limits."
        case .deepseek: "DeepSeek has no read-only key. This key can make paid model calls on your balance."
        case .apify: "Apify tokens can do everything in your account unless you scope them. Kill Cord only reads limits."
        case .tavily: "Tavily has no read-only key. This key can run searches on your credits. Give it a credit limit."
        case .deepgram: "Reading balances needs an Admin or Owner key, which can also manage the project's keys."
        case .runway: "Runway has no read-only key. This key can start generations on your credits."
        case .serpapi: "SerpApi has one private key with no scopes. It can run searches on your plan."
        case .custom: "Kill Cord can't know what this key can do. Use the most limited one the service offers."
        case .manual: nil
        case .cloudflare, .supabase: nil
        }
    }

    /// `keyKind` mid-sentence, with its article: "an admin API key", "a service account key".
    public var keyKindInSentence: String {
        var words = keyKind.split(separator: " ").map(String.init)
        // Lowercase the first word unless it's an acronym ("API token" stays "API").
        if let first = words.first, first.count > 1, first.dropFirst().first?.isLowercase == true {
            words[0] = first.lowercased()
        }
        let phrase = words.joined(separator: " ")
        let article = phrase.first.map { "aeiouAEIOU".contains($0) } == true ? "an" : "a"
        return "\(article) \(phrase)"
    }

    /// The steps before the paste field. The paste step itself is drawn by the app from `fields`.
    public var setupSteps: [SetupStep] {
        func open(_ title: String) -> (String, URL)? { keyURL.map { (title, $0) } }
        switch id {
        case .anthropic:
            let organization = URL(string: "https://platform.claude.com/settings/organization")!
            let serviceAccounts = URL(string: "https://platform.claude.com/settings/service-accounts")!
            return [
                SetupStep("Use an organization, not an Individual Org", "The cost report isn't available to "
                    + "individual Console accounts. If the Console shows an Individual Org, set up an "
                    + "organization first.",
                          link: ("Open Organization Settings", organization)),
                SetupStep("Create a service account (recommended)", "An organization admin creates it on the "
                    + "Service accounts page. Its key acts only as that service account, with its permissions, "
                    + "and isn't tied to you.",
                          link: ("Open Service Accounts", serviceAccounts)),
                SetupStep("Create a key that isn't scoped to a workspace", "On API keys, set Linked account to "
                    + "the service account (or yourself) and leave the workspace unset. Workspace keys won't "
                    + "work. An Admin API key (sk-ant-admin…) from Admin keys also works.",
                          link: open("Open API Keys"))
            ]
        case .google:
            return [
                SetupStep("Turn on the billing export", "In Billing export, send the standard usage cost data to "
                    + "a BigQuery dataset. Data starts arriving a few hours later.",
                          link: ("Open Billing Export", URL(string: "https://console.cloud.google.com/billing/export")!)),
                SetupStep("Create a service account and a JSON key", "Give it BigQuery Data Viewer on the export "
                    + "dataset and BigQuery Job User on its project. Add Billing Account Viewer if you want Kill "
                    + "Cord to check your budgets and spend caps.", link: open("Open Service Accounts"))
            ]
        case .openai:
            return [
                SetupStep("Open Admin keys in the OpenAI dashboard", "Under Settings › Organization.",
                          link: open("Open OpenAI Dashboard")),
                SetupStep("Create an admin key and copy it", "It starts with sk-admin-. A project API key won't work.")
            ]
        case .vercel:
            return [
                SetupStep("Open Tokens in your Vercel account", "Under Account Settings › Tokens.",
                          link: open("Open Vercel Tokens")),
                SetupStep("Create a token and copy it", "Scope it to the team you want to watch.")
            ]
        case .cloudflare:
            return [
                SetupStep("Open API Tokens in the Cloudflare dashboard", "Under My Profile › API Tokens.",
                          link: open("Open Cloudflare Tokens")),
                SetupStep("Create a custom token and copy it", "Give it only the Billing Read permission. "
                    + "It can't change anything.")
            ]
        case .twilio:
            return [
                SetupStep("Open the Twilio Console", "Go to Account › API keys and tokens.",
                          link: open("Open Twilio Console")),
                SetupStep("Create a Standard API key", "Copy its SID and secret. You can use your Auth Token "
                    + "instead, but it can do more.")
            ]
        case .neon:
            return [
                SetupStep("Open your organization in the Neon Console", "Go to Organization settings › API keys.",
                          link: open("Open Neon Console")),
                SetupStep("Create an organization API key and copy it", "Copy the organization ID from "
                    + "Organization settings › General too.")
            ]
        case .supabase:
            return []
        case .openrouter:
            return [
                SetupStep("Open API Keys in OpenRouter", "Under Settings › API Keys.", link: open("Open OpenRouter Keys")),
                SetupStep("Create a key with a small credit limit and copy it", "Kill Cord shows that key's limit "
                    + "left and its spend today and this month.")
            ]
        case .dataforseo:
            return [
                SetupStep("Open API Access in DataForSEO", "Your API login and API password are there. They're "
                    + "not your dashboard sign-in.", link: open("Open API Access")),
                SetupStep("Copy the API login and API password", "Kill Cord reads your balance with them. "
                    + "DataForSEO doesn't charge for that call.")
            ]
        case .ahrefs:
            let docs = URL(string: "https://docs.ahrefs.com/docs/api/subscription-info/operations/get-limits-and-usage")!
            return [
                SetupStep("Create an API key in Ahrefs", "Your plan needs API access. Give the key its own unit "
                    + "limit if Ahrefs offers it.", link: ("Open Ahrefs API Docs", docs)),
                SetupStep("Copy the key", "Kill Cord reads limits and usage, which Ahrefs says uses no units.")
            ]
        case .firecrawl:
            return [
                SetupStep("Open API Keys in Firecrawl", "In the Firecrawl dashboard.", link: open("Open Firecrawl Keys")),
                SetupStep("Copy a key for the team to watch", "It starts with fc-.")
            ]
        case .treg:
            return [
                SetupStep("Make an agent token for Kill Cord", "An admin runs treg org agent-new kill-cord, with "
                    + "options that limit it. treg shows the token once.", link: open("Open treg Docs")),
                SetupStep("Copy the token", "A personal sign-in token works too if you add your team's slug.")
            ]
        case .monid:
            return [
                SetupStep("Open API Keys in Monid", "In the Monid dashboard.", link: open("Open Monid Keys")),
                SetupStep("Create a key and copy it", "It starts with monid_.")
            ]
        case .fal:
            return [
                SetupStep("Open API Keys in fal", "In the fal dashboard.", link: open("Open fal Keys")),
                SetupStep("Create a key with the BILLING preset and copy it", "fal lists only billing reads for "
                    + "it. Don't use a FULL key: it can run models on your credits.")
            ]
        case .elevenlabs:
            return [
                SetupStep("Open API Keys in ElevenLabs", "Under Settings › API Keys.",
                          link: open("Open ElevenLabs Keys")),
                SetupStep("Create a key that can only read User and copy it", "Turn off every other endpoint, "
                    + "so the key can't make speech. ElevenLabs doesn't say which permission this call needs; "
                    + "User read is the likely one.")
            ]
        case .xai:
            return [
                SetupStep("Open Management Keys in the xAI Console", "Under Settings › Management Keys. Your "
                    + "account needs the Management Keys Read and Write permissions.",
                          link: open("Open xAI Management Keys")),
                SetupStep("Create a management key and copy it", "It's separate from the API keys that call Grok."),
                SetupStep("Copy your team ID", "On Settings › Team in the same console.",
                          link: ("Open Team Settings", URL(string: "https://console.x.ai/team/default/settings/team")!))
            ]
        case .deepseek:
            return [
                SetupStep("Open API Keys on the DeepSeek Platform", "Sign in at platform.deepseek.com.",
                          link: open("Open DeepSeek Keys")),
                SetupStep("Create a key just for Kill Cord and copy it", "DeepSeek shows it once. It starts "
                    + "with sk-.")
            ]
        case .apify:
            return [
                SetupStep("Open API & Integrations in Apify Console", "Under Settings › API & Integrations.",
                          link: open("Open Apify Tokens")),
                SetupStep("Create a token for Kill Cord and copy it", "Apify's docs don't say which scoped-token "
                    + "permission reads usage limits. If a scoped token is refused, Kill Cord says so.")
            ]
        case .tavily:
            return [
                SetupStep("Open the Tavily dashboard", "API keys are on the Overview page.",
                          link: open("Open Tavily Dashboard")),
                SetupStep("Create a key for Kill Cord and copy it", "It starts with tvly-. Give it a small credit "
                    + "limit: Kill Cord only reads usage.")
            ]
        case .deepgram:
            return [
                SetupStep("Open the Deepgram Console", "Pick the project, then Settings › API Keys.",
                          link: open("Open Deepgram Console")),
                SetupStep("Create an Admin key and copy it", "Deepgram gives billing:read to the Admin and Owner "
                    + "roles only, so a Member key can't read balances."),
                SetupStep("Add the project ID if the key sees more than one", "It's in the project's settings. "
                    + "With one project, Kill Cord finds it.")
            ]
        case .runway:
            return [
                SetupStep("Open the Runway developer portal", "Pick the project, then its API Keys tab.",
                          link: open("Open Runway Dev")),
                SetupStep("Create a key for Kill Cord and copy it", "It starts with key_. Runway shows it once.")
            ]
        case .serpapi:
            return [
                SetupStep("Open the SerpApi dashboard", "Your private API key is on it.",
                          link: open("Open SerpApi Dashboard")),
                SetupStep("Copy the private API key", "Kill Cord reads your account, which SerpApi says is free "
                    + "and doesn't count toward your searches.")
            ]
        case .manual:
            return [
                SetupStep("Open the service's billing page", "Find your plan, its price, and the next renewal date."),
                SetupStep("Fill them in here", "Kill Cord never contacts the service. It reminds you before the "
                    + "renewal and moves the date forward each period.")
            ]
        case .custom:
            return [
                SetupStep("Find the service's balance call", "In its API docs: an https address that answers with "
                    + "the balance or credits left in JSON, or as a plain number."),
                SetupStep("Fill in where the number is", "Kill Cord calls it once to test before saving. It can't "
                    + "check that the number is right, so compare it with the service's own dashboard.")
            ]
        }
    }
}
