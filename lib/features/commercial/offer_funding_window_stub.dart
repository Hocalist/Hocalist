import 'package:url_launcher/url_launcher.dart';

class OfferFundingWindow {
  bool open() => true;
  Future<bool> navigate(Uri url) =>
      launchUrl(url, mode: LaunchMode.externalApplication);
  String? returned(String setup) => null;
  void close() {}
}
