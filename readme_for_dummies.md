# BulkheadLM For Dummies

This guide is for someone who is about 10 years old, knows almost nothing about computers, and just wants BulkheadLM to start and let them chat.

If a word looks scary, ignore it and follow the steps one by one.

## The shortest possible idea

You need 3 things:

1. A machine where BulkheadLM can run.
2. One API key, or a local model.
3. One command: `./run.sh`

Then BulkheadLM asks you simple questions and opens a chat.

## Pick your easiest path

| What you have | Easiest path |
| --- | --- |
| macOS MacBook | Local install on the Mac |
| Ubuntu computer | Local install on Ubuntu |
| Windows computer | Use WSL Ubuntu, then follow the Ubuntu steps inside WSL |
| Chromebook / ChromeOS | Best path: use the Linux Terminal if available, or use SSH to a small cloud machine already running BulkheadLM |
| FreeBSD machine | Local install on FreeBSD |
| Android phone | Best path: connect by SSH to another machine, often a small cloud Ubuntu VM already running BulkheadLM |
| Tablet or iPad | Best path: connect by SSH to another machine, often a small cloud Ubuntu VM already running BulkheadLM |

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

1. Google Gemini API.
   Google officially has a pricing page with free tier entries for some Gemini API models, but not for every model.
   So you must check the exact model and the exact page on the day you sign up.
   Official link: [Google Gemini API pricing](https://ai.google.dev/pricing)

2. Mistral API experiment tier.
   Mistral officially says it has an Experiment plan for free API use.
   On the official help page checked on 2026-04-04, Mistral says this needs a verified phone number, no credit card, and that requests under the Experiment plan may be used to train Mistral's models.
   Official links:
   [Mistral pricing](https://mistral.ai/pricing)
   [Mistral free experiment plan](https://help.mistral.ai/en/articles/455206-how-can-i-try-the-api-for-free-with-the-experiment-plan)
   [Mistral terms](https://legal.mistral.ai/terms/eu-consumers-terms-of-service)

3. Promotional credits from the provider itself.
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

4. Student programs, only if you are old enough and really are a student.
   GitHub says its Student Developer Pack is only for verified students aged 13 or older.
   GitHub also says offers may change, may not stack, and may not be redeemed multiple times.
   For the target reader of this guide, this usually means: do not count on this path unless a parent, teacher, or school helps you and you really qualify.
   Official links:
   [GitHub Student Developer Pack eligibility](https://education.github.com/pack/join)
   [GitHub Student Developer Pack](https://education.github.com/pack)
   [GitHub Student Pack terms](https://docs.github.com/en/education/about-github-education/github-education-for-students/github-terms-and-conditions-for-the-student-developer-pack)

5. Local models with Ollama.
   This is not a promotional cloud quota. It means the model runs on your own machine, so there is no API bill.
   Official links:
   [Ollama download](https://ollama.com/download)
   [Ollama OpenAI compatibility](https://docs.ollama.com/api/openai-compatibility)

## Very important safety rules

1. Never use an API key from a stranger.
2. Never post your API key in GitHub, Discord, email, or screenshots.
3. Put your key in an environment file, not inside a public message.
4. If you are a child, ask a parent or teacher before entering a paid card anywhere.

## The easiest cloud-key path

If you want the simplest first success, try this order:

1. Try a Google Gemini API key first.
2. Then try the official Mistral Experiment plan if it is available to you.
3. If you already have an OpenAI or Anthropic key on your own account, use that.
4. If you have no cloud key and your computer is strong enough, ask an adult to help with Ollama.

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

1. Choose one Ubuntu virtual machine from Oracle Cloud, Azure, AWS, or Alibaba Cloud.
2. Choose one model API key from Gemini, Mistral, OpenAI, Anthropic, OpenRouter, or another provider already supported by BulkheadLM.
3. Connect to the machine with SSH.
4. Run:

```bash
sudo apt update
sudo apt install -y git
git clone https://github.com/Louis-Ph/bulkhead-lm.git
cd bulkhead-lm
printf '%s\n' 'export GOOGLE_API_KEY="paste-your-key-here"' >> ~/.bashrc.secret
./run.sh
```

5. Choose a model marked `[ready]`.
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
2. If `git` is missing, run:

```bash
xcode-select --install
```

3. Clone the repo:

```bash
git clone https://github.com/Louis-Ph/bulkhead-lm.git
cd bulkhead-lm
```

4. Put your key in a secret file:

```bash
printf '%s\n' 'export GOOGLE_API_KEY="paste-your-key-here"' >> ~/.zshrc.secret
```

You can replace `GOOGLE_API_KEY` with `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, `MISTRAL_API_KEY`, or `OPEN_ROUTER_KEY`.

5. Start:

```bash
./run.sh
```

6. When BulkheadLM asks which model you want, choose a model marked `[ready]`.

## Ubuntu: easiest local start

1. Open the terminal.
2. Install `git` if needed:

```bash
sudo apt update
sudo apt install -y git
```

3. Clone the repo:

```bash
git clone https://github.com/Louis-Ph/bulkhead-lm.git
cd bulkhead-lm
```

4. Put your key in a secret file:

```bash
printf '%s\n' 'export GOOGLE_API_KEY="paste-your-key-here"' >> ~/.bashrc.secret
```

5. Start:

```bash
./run.sh
```

6. The starter can help with missing OCaml tools by itself.

## Windows with WSL Ubuntu: easiest local start

This is the easiest Windows path because BulkheadLM already knows how to behave on Ubuntu.

1. Open PowerShell as Administrator.
2. Install WSL Ubuntu:

```powershell
wsl --install -d Ubuntu
```

3. Restart if Windows asks.
4. Open the Ubuntu app.
5. If Ubuntu asks you to create a username and password, do it once.
6. Now follow the Ubuntu steps above inside Ubuntu.

Short version inside WSL:

```bash
sudo apt update
sudo apt install -y git
git clone https://github.com/Louis-Ph/bulkhead-lm.git
cd bulkhead-lm
printf '%s\n' 'export GOOGLE_API_KEY="paste-your-key-here"' >> ~/.bashrc.secret
./run.sh
```

## FreeBSD: easiest local start

1. Open a shell.
2. Install `git`:

```bash
sudo pkg install -y git
```

3. Clone the repo:

```bash
git clone https://github.com/Louis-Ph/bulkhead-lm.git
cd bulkhead-lm
```

4. Put your key in a secret file:

```bash
printf '%s\n' 'export GOOGLE_API_KEY="paste-your-key-here"' >> ~/.profile.secret
```

5. Start:

```bash
./run.sh
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
3. Let you choose a model.
4. Open a simple chat.
5. Let you attach a local text file with `/file PATH`.
6. Let you explore folders with `/explore`, open a text file with `/open`, and run one safe local command with `/run`.
7. Help configure BulkheadLM with `/admin`.
8. Help build a distributable package with `/package`.

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

1. Gemini API free tier if available where you live.
2. Mistral free experiment tier if it is available for your account.
3. Official provider promotional credits if they exist on the day you sign up.
4. Local Ollama on your own machine.
5. OpenRouter free models router if you already have an OpenRouter key.

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

1. Use a Mac, Ubuntu, WSL Ubuntu, or FreeBSD machine.
2. Get one Gemini API key.
3. Put it in a secret file.
4. Run `./run.sh`.
5. Choose a ready model.
6. Start chatting.
