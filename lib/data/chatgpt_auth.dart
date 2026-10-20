import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:jose/jose.dart';
import 'package:uuid/uuid.dart';
import '../domain/user_profile.dart';
import '../domain/workout.dart';

class ChatGptFailure extends ValidationException {
  const ChatGptFailure(
    this.code, {
    this.status,
    this.requestId,
    this.param,
    this.shape,
  }) : super('');
  final String code;
  final int? status;
  final String? requestId, param, shape;
  @override
  String get message => switch (code) {
    'subscription_sharing_user_not_eligible' =>
      'Esta cuenta o espacio de ChatGPT no es elegible para usar su plan en GymIA. Puedes elegir otro proveedor.',
    'subscription_sharing_usage_limit_exceeded' =>
      'Has alcanzado un límite de uso de ChatGPT. Revisa Uso en los ajustes de ChatGPT antes de volver a enviar.',
    'subscription_sharing_unsupported_capability' =>
      'El plan ChatGPT no admite esta función o entrada con el modelo elegido.',
    'subscription_sharing_route_not_supported' ||
    'chatpass_v2_scope_not_authorized' ||
    'chatpass_v2_invalid_authorization_context' =>
      'ChatGPT no autoriza esta integración o permiso. Tus otros proveedores siguen disponibles.',
    'no_plan' =>
      'Cuenta conectada, pero no has autorizado el uso del plan ChatGPT. Actívalo en ajustes de IA o elige otro proveedor.',
    'cancelled' => 'Conexión con ChatGPT cancelada.',
    'access_denied' =>
      'No se concedió el permiso de ChatGPT. Puedes continuar con otro proveedor.',
    'callback_timeout' =>
      'No llegó el retorno de ChatGPT. Vuelve a la app y reintenta la conexión.',
    'identity' =>
      'No se pudo verificar la identidad devuelta por ChatGPT. No se ha conectado la cuenta.',
    'reconnect' ||
    'invalid_grant' ||
    'invalid_refresh_token' ||
    'token_expired' ||
    'refresh_token_expired' ||
    'refresh_token_invalidated' ||
    'refresh_token_reused' ||
    'subscription_sharing_invalid_user' =>
      'La sesión de ChatGPT ya no es válida. Vuelve a conectar la cuenta desde ajustes de IA.',
    'invalid_client' =>
      'ChatGPT no aceptó el registro de GymIA. Vuelve a conectar o usa otro proveedor.',
    _ => switch (status) {
      401 =>
        'ChatGPT rechazó la sesión o el permiso. Revisa la conexión de la cuenta.',
      403 =>
        'Una restricción de ChatGPT impide esta solicitud para tu cuenta, espacio o región.',
      429 =>
        'ChatGPT limita las solicitudes. Revisa Uso en los ajustes de ChatGPT.',
      400 =>
        'ChatGPT no admite esta solicitud. Revisa el modelo y los adjuntos.',
      503 =>
        'El uso del plan ChatGPT no está disponible ahora. Conservamos la conexión; reintenta más tarde.',
      _ =>
        'No se pudo completar la conexión con ChatGPT. Revisa la red y vuelve a intentarlo.',
    },
  };

  static ChatGptFailure response(
    int status,
    Map<String, dynamic> body, {
    String? requestId,
  }) {
    final error = body['error'];
    final code = error is Map ? error['code'] ?? error['type'] : error;
    return ChatGptFailure(
      code is String ? code : 'request_failed',
      status: status,
      requestId: requestId,
      param:
          error is Map && error['param'] is String
              ? error['param'] as String
              : null,
      shape:
          error is Map
              ? 'error'
              : body.containsKey('detail')
              ? 'detail'
              : 'other',
    );
  }
}

class ChatGptHttpResult {
  const ChatGptHttpResult(this.status, this.body, {this.requestId});
  final int status;
  final Map<String, dynamic> body;
  final String? requestId;
}

