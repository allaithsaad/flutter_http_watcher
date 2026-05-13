import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_http_watcher/network_inspector.dart';

final navigatorKey = GlobalKey<NavigatorState>();

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Network Inspector Demo',
      navigatorKey: navigatorKey,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      builder: (context, child) => HttpWatcherOverlay(
        navigatorKey: navigatorKey,
        child: child!,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _client = HttpWatcherClient();
  final List<String> _results = [];
  bool _loading = false;

  Future<void> _fetch(String label, Uri uri) async {
    setState(() => _loading = true);
    try {
      final res = await _client.get(uri);
      final decoded = jsonDecode(res.body);
      final preview = decoded is List
          ? '${decoded.length} items'
          : (decoded as Map)
              .entries
              .take(2)
              .map((e) => '${e.key}: ${e.value}')
              .join(', ');
      setState(
          () => _results.insert(0, '[$label] ${res.statusCode} — $preview'));
    } catch (e) {
      setState(() => _results.insert(0, '[$label] Error: $e'));
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _post() async {
    setState(() => _loading = true);
    try {
      final res = await _client.post(
        Uri.parse('https://jsonplaceholder.typicode.com/posts'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'title': 'Hello', 'body': 'World', 'userId': 1}),
      );
      final decoded = jsonDecode(res.body) as Map;
      setState(() => _results
          .insert(0, '[POST /posts] ${res.statusCode} — id: ${decoded['id']}'));
    } catch (e) {
      setState(() => _results.insert(0, '[POST /posts] Error: $e'));
    } finally {
      setState(() => _loading = false);
    }
  }

  static const _endpoints = [
    ('GET /posts', 'https://jsonplaceholder.typicode.com/posts'),
    ('GET /post/1', 'https://jsonplaceholder.typicode.com/posts/1'),
    ('GET /users', 'https://jsonplaceholder.typicode.com/users'),
    ('GET /todos', 'https://jsonplaceholder.typicode.com/todos?_limit=5'),
    ('GET /comments', 'https://jsonplaceholder.typicode.com/comments?postId=1'),
    ('GET 404', 'https://jsonplaceholder.typicode.com/posts/99999'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Network Inspector Demo'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (label, url) in _endpoints)
                  FilledButton.tonal(
                    onPressed:
                        _loading ? null : () => _fetch(label, Uri.parse(url)),
                    child:
                        Text(label, style: const TextStyle(fontSize: 12)),
                  ),
                FilledButton(
                  onPressed: _loading ? null : _post,
                  child: const Text('POST /posts',
                      style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ),
          if (_loading) const LinearProgressIndicator(),
          const Divider(height: 1),
          Expanded(
            child: _results.isEmpty
                ? const Center(
                    child: Text(
                      'Tap a button to make a request.\nWatch the floating inspector button.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.black54),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: _results.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (_, i) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Text(_results[i],
                          style: const TextStyle(fontSize: 13)),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
