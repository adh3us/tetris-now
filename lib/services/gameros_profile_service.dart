import 'dart:math';
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
  final String? codigoJugador;

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
    this.codigoJugador,
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
    String? codigoJugador;

    // 1. Consultar tabla 'usuarios' en public (Gameros Core)
    try {
      final userRow = await supabase
          .from('usuarios')
          .select()
          .eq('id', user.id)
          .maybeSingle();

      if (userRow != null) {
        displayName = userRow['nombre_display'] ?? displayName;
        username = userRow['username'] ?? username;
        avatarUrl = userRow['foto_url'] ?? avatarUrl;
        codigoJugador = userRow['codigo_jugador'] as String?;

        // Si ya existe pero aún no tiene código de amigo, se lo generamos y guardamos
        if (codigoJugador == null || codigoJugador.trim().isEmpty) {
          codigoJugador = await _generateUniquePlayerCode();
          try {
            await supabase.from('usuarios').update({
              'codigo_jugador': codigoJugador,
            }).eq('id', user.id);
          } catch (_) {}
        }
      } else {
        // Auto-registro en GamerOS: el usuario se creó en Tetris Now
        // pero nunca en GamerOS. Lo sincronizamos automáticamente en public.usuarios.
        codigoJugador = await _generateUniquePlayerCode();
        final defaultUsername = username ?? (user.email?.split('@').first ?? 'jugador');
        try {
          await supabase.from('usuarios').insert({
            'id': user.id,
            'nombre_display': displayName,
            'username': defaultUsername,
            'foto_url': avatarUrl,
            'codigo_jugador': codigoJugador,
          });
          username = defaultUsername;
        } catch (_) {
          try {
            await supabase.from('usuarios').upsert({
              'id': user.id,
              'nombre_display': displayName,
              'codigo_jugador': codigoJugador,
            });
          } catch (_) {}
        }
      }
    } catch (_) {}

    // 2. Consultar Clan en Gameros Core (public.clanes / public.miembros_clan)
    try {
      final memberRow = await supabase
          .from('miembros_clan')
          .select('clan_id, clanes(nombre)')
          .eq('usuario_id', user.id)
          .eq('estado', 'activo')
          .maybeSingle();

      if (memberRow != null && memberRow['clanes'] != null) {
        final clan = memberRow['clanes'];
        clanName = clan['nombre'] as String?;
      }
    } catch (_) {}

    // 3. Consultar rating ELO propio en esquema tetris (asegura fila inicial)
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
      } else {
        try {
          await supabase.schema('tetris').from('ratings').insert({
            'user_id': user.id,
            'rating': 1000,
            'matches_played': 0,
            'wins': 0,
            'losses': 0,
          });
        } catch (_) {}
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
      codigoJugador: codigoJugador,
    );
  }

  /// Genera un código alfanumérico único de 6 caracteres (ej: K7N9P2) para el sistema de amigos
  Future<String> _generateUniquePlayerCode() async {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rng = Random();
    for (int attempt = 0; attempt < 5; attempt++) {
      final code = List.generate(6, (_) => chars[rng.nextInt(chars.length)]).join();
      try {
        final existing = await supabase
            .from('usuarios')
            .select('id')
            .eq('codigo_jugador', code)
            .maybeSingle();
        if (existing == null) {
          return code;
        }
      } catch (_) {
        return code;
      }
    }
    return List.generate(6, (_) => chars[rng.nextInt(chars.length)]).join();
  }
}
