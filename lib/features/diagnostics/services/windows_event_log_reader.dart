import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;

import '../models/windows_events.dart';
import 'windows_event_collector.dart';

/// Τι ζητάμε από τα ημερολόγια των Windows. Απλά δεδομένα, ώστε να περνούν
/// στο νήμα της ανάγνωσης.
class WindowsEventsRequest {
  const WindowsEventsRequest({
    required this.station,
    required this.from,
    required this.to,
    required this.levels,
    required this.appExecutable,
  });

  final String station;

  /// Πρώτη ημέρα (ολόκληρη).
  final DateTime from;

  /// Τελευταία ημέρα (ολόκληρη).
  final DateTime to;

  final Set<WindowsEventLevel> levels;
  final String appExecutable;
}

/// Διαβάζει τα ημερολόγια Application και System **αυτού** του υπολογιστή.
///
/// Τρέχει σε δικό του νήμα: χιλιάδες συμβάντα θέλουν ένα-δυο δευτερόλεπτα, και
/// η οθόνη δεν επιτρέπεται να παγώσει στο μεταξύ. Η ανάγνωση των δύο αυτών
/// ημερολογίων δεν χρειάζεται δικαιώματα διαχειριστή· όταν όμως κάτι την
/// εμποδίσει (πολιτική τομέα, προστασία από ιούς), η εξαγωγή γίνεται κανονικά
/// και η αιτία γράφεται στο αρχείο — ποτέ δεν ρίχνει την εξαγωγή.
Future<WindowsEventsReport> readWindowsEvents(
  WindowsEventsRequest request, {
  Duration timeout = const Duration(minutes: 2),
}) async {
  try {
    return await Isolate.run(
      () => readWindowsEventsSync(request),
    ).timeout(timeout);
  } on Object catch (error) {
    return _failed(request, 'Η ανάγνωση των συμβάντων διέκοψε: $error');
  }
}

/// Το όνομα του εκτελέσιμου που τρέχει τώρα — αυτό ψάχνουμε στα συμβάντα.
String currentExecutableName() => p.basename(Platform.resolvedExecutable);

WindowsEventsReport _failed(WindowsEventsRequest request, String why) =>
    WindowsEventsReport(
      station: request.station,
      from: request.from,
      to: request.to,
      levels: request.levels,
      appEvents: const [],
      computerLifecycle: const [],
      groups: const [],
      oldestByLog: const {'Application': null, 'System': null},
      failure: why,
    );

/// Η σύγχρονη ανάγνωση — καλείται μόνο μέσα στο νήμα της [readWindowsEvents].
WindowsEventsReport readWindowsEventsSync(WindowsEventsRequest request) {
  if (!Platform.isWindows) {
    return _failed(request, 'Τα συμβάντα υπάρχουν μόνο στα Windows.');
  }
  final api = _EventLogApi();
  final collector = WindowsEventCollector(
    appExecutable: request.appExecutable,
    levels: request.levels,
  );
  final oldest = <String, DateTime?>{};
  final problems = <String>[];
  try {
    for (final log in const ['Application', 'System']) {
      oldest[log] = api.oldestEventTime(log);
      final error = api.scan(
        log,
        _query(log, request),
        (handle, raw) =>
            collector.add(raw, () => api.message(handle, raw) ?? raw.dataText),
      );
      if (error != null) problems.add('$log: $error');
    }
  } finally {
    api.dispose();
  }
  return WindowsEventsReport(
    station: request.station,
    from: request.from,
    to: request.to,
    levels: request.levels,
    appEvents: collector.appEvents,
    computerLifecycle: collector.computerLifecycle,
    groups: collector.groups,
    oldestByLog: oldest,
    failure: problems.isEmpty ? null : problems.join(' · '),
  );
}

/// Το ερώτημα XPath: τα επιλεγμένα επίπεδα, **ή** οι πηγές που μας
/// ενδιαφέρουν σε κάθε επίπεδο, μέσα στην περίοδο.
String _query(String log, WindowsEventsRequest request) {
  final from = request.from.toUtc().toIso8601String();
  final to = request.to.add(const Duration(days: 1)).toUtc().toIso8601String();
  final wanted = <String>[
    for (final level in request.levels) 'Level=${level.code}',
    if (log == 'Application')
      "Provider[@Name='Application Error' or @Name='Application Hang' or "
          "@Name='Windows Error Reporting']",
    if (log == 'System')
      [
        for (final ids in WindowsEventCollector.lifecycleEvents.values)
          for (final id in ids) 'EventID=$id',
      ].join(' or '),
  ];
  return "*[System[(${wanted.join(' or ')}) and "
      "TimeCreated[@SystemTime>='$from' and @SystemTime<'$to']]]";
}