typedef ChatGptTransport =
    Future<ChatGptHttpResult> Function(Uri uri, Map<String, String>? form);
typedef ChatGptBrowser = Future<void> Function(Uri uri);

class ChatGptAccount {
  const ChatGptAccount(this.data);
  final Map<String, dynamic> data;
  String get clientId => data['client_id'] as String;
  String get subject => data['subject'] as String;
  String get email => data['email'] as String? ?? 'Cuenta ChatGPT';
  bool get connected => data['access_token'] is String;
  Set<String> get scopes => Set<String>.from(data['scopes'] as List? ?? []);
  bool get canUsePlan =>
      connected &&
      scopes.contains('resource.invoke') &&
      scopes.contains('chatgpt.tokens.use.direct');
  String get label =>
      '$email · ${clientId.length > 10 ? clientId.substring(clientId.length - 8) : clientId}';
}

/// A one-use browser callback bound only to the device loopback interface.
/// State and PKCE never survive process death: interrupted attempts restart.
class ChatGptCallback {
  ChatGptCallback._(this.server, this.state);
  final HttpServer server;
  final String state;
  bool _received = false;
  final completer = Completer<Map<String, String>>();
  Uri get uri => Uri.parse('http://127.0.0.1:${server.port}/auth/callback');
  static Future<ChatGptCallback> open(String state) async {
    final callback = ChatGptCallback._(
      await HttpServer.bind(InternetAddress.loopbackIPv4, 0, shared: false),
      state,
    );
    callback.server.listen(callback._handle);
    return callback;
  }

  void _handle(HttpRequest request) async {
    try {
      final params = request.uri.queryParametersAll;
      final valid =
          request.method == 'GET' &&
          request.uri.path == '/auth/callback' &&
          request.headers.value('host') == '127.0.0.1:${server.port}' &&
          request.uri.query.length < 16384 &&
          params.values.every((v) => v.length == 1) &&
          _same(params['state']?.single ?? '', state) &&
          !completer.isCompleted &&
          !_received;
      if (valid) _received = true;
      request.response.statusCode = valid ? 200 : 400;
      request.response.headers.set('Cache-Control', 'no-store');
      request.response.headers.set(
        'Content-Security-Policy',
        "default-src 'none'",
      );
      request.response.headers.set('Referrer-Policy', 'no-referrer');
      request.response.headers.contentType = ContentType.html;
      request.response.write(
        valid
            ? '<!doctype html><meta charset="utf-8"><title>GymIA</title><p>Respuesta recibida. Vuelve a GymIA para comprobar la conexión.</p>'
            : 'Retorno no válido.',
      );
      await request.response.close();
      if (valid && !completer.isCompleted) {
        completer.complete(request.uri.queryParameters);
      }
    } catch (_) {
      // A browser closing a socket is not an application error or a valid return.
      try {
        await request.response.close();
      } catch (_) {}
    }
  }

  Future<Map<String, String>> wait(Duration timeout) =>
      completer.future.timeout(
        timeout,
        onTimeout: () => throw const ChatGptFailure('callback_timeout'),
      );
  Future<void> close() async {
    if (!completer.isCompleted) {
      completer.complete({'error': 'cancelled', 'state': state});
    }
    await server.close(force: true);
  }

