# macsetup — `newmac`

One command to turn a freshly wiped Mac into my dev machine.

## On a fresh Mac

1. Finish the macOS setup assistant and sign in to your Apple Account
   (the App Store needs it for Xcode and TestFlight).
2. Open **Terminal** and run:

   ```sh
   curl -fsSL https://raw.githubusercontent.com/ashotpahlevanyan/macsetup/main/bootstrap.sh | bash
   ```

   This installs the Command Line Tools (for git), clones this repo to
   `~/MyProjects/macsetup`, links `newmac` into `~/.local/bin` and runs
   `newmac init`.
3. Answer the questions (about 1 minute). After that the only things it
   waits for are your Mac password, an SSH key passphrase, and the GitHub
   login in the browser. Then it runs unattended. Xcode is the long part.
4. Log out and back in when it finishes.

> If this repo is private, the `curl` line won't work (no GitHub login yet).
> Download the repo as a ZIP from github.com instead, then run
> `bash macsetup-main/bootstrap.sh`, or copy the folder over from a USB stick.

## Commands

| | |
|---|---|
| `newmac init` (or `--init`) | ask the questions, run every step |
| `newmac configure` | only re-answer the questions |
| `newmac <step> [<step>…]` | run single steps, e.g. `newmac ssh iterm` |
| `newmac steps` | list the steps |
| `newmac capture` | copy this Mac's current IntelliJ, iTerm2 and keyboard settings into the repo |
| `newmac update` | `git pull` this repo + `brew upgrade` |

Answers live in `~/.config/newmac/answers.sh`, a plain file you can edit.
Every step is safe to re-run.

## What it does

| Step | What |
|---|---|
| `homebrew` | Xcode Command Line Tools, Rosetta 2, Homebrew |
| `packages` | the groups you pick from `packages/*.Brewfile`: **core** (git, gh, jq, mas, Python, pipx, uv, SWI-Prolog, bash, zsh…), **apps** (iTerm2, IntelliJ IDEA, VS Code, Sublime Text, BBEdit, Chrome, Firefox, Telegram, Claude desktop), **fonts** (Meslo/Hack/JetBrains Mono/Fira Code Nerd Fonts), **ios** (CocoaPods, SwiftLint, xcbeautify, xcodes), **extras** (Docker Desktop, Heroku CLI) |
| `git` | name and commit email (defaults to your GitHub `noreply` address, so pushes aren't refused when GitHub hides your real email), sensible defaults, `gh` as HTTPS credential helper, optional work identity for a folder |
| `ssh` | one ed25519 key per GitHub account (personal + optional work), `~/.ssh/config` with `github.com` / `github-work` host aliases, keys in the macOS Keychain, keys uploaded with `gh`, GitHub host keys verified over HTTPS |
| `shell` | oh-my-zsh + autosuggestions + syntax-highlighting, theme of your choice (agnoster / powerlevel10k / robbyrussell), dotfiles **symlinked** from `dotfiles/`, iTerm2 shell integration |
| `iterm` | default profile with your color scheme, Nerd Font + size, opens in `~/MyProjects` |
| `java` | SDKMAN, latest Temurin JDK, Maven, Gradle |
| `node` | nvm, latest Node LTS, yarn, pnpm |
| `python` | Homebrew's latest Python 3 (`python`/`pip` point to it), pipx, uv |
| `intellij` | plugins from `intellij/plugins.txt` (Material Theme UI, Atom Material Icons, Prolog) + theme, color schemes, fonts and code style from `intellij/config/` |
| `browsers` | Adblock Plus for Chrome (Chrome asks you to enable it on first start) and Firefox |
| `macos` | trackpad (tap to click, **non-natural scrolling**, speed 2.5, gestures), key repeat, keyboard layouts (ABC, Russian, Armenian-HM QWERTY…), computer name |
| `xcode` | TestFlight, Apple Developer app, Xcode (Mac App Store), license, first-launch packages, latest iOS platform + simulator |
| `claude` | Claude Code CLI (native installer, auto-updates) |
| `projects` | creates `~/MyProjects` (and the work folder) |

## Day-to-day

- **Dotfiles are symlinks into this repo.** Edit `~/.aliases` as usual,
  then commit and push from `~/MyProjects/macsetup`. The next Mac gets it.
- Machine-specific shell settings (theme, projects dir) are in
  `~/.zshrc.local`, which is not in git.
- Changed IntelliJ theme, iTerm2 colors or keyboard layouts? Run
  `newmac capture` and commit.
- New IntelliJ plugin: add its ID (shown on its JetBrains Marketplace page)
  to `intellij/plugins.txt`.
- New app: add a line to the right `packages/*.Brewfile`.
- Replaced files are backed up to `~/.newmac-backup/<timestamp>/`.
  The run log is in `~/.config/newmac/newmac.log`.

## SSH with two GitHub accounts

```sh
git clone git@github.com:me/repo.git            # personal key
git clone git@github-work:company/repo.git      # work key
```

Repos under the work folder (default `~/MyProjects/work`) also commit with
your work email and use the work key, via `includeIf` in `~/.gitconfig`.

## Notes

- **IntelliJ**: JetBrains discontinued the separate Community Edition download.
  The single `IntelliJ IDEA` app is free to use without a subscription.
- **Mac App Store apps** (Xcode, TestFlight, Developer) need you signed in to
  the App Store app. If that fails, the script opens the App Store and waits.
- No secrets are stored here: SSH keys are created on each machine, and
  `answers.sh` stays in `~/.config/newmac`.
