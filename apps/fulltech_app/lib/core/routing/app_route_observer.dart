import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final appRouteObserverProvider = Provider<RouteObserver<ModalRoute<dynamic>>>(
  (ref) => RouteObserver<ModalRoute<dynamic>>(),
);
