import 'package:material_ui/material_ui.dart';

import 'screens/destination_screen.dart';
import 'services/front_module.dart';

void main() {
  runApp(BikeApp(frontModule: PreviewFrontModule()));
}

class BikeApp extends StatelessWidget {
  final FrontModule frontModule;
  const BikeApp({super.key, required this.frontModule});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bike Nav',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: const Color(0xFF1565C0)),
      darkTheme: ThemeData(
        colorSchemeSeed: const Color(0xFF1565C0),
        brightness: Brightness.dark,
      ),
      home: DestinationScreen(frontModule: frontModule),
    );
  }
}
