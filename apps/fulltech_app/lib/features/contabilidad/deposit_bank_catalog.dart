class DepositBankAccountOption {
  const DepositBankAccountOption({
    required this.id,
    required this.label,
    this.accountNumber,
  });

  final String id;
  final String label;
  final String? accountNumber;
}

class DepositBankOption {
  const DepositBankOption({
    required this.id,
    required this.label,
    required this.accounts,
  });

  final String id;
  final String label;
  final List<DepositBankAccountOption> accounts;
}

const depositBankCatalog = <DepositBankOption>[
  DepositBankOption(
    id: 'popular',
    label: 'Banco Popular',
    accounts: [
      DepositBankAccountOption(
        id: 'popular_operativa',
        label: 'Cuenta operativa principal',
      ),
      DepositBankAccountOption(
        id: 'popular_recaudos',
        label: 'Cuenta recaudos',
      ),
    ],
  ),
  DepositBankOption(
    id: 'banreservas',
    label: 'Banreservas',
    accounts: [
      DepositBankAccountOption(
        id: 'banreservas_general',
        label: 'Cuenta general',
      ),
    ],
  ),
  DepositBankOption(
    id: 'bhd',
    label: 'BHD',
    accounts: [
      DepositBankAccountOption(
        id: 'bhd_principal',
        label: 'Cuenta principal',
      ),
    ],
  ),
];