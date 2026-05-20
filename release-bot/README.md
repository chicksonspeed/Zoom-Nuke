# Zoom-Nuke Release Bot

A small, boring, reliable Node.js bot that listens for GitHub Release webhook events and posts an announcement to a Telegram channel or group whenever a new Zoom-Nuke release is published.

---

## Project structure

```
release-bot/
├── src/
│   └── index.js          # Main server — webhook listener + Telegram sender
├── .env.example          # Environment variable template
├── .gitignore
├── package.json
├── posted-releases.json  # Auto-created at runtime — tracks posted tags
└── README.md
```

---

## How it works

1. GitHub fires a `release` webhook event when a release is published.  
2. The bot verifies the HMAC-SHA256 signature with your `GITHUB_WEBHOOK_SECRET`.  
3. It checks `action === "published"` and skips drafts, edits, deletions, and tags.  
4. It checks `posted-releases.json` to prevent duplicate posts for the same tag.  
5. It sends a formatted message to Telegram via the Bot API.  
6. It saves the tag to `posted-releases.json` so future duplicates are ignored.

---

## Setup

### 1. Reuse @Zoomnuke_bot (no new bot needed)

You already have **@Zoomnuke_bot**. You only need its token.

**Get or regenerate the token from BotFather:**

1. Open Telegram and search for **@BotFather**.
2. Send `/mybots` and select **@Zoomnuke_bot**.
3. Tap **API Token** to view the existing token.
4. If you need a new one, tap **Revoke current token** and then **Regenerate**.
5. Copy the token — it looks like `123456789:AAFxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx`.

---

### 2. Add @Zoomnuke_bot to your channel or group

**For a channel:**
1. Open the channel in Telegram.
2. Go to **Manage Channel → Administrators → Add Administrator**.
3. Search for `@Zoomnuke_bot` and add it.
4. Grant at minimum the **Post Messages** permission.

**For a group:**
1. Open the group.
2. Tap the group name → **Add Members**.
3. Search for `@Zoomnuke_bot` and add it.

---

### 3. Get your TELEGRAM_CHAT_ID

**For a public channel:**  
The chat ID is `@your_channel_username` (e.g. `@zoomnukereleases`).

**For a private channel or group:**  
1. Forward any message from the channel/group to **@userinfobot** or **@RawDataBot**.
2. The bot will reply with the chat ID — it looks like `-1001234567890` (note the negative sign for channels/groups).

Alternatively, temporarily set your bot token and call:
```
https://api.telegram.org/bot<TOKEN>/getUpdates
```
Send a message in the group and look for `"chat":{"id":...}` in the response.

---

### 4. Install dependencies

```bash
cd release-bot
npm install
```

---

### 5. Configure environment variables

```bash
cp .env.example .env
```

Edit `.env`:

```
TELEGRAM_BOT_TOKEN=123456789:AAFxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
TELEGRAM_CHAT_ID=-1001234567890
GITHUB_WEBHOOK_SECRET=a_random_secret_you_choose
PORT=3000
```

Generate a strong webhook secret:
```bash
openssl rand -hex 32
```

---

### 6. Run locally (for testing)

```bash
npm start
```

