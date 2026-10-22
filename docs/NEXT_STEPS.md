# Next steps that need accounts or tools outside the code

Everything else is built. These parts need something only the owner can set up.

## 0. Turn on Guard battles (one time)

1. Re-run `server/schema.sql` in the Supabase SQL Editor.
2. In the SQL Editor, run `select v from cb_config where k = 'war_key';` and copy the value.
3. On GitHub, open the repo's **Settings → Secrets and variables → Actions → New repository secret**. Name it `WAR_KEY` and paste the value.
4. Open the **Actions** tab, choose **Guard battles**, and press **Run workflow** once to test it. After that it runs every 30 minutes by itself.

GitHub pauses scheduled workflows in a repo with no commits for 60 days. If battles stop, open the Actions tab and re-enable it.

## 1. Check retention (do this weekly)

In Supabase, go to **SQL Editor**, paste the query below and press **Run**:

```sql
select * from retention_report limit 30;
```

Each row is one day's new players and the share who came back 1, 7 and 30 days later. Targets before spending on growth: **day 1 at 40% or more, day 7 at 20% or more.**

## 2. Push notifications ("your move", "your nation needs you")

1. Generate VAPID keys once with `npx web-push generate-vapid-keys` and keep the private key secret.
2. Add a `push_subscriptions` table and a Supabase Edge Function that sends a push when a one-move-a-day game changes turn.
3. iPhone only shows web push for apps added to the Home Screen (iOS 16.4 and later), so the app should prompt players to install it first.

Ask Claude to build this once the keys exist. The client side and the Edge Function code can be written in one session.

## 3. App Store and Google Play

1. **Apple Developer Program**: $99 a year at developer.apple.com. A Mac with Xcode is needed to build the iPhone app.
2. **Google Play Console**: a one-time $25 fee at play.google.com/console.
3. The app gets wrapped with Capacitor (`npm i @capacitor/core @capacitor/cli`, then `npx cap add ios` and `npx cap add android`). Native push uses `@capacitor/push-notifications`.
4. Store listings need screenshots, a short and long description, an age rating questionnaire and the privacy policy URL: https://forestmack.github.io/chess-battle/privacy.html

## 4. Chess Battle Pro and crown packs (payments)

1. Create a Stripe account and two products: Pro ($4.99 a month) and crown packs.
2. Add a Supabase Edge Function for Stripe Checkout and a webhook that marks the player as Pro or adds crowns.
3. In the App Store and Google Play builds, digital purchases must go through Apple's and Google's in-app purchase systems instead of Stripe.

## 5. Translations

Spanish, Portuguese, Hindi and Russian first. This needs every on-screen string moved into a translation table, which is a large but mechanical change.

## 6. 2v2 nation team chess

Two players per side sharing one gold bank. This needs new game rules, a 4-player lobby and turn order. Build it after the core game shows good retention.

## 7. Legal review

`privacy.html` and `terms.html` are written in plain language for a launch. Have a lawyer review them before taking payments or running ads, and if the game is marketed to schools.
