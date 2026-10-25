# Only Us — calculator-style couples website (updated starter)

Mobile-friendly static website starter with Supabase authentication, ₹49/30-day manual UPI payments, one-time couple pairing codes, couple-specific text chat, photo/video uploads, voice recording, and an admin dashboard.

## Important before launch
- This is a starter project, not a security-audited production service. Test it with test accounts first.
- The calculator code (`2580`) only reveals the sign-in screen. It is not account security.
- **Admin access:** `singjaskaran68@gmail.com` is promoted to admin by the SQL setup. Admin can review payment requests, see couple membership and open recent couple messages/media. Tell all users clearly that the admin may access message and media content before they join.
- Chat and media are **not end-to-end encrypted**. Do not claim that only the couple can ever read content because the configured admin can also access it.
- UPI payments are manual. Verify the actual FamPay transaction before approving. Screenshots/UTR alone are not proof of payment.
- Voice recording requires microphone permission and an HTTPS deployment. Browser/device support can vary.
- Media uploads are limited to 50 MB per file and allowed MIME types in the SQL bucket configuration. Consider lower limits for mobile data and cost.
- SQL is intended for a **new Supabase project**. Do not run it blindly on top of the previous schema; it creates policies and tables for this updated structure.

## 1. Set up Supabase on your phone
1. Open https://supabase.com and create a project.
2. Open **SQL Editor** and run the full `supabase-schema.sql` file.
3. The SQL creates tables, RLS policies, private media storage, pairing functions, payment approval function, and promotes `singjaskaran68@gmail.com` to admin if that account already exists. New signups with that email are also marked admin.
4. Open Project Settings / API keys. Copy the **Project URL** and the **publishable/anon key**. Never copy a service-role or secret key into browser code.
5. In `app.js`, replace:
   - `PASTE_YOUR_SUPABASE_PROJECT_URL_HERE`
   - `PASTE_YOUR_SUPABASE_ANON_KEY_HERE`
   - `YOUR-UPI-ID-HERE`
6. If your admin account already existed before running SQL, sign out/in after SQL completes. If it does not show Admin dashboard, run this in SQL Editor: `update public.profiles set is_admin=true where lower(email)='singjaskaran68@gmail.com';`

## 2. Add your FamPay QR (optional)
Upload the QR image into `assets/fampay-qr.png`. Never upload UPI PINs, OTPs, bank credentials or private keys.

## 3. How pairing works
1. Both people create their own account and get approved for ₹49 premium access.
2. Person 1 taps **Create pairing code** and shares the one-time code privately.
3. Person 2 enters the code under **Join partner**.
4. The code can only be used once, and each account can belong to one couple at a time.
5. Their chat uses a couple ID, not a public/shared room code. Other couples are blocked by database access rules.

## 4. Text, photos, videos and voice messages
- Text messages are saved in Supabase Postgres.
- Photos and videos are uploaded to the private `couple-media` storage bucket.
- Voice recording uses the browser microphone and uploads the resulting audio file to the same private bucket.
- File access is limited by storage policies to paired couple members and the admin account.
- Signed URLs are short-lived for media display. This is access control, not end-to-end encryption.

## 5. Manual ₹49 payment approval
1. User pays ₹49 with your UPI QR/ID.
2. User submits their UTR/reference in the website.
3. You verify the real payment in FamPay transaction history.
4. Open Admin dashboard and approve only the matching payment. Approval grants 30 days of premium access.
5. Users must manually pay and request renewal again after expiry.

## 6. Deploy free using GitHub + Cloudflare Pages
1. Extract this ZIP on your phone and upload the files inside `secret-couples-app` to the root of a GitHub repository. Keep `index.html`, `style.css`, `app.js`, `supabase-schema.sql`, `README.md`, and `assets/` in the same structure.
2. Open https://dash.cloudflare.com/ → Workers & Pages → Create → Pages → Connect to Git.
3. Select the repository. For this plain static website, leave the build command blank if allowed and set the output directory to the repository root (or `.` if required by the UI).
4. Deploy. Test the `pages.dev` site on HTTPS; microphone recording will not work on insecure HTTP.

## Pre-launch checks
- Test two test accounts pairing successfully and a third account being unable to join the already-used code.
- Confirm a couple cannot read another couple's text or media.
- Confirm non-admin users cannot open the admin dashboard or approve payments.
- Confirm `singjaskaran68@gmail.com` can review payment requests and access the admin dashboard.
- Test image, video and audio uploads on Android Chrome.
- Publish a clear privacy policy explaining admin message/media access, storage, retention, deletion, payment handling and contact information before inviting real users.
