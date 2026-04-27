# BulkheadLM For Dummies

BulkheadLM is an easy front door to a very powerful AI system: a secure AI router, a multi-provider connector, and a powerful agent provider that can also link machines together and feed larger agent-swarm platforms.

This guide is for someone who is about 10 years old, knows almost nothing about computers, and just wants BulkheadLM to start and let them chat.

If a word looks scary, ignore it and follow the steps one by one.

## The shortest possible idea

You need 3 things:

1. A machine where BulkheadLM can run (any Linux, macOS, or FreeBSD).
2. One API key, or a local model.
3. One command.

Copy-paste this into a terminal and press ENTER:

```bash
curl -fsSL https://raw.githubusercontent.com/Louis-Ph/bulkhead-lm/main/install.sh | sh
```

If your machine only has wget:

```bash
wget -qO- https://raw.githubusercontent.com/Louis-Ph/bulkhead-lm/main/install.sh | sh
```

That single command does everything: installs git, clones BulkheadLM, installs
the build tools, and opens the starter. Press ENTER at every question to accept
the defaults.

Then BulkheadLM asks you simple questions and opens a chat.

## Pick your easiest path

| What you have | Easiest path |
| --- | --- |
| macOS MacBook | `curl -fsSL .../install.sh \| sh` in Terminal |
| Any Linux (Ubuntu, Debian, Fedora, Arch, Alpine ...) | `curl -fsSL .../install.sh \| sh` |
| Windows computer | Use WSL Ubuntu, then run the one-liner inside WSL |
| Chromebook / ChromeOS | Use the Linux Terminal if available, or SSH to a cloud machine |
| FreeBSD machine | `curl -fsSL .../install.sh \| sh` |
| Android phone | SSH to a cloud machine already running BulkheadLM |
| Tablet or iPad | SSH to a cloud machine already running BulkheadLM |

## Fastest free first success: OpenRouter

If you want the smartest beginner path with the fewest decisions, start with
OpenRouter.

Research snapshot for this OpenRouter section: 2026-04-09.

Why this is a great first try:

1. One key can unlock many different models later.
2. BulkheadLM already knows the route `openrouter-free`.
3. OpenRouter's free plan currently shows 25+ free models and 50 requests per day.
4. Later, the same key can also power `openrouter-auto` and `openrouter-gpt-5.2`.

Do this:

```bash
printf '%s\n' 'export OPEN_ROUTER_KEY="paste-your-key-here"' >> ~/.zshrc.secrets
curl -fsSL https://raw.githubusercontent.com/Louis-Ph/bulkhead-lm/main/install.sh | sh
```

On Linux, use `~/.bashrc.secrets` instead of `~/.zshrc.secrets`.

Then:

1. If the starter asks, build the starter config.
2. Choose the model route `openrouter-free`.
3. Start chatting.

Very important:
free limits and free model choices can change. Check the official OpenRouter
pages before you depend on them:

