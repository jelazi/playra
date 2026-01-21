import 'package:titulky_com/bloc/subtitle/subtitle_bloc.dart';
import 'package:titulky_com/bloc/subtitle/subtitle_event.dart';
import 'package:titulky_com/bloc/subtitle/subtitle_state.dart';
import 'package:titulky_com/repositories/titulky_repository.dart';

void main() async {
  print('=== Testing Subtitle BLoC Login ===\n');

  final repository = TitulkyRepository();
  final bloc = SubtitleBloc(repository: repository);

  // Listen to state changes
  bloc.stream.listen((state) {
    print('📱 BLoC State changed: $state');
    if (state is SubtitleLoggedIn) {
      print('✅ Successfully logged in as: ${state.username}');
    } else if (state is SubtitleLoginFailed) {
      print('❌ Login failed: ${state.message}');
    }
  });

  // Send login event
  print('Sending LoginToTitulky event...');
  bloc.add(LoginToTitulky('jelazi', 'Honzicek1'));

  // Wait for completion
  await Future.delayed(const Duration(seconds: 10));

  print('\nClosing BLoC...');
  await bloc.close();
}
