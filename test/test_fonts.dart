import 'package:flutter/services.dart';

Future<void> loadHocalistTestFonts() async {
  final fonts = <String, List<String>>{
    'Roboto': ['assets/fonts/roboto/roboto-regular.ttf', 'assets/fonts/roboto/roboto-medium.ttf', 'assets/fonts/roboto/roboto-bold.ttf'],
    'Nunito': ['assets/fonts/nunito/Nunito-Variable.ttf'],
    'Lexend': ['assets/fonts/lexend/Lexend[wght].ttf'],
    'Archivo': ['assets/fonts/archivo/Archivo-Variable.ttf'],
  };

  for (final entry in fonts.entries) {
    final loader = FontLoader(entry.key);
    for (final asset in entry.value) {
      loader.addFont(rootBundle.load(asset));
    }
    await loader.load();
  }
}
