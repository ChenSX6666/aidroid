import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';

class ImagePickerButton extends StatefulWidget {
  final String? selectedImageBase64;
  final void Function(String?) onImagePicked;

  const ImagePickerButton({
    super.key,
    required this.selectedImageBase64,
    required this.onImagePicked,
  });

  @override
  State<ImagePickerButton> createState() => _ImagePickerButtonState();
}

class _ImagePickerButtonState extends State<ImagePickerButton> {
  final _picker = ImagePicker();

  Future<void> _showPicker() async {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('拍照'),
              onTap: () {
                Navigator.pop(ctx);
                _pickFromCamera();
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('相册'),
              onTap: () {
                Navigator.pop(ctx);
                _pickFromGallery();
              },
            ),
            if (widget.selectedImageBase64 != null)
              ListTile(
                leading: const Icon(Icons.close, color: Colors.red),
                title: const Text('清除图片', style: TextStyle(color: Colors.red)),
                onTap: () {
                  Navigator.pop(ctx);
                  widget.onImagePicked(null);
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickFromCamera() async {
    final status = await Permission.camera.request();
    if (!status.isGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('需要相机权限才能拍照，请在设置中开启')),
        );
      }
      return;
    }

    try {
      final xfile = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );
      if (xfile != null) {
        await _processFile(File(xfile.path));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('拍照失败: $e')),
        );
      }
    }
  }

  Future<void> _pickFromGallery() async {
    // Android 13+: READ_MEDIA_IMAGES, older: READ_EXTERNAL_STORAGE
    final status = await Permission.photos.request();
    if (!status.isGranted && !status.isLimited) {
      // Fallback to storage permission for older Android
      final storageStatus = await Permission.storage.request();
      if (!storageStatus.isGranted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('需要相册权限才能选择图片，请在设置中开启')),
          );
        }
        return;
      }
    }

    try {
      final xfile = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );
      if (xfile != null) {
        await _processFile(File(xfile.path));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('选择图片失败: $e')),
        );
      }
    }
  }

  Future<void> _processFile(File file) async {
    try {
      final size = await file.length();
      if (size > 10 * 1024 * 1024) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('图片太大，请选择小于 10MB 的图片')),
          );
        }
        return;
      }
      final bytes = await file.readAsBytes();
      final base64 = 'data:image/jpeg;base64,${base64Encode(bytes)}';
      widget.onImagePicked(base64);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('处理图片失败: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasImage = widget.selectedImageBase64 != null;

    return GestureDetector(
      onTap: _showPicker,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: hasImage ? const Color(0xFF0D7CB5).withAlpha(30) : Colors.transparent,
          borderRadius: BorderRadius.circular(18),
        ),
        child: hasImage
            ? Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: Image.memory(
                      base64Decode(widget.selectedImageBase64!.contains(',')
                          ? widget.selectedImageBase64!.split(',').last
                          : widget.selectedImageBase64!),
                      width: 36,
                      height: 36,
                      fit: BoxFit.cover,
                    ),
                  ),
                  Positioned(
                    top: 0,
                    right: 0,
                    child: GestureDetector(
                      onTap: () => widget.onImagePicked(null),
                      child: Container(
                        width: 14,
                        height: 14,
                        decoration: const BoxDecoration(
                          color: Colors.black54,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.close, size: 10, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              )
            : Icon(
                Icons.add_photo_alternate_outlined,
                size: 22,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
      ),
    );
  }
}
