import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/supabase_config.dart';

class FriendModel {
  final String friendshipId;
  final String userId;
  final String gamerTag;
  final String? username;
  final String? avatarUrl;
  final int tetrisElo;

  FriendModel({
    required this.friendshipId,
    required this.userId,
    required this.gamerTag,
    this.username,
    this.avatarUrl,
    this.tetrisElo = 1000,
  });
}

class FriendRequestModel {
  final String requestId;
  final String senderId;
  final String senderGamerTag;
  final String? senderAvatar;
  final DateTime createdAt;

  FriendRequestModel({
    required this.requestId,
    required this.senderId,
    required this.senderGamerTag,
    this.senderAvatar,
    required this.createdAt,
  });
}

class UserSearchResult {
  final String id;
  final String displayName;
  final String? username;
  final String? avatarUrl;

  UserSearchResult({required this.id, required this.displayName, this.username, this.avatarUrl});
}

class FriendsService {
  SupabaseClient get supabase => SupabaseConfig.client;

  Future<List<FriendModel>> getFriends() async {
    final user = supabase.auth.currentUser;
    if (user == null) return [];

    try {
      final res = await supabase
          .from('amigos')
          .select()
          .or('solicitante_id.eq.${user.id},receptor_id.eq.${user.id}')
          .eq('estado', 'aceptada');

      final List<FriendModel> friends = [];
      for (final row in (res as List)) {
        final friendUserId = row['solicitante_id'] == user.id ? row['receptor_id'] : row['solicitante_id'];

        String tag = 'Jugador Gameros';
        String? username;
        String? avatar;
        int elo = 1000;

        try {
          // Columnas reales de public.usuarios confirmadas por el equipo de
          // Gameros: 'nombre_display', 'username', 'foto_url'.
          final uRow = await supabase.from('usuarios').select().eq('id', friendUserId).maybeSingle();
          if (uRow != null) {
            tag = uRow['nombre_display'] as String? ?? tag;
            username = uRow['username'] as String?;
            avatar = uRow['foto_url'] as String?;
          }
        } catch (_) {}

        try {
          final rRow = await supabase.schema('tetris').from('ratings').select('rating').eq('user_id', friendUserId).maybeSingle();
          if (rRow != null) elo = rRow['rating'] as int? ?? 1000;
        } catch (_) {}

        friends.add(FriendModel(
          friendshipId: row['id'] as String,
          userId: friendUserId as String,
          gamerTag: tag,
          username: username,
          avatarUrl: avatar,
          tetrisElo: elo,
        ));
      }

      return friends;
    } catch (_) {
      return [];
    }
  }

  Future<List<FriendRequestModel>> getPendingRequests() async {
    final user = supabase.auth.currentUser;
    if (user == null) return [];

    try {
      final res = await supabase
          .from('amigos')
          .select()
          .eq('receptor_id', user.id)
          .eq('estado', 'pendiente');

      final List<FriendRequestModel> list = [];
      for (final row in (res as List)) {
        final senderId = row['solicitante_id'] as String;
        String tag = 'Jugador Gameros';
        String? avatar;
        try {
          final uRow = await supabase.from('usuarios').select().eq('id', senderId).maybeSingle();
          if (uRow != null) {
            tag = uRow['nombre_display'] as String? ?? tag;
            avatar = uRow['foto_url'] as String?;
          }
        } catch (_) {}

        list.add(FriendRequestModel(
          requestId: row['id'] as String,
          senderId: senderId,
          senderGamerTag: tag,
          senderAvatar: avatar,
          createdAt: DateTime.tryParse(row['created_at'] ?? '') ?? DateTime.now(),
        ));
      }
      return list;
    } catch (_) {
      return [];
    }
  }

  /// Búsqueda en vivo por nombre o @usuario contra public.usuarios (RLS
  /// abierta a cualquier usuario autenticado, confirmado por Gameros).
  /// Excluye al propio usuario logueado.
  Future<List<UserSearchResult>> searchUsers(String query) async {
    final q = query.trim();
    if (q.length < 2) return [];
    final user = supabase.auth.currentUser;

    try {
      final res = await supabase
          .from('usuarios')
          .select('id, nombre_display, username, foto_url')
          .or('nombre_display.ilike.%$q%,username.ilike.%$q%')
          .limit(15);

      return (res as List)
          .where((r) => r['id'] != user?.id)
          .map((r) => UserSearchResult(
                id: r['id'] as String,
                displayName: r['nombre_display'] as String? ?? 'Jugador Gameros',
                username: r['username'] as String?,
                avatarUrl: r['foto_url'] as String?,
              ))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// [target] es el id de usuario (de un resultado de búsqueda) o el código
  /// de jugador de 6 caracteres. El RPC real ya resuelve ambos casos y
  /// auto-acepta si el otro ya te había mandado una solicitud.
  /// Lanza la excepción real en vez de tragarla, para poder diagnosticar por
  /// qué una solicitud "enviada" no le llega al destinatario.
  Future<void> sendFriendRequest(String target) async {
    final user = supabase.auth.currentUser;
    if (user == null) throw Exception('No hay sesión activa');

    await supabase.rpc('enviar_solicitud_amistad', params: {
      'p_codigo_o_id': target.trim(),
    });
  }

  Future<void> respondToRequest(String requestId, bool accept) async {
    try {
      await supabase.rpc('responder_solicitud_amistad', params: {
        'p_solicitud_id': requestId,
        'p_aceptar': accept,
      });
    } catch (_) {}
  }

  Future<void> removeFriend(String otherUserId) async {
    try {
      await supabase.rpc('eliminar_amistad', params: {
        'p_otro_usuario_id': otherUserId,
      });
    } catch (_) {}
  }
}
