import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class TextWithLinks extends StatelessWidget {
  final String text;
  final TextStyle? style;
  const TextWithLinks({Key? key, required this.text, this.style})
      : super(key: key);
  static final RegExp schemeRegEx = RegExp(r'[a-z]{3,6}://');
  // not a perfect but good enough regular expression to match URLs in text. It also matches a space at the beginning and a dot at the end,
  // so this is filtered out manually in the found matches
  static final RegExp linkRegEx = RegExp(
      r'(([a-z]{3,6}:\/\/)|(^|\s))([a-zA-Z0-9\-]+\.)+[a-z]{2,13}([\?\/]+[\.\?\=\&\%\/\w\+\-]*)?');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textStyle = style ??
        theme.textTheme.bodyText2 ??
        TextStyle(
            color: theme.brightness == Brightness.light
                ? Colors.black
                : Colors.white);
    final matches = linkRegEx.allMatches(text);
    if (matches.isEmpty) {
      return SelectableText(text, style: textStyle);
    }
    final linkStyle = textStyle.copyWith(
        decoration: TextDecoration.underline, color: theme.accentColor);
    final spans = <TextSpan>[];
    var end = 0;
    for (final match in matches) {
      if (match.end < text.length && text[match.end] == '@') {
        // this is an email address, abort abort! ;-)
        continue;
      }
      final originalGroup = match.group(0)!;
      final group = originalGroup.trimLeft();
      final start = match.start + originalGroup.length - group.length;
      spans.add(TextSpan(text: text.substring(end, start)));
      final endsWithDot = group.endsWith('.');
      final urlText =
          endsWithDot ? group.substring(0, group.length - 1) : group;
      final url = !group.startsWith(schemeRegEx) ? 'https://$urlText' : urlText;
      spans.add(TextSpan(
          text: urlText,
          style: linkStyle,
          recognizer: TapGestureRecognizer()..onTap = () => launch(url)));
      end = endsWithDot ? match.end - 1 : match.end;
    }
    if (end < text.length) {
      spans.add(TextSpan(text: text.substring(end)));
    }
    return SelectableText.rich(
      TextSpan(children: spans, style: textStyle),
    );
  }
}