Expose it to the internet with [ngrok](https://ngrok.com/) for local webhook testing:
```bash
ngrok http 3000
```

Use the `https://xxxx.ngrok.io` URL as your webhook URL in GitHub.

---

### 7. Create the GitHub webhook

1. Go to your repository: `https://github.com/chicksonspeed/Zoom-Nuke`
2. Navigate to **Settings → Webhooks → Add webhook**.
3. Fill in:
   - **Payload URL:** `https://your-deployed-url.com/webhook`
   - **Content type:** `application/json`
   - **Secret:** the same value as `GITHUB_WEBHOOK_SECRET` in your `.env`
   - **Which events?** → Select **Let me select individual events** → check only **Releases**
   - **Active:** ✅ checked
4. Click **Add webhook**.

GitHub will immediately send a `ping` event. The bot will log it and return 200 (it's not a `release` event so nothing is posted).

---

## Deployment

### Render (recommended — free tier available)

1. Push `release-bot/` to a GitHub repo (or a subfolder of Zoom-Nuke).
2. Create a new **Web Service** on [render.com](https://render.com).
3. Set:
   - **Environment:** Node
   - **Build command:** `npm install`
   - **Start command:** `npm start`
   - **Root directory:** `release-bot` (if it's a subfolder)
4. Add environment variables in the Render dashboard (never commit `.env`).
5. Use the Render URL (`https://your-service.onrender.com/webhook`) in your GitHub webhook.

> ⚠️ Render free tier spins down after inactivity. GitHub webhooks will wake it up within seconds but the first post after a long idle may be delayed. Use a paid plan or keep-alive ping for production.

### Railway

1. Connect your GitHub repo at [railway.app](https://railway.app).
2. Set the root directory to `release-bot`.
3. Railway auto-detects Node. Set the start command to `npm start`.
4. Add environment variables in the Railway dashboard.
5. Railway gives you a permanent HTTPS URL.

### Fly.io

```bash
cd release-bot
fly launch          # follow prompts, choose a region
fly secrets set TELEGRAM_BOT_TOKEN=... TELEGRAM_CHAT_ID=... GITHUB_WEBHOOK_SECRET=...
fly deploy
```

Use the Fly URL (`https://your-app.fly.dev/webhook`) in your GitHub webhook.

> Note: `posted-releases.json` lives on the container's ephemeral filesystem. On Fly.io, attach a persistent volume to `/app` to survive redeploys, or switch the state storage to a database.

### VPS (Ubuntu/Debian)

```bash
# Install Node 18+
curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
sudo apt-get install -y nodejs

# Clone or upload your bot
cd /opt/zoom-nuke-release-bot
npm install

# Create .env
nano .env   # fill in your values

# Run with PM2
npm install -g pm2
pm2 start src/index.js --name zoom-nuke-bot
pm2 save
pm2 startup   # follow the printed command to auto-start on reboot
```

Put a reverse proxy (nginx / Caddy) in front and point your GitHub webhook at `https://your-domain.com/webhook`.

---

## Endpoints

| Method | Path       | Description                              |
|--------|------------|------------------------------------------|
| `GET`  | `/health`  | Returns `{"status":"ok","timestamp":"…"}` |
| `POST` | `/webhook` | GitHub release webhook receiver          |

---

## Example Telegram message

```
🚨 Zoom-Nuke release published

Version: v2.1.0
Title: The Big Cleanup

- Fixed crash on empty meeting list
- Added auto-logout on timeout
- Improved error messages

Download:
https://github.com/chicksonspeed/Zoom-Nuke/releases/tag/v2.1.0
```

---

## Security notes

- **Never commit `.env`** — it's in `.gitignore`.
- **Signature verification** — every incoming request is verified with HMAC-SHA256. Requests with a missing or incorrect signature are rejected with HTTP 401.
- **Secret rotation** — if you suspect `GITHUB_WEBHOOK_SECRET` is compromised, generate a new one (`openssl rand -hex 32`), update it in your deployment environment, and update the GitHub webhook secret. Do the same for the Telegram bot token via BotFather.
- **Minimal surface area** — only `POST /webhook` and `GET /health` are handled. All other routes return 404.
- **No inbound ports exposed directly** — run behind a reverse proxy (nginx/Caddy) in VPS deployments.
- **`posted-releases.json` is not sensitive** — it contains only tag names. Do not commit it.

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| Bot starts then crashes immediately | Check all three env vars are set |
| GitHub webhook shows `401` | Wrong or missing `GITHUB_WEBHOOK_SECRET` |
| GitHub webhook shows `500` | Telegram API failed — check `TELEGRAM_BOT_TOKEN` and `TELEGRAM_CHAT_ID` |
| Message posted but bot not in channel | Add @Zoomnuke_bot as admin with Post Messages permission |
| Same release posted twice | Shouldn't happen — check `posted-releases.json` exists and is writable |
| `ping` event on webhook creation | Expected — bot logs and ignores it |
