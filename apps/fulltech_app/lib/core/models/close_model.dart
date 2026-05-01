enum CloseType { capsulas, pos, tienda, phytoemagry }

extension CloseTypeX on CloseType {
  String get label {
    switch (this) {
      case CloseType.capsulas:
        return 'Pastilla';
      case CloseType.pos:
        return 'Software';
      case CloseType.tienda:
        return 'Tienda';
      case CloseType.phytoemagry:
        return 'PhytoEmagry';
    }
  }

  String get apiValue {
    switch (this) {
      case CloseType.capsulas:
        return 'CAPSULAS';
      case CloseType.pos:
        return 'POS';
      case CloseType.tienda:
        return 'TIENDA';
      case CloseType.phytoemagry:
        return 'PHYTOEMAGRY';
    }
  }

  static CloseType fromKey(String value) {
    final normalized = value.trim().toUpperCase();
    switch (normalized) {
      case 'POS':
        return CloseType.pos;
      case 'TIENDA':
      case 'TIENDA_SOFTWARE':
        return CloseType.tienda;
      case 'PHYTOEMAGRY':
      case 'PHYTO':
      case 'CAPSULAS':
      case 'PASTILLA':
        return CloseType.phytoemagry;
      default:
        return CloseType.tienda;
    }
  }
}

class CloseModel {
  final String id;
  final CloseType type;
  final DateTime date;
  final String status; // pending/approved/rejected
  final double cash;
  final double transfer;
  final String? transferBank;
  final double card;
  final double otherIncome;
  final double expenses;
  final double cashDelivered;
  final double? persistedTotalIncome;
  final double? persistedNetTotal;
  final double? persistedDifference;
  final String? notes;
  final String? evidenceUrl;
  final String? evidenceFileName;
  final String? evidenceStorageKey;
  final String? evidenceMimeType;
  final List<Map<String, dynamic>> expenseDetails;
  final String? pdfUrl;
  final String? pdfFileName;
  final String? notificationStatus;
  final String? notificationError;
  final String? createdById;
  final String? createdByName;
  final String? reviewedById;
  final String? reviewedByName;
  final DateTime? reviewedAt;
  final String? reviewNote;
  final String? aiRiskLevel;
  final String? aiReportSummary;
  final Map<String, dynamic>? aiReportJson;
  final DateTime? aiGeneratedAt;
  final List<CloseTransferModel> transfers;
  final DateTime createdAt;
  final DateTime updatedAt;

  const CloseModel({
    required this.id,
    required this.type,
    required this.date,
    required this.status,
    required this.cash,
    required this.transfer,
    this.transferBank,
    required this.card,
    this.otherIncome = 0,
    required this.expenses,
    required this.cashDelivered,
    this.persistedTotalIncome,
    this.persistedNetTotal,
    this.persistedDifference,
    this.notes,
    this.evidenceUrl,
    this.evidenceFileName,
    this.evidenceStorageKey,
    this.evidenceMimeType,
    this.expenseDetails = const [],
    this.pdfUrl,
    this.pdfFileName,
    this.notificationStatus,
    this.notificationError,
    this.createdById,
    this.createdByName,
    this.reviewedById,
    this.reviewedByName,
    this.reviewedAt,
    this.reviewNote,
    this.aiRiskLevel,
    this.aiReportSummary,
    this.aiReportJson,
    this.aiGeneratedAt,
    this.transfers = const [],
    required this.createdAt,
    required this.updatedAt,
  });

