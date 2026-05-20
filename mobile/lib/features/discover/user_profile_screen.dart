import 'package:flutter/material.dart';

import '../../core/api/marketplace_api.dart';
import '../profile/profile_screen.dart';

class UserProfileScreen extends StatelessWidget {
  const UserProfileScreen(
      {super.key, required this.api, required this.userId, this.displayName});
  final MarketplaceApi api;
  final String userId;
  final String? displayName;

  @override
  Widget build(BuildContext context) => ProfileScreen(
        api: api,
        openDashboard: () {},
        viewingUserId: userId,
        preloadedName: displayName,
      );
}
