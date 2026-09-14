import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/supabase_config.dart';
import 'tetris_match_service.dart';

/// Torneo real de public.torneos (no una tabla propia de Tetris).
class TournamentModel {
  final String id;
  final String nombre;
  final String tipo; // 'individual' | 'equipo'
  final String estado; // 'inscripcion' | 'en_curso' | 'finalizado' | 'cancelado'
  final int? tamanoEquipo;
  final DateTime? createdAt;

  TournamentModel({
    required this.id,
    required this.nombre,
    required this.tipo,
    required this.estado,
    this.tamanoEquipo,
    this.createdAt,
  });

  factory TournamentModel.fromMap(Map<String, dynamic> map) {
    return TournamentModel(
      id: map['id'] as String,
      nombre: map['nombre'] as String? ?? 'Torneo Tetris Now',
      // Columna real confirmada en lib/torneos.dart de Gameros: 'formato'
      // ('individual' | 'equipo'), no 'tipo'.
      tipo: map['formato'] as String? ?? 'individual',
      estado: map['estado'] as String? ?? 'inscripcion',
      tamanoEquipo: map['tamano_equipo'] as int?,
      createdAt: DateTime.tryParse(map['fecha_inicio']?.toString() ?? ''),
    );
  }
}

class TournamentInvitationModel {
  final String id;
  final String torneoId;
  final String tipo; // 'individual' | 'equipo'
  final String? torneoNombre;

  TournamentInvitationModel({
    required this.id,
    required this.torneoId,
    required this.tipo,
    this.torneoNombre,
  });

  factory TournamentInvitationModel.fromMap(Map<String, dynamic> map) {
    // La forma exacta de mis_invitaciones_torneo() puede traer el torneo
    // embebido (map['torneos']) o aplanado (map['torneo_nombre']) según la
    // versión del RPC en Gameros — se contemplan ambas variantes.
    String? nombre;
    final nested = map['torneos'];
    if (nested is Map) {
      nombre = nested['nombre'] as String?;
    }
    nombre ??= map['torneo_nombre'] as String?;

    return TournamentInvitationModel(
      id: map['id'] as String,
      torneoId: map['torneo_id'] as String,
      tipo: map['tipo'] as String? ?? 'individual',
      torneoNombre: nombre,
    );
  }
}

class MyTournamentMatch {
  final String matchId;
  final String? torneoPartidaId;
  final String tournamentId;
  final String myTeamId;
  final String opponentTeamId;
  final String opponentGamerTag;
  final String? myInscripcionId;
  final String? opponentInscripcionId;
  final int roundNumber;
  final String status;

  MyTournamentMatch({
    required this.matchId,
    this.torneoPartidaId,
    required this.tournamentId,
    required this.myTeamId,
    required this.opponentTeamId,
    required this.opponentGamerTag,
    this.myInscripcionId,
    this.opponentInscripcionId,
    this.roundNumber = 1,
    required this.status,
  });
}

class TournamentService {
  final SupabaseClient supabase = SupabaseConfig.client;

  String? _tetrisGameId;

  /// Resuelve el id de "Tetris Now" en public.juegos (no está hardcodeado).
  Future<String?> _getTetrisGameId() async {
    if (_tetrisGameId != null) return _tetrisGameId;
    try {
      final rows = await supabase
          .from('juegos')
          .select('id, nombre')
          .ilike('nombre', '%tetris%')
          .limit(1);
      if (rows is List && rows.isNotEmpty) {
        _tetrisGameId = rows.first['id'] as String?;
      }
    } catch (_) {}
    return _tetrisGameId;
  }

  /// Torneos de Tetris Now abiertos a inscripción o en curso. Lanza una
  /// excepción con un mensaje diagnosticable en vez de tragarse el error,
  /// para poder distinguir "no hay torneos" de "no se encontró el juego" o
  /// "falló la consulta" (RLS, nombre de columna, etc).
  Future<List<TournamentModel>> getTournaments() async {
    final gameId = await _getTetrisGameId();
    if (gameId == null) {
      throw Exception('No se encontró "Tetris Now" en public.juegos (revisar el nombre exacto del juego en Gameros)');
    }

    final res = await supabase
        .from('torneos')
        .select('id, nombre, juego, juego_id, formato, estado, fecha_inicio, tamano_equipo')
        .eq('juego_id', gameId)
        .inFilter('estado', ['inscripcion', 'en_curso'])
        .order('fecha_inicio', ascending: false);

    return (res as List)
        .map((e) => TournamentModel.fromMap(Map<String, dynamic>.from(e)))
        .toList();
  }

