import 'package:flutter/material.dart';

/// A [SnackBar] whose hero has a tag of its own. Use it instead of
/// [SnackBar].
///
/// Flutter wraps each SnackBar in a [Hero], so it holds still while a page
/// slides in, and tags it by its content (`'<SnackBar Hero tag - $content>'`).
/// A SnackBar replaced by one with the same content while a page was pushed
/// shared that tag, so a pop that interrupted the push turned the first one's
/// flight to the second one's hero and failed a Flutter debug assertion in
/// `_HeroFlight.divert` (flutter/flutter#172054, #61). Keyed here, the content
/// of each SnackBar is distinct, and so is its tag: a SnackBar still flies
/// between pages, but never as another one.
class AppSnackBar extends SnackBar {
  AppSnackBar({
    super.key,
    required Widget content,
    super.backgroundColor,
    super.duration,
    super.action,
    super.behavior,
  }) : super(
         content: KeyedSubtree(key: UniqueKey(), child: content),
       );
}
