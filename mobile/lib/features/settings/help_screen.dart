import 'package:flutter/material.dart';

import '../../core/theme.dart';

class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Help & Support'),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.menu_book_outlined), text: 'How to Use'),
              Tab(icon: Icon(Icons.help_outline), text: 'FAQs'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [_HowToUseTab(), _FaqTab()],
        ),
      ),
    );
  }
}

// ─── How to Use ──────────────────────────────────────────────────────────────

class _HowToUseTab extends StatelessWidget {
  const _HowToUseTab();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: const [
        _SectionHeader('For Clients'),
        _StepTile(
          number: '1',
          title: 'Browse the Explore Feed',
          body:
              'Open the Explore tab to see recent service listings, reviews, and social posts from local providers.',
        ),
        _StepTile(
          number: '2',
          title: 'Find a Provider',
          body:
              'Tap a listing card and press "Book" to start a booking, or tap the provider\'s name to view their full service profile.',
        ),
        _StepTile(
          number: '3',
          title: 'Post a Job Request',
          body:
              'Go to the Jobs tab and tap "+". Describe what you need, set your budget and municipality, then publish. Providers will send you offers.',
        ),
        _StepTile(
          number: '4',
          title: 'Manage Bookings',
          body:
              'Track all your bookings in the Bookings tab. Once a job is completed, rate the provider to help others in the community.',
        ),
        SizedBox(height: 20),
        _SectionHeader('For Workers & Agencies'),
        _StepTile(
          number: '1',
          title: 'Set Up Your Provider Profile',
          body:
              'Go to the Dashboard tab. Fill in your display name, service category, municipality, and the services you offer. Submit for admin approval.',
        ),
        _StepTile(
          number: '2',
          title: 'Create Service Listings',
          body:
              'Once approved, add listings with your prices, availability, and requirements. These appear in the Explore feed for clients.',
        ),
        _StepTile(
          number: '3',
          title: 'Browse & Bid on Jobs',
          body:
              'Check the Jobs tab → Browse to see open job requests from clients. Tap a job and send an offer with your message and proposed price.',
        ),
        _StepTile(
          number: '4',
          title: 'Accept Bookings',
          body:
              'Clients can book you directly. Go to Bookings → Orders to confirm, start, or complete incoming bookings.',
        ),
        SizedBox(height: 20),
        _SectionHeader('Social Features'),
        _StepTile(
          number: '•',
          title: 'Post on the Feed',
          body:
              'Tap the "+" icon in the Explore tab to share a post with the community. Your profile picture will appear with your post.',
        ),
        _StepTile(
          number: '•',
          title: 'Follow Users',
          body:
              'Search for a user in the Explore searchbar and tap their name to view their profile. Press Follow — their posts will appear higher in your feed.',
        ),
        _StepTile(
          number: '•',
          title: 'Like & Comment',
          body:
              'Tap the heart icon on any feed card to like it. Tap the comment icon or the card itself to open the full post and leave a comment.',
        ),
        SizedBox(height: 24),
      ],
    );
  }
}

// ─── FAQs ────────────────────────────────────────────────────────────────────

class _FaqTab extends StatelessWidget {
  const _FaqTab();

  static const _faqs = [
    (
      q: 'What is HanapGawa?',
      a: 'HanapGawa is a local service marketplace for Tawi-Tawi. It connects clients who need work done with skilled local workers and agencies.',
    ),
    (
      q: 'How do I book a service provider?',
      a: 'Browse the Explore feed, tap a service listing card, and press the "Book" button. Fill in the location details and notes, then confirm.',
    ),
    (
      q: 'Is HanapGawa free to use?',
      a: 'Yes. Creating an account, posting jobs, and browsing listings are all free. HanapGawa does not take a cut from transactions.',
    ),
    (
      q: 'How do I become a provider?',
      a: 'Register or update your account with the Worker or Agency role, go to the Dashboard tab, complete your provider profile, and wait for admin approval (usually within 24 hours).',
    ),
    (
      q: 'What areas does HanapGawa cover?',
      a: 'HanapGawa currently covers all municipalities of Tawi-Tawi: Bongao, Panglima Sugala, South Ubian, Simunul, Sibutu, Tandubas, Sapa-Sapa, Languyan, Mapun, Turtle Islands, and Cagayan de Tawi-Tawi.',
    ),
    (
      q: 'How do I cancel or update a booking?',
      a: 'Go to the Bookings tab, find the booking, and use the action buttons (Confirm, Cancel, Complete) depending on your role and the current status.',
    ),
    (
      q: 'How are reviews verified?',
      a: 'Reviews can only be submitted by clients who have a completed booking with that provider, ensuring all feedback is from real transactions.',
    ),
    (
      q: 'How do I report a user or provider?',
      a: 'Open the provider\'s profile page via Explore and tap the "Report" button. Describe the issue and it will be reviewed by the admin.',
    ),
    (
      q: 'Why is my provider profile pending approval?',
      a: 'All new provider profiles are reviewed by the HanapGawa admin team to ensure quality and legitimacy. This usually takes 24–48 hours.',
    ),
    (
      q: 'How do I change my profile photo?',
      a: 'Go to the Profile tab. Tap the circular avatar photo to pick a new image from your gallery. Tap the cover photo area to change the cover.',
    ),
    (
      q: 'I forgot my password. What do I do?',
      a: 'On the login screen tap "Forgot password?" (if available) or contact the HanapGawa admin for account recovery assistance.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: _faqs
          .map((faq) => ExpansionTile(
                tilePadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                leading: const Icon(Icons.question_answer_outlined,
                    color: appPrimary),
                title: Text(faq.q,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 14)),
                children: [
                  Text(faq.a,
                      style: const TextStyle(
                          color: Color(0xFF555555), height: 1.5)),
                ],
              ))
          .toList(),
    );
  }
}

// ─── Shared helpers ───────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);
  final String title;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(
          title,
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.w900, color: appPrimary),
        ),
      );
}

class _StepTile extends StatelessWidget {
  const _StepTile(
      {required this.number, required this.title, required this.body});
  final String number;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 28,
              height: 28,
              margin: const EdgeInsets.only(top: 2, right: 12),
              decoration: const BoxDecoration(
                  color: appPrimary, shape: BoxShape.circle),
              child: Center(
                child: Text(number,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 13)),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 3),
                  Text(body,
                      style: const TextStyle(
                          color: Color(0xFF555555), height: 1.45)),
                ],
              ),
            ),
          ],
        ),
      );
}