- [OpenRouter Quickstart](https://openrouter.ai/docs/quickstart)
- [OpenRouter Pricing](https://openrouter.ai/pricing)
- [OpenRouter Free Models Router](https://openrouter.ai/docs/guides/routing/routers/free-models-router)

## Before you start: how to get a key cheaply or for free

Offers change often. Always check the official page, not random blogs, Discord messages, or videos.

Research snapshot for this section: 2026-04-04.

Very important reserve:

1. This is not legal advice.
2. I cannot promise that the legal risk is zero.
3. The low-risk path is simple:
   use only your own account, use only official provider offers, read the provider's terms, and stop if the offer does not clearly apply to you.
4. Do not try to fake your age, fake student status, reset trials with extra accounts, buy keys from strangers, or share keys between unrelated people.

The safest easy choices are:

1. OpenRouter free plan and free router.
   OpenRouter officially documents a free models router called `openrouter/free`.
   On the official pricing page checked on 2026-04-09, OpenRouter also shows a Free plan with 25+ free models and 50 requests per day.
   This is a very attractive first path for BulkheadLM because one OpenRouter key can later unlock more routes without changing provider setup.
   Official links:
   [OpenRouter pricing](https://openrouter.ai/pricing)
   [OpenRouter free models router](https://openrouter.ai/docs/guides/routing/routers/free-models-router)
   [OpenRouter quickstart](https://openrouter.ai/docs/quickstart)

2. Google Gemini API.
   Google officially has a pricing page with free tier entries for some Gemini API models, but not for every model.
   So you must check the exact model and the exact page on the day you sign up.
   Official link: [Google Gemini API pricing](https://ai.google.dev/pricing)

3. Mistral API experiment tier.
   Mistral officially says it has an Experiment plan for free API use.
   On the official help page checked on 2026-04-04, Mistral says this needs a verified phone number, no credit card, and that requests under the Experiment plan may be used to train Mistral's models.
   Official links:
   [Mistral pricing](https://mistral.ai/pricing)
   [Mistral free experiment plan](https://help.mistral.ai/en/articles/455206-how-can-i-try-the-api-for-free-with-the-experiment-plan)
   [Mistral terms](https://legal.mistral.ai/terms/eu-consumers-terms-of-service)

4. Promotional credits from the provider itself.
   Some providers sometimes give credits to new accounts or special programs. These offers can appear and disappear.
   Treat them as temporary offers, not as a permanent right.
   Official pages to check:
   [OpenAI pricing](https://openai.com/api/pricing/)
   [OpenAI service credit terms](https://openai.com/policies/service-credit-terms/)
   [Anthropic pricing](https://www.anthropic.com/pricing#api)
   [Anthropic API for individuals](https://support.claude.com/en/articles/8987200-can-i-use-the-claude-api-for-individual-use)

   Extra reserve:
   OpenAI says service credits are governed by credit terms and are non-transferable.
   Anthropic says individuals may use the API, but API use is still subject to its commercial terms, and its help pages describe prepaid usage credits.

5. Student programs, only if you are old enough and really are a student.
   GitHub says its Student Developer Pack is only for verified students aged 13 or older.
   GitHub also says offers may change, may not stack, and may not be redeemed multiple times.
   For the target reader of this guide, this usually means: do not count on this path unless a parent, teacher, or school helps you and you really qualify.
   Official links:
   [GitHub Student Developer Pack eligibility](https://education.github.com/pack/join)
   [GitHub Student Developer Pack](https://education.github.com/pack)
   [GitHub Student Pack terms](https://docs.github.com/en/education/about-github-education/github-education-for-students/github-terms-and-conditions-for-the-student-developer-pack)

6. Local models with Ollama.
   This is not a promotional cloud quota. It means the model runs on your own machine, so there is no API bill.
   This repository also includes a dedicated BulkheadLM local swarm example at `config/example.ollama_swarm.gateway.json` and a ready smoke test at `./scripts/smoke_ollama.sh`.
   If you want the direct no-menu path, use `./run-ollama.sh`.
   That path is meant for explicit local-only use because it relaxes the default egress policy so BulkheadLM can talk to `127.0.0.1:11434`.
   Official links:
   [Ollama download](https://ollama.com/download)
   [Ollama OpenAI compatibility](https://docs.ollama.com/api/openai-compatibility)

7. Cheap direct API providers: DeepSeek, Groq, Cerebras, Perplexity, Together AI, and Cohere.
   BulkheadLM now supports all six as direct provider kinds.
   Several of these providers offer free tiers, generous trial credits, or very low per-token prices.
   As always, check the official pricing page on the day you sign up.
   Key variables: `DEEPSEEK_API_KEY`, `GROQ_API_KEY`, `PERPLEXITY_API_KEY`, `TOGETHER_API_KEY`, `CEREBRAS_API_KEY`, `COHERE_API_KEY`.
   Official links:
   [DeepSeek Platform](https://platform.deepseek.com/)
   [Groq Cloud](https://console.groq.com/)
   [Perplexity AI API](https://www.perplexity.ai/settings/api)
   [Together AI](https://api.together.ai/)
   [Cerebras Cloud](https://cloud.cerebras.ai/)
   [Cohere Platform](https://cohere.com/)

## Very important safety rules

1. Never use an API key from a stranger.
2. Never post your API key in GitHub, Discord, email, or screenshots.
3. Put your key in an environment file, not inside a public message.
4. If you are a child, ask a parent or teacher before entering a paid card anywhere.

## The easiest cloud-key path

If you want the simplest first success, try this order:

1. Try OpenRouter first, especially `openrouter/free`.
2. Then try a Google Gemini API key.
3. Then try the official Mistral Experiment plan if it is available to you.
4. If you already have an OpenAI or Anthropic key on your own account, use that.
5. If you have no cloud key and your computer is strong enough, ask an adult to help with Ollama.

## If you want a cloud machine fast

Good news:
you do not need a giant server.

For BulkheadLM, a small Ubuntu machine is often enough if your model is in the cloud and your API key talks to the model provider.

Research snapshot for this cloud-offers section: 2026-04-04.

The easy idea is:

1. Start one small cloud machine.
2. Connect with SSH.
3. Clone BulkheadLM.
4. Put one API key in your secret file.
5. Run `./run.sh`.

## Cloud shortcut: the fun, easy choices

These are not promises.
They are easy places to look first, on the official pages checked on 2026-04-04.

1. Oracle Cloud Free Tier.
   This is one of the most tempting paths if you want a small remote Linux machine without paying right away.
   Oracle says its Free Tier starts with a trial credit and also includes Always Free services.
   This is often a strong beginner path for "I want my own small Ubuntu box in the cloud."
   Official link: [Oracle Cloud Free Tier](https://www.oracle.com/cloud/free/)

2. Azure free account.
   This is a good path if you want lots of tutorials and a big friendly portal.
   Microsoft says its Azure free account includes a $200 credit for 30 days, free monthly amounts for some services, and many always-free services.
   Microsoft also says signup uses phone and card verification, even though the free account itself should not charge you unless you move to pay-as-you-go.
   Official link: [Azure free account](https://azure.microsoft.com/free/)

3. AWS Free Tier.
   This is a good path if you want the biggest cloud ecosystem and lots of examples.
   AWS says new customers can get up to $200 in credits, with a free plan for up to 6 months and 30+ always-free services.
   This is a strong path if you want a famous cloud and do not mind a bigger control panel.
   Official link: [AWS Free Tier](https://aws.amazon.com/free/)

4. Alibaba Cloud start-for-free pages.
   This is worth checking if you want another big cloud, especially if Alibaba Cloud is a good regional fit for you.
   The important thing to understand is that Alibaba Cloud free access is often product-by-product, not one giant universal promise.
   Some free-trial pages also require identity checks, and some services require a payment method to stay eligible.
   Official links:
   [Alibaba Cloud start for free](https://www.alibabacloud.com/campaign/free-trial)
   [Alibaba Cloud OSS free quota example](https://www.alibabacloud.com/help/en/oss/free-quota-for-new-users)

5. OpenAI API.
   OpenAI is not where you rent the Ubuntu machine.
   OpenAI is where you buy the model brain.
   So the easy combo is:
   one small cloud machine from AWS, Azure, Oracle, or Alibaba Cloud, plus one OpenAI API key.
   OpenAI also says promo service credits are non-transferable and may expire, so use only your own account and do not treat credits like money.
   Official links:
   [OpenAI API pricing](https://openai.com/api/pricing/)
   [OpenAI service credit terms](https://openai.com/policies/service-credit-terms/)

## Very important reserve for cloud promotions

Cloud offers are powerful, but they are not toys.

1. This is not legal advice.
2. I cannot promise that a free offer will still exist when you read this.
3. I cannot promise that your country, age, card, or identity will be accepted.
4. Many cloud offers are only for new customers.
5. Many cloud offers require phone verification, card verification, identity verification, or region checks.
6. Never make extra accounts to reset a free trial.
7. Never use someone else's card or identity.
8. If you are a child, ask an adult before typing card details anywhere.
9. Before you click "Create", check the official pricing page one more time and look for what happens after the trial ends.

## The easiest cloud recipe for BulkheadLM

If you want one simple cloud plan that is easy to understand, do this:

1. Choose one Linux virtual machine from Oracle Cloud, Azure, AWS, or Alibaba Cloud (Ubuntu, Debian, Fedora, anything works).
2. Choose one model API key, with OpenRouter as the easiest first try.
3. Connect to the machine with SSH.
4. Run:

```bash
printf '%s\n' 'export OPEN_ROUTER_KEY="paste-your-key-here"' >> ~/.bashrc.secrets
curl -fsSL https://raw.githubusercontent.com/Louis-Ph/bulkhead-lm/main/install.sh | sh
```

5. Choose `openrouter-free` or another model marked `[ready]`.
6. Start chatting.

If your cloud machine already has BulkheadLM packaged and installed, the path can be even shorter:

```bash
bulkhead-lm-starter
```

## The easiest cloud combos

If you want a fast answer instead of a big comparison, pick one of these:

1. Cheapest feeling:
   Oracle Cloud Free Tier plus Gemini or Mistral.
2. Biggest beginner ecosystem:
   Azure or AWS plus Gemini or OpenAI.
3. "I want the model only, not the server":
   keep BulkheadLM on your own MacBook and only buy an API key.
4. "I want a machine in the cloud and a premium model":
   small Ubuntu VM plus OpenAI or Anthropic key.

## If your device cannot install anything, do this instead

This is the rescue plan.

It is also a surprisingly cool plan.

You can keep using:

1. a locked school Chromebook
2. a work tablet
3. a phone with little storage
4. a shared family device

and still get your own BulkheadLM machine.

The trick is simple:

1. rent or claim one small cloud Ubuntu machine with a promotional offer
2. keep BulkheadLM and your API keys on that cloud machine
3. reach it from your small device with SSH or a browser-based cloud console

That way, your little device becomes a safe remote control, not the place where all the secrets live.

Research snapshot for this no-install cloud-access section: 2026-04-04.

## The most attractive no-install cloud pattern

If you want the easiest idea to remember, it is this:

1. Cloud machine:
   one small Ubuntu VM on Oracle Cloud, AWS, Azure, or Alibaba Cloud
2. Model:
   one API key from Gemini, Mistral, OpenAI, Anthropic, OpenRouter, or another BulkheadLM provider
3. Access:
   SSH app, Chromebook Terminal, or a cloud provider browser console
4. Daily use:
   run `bulkhead-lm-starter` on the cloud machine

The attractive part is:

1. Your phone, tablet, or Chromebook stays light.
2. Your API keys stay in one place.
3. You can reconnect from almost anywhere.
4. If one device breaks, your BulkheadLM machine still exists.
5. You do not need to reinstall everything every time.

## The easiest secure access method

The safest beginner-friendly pattern is usually:

1. create the cloud machine once
2. install BulkheadLM there once
3. keep the API keys only there
4. connect with SSH
5. launch:

```bash
bulkhead-lm-starter
```

If you connect from another machine, the very short command is:

```bash
ssh -t your-user@your-cloud-machine 'bulkhead-lm-starter'
```

This is much better than copying API keys onto every phone, tablet, or borrowed computer.

## If you cannot install even an SSH app

This can still work.

On some cloud providers, the browser itself can help you connect.

Examples checked on 2026-04-04:

1. AWS documents Session Manager, which can open an interactive browser shell on an EC2 instance.
2. AWS also documents EC2 Instance Connect for secure SSH access.
3. Alibaba Cloud documents Workbench, a browser-based remote connection tool for Linux instances.

That means a browser alone may be enough to open your cloud machine, bootstrap BulkheadLM, and later keep using it.

Official links:
- [AWS Session Manager for EC2](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/connect-with-systems-manager-session-manager.html)
- [AWS EC2 Instance Connect](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-instance-connect-methods.html)
- [Alibaba Cloud Workbench](https://www.alibabacloud.com/help/doc-detail/163819.html)

## The easy secure checklist

If you use the cloud rescue plan, try to do these things:

1. Prefer SSH keys over reusable passwords when the provider offers that path.
2. Do not save API keys on the small device if you can avoid it.
3. If the cloud provider lets you limit SSH to your own IP, do it.
4. Do not open more ports than you need.
5. Keep only one small machine at first.
6. If your device is shared, log out after use.
7. If your device is lost, revoke access from the cloud machine side.

## One very easy cloud story

Imagine this:

1. You have only a Chromebook or tablet.
2. You claim a cloud promotional Ubuntu machine.
3. You open its browser console or connect with SSH.
4. You clone BulkheadLM there.
5. You put your API key in the secret file there.
6. You run `./run.sh` once.
7. After that, your daily command is only:

```bash
bulkhead-lm-starter
```

That is a very practical way to get "my own AI machine" without turning your little device into a server.

## Why ChromeOS, Android, and tablets are actually great for this

This is one of the nicest things about BulkheadLM:
your small device does not need to be the big machine.

It can become a tiny control room.

That means:

1. Your Chromebook, phone, or tablet stays simple and light.
2. Your API keys can stay on the remote machine instead of living on the mobile device.
3. You can chat from the sofa, school desk, train, hotel, or garden.
4. You do not need to rebuild the whole project on every small device.
5. If the remote machine is stronger, the experience is usually smoother.

Research snapshot for this mobile-and-ChromeOS section: 2026-04-04.

## ChromeOS: the easy path that feels smart

A Chromebook can be a very nice BulkheadLM control machine.

Google officially says many Chromebooks can turn on a Linux development environment, and that this gives you a Debian environment with a Terminal app.

That means two easy paths:

1. If Linux is available on your Chromebook:
   use the built-in Terminal and connect to your BulkheadLM machine with SSH.
2. If Linux is not available or is blocked by school or work policy:
   use another machine for BulkheadLM and keep the Chromebook as the safe front door.

Very simple ChromeOS path:

1. Open Settings.
2. Go to `About ChromeOS`, then `Developers`.
3. Turn on `Linux development environment` if your device allows it.
4. Open the Terminal app.
5. Run:

```bash
ssh -t your-user@your-machine 'bulkhead-lm-starter'
```

Why this is attractive:

1. The Chromebook stays clean.
2. The heavy work stays on the remote machine.
3. Your API keys do not need to sit on the Chromebook.
4. This is usually much easier than trying to turn a Chromebook into a full server.

Official links:
- [Set up Linux on your Chromebook](https://support.google.com/chromebook/answer/9145439?hl=en)
- [Back up and restore Linux files on Chromebook](https://support.google.com/chromebook/answer/9592813?hl=en)

## macOS: easiest local start

1. Open the Terminal app.
2. Put your key in a secret file:

```bash
printf '%s\n' 'export GOOGLE_API_KEY="paste-your-key-here"' >> ~/.zshrc.secret
```

You can replace `GOOGLE_API_KEY` with `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, `MISTRAL_API_KEY`, `OPEN_ROUTER_KEY`, `DEEPSEEK_API_KEY`, `GROQ_API_KEY`, `PERPLEXITY_API_KEY`, `TOGETHER_API_KEY`, `CEREBRAS_API_KEY`, or `COHERE_API_KEY`.

3. Run the one-liner and press ENTER at every question:

```bash
curl -fsSL https://raw.githubusercontent.com/Louis-Ph/bulkhead-lm/main/install.sh | sh
```

4. Choose a model marked `[ready]` and start chatting.

## Linux (Ubuntu, Debian, Fedora, Arch, Alpine ...): easiest local start

1. Open a terminal.
2. Put your key in a secret file:

```bash
printf '%s\n' 'export GOOGLE_API_KEY="paste-your-key-here"' >> ~/.bashrc.secret
```

3. Run the one-liner and press ENTER at every question:

```bash
curl -fsSL https://raw.githubusercontent.com/Louis-Ph/bulkhead-lm/main/install.sh | sh
```

The installer detects your package manager (apt, dnf, pacman, apk, zypper) and installs everything automatically.

## Windows with WSL: easiest local start

1. Open PowerShell as Administrator.
2. Install WSL Ubuntu:

```powershell
wsl --install -d Ubuntu
```

3. Restart if Windows asks, then open the Ubuntu app.
4. Inside WSL, run:

```bash
printf '%s\n' 'export GOOGLE_API_KEY="paste-your-key-here"' >> ~/.bashrc.secret
curl -fsSL https://raw.githubusercontent.com/Louis-Ph/bulkhead-lm/main/install.sh | sh
```

## FreeBSD: easiest local start

1. Open a shell.
2. Put your key in a secret file:

```bash
printf '%s\n' 'export GOOGLE_API_KEY="paste-your-key-here"' >> ~/.profile.secret
```

3. Run the one-liner:

```bash
curl -fsSL https://raw.githubusercontent.com/Louis-Ph/bulkhead-lm/main/install.sh | sh
```

## Android: easiest path

The easiest Android path is not a full local install.

Do this instead:

1. Have another machine already running BulkheadLM:
   macOS, Ubuntu, WSL Ubuntu, FreeBSD, or one small cloud Ubuntu VM.
2. Install any SSH app on Android.
3. Connect to the other machine.
4. Run:

```bash
ssh -t your-user@your-machine 'cd /path/to/bulkhead-lm && ./run.sh'
```

If BulkheadLM is already installed as a packaged app on the remote machine, this is even easier:

```bash
ssh -t your-user@your-machine 'bulkhead-lm-starter'
```

Advanced note:
Android local install may be possible with advanced tools, but that is not the simple path for this guide.

Why Android is attractive:

1. Your phone becomes a pocket terminal for your own AI machine.
2. The expensive or private things stay on the remote machine.
3. If you lose the phone, you can cut access on the server side.
4. You can keep chatting almost anywhere.

Easy Android safety rules:

1. Keep your phone updated.
2. Use a screen lock.
3. If your device supports theft protection, turn it on.
4. Prefer SSH key login if your SSH app offers it.
5. Only connect to machines you own or trust.

Official links:
- [Check & update your Android version](https://support.google.com/pixelphone/answer/7680439?hl=en)
- [Protect your personal data against theft](https://support.google.com/android/answer/15146908?hl=en)

## Tablet or iPad: easiest path

Same idea as Android.

1. Use any SSH app.
2. Connect to a Mac, Ubuntu, WSL Ubuntu, FreeBSD, or small cloud Ubuntu machine that already has BulkheadLM.
3. Run:

```bash
ssh -t your-user@your-machine 'cd /path/to/bulkhead-lm && ./run.sh'
```

Or, if the machine has a packaged install:

```bash
ssh -t your-user@your-machine 'bulkhead-lm-starter'
```

Why tablets are attractive:

1. Big screen, simple touch use.
2. Great with a tiny Bluetooth keyboard.
3. You keep the real server and the real API keys somewhere safer.
4. It feels much easier than turning the tablet itself into a server.

Easy iPad and tablet safety rules:

1. Turn on a passcode.
2. Turn on Face ID or Touch ID if your device supports it.
3. Keep the tablet updated.
4. Use an SSH app from the official app store, not a random download.
5. If the app offers key-based SSH login, prefer that over a reused weak password.

Official links:
- [Use a passcode with your iPhone, iPad, or iPod touch](https://support.apple.com/en-us/119586)
- [How to download iPadOS 18](https://support.apple.com/en-afri/104986)

## The safest easy remote-access pattern

If you want the best mix of easy and safe, do this:

1. Install BulkheadLM on one real machine:
   Mac, Ubuntu, WSL Ubuntu, FreeBSD, or one small cloud Ubuntu VM.
2. Put the API keys only on that machine.
3. Access that machine from Chromebook, Android, or tablet with SSH.
4. If possible, use SSH keys instead of a reusable password.
5. Launch:

```bash
ssh -t your-user@your-machine 'bulkhead-lm-starter'
```

This is attractive because:

1. The small device feels magical and easy.
2. The secret keys stay in one place.
3. If the mobile device changes, your BulkheadLM machine does not need to be rebuilt.
4. You can revoke access in one place if needed.

## What happens when `./run.sh` starts

The starter tries to help you instead of throwing confusing build errors.

It can:

1. Reuse your existing keys from secret files.
2. Show which models are ready.
   `/models` now also shows the provider family, the upstream model id, and the
   version or mode when BulkheadLM knows them, so short aliases are less opaque.
3. Show the bigger model list that each provider account exposes with
   `/discover`.
4. Refresh that provider model list with `/refresh-models` when you want to ask
   the provider again instead of using the cache.
5. Let you choose a model.
6. Open a simple chat.
7. Let you attach a local text file with `/file PATH`.
8. Let you explore folders with `/explore`, open a text file with `/open`, and run one safe local command with `/run`.
9. Help configure BulkheadLM with `/admin`.
10. Help build a distributable package with `/package`.

Important:
`/models` means "models BulkheadLM can route through this config."
`/discover` means "models your provider account says exist right now."
Discovery helps you inspect providers, but it does not secretly change your
routes.

## The "one magic model" trick: pools

If you have several models and you do not want to pick one each time, you can
ask BulkheadLM to make a small group called a "pool" and give it one easy
name. Then you just use that one name and BulkheadLM picks the best one for
you.

The simplest way is the global pool: it groups every model your config knows
about into one model called `global`. Turn it on once:

```text
/pool global on
```

After that, you can chat as if there were only one model:

```text
/swap global
```

BulkheadLM will:

1. send your message to the model that has been answering fastest lately,
2. fall back to the next one if it fails,
3. stop using a model that has used up its little daily budget.

If you want a smaller, focused group instead of the full global pool, you can
make your own:

```text
/pool create pool-cheap
/pool add pool-cheap groq-llama-3.1-8b 50000
/pool add pool-cheap cerebras-llama-3.1-8b 50000
/pool show pool-cheap
```

`50000` is the daily token budget for each member. Once empty for the day,
that member is skipped automatically until tomorrow.

You can always inspect what is going on:

```text
/pool list
```

Why this is nice:

1. You only have to remember one name like `global` or `pool-cheap`.
2. Each member can have a small daily budget so you do not spend a lot.
3. If one provider is slow or down, the next one takes over without you doing
   anything.
4. If you add a new model later, the global pool picks it up automatically.

## "A chat group where each member is a different AI"

If you have several models or several pools, you can ask BulkheadLM to make
each of them appear as a different person in a Telegram group. You and your
friends can then chat with all of them at once like a real group.

What you need:

1. A Telegram account.
2. One BotFather token per persona. BotFather is free.
3. One line per persona in your secrets file.

Steps:

1. Open Telegram, message `@BotFather`, send `/newbot`. Pick a name like
   "Marie" and a username like "marie_helper_bot". Copy the token. Do the
   same for `@BotFather` again to make a second bot called "Paul".
2. Add the tokens to your secrets:

```bash
cat >> ~/.bashrc.secrets << 'EOF'
export TELEGRAM_TOKEN_MARIE="paste-marie-token"
export TELEGRAM_TOKEN_PAUL="paste-paul-token"
EOF
```

3. In your `config/local_only/starter.gateway.json`, replace the
   `telegram` section with this list of two personas:

```json
{
  "user_connectors": {
    "telegram": [
      {
        "persona_name": "marie",
        "webhook_path": "/connectors/telegram/marie",
        "bot_token_env": "TELEGRAM_TOKEN_MARIE",
        "authorization_env": "BULKHEAD_LM_API_KEY",
        "route_model": "claude-opus",
        "system_prompt": "Tu es Marie, l'experte. Sois directe.",
        "room_memory_mode": "shared"
      },
      {
        "persona_name": "paul",
        "webhook_path": "/connectors/telegram/paul",
        "bot_token_env": "TELEGRAM_TOKEN_PAUL",
        "authorization_env": "BULKHEAD_LM_API_KEY",
        "route_model": "pool-cheap",
        "system_prompt": "Tu es Paul, le relecteur. Tu simplifies les phrases.",
        "room_memory_mode": "shared"
      }
    ]
  }
}
```

4. Start BulkheadLM. Inside the starter, type `/persona list`. You should
   see both `marie` and `paul`.
5. Tell Telegram where each bot lives (replace `your-public-host` with your
   server):

```bash
curl -sS "https://api.telegram.org/bot${TELEGRAM_TOKEN_MARIE}/setWebhook" \
  -d '{"url": "https://your-public-host/connectors/telegram/marie"}'

curl -sS "https://api.telegram.org/bot${TELEGRAM_TOKEN_PAUL}/setWebhook" \
  -d '{"url": "https://your-public-host/connectors/telegram/paul"}'
```

6. Open Telegram, create a group, invite Marie and Paul (and your friends if
   you want).
7. Talk in the group. When you mention `@marie_helper_bot`, Marie answers.
   When you mention `@paul_helper_bot`, Paul answers — and Paul has read
   Marie's reply, so he can refer to it.

Why this is fun:

1. Each persona has its own Telegram name and avatar, like a real group.
2. They share memory, so they can answer each other naturally.
3. One persona can be expensive (Claude Opus), another can be cheap (a pool
   of small models). Your wallet stays happy.
4. You can keep adding personas with more BotFather tokens.

If you don't want them to read each other (parallel bots in one group), set
`"room_memory_mode": "isolated"` on each entry instead of `"shared"`.

## Your first chat

After the starter opens, type something like:

```text
hello
```

Then try:

```text
what can you do for me?
```

## Very useful commands inside the starter

```text
/help
/tools
/models
/providers
/discover
/refresh-models
/pool list
/pool global on
/persona list
/env
/file README.md
/files
/clearfiles
/explore src
/open README.md
/run /bin/ls -la
/admin enable only safe local file access in this repository
/package
/quit
```

## Chat from Telegram, WhatsApp, or other apps

BulkheadLM can connect to your favorite chat apps so you talk to your AI
from your phone, just like texting a friend. No JSON editing needed.

### Telegram (the easiest one)

1. Open Telegram. Search for `@BotFather`. Send `/newbot`. Follow the steps.
   BotFather gives you a token that looks like `123456:ABC-DEF...`.
2. Save that token:

```bash
printf 'export TELEGRAM_BOT_TOKEN="paste-your-token-here"\n' >> ~/.bashrc.secrets
```

3. Run BulkheadLM:

```bash
curl -fsSL https://raw.githubusercontent.com/Louis-Ph/bulkhead-lm/main/install.sh | sh
```

4. In a separate terminal, start the server:

```bash
cd ~/bulkhead-lm
./scripts/with_local_toolchain.sh dune exec bulkhead-lm -- --config config/local_only/starter.gateway.json
```

5. Tell Telegram where your server is (replace `your-public-host`):

```bash
curl -sS "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/setWebhook" \
  -H 'content-type: application/json' \
  -d '{"url": "https://your-public-host/connectors/telegram/webhook", "allowed_updates": ["message"]}'
```

6. Open Telegram, find your bot, and send a message. Your AI answers.

### WhatsApp

1. Go to [developers.facebook.com](https://developers.facebook.com), create an
   app, turn on WhatsApp. Copy the temporary access token.
2. Save the tokens:

```bash
cat >> ~/.bashrc.secrets << 'EOF'
export WHATSAPP_ACCESS_TOKEN="paste-access-token"
export WHATSAPP_VERIFY_TOKEN="pick-any-random-string"
EOF
```

3. Run BulkheadLM. Start the server.
4. In the Meta dashboard, set the webhook URL to
   `https://your-public-host/connectors/whatsapp/webhook` and the verify token
   to the same random string you picked. Subscribe to `messages`.
5. Send a WhatsApp message to your test number.

### Other supported apps

The same pattern works for all these apps. Set the token, run BulkheadLM,
point the webhook.

| App | What to set | Where to get it |
| --- | --- | --- |
| Telegram | `TELEGRAM_BOT_TOKEN` | [@BotFather](https://t.me/BotFather) |
| WhatsApp | `WHATSAPP_ACCESS_TOKEN` + `WHATSAPP_VERIFY_TOKEN` | [Meta for Developers](https://developers.facebook.com) |
| Messenger | `MESSENGER_ACCESS_TOKEN` + `MESSENGER_VERIFY_TOKEN` | [Meta for Developers](https://developers.facebook.com) |
| Instagram | `INSTAGRAM_ACCESS_TOKEN` + `INSTAGRAM_VERIFY_TOKEN` | [Meta for Developers](https://developers.facebook.com) |
| LINE | `LINE_ACCESS_TOKEN` + `LINE_CHANNEL_SECRET` | [LINE Developers](https://developers.line.biz) |
| Viber | `VIBER_AUTH_TOKEN` | [Viber Partners](https://partners.viber.com) |
| WeChat | `WECHAT_SIGNATURE_TOKEN` | WeChat Official Accounts Platform |
| Discord | `DISCORD_PUBLIC_KEY` | [Discord Developers](https://discord.com/developers/applications) |

For every app: add the token to `~/.bashrc.secrets`, run BulkheadLM, and
point the platform's webhook setting to
`https://your-public-host/connectors/<app-name>/webhook`.

BulkheadLM does the rest: it picks your best model, wires up authentication,
and remembers each conversation separately.

## If no model is ready

That usually means your key is missing or empty.

Check with:

```text
/env
```

If you do not see your key variable, close the starter, add the line to your secret file, open a new terminal, and run:

```bash
./run.sh
```

## If you want the cheapest path

Try these in order:

1. OpenRouter free plan and `openrouter/free`.
2. Groq free API tier for fast inference on open models.
3. Cerebras free API tier.
4. Gemini API free tier if available where you live.
5. Mistral free experiment tier if it is available for your account.
6. DeepSeek API for very low-cost inference on DeepSeek models.
7. Official provider promotional credits if they exist on the day you sign up.
8. Local Ollama on your own machine.

As always, free tiers and pricing can change. Check the official provider page on the day you sign up.

## Legal safety in one minute

If you want the lowest practical legal risk for this guide, do this:

1. Use only official provider websites.
2. Use only your own account.
3. Do not lie about your age, school, country, or identity.
4. Do not create extra accounts to reset a free trial.
5. Do not buy, sell, or trade API keys.
6. If a page says a plan is for testing, prototyping, or students only, believe it and stay inside that limit.

That does not make legal risk literally zero, but it makes your path much safer.

## If you want the simplest path with a tablet or phone

Do not try to build everything locally first.

Use a remote machine:

1. A MacBook, Ubuntu box, WSL Ubuntu PC, or FreeBSD machine runs BulkheadLM.
2. Your tablet or phone opens SSH to it.
3. You chat from there.

## If you get stuck

Start with these 3 questions:

1. What machine am I using?
2. Do I already have one API key?
3. Did I really run `./run.sh` inside the `bulkhead-lm` folder?

If the answer to number 2 is no, get a key first.

## Good links

- Main project guide: [README.md](README.md)
- SSH remote usage: [docs/SSH_REMOTE.md](docs/SSH_REMOTE.md)
- Peer machine setup: [docs/PEER_MESH.md](docs/PEER_MESH.md)
- Beginner launcher command: `./run.sh`

## Final truth

If you want one simple first success:

1. Open a terminal on any machine (Mac, Linux, WSL, or FreeBSD).
2. Put one API key in a secret file.
3. Run `curl -fsSL https://raw.githubusercontent.com/Louis-Ph/bulkhead-lm/main/install.sh | sh`
4. Press ENTER at every question.
5. Choose a ready model and start chatting.
