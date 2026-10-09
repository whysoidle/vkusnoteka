import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

Future<String?> pickRecipePhoto() async {
  final file = await ImagePicker().pickImage(
    source: ImageSource.gallery,
    maxWidth: 1600,
    maxHeight: 1600,
  );
  if (file == null) return null;
  if (await file.length() > 30 * 1024 * 1024) {
    throw const FormatException('Фотография превышает 30 МБ');
  }
  final bytes = await file.readAsBytes();
  return Isolate.run(() {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw const FormatException('Формат фотографии не поддерживается');
    }
    var photo = img.bakeOrientation(decoded);
    photo = img.copyResize(
      photo,
      width: photo.width >= photo.height ? 640 : null,
      height: photo.height > photo.width ? 640 : null,
    );
    var encoded = img.encodeJpg(photo, quality: 70);
    if (encoded.length > 120000) {
      encoded = img.encodeJpg(img.copyResize(photo, width: 420), quality: 55);
    }
    if (encoded.length > 120000) {
      throw const FormatException(
        'Фото слишком сложное; выберите другое изображение',
      );
    }
    return base64Encode(encoded);
  });
}

Future<File> prepareOcrImage(String path) async {
  final file = File(path);
  if (await file.length() > 50 * 1024 * 1024) {
    throw const FormatException('Изображение превышает 50 МБ');
  }
  final bytes = await file.readAsBytes();
  final encoded = await Isolate.run(() {
    final image = img.decodeImage(bytes);
    if (image == null) {
      throw const FormatException('Не удалось прочитать изображение');
    }
    var upright = img.bakeOrientation(image);
    if (upright.width > 2200 || upright.height > 2200) {
      upright = img.copyResize(
        upright,
        width: upright.width >= upright.height ? 2200 : null,
        height: upright.height > upright.width ? 2200 : null,
      );
    }
    return img.encodePng(upright);
  });
  final temp = await getTemporaryDirectory();
  final output = File('${temp.path}/ocr-${const Uuid().v4()}.png');
  await output.writeAsBytes(encoded);
  return output;
}
