import 'package:permission_handler/permission_handler.dart';
import 'package:logger/logger.dart';

class RequestVideoPermissions {
  static final _logger = Logger();

  static Future<bool> requestPermissions() async {
    PermissionStatus cameraPermission = await Permission.camera.status;
    PermissionStatus storagePermission = await Permission.storage.status;

    if (cameraPermission != PermissionStatus.granted) {
      cameraPermission = await Permission.camera.request();
      if (cameraPermission != PermissionStatus.granted) {
        _logger.e('Camera permission denied');
        return false;
      }
    }

    if (storagePermission != PermissionStatus.granted) {
      storagePermission = await Permission.storage.request();
      if (storagePermission != PermissionStatus.granted) {
        _logger.e('Storage permission denied');
        return false;
      }
    }

    _logger.i('All necessary permissions granted');
    return true;
  }
}
