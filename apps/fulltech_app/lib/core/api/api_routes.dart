/// Centraliza rutas de API para fácil ajuste
class ApiRoutes {
  static const login = '/auth/login';
  static const refresh = '/auth/refresh';
  static const me = '/auth/me';
  static const settings = '/settings';

  // Usuarios
  static const users = '/users';
    static const usersMe = '/users/me';
  static String userDetail(String id) => '/users/$id';
  static String updateUser(String id) => '/users/$id';
  static String deleteUser(String id) => '/users/$id';
  static String blockUser(String id) => '/users/$id/block';
  static String unblockUser(String id) => '/users/$id/unblock';
  static const usersUpload = '/users/upload';

  // Ponche
  static const punch = '/punch';
  static const punchMe = '/punch/me';
  static const punchAdmin = '/admin/punch';
  static const punchAttendanceSummary = '/admin/attendance/summary';
  static String punchAttendanceUser(String id) => '/admin/attendance/user/$id';
  static const adminSalesSummary = '/admin/sales/summary';
  static const adminPanelOverview = '/admin/panel/overview';
  static const adminPanelAiInsights = '/admin/panel/ai-insights';

  // Ubicación
  static const locationsReport = '/locations';
  static const adminLocationsLatest = '/admin/locations/latest';

  // Contabilidad
  static const contabilidadCloses = '/contabilidad/closes';
  static String contabilidadCloseDetail(String id) =>
      '/contabilidad/closes/$id';
  static const contabilidadDepositOrders = '/contabilidad/deposit-orders';
  static String contabilidadDepositOrderDetail(String id) =>
      '/contabilidad/deposit-orders/$id';
  static const contabilidadFiscalInvoices = '/contabilidad/fiscal-invoices';
  static String contabilidadFiscalInvoiceDetail(String id) =>
      '/contabilidad/fiscal-invoices/$id';
  static const contabilidadFiscalInvoicesUpload =
      '/contabilidad/fiscal-invoices/upload';
  static const contabilidadPayableServices = '/contabilidad/payables/services';
  static String contabilidadPayableServiceDetail(String id) =>
      '/contabilidad/payables/services/$id';
  static String contabilidadPayableServicePayments(String id) =>
      '/contabilidad/payables/services/$id/payments';
  static const contabilidadPayablePayments = '/contabilidad/payables/payments';

  // Clientes
  static const clients = '/clients';
  static String clientDetail(String id) => '/clients/$id';

  // Productos
  static const products = '/products';
  static const productsUpload = '/products/upload';
  static String productDetail(String id) => '/products/$id';
  static String updateProduct(String id) => '/products/$id';
  static String deleteProduct(String id) => '/products/$id';

  // Ventas
  static const sales = '/sales';
  static const salesSummary = '/sales/summary';
  static String saleDetail(String id) => '/sales/$id';

  // Operaciones
  static const services = '/services';
    static const technicians = '/technicians';
  static String serviceDetail(String id) => '/services/$id';
  static String serviceStatus(String id) => '/services/$id/status';
  static String serviceSchedule(String id) => '/services/$id/schedule';
  static String serviceAssign(String id) => '/services/$id/assign';
  static String serviceUpdate(String id) => '/services/$id/update';
  static String serviceFiles(String id) => '/services/$id/files';
  static String serviceWarranty(String id) => '/services/$id/warranty';
  static String customerServices(String id) => '/customers/$id/services';
  static const operationsDashboard = '/dashboard/operations';

  // Nómina
  static const payrollPeriods = '/payroll/periods';
  static const payrollPeriodEnsureCurrentOpen =
      '/payroll/periods/ensure-current-open';
  static const payrollPeriodOpenOverlap = '/payroll/periods/open-overlap';
  static String payrollPeriodDetail(String id) => '/payroll/periods/$id';
  static String payrollPeriodClose(String id) => '/payroll/periods/$id/close';
  static String payrollPeriodNextOpen(String id) =>
      '/payroll/periods/$id/next-open';
  static String payrollPeriodTotalAll(String id) =>
      '/payroll/periods/$id/total-all';

  static const payrollEmployees = '/payroll/employees';
  static const payrollEmployeeUpsert = '/payroll/employees/upsert';
  static String payrollEmployeeDetail(String id) => '/payroll/employees/$id';

  static const payrollConfig = '/payroll/config';
  static const payrollConfigUpsert = '/payroll/config/upsert';

  static const payrollEntries = '/payroll/entries';
  static String payrollEntryDetail(String id) => '/payroll/entries/$id';

  static const payrollTotals = '/payroll/totals';
  static const payrollMyHistory = '/payroll/my-history';
  static const payrollMyGoal = '/payroll/my-goal';

  // Cotizaciones (nube)
  static const cotizaciones = '/cotizaciones';
  static String cotizacionDetail(String id) => '/cotizaciones/$id';
}
