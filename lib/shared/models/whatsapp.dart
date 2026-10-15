import 'models.dart';

/// A customer's WhatsApp chat (one per number).
class WaChat {
  WaChat({
    required this.phone,
    required this.key,
    required this.title,
    this.profileName,
    this.partyKind,
    this.partyDoctype,
    this.partyId,
    this.partyName,
    this.ownerName,
    this.lastMessage,
    this.lastMessageAt,
    this.lastDirection,
    this.unread = 0,
    this.windowOpen = false,
    this.windowClosesAt,
  });

  final String phone; // +918078368600
  final String key; // 918078368600
  final String title;
  final String? profileName;
  final String? partyKind; // Customer | Lead | Deal (null = not in ERPNext)
  final String? partyDoctype;
  final String? partyId;
  final String? partyName;
  final String? ownerName;
  final String? lastMessage;
  final DateTime? lastMessageAt;
  final String? lastDirection; // Incoming | Outgoing
  final int unread;
  final bool windowOpen; // free text allowed (customer wrote in the last 24 hours)
  final DateTime? windowClosesAt;

  bool get inErp => partyId != null;

  factory WaChat.fromJson(Map<String, dynamic> j) {
    final party = j['party'] is Map ? Map<String, dynamic>.from(j['party'] as Map) : null;
    return WaChat(
      phone: j['phone']?.toString() ?? '',
      key: j['key']?.toString() ?? '',
      title: j['title']?.toString() ?? j['phone']?.toString() ?? '',
      profileName: str(j['profile_name']),
      partyKind: str(party?['kind']),
      partyDoctype: str(party?['doctype']),
      partyId: str(party?['id']),
      partyName: str(party?['name']),
      ownerName: str(j['owner_name']),
      lastMessage: str(j['last_message']),
      lastMessageAt: parseDate(j['last_message_at']),
      lastDirection: str(j['last_direction']),
      unread: (j['unread'] as num?)?.toInt() ?? 0,
      windowOpen: j['window_open'] == true,
      windowClosesAt: parseDate(j['window_closes_at']),
    );
  }
}

class WaMedia {
  WaMedia({required this.kind, this.ext, this.name});
  final String kind; // image | audio | video | document
  final String? ext;
  final String? name;

  factory WaMedia.fromJson(Map<String, dynamic> j) =>
      WaMedia(kind: j['kind']?.toString() ?? 'document', ext: str(j['ext']), name: str(j['name']));
}

class WaMessage {
  WaMessage({
    required this.id,
    required this.incoming,
    required this.kind,
    this.text,
    this.template,
    this.templateText,
    this.media,
    this.status,
    this.at,
    this.waId,
    this.replyTo,
    this.by,
    this.localPath,
    this.pending = false,
    this.error,
  });

  final String id;
  final bool incoming;
  final String kind; // text | template | image | audio | video | document | reaction | ...
  final String? text;
  final String? template;
  final String? templateText;
  final WaMedia? media;
  final String? status; // sent | delivered | read | failed
  final DateTime? at;
  final String? waId;
  final String? replyTo;
  final String? by;
  // Messages being sent from this phone (not on the server yet).
  final String? localPath;
  final bool pending;
  final String? error;

  factory WaMessage.fromJson(Map<String, dynamic> j) => WaMessage(
        id: j['id'].toString(),
        incoming: j['direction'] == 'in',
        kind: j['kind']?.toString() ?? 'text',
        text: str(j['text']),
        template: str(j['template']),
        templateText: str(j['template_text']),
        media: j['media'] is Map ? WaMedia.fromJson(Map<String, dynamic>.from(j['media'] as Map)) : null,
        status: str(j['status']),
        at: parseDate(j['at']),
        waId: str(j['wa_id']),
        replyTo: str(j['reply_to']),
        by: str(j['by']),
      );
}

class WaThread {
  WaThread(this.chat, this.messages, this.hasMore);
  final WaChat chat;
  final List<WaMessage> messages;
  final bool hasMore;

  factory WaThread.fromJson(Map<String, dynamic> j) => WaThread(
        WaChat.fromJson(Map<String, dynamic>.from(j['chat'] as Map)),
        ((j['messages'] as List?) ?? const []).map((e) => WaMessage.fromJson(Map<String, dynamic>.from(e as Map))).toList(),
        j['has_more'] == true,
      );
}

class WaTemplate {
  WaTemplate({
    required this.id,
    required this.title,
    required this.body,
    this.category,
    this.language,
    this.headerType,
    this.headerText,
    this.params = 0,
    this.samples = const [],
    this.suggested = const [],
    this.hasDefaultHeader = false,
  });

  final String id;
  final String title;
  final String body;
  final String? category;
  final String? language;
  final String? headerType; // IMAGE | DOCUMENT | TEXT
  final String? headerText;
  final int params;
  final List<String> samples;
  final List<String> suggested;
  final bool hasDefaultHeader;

  bool get needsPicture => headerType == 'IMAGE' || headerType == 'DOCUMENT';

  String preview(List<String> values) {
    var out = body;
    for (var i = 0; i < params; i++) {
      final v = i < values.length && values[i].trim().isNotEmpty ? values[i].trim() : '{{${i + 1}}}';
      out = out.replaceAll('{{${i + 1}}}', v);
    }
    return out;
  }

  factory WaTemplate.fromJson(Map<String, dynamic> j) {
    List<String> list(String k) => ((j[k] as List?) ?? const []).map((e) => e?.toString() ?? '').toList();
    return WaTemplate(
      id: j['id'].toString(),
      title: j['title']?.toString() ?? j['id'].toString(),
      body: j['body']?.toString() ?? '',
      category: str(j['category']),
      language: str(j['language']),
      headerType: str(j['header_type']),
      headerText: str(j['header_text']),
      params: (j['params'] as num?)?.toInt() ?? 0,
      samples: list('samples'),
      suggested: list('suggested'),
      hasDefaultHeader: j['has_default_header'] == true,
    );
  }
}