  static bool _same(String a, String b) {
    var diff = a.length ^ b.length;
    for (var i = 0; i < min(a.length, b.length); i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }
}

class ChatGptAuth {
  ChatGptAuth({
    required this.profileId,
    ChatGptTransport? transport,
    ChatGptBrowser? browser,
    this.timeout = const Duration(minutes: 5),
  }) : transport = transport ?? http,
       browser = browser ?? openBrowser;
  final String profileId;
  final ChatGptTransport transport;
  final ChatGptBrowser browser;
  final Duration timeout;
  static const storage = FlutterSecureStorage();
  static const channel = MethodChannel('com.gymia.app/chatgpt');
  static const issuer = 'https://auth.openai.com';
  static const resource = 'https://api.openai.com/v1';
  static const identityScopes = 'openid profile email';
  static const planScopes =
      '$identityScopes offline_access resource.invoke chatgpt.tokens.use.direct';
  static final Map<String, Future<void>> _locks = {};
  static final Map<String, int> _epochs = {};
  String get _key => profileStorageKey('gymia.chatgpt.accounts.v1', profileId);
  int get _epoch => _epochs[_key] ?? 0;
  ChatGptCallback? _pending;
  bool _connecting = false;
  int _attempt = 0;
  String? _incompleteClientId;

  static String randomSecret() {
    final random = Random.secure();
    return base64Url
        .encode(List.generate(32, (_) => random.nextInt(256)))
        .replaceAll('=', '');
  }

  static String challenge(String verifier) => base64Url
      .encode(sha256.convert(ascii.encode(verifier)).bytes)
      .replaceAll('=', '');
  Future<T> _locked<T>(Future<T> Function() action, {String? key}) async {
    final lockKey = key ?? _key;
    final previous = _locks[lockKey] ?? Future<void>.value();
    final done = Completer<void>();
    _locks[lockKey] = done.future;
    await previous;
    try {
      return await action();
    } finally {
      done.complete();
      if (identical(_locks[lockKey], done.future)) _locks.remove(lockKey);
    }
  }

  Future<Map<String, dynamic>> _read() async {
    final raw = await storage.read(key: _key);
    return raw == null ? {} : Map<String, dynamic>.from(jsonDecode(raw) as Map);
  }

  Future<void> _write(Map<String, dynamic> value) =>
      storage.write(key: _key, value: jsonEncode(value));
  Future<List<ChatGptAccount>> accounts() async =>
      (await _read()).values
          .map((v) => ChatGptAccount(Map<String, dynamic>.from(v as Map)))
          .toList();
  Future<String> _host() => _locked(() async {
    const key = 'gymia.chatgpt.host.v1';
    var host = await storage.read(key: key);
    host ??= 'urn:uuid:${const Uuid().v4()}';
    await storage.write(key: key, value: host);
    return host;
  }, key: 'gymia.chatgpt.host.v1');
  Future<ChatGptAccount> account(String id) async {
    final row = (await _read())[id];
    if (row is! Map) throw const ChatGptFailure('reconnect');
    return ChatGptAccount(Map<String, dynamic>.from(row));
  }

  Future<void> cancel() async {
    _attempt++;
    await _pending?.close();
    _pending = null;
  }

  Future<ChatGptAccount> connect({
    String? clientId,
    bool usePlan = false,
    bool consent = false,
    bool newRegistration = false,
  }) async {
    if (_connecting) {
      throw const ValidationException(
        'Ya hay una conexión con ChatGPT en curso.',
      );
    }
    _connecting = true;
    if (newRegistration) _incompleteClientId = null;
    try {
      return await _connect(
        clientId: clientId,
        usePlan: usePlan,
        consent: consent,
      );
    } finally {
      _connecting = false;
    }
  }

