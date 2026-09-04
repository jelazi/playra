import 'dart:convert';

enum ServerType { smb, http, ftp }

/// Saved remote server connection (e.g. SMB share).
class ServerConnection {
  final String id;
  final String name;
  final ServerType type;
  final String host;
  final int? port;
  final String? share; // for smb
  final String? path; // optional starting path
  final String? username;
  final String? password;

  const ServerConnection({
    required this.id,
    required this.name,
    required this.type,
    required this.host,
    this.port,
    this.share,
    this.path,
    this.username,
    this.password,
  });

  ServerConnection copyWith({String? name, ServerType? type, String? host, int? port, String? share, String? path, String? username, String? password}) =>
      ServerConnection(
        id: id,
        name: name ?? this.name,
        type: type ?? this.type,
        host: host ?? this.host,
        port: port ?? this.port,
        share: share ?? this.share,
        path: path ?? this.path,
        username: username ?? this.username,
        password: password ?? this.password,
      );

  /// Copy without the password. `copyWith` cannot express this — a null there
  /// means "keep the current value".
  ServerConnection withoutPassword() => ServerConnection(id: id, name: name, type: type, host: host, port: port, share: share, path: path, username: username);

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'type': type.name,
    'host': host,
    'port': port,
    'share': share,
    'path': path,
    'username': username,
    'password': password,
  };

  factory ServerConnection.fromJson(Map<String, dynamic> j) => ServerConnection(
    id: j['id'] as String,
    name: j['name'] as String,
    type: ServerType.values.firstWhere((v) => v.name == j['type'], orElse: () => ServerType.smb),
    host: j['host'] as String,
    port: j['port'] as int?,
    share: j['share'] as String?,
    path: j['path'] as String?,
    username: j['username'] as String?,
    password: j['password'] as String?,
  );

  String encode() => jsonEncode(toJson());
  static ServerConnection decode(String s) => ServerConnection.fromJson(jsonDecode(s) as Map<String, dynamic>);
}
