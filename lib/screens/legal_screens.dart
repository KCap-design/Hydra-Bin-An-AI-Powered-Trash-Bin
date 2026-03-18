import 'package:flutter/material.dart';

class LegalScreen extends StatelessWidget {
  final String title;
  final String content;

  const LegalScreen({super.key, required this.title, required this.content});

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF22C55E);
    const bg = Color(0xFF0B0E17);
    const surface = Color(0xFF131824);
    const textPri = Color(0xFFF8FAFC);
    const textSec = Color(0xFF64748B);

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: surface,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF252B3B)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title.toUpperCase(),
                style: const TextStyle(
                  color: accent,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                content,
                style: const TextStyle(
                  color: textPri,
                  fontSize: 16,
                  height: 1.6,
                ),
              ),
              const SizedBox(height: 32),
              const Divider(color: Color(0xFF252B3B)),
              const SizedBox(height: 16),
              const Text(
                "Last Updated: March 2026",
                style: TextStyle(color: textSec, fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const LegalScreen(
      title: "Privacy Policy",
      content: """
Hydra Bin ("we," "our," or "us") is committed to protecting your privacy. This Privacy Policy explains how your personal information is collected, used, and disclosed by Hydra Bin.

1. Information We Collect
We collect information when you use our app, including profile details from social login providers (Google/Facebook) such as your name, email address, and profile picture.

2. How We Use Information
We use your information to:
- Provide and maintain our service.
- Display your profile in the leaderboards.
- Send you notifications regarding your recycling stats.

3. Sharing Information
We do not share your personal information with third parties except as necessary to provide the service or as required by law.

4. Data Retention
We retain your data as long as your account is active. You can request data deletion at any time via the settings in the app or the data deletion page.
      """,
    );
  }
}

class DataDeletionScreen extends StatelessWidget {
  const DataDeletionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const LegalScreen(
      title: "Data Deletion Instructions",
      content: """
At Hydra Bin, we respect your right to manage your data. If you wish to delete your account and all associated data, please follow these instructions:

1. Log in to your Hydra Bin account.
2. Go to the Profile Tab.
3. Select 'Settings' or use the 'Delete Account' button if available.
4. Confirm your deletion request.

Alternatively, if you used Facebook Login to sign up:
1. Go to your Facebook Profile's Apps and Websites settings.
2. Remove the Hydra Bin app.
3. Click 'View Removed Apps and Websites' and select Hydra Bin to request data deletion.

Once requested, all your personal data (name, email, points, and history) will be permanently purged from our database within 24 hours.
      """,
    );
  }
}

class TermsOfServiceScreen extends StatelessWidget {
  const TermsOfServiceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const LegalScreen(
      title: "Terms of Service",
      content: """
By using Hydra Bin, you agree to the following terms:

1. Use of Service
You must use the app for its intended purpose: tracking recycling activity. Any misuse or attempts to manipulate points may result in account suspension.

2. Accounts
When you create an account, you must provide accurate information. You are responsible for maintaining the security of your account.

3. Intellectual Property
The app and its original content are the property of Hydra Bin and are protected by international copyright and trademark laws.

4. Limitation of Liability
Hydra Bin shall not be liable for any indirect, incidental, or consequential damages resulting from the use of the service.

5. Changes to Terms
We reserve the right to modify these terms at any time. Your continued use of the app constitutes acceptance of the new terms.
      """,
    );
  }
}