  Future<ChatGptAccount> _connect({
    String? clientId,
    required bool usePlan,
    required bool consent,
  }) async {
    final epoch = _epoch, attempt = _attempt;
    final saved = clientId == null ? null : await account(clientId);
    final registrationId = clientId ?? _incompleteClientId;
    final state = randomSecret(),
        nonce = randomSecret(),
        verifier = randomSecret();
    final callback = await ChatGptCallback.open(state);
    _pending = callback;
    // Install the error handler before opening a browser that can return quickly.
    final returned = callback.wait(timeout);
    unawaited(returned.then<void>((_) {}, onError: (Object _) {}));
    try {
      final host = await _host();
      if (attempt != _attempt) throw const ChatGptFailure('cancelled');
      await browser(
        Uri.parse('$issuer/api/accounts/authorize').replace(
          queryParameters: {
            'client_id': registrationId ?? 'dynamic_agent_client',
            if (registrationId == null) 'agent_name_hint': 'GymIA',
            'ext_agent_host_id': host,
            if (saved?.data['id_token'] is String)
              'id_token_hint': saved!.data['id_token'] as String,
            'response_type': 'code',
            'redirect_uri': callback.uri.toString(),
            'scope': usePlan ? planScopes : identityScopes,
            'resource': resource,
            'state': state,
            'nonce': nonce,
            'code_challenge_method': 'S256',
            'code_challenge': challenge(verifier),
            if (consent) 'prompt': 'consent',
          },
        ),
      );
      final params = await returned;
      if (params['error'] != null) {
        throw ChatGptFailure(
          params['error'] == 'access_denied' ? 'access_denied' : 'cancelled',
        );
      }
      final issued = params['client_id'] ?? registrationId;
      if (issued == null ||
          !RegExp(r'^[A-Za-z0-9_-]{1,256}$').hasMatch(issued) ||
          issued == 'dynamic_agent_client' ||
          (registrationId != null && registrationId != issued) ||
          params['code'] == null) {
        throw const ChatGptFailure('identity');
      }
      _incompleteClientId = issued;
      final tokens = await _call('$issuer/api/accounts/oauth/token', {
        'grant_type': 'authorization_code',
        'client_id': issued,
        'code': params['code']!,
        'code_verifier': verifier,
        'redirect_uri': callback.uri.toString(),
        'resource': resource,
      });
      final identity = await verifyIdentity(
        tokens['id_token'],
        issued,
        nonce: nonce,
      );
      if (saved != null && saved.subject != identity['sub']) {
        throw const ChatGptFailure('identity');
      }
      final data = _tokenRecord(tokens, {
        'client_id': issued,
        'subject': identity['sub'],
        'email': identity['email'],
        'issuer': issuer,
      });
      await _locked(() async {
        if (epoch != _epoch || attempt != _attempt) {
          throw const ChatGptFailure('cancelled');
        }
        final rows = await _read();
        rows[issued] = data;
        await _write(rows);
      });
      _incompleteClientId = null;
      return ChatGptAccount(data);
    } on ValidationException {
      rethrow;
    } catch (_) {
      throw const ChatGptFailure('connection');
    } finally {
      await callback.close();
      if (identical(_pending, callback)) _pending = null;
      // Consume a pending wait after cancellation/browser launch failure.
      unawaited(returned.then<void>((_) {}, onError: (Object _) {}));
      try {
        await channel.invokeMethod<void>('resumeApp');
      } catch (_) {
        /* Android only. */
      }
    }
  }

  Future<Map<String, dynamic>> verifyIdentity(
    dynamic token,
    String clientId, {
    String? nonce,
  }) async {
    try {
      if (token is! String || token.length > 20000) {
        throw const FormatException();
      }
      final parts = token.split('.');
      if (parts.length != 3) throw const FormatException();
      final header =
          jsonDecode(
                utf8.decode(base64Url.decode(base64Url.normalize(parts[0]))),
              )
              as Map;
      if (header['alg'] != 'RS256') throw const FormatException();
      final metadata = await _call(
        '$issuer/.well-known/openid-configuration',
        null,
      );
      if (metadata['issuer'] != issuer) throw const FormatException();
      final jwksUri = _trusted(metadata['jwks_uri']);
      final keys = await _call(jwksUri.toString(), null);
      final store = JsonWebKeyStore()..addKeySet(JsonWebKeySet.fromJson(keys));
      final jwt = await JsonWebToken.decodeAndVerify(
        token,
        store,
        allowedArguments: ['RS256'],
      );
      final claims = jwt.claims.toJson();
      final aud = claims['aud'];
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      if (claims['iss'] != issuer ||
          !(aud == clientId || aud is List && aud.contains(clientId)) ||
          (aud is List && aud.length > 1 && claims['azp'] != clientId) ||
          claims['exp'] is! num ||
          (claims['exp'] as num) <= now ||
          claims['iat'] is! num ||
          (claims['iat'] as num) > now + 60 ||
          (claims['nbf'] is num && (claims['nbf'] as num) > now + 60) ||
          (nonce != null && claims['nonce'] != nonce) ||
          claims['sub'] is! String ||
          (claims['sub'] as String).isEmpty) {
        throw const FormatException();
      }
      return claims;
    } catch (_) {
      throw const ChatGptFailure('identity');
    }
  }

