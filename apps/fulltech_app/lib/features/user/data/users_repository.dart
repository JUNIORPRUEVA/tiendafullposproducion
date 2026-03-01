import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http_parser/http_parser.dart';

import '../../../core/api/api_routes.dart';
import '../../../core/auth/auth_repository.dart';
import '../../../core/models/user_model.dart';

final usersRepositoryProvider = Provider<UsersRepository>((ref) {
  return UsersRepository(dio: ref.watch(dioProvider));
});

class UsersRepository {
  UsersRepository({required Dio dio}) : _dio = dio;

  final Dio _dio;

  Future<List<UserModel>> fetchUsers() async {
    final res = await _dio.get(ApiRoutes.users);
    final data = res.data as List<dynamic>;
    return data
        .map((e) => UserModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<UserModel> createUser(Map<String, dynamic> payload) async {
    final res = await _dio.post(ApiRoutes.users, data: payload);
    return UserModel.fromJson(res.data as Map<String, dynamic>);
  }

  Future<UserModel> updateUser(String id, Map<String, dynamic> payload) async {
    final res = await _dio.patch(ApiRoutes.updateUser(id), data: payload);
    return UserModel.fromJson(res.data as Map<String, dynamic>);
  }

  Future<void> deleteUser(String id) async {
    await _dio.delete(ApiRoutes.deleteUser(id));
  }

  Future<UserModel> setBlocked(String id, bool blocked) async {
    final res = await _dio.patch(
      ApiRoutes.blockUser(id),
      data: {'blocked': blocked},
    );
    return UserModel.fromJson(res.data as Map<String, dynamic>);
  }

  Future<UserModel> fetchMe() async {
    final res = await _dio.get(ApiRoutes.usersMe);
    return UserModel.fromJson(res.data as Map<String, dynamic>);
  }

  Future<UserModel> updateMe({
    String? email,
    String? nombreCompleto,
    String? telefono,
    String? password,
    String? fotoPersonalUrl,
  }) async {
    final payload = <String, dynamic>{
      'email': email,
      'nombreCompleto': nombreCompleto,
      'telefono': telefono,
      'password': password,
      'fotoPersonalUrl': fotoPersonalUrl,
    };
    payload.removeWhere((key, value) {
      if (value == null) return true;
      if (value is String && value.trim().isEmpty) return true;
      return false;
    });

    final res = await _dio.patch(
      ApiRoutes.usersMe,
      data: payload,
    );
    return UserModel.fromJson(res.data as Map<String, dynamic>);
  }

  Future<String> uploadUserDocument({
    required List<int> bytes,
    required String fileName,
  }) async {
    final lower = fileName.toLowerCase();
    final mediaType = lower.endsWith('.png')
        ? MediaType('image', 'png')
        : lower.endsWith('.webp')
        ? MediaType('image', 'webp')
        : MediaType('image', 'jpeg');

    final formData = FormData.fromMap({
      'file': MultipartFile.fromBytes(
        bytes,
        filename: fileName,
        contentType: mediaType,
      ),
    });

    final res = await _dio.post(ApiRoutes.usersUpload, data: formData);
    final data = res.data as Map<String, dynamic>;
    return (data['url'] ?? data['path'] ?? '') as String;
  }
}
