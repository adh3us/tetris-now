import 'dart:async';
import 'package:app_links/app_links.dart';

class DeepLinkPayload {
  final String? matchId;
  final String? tournamentId;
  final String? torneoPartidaId;
  final String? myInscripcionId;
  final String? opponentInscripcionId;

  DeepLinkPayload({
    this.matchId,
    this.tournamentId,
    this.torneoPartidaId,
    this.myInscripcionId,
    this.opponentInscripcionId,
  });
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
    // Formato oficial: gameros-tetris://partida/<id> o gameros-tetris://torneo?partida_id=<id>
    if (uri.scheme == 'gameros-tetris') {
      if (uri.host == 'partida') {
        final matchId = uri.pathSegments.isNotEmpty ? uri.pathSegments.first : uri.queryParameters['id'];
        final tournamentId = uri.queryParameters['tournament_id'] ?? uri.queryParameters['torneo_id'];
        final torneoPartidaId = uri.queryParameters['torneo_partida_id'] ?? uri.queryParameters['partida_id'];
        final myInsc = uri.queryParameters['insc_propia'] ?? uri.queryParameters['inscripcion_propia'];
        final oppInsc = uri.queryParameters['insc_rival'] ?? uri.queryParameters['inscripcion_rival'];
        if (matchId != null && matchId.isNotEmpty) {
          _deepLinkController.add(DeepLinkPayload(
            matchId: matchId,
            tournamentId: tournamentId,
            torneoPartidaId: torneoPartidaId,
            myInscripcionId: myInsc,
            opponentInscripcionId: oppInsc,
          ));
        }
      } else if (uri.host == 'torneo') {
        final torneoPartidaId = uri.queryParameters['partida_id'] ?? (uri.pathSegments.isNotEmpty ? uri.pathSegments.first : null);
        final tournamentId = uri.queryParameters['torneo_id'] ?? uri.queryParameters['tournament_id'];
        final myInsc = uri.queryParameters['insc_propia'] ?? uri.queryParameters['inscripcion_propia'];
        final oppInsc = uri.queryParameters['insc_rival'] ?? uri.queryParameters['inscripcion_rival'];
        if (torneoPartidaId != null && torneoPartidaId.isNotEmpty) {
          _deepLinkController.add(DeepLinkPayload(
            matchId: torneoPartidaId,
            tournamentId: tournamentId,
            torneoPartidaId: torneoPartidaId,
            myInscripcionId: myInsc,
            opponentInscripcionId: oppInsc,
          ));
        }
      }
    }
  }

  void dispose() {
    _linkSubscription?.cancel();
    _deepLinkController.close();
  }
}
