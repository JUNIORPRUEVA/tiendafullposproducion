class CompanySettings {
  final String companyName;
  final String rnc;
  final String phone;
  final String address;
  final String? logoBase64;
  final String openAiApiKey;
  final String openAiModel;
  final bool hasOpenAiApiKey;
  final String productsSource;
  final bool productsReadOnly;

  const CompanySettings({
    required this.companyName,
    required this.rnc,
    required this.phone,
    required this.address,
    this.logoBase64,
    required this.openAiApiKey,
    required this.openAiModel,
    required this.hasOpenAiApiKey,
    this.productsSource = 'LOCAL',
    this.productsReadOnly = false,
  });

  factory CompanySettings.empty() {
    return const CompanySettings(
      companyName: '',
      rnc: '',
      phone: '',
      address: '',
      logoBase64: null,
      openAiApiKey: '',
      openAiModel: 'gpt-4o-mini',
      hasOpenAiApiKey: false,
      productsSource: 'LOCAL',
      productsReadOnly: false,
    );
  }

  CompanySettings copyWith({
    String? companyName,
    String? rnc,
    String? phone,
    String? address,
    String? logoBase64,
    String? openAiApiKey,
    String? openAiModel,
    bool? hasOpenAiApiKey,
    String? productsSource,
    bool? productsReadOnly,
    bool clearLogo = false,
  }) {
    return CompanySettings(
      companyName: companyName ?? this.companyName,
      rnc: rnc ?? this.rnc,
      phone: phone ?? this.phone,
      address: address ?? this.address,
      logoBase64: clearLogo ? null : (logoBase64 ?? this.logoBase64),
      openAiApiKey: openAiApiKey ?? this.openAiApiKey,
      openAiModel: openAiModel ?? this.openAiModel,
      hasOpenAiApiKey: hasOpenAiApiKey ?? this.hasOpenAiApiKey,
      productsSource: productsSource ?? this.productsSource,
      productsReadOnly: productsReadOnly ?? this.productsReadOnly,
    );
  }

  Map<String, dynamic> toMap() => {
    'companyName': companyName,
    'rnc': rnc,
    'phone': phone,
    'address': address,
    'logoBase64': logoBase64,
    'openAiApiKey': openAiApiKey,
    'openAiModel': openAiModel,
    'hasOpenAiApiKey': hasOpenAiApiKey,
    'productsSource': productsSource,
    'productsReadOnly': productsReadOnly,
  };

  factory CompanySettings.fromMap(Map<String, dynamic> map) {
    return CompanySettings(
      companyName: (map['companyName'] ?? '').toString(),
      rnc: (map['rnc'] ?? '').toString(),
      phone: (map['phone'] ?? '').toString(),
      address: (map['address'] ?? '').toString(),
      logoBase64: map['logoBase64']?.toString(),
      openAiApiKey: (map['openAiApiKey'] ?? '').toString(),
      openAiModel: (map['openAiModel'] ?? 'gpt-4o-mini').toString(),
      hasOpenAiApiKey: map['hasOpenAiApiKey'] == true,
      productsSource: (map['productsSource'] ?? 'LOCAL').toString(),
      productsReadOnly: map['productsReadOnly'] == true,
    );
  }
}
