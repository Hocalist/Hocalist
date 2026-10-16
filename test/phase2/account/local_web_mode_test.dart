import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/data/phase2/providers/provider_runtime.dart';

void main() {
  test(
    'LAN handoff opens only the configured secure root without auth parameters',
    () {
      final current = Uri.parse(
        'http://192.168.1.184:7361/?code=synthetic#private',
      );
      expect(
        hocalistSecurePreviewHandoff(
          current,
          secureOrigin: 'https://approved.trycloudflare.com',
        ).toString(),
        'https://approved.trycloudflare.com/',
      );
      for (final invalid in [
        '',
        'http://example.com',
        'https://example.com/path',
        'https://user@example.com',
      ]) {
        expect(
          hocalistSecurePreviewHandoff(current, secureOrigin: invalid),
          isNull,
        );
      }
      expect(
        hocalistSecurePreviewHandoff(
          Uri.parse('https://approved.trycloudflare.com/'),
          secureOrigin: 'https://approved.trycloudflare.com',
        ),
        isNull,
      );
    },
  );
  test(
    'Google return refuses LAN IP but keeps secure and loopback previews',
    () {
      expect(
        supportsHocalistOAuthReturn(Uri.parse('http://192.168.1.184:7361/')),
        isFalse,
      );
      for (final url in [
        'https://test.trycloudflare.com/',
        'http://127.0.0.1:7359/',
        'http://localhost:7359/',
      ]) {
        expect(supportsHocalistOAuthReturn(Uri.parse(url)), isTrue);
      }
    },
  );
  test('HTTPS preview admits only its exact configured secure origin', () {
    const origin = 'https://approved-preview.trycloudflare.com';
    for (final url in [origin, '$origin/?code=synthetic']) {
      expect(
        isHocalistLocalWebTestOrigin(
          Uri.parse(url),
          enabled: true,
          httpsTestOrigin: origin,
        ),
        isTrue,
      );
    }
    for (final url in [
      'http://approved-preview.trycloudflare.com',
      'https://other.trycloudflare.com',
      '$origin.evil.example',
      '$origin:444',
    ]) {
      expect(
        isHocalistLocalWebTestOrigin(
          Uri.parse(url),
          enabled: true,
          httpsTestOrigin: origin,
        ),
        isFalse,
      );
    }
    expect(
      isHocalistLocalWebTestOrigin(
        Uri.parse(origin),
        enabled: false,
        httpsTestOrigin: origin,
      ),
      isFalse,
    );
    expect(
      isHocalistLocalWebTestOrigin(
        Uri.parse(origin),
        enabled: true,
        httpsTestOrigin: '',
      ),
      isFalse,
    );
  });
  test('Wi-Fi preview requires the exact build-configured origin', () {
    expect(
      isHocalistLocalWebTestOrigin(
        Uri.parse('http://192.168.1.184:7361/'),
        enabled: true,
      ),
      hocalistWifiTestOrigin == 'http://192.168.1.184:7361',
    );
    expect(
      isHocalistLocalWebTestOrigin(
        Uri.parse('http://192.168.1.184:7362/'),
        enabled: true,
      ),
      isFalse,
    );
    expect(
      isHocalistLocalWebTestOrigin(
        Uri.parse('http://192.168.1.184:7361/'),
        enabled: false,
      ),
      isFalse,
    );
  });
  test('real web testing requires an explicit loopback HTTP origin', () {
    expect(
      isHocalistLocalWebTestOrigin(
        Uri.parse('http://127.0.0.1:7359/'),
        enabled: true,
      ),
      isTrue,
    );
    expect(
      isHocalistLocalWebTestOrigin(
        Uri.parse('http://localhost:7359/'),
        enabled: true,
      ),
      isTrue,
    );
    expect(
      isHocalistLocalWebTestOrigin(
        Uri.parse('http://127.0.0.1:7359/'),
        enabled: false,
      ),
      isFalse,
    );
    for (final uri in [
      'https://hocalist.com/',
      'http://hocalist.com/',
      'http://127.0.0.1.evil.example/',
      'file:///hocalist/index.html',
    ]) {
      expect(
        isHocalistLocalWebTestOrigin(Uri.parse(uri), enabled: true),
        isFalse,
        reason: uri,
      );
    }
  });
}
