import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import '../models/artifact_model.dart';
import '../widgets/chat_input.dart';
import 'package:http_parser/http_parser.dart' as http_parser;
import 'package:shared_preferences/shared_preferences.dart';
import '../core/constants.dart';

class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  static const _secureStorage = FlutterSecureStorage();
  static const _requestTimeout = Duration(seconds: 25);
  static const _browseTimeout = Duration(seconds: 90);
  static const _streamConnectTimeout = Duration(seconds: 30);
  static const _uploadTimeout = Duration(seconds: 60);

  String? _token;
  String? _username;
  int? _userId;
  String? _role;

  String? get token => _token;
  String? get username => _username;
  int? get userId => _userId;
  String? get role => _role;
  bool get isLoggedIn => _token != null;
  bool get isAdmin => _role == 'admin';

  Map<String, String> get _authHeaders {
    if (_token == null || _token!.isEmpty) {
      throw ApiException(
        'Session expired. Please login again.',
        code: 'NO_TOKEN',
      );
    }
    return {
      'Authorization': 'Bearer $_token',
      'Content-Type': 'application/json',
    };
  }

  Future<void> loadToken() async {
    final prefs = await SharedPreferences.getInstance();

    if (kIsWeb) {
      _token = prefs.getString('auth_token');
      _username = prefs.getString('auth_username');
      _userId = prefs.getInt('auth_user_id');
      _role = prefs.getString('auth_role');
      return;
    }

    _token = await _secureStorage.read(key: 'auth_token');
    _username = await _secureStorage.read(key: 'auth_username');
    final storedUserId = await _secureStorage.read(key: 'auth_user_id');
    _userId = storedUserId == null ? null : int.tryParse(storedUserId);
    _role = await _secureStorage.read(key: 'auth_role');

    // Migrate old mobile SharedPreferences token into secure storage.
    final legacyToken = prefs.getString('auth_token');
    if (_token == null && legacyToken != null) {
      final legacyUsername = prefs.getString('auth_username');
      final legacyUserId = prefs.getInt('auth_user_id');
      final legacyRole = prefs.getString('auth_role');
      await _saveToken(
        legacyToken,
        legacyUsername ?? '',
        legacyUserId ?? 0,
        legacyRole ?? 'user',
      );
      await prefs.remove('auth_token');
      await prefs.remove('auth_username');
      await prefs.remove('auth_user_id');
      await prefs.remove('auth_role');
    }
  }

  Future<void> _saveToken(
    String token,
    String username,
    int userId,
    String role,
  ) async {
    _token = token;
    _username = username;
    _userId = userId;
    _role = role;

    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('auth_token', token);
      await prefs.setString('auth_username', username);
      await prefs.setInt('auth_user_id', userId);
      await prefs.setString('auth_role', role);
      return;
    }

    await _secureStorage.write(key: 'auth_token', value: token);
    await _secureStorage.write(key: 'auth_username', value: username);
    await _secureStorage.write(key: 'auth_user_id', value: userId.toString());
    await _secureStorage.write(key: 'auth_role', value: role);
  }

  Future<void> clearToken() async {
    _token = null;
    _username = null;
    _userId = null;
    _role = null;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token');
    await prefs.remove('auth_username');
    await prefs.remove('auth_user_id');
    await prefs.remove('auth_role');

    if (!kIsWeb) {
      await _secureStorage.delete(key: 'auth_token');
      await _secureStorage.delete(key: 'auth_username');
      await _secureStorage.delete(key: 'auth_user_id');
      await _secureStorage.delete(key: 'auth_role');
    }
  }

  Future<void> logout() async {
    if (_token == null) {
      await clearToken();
      return;
    }

    try {
      await _sendJson('POST', '/api/auth/logout', headers: _authHeaders);
    } catch (_) {
      // Local logout must still succeed even when the network is down.
    } finally {
      await clearToken();
    }
  }

  Future<http.Response> _sendJson(
    String method,
    String path, {
    Map<String, String>? headers,
    Object? body,
    Duration? timeout,
  }) async {
    final uri = Uri.parse('${AppConstants.backendUrl}$path');
    final effectiveHeaders = headers ?? {'Content-Type': 'application/json'};
    final requestBody = body == null ? null : jsonEncode(body);
    final effectiveTimeout = timeout ?? _requestTimeout;
    final maxAttempts = method == 'GET' ? 2 : 1;

    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        late final http.Response response;
        switch (method) {
          case 'GET':
            response = await http
                .get(uri, headers: effectiveHeaders)
                .timeout(effectiveTimeout);
            break;
          case 'POST':
            response = await http
                .post(uri, headers: effectiveHeaders, body: requestBody)
                .timeout(effectiveTimeout);
            break;
          case 'PUT':
            response = await http
                .put(uri, headers: effectiveHeaders, body: requestBody)
                .timeout(effectiveTimeout);
            break;
          case 'DELETE':
            response = await http
                .delete(uri, headers: effectiveHeaders)
                .timeout(effectiveTimeout);
            break;
          default:
            throw ApiException('Unsupported method: $method');
        }

        if (response.statusCode == 401) {
          await clearToken();
        }
        if (method == 'GET' &&
            response.statusCode >= 500 &&
            attempt < maxAttempts) {
          await Future<void>.delayed(const Duration(milliseconds: 450));
          continue;
        }
        return response;
      } on TimeoutException {
        if (attempt < maxAttempts) {
          await Future<void>.delayed(const Duration(milliseconds: 450));
          continue;
        }
        throw const ApiException(
          'Koneksi timeout. Coba lagi.',
          code: 'TIMEOUT',
        );
      } on http.ClientException catch (e) {
        if (attempt < maxAttempts) {
          await Future<void>.delayed(const Duration(milliseconds: 450));
          continue;
        }
        throw ApiException(
          'Koneksi gagal: ${e.message}',
          code: 'NETWORK_ERROR',
        );
      }
    }

    throw const ApiException(
      'Request gagal. Coba lagi.',
      code: 'REQUEST_FAILED',
    );
  }

  dynamic _decodeBody(http.Response response) {
    if (response.body.isEmpty) return null;
    try {
      return jsonDecode(response.body);
    } catch (_) {
      return null;
    }
  }

  Future<Never> _throwResponse(http.Response response, String fallback) async {
    final decoded = _decodeBody(response);
    final message = decoded is Map<String, dynamic>
        ? (decoded['error']?.toString() ?? fallback)
        : fallback;
    final code = decoded is Map<String, dynamic>
        ? decoded['code']?.toString()
        : null;
    final requestId = decoded is Map<String, dynamic>
        ? (decoded['request_id']?.toString() ??
              response.headers['x-request-id'])
        : response.headers['x-request-id'];

    throw ApiException(
      message,
      statusCode: response.statusCode,
      code: code,
      requestId: requestId,
    );
  }

  Future<Map<String, dynamic>> _jsonMap(
    String method,
    String path, {
    Map<String, String>? headers,
    Object? body,
    String fallback = 'Request failed',
    int okStatus = 200,
    Duration? timeout,
  }) async {
    final response = await _sendJson(
      method,
      path,
      headers: headers,
      body: body,
      timeout: timeout,
    );
    if (response.statusCode == okStatus) {
      return Map<String, dynamic>.from(_decodeBody(response) as Map);
    }
    await _throwResponse(response, fallback);
  }

  Future<List<Map<String, dynamic>>> _jsonList(
    String method,
    String path, {
    String fallback = 'Request failed',
  }) async {
    final response = await _sendJson(method, path, headers: _authHeaders);
    if (response.statusCode == 200) {
      return List<Map<String, dynamic>>.from(_decodeBody(response) as List);
    }
    await _throwResponse(response, fallback);
  }

  Future<void> submitFeedback(
    String content, {
    int? chatId,
    String? model,
  }) async {
    final response = await _sendJson(
      'POST',
      '/api/feedback',
      headers: _authHeaders,
      body: {
        'content': content.trim(),
        if (chatId != null) 'chat_id': chatId,
        if (model != null) 'model': model,
      },
    );
    if (response.statusCode != 201) {
      await _throwResponse(response, 'Gagal mengirim kritik dan saran');
    }
  }

  // Auth
  Future<Map<String, dynamic>> login(String username, String password) async {
    final data = await _jsonMap(
      'POST',
      '/api/auth/login',
      headers: {'Content-Type': 'application/json'},
      body: {'username': username, 'password': password},
      fallback: 'Login failed',
    );
    await _saveToken(
      data['token'],
      data['user']['username'],
      data['user']['id'],
      data['user']['role'] ?? 'user',
    );
    return data;
  }

  Future<Map<String, dynamic>> register(
    String username,
    String password,
  ) async {
    final data = await _jsonMap(
      'POST',
      '/api/auth/register',
      headers: {'Content-Type': 'application/json'},
      body: {'username': username, 'password': password},
      fallback: 'Register failed',
      okStatus: 201,
    );
    await _saveToken(
      data['token'],
      data['user']['username'],
      data['user']['id'],
      data['user']['role'] ?? 'user',
    );
    return data;
  }

  // Models
  Future<Map<String, dynamic>> getUsage() => _jsonMap(
    'GET',
    '/api/usage',
    headers: _authHeaders,
    fallback: 'Failed to load usage',
  );

  Future<List<Map<String, dynamic>>> getModels() async {
    final response = await _sendJson('GET', '/api/models');
    if (response.statusCode == 200) {
      final decoded = _decodeBody(response) as Map<String, dynamic>;
      return List<Map<String, dynamic>>.from(decoded['models'] as List);
    }
    await _throwResponse(response, 'Failed to load models');
  }

  /// Returns the model catalog plus the admin-configured default model id.
  Future<({List<Map<String, dynamic>> models, String? defaultModel})>
      getModelCatalog() async {
    final response = await _sendJson('GET', '/api/models');
    if (response.statusCode == 200) {
      final decoded = _decodeBody(response) as Map<String, dynamic>;
      final models = List<Map<String, dynamic>>.from(decoded['models'] as List);
      return (
        models: models,
        defaultModel: decoded['default_model']?.toString(),
      );
    }
    await _throwResponse(response, 'Failed to load models');
  }

  // Chats
  Future<List<Map<String, dynamic>>> getChats() =>
      _jsonList('GET', '/api/chats', fallback: 'Failed to load chats');

  // When [model] is null the backend picks the admin-configured default model.
  Future<Map<String, dynamic>> createChat({String? model}) => _jsonMap(
    'POST',
    '/api/chats',
    headers: _authHeaders,
    body: {
      if (model != null) 'model': model,
    },
    fallback: 'Failed to create chat',
    okStatus: 201,
  );

  Future<void> renameChat(int chatId, String title) async {
    final response = await _sendJson(
      'PUT',
      '/api/chats/$chatId',
      headers: _authHeaders,
      body: {'title': title},
    );
    if (response.statusCode != 200) {
      await _throwResponse(response, 'Failed to rename chat');
    }
  }

  Future<void> deleteChat(int chatId) async {
    final response = await _sendJson(
      'DELETE',
      '/api/chats/$chatId',
      headers: _authHeaders,
    );
    if (response.statusCode != 200) {
      await _throwResponse(response, 'Failed to delete chat');
    }
  }

  Future<void> updateChatModel(int chatId, String model) async {
    final response = await _sendJson(
      'PUT',
      '/api/chats/$chatId',
      headers: _authHeaders,
      body: {'title': null, 'model': model},
    );
    if (response.statusCode != 200) {
      await _throwResponse(response, 'Failed to update model');
    }
  }

  Future<List<Map<String, dynamic>>> searchChats(String query) => _jsonList(
    'GET',
    '/api/chats/search?q=${Uri.encodeComponent(query)}',
    fallback: 'Search failed',
  );

  Future<List<Map<String, dynamic>>> getMessages(int chatId) => _jsonList(
    'GET',
    '/api/chats/$chatId/messages',
    fallback: 'Failed to load messages',
  );

  Future<List<ArtifactSummary>> getChatArtifacts(int chatId) async {
    final rows = await _jsonList(
      'GET',
      '/api/chats/$chatId/artifacts',
      fallback: 'Failed to load artifacts',
    );
    return rows.map(ArtifactSummary.fromJson).toList();
  }

  Future<ChatArtifact> getArtifact(String artifactId) async {
    final data = await _jsonMap(
      'GET',
      '/api/artifacts/$artifactId',
      headers: _authHeaders,
      fallback: 'Failed to load artifact',
    );
    return ChatArtifact.fromJson(data);
  }

  String downloadArtifactFileUrl(String artifactId, String path) {
    final encodedPath = path.split('/').map(Uri.encodeComponent).join('/');
    return '${AppConstants.backendUrl}/api/artifacts/$artifactId/files/$encodedPath';
  }

  String downloadArtifactZipUrl(String artifactId) =>
      '${AppConstants.backendUrl}/api/artifacts/$artifactId/download.zip';

  Future<http.Response> downloadArtifactFile(String artifactId, String path) async {
    final encodedPath = path.split('/').map(Uri.encodeComponent).join('/');
    return _sendJson(
      'GET',
      '/api/artifacts/$artifactId/files/$encodedPath',
      headers: _authHeaders,
      timeout: _uploadTimeout,
    );
  }

  Future<http.Response> downloadArtifactZip(String artifactId) async {
    return _sendJson(
      'GET',
      '/api/artifacts/$artifactId/download.zip',
      headers: _authHeaders,
      timeout: _uploadTimeout,
    );
  }

  Future<Map<String, dynamic>> sendMessage(
    int chatId,
    String content, {
    List<PendingFile>? files,
    List<String>? tools,
  }) async {
    final body = <String, dynamic>{'content': content};

    if (files != null && files.isNotEmpty) {
      body['file_urls'] = files.map((f) => f.url).toList();
      body['file_names'] = files.map((f) => f.name).toList();
      body['file_url'] = files.first.url;
      body['file_name'] = files.first.name;
    }

    if (tools != null && tools.isNotEmpty) {
      body['tools'] = tools;
    }

    // Use longer timeout for browse requests (90s instead of 25s)
    final timeout = (tools?.contains('browse_web') ?? false)
        ? _browseTimeout
        : _requestTimeout;

    return _jsonMap(
      'POST',
      '/api/chats/$chatId/messages',
      headers: _authHeaders,
      body: body,
      fallback: 'Failed to send message',
      timeout: timeout,
    );
  }

  Future<Map<String, dynamic>> editMessage(
    int chatId,
    int messageId,
    String content,
  ) => _jsonMap(
    'PUT',
    '/api/chats/$chatId/messages/$messageId',
    headers: _authHeaders,
    body: {'content': content},
    fallback: 'Failed to edit message',
  );

  /// Send message with SSE streaming (real-time token delivery)
  /// Falls back to non-streaming if browse tools are active
  Stream<SseEvent> sendMessageStream(
    int chatId,
    String content, {
    List<PendingFile>? files,
    List<String>? tools,
  }) async* {
    final requiresNonStreaming =
        (tools?.contains('browse_web') ?? false) ||
        (tools?.contains('create_image') ?? false);

    if (requiresNonStreaming) {
      final result = await sendMessage(
        chatId,
        content,
        files: files,
        tools: tools,
      );
      final aiContent = result['message']?['content'] ?? '';
      yield SseEvent.token(aiContent);
      yield SseEvent.done(result);
      return;
    }

    final body = <String, dynamic>{'content': content, 'stream': true};

    if (files != null && files.isNotEmpty) {
      body['file_urls'] = files.map((f) => f.url).toList();
      body['file_names'] = files.map((f) => f.name).toList();
      body['file_url'] = files.first.url;
      body['file_name'] = files.first.name;
    }

    if (tools != null && tools.isNotEmpty) {
      body['tools'] = tools;
    }

    final request = http.Request(
      'POST',
      Uri.parse('${AppConstants.backendUrl}/api/chats/$chatId/messages'),
    );
    request.headers.addAll(_authHeaders);
    request.body = jsonEncode(body);

    final client = http.Client();
    try {
      final streamedResponse = await client
          .send(request)
          .timeout(_streamConnectTimeout);

      if (streamedResponse.statusCode == 401) {
        await clearToken();
      }

      if (streamedResponse.statusCode != 200) {
        final respBody = await streamedResponse.stream.bytesToString();
        try {
          final error = jsonDecode(respBody);
          yield SseEvent.error(
            error['error'] ?? 'Stream failed',
            code: error['code'],
            requestId: streamedResponse.headers['x-request-id'],
          );
        } catch (_) {
          yield SseEvent.error(
            'Stream failed: ${streamedResponse.statusCode}',
            requestId: streamedResponse.headers['x-request-id'],
          );
        }
        return;
      }

      String buffer = '';
      await for (final chunk in streamedResponse.stream.transform(
        utf8.decoder,
      )) {
        buffer += chunk;
        while (buffer.contains('\n\n')) {
          final idx = buffer.indexOf('\n\n');
          final line = buffer.substring(0, idx).trim();
          buffer = buffer.substring(idx + 2);

          if (!line.startsWith('data: ')) continue;
          final data = line.substring(6).trim();
          if (data == '[DONE]') continue;

          try {
            final parsed = jsonDecode(data);
            if (parsed['error'] != null) {
              yield SseEvent.error(
                parsed['error'],
                code: parsed['code'],
                requestId: parsed['request_id'],
              );
            } else if (parsed['token'] != null) {
              yield SseEvent.token(parsed['token']);
            } else if (parsed['done'] == true) {
              yield SseEvent.done(parsed);
            }
          } catch (_) {}
        }
      }
    } on TimeoutException {
      yield SseEvent.error(
        'Koneksi stream timeout. Coba lagi.',
        code: 'TIMEOUT',
      );
    } finally {
      client.close();
    }
  }

  // Upload
  // Profile
  /// Load the signed-in user's profile (display_name, avatar_url, role).
  Future<Map<String, dynamic>> getProfile() async {
    final response = await _sendJson(
      'GET',
      '/api/profile',
      headers: _authHeaders,
    );
    if (response.statusCode == 200) {
      return Map<String, dynamic>.from(_decodeBody(response) as Map);
    }
    await _throwResponse(response, 'Failed to load profile');
  }

  /// Update the user's display name (nickname).
  Future<Map<String, dynamic>> updateDisplayName(String displayName) async {
    final response = await _sendJson(
      'PUT',
      '/api/profile',
      headers: _authHeaders,
      body: {'display_name': displayName},
    );
    if (response.statusCode != 200) {
      await _throwResponse(response, 'Failed to update display name');
    }
    return Map<String, dynamic>.from(_decodeBody(response) as Map);
  }

  /// Upload a profile avatar image.
  Future<String> uploadAvatar(
    List<int> bytes,
    String fileName,
    String contentType,
  ) async {
    final uri = Uri.parse('${AppConstants.backendUrl}/api/profile/avatar');
    final request = http.MultipartRequest('POST', uri);
    request.headers['Authorization'] = 'Bearer $_token';

    final parts = contentType.split('/');
    final mediaType = parts.length == 2
        ? http_parser.MediaType(parts[0], parts[1])
        : http_parser.MediaType('application', 'octet-stream');

    request.files.add(
      http.MultipartFile.fromBytes(
        'avatar',
        bytes,
        filename: fileName,
        contentType: mediaType,
      ),
    );

    try {
      final streamedResponse = await request.send().timeout(_uploadTimeout);
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 401) {
        await clearToken();
      }

      if (response.statusCode == 200) {
        final decoded = Map<String, dynamic>.from(_decodeBody(response) as Map);
        return decoded['avatar_url'] as String? ?? '';
      }
      await _throwResponse(response, 'Avatar upload failed');
    } on TimeoutException {
      throw const ApiException('Avatar upload timeout. Coba lagi.', code: 'TIMEOUT');
    }
  }

  /// Remove the current avatar.
  Future<void> removeAvatar() async {
    final response = await _sendJson(
      'DELETE',
      '/api/profile/avatar',
      headers: _authHeaders,
    );
    if (response.statusCode != 200) {
      await _throwResponse(response, 'Failed to remove avatar');
    }
  }

  Future<Map<String, dynamic>> uploadFile(
    List<int> bytes,
    String fileName,
    String contentType,
  ) async {
    final uri = Uri.parse('${AppConstants.backendUrl}/api/upload');
    final request = http.MultipartRequest('POST', uri);
    request.headers['Authorization'] = 'Bearer $_token';

    final parts = contentType.split('/');
    final mediaType = parts.length == 2
        ? http_parser.MediaType(parts[0], parts[1])
        : http_parser.MediaType('application', 'octet-stream');

    request.files.add(
      http.MultipartFile.fromBytes(
        'file',
        bytes,
        filename: fileName,
        contentType: mediaType,
      ),
    );

    try {
      final streamedResponse = await request.send().timeout(_uploadTimeout);
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 401) {
        await clearToken();
      }

      if (response.statusCode == 200) {
        return Map<String, dynamic>.from(_decodeBody(response) as Map);
      }
      await _throwResponse(response, 'Upload failed');
    } on TimeoutException {
      throw const ApiException('Upload timeout. Coba lagi.', code: 'TIMEOUT');
    }
  }
}

class ApiException implements Exception {
  final String message;
  final int? statusCode;
  final String? code;
  final String? requestId;

  const ApiException(
    this.message, {
    this.statusCode,
    this.code,
    this.requestId,
  });

  String get supportMessage =>
      requestId == null ? message : '$message (ID: $requestId)';

  @override
  String toString() => supportMessage;
}

enum SseEventType { token, done, error }

class SseEvent {
  final SseEventType type;
  final String? token;
  final Map<String, dynamic>? metadata;
  final String? error;
  final String? code;
  final String? requestId;

  const SseEvent._({
    required this.type,
    this.token,
    this.metadata,
    this.error,
    this.code,
    this.requestId,
  });

  factory SseEvent.token(String token) =>
      SseEvent._(type: SseEventType.token, token: token);
  factory SseEvent.done(Map<String, dynamic> meta) =>
      SseEvent._(type: SseEventType.done, metadata: meta);
  factory SseEvent.error(String err, {String? code, String? requestId}) =>
      SseEvent._(
        type: SseEventType.error,
        error: err,
        code: code,
        requestId: requestId,
      );
}