  factory CloseModel.fromJson(Map<String, dynamic> json) {
    return CloseModel(
      id: json['id'],
      type: CloseTypeX.fromKey(json['type']),
      date: DateTime.parse(json['date']),
      status: json['status'],
      cash: (json['cash'] as num).toDouble(),
      transfer: (json['transfer'] as num).toDouble(),
      transferBank: (json['transferBank'] as String?)?.trim().isEmpty == true
          ? null
          : json['transferBank'] as String?,
      card: (json['card'] as num).toDouble(),
      otherIncome: (json['otherIncome'] as num?)?.toDouble() ?? 0,
      expenses: (json['expenses'] as num).toDouble(),
      cashDelivered: (json['cashDelivered'] as num).toDouble(),
      persistedTotalIncome: (json['totalIncome'] as num?)?.toDouble(),
      persistedNetTotal: (json['netTotal'] as num?)?.toDouble(),
      persistedDifference: (json['difference'] as num?)?.toDouble(),
      notes: json['notes'] as String?,
        evidenceUrl: json['evidenceUrl'] as String?,
        evidenceFileName: json['evidenceFileName'] as String?,
        evidenceStorageKey: json['evidenceStorageKey'] as String?,
        evidenceMimeType: json['evidenceMimeType'] as String?,
        expenseDetails: (json['expenseDetails'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .toList(),
      pdfUrl: json['pdfUrl'] as String?,
      pdfFileName: json['pdfFileName'] as String?,
      notificationStatus: json['notificationStatus'] as String?,
      notificationError: json['notificationError'] as String?,
      createdById: json['createdById'] as String?,
      createdByName: json['createdByName'] as String?,
      reviewedById: json['reviewedById'] as String?,
      reviewedByName: json['reviewedByName'] as String?,
      reviewedAt: json['reviewedAt'] == null
          ? null
          : DateTime.parse(json['reviewedAt']),
      reviewNote: json['reviewNote'] as String?,
      aiRiskLevel: json['aiRiskLevel'] as String?,
      aiReportSummary: json['aiReportSummary'] as String?,
      aiReportJson: (json['aiReportJson'] as Map?)?.cast<String, dynamic>(),
      aiGeneratedAt: json['aiGeneratedAt'] == null
          ? null
          : DateTime.parse(json['aiGeneratedAt']),
      transfers: (json['transfers'] as List? ?? const [])
          .whereType<Map>()
          .map(
            (row) => CloseTransferModel.fromJson(row.cast<String, dynamic>()),
          )
          .toList(),
      createdAt: DateTime.parse(json['createdAt']),
      updatedAt: DateTime.parse(json['updatedAt']),
    );
  }

  double get incomeTotal =>
      persistedTotalIncome ?? cash + transfer + card + otherIncome;
  double get netTotal => persistedNetTotal ?? incomeTotal - expenses;
  double get difference => persistedDifference ?? cash - cashDelivered;
  bool get isPending => status == 'pending';
  bool get isApproved => status == 'approved';
  bool get isRejected => status == 'rejected';
}

class CloseTransferModel {
  final String id;
  final String bankName;
  final double amount;
  final String? referenceNumber;
  final String? note;
  final List<CloseTransferVoucherModel> vouchers;

  const CloseTransferModel({
    required this.id,
    required this.bankName,
    required this.amount,
    this.referenceNumber,
    this.note,
    this.vouchers = const [],
  });

  factory CloseTransferModel.fromJson(Map<String, dynamic> json) {
    return CloseTransferModel(
      id: json['id'] as String? ?? '',
      bankName: json['bankName'] as String? ?? '',
      amount: (json['amount'] as num?)?.toDouble() ?? 0,
      referenceNumber: json['referenceNumber'] as String?,
      note: json['note'] as String?,
      vouchers: (json['vouchers'] as List? ?? const [])
          .whereType<Map>()
          .map(
            (row) =>
                CloseTransferVoucherModel.fromJson(row.cast<String, dynamic>()),
          )
          .toList(),
    );
  }
}

class CloseTransferVoucherModel {
  final String storageKey;
  final String fileUrl;
  final String fileName;
  final String mimeType;

  const CloseTransferVoucherModel({
    required this.storageKey,
    required this.fileUrl,
    required this.fileName,
    required this.mimeType,
  });

  factory CloseTransferVoucherModel.fromJson(Map<String, dynamic> json) {
    return CloseTransferVoucherModel(
      storageKey: json['storageKey'] as String? ?? '',
      fileUrl: json['fileUrl'] as String? ?? '',
      fileName: json['fileName'] as String? ?? '',
      mimeType: json['mimeType'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'storageKey': storageKey,
    'fileUrl': fileUrl,
    'fileName': fileName,
    'mimeType': mimeType,
  };
}
