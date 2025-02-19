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
  final List<GyroscopeEvent> _gyroDataList = [];
  final List<double> _distanceHistory = [];
  DateTime? _startTime;
  DateTime? _endTime;
  final List<loc.LocationData> _locationDataList = [];
  bool _isCollectingData = false;
  bool _isRecording = false;
  double _totalDistance = 0.0;

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

      // 初回にリストをクリア (タイマー外で一度だけ)
      _locationDataList.clear();
      _gyroDataList.clear();
      _distanceHistory.clear();

      // タイマー設定：500msごとに位置情報とジャイロデータを取得
      _timer = Timer.periodic(const Duration(milliseconds: 500), (_) async {
        final locationData = await LocationGyroView.getLocationData();
        final gyroData = await LocationGyroView.getGyroData();

        if (locationData != null) {
          setState(() {
            // 位置情報が前回の情報と異なれば距離を計算
            if (_previousLocation != null) {
              // 現在位置と前回位置の差分を計算
              _totalDistance +=
                  _calculateDistance(_previousLocation!, locationData);
            }

            // 前回位置情報の更新
            _previousLocation = locationData;

            // 現在の位置とジャイロデータの保存
            _currentLocation = locationData;
            _currentGyroData = gyroData;

            // データリストに追加
            _locationDataList.add(locationData); // 位置データをリストに追加
            if (gyroData != null) {
              _gyroDataList.add(gyroData); // ジャイロデータをリストに追加
            }
            _distanceHistory.add(_totalDistance); // 移動距離をリストに追加
          });
        }
      });

      // ビデオ録画の開始
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

      // ビデオファイルパスとプレイヤーの初期化を一旦セット
      _videoPath = videoFile.path;

      // XFile を File に変換してからコピー
      final File file = File(videoFile.path);
      final directory = Directory('/storage/emulated/0/Download');
      final newPath =
          join(directory.path, '${DateTime.now().millisecondsSinceEpoch}.mp4');
      final newFile = await file.copy(newPath);
      _logger.info('Video copied to: ${newFile.path}');

      // データ保存処理
      await _saveDataToFile();

      // サマリー表示
      _showSummary();

      // ここでは非同期処理が全て完了してから、状態更新を行う
      setState(() {
        _videoPath = newFile.path; // 新しいビデオパスをセット
        _initializeVideoPlayer(); // プレイヤーの初期化（void型だからawait不要）

        // 状態をリセット
        _currentLocation = null; // 位置情報をnullにリセット
        _previousLocation = null; // 前回の位置情報をnullにリセット
        _currentGyroData = null; // ジャイロデータをnullにリセット
        _totalDistance = 0.0; // 移動距離を0にリセット
        _locationDataList.clear(); // 位置データリストをクリア
        _gyroDataList.clear(); // ジャイロデータリストをクリア
        _distanceHistory.clear(); // 距離履歴リストをクリア
      });

      _logger.info('Video recorded and processed successfully.');
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
    //final distance = _calculateDistance();
    final summary =
        '開始時刻: $_startTime\n終了時刻: $_endTime\n移動距離: ${_totalDistance.toStringAsFixed(2)}m\n経過時間: ${duration.inSeconds}秒';
    _showErrorSnackBar(summary);
  }

  double _calculateDistance(loc.LocationData start, loc.LocationData end) {
    const double earthRadius = 6371000; // メートル
    final double dLat = _degreesToRadians(end.latitude! - start.latitude!);
    final double dLon = _degreesToRadians(end.longitude! - start.longitude!);
    final double a = (sin(dLat / 2) * sin(dLat / 2)) +
        (cos(_degreesToRadians(start.latitude!)) *
            cos(_degreesToRadians(end.latitude!)) *
            sin(dLon / 2) *
            sin(dLon / 2));
    final double c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadius * c;
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

      // 拡張子を .csv に変更
      final path = '${directory.path}/$formattedDate.csv';
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
    await _requestPermissions(); // パーミッションをリクエスト

    try {
      // CSV形式のデータ作成
      final data = [
        'Version: 3',
        'Timestamp,Latitude,Longitude,GyroX,GyroY,GyroZ,TotalDistance',
        for (int i = 0; i < _gyroDataList.length; i++)
          '${DateTime.now().toIso8601String()},'
              '${_locationDataList.isNotEmpty ? _locationDataList.last.latitude : 0.0},'
              '${_locationDataList.isNotEmpty ? _locationDataList.last.longitude : 0.0},'
              '${_gyroDataList[i].x},${_gyroDataList[i].y},${_gyroDataList[i].z},${_distanceHistory[i]}'
      ].join('\n');
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
      backgroundColor:
          _isCollectingData ? Colors.lightGreen[100] : Colors.white,
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.all(10),
                  child: Text(
                    'Version: 3\n'
                    'Location: $_currentLocation\n'
                    'Gyroscope: $_currentGyroData\n'
                    'Total Distance: $_totalDistance meters',
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
                        onPressed: _isRecording || _isCollectingData
                            ? null
                            : () async {
                                await _initializeCamera();
                                _getLocationAndStartRecording();
                                setState(() {
                                  _isCollectingData = true;
                                  _isRecording = true;
                                });
                              },
                        child: const Text('start'),
                      ),
                    ),
                    SizedBox(
                      height: 50,
                      width: 105,
                      child: ElevatedButton(
                        onPressed: !_isRecording
                            ? null
                            : () async {
                                _timer?.cancel();
                                await _stopVideoRecording();
                                _cameraController?.dispose();
                                _videoPlayerController?.dispose();
                                setState(() {
                                  _isCollectingData = false;
                                  _isRecording = false;
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
          if (_isCollectingData)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.all(8),
                color: Colors.red.withOpacity(0.8),
                child: const Center(
                  child: Text(
                    '📹 録画中...',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

