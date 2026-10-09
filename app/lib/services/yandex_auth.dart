import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:http/http.dart' as http;

class YandexAuthException implements Exception {
  final String message;
  const YandexAuthException(this.message);
  @override
  String toString() => message;
}

class YandexTokens {
  final String accessToken, refreshToken;
  final DateTime expiresAt;
  const YandexTokens(this.accessToken, this.refreshToken, this.expiresAt);
}

typedef AuthBrowser = Future<String> Function(String url, String callback);

class YandexAuth {
  static const androidRedirect = 'recipevault://oauth';
  static const windowsRedirect = 'http://localhost:9876/auth';
  final http.Client client;
  final AuthBrowser browser;
  YandexAuth({http.Client? client, AuthBrowser? browser})
    : client = client ?? http.Client(),
      browser =
          browser ??
          ((url, callback) => FlutterWebAuth2.authenticate(
            url: url,
            callbackUrlScheme: callback,
            options: const FlutterWebAuth2Options(
              useWebview: false,
              timeout: 180,
            ),
          ));
  static String randomToken() => base64Url
      .encode(List.generate(32, (_) => Random.secure().nextInt(256)))
      .replaceAll('=', '');
  static String challenge(String verifier) => base64Url
      .encode(sha256.convert(ascii.encode(verifier)).bytes)
      .replaceAll('=', '');
  Future<YandexTokens> login(String clientId, {bool? windows}) async {
    if (!RegExp(r'^[a-fA-F0-9]{32}$').hasMatch(clientId)) {
      throw const YandexAuthException(
        'Сначала укажите Client ID зарегистрированного приложения Яндекс OAuth.',
      );
    }
    final onWindows = windows ?? Platform.isWindows;
    final redirect = onWindows ? windowsRedirect : androidRedirect;
    final state = randomToken(), verifier = randomToken();
    final url = Uri.https('oauth.yandex.ru', '/authorize', {
      'response_type': 'code',
      'client_id': clientId,
      'redirect_uri': redirect,
      'scope': 'cloud_api:disk.read cloud_api:disk.write',
      'state': state,
      'code_challenge': challenge(verifier),
      'code_challenge_method': 'S256',
    });
    final result = Uri.parse(
      await browser(
        url.toString(),
        onWindows ? windowsRedirect : 'recipevault',
      ).timeout(const Duration(minutes: 3)),
    );
    final expected = Uri.parse(redirect);
    if (result.scheme != expected.scheme ||
        result.host != expected.host ||
        result.port != expected.port ||
        result.path.replaceFirst(RegExp(r'/$'), '') != expected.path ||
        result.queryParameters['state'] != state) {
      throw const YandexAuthException(
        'Ответ авторизации не совпал с запросом. Повторите вход.',
      );
    }
    if (result.queryParameters.containsKey('error')) {
      throw const YandexAuthException(
        'Яндекс не разрешил вход. Проверьте регистрацию приложения и права на Диск.',
      );
    }
    final code = result.queryParameters['code'];
    if (code == null || code.isEmpty) {
      throw const YandexAuthException(
        'Яндекс не вернул код авторизации. Повторите вход.',
      );
    }
    return _exchange({
      'grant_type': 'authorization_code',
      'client_id': clientId,
      'code': code,
      'code_verifier': verifier,
    });
  }

  Future<YandexTokens> refresh(String clientId, String refreshToken) =>
      _exchange({
        'grant_type': 'refresh_token',
        'client_id': clientId,
        'refresh_token': refreshToken,
      });
  Future<YandexTokens> _exchange(Map<String, String> body) async {
    final response = await client
        .post(Uri.https('oauth.yandex.ru', '/token'), body: body)
        .timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      throw const YandexAuthException(
        'Не удалось получить доступ к Яндекс Диску. Повторите вход и проверьте настройки OAuth-приложения.',
      );
    }
    final json = jsonDecode(utf8.decode(response.bodyBytes)) as Map;
    final access = json['access_token'], refresh = json['refresh_token'];
    final lifetime = json['expires_in'];
    if (access is! String ||
        access.isEmpty ||
        refresh is! String ||
        refresh.isEmpty ||
        lifetime is! num ||
        lifetime <= 0) {
      throw const YandexAuthException(
        'Яндекс вернул неполный ответ авторизации.',
      );
    }
    return YandexTokens(
      access,
      refresh,
      DateTime.now().add(Duration(seconds: lifetime.toInt())),
    );
  }

  void close() => client.close();
}
