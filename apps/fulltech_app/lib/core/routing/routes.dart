class Routes {
  static const splash = '/splash';
  static const login = '/login';
  static const register = '/register';
  static const home = '/home';
  static const user = '/user';
  static const profile = '/profile';
  static const users = '/users';
  static const userDetail = '/users/:id';
  static const ponche = '/ponche';
  static const operaciones = '/operaciones';
  static const catalogo = '/catalogo';
  static const contabilidad = '/contabilidad';
  static const contabilidadCierresDiarios = '/contabilidad/cierres-diarios';
  static const contabilidadFacturaFiscal = '/contabilidad/factura-fiscal';
  static const contabilidadPagosPendientes = '/contabilidad/pagos-pendientes';
  static const clientes = '/clientes';
  static const ventas = '/ventas';
  static const cotizaciones = '/cotizaciones';
  static const cotizacionesHistorial = '/cotizaciones/historial';
  static const registrarVenta = '/ventas/nueva';
  static const clienteNuevo = '/clientes/nuevo';
  static const clienteDetalle = '/clientes/:id';
  static const clienteEditar = '/clientes/:id/editar';
  static const nomina = '/nomina';
  static const misPagos = '/mis-pagos';
  static const configuracion = '/configuracion';

  static String clienteDetail(String id) => '/clientes/$id';
  static String clienteEdit(String id) => '/clientes/$id/editar';
}
