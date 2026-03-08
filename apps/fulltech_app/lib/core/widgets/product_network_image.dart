import 'dart:async';

import 'package:flutter/material.dart';

import '../utils/product_image_url.dart';

class ProductNetworkImage extends StatefulWidget {
  final String imageUrl;
  final String productId;
  final String productName;
  final String? originalUrl;
  final BoxFit fit;
  final Widget fallback;
  final Widget? loading;
  final int maxRetries;

  const ProductNetworkImage({
    super.key,
    required this.imageUrl,
    required this.productId,
    required this.productName,
    required this.originalUrl,
    required this.fallback,
    this.fit = BoxFit.cover,
    this.loading,
    this.maxRetries = 3,
  });

  @override
  State<ProductNetworkImage> createState() => _ProductNetworkImageState();
}

class _ProductNetworkImageState extends State<ProductNetworkImage> {
  static const _retryDelays = <Duration>[
    Duration(seconds: 2),
    Duration(seconds: 5),
    Duration(seconds: 12),
  ];

  Timer? _retryTimer;
  int _retryAttempt = 0;
  bool _retryScheduled = false;

  @override
  void didUpdateWidget(covariant ProductNetworkImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl) {
      _retryTimer?.cancel();
      _retryAttempt = 0;
      _retryScheduled = false;
    }
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final imageUrl = _buildAttemptUrl(widget.imageUrl, _retryAttempt);

    return Image.network(
      imageUrl,
      key: ValueKey(imageUrl),
      fit: widget.fit,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return widget.loading ?? widget.fallback;
      },
      errorBuilder: (context, error, stackTrace) {
        if (_retryAttempt < widget.maxRetries) {
          _scheduleRetry();
          return widget.loading ?? widget.fallback;
        }

        debugLogProductImageFailure(
          productId: widget.productId,
          productName: widget.productName,
          originalUrl: widget.originalUrl,
          attemptedUrl: imageUrl,
          error: error,
        );
        return widget.fallback;
      },
    );
  }

  void _scheduleRetry() {
    if (_retryScheduled) return;
    _retryScheduled = true;
    final delay =
        _retryDelays[(_retryAttempt).clamp(0, _retryDelays.length - 1)];
    _retryTimer?.cancel();
    _retryTimer = Timer(delay, () {
      if (!mounted) return;
      setState(() {
        _retryAttempt += 1;
        _retryScheduled = false;
      });
    });
  }

  String _buildAttemptUrl(String url, int attempt) {
    if (attempt <= 0) return url;
    final uri = Uri.tryParse(url);
    if (uri == null) {
      final separator = url.contains('?') ? '&' : '?';
      return '$url${separator}rt=$attempt';
    }
    final queryParameters = <String, List<String>>{
      for (final entry in uri.queryParametersAll.entries)
        entry.key: List<String>.from(entry.value),
    };
    queryParameters['rt'] = [
      '${DateTime.now().millisecondsSinceEpoch}-$attempt',
    ];
    final query = queryParameters.entries
        .expand(
          (entry) => entry.value.map(
            (value) =>
                '${Uri.encodeQueryComponent(entry.key)}=${Uri.encodeQueryComponent(value)}',
          ),
        )
        .join('&');
    return uri.replace(query: query).toString();
  }
}
