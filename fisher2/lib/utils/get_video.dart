import 'package:camera/camera.dart';
import 'package:logger/logger.dart';

class GetVideo {
  static final _logger = Logger();

  static Future<void> startRecording(CameraController controller) async {
    try {
      await controller.startVideoRecording();
      _logger.i('Video recording started');
    } catch (e) {
      _logger.e('Error starting video recording: $e');
    }
  }

  static Future<XFile?> stopRecording(CameraController controller) async {
    try {
      XFile videoFile = await controller.stopVideoRecording();
      _logger.i('Video recording stopped: ${videoFile.path}');
      return videoFile;
    } catch (e) {
      _logger.e('Error stopping video recording: $e');
      return null;
    }
  }
}
