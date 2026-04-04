# AegisLM For Dummies

This guide is for someone who is about 10 years old, knows almost nothing about computers, and just wants AegisLM to start and let them chat.

If a word looks scary, ignore it and follow the steps one by one.

## The shortest possible idea

You need 3 things:

1. A machine where AegisLM can run.
2. One API key, or a local model.
3. One command: `./run.sh`

Then AegisLM asks you simple questions and opens a chat.

## Pick your easiest path

| What you have | Easiest path |
| --- | --- |
| macOS MacBook | Local install on the Mac |
| Ubuntu computer | Local install on Ubuntu |
| Windows computer | Use WSL Ubuntu, then follow the Ubuntu steps inside WSL |
| FreeBSD machine | Local install on FreeBSD |
| Android phone | Best path: connect by SSH to another machine already running AegisLM |
| Tablet or iPad | Best path: connect by SSH to another machine already running AegisLM |

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

## macOS: easiest local start

1. Open the Terminal app.
2. If `git` is missing, run:

```bash
xcode-select --install
```

3. Clone the repo:

```bash
git clone https://github.com/Louis-Ph/aegis-lm.git
cd aegis-lm
```

4. Put your key in a secret file:

```bash
printf '%s\n' 'export GOOGLE_API_KEY="paste-your-key-here"' >> ~/.zshrc.secret
```

You can replace `GOOGLE_API_KEY` with `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, or `MISTRAL_API_KEY`.

5. Start:

```bash
./run.sh
```

6. When AegisLM asks which model you want, choose a model marked `[ready]`.

## Ubuntu: easiest local start

1. Open the terminal.
2. Install `git` if needed:

```bash
sudo apt update
sudo apt install -y git
```

3. Clone the repo:

```bash
git clone https://github.com/Louis-Ph/aegis-lm.git
cd aegis-lm
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

This is the easiest Windows path because AegisLM already knows how to behave on Ubuntu.

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
git clone https://github.com/Louis-Ph/aegis-lm.git
cd aegis-lm
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
git clone https://github.com/Louis-Ph/aegis-lm.git
cd aegis-lm
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

1. Have another machine already running AegisLM:
   macOS, Ubuntu, WSL Ubuntu, or FreeBSD.
2. Install any SSH app on Android.
3. Connect to the other machine.
4. Run:

```bash
ssh -t your-user@your-machine 'cd /path/to/aegis-lm && ./run.sh'
```

If AegisLM is already installed as a packaged app on the remote machine, this is even easier:

```bash
ssh -t your-user@your-machine 'aegislm-starter'
```

Advanced note:
Android local install may be possible with advanced tools, but that is not the simple path for this guide.

## Tablet or iPad: easiest path

Same idea as Android.

1. Use any SSH app.
2. Connect to a Mac, Ubuntu, WSL Ubuntu, or FreeBSD machine that already has AegisLM.
3. Run:

```bash
ssh -t your-user@your-machine 'cd /path/to/aegis-lm && ./run.sh'
```

Or, if the machine has a packaged install:

```bash
ssh -t your-user@your-machine 'aegislm-starter'
```

## What happens when `./run.sh` starts

The starter tries to help you instead of throwing confusing build errors.

It can:

1. Reuse your existing keys from secret files.
2. Show which models are ready.
3. Let you choose a model.
4. Open a simple chat.
5. Help configure AegisLM with `/admin`.
6. Help build a distributable package with `/package`.

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
/models
/providers
/env
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

1. A MacBook, Ubuntu box, WSL Ubuntu PC, or FreeBSD machine runs AegisLM.
2. Your tablet or phone opens SSH to it.
3. You chat from there.

## If you get stuck

Start with these 3 questions:

1. What machine am I using?
2. Do I already have one API key?
3. Did I really run `./run.sh` inside the `aegis-lm` folder?

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
