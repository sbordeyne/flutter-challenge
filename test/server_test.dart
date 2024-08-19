import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:test/test.dart';

void main() async {
  final port = '8080';
  final host = 'http://0.0.0.0:$port';
  group('CRUD', () {
    late Process p;
    setUpAll(() async {
      final db = File('todos.db');
      if (await db.exists()) {
        await db.delete();
      }
      p = await Process.start(
        'dart',
        ['run', 'bin/server.dart'],
        environment: {'PORT': port},
      );
      // Wait for server to start and print to stdout.
      await p.stdout.first;
    });
    tearDownAll(() => p.kill());

    test('GET /', () async {
      final response = await http.get(Uri.parse('$host/'));
      expect(response.statusCode, 200);
      expect(response.body, '[]');
    });

    test('POST /', () async {
      final response = await http.post(
        Uri.parse('$host/'),
        body: '{"title": "Buy milk"}',
        headers: {'Content-Type': 'application/json'},
      );
      expect(response.statusCode, 200);
      expect(response.body, contains('Buy milk'));
    });

    test('GET /', () async {
      final response = await http.get(Uri.parse('$host/'));
      expect(response.statusCode, 200);
      expect(response.body, contains('Buy milk'));
    });

    test('PATCH /<id>', () async {
      final response = await http.patch(
        Uri.parse('$host/1'),
        body: '{"title": "Buy milk and bread"}',
        headers: {'Content-Type': 'application/json'},
      );
      expect(response.statusCode, 200);
      expect(response.body, contains('Buy milk and bread'));
    });

    test('DELETE /<id>', () async {
      final response = await http.delete(Uri.parse('$host/1'));
      expect(response.statusCode, 200);
      expect(response.body, contains('Buy milk and bread'));
    });

    test('GET /', () async {
      final response = await http.get(Uri.parse('$host/'));
      expect(response.statusCode, 200);
      expect(response.body, '[]');
    });
  });

  group('list filters', () {
    late Process p;
    late DateTime start;
    late DateTime afterMilk;
    late DateTime afterBread;
    late DateTime end;

    setUpAll(() async {
      final db = File('todos.db');
      if (await db.exists()) {
        await db.delete();
      }
      p = await Process.start(
        'dart',
        ['run', 'bin/server.dart'],
        environment: {'PORT': port},
      );
      // Wait for server to start and print to stdout.
      await p.stdout.first;
      start = DateTime.now();
      await http.post(
        Uri.parse('$host/'),
        body:
            '{"title": "Buy milk", "completed": true, "metadata": {"toto": 1}, "priority": 1}',
        headers: {'Content-Type': 'application/json'},
      );
      await Future.delayed(Duration(seconds: 1));
      afterMilk = DateTime.now();
      await http.post(
        Uri.parse('$host/'),
        body:
            '{"title": "Buy bread", "body": "BAGUETTE", "metadata": {"tata": 2}, "priority": 2}',
        headers: {'Content-Type': 'application/json'},
      );
      await Future.delayed(Duration(seconds: 1));
      afterBread = DateTime.now();
      await http.post(
        Uri.parse('$host/'),
        body:
            '{"title": "Buy eggs", "file": "eggs.jpg", "metadata": {"foobar": 3}, "priority": 3}',
        headers: {'Content-Type': 'application/json'},
      );
      end = DateTime.now();
    });
    tearDownAll(() => p.kill());

    test('GET /?is_completed=true', () async {
      final response = await http.get(Uri.parse('$host/?is_completed=true'));
      expect(response.statusCode, 200);
      expect(response.body, contains('Buy milk'));
      expect(response.body, isNot(contains('Buy bread')));
      expect(response.body, isNot(contains('Buy eggs')));
    });

    test('GET /?is_completed=false', () async {
      final response = await http.get(Uri.parse('$host/?is_completed=false'));
      expect(response.statusCode, 200);
      expect(response.body, isNot(contains('Buy milk')));
      expect(response.body, contains('Buy bread'));
      expect(response.body, contains('Buy eggs'));
    });

    test('GET /?title_contains=milk', () async {
      final response = await http.get(Uri.parse('$host/?title_contains=milk'));
      expect(response.statusCode, 200);
      expect(response.body, contains('Buy milk'));
      expect(response.body, isNot(contains('Buy bread')));
      expect(response.body, isNot(contains('Buy eggs')));
    });

    test('GET /?title_contains=bread', () async {
      final response = await http.get(Uri.parse('$host/?title_contains=bread'));
      expect(response.statusCode, 200);
      expect(response.body, isNot(contains('Buy milk')));
      expect(response.body, contains('Buy bread'));
      expect(response.body, isNot(contains('Buy eggs')));
    });

    test('GET /?body_contains=BAGUETTE', () async {
      final response =
          await http.get(Uri.parse('$host/?body_contains=baguette'));
      expect(response.statusCode, 200);
      expect(response.body, isNot(contains('Buy milk')));
      expect(response.body, contains('Buy bread'));
      expect(response.body, isNot(contains('Buy eggs')));
    });

    test('GET /?created_after', () async {
      final response = await http
          .get(Uri.parse('$host/?created_after=${start.toIso8601String()}'));
      expect(response.statusCode, 200);
      expect(response.body, contains('Buy milk'));
      expect(response.body, contains('Buy bread'));
      expect(response.body, contains('Buy eggs'));

      final response2 = await http.get(
          Uri.parse('$host/?created_after=${afterMilk.toIso8601String()}'));
      expect(response2.statusCode, 200);
      expect(response2.body, isNot(contains('Buy milk')));
    });

    test('GET /?created_before', () async {
      final response = await http
          .get(Uri.parse('$host/?created_before=${end.toIso8601String()}'));
      expect(response.statusCode, 200);
      expect(response.body, contains('Buy milk'));
      expect(response.body, contains('Buy bread'));
      expect(response.body, contains('Buy eggs'));

      final response2 = await http.get(
          Uri.parse('$host/?created_before=${afterBread.toIso8601String()}'));
      expect(response2.statusCode, 200);
      expect(response2.body, isNot(contains('Buy eggs')));
    });

    test('GET /?priority=1', () async {
      final response = await http.get(Uri.parse('$host/?priority=1'));
      expect(response.statusCode, 200);
      expect(response.body, contains('Buy milk'));
      expect(response.body, isNot(contains('Buy bread')));
      expect(response.body, isNot(contains('Buy eggs')));
    });
  });
}
