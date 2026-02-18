/// 演员数据模型
class Actor {
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
  final int? lastUpdated;

  Actor({
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
    this.lastUpdated,
  });

  factory Actor.fromJson(Map<String, dynamic> json) {
    return Actor(
      id: json['id'] as String,
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
      lastUpdated: json['last_updated'] as int?,
    );
  }

  factory Actor.fromDbMap(Map<String, dynamic> map) {
    return Actor.fromJson(map);
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
      'last_updated': lastUpdated,
    };
  }

  Map<String, dynamic> toDbMap() {
    return {
      'id': id,
      'name': name,
      'avatar': avatar,
      'last_updated': lastUpdated ?? DateTime.now().millisecondsSinceEpoch ~/ 1000,
    };
  }

  Actor copyWith({
    String? id,
    String? name,
    String? avatar,
    String? birthday,
    String? age,
    String? height,
    String? bust,
    String? waistline,
    String? hipline,
    String? birthplace,
    String? hobby,
    int? lastUpdated,
  }) {
    return Actor(
      id: id ?? this.id,
      name: name ?? this.name,
      avatar: avatar ?? this.avatar,
      birthday: birthday ?? this.birthday,
      age: age ?? this.age,
      height: height ?? this.height,
      bust: bust ?? this.bust,
      waistline: waistline ?? this.waistline,
      hipline: hipline ?? this.hipline,
      birthplace: birthplace ?? this.birthplace,
      hobby: hobby ?? this.hobby,
      lastUpdated: lastUpdated ?? this.lastUpdated,
    );
  }
}
