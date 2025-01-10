import 'package:flutter/material.dart';
import 'package:fisher2/import.dart';

class ModeSelectionView extends StatelessWidget {
  const ModeSelectionView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('モード選択'),
        centerTitle: true,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const FullFunctionView(title: 'Full Function')),
                );
              },
              child: const Text('フル機能モード'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const LocationGyroView(title: 'Location & Gyro')),
                );
              },
              child: const Text('位置データとジャイロモード'),
            ),
          ],
        ),
      ),
    );
  }
}
