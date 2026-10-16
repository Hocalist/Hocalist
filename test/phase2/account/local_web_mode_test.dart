import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/data/phase2/providers/provider_runtime.dart';

void main() {
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
