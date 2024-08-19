import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:sqlite3/open.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:shelf/shelf_io.dart';
import 'package:crypto/crypto.dart';

const dbName = 'todos.db';

final Map<String, Response> cache = {};

Middleware accessControlHeaders() => (innerHandler) {
      return (request) {
        return innerHandler(request.change(headers: {
          'Access-Control-Allow-Origin': '*',
          'Access-Control-Allow-Methods': 'GET,POST,PATCH,DELETE',
          'Access-Control-Allow-Headers': 'Content-Type',
        }));
      };
    };

Middleware contentTypeHeader() => (innerHandler) {
      return (request) async {
        final response = await innerHandler(request);
        return response.change(headers: {
          'Content-Type': 'application/json',
        });
      };
    };

Middleware etagHeader() => (innerHandler) {
      return (request) async {
        if (request.method != 'GET') {
          return innerHandler(request);
        }
        if (request.headers.containsKey('If-None-Match')) {
          final etag = request.headers['If-None-Match'];
          if (cache.containsKey(request.url.path) &&
              cache[request.url.path]!.headers['ETag'] == etag) {
            return Response.notModified();
          }
        }
        final response = await innerHandler(request);
        cache[request.url.path] = response;
        return response;
      };
    };

// Configure routes.
final _router = Router()
  ..get('/', _getAllTodos)
  ..get('/<id>', _getTodoById)
  ..post('/', _createTodo)
  ..patch('/<id>', _updateTodo)
  ..delete('/', _deleteAllTodos)
  ..delete('/<id>', _deleteTodoById);

Map<String, dynamic> serializeTodo(Row row) {
  final todo = Map<String, dynamic>.from(row);
  todo['metadata'] = jsonDecode(todo['metadata']);
  return todo;
}

String computeEtag(String body) {
  return 'W/"${sha256.convert(utf8.encode(body)).toString()}"';
}

Future<Response> _getAllTodos(Request req) async {
  final db = sqlite3.open(dbName);
  final rows = db.select('SELECT * FROM todos;');
  db.dispose();
  final body = jsonEncode(rows.map((r) => serializeTodo(r)).toList());
  return Response.ok(body, headers: {'ETag': computeEtag(body)});
}

Future<Response> _getTodoById(Request req, String id) async {
  final db = sqlite3.open(dbName);
  final rows = db.select('SELECT * FROM todos WHERE id = ?;', [id]);
  db.dispose();
  if (rows.isEmpty) {
    return Response.notFound('{"error": "Todo $id not found"}');
  }
  final body = jsonEncode(serializeTodo(rows.first));
  return Response.ok(body, headers: {'ETag': computeEtag(body)});
}

Future<Response> _createTodo(Request req) async {
  final db = sqlite3.open(dbName);
  final body = await req.readAsString();
  final now = DateTime.now().toIso8601String();
  final data = jsonDecode(body) as Map<String, dynamic>;
  db.execute('''
    INSERT INTO todos (title, body, file, metadata, created_at, updated_at, completed_at)
    VALUES (?, ?, ?, ?, ?, ?, ?);
  ''', [
    data['title'],
    data['body'],
    data['file'],
    jsonEncode(data['metadata']),
    now,
    now,
    (data['completed'] ?? false) ? now : null,
  ]);
  final id = db.lastInsertRowId;
  final rows = db.select('SELECT * FROM todos WHERE id = ?;', [id]);
  db.dispose();
  final responseBody = jsonEncode(serializeTodo(rows.first));
  return Response.ok(responseBody,
      headers: {'ETag': computeEtag(responseBody)});
}

Future<Response> _updateTodo(Request req, String id) async {
  final db = sqlite3.open(dbName);
  final body = await req.readAsString();
  final now = DateTime.now().toIso8601String();
  final data = jsonDecode(body) as Map<String, dynamic>;

  var rows = db.select('SELECT * FROM todos WHERE id = ?;', [id]);

  if (rows.isEmpty) {
    db.dispose();
    return Response.notFound('{"error": "Todo $id not found"}');
  }

  db.execute('''
    UPDATE todos
    SET title = ?, body = ?, file = ?, completed_at = ?, metadata = ?, updated_at = ?
    WHERE id = ?;
  ''', [
    data['title'] ?? rows.first['title'],
    data['body'] ?? rows.first['body'],
    data['file'] ?? rows.first['file'],
    (data['completed'] ?? (rows.first['completed_at'] != null)) ? now : null,
    data['metadata'] != null
        ? jsonEncode(data['metadata'])
        : rows.first['metadata'],
    now,
    id,
  ]);
  rows = db.select('SELECT * FROM todos WHERE id = ?;', [id]);
  db.dispose();
  final responseBody = jsonEncode(serializeTodo(rows.first));
  return Response.ok(responseBody,
      headers: {'ETag': computeEtag(responseBody)});
}

Future<Response> _deleteAllTodos(Request req) async {
  final db = sqlite3.open(dbName);
  db.execute('DELETE FROM todos;');
  db.dispose();
  return Response.ok('');
}

Future<Response> _deleteTodoById(Request req, String id) async {
  final db = sqlite3.open(dbName);
  final rows = db.select('SELECT * FROM todos WHERE id = ?;', [id]);
  if (rows.isEmpty) {
    db.dispose();
    return Response.notFound('{"error": "Todo $id not found"}');
  }
  db.execute('DELETE FROM todos WHERE id = ?;', [id]);
  db.dispose();
  final body = jsonEncode(serializeTodo(rows.first));
  return Response.ok(body, headers: {'ETag': computeEtag(body)});
}

DynamicLibrary _openOnLinux() {
  return DynamicLibrary.open('/lib/x86_64-linux-gnu/libsqlite3.so.0');
}

void main(List<String> args) async {
  open.overrideFor(OperatingSystem.linux, _openOnLinux);
  // Use any available host or container IP (usually `0.0.0.0`).
  final ip = InternetAddress.anyIPv4;

  // Configure a pipeline that logs requests.
  final handler = Pipeline()
      .addMiddleware(logRequests())
      .addMiddleware(accessControlHeaders())
      .addMiddleware(contentTypeHeader())
      .addMiddleware(etagHeader())
      .addHandler(_router.call);

  // For running in containers, we respect the PORT environment variable.
  final port = int.parse(Platform.environment['PORT'] ?? '8080');
  final db = sqlite3.open(dbName);
  db.execute('''
    CREATE TABLE IF NOT EXISTS todos (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      title TEXT NOT NULL,
      body TEXT NULLABLE,
      file TEXT NULLABLE,
      metadata TEXT NULLABLE,
      created_at DATETIME NOT NULL,
      updated_at DATETIME NOT NULL,
      completed_at DATETIME NULLABLE
    );
  ''');
  ProcessSignal.sigint.watch().listen((signal) {
    db.dispose();
    exit(0);
  });
  final server = await serve(handler, ip, port);
  print('Server listening on port ${server.port}');
  db.dispose();
}