  static Uri _trusted(dynamic value) {
    final uri = value is String ? Uri.tryParse(value) : null;
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host != 'auth.openai.com' ||
        uri.port != 443 ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment ||
        uri.hasQuery) {
      throw const ChatGptFailure('identity');
    }
    return uri;
  }

  Map<String, dynamic> _tokenRecord(
    Map<String, dynamic> tokens,
    Map<String, dynamic> previous,
  ) {
    if (tokens['access_token'] is! String ||
        (tokens['access_token'] as String).isEmpty ||
        tokens['token_type']?.toString().toLowerCase() != 'bearer' ||
        tokens['expires_in'] is! num ||
        (tokens['expires_in'] as num) <= 0) {
      throw const ChatGptFailure('identity');
    }
    final scope = tokens['scope'];
    return {
      ...previous,
      'access_token': tokens['access_token'],
      if (tokens['refresh_token'] is String)
        'refresh_token': tokens['refresh_token'],
      if (tokens['id_token'] is String) 'id_token': tokens['id_token'],
      'scopes':
          scope is String
              ? scope.split(' ').where((s) => s.isNotEmpty).toList()
              : previous['scopes'] ?? [],
      'expires_at':
          DateTime.now()
              .add(Duration(seconds: (tokens['expires_in'] as num).toInt()))
              .toUtc()
              .toIso8601String(),
    };
  }

  Future<String> _token(String id, {String? rejected}) => _locked(() async {
    final current = await account(id);
    if (!current.canUsePlan) {
      throw ChatGptFailure(current.connected ? 'no_plan' : 'reconnect');
    }
    final data = current.data;
    final token = data['access_token'] as String;
    final expires = DateTime.tryParse(data['expires_at'] as String? ?? '');
    if ((rejected != null && rejected != token) ||
        (rejected == null &&
            expires != null &&
            expires.isAfter(DateTime.now().add(const Duration(seconds: 60))))) {
      return token;
    }
    final refresh = data['refresh_token'];
    if (refresh is! String) throw const ChatGptFailure('reconnect');
    try {
      final tokens = await _call('$issuer/api/accounts/oauth/token', {
        'grant_type': 'refresh_token',
        'client_id': id,
        'refresh_token': refresh,
        'resource': resource,
      });
      if (tokens['id_token'] != null) {
        final identity = await verifyIdentity(tokens['id_token'], id);
        if (identity['sub'] != current.subject) {
          throw const ChatGptFailure('identity');
        }
      }
      if (tokens['refresh_token'] is! String) {
        throw const ChatGptFailure('identity');
      }
      final next = _tokenRecord(tokens, data);
      final rows = await _read();
      rows[id] = next;
      await _write(rows);
      final account = ChatGptAccount(next);
      if (!account.canUsePlan) throw const ChatGptFailure('no_plan');
      return next['access_token'] as String;
    } on ChatGptFailure catch (e) {
      if ([
        'invalid_grant',
        'invalid_refresh_token',
        'token_expired',
        'refresh_token_expired',
        'refresh_token_invalidated',
        'refresh_token_reused',
      ].contains(e.code)) {
        final rows = await _read();
        rows[id] = _withoutTokens(data);
        await _write(rows);
      }
      rethrow;
    }
  });
  Future<T> authorized<T>(
    String id,
    Future<T> Function(String token) action,
  ) async {
    final epoch = _epoch;
    final token = await _token(id);
    if (epoch != _epoch) throw const ChatGptFailure('cancelled');
    T result;
    try {
      result = await action(token);
    } on ChatGptFailure catch (e) {
      if (e.status != 401 || epoch != _epoch) rethrow;
      final renewed = await _token(id, rejected: token);
      if (epoch != _epoch) throw const ChatGptFailure('cancelled');
      result = await action(renewed);
    }
    if (epoch != _epoch) throw const ChatGptFailure('cancelled');
    return result;
  }

