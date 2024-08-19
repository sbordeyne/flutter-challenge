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
        cache[request.url.toString()] = response;
        return response;
      };
    };

// Configure routes.
final _router = Router()
  ..get('/', _getAllTodos)
  ..get('/<id>', _getTodoById)
  ..post('/', _createTodo)
  ..post('/batch', _createMultipleTodos)
  ..post('/query', _executeQuery)
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
  late final ResultSet rows;
  final db = sqlite3.open(dbName);
  final queryParams = req.url.queryParameters;
  if (queryParams.isEmpty) {
    rows = db.select('SELECT * FROM todos;');
  } else {
    // has query params, filter with them
    // query params available: is_completed: bool, title_contains: string, body_contains: string,
    // has_file: bool, created_before: datetime, created_after: datetime,
    // updated_before: datetime, updated_after: datetime, completed_before: datetime, completed_after: datetime
    final List<String> where = [];
    if (queryParams.containsKey('is_completed')) {
      where.add(
          'completed_at IS ${queryParams['is_completed'] == 'true' ? 'NOT ' : ''}NULL');
    }
    if (queryParams.containsKey('title_contains')) {
      where.add('title LIKE "%${queryParams['title_contains']}%"');
    }
    if (queryParams.containsKey('body_contains')) {
      where.add('body LIKE "%${queryParams['body_contains']}%"');
    }
    if (queryParams.containsKey('has_file')) {
      where.add(
          'file IS ${queryParams['has_file'] == 'true' ? 'NOT ' : ''}NULL');
    }
    if (queryParams.containsKey('created_before')) {
      where.add('created_at < "${queryParams['created_before']}"');
    }
    if (queryParams.containsKey('created_after')) {
      where.add('created_at > "${queryParams['created_after']}"');
    }
    if (queryParams.containsKey('updated_before')) {
      where.add('updated_at < "${queryParams['updated_before']}"');
    }
    if (queryParams.containsKey('updated_after')) {
      where.add('updated_at > "${queryParams['updated_after']}"');
    }
    if (queryParams.containsKey('completed_before')) {
      where.add('completed_at < "${queryParams['completed_before']}"');
    }
    if (queryParams.containsKey('completed_after')) {
      where.add('completed_at > "${queryParams['completed_after']}"');
    }
    if (queryParams.containsKey('priority')) {
      where.add('priority = ${queryParams['priority']}');
    }
    if (queryParams.containsKey('priority_gt')) {
      where.add('priority > ${queryParams['priority_gt']}');
    }
    if (queryParams.containsKey('priority_gte')) {
      where.add('priority >= ${queryParams['priority_gte']}');
    }
    if (queryParams.containsKey('priority_lt')) {
      where.add('priority < ${queryParams['priority_lt']}');
    }
    if (queryParams.containsKey('priority_lte')) {
      where.add('priority <= ${queryParams['priority_lte']}');
    }
    final whereClause = where.join(' AND ');
    print('SELECT * FROM todos WHERE $whereClause;');
    rows = db.select('SELECT * FROM todos WHERE $whereClause;');
  }
  db.dispose();
  if (rows.isEmpty) {
    return Response.ok('[]', headers: {'ETag': computeEtag('[]')});
  }
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
    INSERT INTO todos (title, body, file, metadata, created_at, updated_at, completed_at, priority)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?);
  ''', [
    data['title'],
    data['body'],
    data['file'],
    jsonEncode(data['metadata']),
    now,
    now,
    (data['completed'] ?? false) ? now : null,
    data['priority'] ?? 3,
  ]);
  final id = db.lastInsertRowId;
  final rows = db.select('SELECT * FROM todos WHERE id = ?;', [id]);
  db.dispose();
  final responseBody = jsonEncode(serializeTodo(rows.first));
  return Response.ok(responseBody,
      headers: {'ETag': computeEtag(responseBody)});
}

Future<Response> _createMultipleTodos(Request req) async {
  final db = sqlite3.open(dbName);
  final body = await req.readAsString();
  final now = DateTime.now().toIso8601String();
  final data = jsonDecode(body) as List<dynamic>;
  final values = data.map((d) {
    return [
      d['title'],
      d['body'],
      d['file'],
      jsonEncode(d['metadata']),
      now,
      now,
      (d['completed'] ?? false) ? now : null,
      d['priority'] ?? 3,
    ];
  }).toList();
  final placeholders =
      List.filled(values.length, '(?, ?, ?, ?, ?, ?, ?, ?)').join(',');
  final flatValues = values.expand((v) => v).toList();
  final fromId = db.lastInsertRowId;
  db.execute('''
    INSERT INTO todos (title, body, file, metadata, created_at, updated_at, completed_at, priority)
    VALUES $placeholders;
  ''', flatValues);
  final toId = db.lastInsertRowId;
  final ids =
      List.generate(toId - fromId + 1, (i) => (i + 1).toString()).join(',');
  final rows = db.select('SELECT * FROM todos WHERE id IN ($ids);');
  db.dispose();
  final responseBody = jsonEncode(rows.map((r) => serializeTodo(r)).toList());
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
    SET title = ?, body = ?, file = ?, completed_at = ?, metadata = ?, updated_at = ?, priority = ?
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
    data['priority'] ?? rows.first['priority'],
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

Future<Response> _executeQuery(Request req) async {
  final db = sqlite3.open(dbName);
  final body = await req.readAsString();
  final data = jsonDecode(body) as Map<String, dynamic>;
  final rows = db.select(data['query'], data['values']);
  db.dispose();
  if (rows.isEmpty) {
    return Response.ok('[]', headers: {'ETag': computeEtag('[]')});
  }
  final responseBody = jsonEncode(rows.map((r) => serializeTodo(r)).toList());
  return Response.ok(
    responseBody,
    headers: {'ETag': computeEtag(responseBody)},
  );
}

DynamicLibrary _openOnLinux() {
  return DynamicLibrary.open('/lib/x86_64-linux-gnu/libsqlite3.so.0');
}

void main(List<String> args) async {
  final inContainer = Platform.environment.containsKey('IS_CONTAINER') &&
      Platform.environment['IS_CONTAINER'] == 'true';
  if (inContainer) {
    open.overrideFor(OperatingSystem.linux, _openOnLinux);
  }
  // Use any available host or container IP (usually `0.0.0.0`).
  final ip = InternetAddress.anyIPv4;

  // Configure a pipeline that logs requests.
  final handler = Pipeline()
      .addMiddleware(logRequests())
      .addMiddleware(accessControlHeaders())
      .addMiddleware(contentTypeHeader())
      // .addMiddleware(etagHeader())
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
      priority INTEGER DEFAULT 3,
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
  print(
      'Server listening${inContainer ? ' (in container)' : ''} on port ${server.port}');
  db.dispose();
}
