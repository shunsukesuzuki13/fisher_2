import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:location/location.dart' as loc;
import 'package:fisher2/import.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:camera/camera.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' show join;
import 'package:logging/logging.dart';
import 'package:permission_handler/permission_handler.dart' as perm;
import 'package:video_player/video_player.dart';
import 'package:intl/intl.dart';

class FullFunctionView extends StatefulWidget {
  const FullFunctionView({super.key, required this.title});

  final String title;

  @override
  State<FullFunctionView> createState() => _FullFunctionViewState();
}

class _FullFunctionViewState extends State<FullFunctionView> {
  loc.LocationData? _currentLocation;
  loc.LocationData? _previousLocation;
  GyroscopeEvent? _currentGyroData;
  Timer? _timer;
  final loc.Location location = loc.Location();
  CameraController? _cameraController;
  late Future<void> _initializeControllerFuture;
  String? _videoPath;
  final Logger _logger = Logger('HomeView');
  bool _isLoggingSetup = false;
  VideoPlayerController? _videoPlayerController;

  DateTime? _startTime;
  DateTime? _endTime;
  final List<loc.LocationData> _locationDataList = [];

  @override
  void initState() {
    super.initState();
    _setupLogging();
    _requestPermissions().then((_) {
      _initializeCamera();
    });
  }

  void _setupLogging() {
    if (!_isLoggingSetup) {
      Logger.root.level = Level.ALL;
      Logger.root.onRecord.listen((record) {
        final logger = Logger('LoggingListener');
        logger.log(record.level, '${record.time}: ${record.message}');
      });
      _isLoggingSetup = true;
    }
  }

  Future<void> _initializeCamera() async {
    try {
      final cameras = await availableCameras();
      final firstCamera = cameras.first;

      _cameraController = CameraController(
        firstCamera,
        ResolutionPreset.high,
        enableAudio: false,
      );

      _initializeControllerFuture = _cameraController!.initialize();
    } catch (e) {
      _handleError('カメラの初期化に失敗しました', e);
    }
  }

  Future<void> _requestPermissions() async {
    try {
      final statuses = await [
        perm.Permission.camera,
        perm.Permission.storage,
        perm.Permission.location,
        perm.Permission.microphone,
      ].request();

      if (statuses.values
          .any((status) => status != perm.PermissionStatus.granted)) {
        _logger.info('必要な権限が付与されていません');
      }
    } catch (e) {
      _handleError('権限のリクエスト中にエラーが発生しました', e);
    }
  }

  void _getLocationAndStartRecording() async {
    try {
      await _initializeControllerFuture;
      _startTime = DateTime.now();
      _timer = Timer.periodic(const Duration(seconds: 10), (_) async {
        final data = await GetDate.getPositionAndGyroData(location);
        setState(() {
          _currentLocation = data['location'];
          _currentGyroData = data['gyroscope'];
          _locationDataList.add(_currentLocation!);
        });
      });
      await _startVideoRecording();
    } catch (e) {
      _handleError('位置情報の取得と録画の開始中にエラーが発生しました', e);
    }
  }

  Future<void> _startVideoRecording() async {
    if (!_cameraController!.value.isInitialized) {
      return;
    }

    try {
      final directory = await getApplicationDocumentsDirectory();
      _videoPath = join(directory.path, '${DateTime.now()}.mp4');

      await _cameraController!.startVideoRecording();
      setState(() {}); // カメラプレビューを表示するためにsetStateを呼び出す
    } catch (e) {
      _handleError('ビデオ録画の開始中にエラーが発生しました', e);
    }
  }

  Future<void> _stopVideoRecording() async {
    if (!_cameraController!.value.isRecordingVideo) {
      return;
    }

    try {
      final XFile videoFile = await _cameraController!.stopVideoRecording();
      _endTime = DateTime.now();
      setState(() {
        _videoPath = videoFile.path;
        _initializeVideoPlayer();
      });
      _logger.info('Video recorded to: $_videoPath');

      // XFile を File に変換してからコピー
      final File file = File(videoFile.path);
      final directory = Directory('/storage/emulated/0/Download');
      final newPath =
          join(directory.path, '${DateTime.now().millisecondsSinceEpoch}.mp4');
      final newFile = await file.copy(newPath);
      _logger.info('Video copied to: ${newFile.path}');

      _showSummary();
    } catch (e) {
      _handleError('ビデオ録画の停止中にエラーが発生しました', e);
    }
  }

  void _initializeVideoPlayer() {
    if (_videoPath != null) {
      try {
        _videoPlayerController = VideoPlayerController.file(File(_videoPath!))
          ..initialize().then((_) {
            setState(() {});
            _videoPlayerController!.play();
          });
      } catch (e) {
        _handleError('ビデオプレーヤーの初期化中にエラーが発生しました', e);
      }
    }
  }

