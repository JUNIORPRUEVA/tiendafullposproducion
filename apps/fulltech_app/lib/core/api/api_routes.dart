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
  static const usersMeWorkContractSign = '/users/me/work-contract/sign';
  static String userWorkContractAiEdit(String id) =>
      '/users/$id/work-contract/ai-edit';

  // Ponche
  static const punch = '/punch';
  static const punchMe = '/punch/me';
  static const punchMeAttendance = '/punch/me/attendance';
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
  static String clientProfile(String id) => '/clients/$id/profile';
  static String clientTimeline(String id) => '/clients/$id/timeline';

  // Productos
  static const products = '/products';
  static const catalogProducts = '/catalog/products';
  static const productsUpload = '/products/upload';
  static String productDetail(String id) => '/products/$id';
  static String updateProduct(String id) => '/products/$id';
  static String deleteProduct(String id) => '/products/$id';

  // Ventas
  static const sales = '/sales';
  static const salesSummary = '/sales/summary';
  static String saleDetail(String id) => '/sales/$id';

  static const services = '/services';
  static const technicians = '/technicians';
  static String serviceDetail(String id) => '/services/$id';
  static String orderDetail(String id) => '/ordenes/$id';
  static String serviceStatus(String id) => '/services/$id/status';
  static String serviceOrderState(String id) => '/services/$id/order-state';
  static String servicePhase(String id) => '/services/$id/phase';
  static String serviceAdminPhase(String id) => '/services/$id/admin-phase';
  static String serviceAdminStatus(String id) => '/services/$id/admin-status';
  static String servicePhases(String id) => '/services/$id/phases';
  static String serviceSchedule(String id) => '/services/$id/schedule';
  static String serviceAssign(String id) => '/services/$id/assign';
  static String serviceUpdate(String id) => '/services/$id/update';
  static String serviceFiles(String id) => '/services/$id/files';
  static String serviceSignature(String id) => '/services/$id/signature';
  static String serviceExecutionReport(String id) =>
      '/services/$id/execution-report';
  static String serviceChecklists(String id) => '/services/$id/checklists';
  static String serviceExecutionChanges(String id) =>
      '/services/$id/execution-report/changes';
  static String serviceExecutionChangeDelete(String id, String changeId) =>
      '/services/$id/execution-report/changes/$changeId';
  static const checklistCategories = '/checklist/categories';
  static const checklistPhases = '/checklist/phases';
  static const checklistTemplates = '/checklist/templates';
  static const checklistTemplate = '/checklist/template';
  static const checklistItem = '/checklist/item';
  static String checklistItemCheck(String id) => '/checklist/item/$id/check';
  static const warrantyConfigs = '/warranty-configs';
  static String warrantyConfigDetail(String id) => '/warranty-configs/$id';
  static String warrantyConfigActive(String id) =>
      '/warranty-configs/$id/active';

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
  static const payrollImportFuel = '/payroll/import/fuel';

  static const payrollTotals = '/payroll/totals';
  static const payrollMyHistory = '/payroll/my-history';
  static const payrollMyGoal = '/payroll/my-goal';

  // Manual interno
  static const companyManualEntries = '/company-manual';
  static const companyManualSummary = '/company-manual/summary';
  static String companyManualEntryDetail(String id) => '/company-manual/$id';

  // Cotizaciones (nube)
  static const cotizaciones = '/cotizaciones';
  static String cotizacionDetail(String id) => '/cotizaciones/$id';
  static const cotizacionAiAnalyze = '/cotizaciones/ai/analyze';
  static const cotizacionAiChat = '/cotizaciones/ai/chat';

    // Service orders
    static const serviceOrders = '/service-orders';
    static String serviceOrderDetail(String id) => '/service-orders/$id';
    static String serviceOrderStatus(String id) => '/service-orders/$id/status';
    static String serviceOrderEvidences(String id) =>
            '/service-orders/$id/evidences';
    static String serviceOrderReport(String id) => '/service-orders/$id/report';
    static String serviceOrderClone(String id) => '/service-orders/$id/clone';

  // Asistente IA (global)
  static const aiChat = '/ai/chat';

  // Storage (R2 presigned uploads)
  static const storagePresign = '/storage/presign';
  static const storageConfirm = '/storage/confirm';
  static String storageByService(String serviceId) =>
      '/storage/service/$serviceId';
  static String storageItem(String id) => '/storage/$id';

  // Horarios (Work Scheduling)
  static const workSchedulingEmployees = '/work-scheduling/employees';
  static String workSchedulingEmployee(String id) =>
      '/work-scheduling/employees/$id';

  static const workSchedulingProfiles = '/work-scheduling/profiles';
  static const workSchedulingProfilesUpsert =
      '/work-scheduling/profiles/upsert';

  static const workSchedulingCoverageRules = '/work-scheduling/coverage-rules';
  static const workSchedulingCoverageRulesUpsert =
      '/work-scheduling/coverage-rules/upsert';

  static const workSchedulingExceptions = '/work-scheduling/exceptions';
  static String workSchedulingException(String id) =>
      '/work-scheduling/exceptions/$id';
  static String workSchedulingExceptionDelete(String id) =>
      '/work-scheduling/exceptions/$id/delete';

  static const workSchedulingWeeksGenerate = '/work-scheduling/weeks/generate';
  static String workSchedulingWeek(String weekStartDate) =>
      '/work-scheduling/weeks/$weekStartDate';

  static const workSchedulingManualMoveDayOff =
      '/work-scheduling/manual/move-day-off';
  static const workSchedulingManualSwapDayOff =
      '/work-scheduling/manual/swap-day-off';

  static const workSchedulingAudit = '/work-scheduling/audit';
  static const workSchedulingReportMostChanges =
      '/work-scheduling/reports/most-changes';
  static const workSchedulingReportLowCoverage =
      '/work-scheduling/reports/low-coverage';
}
