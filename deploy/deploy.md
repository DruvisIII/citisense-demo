# Deploying the Barangay Reports web demo to Railway

The demo is a static Flutter web build (`--dart-define=DEMO=true`). It needs
no backend, database, camera, maps API or AI model: all data is simulated
in the browser and saved per browser (shared_preferences / localStorage).

The Docker image only serves files with nginx. **Flutter is not installed in
the image: you build locally and commit the result in `deploy/web/`.**

## 1. Build (on your computer, from the project root)

```bash
flutter pub get
```

```bash
flutter build web --release --dart-define=DEMO=true --no-web-resources-cdn
```

`--no-web-resources-cdn` bundles CanvasKit (Flutter's renderer) in the build.
Without it, every tester's browser downloads it from www.gstatic.com at
start-up, and the app shows a blank page if that host is slow or blocked.

## 2. Copy the build into deploy/web

macOS / Linux:

```bash
rm -rf deploy/web && cp -R build/web deploy/web
```

Windows (PowerShell):

```powershell
Remove-Item -Recurse -Force deploy\web -ErrorAction SilentlyContinue; Copy-Item -Recurse build\web deploy\web
```

Optional local check (needs Docker):

```bash
docker build -t brgy-demo deploy && docker run --rm -p 8080:8080 brgy-demo
```

Then open http://localhost:8080.

## 3. Push to GitHub

```bash
git add deploy && git commit -m "Update web demo build" && git push
```

## 4. Create a NEW Railway service (separate from your backend)

1. Open your Railway project (or create a new one). Do **not** edit the
   existing backend/API service.
2. **+ New → GitHub Repo →** pick this repository. A new service is created.
3. Open the new service → **Settings → Source → Root Directory**: `deploy`
   (so Railway finds `deploy/Dockerfile` and builds from that folder).
   Railway detects the Dockerfile automatically.
4. **Settings → Networking → Generate Domain.** Railway gives a public
   `https://<name>.up.railway.app` address. If asked for a port, use the
   one shown in the deploy logs (the container listens on `$PORT`).
5. Wait for the deploy to finish (Deployments tab shows "Success").
6. Open the URL. Confirm the padlock (HTTPS) and the login screen with the
   "Demo accounts" box. `https://<domain>/healthz` should return `ok`.

No environment variables or secrets are needed.

To update later: rebuild (step 1), copy (step 2), push (step 3). Railway
redeploys automatically. `index.html`, `main.dart.js`, `flutter_bootstrap.js`,
`flutter_service_worker.js` and `version.json` are served with `no-cache`,
so testers get the new version on the next load.

## Demo accounts

| Username | Password |
|----------|----------|
| tester1  | demo1    |
| tester2  | demo2    |
| tester3  | demo3    |
| tester4  | demo4    |
| tester5  | demo5    |

(`tester1@demo.test` also works as a username.) Names and e-mails are fake.
Data is per browser, not per account: Settings → **Reset demo** restores the
starting data and restarts the tutorial.

## Test checklist after each deployment

Devices and browsers:

- [ ] Phone on **mobile data** (Wi-Fi off): Android Chrome
- [ ] Phone on mobile data: iPhone Safari
- [ ] Laptop: Chrome, Edge and Firefox (app shows as a centred phone-width column)
- [ ] A **private / incognito** window (starts fresh: tutorial from step 1)

Walk through the 16 tutorial steps once (Next stays disabled until each
highlighted action is done):

- [ ] 1-2 Welcome, Home overview
- [ ] 3 Tap "Report an Issue" → Next unlocks (Next is disabled before that)
- [ ] 4 Choose a sample photo
- [ ] 5 AI suggestion appears after ~1.5 s; the category can be changed; Confirm
- [ ] 6 Set Location on Map → static map with pin → Confirm
- [ ] 7 Tap the Description box (typing is optional) → Next unlocks
- [ ] 8 Submit Report → snackbar "Report REP0xx submitted"
- [ ] 9 My Reports shows the new report with a **Pending** chip
- [ ] 10 Alerts: banner + unread dot + badge "Your report REP0xx is now In progress"
- [ ] 11 Tap it → Report Details shows **In progress** (and your description)
- [ ] 12 Auto-scroll to "Ask your barangay about this report", tap it
- [ ] 13 Message is pre-filled, press Send → "Barangay is typing…" → after ~2 s
      the reply **"Currently working for it."**
- [ ] 14 Press Back (in-app arrow or browser Back) → My Reports shows **Resolved**
      and a "has been resolved" notification
- [ ] 15 Open the resolved report → Rate the Resolution (5 stars + comment
      pre-filled) → Submit Feedback → "Thanks for your feedback!" → Finish
- [ ] 16 "Thank you for testing!" with a 3-second countdown, then the Google
      Form opens **in the same tab** (check on Android Chrome AND iPhone Safari)
- [ ] On the Google Form, press the browser **Back** button: the app returns to
      Home, the tutorial does **not** restart and there is no second redirect
- [ ] Refresh the page in the middle of the tutorial: it resumes at the same step
- [ ] Settings → How to test / Give feedback / Reset demo all work
- [ ] Skip the tutorial: a "Give feedback" button appears on Home (no redirect)