  void _handleError(String message, [dynamic error]) {
    _logger.severe(message, error);
    _showErrorSnackBar(message);
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _showSummary() {
    final duration = _endTime!.difference(_startTime!);
    final distance = _calculateDistance();
    final summary =
        '開始時刻: $_startTime\n終了時刻: $_endTime\n移動距離: ${distance.toStringAsFixed(2)}m\n経過時間: ${duration.inSeconds}秒';
    _showErrorSnackBar(summary);
  }

  double _calculateDistance() {
    double totalDistance = 0.0;
    for (int i = 1; i < _locationDataList.length; i++) {
      totalDistance += _distanceBetween(
        _locationDataList[i - 1].latitude!,
        _locationDataList[i - 1].longitude!,
        _locationDataList[i].latitude!,
        _locationDataList[i].longitude!,
      );
    }
    return totalDistance;
  }

  double _distanceBetween(double lat1, double lon1, double lat2, double lon2) {
    const double R = 6371000; // 地球の半径 (メートル)
    final double dLat = _degreesToRadians(lat2 - lat1);
    final double dLon = _degreesToRadians(lon2 - lon1);
    final double a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_degreesToRadians(lat1)) *
            cos(_degreesToRadians(lat2)) *
            sin(dLon / 2) *
            sin(dLon / 2);
    final double c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return R * c;
  }

  double _degreesToRadians(double degrees) {
    return degrees * pi / 180;
  }

  Future<List<File>> getImages() async {
    final directory = await getApplicationDocumentsDirectory();
    final imagePath = join(directory.path, 'images');
    final imageDirectory = Directory(imagePath);

    if (!await imageDirectory.exists()) {
      return [];
    }

    final imageFiles = imageDirectory
        .listSync()
        .where((item) => item is File && item.path.endsWith('.jpg'))
        .map((item) => item as File)
        .toList();

    return imageFiles;
  }

  Future<void> _saveDataLocally(String data) async {
    try {
      // ダウンロードフォルダのパスを取得
      Directory? directory;
      if (Platform.isAndroid) {
        directory = Directory('/storage/emulated/0/Download');
      } else {
        directory = await getApplicationDocumentsDirectory();
      }

      // 現在の日付を取得してフォーマット
      final now = DateTime.now();
      final formattedDate = DateFormat('yyyyMMdd_HHmmss').format(now);

      // 日付を含むファイルパスを作成
      final path = '${directory.path}/$formattedDate.txt';
      final file = File(path);

      // ディレクトリが存在しない場合は作成
      if (!await file.parent.exists()) {
        await file.parent.create(recursive: true);
      }

      // データをファイルに書き込む
      await file.writeAsString(data);

      // スナックバーで保存完了を通知
      _showErrorSnackBar('データがローカルストレージに保存されました: ${file.path}');
    } catch (e) {
      _showErrorSnackBar('データの保存中にエラーが発生しました: $e');
    }
  }

  Future<void> _saveDataToFile() async {
    try {
      // 計測時間を計算
      final duration = _endTime!.difference(_startTime!);
      final formattedDuration =
          (duration.inSeconds / 60).toStringAsFixed(2); // 分単位に変換
      final totalDistance = _calculateDistance();
      final formattedDistance = totalDistance.toStringAsFixed(2);

      // 保存するデータを準備
      final data = '''
Measurement Duration: $formattedDuration minutes
Total Distance: $formattedDistance meters
Current Location: ${_currentLocation?.toString()}
Previous Location: ${_previousLocation?.toString()}
Current Gyro Data: ${_currentGyroData?.toString()}
Location Data List: ${_locationDataList.map((loc) => loc.toString()).join('\n')}
''';

      // データをローカルストレージに保存
      await _saveDataLocally(data);
    } catch (e) {
      _logger.severe('データの保存中にエラーが発生しました: $e');
      _showErrorSnackBar('データの保存中にエラーが発生しました: $e ここまで通りました');
    }
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _timer?.cancel();
    _videoPlayerController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
        centerTitle: true,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.all(10),
              child: Text(
                'Location: $_currentLocation\nGyroscope: $_currentGyroData\nVideo Path: $_videoPath',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ),
            if (_cameraController != null &&
                _cameraController!.value.isInitialized)
              Expanded(
                child: CameraPreview(_cameraController!),
              ),
            OverflowBar(
              alignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  height: 50,
                  width: 105,
                  child: ElevatedButton(
                    onPressed: () async {
                      await _initializeCamera();
                      _getLocationAndStartRecording();
                    },
                    child: const Text('start'),
                  ),
                ),
                SizedBox(
                  height: 50,
                  width: 105,
                  child: ElevatedButton(
                    onPressed: () async {
                      _timer?.cancel();
                      await _stopVideoRecording();
                      await _saveDataToFile();
                      _cameraController?.dispose();
                      _videoPlayerController?.dispose();
                      setState(() {
                        _cameraController = null;
                        _videoPlayerController = null;
                      });
                    },
                    child: const Text('stop'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