  /// Invitaciones directas pendientes del usuario logueado (individuales o
  /// de cualquier clan donde sea líder/co-líder).
  Future<List<TournamentInvitationModel>> getMyInvitations() async {
    try {
      final res = await supabase.rpc('mis_invitaciones_torneo');
      if (res is List) {
        return res
            .map((e) => TournamentInvitationModel.fromMap(Map<String, dynamic>.from(e)))
            .toList();
      }
    } catch (_) {}
    return [];
  }

  Future<bool> respondToInvitation(String invitationId, bool accept) async {
    try {
      await supabase.rpc('responder_invitacion_torneo', params: {
        'p_invitacion_id': invitationId,
        'p_aceptar': accept,
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Inscripción individual directa (no vía invitación). El límite de 2
  /// torneos simultáneos y la validación de admite_individual corren
  /// server-side dentro de esta función.
  Future<bool> inscribirseIndividual(String tournamentId) async {
    try {
      await supabase.rpc('inscribirse_torneo', params: {
        'p_torneo_id': tournamentId,
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Inscripción de equipo (clan). El líder o co-líder inscribe a su clan
  /// pasando el tamaño de equipo requerido por el torneo si corresponde.
  Future<Map<String, dynamic>> inscribirseEquipo({
    required String tournamentId,
    required String clanId,
    int? tamanoEquipo,
  }) async {
    try {
      final res = await supabase.rpc('inscribirse_torneo', params: {
        'p_torneo_id': tournamentId,
        'p_clan_id': clanId,
        if (tamanoEquipo != null) 'p_tamano_equipo': tamanoEquipo,
      });
      return {'success': true, 'data': res};
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Consulta si el usuario actual es líder o co-líder activo de algún clan.
  Future<Map<String, dynamic>?> getClanLiderazgo() async {
    final user = supabase.auth.currentUser;
    if (user == null) return null;
    try {
      final row = await supabase
          .from('miembros_clan')
          .select('clan_id, rol, clanes(nombre)')
          .eq('usuario_id', user.id)
          .eq('estado', 'activo')
          .inFilter('rol', ['lider', 'co_lider'])
          .maybeSingle();

      if (row != null && row['clanes'] != null) {
        final clan = row['clanes'] as Map;
        return {
          'clan_id': row['clan_id'] as String,
          'rol': row['rol'] as String,
          'clan_nombre': clan['nombre'] as String? ?? 'Mi Clan',
        };
      }
    } catch (_) {}
    return null;
  }

  Future<bool> cancelarInscripcion(String tournamentId) async {
    try {
      await supabase.rpc('cancelar_inscripcion', params: {
        'p_torneo_id': tournamentId,
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Cruces/partidas de Tetris ya jugados o programados para este torneo.
  /// Lee primero de tetris.match_tetris con nombres de jugadores; si está
  /// vacío, consulta public.partidas y public.inscripciones_torneo de Gameros.
  Future<List<TetrisMatchModel>> getTournamentMatches(String tournamentId) async {
    try {
      final res = await supabase
          .schema('tetris')
          .from('match_tetris')
          .select('*, match_tetris_players(*)')
          .eq('tournament_id', tournamentId)
          .order('round_number', ascending: true);

      if (res is List && res.isNotEmpty) {
        return res.map((e) {
          final map = Map<String, dynamic>.from(e);
          final players = (map['match_tetris_players'] as List? ?? []);
          String? t1Name;
          String? t2Name;
          for (final p in players) {
            if (p['team_id'] == map['team_1_id']) {
              t1Name = p['gamer_tag'];
            } else if (p['team_id'] == map['team_2_id']) {
              t2Name = p['gamer_tag'];
            }
          }
          if (t1Name != null) map['team_1_id'] = t1Name;
          if (t2Name != null) map['team_2_id'] = t2Name;
          return TetrisMatchModel.fromMap(map);
        }).toList();
      }
    } catch (_) {}

    // Fallback: Consultar public.partidas del torneo de Gameros
    try {
      final partidas = await supabase
          .from('partidas')
          .select('id, torneo_id, ronda, inscripcion_a_id, inscripcion_b_id, estado, ganador_inscripcion_id')
          .eq('torneo_id', tournamentId)
          .order('ronda', ascending: true);

      if (partidas is List && partidas.isNotEmpty) {
        final List<TetrisMatchModel> result = [];
        for (final p in partidas) {
          String nameA = 'Participante A';
          String nameB = 'Participante B';
          final inscA = p['inscripcion_a_id'] as String?;
          final inscB = p['inscripcion_b_id'] as String?;
          final winnerInsc = p['ganador_inscripcion_id'] as String?;

          if (inscA != null) {
            try {
              final rA = await supabase
                  .from('inscripciones_torneo')
                  .select('clanes(nombre), usuarios(nombre, username)')
                  .eq('id', inscA)
                  .maybeSingle();
              if (rA != null) {
                if (rA['clanes'] != null && rA['clanes']['nombre'] != null) {
                  nameA = rA['clanes']['nombre'] as String;
                } else if (rA['usuarios'] != null) {
                  final u = rA['usuarios'] as Map;
                  nameA = (u['nombre'] ?? u['username'] ?? 'Jugador A') as String;
                }
              }
            } catch (_) {}
          }

          if (inscB != null) {
            try {
              final rB = await supabase
                  .from('inscripciones_torneo')
                  .select('clanes(nombre), usuarios(nombre, username)')
                  .eq('id', inscB)
                  .maybeSingle();
              if (rB != null) {
                if (rB['clanes'] != null && rB['clanes']['nombre'] != null) {
                  nameB = rB['clanes']['nombre'] as String;
                } else if (rB['usuarios'] != null) {
                  final u = rB['usuarios'] as Map;
                  nameB = (u['nombre'] ?? u['username'] ?? 'Jugador B') as String;
                }
              }
            } catch (_) {}
          }

          final isFinished = p['estado'] == 'jugada';
          final winnerName = isFinished
              ? (winnerInsc == inscA ? nameA : (winnerInsc == inscB ? nameB : null))
              : null;

          result.add(TetrisMatchModel(
            id: p['id'] as String,
            tournamentId: tournamentId,
            torneoPartidaId: p['id'] as String,
            roundNumber: p['ronda'] as int? ?? 1,
            format: '1v1',
            status: isFinished ? 'finished' : 'pending',
            team1Id: nameA,
            team2Id: nameB,
            winnerTeamId: winnerName,
          ));
        }
        if (result.isNotEmpty) return result;
      }
    } catch (_) {}

    return [];
  }

  /// Busca el próximo cruce pendiente del usuario actual en este torneo.
  /// Revisa primero partidas en tetris.match_tetris; si no existen, consulta
  /// el bracket en public.partidas y public.inscripciones_torneo.
  Future<MyTournamentMatch?> getMyPendingTournamentMatch(String tournamentId) async {
    final currentUserId = supabase.auth.currentUser?.id;
    if (currentUserId == null) return null;

    // 1. Buscar en tetris.match_tetris
    try {
      final matches = await supabase
          .schema('tetris')
          .from('match_tetris')
          .select('*, match_tetris_players(*)')
          .eq('tournament_id', tournamentId)
          .inFilter('status', ['pending', 'in_progress'])
          .order('round_number', ascending: true);

      if (matches is List && matches.isNotEmpty) {
        for (final m in matches) {
          final players = (m['match_tetris_players'] as List? ?? []);
          final myPlayer = players.firstWhere(
            (p) => p['user_id'] == currentUserId,
            orElse: () => null,
          );

          if (myPlayer != null) {
            final myTeamId = myPlayer['team_id'] as String;
            final team1Id = m['team_1_id'] as String;
            final team2Id = m['team_2_id'] as String;
            final opponentTeamId = myTeamId == team1Id ? team2Id : team1Id;
            final opponentPlayer = players.firstWhere(
              (p) => p['team_id'] == opponentTeamId,
              orElse: () => null,
            );
            final opponentTag = opponentPlayer?['gamer_tag'] as String? ?? 'Rival por conectar';

            final insc1 = m['torneo_insc_1'] as String?;
            final insc2 = m['torneo_insc_2'] as String?;
            final myInsc = myTeamId == team1Id ? insc1 : insc2;
            final oppInsc = myTeamId == team1Id ? insc2 : insc1;

            return MyTournamentMatch(
              matchId: m['id'] as String,
              torneoPartidaId: m['torneo_partida_id'] as String? ?? m['tournament_id'] as String?,
              tournamentId: tournamentId,
              myTeamId: myTeamId,
              opponentTeamId: opponentTeamId,
              opponentGamerTag: opponentTag,
              myInscripcionId: myInsc,
              opponentInscripcionId: oppInsc,
              roundNumber: m['round_number'] as int? ?? 1,
              status: m['status'] as String? ?? 'pending',
            );
          }
        }
      }
    } catch (_) {}

    // 2. Fallback a public.partidas y public.inscripciones_torneo
    try {
      final userInsc = await supabase
          .from('inscripciones_torneo')
          .select('id, clan_id')
          .eq('torneo_id', tournamentId)
          .eq('usuario_id', currentUserId);

      List<String> myInscripcionIds = [];
      if (userInsc is List && userInsc.isNotEmpty) {
        myInscripcionIds = userInsc.map((e) => e['id'] as String).toList();
      }

      if (myInscripcionIds.isEmpty) {
        final myClans = await supabase
            .from('miembros_clan')
            .select('clan_id')
            .eq('usuario_id', currentUserId)
            .eq('estado', 'activo');

        if (myClans is List && myClans.isNotEmpty) {
          final clanIds = myClans.map((e) => e['clan_id'] as String).toList();
          final clanInsc = await supabase
              .from('inscripciones_torneo')
              .select('id')
              .eq('torneo_id', tournamentId)
              .inFilter('clan_id', clanIds);

          if (clanInsc is List && clanInsc.isNotEmpty) {
            myInscripcionIds = clanInsc.map((e) => e['id'] as String).toList();
          }
        }
      }

      if (myInscripcionIds.isNotEmpty) {
        final partidas = await supabase
            .from('partidas')
            .select('id, torneo_id, ronda, inscripcion_a_id, inscripcion_b_id, estado')
            .eq('torneo_id', tournamentId)
            .eq('estado', 'pendiente');

        if (partidas is List && partidas.isNotEmpty) {
          for (final p in partidas) {
            final inscA = p['inscripcion_a_id'] as String?;
            final inscB = p['inscripcion_b_id'] as String?;

            final isMyA = myInscripcionIds.contains(inscA);
            final isMyB = myInscripcionIds.contains(inscB);

            if (isMyA || isMyB) {
              final myInscId = isMyA ? inscA : inscB;
              final oppInscId = isMyA ? inscB : inscA;
              final crucePartidaId = p['id'] as String;
              final roundNum = p['ronda'] as int? ?? 1;

              String oppName = 'Rival asignado';
              if (oppInscId != null) {
                try {
                  final oppInscRow = await supabase
                      .from('inscripciones_torneo')
                      .select('usuario_id, clan_id, usuarios(nombre, username), clanes(nombre)')
                      .eq('id', oppInscId)
                      .maybeSingle();

                  if (oppInscRow != null) {
                    if (oppInscRow['clanes'] != null && oppInscRow['clanes']['nombre'] != null) {
                      oppName = oppInscRow['clanes']['nombre'] as String;
                    } else if (oppInscRow['usuarios'] != null) {
                      final u = oppInscRow['usuarios'] as Map;
                      oppName = (u['nombre'] ?? u['username'] ?? 'Rival') as String;
                    }
                  }
                } catch (_) {}
              }

              final existingTetris = await supabase
                  .schema('tetris')
                  .from('match_tetris')
                  .select()
                  .eq('torneo_partida_id', crucePartidaId)
                  .maybeSingle();

              if (existingTetris != null) {
                final t1 = existingTetris['team_1_id'] as String;
                final t2 = existingTetris['team_2_id'] as String;
                final myTeam = isMyA ? t1 : t2;
                final oppTeam = isMyA ? t2 : t1;

                return MyTournamentMatch(
                  matchId: existingTetris['id'] as String,
                  torneoPartidaId: crucePartidaId,
                  tournamentId: tournamentId,
                  myTeamId: myTeam,
                  opponentTeamId: oppTeam,
                  opponentGamerTag: oppName,
                  myInscripcionId: myInscId,
                  opponentInscripcionId: oppInscId,
                  roundNumber: roundNum,
                  status: existingTetris['status'] as String? ?? 'pending',
                );
              }

              return MyTournamentMatch(
                matchId: crucePartidaId,
                torneoPartidaId: crucePartidaId,
                tournamentId: tournamentId,
                myTeamId: 'team_a',
                opponentTeamId: 'team_b',
                opponentGamerTag: oppName,
                myInscripcionId: myInscId,
                opponentInscripcionId: oppInscId,
                roundNumber: roundNum,
                status: 'pending',
              );
            }
          }
        }
      }
    } catch (_) {}

    return null;
  }

  /// Prepara la partida en tetris.match_tetris y registra al jugador en
  /// match_tetris_players para que pueda conectarse vía Realtime y jugar.
  Future<Map<String, dynamic>> prepararOUnirseACruceTorneo(
    MyTournamentMatch cruce, {
    String? gamerTag,
  }) async {
    final user = supabase.auth.currentUser;
    if (user == null) throw Exception('Debes iniciar sesión para jugar tu cruce');
    final tag = gamerTag ??
        user.userMetadata?['gamertag'] ??
        user.userMetadata?['name'] ??
        user.email?.split('@').first ??
        'Gamer';

    final crucePartidaId = cruce.torneoPartidaId ?? cruce.tournamentId;

    Map<String, dynamic>? matchRow;
    try {
      final existing = await supabase
          .schema('tetris')
          .from('match_tetris')
          .select('*, match_tetris_players(*)')
          .eq('torneo_partida_id', crucePartidaId)
          .maybeSingle();
      matchRow = existing;
    } catch (_) {}

    String actualMatchId;
    String myTeamId;
    String opponentTeamId;

    if (matchRow != null) {
      actualMatchId = matchRow['id'] as String;
      final team1Id = matchRow['team_1_id'] as String;
      final team2Id = matchRow['team_2_id'] as String;
      final players = (matchRow['match_tetris_players'] as List? ?? []);

      final myPlayer = players.firstWhere(
        (p) => p['user_id'] == user.id,
        orElse: () => null,
      );

      if (myPlayer != null) {
        myTeamId = myPlayer['team_id'] as String;
        opponentTeamId = myTeamId == team1Id ? team2Id : team1Id;
      } else {
        final isTeam1Taken = players.any((p) => p['team_id'] == team1Id);
        if (cruce.myInscripcionId != null && matchRow['torneo_insc_1'] == cruce.myInscripcionId) {
          myTeamId = team1Id;
          opponentTeamId = team2Id;
        } else if (cruce.myInscripcionId != null && matchRow['torneo_insc_2'] == cruce.myInscripcionId) {
          myTeamId = team2Id;
          opponentTeamId = team1Id;
        } else {
          myTeamId = isTeam1Taken ? team2Id : team1Id;
          opponentTeamId = isTeam1Taken ? team1Id : team2Id;
        }

        await supabase.schema('tetris').from('match_tetris_players').insert({
          'match_id': actualMatchId,
          'team_id': myTeamId,
          'user_id': user.id,
          'gamer_tag': tag,
        });

        if (players.isNotEmpty) {
          await supabase.schema('tetris').from('match_tetris').update({
            'status': 'in_progress',
            'started_at': DateTime.now().toIso8601String(),
          }).eq('id', actualMatchId);
        }
      }
    } else {
      final team1Uuid = generateUuidV4();
      final team2Uuid = generateUuidV4();
      myTeamId = team1Uuid;
      opponentTeamId = team2Uuid;

      final newMatch = await supabase.schema('tetris').from('match_tetris').insert({
        'tournament_id': cruce.tournamentId,
        'torneo_partida_id': crucePartidaId,
        'torneo_insc_1': cruce.myInscripcionId,
        'torneo_insc_2': cruce.opponentInscripcionId,
        'round_number': cruce.roundNumber,
        'format': '1v1',
        'status': 'pending',
        'team_1_id': team1Uuid,
        'team_2_id': team2Uuid,
        'room_name': 'Torneo Gameros - R${cruce.roundNumber}',
      }).select().single();

      actualMatchId = newMatch['id'] as String;

      await supabase.schema('tetris').from('match_tetris_players').insert({
        'match_id': actualMatchId,
        'team_id': myTeamId,
        'user_id': user.id,
        'gamer_tag': tag,
      });
    }

    return {
      'match_id': actualMatchId,
      'my_team_id': myTeamId,
      'opponent_team_id': opponentTeamId,
      'torneo_partida_id': crucePartidaId,
      'my_inscripcion_id': cruce.myInscripcionId,
      'opponent_inscripcion_id': cruce.opponentInscripcionId,
    };
  }
}
