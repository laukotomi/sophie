import 'package:sophie/models/app_user.dart';

class UserService {
  final String currentUserId;
  final List<AppUser> users;

  UserService({required this.currentUserId, required this.users});
}
