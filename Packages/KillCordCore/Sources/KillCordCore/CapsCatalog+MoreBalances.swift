import Foundation

/// Native caps for the services in `ProviderInfo.moreBalanceProviders`. Same rules as `CapsCatalog`: each link
/// comes from the provider's docs.
extension CapsCatalog {
    private static func url(_ string: String) -> URL { URL(string: string)! }

    static let moreBalanceControls: [CapControl] = [
        // Runpod. https://docs.runpod.io/accounts-billing/billing
        CapControl(
            id: "runpod.prepaid-balance", provider: .runpod, name: "Prepaid balance, auto-pay off",
            summary: "When the balance reaches $0, Runpod stops all running Pods. With auto-pay off, nothing "
                + "tops it up.",
            enforcement: .hardStop, verification: .selfReported,
            consoleURL: url("https://www.console.runpod.io/user/billing"),
            docURL: url("https://docs.runpod.io/accounts-billing/billing"),
            steps: ["Open Billing in the Runpod console.",
                    "Leave auto-pay off, or set a threshold and amount you accept."],
            caveat: "Network volume storage keeps billing while Pods are stopped. Post-paid accounts are invoiced, "
                + "so their balance stops nothing. Runpod also applies a spend limit of $80 an hour by default, "
                + "which only its support changes."
        ),
        CapControl(
            id: "runpod.low-balance", provider: .runpod, name: "Low balance notification",
            summary: "A daily email when the balance falls below a threshold you set.",
            enforcement: .alertOnly, verification: .selfReported,
            consoleURL: url("https://console.runpod.io/user/settings"),
            docURL: url("https://docs.runpod.io/accounts-billing/billing"),
            steps: ["Open Settings in the Runpod console.",
                    "Under Notification settings, edit General notifications.",
                    "Turn on Low balance notification and set the threshold in dollars."],
            caveat: nil
        ),
        // DeepInfra. https://docs.deepinfra.com/private-models/custom-llms and
        // https://docs.deepinfra.com/agents/introduction
        CapControl(
            id: "deepinfra.spending-limit", provider: .deepinfra, name: "Spending limit",
            summary: "DeepInfra tells you to set spending limits in its billing settings so a forgotten "
                + "deployment can't run up a bill.",
            enforcement: .partialStop, verification: .selfReported,
            consoleURL: url("https://deepinfra.com/dash/billing"),
            docURL: url("https://docs.deepinfra.com/private-models/custom-llms"),
            steps: ["Open Billing in the DeepInfra dashboard.", "Set a spending limit you accept."],
            caveat: "DeepInfra's docs don't say exactly what stops at the limit. They do say a suspended account, "
                + "for example one whose balance ran out, has its instances stopped within a minute or two. An "
                + "API key can't change the limit, so Kill Cord can't check it."
        ),
        // X API. https://docs.x.com/x-api/getting-started/pricing
        CapControl(
            id: "xapi.spending-limit", provider: .xapi, name: "Spending limit per billing cycle",
            summary: "When the limit is reached, X blocks API requests until the next billing cycle.",
            enforcement: .hardStop, verification: .selfReported,
            consoleURL: url("https://console.x.com"),
            docURL: url("https://docs.x.com/x-api/getting-started/pricing"),
            steps: ["Open billing in the X Developer Console.",
                    "Set a spending limit: the most you accept per billing cycle."],
            caveat: "Pay-per-use plans are also capped at 3 million Post reads per monthly billing cycle."
        ),
        CapControl(
            id: "xapi.prepaid-credits", provider: .xapi, name: "Prepaid credits, auto-recharge off",
            summary: "Requests are blocked when the credits run out. With auto-recharge off, nothing tops them up.",
            enforcement: .hardStop, verification: .selfReported,
            consoleURL: url("https://console.x.com"),
            docURL: url("https://docs.x.com/x-api/getting-started/pricing"),
            steps: ["Open billing in the X Developer Console.",
                    "Leave auto-recharge off, or set a recharge amount and trigger you accept."],
            caveat: "The balance can go slightly negative before requests are blocked. Auto-recharge charges at "
                + "most once every 5 minutes."
        ),
        // Black Forest Labs. https://docs.bfl.ai/account_management/credits_billing
        CapControl(
            id: "bfl.prepaid-credits", provider: .bfl, name: "Prepaid credits, auto top-up off",
            summary: "With insufficient credits, BFL refuses requests (HTTP 402). With auto top-up off, nothing "
                + "recharges the balance.",
            enforcement: .hardStop, verification: .selfReported,
            consoleURL: url("https://dashboard.bfl.ai"),
            docURL: url("https://docs.bfl.ai/account_management/credits_billing"),
            steps: ["Open Credits in the BFL dashboard.",
                    "Leave Automatic top-up off, or set a threshold and target you accept."],
            caveat: "BFL's docs describe no spend limit you set: the credits are the cap."
        ),
        // DigitalOcean. https://docs.digitalocean.com/platform/billing/spend-alerts/
        CapControl(
            id: "digitalocean.spend-alert", provider: .digitalocean, name: "Spend alert",
            summary: "Emails when the month's spend crosses percentage thresholds of a budget you set, for the whole "
                + "team or chosen products.",
            enforcement: .alertOnly, verification: .selfReported,
            consoleURL: url("https://cloud.digitalocean.com/account/billing/spend-alerts"),
            docURL: url("https://docs.digitalocean.com/platform/billing/spend-alerts/"),
            steps: ["Open the Spend alerts tab on the Billing page.",
                    "Click Create alert, set a monthly budget and thresholds, and track Total spend."],
            caveat: "DigitalOcean says a spend alert budget \"is not a spending cap and does not limit how much you "
                + "can use\". Notifications arrive within an hour of crossing a threshold."
        ),
        CapControl(
            id: "digitalocean.inference-key-pause", provider: .digitalocean,
            name: "Pause Serverless Inference keys at their budget",
            summary: "A spend alert on model access keys can pause each key when its spend reaches 100% of its "
                + "budget, stopping Serverless Inference requests for that key.",
            enforcement: .partialStop, verification: .selfReported,
            consoleURL: url("https://cloud.digitalocean.com/account/billing/spend-alerts"),
            docURL: url("https://docs.digitalocean.com/platform/billing/spend-alerts/"),
            steps: ["Create a spend alert and choose Managed Access Keys (Serverless Inference).",
                    "Select the keys and turn on Pause Serverless Inference at threshold."],
            caveat: "In public preview. It covers only the keys you pick, up to 10 per alert, not Droplets or other "
                + "products."
        ),
        // Telnyx. https://developers.telnyx.com/api-reference/autorechargepreferences/list-auto-recharge-preferences
        // and the suspension terms at https://telnyx.com/terms-and-conditions-of-service
        CapControl(
            id: TelnyxProvider.autoRechargeCapID, provider: .telnyx, name: "Prepaid balance, auto recharge off",
            summary: "With auto recharge off, nothing tops up the balance, and Telnyx's terms let it suspend "
                + "services once the deposit balance goes negative.",
            enforcement: .partialStop, verification: .api,
            consoleURL: url("https://portal.telnyx.com"),
            docURL: url("https://developers.telnyx.com/api-reference/autorechargepreferences/"
                + "list-auto-recharge-preferences"),
            steps: ["Open billing in the Telnyx Mission Control Portal.",
                    "Turn auto recharge off, or set a threshold and recharge amount you accept."],
            caveat: "Telnyx \"may\" suspend services at a negative balance; it isn't a promised stop. Spend can also "
                + "run past zero up to your credit limit."
        ),
        // Luma AI. https://docs.agents.lumalabs.ai/agents/budgets/
        CapControl(
            id: "luma.credits", provider: .luma, name: "Prepaid credits and key spending caps",
            summary: "Luma refuses a generation with HTTP 402 when your account balance, or your API key's cap for "
                + "the billing period, runs out.",
            enforcement: .hardStop, verification: .selfReported,
            consoleURL: url("https://app.lumalabs.ai/settings/developer"),
            docURL: url("https://docs.agents.lumalabs.ai/agents/budgets/"),
            steps: ["Open Developer settings in Luma.",
                    "Keep only the credits you're willing to spend, and give your API keys a spending cap where "
                        + "Luma offers one."],
            caveat: "Luma's docs mention a per-key cap per billing period but don't show where to set it. Settled "
                + "spend can end slightly above a cap, because generations are admitted on estimates."
        ),
        // HeyGen. https://developers.heygen.com/user-profile and https://developers.heygen.com/reference/get-current-user
        CapControl(
            id: HeyGenProvider.spendingCapID, provider: .heygen, name: "Spending cap (usage-based billing)",
            summary: "Usage-based HeyGen accounts can carry a spending cap in dollars. Kill Cord reads it, and "
                + "what's been spent against it.",
            enforcement: .hardStop, verification: .api,
            consoleURL: url("https://platform.heygen.com"),
            docURL: url("https://developers.heygen.com/user-profile"),
            steps: ["Open billing on the HeyGen API platform.", "Set a spending cap you accept."],
            caveat: "HeyGen's API docs name the optional cap but don't say where it's set or exactly what stops at "
                + "it. Prepaid wallet accounts have no cap: the wallet is the limit."
        ),
        CapControl(
            id: HeyGenProvider.autoReloadCapID, provider: .heygen, name: "Prepaid wallet, auto reload off",
            summary: "A wallet with auto reload off can't spend past its balance: HeyGen answers 402 "
                + "insufficient_credit.",
            enforcement: .hardStop, verification: .api,
            consoleURL: url("https://platform.heygen.com"),
            docURL: url("https://developers.heygen.com/user-profile"),
            steps: ["Open billing on the HeyGen API platform.",
                    "Turn auto reload off, or set a threshold and amount you accept."],
            caveat: "Applies only to wallet billing."
        ),
        // Browser Use. https://docs.browser-use.com/cloud/guides/billing
        CapControl(
            id: "browseruse.key-monthly-cap", provider: .browseruse, name: "Monthly spending cap on each API key",
            summary: "When a key reaches its cap for the UTC calendar month, Browser Use refuses new runs and browsers "
                + "for it with HTTP 402.",
            enforcement: .partialStop, verification: .selfReported,
            consoleURL: url("https://cloud.browser-use.com/settings"),
            docURL: url("https://docs.browser-use.com/cloud/guides/billing"),
            steps: ["Open API key settings in Browser Use Cloud.", "Give each key your apps use a monthly USD cap."],
            caveat: "Browser Use calls it a soft limit: work already running can finish above the cap."
        ),
        CapControl(
            id: "browseruse.prepaid-credits", provider: .browseruse, name: "Prepaid credits, auto recharge off",
            summary: "A project spends its credits; with auto recharge off, nothing buys more.",
            enforcement: .hardStop, verification: .selfReported,
            consoleURL: url("https://cloud.browser-use.com/settings?tab=billing"),
            docURL: url("https://docs.browser-use.com/cloud/guides/billing"),
            steps: ["Open Settings › Billing with the project selected.",
                    "Leave auto recharge off, or set a threshold and recharge amount you accept."],
            caveat: "Turning auto recharge on below the threshold can charge right away."
        ),
        // Novita AI. https://docs.novita.ai/api-reference/basic-error-code and
        // https://docs.novita.ai/api-reference/budget-query-key-list
        CapControl(
            id: "novita.prepaid-balance", provider: .novita, name: "Prepaid balance",
            summary: "Novita refuses paid requests with an insufficient balance error once the available credit runs "
                + "out.",
            enforcement: .hardStop, verification: .selfReported,
            consoleURL: url("https://novita.ai/billing"),
            docURL: url("https://docs.novita.ai/api-reference/basic-error-code"),
            steps: ["Open Billing and Payments in Novita AI.",
                    "Top up only what you're willing to spend, then mark this done."],
            caveat: "A credit limit, if your account has one, lets spending run past your top-ups. Teams can also "
                + "give each member's API keys a one-time or recurring budget, which Kill Cord can't read without "
                + "the member's ID."
        ),
        // Baseten. https://docs.baseten.co/deployment/autoscaling/overview
        CapControl(
            id: "baseten.max-replicas", provider: .baseten, name: "Maximum replicas on each deployment",
            summary: "max_replica is the ceiling for a deployment's capacity: the autoscaler won't start more "
                + "replicas, which Baseten says \"limits capacity and cost\".",
            enforcement: .partialStop, verification: .selfReported,
            consoleURL: url("https://app.baseten.co"),
            docURL: url("https://docs.baseten.co/deployment/autoscaling/overview"),
            steps: ["Open each dedicated deployment's autoscaling settings.",
                    "Set max replicas to the most you're willing to pay for, and min replicas to 0 to scale to zero."],
            caveat: "It caps replicas, not dollars. Training, Model APIs and Loops aren't limited by it, and Baseten "
                + "documents no account-wide spend cap."
        ),
        // Vonage. https://developer.vonage.com/en/account/guides/payments and https://developer.vonage.com/en/api/account
        CapControl(
            id: VonageProvider.autoReloadCapID, provider: .vonage, name: "Prepaid balance, auto reload off",
            summary: "Vonage says that when the balance reaches zero \"you can no longer use our APIs and your virtual "
                + "numbers are cancelled\". With auto reload off, nothing tops it up.",
            enforcement: .hardStop, verification: .api,
            consoleURL: url("https://dashboard.nexmo.com/billing-and-payments"),
            docURL: url("https://developer.vonage.com/en/account/guides/payments"),
            steps: ["Open Billing & payments in the Vonage API Dashboard.",
                    "Set Auto reload to off, or choose a reload amount you accept."],
            caveat: "At zero your virtual numbers are cancelled too, so keep enough balance for the numbers you rent."
        )
    ]
}