/// Οι λίγες κλήσεις της διεπαφής ημερολογίων των Windows (wevtapi) που
/// χρειαζόμαστε — μόνο ανάγνωση.
class _EventLogApi {
  _EventLogApi() : _lib = DynamicLibrary.open('wevtapi.dll') {
    _evtQuery = _lib
        .lookupFunction<
          IntPtr Function(IntPtr, Pointer<Utf16>, Pointer<Utf16>, Uint32),
          int Function(int, Pointer<Utf16>, Pointer<Utf16>, int)
        >('EvtQuery');
    _evtNext = _lib
        .lookupFunction<
          Int32 Function(
            IntPtr,
            Uint32,
            Pointer<IntPtr>,
            Uint32,
            Uint32,
            Pointer<Uint32>,
          ),
          int Function(int, int, Pointer<IntPtr>, int, int, Pointer<Uint32>)
        >('EvtNext');
    _evtRender = _lib
        .lookupFunction<
          Int32 Function(
            IntPtr,
            IntPtr,
            Uint32,
            Uint32,
            Pointer<Void>,
            Pointer<Uint32>,
            Pointer<Uint32>,
          ),
          int Function(
            int,
            int,
            int,
            int,
            Pointer<Void>,
            Pointer<Uint32>,
            Pointer<Uint32>,
          )
        >('EvtRender');
    _evtClose = _lib.lookupFunction<Int32 Function(IntPtr), int Function(int)>(
      'EvtClose',
    );
    _evtOpenPublisherMetadata = _lib
        .lookupFunction<
          IntPtr Function(
            IntPtr,
            Pointer<Utf16>,
            Pointer<Utf16>,
            Uint32,
            Uint32,
          ),
          int Function(int, Pointer<Utf16>, Pointer<Utf16>, int, int)
        >('EvtOpenPublisherMetadata');
    _evtFormatMessage = _lib
        .lookupFunction<
          Int32 Function(
            IntPtr,
            IntPtr,
            Uint32,
            Uint32,
            Pointer<Void>,
            Uint32,
            Uint32,
            Pointer<Utf16>,
            Pointer<Uint32>,
          ),
          int Function(
            int,
            int,
            int,
            int,
            Pointer<Void>,
            int,
            int,
            Pointer<Utf16>,
            Pointer<Uint32>,
          )
        >('EvtFormatMessage');
  }

  static const int _queryChannelPath = 0x1;
  static const int _queryForward = 0x100;
  static const int _renderEventXml = 1;
  static const int _formatMessageEvent = 1;
  static const int _infinite = 0xFFFFFFFF;
  static const int _batch = 64;

  final DynamicLibrary _lib;
  late final int Function(int, Pointer<Utf16>, Pointer<Utf16>, int) _evtQuery;
  late final int Function(int, int, Pointer<IntPtr>, int, int, Pointer<Uint32>)
  _evtNext;
  late final int Function(
    int,
    int,
    int,
    int,
    Pointer<Void>,
    Pointer<Uint32>,
    Pointer<Uint32>,
  )
  _evtRender;
  late final int Function(int) _evtClose;
  late final int Function(int, Pointer<Utf16>, Pointer<Utf16>, int, int)
  _evtOpenPublisherMetadata;
  late final int Function(
    int,
    int,
    int,
    int,
    Pointer<Void>,
    int,
    int,
    Pointer<Utf16>,
    Pointer<Uint32>,
  )
  _evtFormatMessage;

  /// Περιγραφές μηνυμάτων ανά πηγή — ανοίγονται μία φορά η καθεμιά.
  final Map<String, int> _publishers = {};

  /// Διατρέχει όσα συμβάντα ταιριάζουν στο [xpath]. Επιστρέφει την αιτία,
  /// αν το ημερολόγιο δεν άνοιξε καθόλου.
  String? scan(
    String log,
    String xpath,
    void Function(int handle, RawWindowsEvent raw) onEvent,
  ) {
    return using((arena) {
      final query = _evtQuery(
        0,
        log.toNativeUtf16(allocator: arena),
        xpath.toNativeUtf16(allocator: arena),
        _queryChannelPath | _queryForward,
      );
      if (query == 0) {
        return 'το ημερολόγιο δεν άνοιξε για ανάγνωση';
      }
      final handles = arena<IntPtr>(_batch);
      final returned = arena<Uint32>();
      try {
        while (_evtNext(query, _batch, handles, _infinite, 0, returned) != 0) {
          for (var i = 0; i < returned.value; i++) {
            final handle = handles[i];
            try {
              final raw = _parse(log, _renderXml(handle));
              if (raw != null) onEvent(handle, raw);
            } finally {
              _evtClose(handle);
            }
          }
        }
      } finally {
        _evtClose(query);
      }
      return null;
    });
  }

