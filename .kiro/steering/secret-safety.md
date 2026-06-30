# Secret-safety pre-commit protocol (NON-NEGOTIABLE)

Before EVERY `git commit` or `git push`:

1. Run `git status`.
2. Run `git diff --cached --name-only`.
3. Ensure NONE of these are staged (match by name anywhere in the path):
   - `android/key.properties`
   - `*.jks`
   - `*.keystore`
   - `.env`, `.env.*`
   - `service-account*.json`
   - `firebase-adminsdk*.json`
   - `GoogleService-Info.plist`
   - `google-services.json.backup`
   - `PROJECT_SECRETS.md`

If ANY secret file is detected in the staged set: **STOP immediately. Do NOT
commit or push.** Report exactly which file was caught and wait for the user's
explicit approval before proceeding.

## Staging hygiene
- NEVER use `git add -A` or `git add .`. Stage only the specific files you
  intend to commit (`git add <path> ...`). A broad add is how secrets and
  unrelated changes slip in.
- Prefer `git mv` for moves so history is preserved and only those paths stage.

## If a secret is already tracked
- Do not just delete it — it stays in history. Flag to the user; removal needs
  `git rm --cached` + a history-rewrite decision, which only the user approves.
