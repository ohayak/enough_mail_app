import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';

class IconText extends StatelessWidget {
  final Widget icon;
  final Widget label;
  final EdgeInsets padding;
  final EdgeInsets horizontalPadding;
  final Brightness? brightness;
  const IconText({
    Key? key,
    required this.icon,
    required this.label,
    this.padding = const EdgeInsets.all(8.0),
    this.horizontalPadding = const EdgeInsets.only(left: 8.0),
    this.brightness,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: padding,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          icon,
          Padding(
            padding: horizontalPadding,
            child: label,
          )
        ],
      ),
    );
    if (brightness != null) {
      return Theme(
        data: ThemeData(brightness: brightness),
        child: content,
      );
    } else {
      return content;
    }
  }
}
