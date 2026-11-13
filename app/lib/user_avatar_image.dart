import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'auth.dart';

class UserAvatarImage extends StatelessWidget {
  const UserAvatarImage({
    required this.nickname,
    required this.radius,
    this.avatarUrl,
    super.key,
  });

  final String nickname;
  final String? avatarUrl;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final url = avatarUrl?.trim();
    final fallback = nickname.trim().isEmpty ? '用' : nickname.trim()[0];
    return CircleAvatar(
      radius: radius,
      backgroundColor: AppPalette.soft,
      child: url == null || url.isEmpty
          ? Text(fallback, style: TextStyle(fontSize: radius * .75))
          : ClipOval(
              child: Image.network(
                absoluteImageUrl(url),
                width: radius * 2,
                height: radius * 2,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Center(child: Text(fallback)),
              ),
            ),
    );
  }
}
