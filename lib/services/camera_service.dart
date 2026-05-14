import 'package:image_picker/image_picker.dart';

class CameraService {
  final _picker = ImagePicker();

  Future<String?> pickFromCamera() async {
    final photo = await _picker.pickImage(
      source: ImageSource.camera,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );
    return photo?.path;
  }

  Future<String?> pickFromGallery() async {
    final photo = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );
    return photo?.path;
  }
}
