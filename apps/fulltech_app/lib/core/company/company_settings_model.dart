class CompanySettings {
  final String companyName;
  final String rnc;
  final String phone;
  final String address;
  final String? logoBase64;

  const CompanySettings({
    required this.companyName,
    required this.rnc,
    required this.phone,
    required this.address,
    this.logoBase64,
  });

  factory CompanySettings.empty() {
    return const CompanySettings(
      companyName: '',
      rnc: '',
      phone: '',
      address: '',
      logoBase64: null,
    );
  }

  CompanySettings copyWith({
    String? companyName,
    String? rnc,
    String? phone,
    String? address,
    String? logoBase64,
    bool clearLogo = false,
  }) {
    return CompanySettings(
      companyName: companyName ?? this.companyName,
      rnc: rnc ?? this.rnc,
      phone: phone ?? this.phone,
      address: address ?? this.address,
      logoBase64: clearLogo ? null : (logoBase64 ?? this.logoBase64),
    );
  }

  Map<String, dynamic> toMap() => {
    'companyName': companyName,
    'rnc': rnc,
    'phone': phone,
    'address': address,
    'logoBase64': logoBase64,
  };

  factory CompanySettings.fromMap(Map<String, dynamic> map) {
    return CompanySettings(
      companyName: (map['companyName'] ?? '').toString(),
      rnc: (map['rnc'] ?? '').toString(),
      phone: (map['phone'] ?? '').toString(),
      address: (map['address'] ?? '').toString(),
      logoBase64: map['logoBase64']?.toString(),
    );
  }
}
