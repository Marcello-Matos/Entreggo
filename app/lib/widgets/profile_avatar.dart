import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../api/api_client.dart';
import '../auth/auth_service.dart';
import '../theme.dart';

/// Avatar do perfil: foto enviada pelo usuário, a foto do Google ou um ícone.
/// Toque abre as opções: câmera, galeria ou remover.
class ProfileAvatar extends StatefulWidget {
  const ProfileAvatar({
    super.key,
    required this.api,
    required this.auth,
    this.radius = 22,
  });

  final ApiClient api;
  final AuthService auth;
  final double radius;

  @override
  State<ProfileAvatar> createState() => _ProfileAvatarState();
}

class _ProfileAvatarState extends State<ProfileAvatar> {
  Uint8List? _photo;
  bool _loaded = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final bytes = await widget.api.fetchPhoto();
      if (mounted) setState(() => _photo = bytes);
    } catch (_) {
      // Sem a foto do servidor, segue com a do provedor de login ou o ícone.
    } finally {
      if (mounted) setState(() => _loaded = true);
    }
  }

  void _toast(String message) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));

  Future<void> _pick(ImageSource source) async {
    final file = await ImagePicker().pickImage(
      source: source,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 85,
    );
    if (file == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final bytes = await file.readAsBytes();
      await widget.api.uploadPhoto(bytes, filename: file.name);
      if (mounted) setState(() => _photo = bytes);
    } on ApiException catch (e) {
      _toast(e.message);
    } catch (e) {
      _toast('Falha ao enviar a foto: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove() async {
    setState(() => _busy = true);
    try {
      await widget.api.deletePhoto();
      if (mounted) setState(() => _photo = null);
    } on ApiException catch (e) {
      _toast(e.message);
    } catch (e) {
      _toast('Falha de conexão: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showOptions() => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('Tirar foto'),
            onTap: () {
              Navigator.pop(context);
              _pick(ImageSource.camera);
            },
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Escolher da galeria'),
            onTap: () {
              Navigator.pop(context);
              _pick(ImageSource.gallery);
            },
          ),
          if (_photo != null)
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Remover foto'),
              onTap: () {
                Navigator.pop(context);
                _remove();
              },
            ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final remoteUrl = widget.auth.photoUrl;
    final ImageProvider? image = _photo != null
        ? MemoryImage(_photo!)
        : remoteUrl != null
        ? NetworkImage(remoteUrl)
        : null;
    return GestureDetector(
      onTap: _busy ? null : _showOptions,
      child: Stack(
        alignment: Alignment.bottomRight,
        children: [
          CircleAvatar(
            radius: widget.radius,
            backgroundColor: const Color(0xFFEAF2FE),
            backgroundImage: _loaded ? image : null,
            child: image == null
                ? const Icon(Icons.person, color: EntreggoColors.primary)
                : null,
          ),
          if (_busy)
            SizedBox(
              width: widget.radius * 2,
              height: widget.radius * 2,
              child: const CircularProgressIndicator(strokeWidth: 2),
            )
          else
            const CircleAvatar(
              radius: 9,
              backgroundColor: EntreggoColors.primary,
              child: Icon(Icons.edit, size: 11, color: Colors.white),
            ),
        ],
      ),
    );
  }
}
