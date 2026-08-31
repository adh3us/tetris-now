import 'dart:async';
import 'package:app_links/app_links.dart';

class DeepLinkPayload {
  final String? matchId;

  DeepLinkPayload({this.matchId});
}

class DeepLinkService {
  static final DeepLinkService _instance = DeepLinkService._internal();
  factory DeepLinkService() => _instance;
  DeepLinkService._internal();

  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _linkSubscription;

  final StreamController<DeepLinkPayload> _deepLinkController = StreamController<DeepLinkPayload>.broadcast();
  Stream<DeepLinkPayload> get onDeepLink => _deepLinkController.stream;

  Future<void> initialize() async {
    // 1. Cold Start
    try {
      final initialUri = await _appLinks.getInitialLink();
      if (initialUri != null) {
        _processUri(initialUri);
      }
    } catch (_) {}

    // 2. Warm Start
    _linkSubscription = _appLinks.uriLinkStream.listen(
      (uri) {
        _processUri(uri);
      },
      onError: (_) {},
    );
  }

  void _processUri(Uri uri) {
    // Formato oficial: gameros-tetris://partida/<id>
    if (uri.scheme == 'gameros-tetris' && uri.host == 'partida') {
      final matchId = uri.pathSegments.isNotEmpty ? uri.pathSegments.first : uri.queryParameters['id'];
      if (matchId != null && matchId.isNotEmpty) {
        _deepLinkController.add(DeepLinkPayload(matchId: matchId));
      }
    }
  }

  void dispose() {
    _linkSubscription?.cancel();
    _deepLinkController.close();
  }
}
