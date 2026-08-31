import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/supabase_config.dart';

class GamerosUserProfile {
  final String id;
  final String email;
  final String displayName; // Nombre principal (ej: Rey-ToRuS)
  final String? username;    // Nombre secundario (ej: @ToRuS)
  final String? avatarUrl;
  final int nivel;
  final int reputacion;
  final int tetrisElo;
  final int tetrisMatches;
  final int tetrisWins;
  final int tetrisLosses;
  final String? clanName;
  final String? clanTag;

  GamerosUserProfile({
    required this.id,
    required this.email,
    required this.displayName,
    this.username,
    this.avatarUrl,
    this.nivel = 1,
    this.reputacion = 100,
    this.tetrisElo = 1000,
    this.tetrisMatches = 0,
    this.tetrisWins = 0,
    this.tetrisLosses = 0,
    this.clanName,
    this.clanTag,
  });
}

class GamerosProfileService {
  SupabaseClient get supabase => SupabaseConfig.client;

  Future<GamerosUserProfile?> getFullProfile() async {
    final user = supabase.auth.currentUser;
    if (user == null) return null;

    final meta = user.userMetadata ?? {};
    String displayName = meta['full_name'] ??
        meta['name'] ??
        meta['nombre'] ??
        meta['gamertag'] ??
        user.email?.split('@').first ??
        'Rey-ToRuS';

    String? username = meta['user_name'] ?? meta['username'] ?? meta['alias'];
    String? avatarUrl = meta['avatar_url'] ?? meta['picture'] ?? meta['foto_url'];
    int nivel = 1;
    int reputacion = 100;
    String? clanName;
    String? clanTag;

    // 1. Consultar tabla 'usuarios' en public (Gameros Core)
    try {
      final userRow = await supabase
          .from('usuarios')
          .select()
          .eq('id', user.id)
          .maybeSingle();

      if (userRow != null) {
        // En Gameros: 'nombre' o 'nombre_completo' es Rey-ToRuS, 'username' es @ToRuS
        displayName = userRow['nombre'] ??
            userRow['nombre_completo'] ??
            userRow['display_name'] ??
            userRow['gamertag'] ??
            displayName;

        username = userRow['username'] ??
            userRow['nombre_usuario'] ??
            userRow['alias'] ??
            username;

        avatarUrl = userRow['foto_url'] ??
            userRow['avatar_url'] ??
            userRow['foto'] ??
            avatarUrl;

        nivel = userRow['nivel'] as int? ?? userRow['level'] as int? ?? 1;
        reputacion = userRow['reputacion'] as int? ?? userRow['reputation'] as int? ?? 100;
      }
    } catch (_) {}

    // 2. Consultar Clan / Equipo en Gameros Core
    try {
      final memberRow = await supabase
          .from('miembros_equipo')
          .select('equipos(nombre, tag)')
          .eq('usuario_id', user.id)
          .maybeSingle();

      if (memberRow != null && memberRow['equipos'] != null) {
        final eq = memberRow['equipos'];
        clanName = eq['nombre'] as String?;
        clanTag = eq['tag'] as String?;
      }
    } catch (_) {}

    // 3. Consultar rating ELO propio en esquema tetris
    int elo = 1000;
    int matches = 0;
    int wins = 0;
    int losses = 0;

    try {
      final ratingRow = await supabase
          .schema('tetris')
          .from('ratings')
          .select()
          .eq('user_id', user.id)
          .maybeSingle();

      if (ratingRow != null) {
        elo = ratingRow['rating'] as int? ?? 1000;
        matches = ratingRow['matches_played'] as int? ?? 0;
        wins = ratingRow['wins'] as int? ?? 0;
        losses = ratingRow['losses'] as int? ?? 0;
      }
    } catch (_) {}

    return GamerosUserProfile(
      id: user.id,
      email: user.email ?? '',
      displayName: displayName,
      username: username,
      avatarUrl: avatarUrl,
      nivel: nivel,
      reputacion: reputacion,
      tetrisElo: elo,
      tetrisMatches: matches,
      tetrisWins: wins,
      tetrisLosses: losses,
      clanName: clanName,
      clanTag: clanTag,
    );
  }
}
