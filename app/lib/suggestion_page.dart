import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'l10n.dart';

class SuggestionPage extends StatefulWidget {
  const SuggestionPage({super.key, required this.token});

  final String token;

  @override
  State<SuggestionPage> createState() => _SuggestionPageState();
}

class _SuggestionPageState extends State<SuggestionPage> {
  static const _apiBase = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://api.damumu.com/api/v1',
  );
  final _input = TextEditingController();
  late Future<List<Map<String, dynamic>>> _items = _load();
  bool _sending = false;

  Uri get _endpoint => Uri.parse('$_apiBase/me/suggestions');
  Map<String, String> get _headers => {
    'Authorization': 'Bearer ${widget.token}',
    'Content-Type': 'application/json',
  };

  Future<List<Map<String, dynamic>>> _load() async {
    final response = await http
        .get(_endpoint, headers: _headers)
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) throw const FormatException();
    final data = jsonDecode(utf8.decode(response.bodyBytes))['data'] as List;
    return data.map((row) => (row as Map).cast<String, dynamic>()).toList();
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    FocusScope.of(context).unfocus();
    setState(() => _sending = true);
    try {
      final response = await http
          .post(_endpoint, headers: _headers, body: jsonEncode({'text': text}))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 201) throw const FormatException();
      if (!mounted) return;
      _input.clear();
      setState(() => _items = _load());
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.tr('suggestionSent'))));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(context.tr('suggestionFailed'))));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(context.tr('suggestions'))),
    body: RefreshIndicator(
      onRefresh: () async {
        setState(() => _items = _load());
        try {
          await _items;
        } catch (_) {
          /* Render the retry state below. */
        }
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        children: [
          Text(context.tr('suggestionIntro')),
          const SizedBox(height: 14),
          TextField(
            controller: _input,
            enabled: !_sending,
            minLines: 3,
            maxLines: 6,
            maxLength: 1000,
            decoration: InputDecoration(hintText: context.tr('suggestionHint')),
          ),
          ListenableBuilder(
            listenable: _input,
            builder: (context, _) => FilledButton(
              onPressed: _sending || _input.text.trim().isEmpty ? null : _send,
              child: Text(context.tr('suggestionSubmit')),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            context.tr('suggestionHistory'),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          FutureBuilder(
            future: _items,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return TextButton(
                  onPressed: () => setState(() => _items = _load()),
                  child: Text(context.tr('suggestionFailed')),
                );
              }
              final rows = snapshot.data ?? const [];
              if (rows.isEmpty) return Text(context.tr('suggestionEmpty'));
              return Column(
                children: [
                  for (final row in rows)
                    Card(
                      child: ListTile(
                        title: Text(row['body'] as String),
                        subtitle: row['reply'] is String
                            ? Text(
                                '${context.tr('suggestionReply')} · ${row['reply']}',
                              )
                            : Text(context.tr('suggestionPending')),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    ),
  );
}
