import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
    return data.map((e) => UserModel.fromJson(e as Map<String, dynamic>)).toList();
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
    final res = await _dio.patch(ApiRoutes.blockUser(id), data: {'blocked': blocked});
    return UserModel.fromJson(res.data as Map<String, dynamic>);
  }

  Future<UserModel> fetchMe() async {
    final res = await _dio.get('${ApiRoutes.users}/me');
    return UserModel.fromJson(res.data as Map<String, dynamic>);
  }

  Future<UserModel> updateMe({String? email, String? nombreCompleto, String? telefono, String? password}) async {
    final res = await _dio.patch('${ApiRoutes.users}/me', data: {
      'email': email,
      'nombreCompleto': nombreCompleto,
      'telefono': telefono,
      'password': password,
    });
    return UserModel.fromJson(res.data as Map<String, dynamic>);
  }
}
