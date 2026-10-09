import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:recipe_vault/services/yandex_auth.dart';

const id = '0123456789abcdef0123456789abcdef';
void main() {
  test('PKCE S256 matches RFC example', () {
    expect(
      YandexAuth.challenge('dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk'),
      'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM',
    );
  });
  test(
    'authorization returns to matching state and exchanges code without secret',
    () async {
      final auth = YandexAuth(
        browser: (url, callback) async {
          final request = Uri.parse(url);
          expect(callback, 'recipevault');
          expect(request.queryParameters['code_challenge_method'], 'S256');
          expect(
            request.queryParameters['scope'],
            'cloud_api:disk.read cloud_api:disk.write',
          );
          return '${YandexAuth.androidRedirect}?code=test&state=${request.queryParameters['state']}';
        },
        client: MockClient((request) async {
          final body = Uri.splitQueryString(request.body);
          expect(body['grant_type'], 'authorization_code');
          expect(body.containsKey('client_secret'), false);
          expect(body['code_verifier']!.length, greaterThanOrEqualTo(43));
          return http.Response(
            jsonEncode({
              'access_token': 'token',
              'refresh_token': 'refresh',
              'expires_in': 3600,
            }),
            200,
          );
        }),
      );
      final tokens = await auth.login(id, windows: false);
      expect(tokens.accessToken, 'token');
      expect(tokens.refreshToken, 'refresh');
      auth.close();
    },
  );
  test('wrong callback state never sends an exchange request', () async {
    final auth = YandexAuth(
      browser: (_, _) async =>
          '${YandexAuth.androidRedirect}?code=bad&state=wrong',
      client: MockClient((_) async => throw StateError('must not exchange')),
    );
    await expectLater(
      auth.login(id, windows: false),
      throwsA(isA<YandexAuthException>()),
    );
    auth.close();
  });
  test(
    'Windows callback uses local browser handler and rejects wrong route',
    () async {
      final auth = YandexAuth(
        browser: (url, callback) async {
          expect(callback, YandexAuth.windowsRedirect);
          return 'http://localhost:9876/wrong?code=test&state=${Uri.parse(url).queryParameters['state']}';
        },
      );
      await expectLater(
        auth.login(id, windows: true),
        throwsA(isA<YandexAuthException>()),
      );
      auth.close();
    },
  );
  test('missing Client ID fails before browser opens', () async {
    final auth = YandexAuth(
      browser: (_, _) async => throw StateError('must not open'),
    );
    await expectLater(auth.login(''), throwsA(isA<YandexAuthException>()));
    auth.close();
  });
}