  /// Η ώρα του παλαιότερου συμβάντος που κρατούν ακόμη τα Windows.
  DateTime? oldestEventTime(String log) {
    DateTime? oldest;
    scanFirst(log, (raw) => oldest = raw.time);
    return oldest;
  }

  void scanFirst(String log, void Function(RawWindowsEvent raw) onEvent) {
    using((arena) {
      final query = _evtQuery(
        0,
        log.toNativeUtf16(allocator: arena),
        '*'.toNativeUtf16(allocator: arena),
        _queryChannelPath | _queryForward,
      );
      if (query == 0) return;
      final handle = arena<IntPtr>();
      final returned = arena<Uint32>();
      try {
        if (_evtNext(query, 1, handle, _infinite, 0, returned) != 0 &&
            returned.value == 1) {
          try {
            final raw = _parse(log, _renderXml(handle.value));
            if (raw != null) onEvent(raw);
          } finally {
            _evtClose(handle.value);
          }
        }
      } finally {
        _evtClose(query);
      }
    });
  }

  String _renderXml(int handle) {
    return using((arena) {
      final used = arena<Uint32>();
      final count = arena<Uint32>();
      _evtRender(0, handle, _renderEventXml, 0, nullptr, used, count);
      final size = used.value;
      if (size == 0) return '';
      final buffer = arena<Uint8>(size);
      if (_evtRender(
            0,
            handle,
            _renderEventXml,
            size,
            buffer.cast(),
            used,
            count,
          ) ==
          0) {
        return '';
      }
      return buffer.cast<Utf16>().toDartString(length: size ~/ 2 - 1);
    });
  }

  /// Το μήνυμα του συμβάντος όπως το δείχνει η Προβολή συμβάντων, στη γλώσσα
  /// των Windows. `null` όταν η πηγή δεν δίνει περιγραφή.
  String? message(int handle, RawWindowsEvent raw) {
    final publisher = _publishers.putIfAbsent(
      raw.provider,
      () => using(
        (arena) => _evtOpenPublisherMetadata(
          0,
          raw.provider.toNativeUtf16(allocator: arena),
          nullptr,
          0,
          0,
        ),
      ),
    );
    if (publisher == 0) return null;
    return using((arena) {
      final used = arena<Uint32>();
      _evtFormatMessage(
        publisher,
        handle,
        0,
        0,
        nullptr,
        _formatMessageEvent,
        0,
        nullptr,
        used,
      );
      final chars = used.value;
      if (chars == 0) return null;
      final buffer = arena<Uint16>(chars);
      final ok = _evtFormatMessage(
        publisher,
        handle,
        0,
        0,
        nullptr,
        _formatMessageEvent,
        chars,
        buffer.cast(),
        used,
      );
      if (ok == 0) return null;
      // Τα Windows σημαδεύουν τις ημερομηνίες με αόρατους χαρακτήρες
      // κατεύθυνσης κειμένου· στο αρχείο δεν προσθέτουν τίποτα.
      final text = buffer
          .cast<Utf16>()
          .toDartString(length: chars - 1)
          .replaceAll(RegExp('[‎‏]'), '')
          .trim();
      return text.isEmpty ? null : text;
    });
  }

  void dispose() {
    for (final publisher in _publishers.values) {
      if (publisher != 0) _evtClose(publisher);
    }
    _publishers.clear();
  }

  static final _provider = RegExp(r'''<Provider Name=['"]([^'"]*)['"]''');
  static final _eventId = RegExp(r'<EventID[^>]*>(\d+)</EventID>');
  static final _level = RegExp(r'<Level>(\d+)</Level>');
  static final _time = RegExp(r'''<TimeCreated SystemTime=['"]([^'"]+)['"]''');
  static final _data = RegExp(r'<Data(?: [^>]*)?>([^<]*)</Data>');

  static RawWindowsEvent? _parse(String log, String xml) {
    final provider = _provider.firstMatch(xml)?.group(1);
    final id = int.tryParse(_eventId.firstMatch(xml)?.group(1) ?? '');
    final time = DateTime.tryParse(_time.firstMatch(xml)?.group(1) ?? '');
    if (provider == null || id == null || time == null) return null;
    final level = int.tryParse(_level.firstMatch(xml)?.group(1) ?? '') ?? 4;
    final data = _data
        .allMatches(xml)
        .map((m) => _unescape(m.group(1) ?? '').trim())
        .where((value) => value.isNotEmpty)
        .join(' | ');
    return RawWindowsEvent(
      log: log,
      provider: provider,
      eventId: id,
      level: WindowsEventLevel.ofCode(level),
      time: time.toLocal(),
      dataText: data,
    );
  }

  static String _unescape(String text) => text
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&amp;', '&');
}