  static Map<String, dynamic> _withoutTokens(Map<String, dynamic> data) =>
      {...data}..removeWhere(
        (k, _) => [
          'access_token',
          'refresh_token',
          'id_token',
          'expires_at',
          'scopes',
        ].contains(k),
      );
  Future<bool> disconnect(String id) async {
    _epochs[_key] = _epoch + 1;
    await cancel();
    return _locked(() async {
      final data = (await account(id)).data;
      var revoked = data['refresh_token'] == null;
      try {
        if (!revoked) {
          final metadata = await _call(
            '$issuer/.well-known/openid-configuration',
            null,
          );
          final uri = _trusted(metadata['revocation_endpoint']);
          await _call(uri.toString(), {
            'token': data['refresh_token'] as String,
            'token_type_hint': 'refresh_token',
            'client_id': id,
          });
          revoked = true;
        }
      } catch (_) {
        revoked = false;
      } finally {
        final rows = await _read();
        rows[id] = _withoutTokens(data);
        await _write(rows);
      }
      return revoked;
    });
  }

  Future<Map<String, dynamic>> _call(
    String uri,
    Map<String, String>? form,
  ) async {
    final response = await transport(Uri.parse(uri), form);
    if (response.status < 200 || response.status >= 300) {
      throw ChatGptFailure.response(
        response.status,
        response.body,
        requestId: response.requestId,
      );
    }
    return response.body;
  }

  static Future<void> openBrowser(Uri uri) async {
    try {
      await channel.invokeMethod<void>('openBrowser', {'url': uri.toString()});
    } catch (_) {
      throw const ValidationException(
        'No se pudo abrir el navegador de Android. Comprueba que tienes uno instalado.',
      );
    }
  }

  Future<void> showUsage() =>
      browser(Uri.parse('https://chatgpt.com/settings/usage'));
  static Future<ChatGptHttpResult> http(
    Uri uri,
    Map<String, String>? form,
  ) async {
    final client =
        HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      return await (() async {
        final request = await client.openUrl(
          form == null ? 'GET' : 'POST',
          uri,
        );
        request.followRedirects = false;
        request.headers.set('Accept', 'application/json');
        if (form != null) {
          request.headers.set(
            'Content-Type',
            'application/x-www-form-urlencoded',
          );
          request.add(utf8.encode(Uri(queryParameters: form).query));
        }
        final response = await request.close();
        final bytes = <int>[];
        await for (final chunk in response) {
          if (bytes.length + chunk.length > 1024 * 1024) {
            throw const FormatException();
          }
          bytes.addAll(chunk);
        }
        Map<String, dynamic> body = {};
        if (bytes.isNotEmpty) {
          try {
            body = Map<String, dynamic>.from(
              jsonDecode(utf8.decode(bytes)) as Map,
            );
          } catch (_) {
            if (response.statusCode >= 200 && response.statusCode < 300) {
              rethrow;
            }
          }
        }
        return ChatGptHttpResult(
          response.statusCode,
          body,
          requestId: response.headers.value('x-request-id'),
        );
      })().timeout(const Duration(seconds: 25));
    } on ChatGptFailure {
      rethrow;
    } catch (_) {
      throw const ChatGptFailure('connection');
    } finally {
      client.close(force: true);
    }
  }
}
