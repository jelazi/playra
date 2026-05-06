import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../models/server_connection.dart';
import '../../services/playra_storage.dart';

class ServersState extends Equatable {
  final List<ServerConnection> servers;
  const ServersState(this.servers);

  @override
  List<Object?> get props => [servers];
}

class ServersCubit extends Cubit<ServersState> {
  ServersCubit() : super(ServersState(PlayraStorage.getServers()));

  Future<void> refresh() async {
    emit(ServersState(PlayraStorage.getServers()));
  }

  Future<void> save(ServerConnection s) async {
    await PlayraStorage.saveServer(s);
    await refresh();
  }

  Future<void> delete(String id) async {
    await PlayraStorage.deleteServer(id);
    await refresh();
  }
}
