/// 演员/明星信息模型
class Star {
  final String id;
  final String? name;
  final String? avatar;
  final String? birthday;
  final String? age;
  final String? height;
  final String? bust;
  final String? waistline;
  final String? hipline;
  final String? birthplace;
  final String? hobby;
  final String? data;
  final int? lastUpdated;

  Star({
    required this.id,
    this.name,
    this.avatar,
    this.birthday,
    this.age,
    this.height,
    this.bust,
    this.waistline,
    this.hipline,
    this.birthplace,
    this.hobby,
    this.data,
    this.lastUpdated,
  });

  factory Star.fromJson(Map<String, dynamic> json) {
    return Star(
      id: json['id'] as String? ?? '',
      name: json['name'] as String?,
      avatar: json['avatar'] as String?,
      birthday: json['birthday'] as String?,
      age: json['age'] as String?,
      height: json['height'] as String?,
      bust: json['bust'] as String?,
      waistline: json['waistline'] as String?,
      hipline: json['hipline'] as String?,
      birthplace: json['birthplace'] as String?,
      hobby: json['hobby'] as String?,
      data: json['data'] as String?,
      lastUpdated: json['last_updated'] as int?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'avatar': avatar,
      'birthday': birthday,
      'age': age,
      'height': height,
      'bust': bust,
      'waistline': waistline,
      'hipline': hipline,
      'birthplace': birthplace,
      'hobby': hobby,
      'data': data,
      'last_updated': lastUpdated,
    };
  }
}
