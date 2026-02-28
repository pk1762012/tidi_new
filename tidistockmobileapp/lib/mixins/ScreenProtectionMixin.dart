import 'package:flutter/widgets.dart';
import 'package:tidistockmobileapp/service/ScreenProtectionService.dart';

mixin ScreenProtectionMixin<T extends StatefulWidget> on State<T> {
  @override
  void initState() {
    super.initState();
    ScreenProtectionService.instance.enableProtection();
  }

  @override
  void dispose() {
    ScreenProtectionService.instance.disableProtection();
    super.dispose();
  }
}
